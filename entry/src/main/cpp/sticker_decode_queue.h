#ifndef PETRELGRAM_STICKER_DECODE_QUEUE_H
#define PETRELGRAM_STICKER_DECODE_QUEUE_H

#include <cstdint>
#include <functional>
#include <string>
#include <vector>

#include <multimedia/image_framework/image/pixelmap_native.h>

#include "sticker_frame_cache.h"
#include "webm_alpha.h"

// webm 贴纸的边解边播调度（2026-10-09）。
//
// 【原来】每张贴纸一个 napi async work，整段解完才交出全部帧；ArkTS 侧再用一条
// promise 链把所有贴纸串成一队。一屏十几张新贴纸 = 第十张要等前九张整段解完，
// 才轮到它解第一帧（用户反馈的「贴纸会卡」）。
//
// 【现在】一条常驻解码线程，所有任务在上面轮转，**每步只推进一包（或一帧缓存）**：
// - 先挑「磁盘缓存读取」任务：只是解压，快，命中了就别让它排在软解后面；
// - 再在前 kMaxActiveDecodes 个软解任务里挑**已出帧最少**的推进——每张贴纸先
//   拿到第一帧，再一起往后走。
// 解出的帧当场建成原生 PixelMap，按批交给 Deliver（第一帧单独一批）。
namespace sticker_decode {

struct Batch {
    // 交出去之后由接收方负责 OH_PixelmapNative_Release。
    std::vector<OH_PixelmapNative *> pixelmaps;
    bool done = false;
    bool ok = true;
    // 缓存读取任务在第一批里带上头部信息（尺寸、帧数、时间戳表），软解任务不带
    // ——那些 ArkTS 侧拆包时就知道了。
    bool hasInfo = false;
    sticker_cache::CacheInfo info{};
    std::vector<int32_t> timesMs;
};

void ReleaseBatch(Batch *batch);

// 两个回调都在解码线程上调用。Deliver 接过 batch 的所有权；Finish 在任务结束
// （做完、出错或被取消）后恰好调用一次，之后不会再有 Deliver。
using Deliver = std::function<void(Batch *)>;
using Finish = std::function<void()>;

struct DecodeParams {
    std::vector<webm_alpha::Packet> color;
    std::vector<webm_alpha::Packet> alpha;
    int32_t srcW = 0;
    int32_t srcH = 0;
    int32_t dstW = 0;
    int32_t dstH = 0;
    int32_t frameStep = 1;
    // 解完之后写一份压缩缓存（空串 = 不写）；timesMs 一并写进缓存头。
    std::string cachePath;
    std::vector<int32_t> timesMs;
    int32_t durationMs = 0;
};

// 返回任务号（>0）；参数不合法返回 0，且不会调用任何回调。
int32_t SubmitDecode(DecodeParams params, Deliver deliver, Finish finish);

// 读一份磁盘帧缓存。解出来超过 maxBytes（>0 时）就不读像素，直接交一批
// {done, ok=false, hasInfo} 回去，让调用方知道是「内存不够」而不是「没有缓存」。
int32_t SubmitLoad(std::string cachePath, int64_t maxBytes, Deliver deliver, Finish finish);

// 取消。已经交出去的帧照旧归接收方；之后不再 Deliver，随后调用 Finish。
void Cancel(int32_t id);

} // namespace sticker_decode

#endif // PETRELGRAM_STICKER_DECODE_QUEUE_H
