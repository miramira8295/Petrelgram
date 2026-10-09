#ifndef PETRELGRAM_STICKER_FRAME_CACHE_H
#define PETRELGRAM_STICKER_FRAME_CACHE_H

#include <cstdint>
#include <cstdio>
#include <string>
#include <vector>

// 解码结果的磁盘缓存。
//
// 【为什么需要】这条链路把整段贴纸预解码成 RGBA 帧驻留内存，而内存预算只有
// 32MiB、单段上限 12MiB——同时只驻留得下两三段。贴纸面板一屏几十张，LRU 一抖
// 就得重新走一遍「读文件 → 拆 WebM → libvpx 逐帧软解」。缓存到磁盘之后，第二
// 次起只剩「读文件 → 解压」，省掉的正是最贵的那段。
//
// 【为什么必须压缩】解码后的帧是裸 RGBA：256×256×4×90 帧 = 23MB 一张。原样
// 落盘，几十张贴纸就是几个 GB。贴纸画面大片全透明、色块平坦，zlib 即便在最快
// 档也能压到个位数百分比。压缩发生在 worker 线程上，不占 UI。
namespace sticker_cache {

struct CacheInfo {
    int32_t width = 0;
    int32_t height = 0;
    int32_t frameCount = 0;
    int32_t durationMs = 0;
};

// 解出来的字节数（= w*h*4*frames）。调用方据此判断放不放得进内存预算。
int64_t DecodedBytes(const CacheInfo &info);

// 只读头部：拿尺寸/帧数，不碰像素。
bool ReadInfo(const std::string &path, CacheInfo &info);

// 压一帧（zlib 最快档）。边解边压：解码线程解出一帧就压好留着，整段解完再一次
// 写盘，用不着把整段裸 RGBA 攒在内存里。
bool CompressFrame(const std::vector<uint8_t> &rgba, std::vector<uint8_t> &packed);

// 把已经压好的帧写成一份缓存。先写临时文件再改名——半截的缓存文件比没有更糟。
bool WritePacked(const std::string &path, const CacheInfo &info,
                 const std::vector<std::vector<uint8_t>> &packed, const std::vector<int32_t> &timesMs);

// 逐帧读（命中缓存也边读边播：读出第一帧就能开始画，不等整段解压完）。
class Reader {
public:
    Reader() = default;
    ~Reader();
    Reader(const Reader &) = delete;
    Reader &operator=(const Reader &) = delete;

    // 读头部、时间戳表、每帧长度表。文件不在或头部不对返回 false。
    bool Open(const std::string &path);
    const CacheInfo &Info() const { return info_; }
    const std::vector<int32_t> &TimesMs() const { return timesMs_; }
    // 解出下一帧（width*height*4 的非预乘 RGBA）。读坏了返回 false。
    bool Next(std::vector<uint8_t> &rgba);
    bool Done() const { return next_ >= sizes_.size(); }

private:
    FILE *file_ = nullptr;
    CacheInfo info_{};
    std::vector<int32_t> timesMs_;
    std::vector<int32_t> sizes_;
    std::vector<uint8_t> packed_;
    size_t next_ = 0;
};

} // namespace sticker_cache

#endif // PETRELGRAM_STICKER_FRAME_CACHE_H
