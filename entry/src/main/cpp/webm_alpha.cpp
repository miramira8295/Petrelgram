#include "webm_alpha.h"

#include <algorithm>
#include <functional>
#include <map>
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

// 解码线程数。贴纸上限 512px/30fps/3s，单线程足够。原来给 2 是为了让整段解码
// 早点结束；边解边播之后几张贴纸在调度线程上轮流各推进一包，每个解码器再开
// 工作线程只会互相抢 CPU（同时最多几张 × 两路解码器）。
constexpr int kDecodeThreads = 1;

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

// 喂一包，把这一包解出的帧逐一交给 sink。
//
// 比起原来那套系统 AVCodec 的同步轮询（喂 buffer / 查 buffer / 数 stall 轮次 /
// 处理 EOS），libvpx 是纯同步的：decode 一次，get_frame 把这一包产出的帧全取走。
// 没有队列、没有超时、没有硬件挂死。
bool DecodePacket(VpxDecoder &dec, const Packet &pkt, const FrameSink &sink) {
    if (pkt.empty()) {
        // 空包不是错误（容器里可能有占位），但也没什么可解的。
        return true;
    }
    const vpx_codec_err_t err = vpx_codec_decode(&dec.ctx, pkt.data(),
                                                static_cast<unsigned int>(pkt.size()), nullptr, 0);
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
        // 一直是显示尺寸，两版一致。
        info.picW = static_cast<int32_t>(img->d_w);
        info.picH = static_cast<int32_t>(img->d_h);
        info.rangeFull = img->range == VPX_CR_FULL_RANGE;
        if (info.plane[0] == nullptr || info.picW <= 0 || info.picH <= 0) {
            return false;
        }
        sink(info);
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

struct AlphaSequenceDecoder::Impl {
    std::vector<Packet> color;
    std::vector<Packet> alpha;
    int32_t srcW = 0;
    int32_t srcH = 0;
    int32_t dstW = 0;
    int32_t dstH = 0;
    size_t step = 1;
    size_t keepCount = 0;
    bool opaque = false;
    VpxDecoder colorDec;
    VpxDecoder alphaDec;
    size_t next = 0;
    size_t colorSeen = 0;
    size_t alphaSeen = 0;
    bool alphaFull = false;
    // 已解出、还没配上颜色帧的 alpha 平面，按「保留序号」存。两路是同一段时间轴、
    // 同样的帧数，按解出的序号配对；用 map 而不是队列，是为了某一路偶尔少出一帧时
    // 只丢那一帧，不让后面整段错位。
    std::map<size_t, std::vector<uint8_t>> alphaPlanes;
    std::vector<uint8_t> luma;
    std::vector<uint8_t> chromaU;
    std::vector<uint8_t> chromaV;

    void OnAlpha(const FrameInfo &f) {
        const size_t seen = alphaSeen++;
        if (seen % step != 0 || seen / step >= keepCount) {
            return;
        }
        alphaFull = f.rangeFull;
        const size_t planeBytes = static_cast<size_t>(dstW) * dstH;
        std::vector<uint8_t> plane(planeBytes, 0);
        // alpha 那一路只有 Y 有意义——它就是被当灰度图编码的透明度。
        ResizePlane(f.plane[0], f.stride[0], 1, std::min(f.picW, srcW), std::min(f.picH, srcH),
                    plane.data(), dstW, dstH);
        alphaPlanes[seen / step] = std::move(plane);
    }

    void OnColor(const FrameInfo &f, std::vector<RgbaFrame> &out) {
        const size_t seen = colorSeen++;
        const size_t index = seen / step;
        if (seen % step != 0 || index >= keepCount) {
            return;
        }
        const std::vector<uint8_t> *alphaPlane = nullptr;
        if (!opaque) {
            // 比当前序号还旧的 alpha 再也配不上了，顺手丢掉。
            alphaPlanes.erase(alphaPlanes.begin(), alphaPlanes.lower_bound(index));
            auto it = alphaPlanes.find(index);
            if (it == alphaPlanes.end()) {
                return;   // 这一帧缺 alpha：丢这一帧（同旧实现），不让后面错位
            }
            alphaPlane = &it->second;
        }
        const int32_t picW = std::min(f.picW, srcW);
        const int32_t picH = std::min(f.picH, srcH);
        const size_t planeBytes = static_cast<size_t>(dstW) * dstH;
        // I420：三个平面各自连续，pixelStride 一律是 1。
        ResizePlane(f.plane[0], f.stride[0], 1, picW, picH, luma.data(), dstW, dstH);
        ResizePlane(f.plane[1], f.stride[1], 1, picW / 2, picH / 2, chromaU.data(), dstW, dstH);
        ResizePlane(f.plane[2], f.stride[2], 1, picW / 2, picH / 2, chromaV.data(), dstW, dstH);
        RgbaFrame frame(planeBytes * 4, 0);
        for (size_t p = 0; p < planeBytes; ++p) {
            // BT.601。VP9 贴纸不带色彩描述，ffmpeg 与各家播放器对这类小尺寸
            // 内容的默认也是 601，跟着走才不会和缩略图对不上色。
            const int32_t y = f.rangeFull ? luma[p] : (luma[p] - 16) * 255 / 219;
            const int32_t u = static_cast<int32_t>(chromaU[p]) - 128;
            const int32_t v = static_cast<int32_t>(chromaV[p]) - 128;
            frame[p * 4 + 0] = Clamp255(y + (91881 * v >> 16));
            frame[p * 4 + 1] = Clamp255(y - ((22554 * u + 46802 * v) >> 16));
            frame[p * 4 + 2] = Clamp255(y + (116130 * u >> 16));
            frame[p * 4 + 3] = alphaPlane == nullptr ? 255 : ExpandRange((*alphaPlane)[p], alphaFull);
        }
        if (alphaPlane != nullptr) {
            alphaPlanes.erase(index);
        }
        out.push_back(std::move(frame));
    }
};

AlphaSequenceDecoder::AlphaSequenceDecoder() : impl_(new Impl()) {}

AlphaSequenceDecoder::~AlphaSequenceDecoder() {
    delete impl_;
}

bool AlphaSequenceDecoder::Init(std::vector<Packet> colorPackets, std::vector<Packet> alphaPackets,
                                int32_t srcW, int32_t srcH, int32_t dstW, int32_t dstH,
                                int32_t frameStep) {
    Impl &d = *impl_;
    // alphaPackets 为空 = 这段贴纸本来就不透明（普通 VP9，没有 BlockAdditional
    // 那一路）。走同一条解码链路，只是 alpha 平面恒为 255——这样"贴纸一律解成
    // 帧序列"，不必为不透明的那些再养一个播放器实例。
    d.opaque = alphaPackets.empty();
    if (colorPackets.empty() || frameStep <= 0) {
        return false;
    }
    if (!d.opaque && colorPackets.size() != alphaPackets.size()) {
        return false;
    }
    if (srcW <= 0 || srcH <= 0 || dstW <= 0 || dstH <= 0 || srcW > kMaxDim || srcH > kMaxDim ||
        dstW > srcW || dstH > srcH) {
        return false;
    }
    d.step = static_cast<size_t>(frameStep);
    d.keepCount = (colorPackets.size() + d.step - 1) / d.step;
    const size_t planeBytes = static_cast<size_t>(dstW) * dstH;
    if (planeBytes * 4 * d.keepCount > kMaxTotalBytes) {
        return false;
    }
    d.color = std::move(colorPackets);
    d.alpha = std::move(alphaPackets);
    d.srcW = srcW;
    d.srcH = srcH;
    d.dstW = dstW;
    d.dstH = dstH;
    d.luma.assign(planeBytes, 0);
    d.chromaU.assign(planeBytes, 0);
    d.chromaV.assign(planeBytes, 0);
    return d.colorDec.Init() && (d.opaque || d.alphaDec.Init());
}

bool AlphaSequenceDecoder::Step(std::vector<RgbaFrame> &out) {
    Impl &d = *impl_;
    if (d.next >= d.color.size()) {
        return true;
    }
    const size_t i = d.next++;
    // 同一包的 alpha 先解：颜色帧出来时它那一层透明度已经在手。
    if (!d.opaque &&
        !DecodePacket(d.alphaDec, d.alpha[i], [&](const FrameInfo &f) { d.OnAlpha(f); })) {
        return false;
    }
    if (!DecodePacket(d.colorDec, d.color[i], [&](const FrameInfo &f) { d.OnColor(f, out); })) {
        return false;
    }
    // 喂过的包不再需要，早一点还回去。
    Packet().swap(d.color[i]);
    if (!d.opaque) {
        Packet().swap(d.alpha[i]);
    }
    return true;
}

bool AlphaSequenceDecoder::Done() const {
    return impl_->next >= impl_->color.size();
}

} // namespace webm_alpha
