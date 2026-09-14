#ifndef PETRELGRAM_TGS_RENDER_H
#define PETRELGRAM_TGS_RENDER_H

#include <cstdint>
#include <string>
#include <vector>

// TGS（gzip 过的 Lottie JSON）的原生渲染。
//
// 【为什么不是整段预解码】2026-09-14 在设备上读了 25 个真实 .tgs 的头：24 个是
// 60fps × 3 秒 = 180 帧、512×512。按气泡尺寸 256px 算，整段驻留是 46MB 一张。
// 而 Lottie 的任意一帧都能独立渲染（不像 VP9 有帧间预测），所以这里只提供
// 「按帧号渲一张」，缓冲几帧由调用方决定。
namespace tgs_render {

struct AnimationInfo {
    int32_t handle = 0;
    int32_t totalFrames = 0;
    double frameRate = 0;
    int32_t width = 0;
    int32_t height = 0;
};

// 打开一个 .tgs：读文件、gunzip、交给 rlottie 解析。失败返回 handle == 0。
// width/height 是**渲染尺寸**（渲染成什么大小就占多少内存），不是贴纸原生尺寸。
AnimationInfo Open(const std::string &path, int32_t width, int32_t height);

// 渲染一帧到 out（大小 = width*height*4，非预乘 RGBA）。
bool RenderFrame(int32_t handle, int32_t frameIndex, std::vector<uint8_t> &out,
                 int32_t &width, int32_t &height);

void Close(int32_t handle);

// 当前还开着几个（诊断用）。
int32_t OpenCount();

} // namespace tgs_render

#endif // PETRELGRAM_TGS_RENDER_H
