#include "webm_alpha_napi.h"

#include <cstring>
#include <new>
#include <hilog/log.h>
#include <multimedia/image_framework/image/pixelmap_native.h>
#include <vector>

#include "sticker_frame_cache.h"
#include "webm_alpha.h"

namespace {

// LOG_DOMAIN / LOG_TAG 是 hilog 的宏名，不能拿来当变量。
constexpr unsigned int kLogDomain = 0x0000;
constexpr const char *kLogTag = "WebmAlpha";
constexpr int32_t kPixelFormatRgba8888 = 3;          // PIXEL_FORMAT_RGBA_8888
constexpr int32_t kAlphaTypeUnpremultiplied = 3;     // PIXELMAP_ALPHA_TYPE_UNPREMULTIPLIED
// 单次调用的包数上限，纯粹是给"参数被算错"兜底；正常贴纸远低于此。
constexpr size_t kMaxPackets = 600;

struct DecodeTask {
    std::vector<webm_alpha::Packet> color;
    std::vector<webm_alpha::Packet> alpha;
    int32_t srcW = 0;
    int32_t srcH = 0;
    int32_t dstW = 0;
    int32_t dstH = 0;
    int32_t frameStep = 1;
    // 解出来之后往这里落一份压缩缓存（空串 = 不缓存）。同时带着时间戳表：
    // 命中缓存那条路不再拆 WebM，时间戳只能从缓存里拿。
    std::string cachePath;
    std::vector<int32_t> timesMs;
    int32_t durationMs = 0;
    std::vector<webm_alpha::RgbaFrame> frames;
    // worker 线程上就建好的原生 PixelMap；complete 回调里只做 napi 转换。
    std::vector<OH_PixelmapNative *> pixelmaps;
    bool ok = false;
    napi_deferred deferred = nullptr;
    napi_async_work work = nullptr;
};

napi_value Undefined(napi_env env) {
    napi_value v = nullptr;
    napi_get_undefined(env, &v);
    return v;
}

bool ReadInt(napi_env env, napi_value value, int32_t &out) {
    return napi_get_value_int32(env, value, &out) == napi_ok;
}

// 把 (拼接后的字节, int32 长度表) 还原成一串包。ArkTS 侧之所以拼成两块
// ArrayBuffer 而不是传数组，是为了只跨一次 NAPI —— 一张贴纸 90 帧、两路，
// 逐包传就是 180 次对象转换。
bool SplitPackets(const uint8_t *data, size_t dataLen, const uint8_t *lens, size_t lensLen,
                  std::vector<webm_alpha::Packet> &out) {
    if (data == nullptr || lens == nullptr || lensLen % sizeof(int32_t) != 0) {
        return false;
    }
    const size_t count = lensLen / sizeof(int32_t);
    if (count == 0 || count > kMaxPackets) {
        return false;
    }
    out.reserve(count);
    size_t offset = 0;
    for (size_t i = 0; i < count; ++i) {
        int32_t len = 0;
        std::memcpy(&len, lens + i * sizeof(int32_t), sizeof(int32_t));
        if (len <= 0 || offset + static_cast<size_t>(len) > dataLen) {
            return false;
        }
        out.emplace_back(data + offset, data + offset + len);
        offset += static_cast<size_t>(len);
    }
    return offset == dataLen;
}

bool ReadString(napi_env env, napi_value value, std::string &out) {
    size_t len = 0;
    if (napi_get_value_string_utf8(env, value, nullptr, 0, &len) != napi_ok) {
        return false;
    }
    out.assign(len, '\0');
    size_t written = 0;
    return napi_get_value_string_utf8(env, value, &out[0], len + 1, &written) == napi_ok;
}

bool ReadArrayBuffer(napi_env env, napi_value value, void **data, size_t *length) {
    bool isBuffer = false;
    if (napi_is_arraybuffer(env, value, &isBuffer) != napi_ok || !isBuffer) {
        return false;
    }
    return napi_get_arraybuffer_info(env, value, data, length) == napi_ok;
}

// 这一步跑在 complete 回调（JS 线程）上，因为 napi 值只能在 JS 线程创建；
// 转完立刻释放原生壳。像素级构造已经挪到 worker 的 ExecuteDecode 里完成。
napi_value BuildFrameArray(napi_env env, DecodeTask *task) {
    napi_value array = nullptr;
    napi_create_array_with_length(env, task->pixelmaps.size(), &array);
    for (size_t i = 0; i < task->pixelmaps.size(); ++i) {
        napi_value jsPixelmap = nullptr;
        const Image_ErrorCode conv =
            OH_PixelmapNative_ConvertPixelmapNativeToNapi(env, task->pixelmaps[i], &jsPixelmap);
        // 转换出的 JS 对象自己持有一份内部 PixelMap，这个原生壳必须释放，
        // 否则每帧漏一个。
        OH_PixelmapNative_Release(task->pixelmaps[i]);
        task->pixelmaps[i] = nullptr;
        if (conv != IMAGE_SUCCESS || jsPixelmap == nullptr) {
            return nullptr;
        }
        napi_set_element(env, array, static_cast<uint32_t>(i), jsPixelmap);
    }
    task->pixelmaps.clear();
    return array;
}

// RGBA 帧 -> 原生 PixelMap。解码与「命中磁盘缓存」两条路共用。
// **跑在 worker 上**：像素级构造放在 complete 回调里就是在主线程上一次性做完
// 整段贴纸，真机实测单次 94ms（2026-08-26 trace）。
bool MakePixelmaps(int32_t dstW, int32_t dstH, std::vector<std::vector<uint8_t>> &frames,
                   std::vector<OH_PixelmapNative *> &out) {
    OH_Pixelmap_InitializationOptions *options = nullptr;
    if (OH_PixelmapInitializationOptions_Create(&options) != IMAGE_SUCCESS || options == nullptr) {
        return false;
    }
    OH_PixelmapInitializationOptions_SetWidth(options, static_cast<uint32_t>(dstW));
    OH_PixelmapInitializationOptions_SetHeight(options, static_cast<uint32_t>(dstH));
    OH_PixelmapInitializationOptions_SetPixelFormat(options, kPixelFormatRgba8888);
    // **源格式必须显式设，不能只设目标格式。**
    //
    // SetPixelFormat 设的是 PixelMap 建成之后的格式；CreatePixelmap 还要知道
    // 传进去那段缓冲区**本身**是什么格式。那一项此前一直没设，走了默认值，
    // 结果把写好的 RGBA 当成别的排列去转——真机上整片偏青（红蓝互换）。
    OH_PixelmapInitializationOptions_SetSrcPixelFormat(options, kPixelFormatRgba8888);
    // 行距同理：缓冲区是紧凑排布，一行就是 dstW*4 字节。猜错的表现是斜切。
    OH_PixelmapInitializationOptions_SetRowStride(options, static_cast<uint32_t>(dstW) * 4);
    OH_PixelmapInitializationOptions_SetAlphaType(options, kAlphaTypeUnpremultiplied);
    bool ok = true;
    out.reserve(frames.size());
    for (size_t i = 0; i < frames.size(); ++i) {
        std::vector<uint8_t> &frame = frames[i];
        OH_PixelmapNative *pixelmap = nullptr;
        if (OH_PixelmapNative_CreatePixelmap(frame.data(), frame.size(), options, &pixelmap)
                != IMAGE_SUCCESS || pixelmap == nullptr) {
            ok = false;
            break;
        }
        out.push_back(pixelmap);
        // 此刻释放源缓冲是安全的（PixelMap 已持有自己那份拷贝），也必须释放：
        // 不释放的话「整段 RGBA + 整段 PixelMap」同时在世，峰值内存翻倍。
        std::vector<uint8_t>().swap(frame);
    }
    OH_PixelmapInitializationOptions_Release(options);
    return ok;
}

void ExecuteDecode(napi_env env, void *data) {
    DecodeTask *task = static_cast<DecodeTask *>(data);
    task->ok = webm_alpha::DecodeAlphaSequence(task->color, task->alpha, task->srcW, task->srcH,
                                               task->dstW, task->dstH, task->frameStep, task->frames);
    // 码流本身不再需要，早一点还回去。
    std::vector<webm_alpha::Packet>().swap(task->color);
    std::vector<webm_alpha::Packet>().swap(task->alpha);
    if (!task->ok) {
        return;
    }
    // 落盘就在这里：再往下几行帧就被 swap 掉换成 PixelMap 了，那之后拿不到
    // 原始 RGBA。写失败不影响本次播放，只是下次还得重解。
    if (!task->cachePath.empty() && task->frames.size() == task->timesMs.size()) {
        sticker_cache::CacheInfo info{task->dstW, task->dstH,
                                      static_cast<int32_t>(task->frames.size()), task->durationMs};
        if (!sticker_cache::Write(task->cachePath, info, task->frames, task->timesMs)) {
            OH_LOG_Print(LOG_APP, LOG_WARN, kLogDomain, kLogTag, "%{public}s", "frame cache write failed");
        }
    }
    if (!MakePixelmaps(task->dstW, task->dstH, task->frames, task->pixelmaps)) {
        task->ok = false;
    }
}

void CompleteDecode(napi_env env, napi_status status, void *data) {
    DecodeTask *task = static_cast<DecodeTask *>(data);
    napi_value result = nullptr;
    if (status == napi_ok && task->ok) {
        result = BuildFrameArray(env, task);
    }
    // worker 上建好但没能交出去的那些，必须在这里释放——BuildFrameArray 中途
    // 失败会留下后半段没转换的。
    for (size_t i = 0; i < task->pixelmaps.size(); ++i) {
        if (task->pixelmaps[i] != nullptr) {
            OH_PixelmapNative_Release(task->pixelmaps[i]);
        }
    }
    task->pixelmaps.clear();
    if (result != nullptr) {
        napi_resolve_deferred(env, task->deferred, result);
    } else {
        // 失败一律 resolve 成空数组而不是 reject：调用方拿到空就回退到
        // ijkplayer，跟"设备不支持"是同一条路，不必区分两种错误处理。
        OH_LOG_Print(LOG_APP, LOG_WARN, kLogDomain, kLogTag, "%{public}s", "decode failed, falling back");
        napi_value empty = nullptr;
        napi_create_array_with_length(env, 0, &empty);
        napi_resolve_deferred(env, task->deferred, empty);
    }
    napi_delete_async_work(env, task->work);
    delete task;
}


// ── 命中磁盘缓存那条路 ───────────────────────────────────────────────
struct LoadTask {
    std::string path;
    int64_t maxBytes = 0;
    sticker_cache::CacheInfo info;
    std::vector<std::vector<uint8_t>> frames;
    std::vector<int32_t> timesMs;
    std::vector<OH_PixelmapNative *> pixelmaps;
    bool ok = false;
    napi_deferred deferred = nullptr;
    napi_async_work work = nullptr;
};

void ExecuteLoad(napi_env env, void *data) {
    LoadTask *task = static_cast<LoadTask *>(data);
    sticker_cache::CacheInfo info{};
    if (!sticker_cache::ReadInfo(task->path, info)) {
        return;   // 没有缓存，或者文件坏了
    }
    // 预算是**解压后**的字节：压缩比再好，进内存的还是整段 RGBA。
    if (task->maxBytes > 0 && sticker_cache::DecodedBytes(info) > task->maxBytes) {
        return;
    }
    if (!sticker_cache::Read(task->path, task->info, task->frames, task->timesMs)) {
        return;
    }
    task->ok = MakePixelmaps(task->info.width, task->info.height, task->frames, task->pixelmaps);
}

void CompleteLoad(napi_env env, napi_status status, void *data) {
    LoadTask *task = static_cast<LoadTask *>(data);
    napi_value result = nullptr;
    if (status == napi_ok && task->ok) {
        napi_value frames = nullptr;
        napi_create_array_with_length(env, task->pixelmaps.size(), &frames);
        bool ok = true;
        for (size_t i = 0; i < task->pixelmaps.size(); ++i) {
            napi_value jsPixelmap = nullptr;
            const Image_ErrorCode conv =
                OH_PixelmapNative_ConvertPixelmapNativeToNapi(env, task->pixelmaps[i], &jsPixelmap);
            OH_PixelmapNative_Release(task->pixelmaps[i]);
            task->pixelmaps[i] = nullptr;
            if (conv != IMAGE_SUCCESS || jsPixelmap == nullptr) {
                ok = false;
                break;
            }
            napi_set_element(env, frames, static_cast<uint32_t>(i), jsPixelmap);
        }
        if (ok) {
            napi_value times = nullptr;
            napi_create_array_with_length(env, task->timesMs.size(), &times);
            for (size_t i = 0; i < task->timesMs.size(); ++i) {
                napi_value v = nullptr;
                napi_create_int32(env, task->timesMs[i], &v);
                napi_set_element(env, times, static_cast<uint32_t>(i), v);
            }
            napi_create_object(env, &result);
            napi_value w = nullptr;
            napi_value h = nullptr;
            napi_value d = nullptr;
            napi_create_int32(env, task->info.width, &w);
            napi_create_int32(env, task->info.height, &h);
            napi_create_int32(env, task->info.durationMs, &d);
            napi_set_named_property(env, result, "frames", frames);
            napi_set_named_property(env, result, "timesMs", times);
            napi_set_named_property(env, result, "width", w);
            napi_set_named_property(env, result, "height", h);
            napi_set_named_property(env, result, "durationMs", d);
        }
    }
    for (size_t i = 0; i < task->pixelmaps.size(); ++i) {
        if (task->pixelmaps[i] != nullptr) {
            OH_PixelmapNative_Release(task->pixelmaps[i]);
        }
    }
    task->pixelmaps.clear();
    if (result == nullptr) {
        // 没命中就是没命中，resolve null——调用方照常去解码，不该当异常处理。
        napi_get_null(env, &result);
    }
    napi_resolve_deferred(env, task->deferred, result);
    napi_delete_async_work(env, task->work);
    delete task;
}

napi_value StickerFramesLoad(napi_env env, napi_callback_info info) {
    size_t argc = 2;
    napi_value args[2] = {nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    napi_value promise = nullptr;
    napi_deferred deferred = nullptr;
    if (napi_create_promise(env, &deferred, &promise) != napi_ok) {
        return Undefined(env);
    }
    auto fail = [&]() -> napi_value {
        napi_value nul = nullptr;
        napi_get_null(env, &nul);
        napi_resolve_deferred(env, deferred, nul);
        return promise;
    };
    if (argc < 2) {
        return fail();
    }
    LoadTask *task = new (std::nothrow) LoadTask();
    if (task == nullptr) {
        return fail();
    }
    double maxBytes = 0;
    if (!ReadString(env, args[0], task->path) ||
        napi_get_value_double(env, args[1], &maxBytes) != napi_ok) {
        delete task;
        return fail();
    }
    task->maxBytes = static_cast<int64_t>(maxBytes);
    task->deferred = deferred;
    napi_value name = nullptr;
    napi_create_string_utf8(env, "stickerFramesLoad", NAPI_AUTO_LENGTH, &name);
    if (napi_create_async_work(env, nullptr, name, ExecuteLoad, CompleteLoad, task, &task->work)
            != napi_ok) {
        delete task;
        return fail();
    }
    if (napi_queue_async_work(env, task->work) != napi_ok) {
        napi_delete_async_work(env, task->work);
        task->work = nullptr;
        delete task;
        return fail();
    }
    return promise;
}

napi_value WebmAlphaAvailable(napi_env env, napi_callback_info info) {
    napi_value result = nullptr;
    napi_get_boolean(env, webm_alpha::Vp9DecoderAvailable(), &result);
    return result;
}

napi_value WebmAlphaDecode(napi_env env, napi_callback_info info) {
    size_t argc = 12;
    napi_value args[12] = {nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    napi_value promise = nullptr;
    napi_deferred deferred = nullptr;
    if (napi_create_promise(env, &deferred, &promise) != napi_ok) {
        return Undefined(env);
    }
    auto fail = [&]() -> napi_value {
        napi_value empty = nullptr;
        napi_create_array_with_length(env, 0, &empty);
        napi_resolve_deferred(env, deferred, empty);
        return promise;
    };
    if (argc < 12) {
        return fail();
    }
    void *colorData = nullptr;
    void *colorLens = nullptr;
    void *alphaData = nullptr;
    void *alphaLens = nullptr;
    size_t colorDataLen = 0;
    size_t colorLensLen = 0;
    size_t alphaDataLen = 0;
    size_t alphaLensLen = 0;
    if (!ReadArrayBuffer(env, args[0], &colorData, &colorDataLen) ||
        !ReadArrayBuffer(env, args[1], &colorLens, &colorLensLen) ||
        !ReadArrayBuffer(env, args[2], &alphaData, &alphaDataLen) ||
        !ReadArrayBuffer(env, args[3], &alphaLens, &alphaLensLen)) {
        return fail();
    }
    DecodeTask *task = new (std::nothrow) DecodeTask();
    if (task == nullptr) {
        return fail();
    }
    // 在同步段就把字节复制走：异步线程跑起来之后，ArrayBuffer 的
    // 生命周期不再由这里控制。贴纸码流只有几十 KB，复制的代价可以忽略。
    // alpha 两块都为空 = 不透明贴纸，走同一条链路但不解 alpha 那一路
    // （见 webm_alpha.cpp 里 opaque 那段）。
    const bool opaque = alphaDataLen == 0 && alphaLensLen == 0;
    const bool parsed =
        SplitPackets(static_cast<const uint8_t *>(colorData), colorDataLen,
                     static_cast<const uint8_t *>(colorLens), colorLensLen, task->color) &&
        (opaque || SplitPackets(static_cast<const uint8_t *>(alphaData), alphaDataLen,
                                static_cast<const uint8_t *>(alphaLens), alphaLensLen,
                                task->alpha)) &&
        ReadInt(env, args[4], task->srcW) && ReadInt(env, args[5], task->srcH) &&
        ReadInt(env, args[6], task->dstW) && ReadInt(env, args[7], task->dstH) &&
        ReadInt(env, args[8], task->frameStep) && ReadInt(env, args[11], task->durationMs);
    // 缓存路径与时间戳表都是可选的：任一取不到就只当"这次不缓存"，
    // 不能连解码一起失败。
    if (parsed) {
        std::string cachePath;
        if (ReadString(env, args[9], cachePath)) {
            task->cachePath = cachePath;
        }
        void *timesData = nullptr;
        size_t timesLen = 0;
        if (ReadArrayBuffer(env, args[10], &timesData, &timesLen) &&
            timesLen % sizeof(int32_t) == 0 && timesLen > 0) {
            const size_t count = timesLen / sizeof(int32_t);
            task->timesMs.resize(count);
            std::memcpy(task->timesMs.data(), timesData, timesLen);
        } else {
            task->cachePath.clear();   // 没有时间戳表就别写半份缓存
        }
    }
    if (!parsed) {
        delete task;
        return fail();
    }
    task->deferred = deferred;
    napi_value name = nullptr;
    napi_create_string_utf8(env, "webmAlphaDecode", NAPI_AUTO_LENGTH, &name);
    if (napi_create_async_work(env, nullptr, name, ExecuteDecode, CompleteDecode, task,
                               &task->work) != napi_ok) {
        delete task;
        return fail();
    }
    if (napi_queue_async_work(env, task->work) != napi_ok) {
        napi_delete_async_work(env, task->work);
        task->work = nullptr;
        delete task;
        return fail();
    }
    return promise;
}

} // namespace

void WebmAlphaRegister(napi_env env, napi_value exports) {
    napi_property_descriptor desc[] = {
        {"webmAlphaAvailable", nullptr, WebmAlphaAvailable, nullptr, nullptr, nullptr, napi_default,
         nullptr},
        {"webmAlphaDecode", nullptr, WebmAlphaDecode, nullptr, nullptr, nullptr, napi_default,
         nullptr},
        {"stickerFramesLoad", nullptr, StickerFramesLoad, nullptr, nullptr, nullptr, napi_default,
         nullptr},
    };
    napi_define_properties(env, exports, sizeof(desc) / sizeof(desc[0]), desc);
}
