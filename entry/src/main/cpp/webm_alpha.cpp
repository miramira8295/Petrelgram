#include "webm_alpha.h"

#include <algorithm>
#include <functional>
#include <hilog/log.h>
#include <multimedia/player_framework/native_avbuffer.h>
#include <multimedia/player_framework/native_avbuffer_info.h>
#include <multimedia/player_framework/native_avcapability.h>
#include <multimedia/player_framework/native_avcodec_base.h>
#include <multimedia/player_framework/native_avcodec_videodecoder.h>
#include <multimedia/player_framework/native_averrors.h>
#include <multimedia/player_framework/native_avformat.h>

namespace webm_alpha {
namespace {

constexpr unsigned int LOG_DOMAIN = 0x0000;
constexpr const char *LOG_TAG = "WebmAlpha";

// 不用 OH_AVCODEC_MIMETYPE_VIDEO_VP9：它是 API 23 才引入的**数据符号**，
// 而 libentry.so 要在 API 20 的机器上一起加载。数据符号在加载时就要解析，
// 引用它会让整个 so 在老机器上装不进去——不是这个功能不可用，是 App 起不来。
// 字符串常量本身是稳定的协议标识，硬写没有兼容性风险。
constexpr const char *kVp9Mime = "video/x-vnd.on2.vp9";

// 输入/输出轮询的节奏。同步模式下这两个超时只影响忙等程度，不影响正确性。
constexpr int64_t kInputTimeoutUs = 0;
constexpr int64_t kOutputTimeoutUs = 20000;
// 连续这么多轮既喂不进去也吐不出来就认输。硬件解码器偶发挂死时，
// 宁可回退到 ijkplayer，也不能把这条工作线程永远钉在这里。
constexpr int kMaxStallRounds = 300;
// 再保守一层：ArkTS 侧已经按预算裁过尺寸，这里只防"参数被算错"。
constexpr size_t kMaxTotalBytes = 24u * 1024u * 1024u;
constexpr int32_t kMaxDim = 4096;

struct FrameInfo {
    const uint8_t *base;
    int32_t stride;    // Y 平面行距
    int32_t sliceH;    // Y 平面行数（UV 从 base + stride*sliceH 开始）
    int32_t picW;
    int32_t picH;
    bool rangeFull;
};

using FrameSink = std::function<void(const FrameInfo &)>;

struct DecoderHandle {
    OH_AVCodec *codec = nullptr;
    ~DecoderHandle() {
        if (codec != nullptr) {
            OH_VideoDecoder_Stop(codec);
            OH_VideoDecoder_Destroy(codec);
        }
    }
};

// 从一帧输出 buffer 的附带 format 里取行距/可见尺寸/色域范围。
// 取不到就退回配置值：某些实现只在 OnStreamChanged 里报一次。
void ReadFrameLayout(OH_AVBuffer *buffer, int32_t srcW, int32_t srcH, FrameInfo &info) {
    info.stride = srcW;
    info.sliceH = srcH;
    info.picW = srcW;
    info.picH = srcH;
    info.rangeFull = false;
    OH_AVFormat *format = OH_AVBuffer_GetParameter(buffer);
    if (format == nullptr) {
        return;
    }
    int32_t v = 0;
    if (OH_AVFormat_GetIntValue(format, OH_MD_KEY_VIDEO_STRIDE, &v) && v > 0) {
        info.stride = v;
    }
    if (OH_AVFormat_GetIntValue(format, OH_MD_KEY_VIDEO_SLICE_HEIGHT, &v) && v > 0) {
        info.sliceH = v;
    }
    if (OH_AVFormat_GetIntValue(format, OH_MD_KEY_VIDEO_PIC_WIDTH, &v) && v > 0) {
        info.picW = v;
    }
    if (OH_AVFormat_GetIntValue(format, OH_MD_KEY_VIDEO_PIC_HEIGHT, &v) && v > 0) {
        info.picH = v;
    }
    if (OH_AVFormat_GetIntValue(format, OH_MD_KEY_RANGE_FLAG, &v)) {
        info.rangeFull = v != 0;
    }
    OH_AVFormat_Destroy(format);
}

bool ConfigureDecoder(OH_AVCodec *codec, int32_t srcW, int32_t srcH) {
    OH_AVFormat *format = OH_AVFormat_Create();
    if (format == nullptr) {
        return false;
    }
    OH_AVFormat_SetIntValue(format, OH_MD_KEY_WIDTH, srcW);
    OH_AVFormat_SetIntValue(format, OH_MD_KEY_HEIGHT, srcH);
    OH_AVFormat_SetIntValue(format, OH_MD_KEY_PIXEL_FORMAT, AV_PIXEL_FORMAT_NV12);
    const bool ok = OH_VideoDecoder_Configure(codec, format) == AV_ERR_OK;
    OH_AVFormat_Destroy(format);
    return ok;
}

// 同步模式（API 20 起）：不注册回调，自己轮询进出。回调模式要额外一套线程
// 和条件变量，而这里本来就跑在 napi async work 的工作线程上，同步更简单，
// 也更容易在出错时干净收场。
bool DecodeStream(const std::vector<Packet> &packets, int32_t srcW, int32_t srcH,
                  const FrameSink &sink) {
    DecoderHandle handle;
    handle.codec = OH_VideoDecoder_CreateByMime(kVp9Mime);
    if (handle.codec == nullptr) {
        OH_LOG_Print(LOG_APP, LOG_WARN, LOG_DOMAIN, LOG_TAG, "%{public}s", "no vp9 decoder");
        return false;
    }
    if (!ConfigureDecoder(handle.codec, srcW, srcH) ||
        OH_VideoDecoder_Prepare(handle.codec) != AV_ERR_OK ||
        OH_VideoDecoder_Start(handle.codec) != AV_ERR_OK) {
        OH_LOG_Print(LOG_APP, LOG_WARN, LOG_DOMAIN, LOG_TAG, "%{public}s", "decoder start failed");
        return false;
    }

    size_t fed = 0;
    bool eosSent = false;
    bool eosSeen = false;
    int stall = 0;
    while (!eosSeen && stall < kMaxStallRounds) {
        bool progressed = false;
        if (!eosSent) {
            uint32_t index = 0;
            if (OH_VideoDecoder_QueryInputBuffer(handle.codec, &index, kInputTimeoutUs) == AV_ERR_OK) {
                OH_AVBuffer *in = OH_VideoDecoder_GetInputBuffer(handle.codec, index);
                if (in == nullptr) {
                    return false;
                }
                OH_AVCodecBufferAttr attr{};
                if (fed < packets.size()) {
                    const Packet &pkt = packets[fed];
                    uint8_t *addr = OH_AVBuffer_GetAddr(in);
                    const int32_t cap = OH_AVBuffer_GetCapacity(in);
                    if (addr == nullptr || cap < 0 || static_cast<size_t>(cap) < pkt.size()) {
                        return false;
                    }
                    std::copy(pkt.begin(), pkt.end(), addr);
                    attr.offset = 0;
                    attr.size = static_cast<int32_t>(pkt.size());
                    // pts 用序号即可：这条链路的播放时钟由 ArkTS 侧的时间戳表驱动，
                    // 解码器的 pts 只需要单调。
                    attr.pts = static_cast<int64_t>(fed);
                    attr.flags = AVCODEC_BUFFER_FLAGS_NONE;
                    ++fed;
                } else {
                    attr.flags = AVCODEC_BUFFER_FLAGS_EOS;
                    eosSent = true;
                }
                if (OH_AVBuffer_SetBufferAttr(in, &attr) != AV_ERR_OK ||
                    OH_VideoDecoder_PushInputBuffer(handle.codec, index) != AV_ERR_OK) {
                    return false;
                }
                progressed = true;
            }
        }
        uint32_t outIndex = 0;
        const OH_AVErrCode got =
            OH_VideoDecoder_QueryOutputBuffer(handle.codec, &outIndex, kOutputTimeoutUs);
        if (got == AV_ERR_OK) {
            OH_AVBuffer *out = OH_VideoDecoder_GetOutputBuffer(handle.codec, outIndex);
            if (out == nullptr) {
                return false;
            }
            OH_AVCodecBufferAttr attr{};
            const bool haveAttr = OH_AVBuffer_GetBufferAttr(out, &attr) == AV_ERR_OK;
            if (haveAttr && (attr.flags & AVCODEC_BUFFER_FLAGS_EOS) != 0) {
                eosSeen = true;
            } else if (haveAttr && attr.size > 0) {
                FrameInfo info{};
                info.base = OH_AVBuffer_GetAddr(out);
                ReadFrameLayout(out, srcW, srcH, info);
                if (info.base != nullptr) {
                    sink(info);
                }
            }
            OH_VideoDecoder_FreeOutputBuffer(handle.codec, outIndex);
            progressed = true;
        } else if (got == AV_ERR_STREAM_CHANGED) {
            progressed = true; // 行距/尺寸逐帧重读，这里无需额外处理
        }
        stall = progressed ? 0 : stall + 1;
    }
    return eosSeen;
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

// 有限范围（16..235）拉回 0..255。alpha 那一路也要做：ffmpeg 的 libvpx 路径是
// 把 Y 直接当 A 用，若编码器写的是 limited，全透明区就会停在 16 而不是 0，
// 表现成一圈灰边。按流自己报的 range 展开才是对的。
inline uint8_t ExpandRange(uint8_t v, bool full) {
    if (full) {
        return v;
    }
    return Clamp255((static_cast<int32_t>(v) - 16) * 255 / 219);
}

} // namespace

bool Vp9DecoderAvailable() {
    static const bool available = []() -> bool {
        OH_AVCapability *cap = OH_AVCodec_GetCapability(kVp9Mime, false);
        return cap != nullptr;
    }();
    return available;
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
    if (!Vp9DecoderAvailable()) {
        return false;
    }

    // 两路先后解，不并行：同时开两个硬件实例会占掉别处要用的解码器，而先把
    // alpha 存成 dstW*dstH 的单字节平面，额外内存只有最终 RGBA 的 1/4。
    const size_t planeBytes = static_cast<size_t>(dstW) * dstH;
    std::vector<std::vector<uint8_t>> alphaPlanes;
    alphaPlanes.reserve(keepCount);
    bool alphaFull = false;
    size_t alphaSeen = 0;
    const bool alphaOk = DecodeStream(alphaPackets, srcW, srcH, [&](const FrameInfo &f) {
        const size_t seen = alphaSeen++;
        if (seen % step != 0 || alphaPlanes.size() >= keepCount) {
            return;
        }
        alphaFull = f.rangeFull;
        std::vector<uint8_t> plane(planeBytes, 0);
        ResizePlane(f.base, f.stride, 1, std::min(f.picW, srcW), std::min(f.picH, srcH),
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
    const bool colorOk = DecodeStream(colorPackets, srcW, srcH, [&](const FrameInfo &f) {
        const size_t seen = colorSeen++;
        // 两路是同一段时间轴、同样的帧数，按解出的序号配对；留哪几帧也用
        // 同一个 step，所以 index 一定对得上。
        const size_t index = seen / step;
        if (seen % step != 0 || index >= alphaPlanes.size()) {
            return;
        }
        const int32_t picW = std::min(f.picW, srcW);
        const int32_t picH = std::min(f.picH, srcH);
        const uint8_t *uv = f.base + static_cast<size_t>(f.stride) * f.sliceH;
        ResizePlane(f.base, f.stride, 1, picW, picH, luma.data(), dstW, dstH);
        ResizePlane(uv, f.stride, 2, picW / 2, picH / 2, chromaU.data(), dstW, dstH);
        ResizePlane(uv + 1, f.stride, 2, picW / 2, picH / 2, chromaV.data(), dstW, dstH);
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
