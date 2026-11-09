#include "tgs_render.h"

#include <algorithm>
#include <chrono>
#include <condition_variable>
#include <cstdio>
#include <cstring>
#include <deque>
#include <functional>
#include <hilog/log.h>
#include <map>
#include <memory>
#include <mutex>
#include <pthread.h>
#include <rlottie.h>
#include <zlib.h>

#include "tgs_frame_cache.h"

namespace tgs_render {
namespace {

constexpr unsigned int kLogDomain = 0x0000;
constexpr const char *kLogTag = "TgsRender";
// .tgs 是几十 KB，解压后的 JSON 实测中位 147KB、最大 381KB。留足余量，
// 同时挡住"这不是贴纸"的文件。
constexpr size_t kMaxCompressedBytes = 4u * 1024 * 1024;
constexpr size_t kMaxJsonBytes = 32u * 1024 * 1024;
constexpr int32_t kMaxDim = 512;

// 一层 = 一个 .tgs。普通贴纸只有一层；🎰 老虎机是 5 层（背景/三个转轮/拉杆，
// Telegram 就是这么下发的），在这里按 z 序合成一张，见 RenderFrame。
struct Layer {
    std::string path;
    // 帧缓存整段在盘上时一直是空的：真遇到没存的帧才解析（见 EnsureAnimations）。
    std::unique_ptr<rlottie::Animation> animation;
};

struct Entry {
    std::vector<Layer> layers;
    bool parseFailed = false;
    int32_t width = 0;
    int32_t height = 0;
    int32_t totalFrames = 0;
    // rlottie 要的是 uint32 的画布（预乘 ARGB）；复用同一块，免得每帧一次分配/释放。
    // 多层时 canvas 是合成结果，scratch 是当前这一层。
    std::vector<uint32_t> canvas;
    std::vector<uint32_t> scratch;
    // 渲好的帧的磁盘缓存（tgs_frame_cache.h）。没给缓存目录或取不到源文件大小时为空。
    std::shared_ptr<tgs_cache::FrameCache> cache;
};

// 命中/渲染的计数与耗时，攒够一批打一行 [TgsCache]，上机对账用。
struct CacheStats {
    int64_t hits = 0;
    int64_t misses = 0;
    double hitMs = 0;
    double missMs = 0;
};
std::mutex g_statsMutex;
CacheStats g_stats;
constexpr int64_t kStatsEvery = 120;
constexpr size_t kMaxLayers = 8;

std::mutex g_mutex;
std::map<int32_t, std::shared_ptr<Entry>> g_entries;
int32_t g_nextHandle = 1;

// ── 所有 rlottie 调用都跑在这一条线程上 ─────────────────────────────────
//
// **这是一次真机崩溃换来的**（2026-09-14，SIGSEGV 写未映射地址
// esr=0x92000045，栈在 tgs_render::RenderFrame 下面十几层 rlottie 里）：
// 我们编 rlottie 时关掉了 LOTTIE_THREAD（不想要它自带的线程池），而
// vglobal.h:74 那个开关**同时**控制 `vthread_local` 的定义——关掉之后它展开成
// 空，于是 vrle.cpp 的 Scratch_Object（RLE 临时缓冲）和 lottieitem.cpp 的
// Dash_Vector 从"每线程一份"变成**全进程一份**。而 napi 的 async work 跑在
// FFRT 线程池上，两张贴纸同时渲染就是两个线程往同一块 VRle::Data 里写。
//
// 两条修法：把 LOTTIE_THREAD 打开（恢复 thread_local，但也会带回它的线程池），
// 或者保证所有调用在同一条线程上。选后者——线程数由我们自己掌握，而且解析
// （loadFromData）和渲染本来就该串起来：一次只解一张，和 webm 那条链路同一个
// 策略。调用方（FFRT worker）在这里阻塞等结果，总耗时不变。
//
// 栈给 1MB：freetype 那套灰度光栅化在栈上开临时池，FFRT worker 的栈未必够。
class RenderThread {
public:
    static RenderThread &instance() {
        static RenderThread thread;
        return thread;
    }

    // 把 fn 排进去并等它跑完。fn 抛异常不在预期内（rlottie 不抛），真抛了
    // 就会穿过这里——那是 bug，不该吞。
    void Run(const std::function<void()> &fn) {
        Job job{&fn, false};
        {
            std::unique_lock<std::mutex> lock(mutex_);
            queue_.push_back(&job);
        }
        pending_.notify_one();
        std::unique_lock<std::mutex> lock(mutex_);
        done_.wait(lock, [&job]() { return job.done; });
    }

private:
    struct Job {
        const std::function<void()> *fn;
        bool done;
    };

    RenderThread() {
        pthread_attr_t attr;
        pthread_attr_init(&attr);
        pthread_attr_setstacksize(&attr, 1024 * 1024);
        pthread_create(&thread_, &attr, &RenderThread::Main, this);
        pthread_attr_destroy(&attr);
    }

    static void *Main(void *arg) {
        pthread_setname_np(pthread_self(), "PgTgsRender");
        static_cast<RenderThread *>(arg)->Loop();
        return nullptr;
    }

    void Loop() {
        while (true) {
            Job *job = nullptr;
            {
                std::unique_lock<std::mutex> lock(mutex_);
                pending_.wait(lock, [this]() { return !queue_.empty(); });
                job = queue_.front();
                queue_.pop_front();
            }
            (*job->fn)();
            {
                std::unique_lock<std::mutex> lock(mutex_);
                job->done = true;
            }
            done_.notify_all();
        }
    }

    std::mutex mutex_;
    std::condition_variable pending_;
    std::condition_variable done_;
    std::deque<Job *> queue_;
    pthread_t thread_{};
};

bool ReadWholeFile(const std::string &path, std::vector<uint8_t> &out) {
    FILE *f = fopen(path.c_str(), "rb");
    if (f == nullptr) {
        return false;
    }
    fseek(f, 0, SEEK_END);
    const long size = ftell(f);
    fseek(f, 0, SEEK_SET);
    if (size <= 0 || static_cast<size_t>(size) > kMaxCompressedBytes) {
        fclose(f);
        return false;
    }
    out.resize(static_cast<size_t>(size));
    const size_t read = fread(out.data(), 1, out.size(), f);
    fclose(f);
    return read == out.size();
}

// gzip / zlib 都认（windowBits 15+32 = 自动识别）。**不是所有 .tgs 都压过**：
// 少数文件就是裸 JSON，开头的 '{' 会让 inflateInit2 直接失败，那时原样返回。
bool Gunzip(const std::vector<uint8_t> &src, std::string &out) {
    if (src.empty()) {
        return false;
    }
    if (src[0] == '{') {
        out.assign(reinterpret_cast<const char *>(src.data()), src.size());
        return true;
    }
    z_stream stream{};
    if (inflateInit2(&stream, 15 + 32) != Z_OK) {
        return false;
    }
    stream.next_in = const_cast<Bytef *>(src.data());
    stream.avail_in = static_cast<uInt>(src.size());
    std::vector<uint8_t> buffer(256 * 1024);
    out.clear();
    int status = Z_OK;
    do {
        stream.next_out = buffer.data();
        stream.avail_out = static_cast<uInt>(buffer.size());
        status = inflate(&stream, Z_NO_FLUSH);
        if (status != Z_OK && status != Z_STREAM_END) {
            inflateEnd(&stream);
            return false;
        }
        out.append(reinterpret_cast<const char *>(buffer.data()), buffer.size() - stream.avail_out);
        if (out.size() > kMaxJsonBytes) {
            inflateEnd(&stream);
            return false;
        }
    } while (status != Z_STREAM_END);
    inflateEnd(&stream);
    return !out.empty();
}

std::shared_ptr<Entry> Find(int32_t handle) {
    std::lock_guard<std::mutex> guard(g_mutex);
    auto it = g_entries.find(handle);
    return it == g_entries.end() ? nullptr : it->second;
}

// 读文件 + gunzip + 交给 rlottie。解析必须在渲染线程上（见 RenderThread 的说明）。
std::unique_ptr<rlottie::Animation> ParseAnimation(const std::string &path) {
    std::vector<uint8_t> raw;
    if (!ReadWholeFile(path, raw)) {
        return nullptr;
    }
    std::string json;
    if (!Gunzip(raw, json)) {
        return nullptr;
    }
    // 第二个参数是 rlottie 自己的模型缓存键：同一张贴纸在多处播放时只解析一次
    // JSON。用文件路径当键正合适。
    std::unique_ptr<rlottie::Animation> animation;
    RenderThread::instance().Run([&animation, &json, &path]() {
        animation = rlottie::Animation::loadFromData(std::move(json), path);
    });
    if (!animation) {
        OH_LOG_Print(LOG_APP, LOG_WARN, kLogDomain, kLogTag, "%{public}s", "parse failed");
    }
    return animation;
}

// 帧缓存不全、遇到没存的帧时才解析。同一个 handle 同时只有一帧在途（JS 侧排队），
// 不会有两个线程同时进来。任何一层解析失败整个作废：少一层的老虎机是错的画面。
bool EnsureAnimations(Entry &entry) {
    if (entry.parseFailed) {
        return false;
    }
    for (Layer &layer : entry.layers) {
        if (layer.animation) {
            continue;
        }
        layer.animation = ParseAnimation(layer.path);
        if (!layer.animation) {
            entry.parseFailed = true;
            return false;
        }
    }
    const size_t pixels = static_cast<size_t>(entry.width) * entry.height;
    if (entry.canvas.size() != pixels) {
        entry.canvas.assign(pixels, 0);
    }
    if (entry.layers.size() > 1 && entry.scratch.size() != pixels) {
        entry.scratch.assign(pixels, 0);
    }
    return true;
}

// 所有层里最长的那一层定总帧数；帧率取第一层（同一组动画，帧率一致）。
void TakeTimeline(const Entry &entry, int32_t &totalFrames, double &frameRate) {
    totalFrames = 0;
    frameRate = 0;
    for (const Layer &layer : entry.layers) {
        totalFrames = std::max(totalFrames, static_cast<int32_t>(layer.animation->totalFrame()));
    }
    frameRate = entry.layers.front().animation->frameRate();
}

// 预乘 ARGB 的 source-over：dst = src + dst × (1 − srcA)。四个通道同一个式子。
void CompositeOver(const std::vector<uint32_t> &src, std::vector<uint32_t> &dst) {
    for (size_t i = 0; i < src.size(); ++i) {
        const uint32_t s = src[i];
        const uint32_t sa = s >> 24;
        if (sa == 0) {
            continue;
        }
        if (sa == 255) {
            dst[i] = s;
            continue;
        }
        const uint32_t d = dst[i];
        const uint32_t inv = 255 - sa;
        uint32_t out = 0;
        for (int shift = 0; shift < 32; shift += 8) {
            const uint32_t c = ((s >> shift) & 0xFF) + (((d >> shift) & 0xFF) * inv + 127) / 255;
            out |= (c > 255 ? 255 : c) << shift;
        }
        dst[i] = out;
    }
}

// 把第 frame 帧（合成后的预乘 ARGB）渲进 entry.canvas。层比总帧数短的停在自己最后一帧。
void RenderLayers(Entry &entry, int32_t frame) {
    RenderThread::instance().Run([&entry, frame]() {
        const size_t w = static_cast<size_t>(entry.width);
        const size_t h = static_cast<size_t>(entry.height);
        const bool single = entry.layers.size() == 1;
        if (!single) {
            std::fill(entry.canvas.begin(), entry.canvas.end(), 0u);
        }
        for (Layer &layer : entry.layers) {
            const size_t total = layer.animation->totalFrame();
            if (total == 0) {
                continue;
            }
            const size_t at = std::min(static_cast<size_t>(frame), total - 1);
            std::vector<uint32_t> &target = single ? entry.canvas : entry.scratch;
            rlottie::Surface surface(target.data(), w, h, w * 4);
            layer.animation->renderSync(at, surface);
            if (!single) {
                CompositeOver(entry.scratch, entry.canvas);
            }
        }
    });
}

void NoteStats(bool hit, double ms) {
    std::lock_guard<std::mutex> guard(g_statsMutex);
    if (hit) {
        g_stats.hits++;
        g_stats.hitMs += ms;
    } else {
        g_stats.misses++;
        g_stats.missMs += ms;
    }
    if (g_stats.hits + g_stats.misses < kStatsEvery) {
        return;
    }
    OH_LOG_Print(LOG_APP, LOG_WARN, kLogDomain, kLogTag,
                 "[TgsCache] hits=%{public}lld avgHitMs=%{public}.2f misses=%{public}lld avgMissMs=%{public}.2f",
                 static_cast<long long>(g_stats.hits), g_stats.hits > 0 ? g_stats.hitMs / g_stats.hits : 0.0,
                 static_cast<long long>(g_stats.misses), g_stats.misses > 0 ? g_stats.missMs / g_stats.misses : 0.0);
    g_stats = CacheStats{};
}

} // namespace

AnimationInfo Open(const std::vector<std::string> &paths, int32_t width, int32_t height,
                   const std::string &cacheDir) {
    AnimationInfo info;
    if (width <= 0 || height <= 0 || width > kMaxDim || height > kMaxDim || paths.empty() ||
        paths.size() > kMaxLayers) {
        return info;
    }
    auto entry = std::make_shared<Entry>();
    for (const std::string &path : paths) {
        if (path.empty()) {
            return info;
        }
        entry->layers.push_back(Layer{path, nullptr});
    }
    entry->width = width;
    entry->height = height;
    std::string cachePath;
    if (!cacheDir.empty()) {
        const std::string name = tgs_cache::FileNameFor(paths, width, height);
        cachePath = name.empty() ? "" : cacheDir + "/" + name;
    }
    // 盘上已经有这张：总帧数/帧率从缓存头里来，不读源文件、不解析 JSON。
    if (!cachePath.empty()) {
        entry->cache = tgs_cache::FrameCache::Open(cachePath, width, height, 0, 0, false);
    }
    double frameRate = 0;
    if (entry->cache != nullptr && entry->cache->CachedCount() > 0) {
        entry->totalFrames = entry->cache->TotalFrames();
        frameRate = entry->cache->FrameRate();
    } else {
        if (!EnsureAnimations(*entry)) {
            return info;
        }
        TakeTimeline(*entry, entry->totalFrames, frameRate);
        if (entry->totalFrames <= 0) {
            return info;
        }
        if (!cachePath.empty() && entry->cache == nullptr) {
            entry->cache = tgs_cache::FrameCache::Open(cachePath, width, height, entry->totalFrames, frameRate, true);
        }
    }
    info.totalFrames = entry->totalFrames;
    info.frameRate = frameRate;
    info.width = width;
    info.height = height;
    {
        std::lock_guard<std::mutex> guard(g_mutex);
        info.handle = g_nextHandle++;
        g_entries[info.handle] = entry;
    }
    return info;
}

bool RenderFrame(int32_t handle, int32_t frameIndex, std::vector<uint8_t> &out, int32_t &width,
                 int32_t &height) {
    std::shared_ptr<Entry> entry = Find(handle);
    if (entry == nullptr || frameIndex < 0 || entry->totalFrames <= 0) {
        return false;
    }
    const int32_t frame = frameIndex % entry->totalFrames;
    width = entry->width;
    height = entry->height;
    const auto started = std::chrono::steady_clock::now();
    auto elapsedMs = [&started]() -> double {
        return std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - started).count();
    };
    if (entry->cache != nullptr && entry->cache->Get(frame, out)) {
        NoteStats(true, elapsedMs());
        return true;
    }
    if (!EnsureAnimations(*entry)) {
        return false;
    }
    RenderLayers(*entry, frame);
    // rlottie 吐的是**预乘的 ARGB32**，按本机字节序落在内存里就是 B,G,R,A。
    // PixelMap 那边我们统一用非预乘 RGBA（与 webm 贴纸同一套，见
    // webm_alpha_napi 里关于 SetSrcPixelFormat 的那段事故说明），所以这里
    // 既要换字节序，也要反预乘——少做一步的表现分别是"红蓝互换"和"半透明
    // 边缘发黑"。
    const size_t pixels = static_cast<size_t>(entry->width) * entry->height;
    out.resize(pixels * 4);
    const uint32_t *src = entry->canvas.data();
    for (size_t i = 0; i < pixels; ++i) {
        const uint32_t v = src[i];
        const uint32_t a = (v >> 24) & 0xFF;
        uint32_t r = (v >> 16) & 0xFF;
        uint32_t g = (v >> 8) & 0xFF;
        uint32_t b = v & 0xFF;
        if (a != 0 && a != 255) {
            r = r * 255 / a;
            g = g * 255 / a;
            b = b * 255 / a;
            r = r > 255 ? 255 : r;
            g = g > 255 ? 255 : g;
            b = b > 255 ? 255 : b;
        } else if (a == 0) {
            r = 0;
            g = 0;
            b = 0;
        }
        out[i * 4 + 0] = static_cast<uint8_t>(r);
        out[i * 4 + 1] = static_cast<uint8_t>(g);
        out[i * 4 + 2] = static_cast<uint8_t>(b);
        out[i * 4 + 3] = static_cast<uint8_t>(a);
    }
    if (entry->cache != nullptr) {
        entry->cache->PutAsync(frame, out);
    }
    NoteStats(false, elapsedMs());
    return true;
}

void Close(int32_t handle) {
    std::lock_guard<std::mutex> guard(g_mutex);
    g_entries.erase(handle);
}

int32_t OpenCount() {
    std::lock_guard<std::mutex> guard(g_mutex);
    return static_cast<int32_t>(g_entries.size());
}

} // namespace tgs_render
