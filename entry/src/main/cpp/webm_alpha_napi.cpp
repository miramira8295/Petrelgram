#include "webm_alpha_napi.h"

#include <cstring>
#include <new>
#include <hilog/log.h>
#include <multimedia/image_framework/image/pixelmap_native.h>
#include <vector>

#include "sticker_decode_queue.h"
#include "sticker_frame_cache.h"
#include "webm_alpha.h"

namespace {

// LOG_DOMAIN / LOG_TAG 是 hilog 的宏名，不能拿来当变量。
constexpr unsigned int kLogDomain = 0x0000;
constexpr const char *kLogTag = "WebmAlpha";
// 单次调用的包数上限，纯粹是给"参数被算错"兜底；正常贴纸远低于此。
constexpr size_t kMaxPackets = 600;

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

// ── 边解边播：线程安全函数把每一批帧送回 JS 线程 ───────────────────────
//
// 解码线程（sticker_decode_queue）每交出一批，就经 napi 线程安全函数排到 JS 线程，
// 在这里把原生 PixelMap 转成 JS 对象、调用 ArkTS 传进来的 onFrames。
// onFrames(frames, done, ok, info)：info 只有读缓存任务的第一批才有。

napi_value BuildInfo(napi_env env, const sticker_decode::Batch &batch) {
    napi_value info = nullptr;
    napi_create_object(env, &info);
    napi_value w = nullptr;
    napi_value h = nullptr;
    napi_value d = nullptr;
    napi_value times = nullptr;
    napi_create_int32(env, batch.info.width, &w);
    napi_create_int32(env, batch.info.height, &h);
    napi_create_int32(env, batch.info.durationMs, &d);
    napi_create_array_with_length(env, batch.timesMs.size(), &times);
    for (size_t i = 0; i < batch.timesMs.size(); ++i) {
        napi_value v = nullptr;
        napi_create_int32(env, batch.timesMs[i], &v);
        napi_set_element(env, times, static_cast<uint32_t>(i), v);
    }
    napi_set_named_property(env, info, "width", w);
    napi_set_named_property(env, info, "height", h);
    napi_set_named_property(env, info, "durationMs", d);
    napi_set_named_property(env, info, "timesMs", times);
    return info;
}

void CallOnFrames(napi_env env, napi_value jsCallback, void *context, void *data) {
    sticker_decode::Batch *batch = static_cast<sticker_decode::Batch *>(data);
    if (batch == nullptr) {
        return;
    }
    // env 为空 = 环境正在销毁：没人接了，帧原地释放。
    if (env == nullptr || jsCallback == nullptr) {
        sticker_decode::ReleaseBatch(batch);
        return;
    }
    napi_handle_scope scope = nullptr;
    napi_open_handle_scope(env, &scope);
    napi_value frames = nullptr;
    napi_create_array_with_length(env, batch->pixelmaps.size(), &frames);
    bool ok = batch->ok;
    uint32_t count = 0;
    for (size_t i = 0; i < batch->pixelmaps.size(); ++i) {
        napi_value jsPixelmap = nullptr;
        const Image_ErrorCode conv =
            OH_PixelmapNative_ConvertPixelmapNativeToNapi(env, batch->pixelmaps[i], &jsPixelmap);
        // 转换出的 JS 对象自己持有一份内部 PixelMap，这个原生壳必须释放，否则每帧漏一个。
        OH_PixelmapNative_Release(batch->pixelmaps[i]);
        batch->pixelmaps[i] = nullptr;
        if (conv != IMAGE_SUCCESS || jsPixelmap == nullptr) {
            ok = false;   // 剩下的照样要释放，循环继续
            continue;
        }
        napi_set_element(env, frames, count++, jsPixelmap);
    }
    napi_value args[4] = {frames, nullptr, nullptr, nullptr};
    // 转换失败也当作整段结束：JS 侧据此放弃这一段、回退。
    napi_get_boolean(env, batch->done || !ok, &args[1]);
    napi_get_boolean(env, ok, &args[2]);
    if (batch->hasInfo) {
        args[3] = BuildInfo(env, *batch);
    } else {
        napi_get_undefined(env, &args[3]);
    }
    napi_value undefined = nullptr;
    napi_get_undefined(env, &undefined);
    napi_call_function(env, undefined, jsCallback, 4, args, nullptr);
    napi_close_handle_scope(env, scope);
    delete batch;
}

// 为一个任务建线程安全函数，并给出交付 / 收尾两个回调。失败返回 false。
bool MakeStreamCallbacks(napi_env env, napi_value jsCallback, const char *name,
                         sticker_decode::Deliver &deliver, sticker_decode::Finish &finish) {
    napi_valuetype type = napi_undefined;
    if (napi_typeof(env, jsCallback, &type) != napi_ok || type != napi_function) {
        return false;
    }
    napi_value resourceName = nullptr;
    napi_create_string_utf8(env, name, NAPI_AUTO_LENGTH, &resourceName);
    napi_threadsafe_function tsfn = nullptr;
    if (napi_create_threadsafe_function(env, jsCallback, nullptr, resourceName, 0, 1, nullptr, nullptr,
                                        nullptr, CallOnFrames, &tsfn) != napi_ok || tsfn == nullptr) {
        return false;
    }
    deliver = [tsfn](sticker_decode::Batch *batch) {
        if (napi_call_threadsafe_function(tsfn, batch, napi_tsfn_blocking) != napi_ok) {
            sticker_decode::ReleaseBatch(batch);
        }
    };
    finish = [tsfn]() { napi_release_threadsafe_function(tsfn, napi_tsfn_release); };
    return true;
}

napi_value MakeInt(napi_env env, int32_t v) {
    napi_value out = nullptr;
    napi_create_int32(env, v, &out);
    return out;
}

// stickerFramesLoadStream(cachePath, maxBytes, onFrames) -> 任务号（0 = 没起来）
napi_value StickerFramesLoadStream(napi_env env, napi_callback_info info) {
    size_t argc = 3;
    napi_value args[3] = {nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    std::string path;
    double maxBytes = 0;
    if (argc < 3 || !ReadString(env, args[0], path) ||
        napi_get_value_double(env, args[1], &maxBytes) != napi_ok) {
        return MakeInt(env, 0);
    }
    sticker_decode::Deliver deliver;
    sticker_decode::Finish finish;
    if (!MakeStreamCallbacks(env, args[2], "stickerFramesLoadStream", deliver, finish)) {
        return MakeInt(env, 0);
    }
    const int32_t id = sticker_decode::SubmitLoad(path, static_cast<int64_t>(maxBytes), deliver, finish);
    if (id == 0) {
        finish();
    }
    return MakeInt(env, id);
}

napi_value StickerDecodeCancel(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value args[1] = {nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    int32_t id = 0;
    if (argc >= 1 && ReadInt(env, args[0], id) && id > 0) {
        sticker_decode::Cancel(id);
    }
    return Undefined(env);
}

napi_value WebmAlphaAvailable(napi_env env, napi_callback_info info) {
    napi_value result = nullptr;
    napi_get_boolean(env, webm_alpha::Vp9DecoderAvailable(), &result);
    return result;
}

// webmAlphaDecodeStream(colorData, colorLengths, alphaData, alphaLengths, srcW, srcH,
//   dstW, dstH, frameStep, cachePath, timesMs, durationMs, onFrames) -> 任务号（0 = 没起来）
napi_value WebmAlphaDecodeStream(napi_env env, napi_callback_info info) {
    size_t argc = 13;
    napi_value args[13] = {nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    if (argc < 13) {
        return MakeInt(env, 0);
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
        return MakeInt(env, 0);
    }
    sticker_decode::DecodeParams params;
    // 在同步段就把字节复制走：解码线程跑起来之后，ArrayBuffer 的生命周期不再由
    // 这里控制。贴纸码流只有几十 KB，复制的代价可以忽略。
    // alpha 两块都为空 = 不透明贴纸，走同一条链路但不解 alpha 那一路。
    const bool opaque = alphaDataLen == 0 && alphaLensLen == 0;
    const bool parsed =
        SplitPackets(static_cast<const uint8_t *>(colorData), colorDataLen,
                     static_cast<const uint8_t *>(colorLens), colorLensLen, params.color) &&
        (opaque || SplitPackets(static_cast<const uint8_t *>(alphaData), alphaDataLen,
                                static_cast<const uint8_t *>(alphaLens), alphaLensLen, params.alpha)) &&
        ReadInt(env, args[4], params.srcW) && ReadInt(env, args[5], params.srcH) &&
        ReadInt(env, args[6], params.dstW) && ReadInt(env, args[7], params.dstH) &&
        ReadInt(env, args[8], params.frameStep) && ReadInt(env, args[11], params.durationMs);
    if (!parsed) {
        return MakeInt(env, 0);
    }
    // 缓存路径与时间戳表都是可选的：任一取不到就只当"这次不缓存"，不能连解码一起失败。
    std::string cachePath;
    if (ReadString(env, args[9], cachePath)) {
        params.cachePath = cachePath;
    }
    void *timesData = nullptr;
    size_t timesLen = 0;
    if (ReadArrayBuffer(env, args[10], &timesData, &timesLen) && timesLen % sizeof(int32_t) == 0 &&
        timesLen > 0) {
        params.timesMs.resize(timesLen / sizeof(int32_t));
        std::memcpy(params.timesMs.data(), timesData, timesLen);
    } else {
        params.cachePath.clear();   // 没有时间戳表就别写半份缓存
    }
    sticker_decode::Deliver deliver;
    sticker_decode::Finish finish;
    if (!MakeStreamCallbacks(env, args[12], "webmAlphaDecodeStream", deliver, finish)) {
        return MakeInt(env, 0);
    }
    const int32_t id = sticker_decode::SubmitDecode(std::move(params), deliver, finish);
    if (id == 0) {
        finish();
    }
    return MakeInt(env, id);
}

} // namespace

void WebmAlphaRegister(napi_env env, napi_value exports) {
    napi_property_descriptor desc[] = {
        {"webmAlphaAvailable", nullptr, WebmAlphaAvailable, nullptr, nullptr, nullptr, napi_default,
         nullptr},
        {"webmAlphaDecodeStream", nullptr, WebmAlphaDecodeStream, nullptr, nullptr, nullptr,
         napi_default, nullptr},
        {"stickerFramesLoadStream", nullptr, StickerFramesLoadStream, nullptr, nullptr, nullptr,
         napi_default, nullptr},
        {"stickerDecodeCancel", nullptr, StickerDecodeCancel, nullptr, nullptr, nullptr, napi_default,
         nullptr},
    };
    napi_define_properties(env, exports, sizeof(desc) / sizeof(desc[0]), desc);
}
