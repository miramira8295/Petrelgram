#include "tgs_napi.h"

#include <multimedia/image_framework/image/pixelmap_native.h>
#include <new>
#include <string>
#include <vector>

#include "tgs_render.h"

namespace {

constexpr int32_t kPixelFormatRgba8888 = 3;          // PIXEL_FORMAT_RGBA_8888
constexpr int32_t kAlphaTypeUnpremultiplied = 3;     // PIXELMAP_ALPHA_TYPE_UNPREMULTIPLIED

napi_value Undefined(napi_env env) {
    napi_value v = nullptr;
    napi_get_undefined(env, &v);
    return v;
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

// ── 打开 ──────────────────────────────────────────────────────────────
struct OpenTask {
    std::string path;
    int32_t width = 0;
    int32_t height = 0;
    tgs_render::AnimationInfo info;
    napi_deferred deferred = nullptr;
    napi_async_work work = nullptr;
};

void ExecuteOpen(napi_env env, void *data) {
    OpenTask *task = static_cast<OpenTask *>(data);
    // 读文件 + gunzip + 解析 JSON 都在 worker 上：解压后的 JSON 实测中位
    // 147KB，放主线程解析就是一次可见的卡顿。
    task->info = tgs_render::Open(task->path, task->width, task->height);
}

void CompleteOpen(napi_env env, napi_status status, void *data) {
    OpenTask *task = static_cast<OpenTask *>(data);
    napi_value result = nullptr;
    if (status == napi_ok && task->info.handle != 0) {
        napi_create_object(env, &result);
        napi_value handle = nullptr;
        napi_value total = nullptr;
        napi_value fps = nullptr;
        napi_value w = nullptr;
        napi_value h = nullptr;
        napi_create_int32(env, task->info.handle, &handle);
        napi_create_int32(env, task->info.totalFrames, &total);
        napi_create_double(env, task->info.frameRate, &fps);
        napi_create_int32(env, task->info.width, &w);
        napi_create_int32(env, task->info.height, &h);
        napi_set_named_property(env, result, "handle", handle);
        napi_set_named_property(env, result, "totalFrames", total);
        napi_set_named_property(env, result, "frameRate", fps);
        napi_set_named_property(env, result, "width", w);
        napi_set_named_property(env, result, "height", h);
    } else {
        napi_get_null(env, &result);
    }
    napi_resolve_deferred(env, task->deferred, result);
    napi_delete_async_work(env, task->work);
    delete task;
}

napi_value TgsOpen(napi_env env, napi_callback_info info) {
    size_t argc = 3;
    napi_value args[3] = {nullptr};
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
    if (argc < 3) {
        return fail();
    }
    OpenTask *task = new (std::nothrow) OpenTask();
    if (task == nullptr) {
        return fail();
    }
    if (!ReadString(env, args[0], task->path) ||
        napi_get_value_int32(env, args[1], &task->width) != napi_ok ||
        napi_get_value_int32(env, args[2], &task->height) != napi_ok) {
        delete task;
        return fail();
    }
    task->deferred = deferred;
    napi_value name = nullptr;
    napi_create_string_utf8(env, "tgsOpen", NAPI_AUTO_LENGTH, &name);
    if (napi_create_async_work(env, nullptr, name, ExecuteOpen, CompleteOpen, task, &task->work)
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

// ── 渲一帧 ────────────────────────────────────────────────────────────
struct RenderTask {
    int32_t handle = 0;
    int32_t frameIndex = 0;
    int32_t width = 0;
    int32_t height = 0;
    std::vector<uint8_t> rgba;
    OH_PixelmapNative *pixelmap = nullptr;
    bool ok = false;
    napi_deferred deferred = nullptr;
    napi_async_work work = nullptr;
};

void ExecuteRender(napi_env env, void *data) {
    RenderTask *task = static_cast<RenderTask *>(data);
    if (!tgs_render::RenderFrame(task->handle, task->frameIndex, task->rgba, task->width,
                                 task->height)) {
        return;
    }
    // PixelMap 的构造也留在 worker（同 webm 那条链路的判断：放 complete 回调
    // 里就是在主线程上做像素级拷贝）。
    OH_Pixelmap_InitializationOptions *options = nullptr;
    if (OH_PixelmapInitializationOptions_Create(&options) != IMAGE_SUCCESS || options == nullptr) {
        return;
    }
    OH_PixelmapInitializationOptions_SetWidth(options, static_cast<uint32_t>(task->width));
    OH_PixelmapInitializationOptions_SetHeight(options, static_cast<uint32_t>(task->height));
    OH_PixelmapInitializationOptions_SetPixelFormat(options, kPixelFormatRgba8888);
    OH_PixelmapInitializationOptions_SetSrcPixelFormat(options, kPixelFormatRgba8888);
    OH_PixelmapInitializationOptions_SetRowStride(options, static_cast<uint32_t>(task->width) * 4);
    OH_PixelmapInitializationOptions_SetAlphaType(options, kAlphaTypeUnpremultiplied);
    task->ok = OH_PixelmapNative_CreatePixelmap(task->rgba.data(), task->rgba.size(), options,
                                                &task->pixelmap) == IMAGE_SUCCESS
        && task->pixelmap != nullptr;
    OH_PixelmapInitializationOptions_Release(options);
    std::vector<uint8_t>().swap(task->rgba);
}

void CompleteRender(napi_env env, napi_status status, void *data) {
    RenderTask *task = static_cast<RenderTask *>(data);
    napi_value result = nullptr;
    if (status == napi_ok && task->ok && task->pixelmap != nullptr) {
        napi_value js = nullptr;
        if (OH_PixelmapNative_ConvertPixelmapNativeToNapi(env, task->pixelmap, &js) == IMAGE_SUCCESS
            && js != nullptr) {
            result = js;
        }
    }
    if (task->pixelmap != nullptr) {
        // 转换出的 JS 对象自己持有一份内部 PixelMap，这个原生壳必须释放。
        OH_PixelmapNative_Release(task->pixelmap);
        task->pixelmap = nullptr;
    }
    if (result == nullptr) {
        napi_get_null(env, &result);
    }
    napi_resolve_deferred(env, task->deferred, result);
    napi_delete_async_work(env, task->work);
    delete task;
}

napi_value TgsRenderFrame(napi_env env, napi_callback_info info) {
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
    RenderTask *task = new (std::nothrow) RenderTask();
    if (task == nullptr) {
        return fail();
    }
    if (napi_get_value_int32(env, args[0], &task->handle) != napi_ok ||
        napi_get_value_int32(env, args[1], &task->frameIndex) != napi_ok) {
        delete task;
        return fail();
    }
    task->deferred = deferred;
    napi_value name = nullptr;
    napi_create_string_utf8(env, "tgsRenderFrame", NAPI_AUTO_LENGTH, &name);
    if (napi_create_async_work(env, nullptr, name, ExecuteRender, CompleteRender, task, &task->work)
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

napi_value TgsClose(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value args[1] = {nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    int32_t handle = 0;
    if (argc >= 1 && napi_get_value_int32(env, args[0], &handle) == napi_ok) {
        tgs_render::Close(handle);
    }
    return Undefined(env);
}

napi_value TgsOpenCount(napi_env env, napi_callback_info info) {
    napi_value result = nullptr;
    napi_create_int32(env, tgs_render::OpenCount(), &result);
    return result;
}

} // namespace

void TgsRegister(napi_env env, napi_value exports) {
    napi_property_descriptor desc[] = {
        {"tgsOpen", nullptr, TgsOpen, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"tgsRenderFrame", nullptr, TgsRenderFrame, nullptr, nullptr, nullptr, napi_default,
         nullptr},
        {"tgsClose", nullptr, TgsClose, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"tgsOpenCount", nullptr, TgsOpenCount, nullptr, nullptr, nullptr, napi_default, nullptr},
    };
    napi_define_properties(env, exports, sizeof(desc) / sizeof(desc[0]), desc);
}
