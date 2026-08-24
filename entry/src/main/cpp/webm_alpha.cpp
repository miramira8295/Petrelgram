#include "webm_alpha.h"

#include <algorithm>
#include <functional>
#include <hilog/log.h>

#include <vpx/vp8dx.h>
#include <vpx/vpx_codec.h>
#include <vpx/vpx_decoder.h>
#include <vpx/vpx_image.h>

namespace webm_alpha {
namespace {

// LOG_DOMAIN / LOG_TAG 是 hilog 的宏名，不能拿来当变量。
constexpr unsigned int kLogDomain = 0x0000;
constexpr const char *kLogTag = "WebmAlpha";

// 解码线程数。贴纸上限 512px/30fps/3s，单线程也够；给 2 是让首帧快一点，
// 再多只会在这类小分辨率上被线程同步吃掉。
constexpr int kDecodeThreads = 2;

// 再保守一层：ArkTS 侧已经按预算裁过尺寸，这里只防"参数被算错"。
constexpr size_t kMaxTotalBytes = 24u * 1024u * 1024u;
constexpr int32_t kMaxDim = 4096;

// 一帧解出来的样子。
//
// **三个平面各带各的行距**，而不是"一个 base 加一个 stride"：libvpx 出的是
// I420（三个独立平面），不是系统 AVCodec 那种 NV12（UV 交错在 Y 后面）。旧代码
// 是照 NV12 写的——UV 用 base + stride*sliceH 定位、pixelStride 取 2。换到 libvpx
// 之后那套定位全错，所以这里跟着改成平面数组。
struct FrameInfo {
    const uint8_t *plane[3];
    int32_t stride[3];
    int32_t picW;
    int32_t picH;
    bool rangeFull;
};

using FrameSink = std::function<void(const FrameInfo &)>;

// vpx_codec_ctx_t 的 RAII 壳。中途任何一步失败都要 destroy，否则解码器内部的
// 帧缓冲池会漏——一张贴纸几十帧，漏几次就是几十 MB。
struct VpxDecoder {
    vpx_codec_ctx_t ctx{};
    bool inited = false;

    bool Init() {
        vpx_codec_dec_cfg_t cfg{};
        cfg.threads = kDecodeThreads;
        cfg.w = 0; // 0 = 由码流自报，别拿外部尺寸去框它
        cfg.h = 0;
        const vpx_codec_err_t err = vpx_codec_dec_init(&ctx, vpx_codec_vp9_dx(), &cfg, 0);
        inited = err == VPX_CODEC_OK;
        if (!inited) {
            OH_LOG_Print(LOG_APP, LOG_ERROR, kLogDomain, kLogTag,
                         "vpx_codec_dec_init failed: %{public}s", vpx_codec_err_to_string(err));
        }
        return inited;
    }

    ~VpxDecoder() {
        if (inited) {
            vpx_codec_destroy(&ctx);
        }
    }
};

// 解一路 VP9 码流，每解出一帧就交给 sink。
//
// **每一包都要喂进去**，哪怕调用方只想留其中几帧：VP9 是帧间预测的，跳过一个包
// 后面全错。降帧只发生在 sink 那一侧（少留几帧省内存），解码时间省不掉——这正是
// 预算里优先降分辨率、其次才降帧的原因。
//
// 比起原来那套系统 AVCodec 的同步轮询（喂 buffer / 查 buffer / 数 stall 轮次 /
// 处理 EOS），libvpx 是纯同步的：decode 一次，get_frame 把这一包产出的帧全取走。
// 没有队列、没有超时、没有硬件挂死，那 100 多行连同它们的兜底一起删掉了。
bool DecodeStream(const std::vector<Packet> &packets, const FrameSink &sink) {
    VpxDecoder dec;
    if (!dec.Init()) {
        return false;
    }
    for (const Packet &pkt : packets) {
        if (pkt.empty()) {
            // 空包不是错误（容器里可能有占位），但也没什么可解的。
            continue;
        }
        const vpx_codec_err_t err = vpx_codec_decode(&dec.ctx, pkt.data(),
                                                    static_cast<unsigned int>(pkt.size()),
                                                    nullptr, 0);
        if (err != VPX_CODEC_OK) {
            OH_LOG_Print(LOG_APP, LOG_ERROR, kLogDomain, kLogTag,
                         "vpx_codec_decode failed: %{public}s", vpx_codec_err_to_string(err));
            return false;
        }
        vpx_codec_iter_t iter = nullptr;
        const vpx_image_t *img = nullptr;
        while ((img = vpx_codec_get_frame(&dec.ctx, &iter)) != nullptr) {
            // **格式必须核**。贴纸是 8bit I420；真拿到别的（高位深、I422、
            // I444）而照 I420 去读，出来的是错位的花屏而不是报错——那种失败
            // 极难从现象追回原因。宁可整条回退到 ijkplayer。
            if (img->fmt != VPX_IMG_FMT_I420) {
                OH_LOG_Print(LOG_APP, LOG_ERROR, kLogDomain, kLogTag,
                             "unexpected vpx img fmt: %{public}d", static_cast<int>(img->fmt));
                return false;
            }
            FrameInfo info{};
            info.plane[0] = img->planes[VPX_PLANE_Y];
            info.plane[1] = img->planes[VPX_PLANE_U];
            info.plane[2] = img->planes[VPX_PLANE_V];
            info.stride[0] = img->stride[VPX_PLANE_Y];
            info.stride[1] = img->stride[VPX_PLANE_U];
            info.stride[2] = img->stride[VPX_PLANE_V];
            // **用 d_w/d_h，不用 w/h。** libvpx 1.17 把 w/h 的语义从"stride 与
            // 对齐高度"改成了"真实宽高"（CHANGELOG 的 Upgrading 条目）；d_w/d_h
            // 一直是显示尺寸，两版一致。用 d_w/d_h 就不必跟着版本改口径——按旧
            // 语义写的代码升级后会静默地把右边缘写成垃圾，还不报错。
            info.picW = static_cast<int32_t>(img->d_w);
            info.picH = static_cast<int32_t>(img->d_h);
            info.rangeFull = img->range == VPX_CR_FULL_RANGE;
            if (info.plane[0] == nullptr || info.picW <= 0 || info.picH <= 0) {
                return false;
            }
            sink(info);
        }
    }
    return true;
}

// 面积平均缩放。这条链路只会缩不会放（目标尺寸由预算算出，恒 ≤ 源），
// 双线性在 2:1 以上会漏采样，面积平均是更对的选择，代价也只是一次累加。
void ResizePlane(const uint8_t *src, int32_t srcStride, int32_t srcPixelStride, int32_t srcW,
                 int32_t srcH, uint8_t *dst, int32_t dstW, int32_t dstH) {
    for (int32_t y = 0; y < dstH; ++y) {
        const int32_t y0 = y * srcH / dstH;
        const int32_t y1 = std::max(y0 + 1, (y + 1) * srcH / dstH);
        for (int32_t x = 0; x < dstW; ++x) {
            const int32_t x0 = x * srcW / dstW;
            const int32_t x1 = std::max(x0 + 1, (x + 1) * srcW / dstW);
            uint32_t sum = 0;
            uint32_t n = 0;
            for (int32_t sy = y0; sy < y1 && sy < srcH; ++sy) {
                const uint8_t *row = src + static_cast<size_t>(sy) * srcStride;
                for (int32_t sx = x0; sx < x1 && sx < srcW; ++sx) {
                    sum += row[static_cast<size_t>(sx) * srcPixelStride];
                    ++n;
                }
            }
            dst[static_cast<size_t>(y) * dstW + x] = n == 0 ? 0 : static_cast<uint8_t>(sum / n);
        }
    }
}

inline uint8_t Clamp255(int32_t v) {
    return static_cast<uint8_t>(v < 0 ? 0 : (v > 255 ? 255 : v));
}

// 有限范围（16..235）拉回 0..255。alpha 那一路也要做：那一路是把 Y 直接当 A 用，
// 若编码器写的是 limited，全透明区就会停在 16 而不是 0，表现成一圈灰边。按流
// 自己报的 range 展开才是对的。
inline uint8_t ExpandRange(uint8_t v, bool full) {
    if (full) {
        return v;
    }
    return Clamp255((static_cast<int32_t>(v) - 16) * 255 / 219);
}

} // namespace

// 恒为 true：VP9 解码器是随包带的（third_party/libvpx-ohos），不再问设备。
//
// **这个函数留着是有代价的，但值得。** 它现在没有任何判断，看着像废话——可它
// 是调用方那条"探测不到就回退 ijkplayer"分支的开关。留着，是因为将来若要按机型
// 或按内存关掉软解，这里是唯一的开关点；删掉就得把回退逻辑重新长回来。
//
// 历史：这里原本枚举系统 AVCodec 的 VP9 能力。2026-08-20 在一台海思设备上枚举
// 到全部 19 个视频解码器都没有 VP9/VP8（软硬解都没有），整条链路一次都没跑起来。
// 换成随包自带的 libvpx 之后，设备有没有 VP9 与本功能无关了。
bool Vp9DecoderAvailable() {
    return true;
}

bool DecodeAlphaSequence(const std::vector<Packet> &colorPackets,
                         const std::vector<Packet> &alphaPackets, int32_t srcW, int32_t srcH,
                         int32_t dstW, int32_t dstH, int32_t frameStep,
                         std::vector<RgbaFrame> &out) {
    out.clear();
    if (colorPackets.empty() || colorPackets.size() != alphaPackets.size() || frameStep <= 0) {
        return false;
    }
    if (srcW <= 0 || srcH <= 0 || dstW <= 0 || dstH <= 0 || srcW > kMaxDim || srcH > kMaxDim ||
        dstW > srcW || dstH > srcH) {
        return false;
    }
    const size_t step = static_cast<size_t>(frameStep);
    const size_t keepCount = (colorPackets.size() + step - 1) / step;
    const size_t frameBytes = static_cast<size_t>(dstW) * dstH * 4;
    if (frameBytes * keepCount > kMaxTotalBytes) {
        return false;
    }

    // 两路先后解，不并行：先把 alpha 存成 dstW*dstH 的单字节平面，额外内存只有
    // 最终 RGBA 的 1/4。并行两个解码器实例省不到多少时间，却让内存翻倍。
    const size_t planeBytes = static_cast<size_t>(dstW) * dstH;
    std::vector<std::vector<uint8_t>> alphaPlanes;
    alphaPlanes.reserve(keepCount);
    bool alphaFull = false;
    size_t alphaSeen = 0;
    const bool alphaOk = DecodeStream(alphaPackets, [&](const FrameInfo &f) {
        const size_t seen = alphaSeen++;
        if (seen % step != 0 || alphaPlanes.size() >= keepCount) {
            return;
        }
        alphaFull = f.rangeFull;
        std::vector<uint8_t> plane(planeBytes, 0);
        // alpha 那一路只有 Y 有意义——它就是被当灰度图编码的透明度。
        ResizePlane(f.plane[0], f.stride[0], 1, std::min(f.picW, srcW), std::min(f.picH, srcH),
                    plane.data(), dstW, dstH);
        alphaPlanes.push_back(std::move(plane));
    });
    if (!alphaOk || alphaPlanes.empty()) {
        return false;
    }

    std::vector<uint8_t> luma(planeBytes, 0);
    std::vector<uint8_t> chromaU(planeBytes, 0);
    std::vector<uint8_t> chromaV(planeBytes, 0);
    size_t colorSeen = 0;
    const bool colorOk = DecodeStream(colorPackets, [&](const FrameInfo &f) {
        const size_t seen = colorSeen++;
        // 两路是同一段时间轴、同样的帧数，按解出的序号配对；留哪几帧也用
        // 同一个 step，所以 index 一定对得上。
        const size_t index = seen / step;
        if (seen % step != 0 || index >= alphaPlanes.size()) {
            return;
        }
        const int32_t picW = std::min(f.picW, srcW);
        const int32_t picH = std::min(f.picH, srcH);
        // I420：三个平面各自连续，pixelStride 一律是 1。（NV12 那套 UV 交错、
        // pixelStride=2 的写法只适用于系统 AVCodec，换 libvpx 后不再成立。）
        ResizePlane(f.plane[0], f.stride[0], 1, picW, picH, luma.data(), dstW, dstH);
        ResizePlane(f.plane[1], f.stride[1], 1, picW / 2, picH / 2, chromaU.data(), dstW, dstH);
        ResizePlane(f.plane[2], f.stride[2], 1, picW / 2, picH / 2, chromaV.data(), dstW, dstH);
        const std::vector<uint8_t> &alpha = alphaPlanes[index];
        RgbaFrame frame(frameBytes, 0);
        for (size_t p = 0; p < planeBytes; ++p) {
            // BT.601。VP9 贴纸不带色彩描述，ffmpeg 与各家播放器对这类小尺寸
            // 内容的默认也是 601，跟着走才不会和缩略图对不上色。
            const int32_t y = f.rangeFull ? luma[p] : (luma[p] - 16) * 255 / 219;
            const int32_t u = static_cast<int32_t>(chromaU[p]) - 128;
            const int32_t v = static_cast<int32_t>(chromaV[p]) - 128;
            frame[p * 4 + 0] = Clamp255(y + (91881 * v >> 16));
            frame[p * 4 + 1] = Clamp255(y - ((22554 * u + 46802 * v) >> 16));
            frame[p * 4 + 2] = Clamp255(y + (116130 * u >> 16));
            frame[p * 4 + 3] = ExpandRange(alpha[p], alphaFull);
        }
        out.push_back(std::move(frame));
    });
    if (!colorOk || out.empty()) {
        out.clear();
        return false;
    }
    return true;
}

} // namespace webm_alpha
