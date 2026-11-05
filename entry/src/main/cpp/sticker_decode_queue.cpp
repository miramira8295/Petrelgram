#include "sticker_decode_queue.h"

#include <atomic>
#include <condition_variable>
#include <hilog/log.h>
#include <list>
#include <memory>
#include <mutex>
#include <thread>

namespace sticker_decode {
namespace {

constexpr unsigned int kLogDomain = 0x0000;
constexpr const char *kLogTag = "StickerDecode";
constexpr int32_t kPixelFormatRgb565 = 2;            // PIXEL_FORMAT_RGB_565
constexpr int32_t kPixelFormatRgba8888 = 3;          // PIXEL_FORMAT_RGBA_8888
constexpr int32_t kAlphaTypeUnpremultiplied = 3;     // PIXELMAP_ALPHA_TYPE_UNPREMULTIPLIED

// 同时在推进的软解任务数。每张贴纸两路 libvpx 解码器、各带一池参考帧（512px 时
// 一个解码器几 MB），全屏几十张一起开就是几十个解码器的常驻内存；而且轮转的张数
// 越多，每张拿到下一帧越慢。排在后面的照样会轮到，只是先等前面几张解完。
constexpr size_t kMaxActiveDecodes = 3;
// 第一帧之后每攒这么多帧交一次：一帧一交，每帧都要跨一次线程、在主线程上做一次
// napi 转换；整段一交又回到了「全部解完才动」。
constexpr size_t kBatchFrames = 6;

enum class Kind { Decode, Load };

struct Job {
    int32_t id = 0;
    Kind kind = Kind::Decode;
    std::atomic<bool> cancelled{false};
    Deliver deliver;
    Finish finish;
    size_t emitted = 0;
    bool started = false;
    std::vector<OH_PixelmapNative *> pending;
    OH_Pixelmap_InitializationOptions *options = nullptr;
    int32_t width = 0;
    int32_t height = 0;
    // 每像素字节数：4 = RGBA_8888；2 = RGB_565（不透明贴纸，内存省一半，预算放得下两倍的帧）。
    int32_t bytesPerPixel = 4;
    // 软解
    webm_alpha::AlphaSequenceDecoder decoder;
    DecodeParams params;
    std::vector<std::vector<uint8_t>> packed;   // 边解边压，解完一次写盘
    bool cacheBroken = false;
    // 读缓存
    std::string cachePath;
    int64_t maxBytes = 0;
    sticker_cache::Reader reader;
    bool infoPending = false;

    ~Job() {
        for (OH_PixelmapNative *pm : pending) {
            OH_PixelmapNative_Release(pm);
        }
        if (options != nullptr) {
            OH_PixelmapInitializationOptions_Release(options);
        }
    }
};

std::mutex gMutex;
std::condition_variable gCv;
std::list<std::unique_ptr<Job>> gJobs;
int32_t gNextId = 1;
bool gWorkerStarted = false;
// 见 sticker_decode_queue.h 的 SetPaused 说明。用 atomic 是为了让 WorkerLoop
// 的等待条件能直接读，不必每次都抓锁再判。
std::atomic<bool> gPaused{false};

bool InitOptions(Job &job, int32_t w, int32_t h, int32_t bytesPerPixel) {
    const int32_t format = bytesPerPixel == 2 ? kPixelFormatRgb565 : kPixelFormatRgba8888;
    if (OH_PixelmapInitializationOptions_Create(&job.options) != IMAGE_SUCCESS || job.options == nullptr) {
        return false;
    }
    OH_PixelmapInitializationOptions_SetWidth(job.options, static_cast<uint32_t>(w));
    OH_PixelmapInitializationOptions_SetHeight(job.options, static_cast<uint32_t>(h));
    OH_PixelmapInitializationOptions_SetPixelFormat(job.options, format);
    // **源格式必须显式设，不能只设目标格式。** 不设的话 CreatePixelmap 把写好的
    // RGBA 当成别的排列去转——真机上整片偏青（红蓝互换）。
    OH_PixelmapInitializationOptions_SetSrcPixelFormat(job.options, format);
    // 行距同理：缓冲区是紧凑排布，一行就是 w*bytesPerPixel 字节。猜错的表现是斜切。
    OH_PixelmapInitializationOptions_SetRowStride(job.options, static_cast<uint32_t>(w * bytesPerPixel));
    OH_PixelmapInitializationOptions_SetAlphaType(job.options, kAlphaTypeUnpremultiplied);
    job.width = w;
    job.height = h;
    job.bytesPerPixel = bytesPerPixel;
    return true;
}

// 非预乘 RGBA -> RGB565（native endian 的 uint16：R 高 5 位、G 中 6 位、B 低 5 位）。
// 不透明贴纸的 alpha 恒为 255，丢掉不损失任何东西。
void RgbaToRgb565(const std::vector<uint8_t> &rgba, std::vector<uint8_t> &out) {
    const size_t pixels = rgba.size() / 4;
    out.resize(pixels * 2);
    uint16_t *dst = reinterpret_cast<uint16_t *>(out.data());
    for (size_t i = 0; i < pixels; ++i) {
        const uint8_t r = rgba[i * 4];
        const uint8_t g = rgba[i * 4 + 1];
        const uint8_t b = rgba[i * 4 + 2];
        dst[i] = static_cast<uint16_t>(((r >> 3) << 11) | ((g >> 2) << 5) | (b >> 3));
    }
}

// RGBA -> 原生 PixelMap（它持有自己那份拷贝，源缓冲随后就可以丢）。
bool AppendPixelmap(Job &job, std::vector<uint8_t> &rgba) {
    OH_PixelmapNative *pm = nullptr;
    if (OH_PixelmapNative_CreatePixelmap(rgba.data(), rgba.size(), job.options, &pm) != IMAGE_SUCCESS ||
        pm == nullptr) {
        return false;
    }
    job.pending.push_back(pm);
    ++job.emitted;
    return true;
}

void Flush(Job &job, bool done, bool ok) {
    Batch *batch = new Batch();
    batch->pixelmaps.swap(job.pending);
    batch->done = done;
    batch->ok = ok;
    if (job.infoPending) {
        job.infoPending = false;
        batch->hasInfo = true;
        batch->info = job.reader.Info();
        batch->timesMs = job.reader.TimesMs();
    }
    job.deliver(batch);
}

// 第一帧单独交（越早画上越好），之后攒够一批再交。
void MaybeFlush(Job &job) {
    if (job.pending.empty()) {
        return;
    }
    if (job.emitted == job.pending.size() || job.pending.size() >= kBatchFrames) {
        Flush(job, false, true);
    }
}

void Fail(Job &job) {
    for (OH_PixelmapNative *pm : job.pending) {
        OH_PixelmapNative_Release(pm);
    }
    job.pending.clear();
    Flush(job, true, false);
}

// 推进一步。返回 true = 任务结束（做完或出错，结局已经 Deliver 出去）。
bool StepDecode(Job &job) {
    if (!job.started) {
        job.started = true;
        DecodeParams &p = job.params;
        const int32_t bytesPerPixel = p.alpha.empty() ? 2 : 4;   // 不透明 = 没有 alpha 那一路
        if (!job.decoder.Init(std::move(p.color), std::move(p.alpha), p.srcW, p.srcH, p.dstW, p.dstH,
                              p.frameStep) ||
            !InitOptions(job, p.dstW, p.dstH, bytesPerPixel)) {
            Fail(job);
            return true;
        }
        job.cacheBroken = p.cachePath.empty();
    }
    std::vector<webm_alpha::RgbaFrame> frames;
    if (!job.decoder.Step(frames)) {
        Fail(job);
        return true;
    }
    std::vector<uint8_t> rgb565;
    for (webm_alpha::RgbaFrame &rgba : frames) {
        std::vector<uint8_t> &frame = job.bytesPerPixel == 2 ? rgb565 : rgba;
        if (job.bytesPerPixel == 2) {
            RgbaToRgb565(rgba, rgb565);
        }
        if (!job.cacheBroken) {
            std::vector<uint8_t> packed;
            if (sticker_cache::CompressFrame(frame, packed)) {
                job.packed.push_back(std::move(packed));
            } else {
                job.cacheBroken = true;   // 写不成缓存不影响播放，只是下次还得重解
                std::vector<std::vector<uint8_t>>().swap(job.packed);
            }
        }
        if (!AppendPixelmap(job, frame)) {
            Fail(job);
            return true;
        }
    }
    if (!job.decoder.Done()) {
        MaybeFlush(job);
        return false;
    }
    if (job.emitted == 0) {
        Fail(job);
        return true;
    }
    // 解码器可能比预期少吐几帧；时间戳表对不上就不写缓存——命中缓存那条路要靠
    // 它一帧一帧对时刻，错位比没有缓存更糟。
    const DecodeParams &p = job.params;
    if (!job.cacheBroken && job.packed.size() == p.timesMs.size()) {
        sticker_cache::CacheInfo info{p.dstW, p.dstH, static_cast<int32_t>(job.packed.size()), p.durationMs,
                                      job.bytesPerPixel};
        if (!sticker_cache::WritePacked(p.cachePath, info, job.packed, p.timesMs)) {
            OH_LOG_Print(LOG_APP, LOG_WARN, kLogDomain, kLogTag, "%{public}s", "frame cache write failed");
        }
    }
    std::vector<std::vector<uint8_t>>().swap(job.packed);
    Flush(job, true, true);
    return true;
}

bool StepLoad(Job &job) {
    if (!job.started) {
        job.started = true;
        if (!job.reader.Open(job.cachePath)) {
            Fail(job);   // 没有缓存或文件坏了：调用方照常去解码
            return true;
        }
        const sticker_cache::CacheInfo &info = job.reader.Info();
        job.infoPending = true;
        // 预算是**解压后**的字节：压缩比再好，进内存的还是整段 RGBA。
        if (job.maxBytes > 0 && sticker_cache::DecodedBytes(info) > job.maxBytes) {
            Flush(job, true, false);   // 带着 info 交回去：是内存不够，不是没有缓存
            return true;
        }
        if (!InitOptions(job, info.width, info.height, info.bytesPerPixel)) {
            Fail(job);
            return true;
        }
    }
    std::vector<uint8_t> rgba;
    if (!job.reader.Next(rgba) || !AppendPixelmap(job, rgba)) {
        Fail(job);
        return true;
    }
    if (!job.reader.Done()) {
        MaybeFlush(job);
        return false;
    }
    Flush(job, true, true);
    return true;
}

// 挑下一个要推进的任务；顺带把已取消的摘出来交给调用方去收尾。
Job *PickLocked(std::vector<std::unique_ptr<Job>> &dropped) {
    for (auto it = gJobs.begin(); it != gJobs.end();) {
        if ((*it)->cancelled.load()) {
            dropped.push_back(std::move(*it));
            it = gJobs.erase(it);
        } else {
            ++it;
        }
    }
    Job *best = nullptr;
    for (const std::unique_ptr<Job> &job : gJobs) {
        if (job->kind == Kind::Load && (best == nullptr || job->emitted < best->emitted)) {
            best = job.get();
        }
    }
    if (best != nullptr) {
        return best;
    }
    size_t active = 0;
    for (const std::unique_ptr<Job> &job : gJobs) {
        if (job->kind != Kind::Decode) {
            continue;
        }
        if (best == nullptr || job->emitted < best->emitted) {
            best = job.get();
        }
        if (++active >= kMaxActiveDecodes) {
            break;
        }
    }
    return best;
}

void RemoveLocked(Job *done, std::unique_ptr<Job> &out) {
    for (auto it = gJobs.begin(); it != gJobs.end(); ++it) {
        if (it->get() == done) {
            out = std::move(*it);
            gJobs.erase(it);
            return;
        }
    }
}

void WorkerLoop() {
    for (;;) {
        std::vector<std::unique_ptr<Job>> dropped;
        Job *job = nullptr;
        {
            std::unique_lock<std::mutex> lock(gMutex);
            // 暂停期间不取新任务：等「有任务且没暂停」。恢复时 SetPaused 会
            // notify_all 把这条线程叫醒。
            gCv.wait(lock, [] { return !gJobs.empty() && !gPaused.load(); });
            job = PickLocked(dropped);
        }
        // 收尾放在锁外：Finish 会碰 napi 线程安全函数，别让它卡住 Submit/Cancel。
        for (std::unique_ptr<Job> &gone : dropped) {
            gone->finish();
        }
        if (job == nullptr) {
            continue;
        }
        // 任务只在这条线程上被推进、被删除；Cancel 只置标志，所以锁外用 job 是安全的。
        const bool finished = job->kind == Kind::Load ? StepLoad(*job) : StepDecode(*job);
        if (!finished) {
            continue;
        }
        std::unique_ptr<Job> owned;
        {
            std::lock_guard<std::mutex> lock(gMutex);
            RemoveLocked(job, owned);
        }
        if (owned) {
            owned->finish();
        }
    }
}

int32_t Enqueue(std::unique_ptr<Job> job) {
    std::lock_guard<std::mutex> lock(gMutex);
    if (!gWorkerStarted) {
        gWorkerStarted = true;
        // 进程级常驻，不 join：贴纸随时会来，反复起停线程比空等更贵。
        std::thread(WorkerLoop).detach();
    }
    const int32_t id = gNextId++;
    if (gNextId <= 0) {
        gNextId = 1;
    }
    job->id = id;
    gJobs.push_back(std::move(job));
    gCv.notify_one();
    return id;
}

} // namespace

void SetPaused(bool paused) {
    gPaused.store(paused);
    if (!paused) {
        std::lock_guard<std::mutex> lock(gMutex);
        gCv.notify_all();
    }
}

void ReleaseBatch(Batch *batch) {
    if (batch == nullptr) {
        return;
    }
    for (OH_PixelmapNative *pm : batch->pixelmaps) {
        if (pm != nullptr) {
            OH_PixelmapNative_Release(pm);
        }
    }
    delete batch;
}

int32_t SubmitDecode(DecodeParams params, Deliver deliver, Finish finish) {
    if (params.color.empty() || params.dstW <= 0 || params.dstH <= 0 || !deliver || !finish) {
        return 0;
    }
    std::unique_ptr<Job> job(new Job());
    job->kind = Kind::Decode;
    job->params = std::move(params);
    job->deliver = std::move(deliver);
    job->finish = std::move(finish);
    return Enqueue(std::move(job));
}

int32_t SubmitLoad(std::string cachePath, int64_t maxBytes, Deliver deliver, Finish finish) {
    if (cachePath.empty() || !deliver || !finish) {
        return 0;
    }
    std::unique_ptr<Job> job(new Job());
    job->kind = Kind::Load;
    job->cachePath = std::move(cachePath);
    job->maxBytes = maxBytes;
    job->deliver = std::move(deliver);
    job->finish = std::move(finish);
    return Enqueue(std::move(job));
}

void Cancel(int32_t id) {
    std::lock_guard<std::mutex> lock(gMutex);
    for (const std::unique_ptr<Job> &job : gJobs) {
        if (job->id == id) {
            job->cancelled.store(true);
            gCv.notify_one();   // 让工作线程尽快把它摘掉、调 Finish
            return;
        }
    }
}

} // namespace sticker_decode
