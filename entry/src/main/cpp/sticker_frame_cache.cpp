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
// v2（2026-10-10）：头部多一个 bytesPerPixel（不透明贴纸存 RGB565）。v1 文件一律当没有缓存。
constexpr uint32_t kVersion = 2;
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
    int32_t bytesPerPixel;
};

bool HeaderSane(const Header &h) {
    return h.magic == kMagic && h.version == kVersion &&
           h.width > 0 && h.width <= kMaxDim && h.height > 0 && h.height <= kMaxDim &&
           h.frameCount > 0 && h.frameCount <= kMaxFrames && h.durationMs >= 0 &&
           (h.bytesPerPixel == 2 || h.bytesPerPixel == 4);
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
    return static_cast<int64_t>(info.width) * info.height * info.bytesPerPixel * info.frameCount;
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
    info.bytesPerPixel = h.bytesPerPixel;
    return true;
}

bool CompressFrame(const std::vector<uint8_t> &rgba, std::vector<uint8_t> &packed) {
    uLongf bound = compressBound(static_cast<uLong>(rgba.size()));
    packed.resize(bound);
    // Z_BEST_SPEED：这一步跑在解码线程上、夹在两帧之间，压缩比再高也换不来
    // 什么——贴纸大片透明，最快档已经能压到几个百分点。
    if (compress2(packed.data(), &bound, rgba.data(), static_cast<uLong>(rgba.size()),
                  Z_BEST_SPEED) != Z_OK) {
        packed.clear();
        return false;
    }
    packed.resize(bound);
    return true;
}

bool WritePacked(const std::string &path, const CacheInfo &info,
                 const std::vector<std::vector<uint8_t>> &packed, const std::vector<int32_t> &timesMs) {
    if (packed.empty() || packed.size() != timesMs.size() ||
        static_cast<int32_t>(packed.size()) != info.frameCount) {
        return false;
    }
    Header h{kMagic, kVersion, info.width, info.height, info.frameCount, info.durationMs, info.bytesPerPixel};
    if (!HeaderSane(h)) {
        return false;
    }
    std::vector<int32_t> sizes;
    sizes.reserve(packed.size());
    for (const std::vector<uint8_t> &frame : packed) {
        if (frame.empty()) {
            return false;
        }
        sizes.push_back(static_cast<int32_t>(frame.size()));
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

Reader::~Reader() {
    if (file_ != nullptr) {
        fclose(file_);
    }
}

bool Reader::Open(const std::string &path) {
    file_ = fopen(path.c_str(), "rb");
    if (file_ == nullptr) {
        return false;
    }
    Header h{};
    if (!ReadExact(file_, &h, sizeof(h)) || !HeaderSane(h)) {
        return false;
    }
    const size_t count = static_cast<size_t>(h.frameCount);
    timesMs_.assign(count, 0);
    sizes_.assign(count, 0);
    if (!ReadExact(file_, timesMs_.data(), count * sizeof(int32_t)) ||
        !ReadExact(file_, sizes_.data(), count * sizeof(int32_t))) {
        return false;
    }
    info_.width = h.width;
    info_.height = h.height;
    info_.frameCount = h.frameCount;
    info_.durationMs = h.durationMs;
    info_.bytesPerPixel = h.bytesPerPixel;
    return true;
}

bool Reader::Next(std::vector<uint8_t> &rgba) {
    if (file_ == nullptr || next_ >= sizes_.size()) {
        return false;
    }
    const int32_t size = sizes_[next_++];
    if (size <= 0) {
        return false;
    }
    packed_.resize(static_cast<size_t>(size));
    if (!ReadExact(file_, packed_.data(), packed_.size())) {
        return false;
    }
    const size_t frameBytes = static_cast<size_t>(info_.width) * info_.height * info_.bytesPerPixel;
    rgba.resize(frameBytes);
    uLongf out = static_cast<uLongf>(frameBytes);
    return uncompress(rgba.data(), &out, packed_.data(), static_cast<uLong>(packed_.size())) == Z_OK &&
           out == frameBytes;
}

} // namespace sticker_cache
