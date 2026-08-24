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

// 解码并合成。out 里每帧是 dstW*dstH*4 的非预乘 RGBA。
//
// frameStep 是**保留**步长，不是喂包步长：VP9 是帧间预测的，少喂一个包后面
// 全错，所以每一包都要送进解码器，只是解出来之后每 step 帧留一帧。降帧因此
// 只省内存，不省解码时间——这正是预算里优先降分辨率、其次才降帧的原因。
//
// 任何一步失败都返回 false 并清空 out —— 半截的结果比没有更糟。
bool DecodeAlphaSequence(const std::vector<Packet> &colorPackets,
                         const std::vector<Packet> &alphaPackets,
                         int32_t srcW, int32_t srcH, int32_t dstW, int32_t dstH,
                         int32_t frameStep, std::vector<RgbaFrame> &out);

} // namespace webm_alpha

#endif // PETRELGRAM_WEBM_ALPHA_H
