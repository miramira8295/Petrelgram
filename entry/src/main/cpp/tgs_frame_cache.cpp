#include "tgs_frame_cache.h"

#include <condition_variable>
#include <cstdio>
#include <cstring>
#include <deque>
#include <fcntl.h>
#include <map>
#include <pthread.h>
#include <sys/stat.h>
#include <unistd.h>
#include <zlib.h>

namespace tgs_cache {
namespace {

// 文件排布（小端，按字段逐个读写，不靠结构体对齐）：
//   magic "PGTF" | version u32 | width i32 | height i32 | totalFrames i32 | frameRate f64
//   索引表 totalFrames × (offset u32, size u32)，size = 0 表示这帧还没存
//   之后是追加的 zlib 数据
// 改了排布就把 kVersion +1：文件名里带版本，旧文件自然认不出来、由淘汰清掉。
constexpr uint32_t kMagic = 0x46544750;   // "PGTF"
constexpr uint32_t kVersion = 1;
constexpr size_t kHeaderBytes = 4 + 4 + 4 + 4 + 4 + 8;
constexpr size_t kEntryBytes = 8;
// 真实贴纸 60fps × 3 秒 = 180 帧；留足余量，挡住坏头。
constexpr int32_t kMaxFrames = 2000;
constexpr int32_t kMaxDim = 512;
// 文件超过这个就不再追加（偏移是 u32；正常一张贴纸几 MB）。
constexpr uint64_t kMaxFileBytes = 256ull * 1024 * 1024;
// 后台压缩队列上限：首轮 60fps×3s 最多连续产出 180 帧，留足 192 槽位保证一轮全部落盘。
constexpr size_t kMaxPending = 192;

void PutU32(uint8_t *p, uint32_t v) {
    p[0] = static_cast<uint8_t>(v);
    p[1] = static_cast<uint8_t>(v >> 8);
    p[2] = static_cast<uint8_t>(v >> 16);
    p[3] = static_cast<uint8_t>(v >> 24);
}

uint32_t GetU32(const uint8_t *p) {
    return static_cast<uint32_t>(p[0]) | (static_cast<uint32_t>(p[1]) << 8) |
           (static_cast<uint32_t>(p[2]) << 16) | (static_cast<uint32_t>(p[3]) << 24);
}

bool PreadAll(int fd, uint8_t *buf, size_t len, uint64_t off) {
    size_t done = 0;
    while (done < len) {
        const ssize_t n = pread(fd, buf + done, len - done, static_cast<off_t>(off + done));
        if (n <= 0) {
            return false;
        }
        done += static_cast<size_t>(n);
    }
    return true;
}

bool PwriteAll(int fd, const uint8_t *buf, size_t len, uint64_t off) {
    size_t done = 0;
    while (done < len) {
        const ssize_t n = pwrite(fd, buf + done, len - done, static_cast<off_t>(off + done));
        if (n <= 0) {
            return false;
        }
        done += static_cast<size_t>(n);
    }
    return true;
}

// ── 同一文件只开一份 ─────────────────────────────────────────────────
std::mutex g_registryMutex;
std::map<std::string, std::weak_ptr<FrameCache>> g_registry;

// ── 后台压缩线程 ────────────────────────────────────────────────────
// 压缩（zlib 最快档，256px 一帧约一两毫秒）不放在要帧的那条路上：那条路被 JS 侧
// 排成了一队（util/tgsRenderQueue），多花的每一毫秒都会推迟后面所有贴纸的帧。
struct PutJob {
    std::shared_ptr<FrameCache> cache;
    int32_t frame;
    std::vector<uint8_t> rgba;
};

class Writer {
public:
    static Writer &instance() {
        static Writer writer;
        return writer;
    }

    void Push(PutJob job) {
        {
            std::lock_guard<std::mutex> lock(mutex_);
            if (queue_.size() >= kMaxPending) {
                return;
            }
            queue_.push_back(std::move(job));
        }
        pending_.notify_one();
    }

private:
    Writer() {
        pthread_t thread{};
        if (pthread_create(&thread, nullptr, &Writer::Main, this) == 0) {
            pthread_detach(thread);
        }
    }

    static void *Main(void *arg) {
        pthread_setname_np(pthread_self(), "PgTgsCache");
        static_cast<Writer *>(arg)->Loop();
        return nullptr;
    }

    void Loop() {
        std::vector<uint8_t> packed;
        while (true) {
            PutJob job;
            {
                std::unique_lock<std::mutex> lock(mutex_);
                pending_.wait(lock, [this]() { return !queue_.empty(); });
                job = std::move(queue_.front());
                queue_.pop_front();
            }
            uLongf bound = compressBound(static_cast<uLong>(job.rgba.size()));
            packed.resize(bound);
            if (compress2(packed.data(), &bound, job.rgba.data(), static_cast<uLong>(job.rgba.size()),
                          Z_BEST_SPEED) != Z_OK) {
                continue;
            }
            packed.resize(bound);
            job.cache->Append(job.frame, packed);
        }
    }

    std::mutex mutex_;
    std::condition_variable pending_;
    std::deque<PutJob> queue_;
};

} // namespace

FrameCache::~FrameCache() {
    if (fd_ >= 0) {
        close(fd_);
    }
}

bool FrameCache::LoadHeader() {
    uint8_t head[kHeaderBytes];
    if (!PreadAll(fd_, head, sizeof(head), 0)) {
        return false;
    }
    if (GetU32(head) != kMagic || GetU32(head + 4) != kVersion ||
        static_cast<int32_t>(GetU32(head + 8)) != width_ ||
        static_cast<int32_t>(GetU32(head + 12)) != height_) {
        return false;
    }
    const int32_t total = static_cast<int32_t>(GetU32(head + 16));
    double fps = 0;
    std::memcpy(&fps, head + 20, sizeof(fps));
    if (total <= 0 || total > kMaxFrames || !(fps > 0 && fps <= 240)) {
        return false;
    }
    std::vector<uint8_t> table(static_cast<size_t>(total) * kEntryBytes);
    if (!PreadAll(fd_, table.data(), table.size(), kHeaderBytes)) {
        return false;
    }
    struct stat st {};
    if (fstat(fd_, &st) != 0) {
        return false;
    }
    const uint64_t fileBytes = static_cast<uint64_t>(st.st_size);
    const uint64_t dataStart = kHeaderBytes + table.size();
    const uint64_t maxPacked = static_cast<uint64_t>(width_) * height_ * 4 + 4096;
    offsets_.assign(static_cast<size_t>(total), 0);
    sizes_.assign(static_cast<size_t>(total), 0);
    for (int32_t i = 0; i < total; ++i) {
        const uint32_t off = GetU32(table.data() + i * kEntryBytes);
        const uint32_t size = GetU32(table.data() + i * kEntryBytes + 4);
        // 越界的格子当没存（进程在写数据和写索引之间被杀不会出这种，但坏盘会）。
        if (size == 0 || off < dataStart || size > maxPacked || off + static_cast<uint64_t>(size) > fileBytes) {
            continue;
        }
        offsets_[i] = off;
        sizes_[i] = size;
    }
    totalFrames_ = total;
    frameRate_ = fps;
    end_ = fileBytes < dataStart ? dataStart : fileBytes;
    return true;
}

bool FrameCache::WriteFreshHeader() {
    if (ftruncate(fd_, 0) != 0) {
        return false;
    }
    std::vector<uint8_t> buf(kHeaderBytes + static_cast<size_t>(totalFrames_) * kEntryBytes, 0);
    PutU32(buf.data(), kMagic);
    PutU32(buf.data() + 4, kVersion);
    PutU32(buf.data() + 8, static_cast<uint32_t>(width_));
    PutU32(buf.data() + 12, static_cast<uint32_t>(height_));
    PutU32(buf.data() + 16, static_cast<uint32_t>(totalFrames_));
    std::memcpy(buf.data() + 20, &frameRate_, sizeof(frameRate_));
    if (!PwriteAll(fd_, buf.data(), buf.size(), 0)) {
        return false;
    }
    offsets_.assign(static_cast<size_t>(totalFrames_), 0);
    sizes_.assign(static_cast<size_t>(totalFrames_), 0);
    end_ = buf.size();
    return true;
}

std::shared_ptr<FrameCache> FrameCache::Open(const std::string &path, int32_t width, int32_t height,
                                             int32_t totalFrames, double frameRate, bool create) {
    if (path.empty() || width <= 0 || height <= 0 || width > kMaxDim || height > kMaxDim) {
        return nullptr;
    }
    std::lock_guard<std::mutex> guard(g_registryMutex);
    auto it = g_registry.find(path);
    if (it != g_registry.end()) {
        std::shared_ptr<FrameCache> live = it->second.lock();
        if (live != nullptr) {
            return live;
        }
        g_registry.erase(it);
    }
    const int fd = open(path.c_str(), create ? (O_RDWR | O_CREAT) : O_RDWR, 0600);
    if (fd < 0) {
        return nullptr;
    }
    std::shared_ptr<FrameCache> cache(new FrameCache());
    cache->fd_ = fd;
    cache->width_ = width;
    cache->height_ = height;
    if (!cache->LoadHeader()) {
        if (!create || totalFrames <= 0 || totalFrames > kMaxFrames || !(frameRate > 0)) {
            return nullptr;
        }
        cache->totalFrames_ = totalFrames;
        cache->frameRate_ = frameRate;
        if (!cache->WriteFreshHeader()) {
            return nullptr;
        }
    } else {
        // 淘汰按修改时间挑最老的：命中只读不写，这里摸一下，常用的就不会先被删。
        futimens(fd, nullptr);
    }
    g_registry[path] = cache;
    return cache;
}

int32_t FrameCache::CachedCount() {
    std::lock_guard<std::mutex> lock(mutex_);
    int32_t n = 0;
    for (uint32_t s : sizes_) {
        n += s > 0 ? 1 : 0;
    }
    return n;
}

bool FrameCache::Get(int32_t frame, std::vector<uint8_t> &rgba) {
    uint32_t off = 0;
    uint32_t size = 0;
    {
        std::lock_guard<std::mutex> lock(mutex_);
        if (frame < 0 || frame >= totalFrames_ || sizes_[frame] == 0) {
            return false;
        }
        off = offsets_[frame];
        size = sizes_[frame];
    }
    std::vector<uint8_t> packed(size);
    const size_t want = static_cast<size_t>(width_) * height_ * 4;
    rgba.resize(want);
    uLongf got = static_cast<uLongf>(want);
    if (!PreadAll(fd_, packed.data(), packed.size(), off) ||
        uncompress(rgba.data(), &got, packed.data(), static_cast<uLong>(packed.size())) != Z_OK ||
        got != want) {
        // 读坏了：这格作废，调用方照常去渲，渲完会重新存一份。
        std::lock_guard<std::mutex> lock(mutex_);
        sizes_[frame] = 0;
        offsets_[frame] = 0;
        return false;
    }
    return true;
}

void FrameCache::PutAsync(int32_t frame, std::vector<uint8_t> rgba) {
    {
        std::lock_guard<std::mutex> lock(mutex_);
        if (frame < 0 || frame >= totalFrames_ || sizes_[frame] != 0 || end_ >= kMaxFileBytes) {
            return;
        }
    }
    PutJob job;
    job.cache = shared_from_this();
    job.frame = frame;
    job.rgba = std::move(rgba);
    Writer::instance().Push(std::move(job));
}

void FrameCache::Append(int32_t frame, const std::vector<uint8_t> &packed) {
    std::lock_guard<std::mutex> lock(mutex_);
    if (frame < 0 || frame >= totalFrames_ || sizes_[frame] != 0 || packed.empty() ||
        end_ + packed.size() >= kMaxFileBytes) {
        return;
    }
    const uint64_t off = end_;
    // 先写数据再写索引：中途被杀，索引那格还是 0，等于没存。
    if (!PwriteAll(fd_, packed.data(), packed.size(), off)) {
        return;
    }
    uint8_t entry[kEntryBytes];
    PutU32(entry, static_cast<uint32_t>(off));
    PutU32(entry + 4, static_cast<uint32_t>(packed.size()));
    if (!PwriteAll(fd_, entry, sizeof(entry), kHeaderBytes + static_cast<uint64_t>(frame) * kEntryBytes)) {
        return;
    }
    end_ = off + packed.size();
    offsets_[frame] = static_cast<uint32_t>(off);
    sizes_[frame] = static_cast<uint32_t>(packed.size());
}

namespace {

// 源文件名去掉目录和扩展名，只留安全字符（来自 TDLib，不假设它干净）。
std::string SafeStem(const std::string &sourcePath) {
    const size_t slash = sourcePath.find_last_of('/');
    std::string base = slash == std::string::npos ? sourcePath : sourcePath.substr(slash + 1);
    const size_t dot = base.find_last_of('.');
    if (dot != std::string::npos && dot > 0) {
        base = base.substr(0, dot);
    }
    std::string safe;
    for (char ch : base) {
        const bool ok = (ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z') ||
                        (ch >= '0' && ch <= '9') || ch == '-' || ch == '_';
        safe.push_back(ok ? ch : '_');
    }
    return safe.size() > 64 ? safe.substr(safe.size() - 64) : safe;
}

// FNV-1a 64 位。只用来区分「同一个背景层配了哪几个转轮」，不涉及安全。
uint64_t Fnv1a(const std::string &text) {
    uint64_t hash = 1469598103934665603ull;
    for (unsigned char ch : text) {
        hash ^= ch;
        hash *= 1099511628211ull;
    }
    return hash;
}

} // namespace

std::string FileNameFor(const std::vector<std::string> &sourcePaths, int32_t width, int32_t height) {
    if (sourcePaths.empty()) {
        return "";
    }
    // 带字节数：TDLib 会复用文件名，同名换了内容时长度几乎必然不同，缓存随之失效。
    std::string fingerprint;
    long long firstSize = 0;
    for (size_t i = 0; i < sourcePaths.size(); ++i) {
        struct stat st {};
        if (stat(sourcePaths[i].c_str(), &st) != 0 || st.st_size <= 0) {
            return "";
        }
        if (i == 0) {
            firstSize = static_cast<long long>(st.st_size);
        }
        fingerprint += SafeStem(sourcePaths[i]) + ":" + std::to_string(static_cast<long long>(st.st_size)) + ";";
    }
    char layers[32] = {0};
    if (sourcePaths.size() > 1) {
        snprintf(layers, sizeof(layers), "_m%016llx", static_cast<unsigned long long>(Fnv1a(fingerprint)));
    }
    return SafeStem(sourcePaths[0]) + "_" + std::to_string(firstSize) + layers + "_" + std::to_string(width) + "x" +
           std::to_string(height) + "_v" + std::to_string(kVersion) + ".pgtf";
}

} // namespace tgs_cache
