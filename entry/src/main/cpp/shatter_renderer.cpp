#include "shatter_renderer.h"
#include "shatter_geometry.h"
#include "shatter_shaders.h"

#include <EGL/egl.h>
#include <EGL/eglext.h>
#include <GLES3/gl3.h>
#include <hilog/log.h>
#include <multimedia/image_framework/image/pixelmap_native.h>
#include <native_window/external_window.h>
#include <native_vsync/native_vsync.h>
#include <atomic>
#include <chrono>
#include <condition_variable>
#include <cstdlib>
#include <cstring>
#include <deque>
#include <functional>
#include <future>
#include <memory>
#include <mutex>
#include <thread>
#include <unordered_map>

namespace shatter {
namespace {
using Clock = std::chrono::steady_clock;

struct Scene {
    Geometry geometry;
    std::vector<uint8_t> pixels;
    napi_env owner = nullptr;
    napi_threadsafe_function callback = nullptr; // 仅渲染线程持有/释放。
    OHNativeWindow *window = nullptr;
    EGLSurface surface = EGL_NO_SURFACE;
    GLuint texture = 0, buffer = 0, vao = 0;
    GLsizei count = 0;
    bool running = false;
    double durationMs = 1100;
    Clock::time_point started;
    Clock::time_point deadline = Clock::now() + std::chrono::milliseconds(3050);
};

void Notify(Scene &scene, int event) {
    if (scene.callback) {
        // 只有首帧、完成/失败事件，不经过 ArkTS 逐帧调度。
        napi_call_threadsafe_function(scene.callback, reinterpret_cast<void *>(intptr_t(event + 2)),
                                      napi_tsfn_nonblocking);
    }
}

class Renderer {
public:
    static Renderer &Get() { static Renderer renderer; return renderer; }
    void Post(std::function<void()> command) {
        {
            std::lock_guard<std::mutex> lock(mutex_);
            commands_.push_back(std::move(command));
        }
        wake_.notify_one();
    }
    // 以下方法只从渲染线程调用。
    void Warm() { Initialize(); }
    void Add(int id, const std::shared_ptr<Scene> &scene) { scenes_.emplace(id, scene); }
    void Attach(int id, uint64_t surfaceId, napi_threadsafe_function callback) {
        auto found = scenes_.find(id);
        if (found == scenes_.end() || found->second->callback) {
            napi_release_threadsafe_function(callback, napi_tsfn_release);
            return;
        }
        auto &scene = *found->second;
        scene.callback = callback;
        if (!Initialize()) { Fail(id, "initialize"); return; }
        if (!Upload(scene, surfaceId)) { Fail(id, "upload"); return; }
        if (!Draw(scene, 0)) { Fail(id, "first-frame"); return; }
        Notify(scene, 0); // 首帧已提交，等待 UI 隐藏原行后显式 Begin。
    }
    void Begin(int id, double durationMs) {
        auto found = scenes_.find(id);
        if (found == scenes_.end() || found->second->surface == EGL_NO_SURFACE || found->second->running) {
            return;
        }
        auto &scene = *found->second;
        scene.durationMs = std::max(0.0, std::min(1100.0, durationMs));
        scene.started = Clock::now();
        scene.running = true;
    }
    void Close(int id) {
        auto found = scenes_.find(id);
        if (found == scenes_.end()) { return; }
        Release(*found->second);
        scenes_.erase(found);
    }
    void CloseOwner(napi_env owner) {
        for (auto it = scenes_.begin(); it != scenes_.end();) {
            if (it->second->owner == owner) {
                Release(*it->second);
                it = scenes_.erase(it);
            } else { ++it; }
        }
    }
private:
    Renderer() : thread_([this]() { Run(); }) {}
    ~Renderer() {
        {
            std::lock_guard<std::mutex> lock(mutex_);
            stopping_ = true;
        }
        wake_.notify_one();
        thread_.join();
    }
    static void OnVSync(long long, void *data) {
        auto &self = *static_cast<Renderer *>(data);
        {
            std::lock_guard<std::mutex> lock(self.mutex_);
            self.tick_ = true;
        }
        self.wake_.notify_one();
    }
    void Fail(int id, const char *stage = "frame-or-deadline") {
        OH_LOG_Print(LOG_APP, LOG_WARN, 0x0000, "Shatter",
            "Shatter renderer failed: stage=%{public}s egl=%{public}x gl=%{public}x", stage, eglGetError(), glGetError());
        auto found = scenes_.find(id);
        if (found != scenes_.end()) { Notify(*found->second, -1); }
        Close(id);
    }
    GLuint Shader(GLenum type, const char *source) {
        GLuint shader = glCreateShader(type);
        glShaderSource(shader, 1, &source, nullptr);
        glCompileShader(shader);
        GLint ok = 0;
        glGetShaderiv(shader, GL_COMPILE_STATUS, &ok);
        if (!ok) {
            char message[512] = {};
            glGetShaderInfoLog(shader, sizeof(message), nullptr, message);
            OH_LOG_Print(LOG_APP, LOG_WARN, 0x0000, "Shatter", "shader compile: %{public}s", message);
            glDeleteShader(shader);
            return 0;
        }
        return shader;
    }
    bool Initialize() {
        if (program_ && vsync_) { return true; }
        // 失败可在下一次动画重试；空闲时仅保留小型 context/program，不保留截图。
        ResetContext();
        display_ = eglGetDisplay(EGL_DEFAULT_DISPLAY);
        if (display_ == EGL_NO_DISPLAY || !eglInitialize(display_, nullptr, nullptr) ||
            !eglBindAPI(EGL_OPENGL_ES_API)) { return false; }
        const EGLint attrs[] = {EGL_SURFACE_TYPE, EGL_WINDOW_BIT | EGL_PBUFFER_BIT,
            EGL_RENDERABLE_TYPE, EGL_OPENGL_ES3_BIT_KHR, EGL_RED_SIZE, 8, EGL_GREEN_SIZE, 8,
            EGL_BLUE_SIZE, 8, EGL_ALPHA_SIZE, 8, EGL_DEPTH_SIZE, 0, EGL_STENCIL_SIZE, 0, EGL_NONE};
        EGLint count = 0;
        if (!eglChooseConfig(display_, attrs, &config_, 1, &count) || count == 0) { return false; }
        const EGLint contextAttrs[] = {EGL_CONTEXT_CLIENT_VERSION, 3, EGL_NONE};
        context_ = eglCreateContext(display_, config_, EGL_NO_CONTEXT, contextAttrs);
        const EGLint pbufferAttrs[] = {EGL_WIDTH, 1, EGL_HEIGHT, 1, EGL_NONE};
        parking_ = eglCreatePbufferSurface(display_, config_, pbufferAttrs);
        if (context_ == EGL_NO_CONTEXT || parking_ == EGL_NO_SURFACE ||
            !eglMakeCurrent(display_, parking_, parking_, context_)) { return false; }
        GLuint vertex = Shader(GL_VERTEX_SHADER, kVertexShader);
        GLuint fragment = Shader(GL_FRAGMENT_SHADER, kFragmentShader);
        if (!vertex || !fragment) { glDeleteShader(vertex); glDeleteShader(fragment); return false; }
        GLuint program = glCreateProgram();
        glAttachShader(program, vertex);
        glAttachShader(program, fragment);
        glLinkProgram(program);
        glDeleteShader(vertex);
        glDeleteShader(fragment);
        GLint ok = 0;
        glGetProgramiv(program, GL_LINK_STATUS, &ok);
        if (!ok) { glDeleteProgram(program); return false; }
        program_ = program;
        viewport_ = glGetUniformLocation(program_, "viewportSize");
        imageSize_ = glGetUniformLocation(program_, "imageSize");
        top_ = glGetUniformLocation(program_, "topPadding");
        progress_ = glGetUniformLocation(program_, "progress");
        moving_ = glGetUniformLocation(program_, "moving");
        glUseProgram(program_);
        glUniform1i(glGetUniformLocation(program_, "snapshot"), 0);
        glEnable(GL_BLEND);
        glBlendFunc(GL_ONE, GL_ONE_MINUS_SRC_ALPHA);
        glDisable(GL_DEPTH_TEST);
        glDisable(GL_DITHER);
        if (!vsync_) {
            vsync_ = OH_NativeVSync_Create("PetrelgramShatter", 16);
            if (vsync_) {
                OH_NativeVSync_ExpectedRateRange range{30, 120, 120};
                OH_NativeVSync_SetExpectedFrameRateRange(vsync_, &range);
            }
        }
        return vsync_ != nullptr;
    }
    bool Upload(Scene &scene, uint64_t surfaceId) {
        const auto &g = scene.geometry;
        GLint maxTexture = 0;
        glGetIntegerv(GL_MAX_TEXTURE_SIZE, &maxTexture);
        if (g.surfaceWidth > maxTexture || g.surfaceHeight > maxTexture ||
            OH_NativeWindow_CreateNativeWindowFromSurfaceId(surfaceId, &scene.window) != 0 || !scene.window) {
            return false;
        }
        if (OH_NativeWindow_NativeWindowHandleOpt(scene.window, SET_BUFFER_GEOMETRY,
                                                 g.surfaceWidth, g.surfaceHeight) != 0) { return false; }
        EGLint format = 0;
        if (!eglGetConfigAttrib(display_, config_, EGL_NATIVE_VISUAL_ID, &format) ||
            OH_NativeWindow_NativeWindowHandleOpt(scene.window, SET_FORMAT, format) != 0) { return false; }
        scene.surface = eglCreateWindowSurface(display_, config_,
            reinterpret_cast<EGLNativeWindowType>(scene.window), nullptr);
        if (scene.surface == EGL_NO_SURFACE ||
            !eglMakeCurrent(display_, scene.surface, scene.surface, context_)) { return false; }
        eglSwapInterval(display_, 0); // VSync 统一驱动；不在每个行的 swap 再串行等待。
        glGenTextures(1, &scene.texture);
        glActiveTexture(GL_TEXTURE0);
        glBindTexture(GL_TEXTURE_2D, scene.texture);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
        glPixelStorei(GL_UNPACK_ALIGNMENT, 1);
        glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, g.width, g.height, 0, GL_RGBA,
                     GL_UNSIGNED_BYTE, scene.pixels.data());
        glGenVertexArrays(1, &scene.vao);
        glBindVertexArray(scene.vao);
        glGenBuffers(1, &scene.buffer);
        glBindBuffer(GL_ARRAY_BUFFER, scene.buffer);
        glBufferData(GL_ARRAY_BUFFER, g.tiles.size() * sizeof(Tile), g.tiles.data(), GL_STATIC_DRAW);
        for (GLuint i = 0; i < 2; ++i) {
            glEnableVertexAttribArray(i);
            glVertexAttribPointer(i, 4, GL_FLOAT, GL_FALSE, sizeof(Tile),
                                  reinterpret_cast<void *>(i * 4 * sizeof(float)));
            glVertexAttribDivisor(i, 1);
        }
        scene.count = static_cast<GLsizei>(g.tiles.size());
        std::vector<uint8_t>().swap(scene.pixels);
        std::vector<Tile>().swap(scene.geometry.tiles);
        return glGetError() == GL_NO_ERROR;
    }
    bool Draw(Scene &scene, float progress) {
        if (!eglMakeCurrent(display_, scene.surface, scene.surface, context_)) { return false; }
        const auto &g = scene.geometry;
        glViewport(0, 0, g.surfaceWidth, g.surfaceHeight);
        glClearColor(0, 0, 0, 0);
        glClear(GL_COLOR_BUFFER_BIT);
        if (progress < 1) {
            glUseProgram(program_);
            glBindVertexArray(scene.vao);
            glActiveTexture(GL_TEXTURE0);
            glBindTexture(GL_TEXTURE_2D, scene.texture);
            glUniform2f(viewport_, g.surfaceWidth, g.surfaceHeight);
            glUniform2f(imageSize_, g.width, g.height);
            glUniform1f(top_, g.top);
            glUniform1f(progress_, progress);
            // 整数像素切口共享边，无多重采样：静止区域不会出现拼片缝隙。
            glUniform1i(moving_, 0);
            glDrawArraysInstanced(GL_TRIANGLES, 0, 6, scene.count);
            glUniform1i(moving_, 1);
            glDrawArraysInstanced(GL_TRIANGLES, 0, 6, scene.count);
        }
        return eglSwapBuffers(display_, scene.surface) == EGL_TRUE;
    }
    void Release(Scene &scene) {
        if (context_ != EGL_NO_CONTEXT && parking_ != EGL_NO_SURFACE &&
            eglMakeCurrent(display_, parking_, parking_, context_)) {
            glDeleteTextures(1, &scene.texture);
            glDeleteBuffers(1, &scene.buffer);
            glDeleteVertexArrays(1, &scene.vao);
        }
        if (scene.surface != EGL_NO_SURFACE) { eglDestroySurface(display_, scene.surface); }
        if (scene.window) { OH_NativeWindow_DestroyNativeWindow(scene.window); }
        if (scene.callback) { napi_release_threadsafe_function(scene.callback, napi_tsfn_release); }
        scene.callback = nullptr;
    }
    void ResetContext() {
        if (context_ != EGL_NO_CONTEXT) {
            if (parking_ != EGL_NO_SURFACE && eglMakeCurrent(display_, parking_, parking_, context_)) {
                glDeleteProgram(program_);
            }
            eglMakeCurrent(display_, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);
            eglDestroyContext(display_, context_);
        }
        if (parking_ != EGL_NO_SURFACE) { eglDestroySurface(display_, parking_); }
        if (display_ != EGL_NO_DISPLAY) { eglTerminate(display_); }
        program_ = 0;
        parking_ = EGL_NO_SURFACE;
        context_ = EGL_NO_CONTEXT;
        display_ = EGL_NO_DISPLAY;
    }
    void Run() {
        bool requested = false;
        for (;;) {
            std::deque<std::function<void()>> commands;
            bool tick = false;
            {
                std::unique_lock<std::mutex> lock(mutex_);
                auto ready = [&]() { return stopping_ || tick_ || !commands_.empty(); };
                if (scenes_.empty()) { wake_.wait(lock, ready); }
                else {
                    auto deadline = Clock::time_point::max();
                    for (const auto &item : scenes_) { deadline = std::min(deadline, item.second->deadline); }
                    wake_.wait_until(lock, deadline, ready);
                }
                if (stopping_) { break; }
                tick = tick_;
                tick_ = false;
                commands.swap(commands_);
            }
            if (tick) { requested = false; }
            for (auto &command : commands) { command(); }
            std::vector<int> completed, failed;
            const auto now = Clock::now();
            bool needsFrame = false;
            for (auto &item : scenes_) {
                auto &scene = *item.second;
                if (now >= scene.deadline) { failed.push_back(item.first); continue; }
                if (!scene.running) { continue; }
                if (tick) {
                    const double elapsed = std::chrono::duration<double, std::milli>(now - scene.started).count();
                    const float progress = scene.durationMs > 0 ? std::min(1.0, elapsed / scene.durationMs) : 1;
                    if (!Draw(scene, progress)) { failed.push_back(item.first); continue; }
                    if (progress >= 1) { completed.push_back(item.first); continue; }
                }
                needsFrame = true;
            }
            for (int id : completed) { Notify(*scenes_.at(id), 1); Close(id); }
            for (int id : failed) { Fail(id); }
            if (!needsFrame) { requested = false; }
            if (needsFrame && !requested) {
                requested = vsync_ && OH_NativeVSync_RequestFrame(vsync_, OnVSync, this) == 0;
                if (!requested) {
                    std::vector<int> ids;
                    for (const auto &item : scenes_) { if (item.second->running) { ids.push_back(item.first); } }
                    for (int id : ids) { Fail(id); }
                }
            }
        }
        for (auto &item : scenes_) { Release(*item.second); }
        scenes_.clear();
        if (vsync_) { OH_NativeVSync_Destroy(vsync_); vsync_ = nullptr; }
        ResetContext();
    }
    std::mutex mutex_;
    std::condition_variable wake_;
    std::deque<std::function<void()>> commands_;
    bool stopping_ = false, tick_ = false;
    std::unordered_map<int, std::shared_ptr<Scene>> scenes_;
    EGLDisplay display_ = EGL_NO_DISPLAY;
    EGLContext context_ = EGL_NO_CONTEXT;
    EGLSurface parking_ = EGL_NO_SURFACE;
    EGLConfig config_ = nullptr;
    GLuint program_ = 0;
    GLint viewport_ = -1, imageSize_ = -1, top_ = -1, progress_ = -1, moving_ = -1;
    OH_NativeVSync *vsync_ = nullptr;
    std::thread thread_; // 最后初始化，避免线程先读到尚未初始化的状态。
};

struct PrepareTask {
    OH_PixelmapNative *pixelmap = nullptr;
    napi_ref source = nullptr;
    napi_async_work work = nullptr;
    napi_deferred deferred = nullptr;
    float density = 1;
    int budget = 8000;
    bool ok = false;
    std::shared_ptr<Scene> scene = std::make_shared<Scene>();
};

void PreparePixelsImpl(void *data) {
    auto &task = *static_cast<PrepareTask *>(data);
    OH_Pixelmap_ImageInfo *info = nullptr;
    if (OH_PixelmapImageInfo_Create(&info) != IMAGE_SUCCESS) { return; }
    uint32_t width = 0, height = 0, stride = 0;
    int32_t format = 0, alpha = 0;
    bool ok = OH_PixelmapNative_GetImageInfo(task.pixelmap, info) == IMAGE_SUCCESS &&
        OH_PixelmapImageInfo_GetWidth(info, &width) == IMAGE_SUCCESS &&
        OH_PixelmapImageInfo_GetHeight(info, &height) == IMAGE_SUCCESS &&
        OH_PixelmapImageInfo_GetRowStride(info, &stride) == IMAGE_SUCCESS &&
        OH_PixelmapImageInfo_GetPixelFormat(info, &format) == IMAGE_SUCCESS &&
        // GetImageInfo 填的是 alphaMode；旧 GetAlphaType 读另一个默认字段，可能始终为 0。
        // 项目最低 API20，直接用返回实际 PixelMap 透明度模式的接口。
        OH_PixelmapImageInfo_GetAlphaMode(info, &alpha) == IMAGE_SUCCESS;
    OH_PixelmapImageInfo_Release(info);
    if (!ok || width == 0 || height == 0 || width > 8192 || height > 8192 ||
        uint64_t(width) * height > 16777216 || stride < width * 4 ||
        (format != PIXEL_FORMAT_RGBA_8888 && format != PIXEL_FORMAT_BGRA_8888) ||
        alpha < PIXELMAP_ALPHA_TYPE_OPAQUE || alpha > PIXELMAP_ALPHA_TYPE_UNPREMULTIPLIED) {
        OH_LOG_Print(LOG_APP, LOG_WARN, 0x0000, "Shatter", "Shatter prepare metadata invalid: ok=%{public}d "
            "size=%{public}ux%{public}u stride=%{public}u format=%{public}d alphaMode=%{public}d",
            ok, width, height, stride, format, alpha);
        return;
    }
    auto &pixels = task.scene->pixels;
    pixels.resize(size_t(width) * height * 4);
    void *address = nullptr;
    const auto access = OH_PixelmapNative_AccessPixels(task.pixelmap, &address);
    if (access != IMAGE_SUCCESS || !address) {
        OH_LOG_Print(LOG_APP, LOG_WARN, 0x0000, "Shatter", "Shatter prepare pixels inaccessible: %{public}d", access);
        return;
    }
    const auto *src = static_cast<const uint8_t *>(address);
    for (uint32_t y = 0; y < height; ++y) {
        const auto *row = src + size_t(y) * stride;
        auto *out = pixels.data() + size_t(y) * width * 4;
        if (format == PIXEL_FORMAT_RGBA_8888 && alpha == PIXELMAP_ALPHA_TYPE_PREMULTIPLIED) {
            std::memcpy(out, row, size_t(width) * 4);
            continue;
        }
        for (uint32_t x = 0; x < width; ++x) {
            const uint8_t a = alpha == PIXELMAP_ALPHA_TYPE_OPAQUE ? 255 : row[x * 4 + 3];
            const int red = format == PIXEL_FORMAT_RGBA_8888 ? 0 : 2;
            out[x * 4] = row[x * 4 + red];
            out[x * 4 + 1] = row[x * 4 + 1];
            out[x * 4 + 2] = row[x * 4 + 2 - red];
            out[x * 4 + 3] = a;
            if (alpha == PIXELMAP_ALPHA_TYPE_UNPREMULTIPLIED) {
                for (int c = 0; c < 3; ++c) { out[x * 4 + c] = (unsigned(out[x * 4 + c]) * a + 127) / 255; }
            }
        }
    }
    OH_PixelmapNative_UnaccessPixels(task.pixelmap);
    static std::atomic<uint32_t> seeds{uint32_t(Clock::now().time_since_epoch().count())};
    task.scene->geometry = MakeGeometry(width, height, task.density, task.budget, seeds.fetch_add(1));
    task.ok = !task.scene->geometry.tiles.empty();
}

void PreparePixels(napi_env, void *data) {
    try {
        PreparePixelsImpl(data);
    } catch (const std::bad_alloc &) {
        // 内存不足沿用截图失败的完成协议，不让 worker 异常终止应用。
        static_cast<PrepareTask *>(data)->ok = false;
    }
}

napi_value Undefined(napi_env env) { napi_value value; napi_get_undefined(env, &value); return value; }
void Number(napi_env env, napi_value object, const char *key, int n) {
    napi_value value;
    napi_create_int32(env, n, &value);
    napi_set_named_property(env, object, key, value);
}
void CompletePrepare(napi_env env, napi_status status, void *data) {
    std::unique_ptr<PrepareTask> task(static_cast<PrepareTask *>(data));
    // Destroy 只销毁 native 包装，原 ArkTS PixelMap 由 await 调用者 finally 释放。
    OH_PixelmapNative_Destroy(&task->pixelmap);
    napi_delete_reference(env, task->source);
    napi_value result;
    napi_get_null(env, &result);
    if (status == napi_ok && task->ok) {
        static std::atomic<int> nextId{1};
        const int id = nextId.fetch_add(1);
        const auto &g = task->scene->geometry;
        napi_create_object(env, &result);
        Number(env, result, "handle", id);
        Number(env, result, "width", g.width);
        Number(env, result, "height", g.height);
        Number(env, result, "surfaceWidth", g.surfaceWidth);
        Number(env, result, "surfaceHeight", g.surfaceHeight);
        Number(env, result, "top", g.top);
        auto scene = task->scene;
        Renderer::Get().Post([id, scene]() { Renderer::Get().Add(id, scene); });
    }
    napi_resolve_deferred(env, task->deferred, result);
    napi_delete_async_work(env, task->work);
}

napi_value Prepare(napi_env env, napi_callback_info info) {
    size_t argc = 3;
    napi_value args[3] = {};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    napi_value promise;
    std::unique_ptr<PrepareTask> task(new PrepareTask());
    napi_create_promise(env, &task->deferred, &promise);
    double density = 0;
    bool ok = argc == 3 && napi_get_value_double(env, args[1], &density) == napi_ok &&
        std::isfinite(density) && density > 0 && density <= 8 &&
        napi_get_value_int32(env, args[2], &task->budget) == napi_ok && task->budget > 0 && task->budget <= 8000 &&
        OH_PixelmapNative_ConvertPixelmapNativeFromNapi(env, args[0], &task->pixelmap) == IMAGE_SUCCESS &&
        napi_create_reference(env, args[0], 1, &task->source) == napi_ok;
    task->density = density;
    task->scene->owner = env;
    napi_value name;
    napi_create_string_utf8(env, "shatterPrepare", NAPI_AUTO_LENGTH, &name);
    if (ok) {
        ok = napi_create_async_work(env, nullptr, name, PreparePixels, CompletePrepare, task.get(), &task->work) == napi_ok;
    }
    if (ok) { ok = napi_queue_async_work(env, task->work) == napi_ok; }
    if (!ok) {
        if (task->pixelmap) { OH_PixelmapNative_Destroy(&task->pixelmap); }
        if (task->source) { napi_delete_reference(env, task->source); }
        if (task->work) { napi_delete_async_work(env, task->work); }
        napi_value nullValue;
        napi_get_null(env, &nullValue);
        napi_resolve_deferred(env, task->deferred, nullValue);
    } else {
        task.release();
        Renderer::Get().Post([]() { Renderer::Get().Warm(); });
    }
    return promise;
}

void CallEvent(napi_env env, napi_value callback, void *, void *data) {
    if (!env || !callback) { return; }
    napi_value event, result;
    napi_create_int32(env, int(reinterpret_cast<intptr_t>(data)) - 2, &event);
    napi_call_function(env, Undefined(env), callback, 1, &event, &result);
}

napi_value Attach(napi_env env, napi_callback_info info) {
    size_t argc = 3;
    napi_value args[3] = {};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    int id = 0;
    char surface[32] = {};
    size_t length = 0;
    napi_valuetype type;
    napi_threadsafe_function callback = nullptr;
    bool ok = argc == 3 && napi_get_value_int32(env, args[0], &id) == napi_ok && id > 0 &&
        napi_get_value_string_utf8(env, args[1], surface, sizeof(surface), &length) == napi_ok &&
        length > 0 && length < sizeof(surface) - 1 && napi_typeof(env, args[2], &type) == napi_ok && type == napi_function;
    char *end = nullptr;
    const uint64_t surfaceId = ok ? std::strtoull(surface, &end, 10) : 0;
    ok = ok && surfaceId != 0 && end && *end == '\0';
    napi_value name;
    napi_create_string_utf8(env, "shatterEvents", NAPI_AUTO_LENGTH, &name);
    if (ok) {
        ok = napi_create_threadsafe_function(env, args[2], nullptr, name, 0, 1, nullptr, nullptr, nullptr,
                                            CallEvent, &callback) == napi_ok;
    }
    if (ok) {
        napi_unref_threadsafe_function(env, callback);
        Renderer::Get().Post([id, surfaceId, callback]() { Renderer::Get().Attach(id, surfaceId, callback); });
    }
    napi_value result;
    napi_get_boolean(env, ok, &result);
    return result;
}

napi_value Begin(napi_env env, napi_callback_info info) {
    size_t argc = 2;
    napi_value args[2] = {};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    int id = 0;
    double duration = 0;
    if (argc == 2 && napi_get_value_int32(env, args[0], &id) == napi_ok &&
        napi_get_value_double(env, args[1], &duration) == napi_ok && std::isfinite(duration)) {
        Renderer::Get().Post([id, duration]() { Renderer::Get().Begin(id, duration); });
    }
    return Undefined(env);
}

napi_value Close(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value arg;
    int id = 0;
    napi_get_cb_info(env, info, &argc, &arg, nullptr, nullptr);
    if (argc == 1 && napi_get_value_int32(env, arg, &id) == napi_ok && id > 0) {
        Renderer::Get().Post([id]() { Renderer::Get().Close(id); });
    }
    return Undefined(env);
}

void Cleanup(void *data) {
    auto owner = static_cast<napi_env>(data);
    // 环境销毁时先撤销 producer 对 TSFN 的引用，再允许 NAPI 回收它们。
    auto done = std::make_shared<std::promise<void>>();
    auto future = done->get_future();
    Renderer::Get().Post([owner, done]() { Renderer::Get().CloseOwner(owner); done->set_value(); });
    future.wait();
}
} // namespace
} // namespace shatter

void ShatterRegister(napi_env env, napi_value exports) {
    napi_property_descriptor properties[] = {
        {"shatterPrepare", nullptr, shatter::Prepare, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"shatterAttach", nullptr, shatter::Attach, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"shatterBegin", nullptr, shatter::Begin, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"shatterClose", nullptr, shatter::Close, nullptr, nullptr, nullptr, napi_default, nullptr}
    };
    napi_define_properties(env, exports, sizeof(properties) / sizeof(properties[0]), properties);
    napi_add_env_cleanup_hook(env, shatter::Cleanup, env);
}
