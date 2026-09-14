#include "tgs_render.h"

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

namespace tgs_render {
namespace {

constexpr unsigned int kLogDomain = 0x0000;
constexpr const char *kLogTag = "TgsRender";
// .tgs 是几十 KB，解压后的 JSON 实测中位 147KB、最大 381KB。留足余量，
// 同时挡住"这不是贴纸"的文件。
constexpr size_t kMaxCompressedBytes = 4u * 1024 * 1024;
constexpr size_t kMaxJsonBytes = 32u * 1024 * 1024;
constexpr int32_t kMaxDim = 512;

struct Entry {
    std::unique_ptr<rlottie::Animation> animation;
    int32_t width = 0;
    int32_t height = 0;
    // rlottie 要的是 uint32 的画布；复用同一块，免得每帧一次分配/释放。
    std::vector<uint32_t> canvas;
};

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

} // namespace

AnimationInfo Open(const std::string &path, int32_t width, int32_t height) {
    AnimationInfo info;
    if (width <= 0 || height <= 0 || width > kMaxDim || height > kMaxDim) {
        return info;
    }
    std::vector<uint8_t> raw;
    if (!ReadWholeFile(path, raw)) {
        return info;
    }
    std::string json;
    if (!Gunzip(raw, json)) {
        return info;
    }
    // 第二个参数是 rlottie 自己的模型缓存键：同一张贴纸在多处播放时只解析一次
    // JSON。用文件路径当键正合适。
    std::unique_ptr<rlottie::Animation> animation;
    RenderThread::instance().Run([&animation, &json, &path]() {
        animation = rlottie::Animation::loadFromData(std::move(json), path);
    });
    if (!animation) {
        OH_LOG_Print(LOG_APP, LOG_WARN, kLogDomain, kLogTag, "%{public}s", "parse failed");
        return info;
    }
    auto entry = std::make_shared<Entry>();
    entry->width = width;
    entry->height = height;
    entry->canvas.assign(static_cast<size_t>(width) * height, 0);
    info.totalFrames = static_cast<int32_t>(animation->totalFrame());
    info.frameRate = animation->frameRate();
    info.width = width;
    info.height = height;
    entry->animation = std::move(animation);
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
    if (entry == nullptr || frameIndex < 0) {
        return false;
    }
    const size_t total = entry->animation->totalFrame();
    if (total == 0) {
        return false;
    }
    const size_t frame = static_cast<size_t>(frameIndex) % total;
    RenderThread::instance().Run([&entry, frame]() {
        rlottie::Surface surface(entry->canvas.data(), static_cast<size_t>(entry->width),
                                 static_cast<size_t>(entry->height),
                                 static_cast<size_t>(entry->width) * 4);
        entry->animation->renderSync(frame, surface);
    });
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
    width = entry->width;
    height = entry->height;
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
