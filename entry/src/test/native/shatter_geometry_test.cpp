#include "../../main/cpp/shatter_geometry.h"
#include <cassert>
#include <fstream>
#include <iostream>
#include <limits>

static void Check(int w, int h, float density, int budget, uint32_t seed) {
    const auto g = shatter::MakeGeometry(w, h, density, budget, seed);
    assert(!g.tiles.empty() && g.tiles.size() <= 15360 && g.tiles.size() <= size_t(budget * 2));
    std::vector<uint8_t> coverage(size_t(w) * h, 0);
    double previousDelay = -1;
    for (const auto &tile : g.tiles) {
        assert(tile.width >= 1 && tile.height >= 1);
        assert(tile.x >= 0 && tile.y >= 0 && tile.x + tile.width <= w && tile.y + tile.height <= h);
        assert(tile.delay >= previousDelay && tile.delay >= 0 && tile.delay <= .82);
        assert(tile.fade >= .55f && tile.fade <= .95f);
        previousDelay = tile.delay;
        for (int y = tile.y; y < tile.y + tile.height; ++y) {
            for (int x = tile.x; x < tile.x + tile.width; ++x) {
                assert(++coverage[y * w + x] == 1); // 每个像素恰好一片：不重叠、不留缝。
            }
        }
        double previousX = tile.x, previousY = tile.y, previousAlpha = 1;
        for (int frame = 0; frame <= 120; ++frame) {
            const double t = frame / 120.0;
            const double scale = 1 - .45 * t;
            const double motion = .35 * t + .65 * t * t;
            const double x = tile.x + tile.width * (1 - scale) / 2 + tile.drift * motion;
            const double y = g.top + tile.y + tile.height * (1 - scale) / 2 - tile.rise * motion;
            const double alpha = std::pow(1 - t, tile.fade);
            assert(x >= 0 && y >= 0 && x + tile.width * scale < g.surfaceWidth);
            assert(y + tile.height * scale < g.surfaceHeight);
            assert(x >= previousX && y <= g.top + previousY && alpha <= previousAlpha);
            previousX = x; previousY = y - g.top; previousAlpha = alpha;
        }
    }
    for (auto count : coverage) { assert(count == 1); }
}

int main(int argc, char **argv) {
    int scenarios = 0;
    for (uint32_t seed = 0; seed < 20; ++seed) {
        for (int budget : {128, 800, 3200, 4000, 8000}) {
            for (const auto &size : {std::pair<int, int>{1200, 216}, {900, 900}, {900, 1800},
                                    {2160, 240}, {1, 96}, {96, 1}, {1, 1}}) {
                Check(size.first, size.second, 3, budget, seed);
                ++scenarios;
            }
        }
    }
    Check(31, 33, .1f, 3200, 1);
    assert(shatter::MakeGeometry(0, 1, 1, 3200, 0).tiles.empty());
    assert(shatter::MakeGeometry(1, 1, std::numeric_limits<float>::quiet_NaN(), 3200, 0).tiles.empty());
    assert(shatter::MakeGeometry(1, 1, 1, 0, 0).tiles.empty());
    // 碎裂波前应持续至动画后段；总时长仍由渲染器保持 1100ms。
    const auto propagation = shatter::MakeGeometry(1200, 216, 3, 3200, 42);
    assert(propagation.tiles.back().delay > .75);
    if (argc > 1) {
        const auto g = shatter::MakeGeometry(400, 100, 1, 3200, 42);
        std::ofstream out(argv[1]);
        out.precision(9);
        out << "{\"width\":" << g.width << ",\"height\":" << g.height
            << ",\"surfaceWidth\":" << g.surfaceWidth << ",\"surfaceHeight\":" << g.surfaceHeight
            << ",\"top\":" << g.top << ",\"tiles\":[";
        for (size_t i = 0; i < g.tiles.size(); ++i) {
            const auto &t = g.tiles[i];
            if (i) { out << ','; }
            out << '[' << t.x << ',' << t.y << ',' << t.width << ',' << t.height << ','
                << t.drift << ',' << t.rise << ',' << t.delay << ',' << t.fade << ']';
        }
        out << "]}";
    }
    std::cout << "Shatter geometry: " << scenarios + 4 << " scenarios passed\n";
}
