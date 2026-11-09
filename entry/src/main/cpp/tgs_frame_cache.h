#ifndef PETRELGRAM_TGS_FRAME_CACHE_H
#define PETRELGRAM_TGS_FRAME_CACHE_H

#include <cstdint>
#include <memory>
#include <mutex>
#include <string>
#include <vector>

// TGS 渲好的帧的磁盘缓存（2026-10-10）。
//
// 【为什么需要】rlottie 每帧现场渲：trace 里 tgsRenderFrame 平均 7ms，而且所有 TGS
// 共用一条渲染线程。一屏五张 30fps 就是每秒 150 帧 × 7ms，那条线程被吃满，贴纸
// 只能掉帧；CPU 一直在算，也是发热的一份。渲过的帧压缩存盘，再播时只剩「读 +
// 解压」。
//
// 【和 webm 那份为什么不共用格式】webm 是整段解完一次写盘、顺序读；这里是按帧号
// 随机要帧，哪帧渲过哪帧就落盘，所以文件是「头 + 每帧一格的索引表 + 追加的数据」，
// 读写都按帧号。
//
// 【整段命中不解析 JSON】头里存了总帧数和帧率，打开时文件在就直接用，rlottie 的
// 模型等真遇到没缓存的帧才解析（见 tgs_render.cpp）。
namespace tgs_cache {

class FrameCache : public std::enable_shared_from_this<FrameCache> {
public:
    ~FrameCache();
    FrameCache(const FrameCache &) = delete;
    FrameCache &operator=(const FrameCache &) = delete;

    // 同一个文件进程内只开一份（两处播同一张贴纸，各自追加会互相覆盖）。
    // create = false：文件不在或头对不上就返回 nullptr；
    // create = true ：对不上就清掉重建，totalFrames/frameRate 用传进来的。
    static std::shared_ptr<FrameCache> Open(const std::string &path, int32_t width, int32_t height,
                                            int32_t totalFrames, double frameRate, bool create);

    int32_t TotalFrames() const { return totalFrames_; }
    double FrameRate() const { return frameRate_; }
    int32_t CachedCount();

    // 有这一帧就解压到 rgba（width*height*4，非预乘 RGBA）。读坏了把这格清掉、返回 false。
    bool Get(int32_t frame, std::vector<uint8_t> &rgba);
    // 交给后台线程压缩并追加，调用方不等。队列满了直接丢（下次渲到再存）。
    void PutAsync(int32_t frame, std::vector<uint8_t> rgba);
    // 后台线程用：压好的数据追加进文件、登记索引。
    void Append(int32_t frame, const std::vector<uint8_t> &packed);

private:
    FrameCache() = default;
    bool LoadHeader();
    bool WriteFreshHeader();

    std::mutex mutex_;
    int fd_ = -1;
    int32_t width_ = 0;
    int32_t height_ = 0;
    int32_t totalFrames_ = 0;
    double frameRate_ = 0;
    uint64_t end_ = 0;
    std::vector<uint32_t> offsets_;
    std::vector<uint32_t> sizes_;
};

// 缓存文件名：源文件名 + 字节数 + 渲染尺寸 + 版本；多层（老虎机）再带上全部层的指纹。
// 取不到任何一层的源文件大小返回空串（不缓存）。
std::string FileNameFor(const std::vector<std::string> &sourcePaths, int32_t width, int32_t height);

} // namespace tgs_cache

#endif // PETRELGRAM_TGS_FRAME_CACHE_H
