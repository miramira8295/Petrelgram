// 测试平台 GetImageInfo 的真实字段语义：alphaMode 被填充，旧 alphaType 留默认 0。
// test-shatter-pixels.py 注入产品的 PreparePixelsImpl，避免另写一份被测逻辑。
#include "shatter_geometry.h"
#include <atomic>
#include <cassert>
#include <chrono>
#include <cstring>
#include <iostream>
#include <memory>
using Clock = std::chrono::steady_clock;
using shatter::MakeGeometry;
constexpr int IMAGE_SUCCESS = 0;
constexpr int PIXEL_FORMAT_RGBA_8888 = 3, PIXEL_FORMAT_BGRA_8888 = 4;
constexpr int PIXELMAP_ALPHA_TYPE_OPAQUE = 1, PIXELMAP_ALPHA_TYPE_PREMULTIPLIED = 2;
constexpr int PIXELMAP_ALPHA_TYPE_UNPREMULTIPLIED = 3;
constexpr int LOG_APP = 0, LOG_WARN = 0;
void OH_LOG_Print(int, int, int, const char *, const char *, ...) {}
struct OH_Pixelmap_ImageInfo {
    uint32_t width = 2, height = 2, stride = 12;
    int format = PIXEL_FORMAT_RGBA_8888, alphaMode = PIXELMAP_ALPHA_TYPE_PREMULTIPLIED, alphaType = 0;
};
struct OH_PixelmapNative {
    OH_Pixelmap_ImageInfo info;
    // 两行各有 4 字节 padding。
    std::vector<uint8_t> bytes{100, 50, 25, 128, 20, 30, 40, 255, 99, 99, 99, 99,
                               9, 8, 7, 64, 1, 2, 3, 255, 99, 99, 99, 99};
    bool lockFails = false, locked = false;
};
int OH_PixelmapImageInfo_Create(OH_Pixelmap_ImageInfo **info) { *info = new OH_Pixelmap_ImageInfo(); return 0; }
int OH_PixelmapNative_GetImageInfo(OH_PixelmapNative *pixels, OH_Pixelmap_ImageInfo *info) { *info = pixels->info; return 0; }
int OH_PixelmapImageInfo_GetWidth(OH_Pixelmap_ImageInfo *info, uint32_t *v) { *v = info->width; return 0; }
int OH_PixelmapImageInfo_GetHeight(OH_Pixelmap_ImageInfo *info, uint32_t *v) { *v = info->height; return 0; }
int OH_PixelmapImageInfo_GetRowStride(OH_Pixelmap_ImageInfo *info, uint32_t *v) { *v = info->stride; return 0; }
int OH_PixelmapImageInfo_GetPixelFormat(OH_Pixelmap_ImageInfo *info, int *v) { *v = info->format; return 0; }
int OH_PixelmapImageInfo_GetAlphaMode(OH_Pixelmap_ImageInfo *info, int *v) { *v = info->alphaMode; return 0; }
int OH_PixelmapImageInfo_GetAlphaType(OH_Pixelmap_ImageInfo *info, int *v) { *v = info->alphaType; return 0; }
void OH_PixelmapImageInfo_Release(OH_Pixelmap_ImageInfo *info) { delete info; }
int OH_PixelmapNative_AccessPixels(OH_PixelmapNative *pixels, void **address) {
    if (pixels->lockFails) { return 1; }
    pixels->locked = true; *address = pixels->bytes.data(); return 0;
}
void OH_PixelmapNative_UnaccessPixels(OH_PixelmapNative *pixels) { pixels->locked = false; }
struct Scene { std::vector<uint8_t> pixels; shatter::Geometry geometry; };
struct PrepareTask {
    OH_PixelmapNative *pixelmap = nullptr;
    float density = 3.5;
    int budget = 3200;
    bool ok = false;
    std::shared_ptr<Scene> scene = std::make_shared<Scene>();
};
#include "shatter_pixels_impl.inc"

static PrepareTask Run(OH_PixelmapNative &pixels) {
    PrepareTask task;
    task.pixelmap = &pixels;
    PreparePixelsImpl(&task);
    assert(!pixels.locked);
    return task;
}
int main() {
    OH_PixelmapNative pixels;
    auto task = Run(pixels);
    assert(task.ok); // 回归点：alphaType=0 不能把有效截图当作失败。
    assert(task.scene->pixels == std::vector<uint8_t>({100,50,25,128,20,30,40,255,9,8,7,64,1,2,3,255}));
    pixels.info.format = PIXEL_FORMAT_BGRA_8888;
    task = Run(pixels);
    assert(task.ok && task.scene->pixels[0] == 25 && task.scene->pixels[2] == 100);
    pixels.info.alphaMode = PIXELMAP_ALPHA_TYPE_UNPREMULTIPLIED;
    task = Run(pixels);
    assert(task.ok && task.scene->pixels[0] == 13 && task.scene->pixels[1] == 25 && task.scene->pixels[2] == 50);
    pixels.info.alphaMode = PIXELMAP_ALPHA_TYPE_OPAQUE;
    task = Run(pixels);
    assert(task.ok && task.scene->pixels[0] == 25 && task.scene->pixels[3] == 255);
    pixels.info.format = 7;
    assert(!Run(pixels).ok);
    pixels.info.format = PIXEL_FORMAT_RGBA_8888;
    pixels.lockFails = true;
    assert(!Run(pixels).ok);
    pixels.lockFails = false;
    pixels.info.stride = 4;
    assert(!Run(pixels).ok);
    std::cout << "Shatter native pixels: 7 scenarios passed\n";
}
