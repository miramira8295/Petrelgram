#ifndef PETRELGRAM_SHATTER_GEOMETRY_H
#define PETRELGRAM_SHATTER_GEOMETRY_H

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <random>
#include <vector>

namespace shatter {
// 两个 vec4，生成后直接作为 GPU instance buffer；动画中不再改写。
struct Tile {
    float x, y, width, height;
    float drift, rise, delay, fade;
};

struct Geometry {
    int width = 0, height = 0;
    int surfaceWidth = 0, surfaceHeight = 0, top = 0;
    int bufferWidth = 0, bufferHeight = 0;
    std::vector<Tile> tiles;
};

// Sorted once during preparation. No per-particle CPU animation/update/upload.
inline size_t StartedTileCount(const std::vector<float> &delays, float progress) {
    return std::lower_bound(delays.begin(), delays.end(), progress) - delays.begin();
}

// 与原 Canvas 随机二分、波前和运动参数一致。seed 仅用于可重复的宿主验证。
inline Geometry MakeGeometry(int width, int height, float density, int budget, uint32_t seed) {
    Geometry result;
    if (width <= 0 || height <= 0 || !std::isfinite(density) || density <= 0 || budget <= 0) {
        return result;
    }
    result.width = width;
    result.height = height;
    std::mt19937 random(seed);
    auto unit = [&]() { return std::generate_canonical<double, 32>(random); };
    const size_t limit = std::min(budget, 8000);
    const double target = std::max(1.0, std::max(2.475 * density,
        std::sqrt(2.0 * width * height / limit)));
    struct Region { int x, y, w, h; };
    std::vector<Region> pending{{0, 0, width, height}};
    // Breadth first keeps fragments balanced at the strict budget. At most
    // 2*limit-1 regions, one linear pass, no shifting/splicing a queue.
    size_t next = 0;
    while (next < pending.size()) {
        const auto r = pending[next++];
        if ((r.w > target || r.h > target) &&
            result.tiles.size() + pending.size() - next + 1 < limit) {
            const bool vertical = r.w > target && (r.h <= target || r.w * (0.7 + unit() * 0.6) > r.h);
            const double ratio = 0.36 + unit() * 0.28;
            if (vertical) {
                const int cut = std::max(1, std::min(r.w - 1, int(std::round(r.w * ratio))));
                pending.push_back({r.x, r.y, cut, r.h});
                pending.push_back({r.x + cut, r.y, r.w - cut, r.h});
            } else {
                const int cut = std::max(1, std::min(r.h - 1, int(std::round(r.h * ratio))));
                pending.push_back({r.x, r.y, r.w, cut});
                pending.push_back({r.x, r.y + cut, r.w, r.h - cut});
            }
            continue;
        }
        const double right = 1 - (r.x + r.w / 2.0) / width;
        const double top = (r.y + r.h / 2.0) / height;
        const double delay = std::max(0.0, std::min(0.82,
            std::sqrt(right * right + top * top) / std::sqrt(2.0) * 0.8 + (unit() - 0.5) * 0.035));
        const float drift = density * (70 + right * 150 + unit() * 24);
        const float rise = density * (100 + unit() * 140);
        const float fade = 0.55 + unit() * 0.4;
        result.tiles.push_back({float(r.x), float(r.y), float(r.w), float(r.h),
            drift, rise, float(delay), fade});
    }
    std::stable_sort(result.tiles.begin(), result.tiles.end(),
        [](const Tile &a, const Tile &b) { return a.delay < b.delay; });
    double rightEdge = width, topEdge = 0;
    for (const auto &t : result.tiles) {
        // 右边界为凸函数、上边界为凹函数：极值在运动的两个端点。
        rightEdge = std::max(rightEdge, t.x + 0.775 * t.width + t.drift);
        topEdge = std::min(topEdge, t.y + 0.225 * t.height - t.rise);
    }
    result.top = int(std::ceil(-topEdge)) + 1; // 留 1px 抗锯齿余量，不缩放截图。
    result.surfaceWidth = int(std::ceil(rightEdge)) + 1;
    result.surfaceHeight = height + result.top + 1;
    // Keep original layout/texture coordinates. Only the transient animated
    // buffer uses <=2px/vp and <=1M pixels; static chat remains full-resolution.
    const double scale = std::min({1.0, 2.0 / density,
        std::sqrt(1048576.0 / (double(result.surfaceWidth) * result.surfaceHeight))});
    result.bufferWidth = std::max(1, int(std::floor(result.surfaceWidth * scale)));
    result.bufferHeight = std::max(1, int(std::floor(result.surfaceHeight * scale)));
    return result;
}
} // namespace shatter
#endif
