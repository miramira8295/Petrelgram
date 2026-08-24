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

// 逐帧转成 PixelMap，转完立刻释放那一帧的 RGBA。
// 不先整批转再释放：那样峰值会是两倍，正是这条链路最不能付的代价。
napi_value BuildFrameArray(napi_env env, DecodeTask *task) {
    napi_value array = nullptr;
    napi_create_array_with_length(env, task->frames.size(), &array);
    OH_Pixelmap_InitializationOptions *options = nullptr;
    if (OH_PixelmapInitializationOptions_Create(&options) != IMAGE_SUCCESS || options == nullptr) {
        return nullptr;
    }
    OH_PixelmapInitializationOptions_SetWidth(options, static_cast<uint32_t>(task->dstW));
    OH_PixelmapInitializationOptions_SetHeight(options, static_cast<uint32_t>(task->dstH));
    OH_PixelmapInitializationOptions_SetPixelFormat(options, kPixelFormatRgba8888);
    OH_PixelmapInitializationOptions_SetAlphaType(options, kAlphaTypeUnpremultiplied);
    bool ok = true;
    for (size_t i = 0; i < task->frames.size(); ++i) {
        webm_alpha::RgbaFrame &frame = task->frames[i];
        OH_PixelmapNative *pixelmap = nullptr;
        const Image_ErrorCode code =
            OH_PixelmapNative_CreatePixelmap(frame.data(), frame.size(), options, &pixelmap);
        if (code != IMAGE_SUCCESS || pixelmap == nullptr) {
            ok = false;
            break;
        }
        napi_value jsPixelmap = nullptr;
        const Image_ErrorCode conv =
            OH_PixelmapNative_ConvertPixelmapNativeToNapi(env, pixelmap, &jsPixelmap);
        // 转换出的 JS 对象自己持有一份内部 PixelMap，这个原生壳必须释放，
        // 否则每张贴纸都会把整段帧序列泄在原生侧。
        OH_PixelmapNative_Release(pixelmap);
        if (conv != IMAGE_SUCCESS || jsPixelmap == nullptr) {
            ok = false;
            break;
        }
        napi_set_element(env, array, static_cast<uint32_t>(i), jsPixelmap);
        webm_alpha::RgbaFrame().swap(frame);
    }
    OH_PixelmapInitializationOptions_Release(options);
    return ok ? array : nullptr;
}

void ExecuteDecode(napi_env env, void *data) {
    DecodeTask *task = static_cast<DecodeTask *>(data);
    task->ok = webm_alpha::DecodeAlphaSequence(task->color, task->alpha, task->srcW, task->srcH,
                                               task->dstW, task->dstH, task->frameStep, task->frames);
    // 码流本身不再需要，早一点还回去。
    std::vector<webm_alpha::Packet>().swap(task->color);
    std::vector<webm_alpha::Packet>().swap(task->alpha);
}

void CompleteDecode(napi_env env, napi_status status, void *data) {
    DecodeTask *task = static_cast<DecodeTask *>(data);
    napi_value result = nullptr;
    if (status == napi_ok && task->ok) {
        result = BuildFrameArray(env, task);
    }
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
                               &task->work) != napi_ok ||
        napi_queue_async_work(env, task->work) != napi_ok) {
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
