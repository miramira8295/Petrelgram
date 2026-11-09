#ifndef PETRELGRAM_WEBM_ALPHA_H
#define PETRELGRAM_WEBM_ALPHA_H

#include <cstddef>
#include <cstdint>
#include <vector>

// Telegram 的 webm 贴纸把 alpha 存成第二路普通 VP9 灰度流（WebM
// BlockAdditional，BlockAddID=1）。ArkTS 侧的 WebmAlphaDemuxer 负责拆包，
// 这里只做"两路 VP9 码流 -> 一串 RGBA 帧"，用系统 AVCodec 的 VP9 解码器。
namespace webm_alpha {

using Packet = std::vector<uint8_t>;
using RgbaFrame = std::vector<uint8_t>;

// 设备上有没有 VP9 解码能力。系统 VP9 是 API 23 才有的，低版本这里返回 false，
// 调用方原样回退到 ijkplayer。结果只探一次。
bool Vp9DecoderAvailable();

// 两路 VP9 码流 -> RGBA 帧，**一次推进一包**（边解边播，2026-10-09）。
//
// 原来是 DecodeAlphaSequence 一口气解完整段再交出去：第一帧要等最后一帧，一屏
// 新贴纸排着队一张张解完才动。现在由调度线程（sticker_decode_queue）反复调 Step，
// 每步喂一包、把这一包产出的帧交出去，几张贴纸轮流推进，各自很快拿到第一帧。
//
// 每帧是 dstW*dstH*4 的非预乘 RGBA。
//
// frameStep 是**保留**步长，不是喂包步长：VP9 是帧间预测的，少喂一个包后面
// 全错，所以每一包都要送进解码器，只是解出来之后每 step 帧留一帧。降帧因此
// 只省内存，不省解码时间——这正是预算里优先降分辨率、其次才降帧的原因。
class AlphaSequenceDecoder {
public:
    AlphaSequenceDecoder();
    ~AlphaSequenceDecoder();
    AlphaSequenceDecoder(const AlphaSequenceDecoder &) = delete;
    AlphaSequenceDecoder &operator=(const AlphaSequenceDecoder &) = delete;

    // alphaPackets 为空 = 不透明贴纸。参数不合法或解码器建不起来返回 false。
    bool Init(std::vector<Packet> colorPackets, std::vector<Packet> alphaPackets,
              int32_t srcW, int32_t srcH, int32_t dstW, int32_t dstH, int32_t frameStep);

    // 喂下一包（两路各一包），把这一包产出、且该保留的帧追加到 out。
    // 解码出错返回 false——调用方整段放弃，半截的结果比没有更糟。
    bool Step(std::vector<RgbaFrame> &out);

    bool Done() const;

private:
    struct Impl;
    Impl *impl_;
};

} // namespace webm_alpha

#endif // PETRELGRAM_WEBM_ALPHA_H
