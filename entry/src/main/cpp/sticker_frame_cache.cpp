#include "sticker_frame_cache.h"

#include <cstdio>
#include <cstring>
#include <hilog/log.h>
#include <zlib.h>

namespace sticker_cache {
namespace {

constexpr unsigned int kLogDomain = 0x0000;
constexpr const char *kLogTag = "StickerCache";
constexpr uint32_t kMagic = 0x46534750;   // 'PGSF'
constexpr uint32_t kVersion = 1;
// 兜底上限，防止读到损坏/被篡改的头部之后去分配一个荒唐的缓冲区。
constexpr int32_t kMaxDim = 512;
constexpr int32_t kMaxFrames = 600;

struct Header {
    uint32_t magic;
    uint32_t version;
    int32_t width;
    int32_t height;
    int32_t frameCount;
    int32_t durationMs;
};

bool HeaderSane(const Header &h) {
    return h.magic == kMagic && h.version == kVersion &&
           h.width > 0 && h.width <= kMaxDim && h.height > 0 && h.height <= kMaxDim &&
           h.frameCount > 0 && h.frameCount <= kMaxFrames && h.durationMs >= 0;
}

struct FileCloser {
    FILE *f;
    ~FileCloser() {
        if (f != nullptr) {
            fclose(f);
        }
    }
};

bool ReadExact(FILE *f, void *dst, size_t bytes) {
    return fread(dst, 1, bytes, f) == bytes;
}

} // namespace

int64_t DecodedBytes(const CacheInfo &info) {
    return static_cast<int64_t>(info.width) * info.height * 4 * info.frameCount;
}

bool ReadInfo(const std::string &path, CacheInfo &info) {
    FILE *f = fopen(path.c_str(), "rb");
    if (f == nullptr) {
        return false;
    }
    FileCloser closer{f};
    Header h{};
    if (!ReadExact(f, &h, sizeof(h)) || !HeaderSane(h)) {
        return false;
    }
    info.width = h.width;
    info.height = h.height;
    info.frameCount = h.frameCount;
    info.durationMs = h.durationMs;
    return true;
}

bool Read(const std::string &path, CacheInfo &info, std::vector<std::vector<uint8_t>> &frames,
          std::vector<int32_t> &timesMs) {
    FILE *f = fopen(path.c_str(), "rb");
    if (f == nullptr) {
        return false;
    }
    FileCloser closer{f};
    Header h{};
    if (!ReadExact(f, &h, sizeof(h)) || !HeaderSane(h)) {
        return false;
    }
    const size_t count = static_cast<size_t>(h.frameCount);
    timesMs.assign(count, 0);
    if (!ReadExact(f, timesMs.data(), count * sizeof(int32_t))) {
        return false;
    }
    std::vector<int32_t> sizes(count, 0);
    if (!ReadExact(f, sizes.data(), count * sizeof(int32_t))) {
        return false;
    }
    const size_t frameBytes = static_cast<size_t>(h.width) * h.height * 4;
    frames.clear();
    frames.reserve(count);
    std::vector<uint8_t> packed;
    for (size_t i = 0; i < count; ++i) {
        if (sizes[i] <= 0) {
            return false;
        }
        packed.resize(static_cast<size_t>(sizes[i]));
        if (!ReadExact(f, packed.data(), packed.size())) {
            return false;
        }
        std::vector<uint8_t> frame(frameBytes);
        uLongf out = static_cast<uLongf>(frameBytes);
        if (uncompress(frame.data(), &out, packed.data(),
                       static_cast<uLong>(packed.size())) != Z_OK || out != frameBytes) {
            return false;
        }
        frames.push_back(std::move(frame));
    }
    info.width = h.width;
    info.height = h.height;
    info.frameCount = h.frameCount;
    info.durationMs = h.durationMs;
    return true;
}

bool Write(const std::string &path, const CacheInfo &info,
           const std::vector<std::vector<uint8_t>> &frames, const std::vector<int32_t> &timesMs) {
    if (frames.empty() || frames.size() != timesMs.size() ||
        static_cast<int32_t>(frames.size()) != info.frameCount) {
        return false;
    }
    Header h{kMagic, kVersion, info.width, info.height, info.frameCount, info.durationMs};
    if (!HeaderSane(h)) {
        return false;
    }
    const size_t frameBytes = static_cast<size_t>(info.width) * info.height * 4;
    // 先压缩到内存，再一次写出：压缩中途失败就不该在磁盘上留下任何东西。
    std::vector<std::vector<uint8_t>> packed;
    packed.reserve(frames.size());
    std::vector<int32_t> sizes;
    sizes.reserve(frames.size());
    for (const std::vector<uint8_t> &frame : frames) {
        if (frame.size() != frameBytes) {
            return false;
        }
        uLongf bound = compressBound(static_cast<uLong>(frameBytes));
        std::vector<uint8_t> out(bound);
        // Z_BEST_SPEED：这一步在 worker 上串在解码后面，压缩比再高也换不来
        // 什么——贴纸大片透明，最快档已经能压到几个百分点。
        if (compress2(out.data(), &bound, frame.data(), static_cast<uLong>(frameBytes),
                      Z_BEST_SPEED) != Z_OK) {
            return false;
        }
        out.resize(bound);
        sizes.push_back(static_cast<int32_t>(out.size()));
        packed.push_back(std::move(out));
    }
    const std::string tmp = path + ".tmp";
    FILE *f = fopen(tmp.c_str(), "wb");
    if (f == nullptr) {
        OH_LOG_Print(LOG_APP, LOG_WARN, kLogDomain, kLogTag, "%{public}s", "cache open failed");
        return false;
    }
    bool ok = fwrite(&h, 1, sizeof(h), f) == sizeof(h) &&
              fwrite(timesMs.data(), 1, timesMs.size() * sizeof(int32_t), f) ==
                  timesMs.size() * sizeof(int32_t) &&
              fwrite(sizes.data(), 1, sizes.size() * sizeof(int32_t), f) ==
                  sizes.size() * sizeof(int32_t);
    for (size_t i = 0; ok && i < packed.size(); ++i) {
        ok = fwrite(packed[i].data(), 1, packed[i].size(), f) == packed[i].size();
    }
    fclose(f);
    if (!ok || rename(tmp.c_str(), path.c_str()) != 0) {
        remove(tmp.c_str());
        return false;
    }
    return true;
}

} // namespace sticker_cache
