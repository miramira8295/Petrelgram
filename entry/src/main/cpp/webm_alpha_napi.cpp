#include "webm_alpha_napi.h"

#include <cstring>
#include <new>
#include <hilog/log.h>
#include <multimedia/image_framework/image/pixelmap_native.h>
#include <vector>

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
    // PixelMap 构造是像素级拷贝/格式转换，必须留在 worker：放在 complete 回调里
    // 等于在主线程上一次性做完整段贴纸，真机实测单次 94ms（2026-08-26 trace）。
    OH_Pixelmap_InitializationOptions *options = nullptr;
    if (OH_PixelmapInitializationOptions_Create(&options) != IMAGE_SUCCESS || options == nullptr) {
        task->ok = false;
        return;
    }
    OH_PixelmapInitializationOptions_SetWidth(options, static_cast<uint32_t>(task->dstW));
    OH_PixelmapInitializationOptions_SetHeight(options, static_cast<uint32_t>(task->dstH));
    OH_PixelmapInitializationOptions_SetPixelFormat(options, kPixelFormatRgba8888);
    // **源格式必须显式设，不能只设目标格式。**
    //
    // SetPixelFormat 设的是 PixelMap 建成之后的格式；CreatePixelmap 还要知道
    // 传进去那段缓冲区**本身**是什么格式，才知道要不要转、怎么转。那一项是
    // SetSrcPixelFormat，此前一直没设，于是走了它的默认值——结果是把我们写好的
    // RGBA 当成别的排列去转，红蓝互换。
    //
    // 真机实测（PLA-AL10 / API 26）：贴纸面板里走这条链路的视频贴纸整片偏青，
    // 同屏的静态贴纸正常——青正是暖色调红蓝互换后的样子。而宿主机验证已经证明
    // DecodeAlphaSequence 吐出来的字节是正确的 RGBA（红圆 R=232 G=9 B=7），
    // 所以错位只可能发生在这一步。
    OH_PixelmapInitializationOptions_SetSrcPixelFormat(options, kPixelFormatRgba8888);
    // 行距同理：我们的缓冲区是紧凑排布，一行就是 dstW*4 字节。不说清楚就得
    // 指望它猜对；猜错的表现是每行错开几个像素的斜切。
    OH_PixelmapInitializationOptions_SetRowStride(options,
                                                  static_cast<uint32_t>(task->dstW) * 4);
    OH_PixelmapInitializationOptions_SetAlphaType(options, kAlphaTypeUnpremultiplied);
    task->pixelmaps.reserve(task->frames.size());
    for (size_t i = 0; i < task->frames.size(); ++i) {
        webm_alpha::RgbaFrame &frame = task->frames[i];
        OH_PixelmapNative *pixelmap = nullptr;
        if (OH_PixelmapNative_CreatePixelmap(frame.data(), frame.size(), options, &pixelmap)
                != IMAGE_SUCCESS || pixelmap == nullptr) {
            task->ok = false;
            break;
        }
        task->pixelmaps.push_back(pixelmap);
        // 此刻释放这一帧的源 RGBA 缓冲是安全的：OH_PixelmapNative_CreatePixelmap
        // 返回时像素数据的所有权已经转交给 PixelMap 自己持有的那份拷贝——这是
        // 既有行为已经证明的事实（JS 侧拿到的 PixelMap 在 `delete task` 把
        // task->frames 整段 RGBA 都释放掉之后仍然长期正常显示）。也必须此刻
        // 释放：不释放的话，循环剩余的帧会让「整段 RGBA + 整段 PixelMap」同时
        // 在世，峰值内存直接翻倍。
        webm_alpha::RgbaFrame().swap(frame);
    }
    OH_PixelmapInitializationOptions_Release(options);
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

napi_value WebmAlphaAvailable(napi_env env, napi_callback_info info) {
    napi_value result = nullptr;
    napi_get_boolean(env, webm_alpha::Vp9DecoderAvailable(), &result);
    return result;
}

napi_value WebmAlphaDecode(napi_env env, napi_callback_info info) {
    size_t argc = 9;
    napi_value args[9] = {nullptr};
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
    if (argc < 9) {
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
    const bool parsed =
        SplitPackets(static_cast<const uint8_t *>(colorData), colorDataLen,
                     static_cast<const uint8_t *>(colorLens), colorLensLen, task->color) &&
        SplitPackets(static_cast<const uint8_t *>(alphaData), alphaDataLen,
                     static_cast<const uint8_t *>(alphaLens), alphaLensLen, task->alpha) &&
        ReadInt(env, args[4], task->srcW) && ReadInt(env, args[5], task->srcH) &&
        ReadInt(env, args[6], task->dstW) && ReadInt(env, args[7], task->dstH) &&
        ReadInt(env, args[8], task->frameStep);
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
    };
    napi_define_properties(env, exports, sizeof(desc) / sizeof(desc[0]), desc);
}
