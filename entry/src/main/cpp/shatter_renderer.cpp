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
#include <qos/qos.h>
#include <atomic>
#include <chrono>
#include <condition_variable>
#include <cstdlib>
#include <cstring>
#include <cstdio>
#include <deque>
#include <fstream>
#include <functional>
#include <future>
#include <memory>
#include <mutex>
#include <string>
#include <thread>
#include <unordered_map>

namespace shatter {
namespace {
using Clock = std::chrono::steady_clock;

struct Scene {
    Geometry geometry;
    std::vector<uint8_t> pixels;
    std::vector<float> delays;
    napi_env owner = nullptr;
    napi_threadsafe_function callback = nullptr; // 仅渲染线程持有/释放。
    OHNativeWindow *window = nullptr;
    EGLSurface surface = EGL_NO_SURFACE;
    GLuint texture = 0, buffer = 0, vao = 0;
    GLsizei count = 0;
    bool running = false;
    double durationMs = 1100;
    Clock::time_point started;
    long long startedVsyncNs = 0;
    Clock::time_point deadline = Clock::now() + std::chrono::milliseconds(3050);
    float stageX = 0, stageY = 0;
    float lastProgress = 0;
};

struct StageEventPayload {
    int layerHandle;
    int event;
};

struct Stage {
    int width = 0, height = 0;
    int bufferWidth = 0, bufferHeight = 0;
    napi_env owner = nullptr;
    napi_threadsafe_function callback = nullptr;
    OHNativeWindow *window = nullptr;
    EGLSurface surface = EGL_NO_SURFACE;
    std::unordered_map<int, std::shared_ptr<Scene>> layers;
};

void Notify(Scene &scene, int event) {
    if (scene.callback) {
        // 只有首帧、完成/失败事件，不经过 ArkTS 逐帧调度。
        napi_call_threadsafe_function(scene.callback, reinterpret_cast<void *>(intptr_t(event + 2)),
                                      napi_tsfn_nonblocking);
    }
}

void NotifyStage(Stage &stage, int layerHandle, int event) {
    if (!stage.callback) { return; }
    auto *payload = new StageEventPayload{layerHandle, event};
    if (napi_call_threadsafe_function(stage.callback, payload, napi_tsfn_nonblocking) != napi_ok) {
        delete payload;
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
    void Warm(std::string cacheDir = {}) {
        if (!cacheDir.empty()) { cacheDir_ = std::move(cacheDir); }
        Initialize();
    }
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
        scene.startedVsyncNs = 0;
        scene.running = true;
    }
    void Close(int id) {
        auto found = scenes_.find(id);
        if (found == scenes_.end()) { return; }
        Release(*found->second);
        scenes_.erase(found);
    }
    void OpenStage(int stageId, uint64_t surfaceId, int width, int height,
                   int bufferWidth, int bufferHeight, napi_env owner, napi_threadsafe_function callback) {
        auto stage = std::make_shared<Stage>();
        stage->width = width;
        stage->height = height;
        stage->bufferWidth = bufferWidth;
        stage->bufferHeight = bufferHeight;
        stage->owner = owner;
        stage->callback = callback;
        if (!Initialize()) {
            OH_LOG_Print(LOG_APP, LOG_WARN, 0x0000, "Shatter", "Stage init failed");
            NotifyStage(*stage, 0, -1);
            ReleaseStage(*stage);
            return;
        }
        GLint maxTexture = 0;
        glGetIntegerv(GL_MAX_TEXTURE_SIZE, &maxTexture);
        if (bufferWidth > maxTexture || bufferHeight > maxTexture ||
            OH_NativeWindow_CreateNativeWindowFromSurfaceId(surfaceId, &stage->window) != 0 || !stage->window) {
            NotifyStage(*stage, 0, -1);
            ReleaseStage(*stage);
            return;
        }
        if (OH_NativeWindow_NativeWindowHandleOpt(stage->window, SET_BUFFER_GEOMETRY,
                                                 bufferWidth, bufferHeight) != 0) {
            NotifyStage(*stage, 0, -1);
            ReleaseStage(*stage);
            return;
        }
        EGLint format = 0;
        if (!eglGetConfigAttrib(display_, config_, EGL_NATIVE_VISUAL_ID, &format) ||
            OH_NativeWindow_NativeWindowHandleOpt(stage->window, SET_FORMAT, format) != 0) {
            NotifyStage(*stage, 0, -1);
            ReleaseStage(*stage);
            return;
        }
        stage->surface = eglCreateWindowSurface(display_, config_,
            reinterpret_cast<EGLNativeWindowType>(stage->window), nullptr);
        if (stage->surface == EGL_NO_SURFACE ||
            !eglMakeCurrent(display_, stage->surface, stage->surface, context_)) {
            NotifyStage(*stage, 0, -1);
            ReleaseStage(*stage);
            return;
        }
        eglSwapInterval(display_, 0);
        // 初始化一张全透明首帧，防止切换瞬间出现未清屏残留。
        glViewport(0, 0, bufferWidth, bufferHeight);
        glClearColor(0, 0, 0, 0);
        glClear(GL_COLOR_BUFFER_BIT);
        eglSwapBuffers(display_, stage->surface);
        stages_.emplace(stageId, stage);
    }
    void StageAdd(int stageId, int sceneId, float stageX, float stageY) {
        auto stageIt = stages_.find(stageId);
        auto sceneIt = scenes_.find(sceneId);
        if (stageIt == stages_.end() || sceneIt == scenes_.end()) {
            if (stageIt != stages_.end()) { NotifyStage(*stageIt->second, sceneId, -1); }
            return;
        }
        auto &stage = *stageIt->second;
        auto scene = sceneIt->second;
        scenes_.erase(sceneIt);
        scene->stageX = stageX;
        scene->stageY = stageY;
        scene->lastProgress = 0;
        scene->deadline = Clock::now() + std::chrono::milliseconds(3050);
        if (!eglMakeCurrent(display_, stage.surface, stage.surface, context_) ||
            !UploadLayerResources(*scene)) {
            ReleaseLayerResources(*scene);
            NotifyStage(stage, sceneId, -1);
            return;
        }
        stage.layers.emplace(sceneId, scene);
        if (!DrawStage(stage)) {
            FailStage(stageId);
            return;
        }
        NotifyStage(stage, sceneId, 0);
    }
    void StageBegin(int stageId, int sceneId, double durationMs) {
        auto stageIt = stages_.find(stageId);
        if (stageIt == stages_.end()) { return; }
        auto layerIt = stageIt->second->layers.find(sceneId);
        if (layerIt == stageIt->second->layers.end() || layerIt->second->running) { return; }
        auto &scene = *layerIt->second;
        scene.durationMs = std::max(0.0, std::min(1100.0, durationMs));
        scene.started = Clock::now();
        scene.startedVsyncNs = 0;
        scene.running = true;
    }
    void StageRemove(int stageId, int sceneId) {
        auto stageIt = stages_.find(stageId);
        if (stageIt == stages_.end()) { return; }
        auto &stage = *stageIt->second;
        auto layerIt = stage.layers.find(sceneId);
        if (layerIt == stage.layers.end()) { return; }
        ReleaseLayerResources(*layerIt->second);
        stage.layers.erase(layerIt);
        if (stage.surface != EGL_NO_SURFACE) { DrawStage(stage); }
    }
    void CloseStage(int stageId) {
        auto stageIt = stages_.find(stageId);
        if (stageIt == stages_.end()) { return; }
        ReleaseStage(*stageIt->second);
        stages_.erase(stageIt);
    }
    void CloseOwner(napi_env owner) {
        for (auto it = scenes_.begin(); it != scenes_.end();) {
            if (it->second->owner == owner) {
                Release(*it->second);
                it = scenes_.erase(it);
            } else { ++it; }
        }
        for (auto it = stages_.begin(); it != stages_.end();) {
            if (it->second->owner == owner) {
                ReleaseStage(*it->second);
                it = stages_.erase(it);
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
    static void OnVSync(long long timestamp, void *data) {
        auto &self = *static_cast<Renderer *>(data);
        {
            std::lock_guard<std::mutex> lock(self.mutex_);
            self.vsyncTimestampNs_ = timestamp;
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
    static uint64_t HashBytes(uint64_t h, const char *s) {
        if (!s) { return h; }
        for (const unsigned char *p = reinterpret_cast<const unsigned char *>(s); *p; ++p) {
            h ^= uint64_t(*p);
            h *= 1099511628211ULL;
        }
        return h;
    }
    uint64_t ProgramCacheHash() const {
        uint64_t h = 14695981039346656037ULL;
        h = HashBytes(h, reinterpret_cast<const char *>(glGetString(GL_VENDOR)));
        h = HashBytes(h, "|");
        h = HashBytes(h, reinterpret_cast<const char *>(glGetString(GL_RENDERER)));
        h = HashBytes(h, "|");
        h = HashBytes(h, reinterpret_cast<const char *>(glGetString(GL_VERSION)));
        h = HashBytes(h, "|");
        h = HashBytes(h, kVertexShader);
        h = HashBytes(h, "|");
        h = HashBytes(h, kFragmentShader);
        return h;
    }
    struct ProgramBinaryHeader {
        uint32_t magic;
        uint32_t version;
        uint64_t hash;
        GLenum format;
        uint32_t size;
    };
    static constexpr uint32_t kProgramBinaryMagic = 0x53485452u; // 'SHTR'
    static constexpr uint32_t kProgramBinaryVersion = 1u;
    std::string ProgramCachePath() const {
        if (cacheDir_.empty()) { return {}; }
        return cacheDir_ + "/shatter_prog_v1.bin";
    }
    bool TryLoadCachedProgram(GLuint program, uint64_t expectedHash) {
        const std::string path = ProgramCachePath();
        if (path.empty()) { return false; }
        GLint numFormats = 0;
        glGetIntegerv(GL_NUM_PROGRAM_BINARY_FORMATS, &numFormats);
        if (numFormats <= 0) { return false; }
        std::ifstream in(path, std::ios::binary);
        if (!in) { return false; }
        ProgramBinaryHeader hdr{};
        if (!in.read(reinterpret_cast<char *>(&hdr), sizeof(hdr))) { return false; }
        if (hdr.magic != kProgramBinaryMagic || hdr.version != kProgramBinaryVersion ||
            hdr.hash != expectedHash || hdr.size == 0 || hdr.size > 4 * 1024 * 1024) {
            return false;
        }
        std::vector<uint8_t> bin(hdr.size);
        if (!in.read(reinterpret_cast<char *>(bin.data()), hdr.size)) { return false; }
        glProgramBinary(program, hdr.format, bin.data(), GLsizei(bin.size()));
        GLint ok = 0;
        glGetProgramiv(program, GL_LINK_STATUS, &ok);
        if (ok) {
            OH_LOG_Print(LOG_APP, LOG_INFO, 0x0000, "Shatter",
                "Loaded cached shader binary (%u bytes)", hdr.size);
            return true;
        }
        return false;
    }
    void SaveCachedProgram(GLuint program, uint64_t hash) {
        const std::string path = ProgramCachePath();
        if (path.empty()) { return; }
        GLint numFormats = 0;
        glGetIntegerv(GL_NUM_PROGRAM_BINARY_FORMATS, &numFormats);
        if (numFormats <= 0) { return; }
        GLint len = 0;
        glGetProgramiv(program, GL_PROGRAM_BINARY_LENGTH, &len);
        if (len <= 0 || len > 4 * 1024 * 1024) { return; }
        std::vector<uint8_t> bin(static_cast<size_t>(len));
        GLenum format = 0;
        GLsizei written = 0;
        glGetProgramBinary(program, len, &written, &format, bin.data());
        if (written <= 0 || glGetError() != GL_NO_ERROR) { return; }
        ProgramBinaryHeader hdr{kProgramBinaryMagic, kProgramBinaryVersion, hash, format, uint32_t(written)};
        const std::string tmp = path + ".tmp";
        std::ofstream out(tmp, std::ios::binary | std::ios::trunc);
        if (!out) { return; }
        out.write(reinterpret_cast<const char *>(&hdr), sizeof(hdr));
        out.write(reinterpret_cast<const char *>(bin.data()), written);
        out.close();
        if (out) { std::rename(tmp.c_str(), path.c_str()); }
        else { std::remove(tmp.c_str()); }
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
        const uint64_t shaderHash = ProgramCacheHash();
        GLuint program = glCreateProgram();
        if (!TryLoadCachedProgram(program, shaderHash)) {
            GLuint vertex = Shader(GL_VERTEX_SHADER, kVertexShader);
            GLuint fragment = Shader(GL_FRAGMENT_SHADER, kFragmentShader);
            if (!vertex || !fragment) {
                glDeleteShader(vertex);
                glDeleteShader(fragment);
                glDeleteProgram(program);
                return false;
            }
            glAttachShader(program, vertex);
            glAttachShader(program, fragment);
            glProgramParameteri(program, GL_PROGRAM_BINARY_RETRIEVABLE_HINT, GL_TRUE);
            glLinkProgram(program);
            glDeleteShader(vertex);
            glDeleteShader(fragment);
            GLint ok = 0;
            glGetProgramiv(program, GL_LINK_STATUS, &ok);
            if (!ok) { glDeleteProgram(program); return false; }
            SaveCachedProgram(program, shaderHash);
        }
        program_ = program;
        viewport_ = glGetUniformLocation(program_, "viewportSize");
        bufferScale_ = glGetUniformLocation(program_, "bufferScale");
        imageSize_ = glGetUniformLocation(program_, "imageSize");
        originOffset_ = glGetUniformLocation(program_, "originOffset");
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
            vsync_ = OH_NativeVSync_Create("PetrelgramShatter", 17);
        }
        return vsync_ != nullptr;
    }
    bool UploadLayerResources(Scene &scene) {
        const auto &g = scene.geometry;
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
        scene.delays.reserve(g.tiles.size());
        for (const auto &tile : g.tiles) { scene.delays.push_back(tile.delay); }
        std::vector<uint8_t>().swap(scene.pixels);
        std::vector<Tile>().swap(scene.geometry.tiles);
        return glGetError() == GL_NO_ERROR;
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
                                                 g.bufferWidth, g.bufferHeight) != 0) { return false; }
        EGLint format = 0;
        if (!eglGetConfigAttrib(display_, config_, EGL_NATIVE_VISUAL_ID, &format) ||
            OH_NativeWindow_NativeWindowHandleOpt(scene.window, SET_FORMAT, format) != 0) { return false; }
        scene.surface = eglCreateWindowSurface(display_, config_,
            reinterpret_cast<EGLNativeWindowType>(scene.window), nullptr);
        if (scene.surface == EGL_NO_SURFACE ||
            !eglMakeCurrent(display_, scene.surface, scene.surface, context_)) { return false; }
        eglSwapInterval(display_, 0); // VSync 统一驱动；不在每个行的 swap 再串行等待。
        return UploadLayerResources(scene);
    }
    void DrawLayer(const Scene &scene, float originX, float originY, float topPad, float progress) {
        if (progress >= 1.0f || scene.count == 0) { return; }
        const auto &g = scene.geometry;
        glBindVertexArray(scene.vao);
        glBindBuffer(GL_ARRAY_BUFFER, scene.buffer);
        glActiveTexture(GL_TEXTURE0);
        glBindTexture(GL_TEXTURE_2D, scene.texture);
        glUniform2f(imageSize_, g.width, g.height);
        glUniform2f(originOffset_, originX, originY);
        glUniform1f(top_, topPad);
        glUniform1f(progress_, progress);
        // 整数像素切口共享边，无多重采样：静止区域不会出现拼片缝隙。
        const GLsizei started = static_cast<GLsizei>(StartedTileCount(scene.delays, progress));
        DrawRange(started, scene.count - started, 0);
        DrawRange(0, started, 1);
    }
    bool Draw(Scene &scene, float progress) {
        if (!eglMakeCurrent(display_, scene.surface, scene.surface, context_)) { return false; }
        const auto &g = scene.geometry;
        glViewport(0, 0, g.bufferWidth, g.bufferHeight);
        glClearColor(0, 0, 0, 0);
        glClear(GL_COLOR_BUFFER_BIT);
        if (progress < 1) {
            glUseProgram(program_);
            glUniform2f(viewport_, g.surfaceWidth, g.surfaceHeight);
            glUniform2f(bufferScale_, float(g.bufferWidth) / g.surfaceWidth,
                        float(g.bufferHeight) / g.surfaceHeight);
            DrawLayer(scene, 0.0f, 0.0f, float(g.top), progress);
        }
        return eglSwapBuffers(display_, scene.surface) == EGL_TRUE;
    }
    bool DrawStage(Stage &stage) {
        if (stage.surface == EGL_NO_SURFACE ||
            !eglMakeCurrent(display_, stage.surface, stage.surface, context_)) { return false; }
        glViewport(0, 0, stage.bufferWidth, stage.bufferHeight);
        glClearColor(0, 0, 0, 0);
        glClear(GL_COLOR_BUFFER_BIT);
        if (!stage.layers.empty()) {
            glUseProgram(program_);
            glUniform2f(viewport_, float(stage.width), float(stage.height));
            glUniform2f(bufferScale_, float(stage.bufferWidth) / float(stage.width),
                        float(stage.bufferHeight) / float(stage.height));
            for (const auto &entry : stage.layers) {
                const auto &layer = *entry.second;
                DrawLayer(layer, layer.stageX, layer.stageY, 0.0f, layer.lastProgress);
            }
        }
        return eglSwapBuffers(display_, stage.surface) == EGL_TRUE;
    }
    void FailStage(int stageId) {
        OH_LOG_Print(LOG_APP, LOG_WARN, 0x0000, "Shatter",
            "Shatter stage failed: id=%{public}d egl=%{public}x gl=%{public}x", stageId, eglGetError(), glGetError());
        auto found = stages_.find(stageId);
        if (found != stages_.end()) { NotifyStage(*found->second, 0, -1); }
        CloseStage(stageId);
    }
    void ReleaseLayerResources(Scene &scene) {
        if (context_ != EGL_NO_CONTEXT && parking_ != EGL_NO_SURFACE &&
            eglMakeCurrent(display_, parking_, parking_, context_)) {
            if (scene.texture) { glDeleteTextures(1, &scene.texture); scene.texture = 0; }
            if (scene.buffer) { glDeleteBuffers(1, &scene.buffer); scene.buffer = 0; }
            if (scene.vao) { glDeleteVertexArrays(1, &scene.vao); scene.vao = 0; }
        }
    }
    void ReleaseStage(Stage &stage) {
        if (context_ != EGL_NO_CONTEXT && parking_ != EGL_NO_SURFACE &&
            eglMakeCurrent(display_, parking_, parking_, context_)) {
            for (auto &entry : stage.layers) {
                auto &layer = *entry.second;
                if (layer.texture) { glDeleteTextures(1, &layer.texture); layer.texture = 0; }
                if (layer.buffer) { glDeleteBuffers(1, &layer.buffer); layer.buffer = 0; }
                if (layer.vao) { glDeleteVertexArrays(1, &layer.vao); layer.vao = 0; }
            }
        }
        stage.layers.clear();
        if (stage.surface != EGL_NO_SURFACE) { eglDestroySurface(display_, stage.surface); stage.surface = EGL_NO_SURFACE; }
        if (stage.window) { OH_NativeWindow_DestroyNativeWindow(stage.window); stage.window = nullptr; }
        if (stage.callback) { napi_release_threadsafe_function(stage.callback, napi_tsfn_release); stage.callback = nullptr; }
    }
    void DrawRange(GLsizei first, GLsizei count, int moving) {
        if (count == 0) { return; }
        // ES3.0 has no base-instance draw: offset immutable attributes instead.
        // Constant GL command count, no buffer rewrite, each tile submitted once.
        for (GLuint i = 0; i < 2; ++i) {
            glVertexAttribPointer(i, 4, GL_FLOAT, GL_FALSE, sizeof(Tile),
                reinterpret_cast<void *>(size_t(first) * sizeof(Tile) + i * 4 * sizeof(float)));
        }
        glUniform1i(moving_, moving);
        glDrawArraysInstanced(GL_TRIANGLES, 0, 6, count);
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
    bool HasActiveWork() const {
        if (!scenes_.empty()) { return true; }
        for (const auto &item : stages_) {
            if (!item.second->layers.empty()) { return true; }
        }
        return false;
    }
    Clock::time_point NextDeadline() const {
        auto deadline = Clock::time_point::max();
        for (const auto &item : scenes_) { deadline = std::min(deadline, item.second->deadline); }
        for (const auto &st : stages_) {
            for (const auto &layer : st.second->layers) {
                deadline = std::min(deadline, layer.second->deadline);
            }
        }
        return deadline;
    }
    float AdvanceProgress(Scene &scene, const Clock::time_point &now, long long vsyncTs) {
        double elapsed = 0;
        if (vsyncTs > 0) {
            if (scene.startedVsyncNs == 0) {
                const double wallElapsed = std::chrono::duration<double, std::milli>(now - scene.started).count();
                const double clamped = std::max(0.0, std::min(16.0, wallElapsed));
                scene.startedVsyncNs = vsyncTs - static_cast<long long>(clamped * 1000000.0);
            }
            elapsed = std::max(0.0, double(vsyncTs - scene.startedVsyncNs) * 1e-6);
        } else {
            elapsed = std::chrono::duration<double, std::milli>(now - scene.started).count();
        }
        return scene.durationMs > 0 ? float(std::min(1.0, elapsed / scene.durationMs)) : 1.0f;
    }
    void Run() {
        bool requested = false;
        bool qosElevated = false;
        bool highRateActive = false;
        for (;;) {
            std::deque<std::function<void()>> commands;
            bool tick = false;
            long long vsyncTs = 0;
            {
                std::unique_lock<std::mutex> lock(mutex_);
                const bool activeWork = HasActiveWork();
                if (!activeWork) {
                    if (highRateActive && vsync_) {
                        // 空闲时显式归零帧率投票，既省电又保证下次无触摸远端删除时
                        // 0 -> 120 的状态跃迁能立即唤醒 HarmonyOS HGM 拉满 LTPO 120Hz。
                        OH_NativeVSync_ExpectedRateRange idleRange{0, 0, 0};
                        OH_NativeVSync_SetExpectedFrameRateRange(vsync_, &idleRange);
                        highRateActive = false;
                    }
                    if (qosElevated) {
                        OH_QoS_ResetThreadQoS();
                        qosElevated = false;
                    }
                }
                auto ready = [&]() { return stopping_ || tick_ || !commands_.empty(); };
                if (!activeWork) { wake_.wait(lock, ready); }
                else {
                    wake_.wait_until(lock, NextDeadline(), ready);
                }
                if (stopping_) { break; }
                tick = tick_;
                tick_ = false;
                vsyncTs = vsyncTimestampNs_;
                commands.swap(commands_);
            }
            if (tick) { requested = false; }
            for (auto &command : commands) { command(); }
            if (HasActiveWork()) {
                if (!qosElevated) {
                    OH_QoS_SetThreadQoS(QOS_USER_INTERACTIVE);
                    qosElevated = true;
                }
                if (!highRateActive && vsync_) {
                    OH_NativeVSync_ExpectedRateRange activeRange{120, 120, 120};
                    OH_NativeVSync_SetExpectedFrameRateRange(vsync_, &activeRange);
                    highRateActive = true;
                }
            }
            std::vector<int> completed, failed;
            std::vector<std::pair<int, float>> toDraw;
            std::vector<int> stagesToDraw, stagesFailed;
            std::vector<std::pair<int, int>> stageLayersCompleted, stageLayersExpired;
            const auto now = Clock::now();
            bool needsFrame = false;
            for (auto &item : scenes_) {
                auto &scene = *item.second;
                if (now >= scene.deadline) { failed.push_back(item.first); continue; }
                if (!scene.running) { continue; }
                if (tick) {
                    const float progress = AdvanceProgress(scene, now, vsyncTs);
                    toDraw.push_back({item.first, progress});
                    if (progress < 1.0f) { needsFrame = true; }
                } else {
                    needsFrame = true;
                }
            }
            for (auto &stItem : stages_) {
                auto &stage = *stItem.second;
                bool stageDirty = false;
                for (auto &layerItem : stage.layers) {
                    auto &layer = *layerItem.second;
                    if (now >= layer.deadline) {
                        stageLayersExpired.push_back({stItem.first, layerItem.first});
                        stageDirty = true;
                        continue;
                    }
                    if (!layer.running) { continue; }
                    if (tick) {
                        const float progress = AdvanceProgress(layer, now, vsyncTs);
                        layer.lastProgress = progress;
                        stageDirty = true;
                        if (progress >= 1.0f) {
                            stageLayersCompleted.push_back({stItem.first, layerItem.first});
                        } else {
                            needsFrame = true;
                        }
                    } else {
                        needsFrame = true;
                    }
                }
                if (stageDirty) { stagesToDraw.push_back(stItem.first); }
            }
            // 在 Draw/eglSwapBuffers 之前预先请求下一帧 VSync，避免绘制贴近 8.33ms 边界时漏拍。
            if (needsFrame && !requested) {
                requested = vsync_ && OH_NativeVSync_RequestFrame(vsync_, OnVSync, this) == 0;
                if (!requested) {
                    for (const auto &item : scenes_) { if (item.second->running) { failed.push_back(item.first); } }
                    for (const auto &stItem : stages_) { if (!stItem.second->layers.empty()) { stagesFailed.push_back(stItem.first); } }
                    toDraw.clear();
                    stagesToDraw.clear();
                }
            }
            for (const auto &entry : toDraw) {
                auto found = scenes_.find(entry.first);
                if (found == scenes_.end()) { continue; }
                if (!Draw(*found->second, entry.second)) { failed.push_back(entry.first); continue; }
                if (entry.second >= 1.0f) { completed.push_back(entry.first); }
            }
            for (const auto &expired : stageLayersExpired) {
                auto stIt = stages_.find(expired.first);
                if (stIt == stages_.end()) { continue; }
                auto layerIt = stIt->second->layers.find(expired.second);
                if (layerIt == stIt->second->layers.end()) { continue; }
                NotifyStage(*stIt->second, expired.second, -1);
                ReleaseLayerResources(*layerIt->second);
                stIt->second->layers.erase(layerIt);
            }
            for (int stageId : stagesToDraw) {
                auto stIt = stages_.find(stageId);
                if (stIt == stages_.end()) { continue; }
                if (!DrawStage(*stIt->second)) { stagesFailed.push_back(stageId); }
            }
            for (const auto &done : stageLayersCompleted) {
                auto stIt = stages_.find(done.first);
                if (stIt == stages_.end()) { continue; }
                auto layerIt = stIt->second->layers.find(done.second);
                if (layerIt == stIt->second->layers.end()) { continue; }
                NotifyStage(*stIt->second, done.second, 1);
                ReleaseLayerResources(*layerIt->second);
                stIt->second->layers.erase(layerIt);
            }
            for (int id : completed) {
                auto found = scenes_.find(id);
                if (found != scenes_.end()) { Notify(*found->second, 1); Close(id); }
            }
            for (int id : failed) { Fail(id); }
            for (int stageId : stagesFailed) { FailStage(stageId); }
            if (!needsFrame) { requested = false; }
        }
        if (highRateActive && vsync_) {
            OH_NativeVSync_ExpectedRateRange idleRange{0, 0, 0};
            OH_NativeVSync_SetExpectedFrameRateRange(vsync_, &idleRange);
        }
        if (qosElevated) { OH_QoS_ResetThreadQoS(); }
        for (auto &item : scenes_) { Release(*item.second); }
        scenes_.clear();
        for (auto &item : stages_) { ReleaseStage(*item.second); }
        stages_.clear();
        if (vsync_) { OH_NativeVSync_Destroy(vsync_); vsync_ = nullptr; }
        ResetContext();
    }
    std::mutex mutex_;
    std::condition_variable wake_;
    std::deque<std::function<void()>> commands_;
    bool stopping_ = false, tick_ = false;
    long long vsyncTimestampNs_ = 0;
    std::unordered_map<int, std::shared_ptr<Scene>> scenes_;
    std::unordered_map<int, std::shared_ptr<Stage>> stages_;
    EGLDisplay display_ = EGL_NO_DISPLAY;
    EGLContext context_ = EGL_NO_CONTEXT;
    EGLSurface parking_ = EGL_NO_SURFACE;
    EGLConfig config_ = nullptr;
    GLuint program_ = 0;
    GLint viewport_ = -1, bufferScale_ = -1, imageSize_ = -1, originOffset_ = -1, top_ = -1, progress_ = -1, moving_ = -1;
    std::string cacheDir_;
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
    void *address = nullptr;
    const auto access = OH_PixelmapNative_AccessPixels(task.pixelmap, &address);
    if (access != IMAGE_SUCCESS || !address) {
        OH_LOG_Print(LOG_APP, LOG_WARN, 0x0000, "Shatter", "Shatter prepare pixels inaccessible: %{public}d", access);
        return;
    }
    const auto *src = static_cast<const uint8_t *>(address);
    // 扫描非透明像素的紧致外接框：单条消息截图通常是整屏宽度的透明 Row，
    // 裁剪掉左右/上下纯透明留白后再转换像素和生成碎片，可大幅减少纹理与合成面积。
    uint32_t cropX = 0, cropY = 0, cropW = width, cropH = height;
    if (alpha != PIXELMAP_ALPHA_TYPE_OPAQUE) {
        uint32_t minX = width, minY = height, maxX = 0, maxY = 0;
        for (uint32_t y = 0; y < height; ++y) {
            const auto *row = src + size_t(y) * stride;
            uint32_t x = 0;
            while (x < width && row[size_t(x) * 4 + 3] == 0) { ++x; }
            if (x == width) { continue; }
            if (y < minY) { minY = y; }
            maxY = y;
            if (x < minX) { minX = x; }
            uint32_t rx = width - 1;
            while (rx > maxX && row[size_t(rx) * 4 + 3] == 0) { --rx; }
            if (rx > maxX) { maxX = rx; }
        }
        if (minX <= maxX && minY <= maxY) {
            cropX = minX > 0 ? minX - 1 : 0;
            cropY = minY > 0 ? minY - 1 : 0;
            const uint32_t endX = maxX + 1 < width ? maxX + 1 : width - 1;
            const uint32_t endY = maxY + 1 < height ? maxY + 1 : height - 1;
            cropW = endX - cropX + 1;
            cropH = endY - cropY + 1;
        }
    }
    auto &pixels = task.scene->pixels;
    pixels.resize(size_t(cropW) * cropH * 4);
    const bool isRgba = format == PIXEL_FORMAT_RGBA_8888;
    if (isRgba && alpha == PIXELMAP_ALPHA_TYPE_PREMULTIPLIED) {
        const size_t copyBytes = size_t(cropW) * 4;
        for (uint32_t y = 0; y < cropH; ++y) {
            const auto *row = src + size_t(cropY + y) * stride + size_t(cropX) * 4;
            std::memcpy(pixels.data() + size_t(y) * copyBytes, row, copyBytes);
        }
    } else if (!isRgba && alpha == PIXELMAP_ALPHA_TYPE_PREMULTIPLIED) {
        for (uint32_t y = 0; y < cropH; ++y) {
            const auto *row = src + size_t(cropY + y) * stride + size_t(cropX) * 4;
            auto *out = pixels.data() + size_t(y) * cropW * 4;
            for (uint32_t x = 0; x < cropW; ++x) {
                const size_t o = size_t(x) * 4;
                uint32_t px = 0;
                std::memcpy(&px, row + o, 4);
                px = (px & 0xFF00FF00u) | ((px & 0x00FF0000u) >> 16) | ((px & 0x000000FFu) << 16);
                std::memcpy(out + o, &px, 4);
            }
        }
    } else if (alpha == PIXELMAP_ALPHA_TYPE_OPAQUE) {
        const int red = isRgba ? 0 : 2;
        const int blue = 2 - red;
        for (uint32_t y = 0; y < cropH; ++y) {
            const auto *row = src + size_t(cropY + y) * stride + size_t(cropX) * 4;
            auto *out = pixels.data() + size_t(y) * cropW * 4;
            for (uint32_t x = 0; x < cropW; ++x) {
                const size_t o = size_t(x) * 4;
                out[o] = row[o + red];
                out[o + 1] = row[o + 1];
                out[o + 2] = row[o + blue];
                out[o + 3] = 255;
            }
        }
    } else {
        const int red = isRgba ? 0 : 2;
        const int blue = 2 - red;
        for (uint32_t y = 0; y < cropH; ++y) {
            const auto *row = src + size_t(cropY + y) * stride + size_t(cropX) * 4;
            auto *out = pixels.data() + size_t(y) * cropW * 4;
            for (uint32_t x = 0; x < cropW; ++x) {
                const size_t o = size_t(x) * 4;
                const uint8_t a = row[o + 3];
                if (a == 0) {
                    out[o] = out[o + 1] = out[o + 2] = out[o + 3] = 0;
                } else if (a == 255) {
                    out[o] = row[o + red];
                    out[o + 1] = row[o + 1];
                    out[o + 2] = row[o + blue];
                    out[o + 3] = 255;
                } else {
                    out[o] = static_cast<uint8_t>((unsigned(row[o + red]) * a + 127) / 255);
                    out[o + 1] = static_cast<uint8_t>((unsigned(row[o + 1]) * a + 127) / 255);
                    out[o + 2] = static_cast<uint8_t>((unsigned(row[o + blue]) * a + 127) / 255);
                    out[o + 3] = a;
                }
            }
        }
    }
    OH_PixelmapNative_UnaccessPixels(task.pixelmap);
    static std::atomic<uint32_t> seeds{uint32_t(Clock::now().time_since_epoch().count())};
    task.scene->geometry = MakeGeometry(int(cropW), int(cropH), task.density, task.budget,
                                        seeds.fetch_add(1), pixels.data());
    task.scene->geometry.offsetX = int(cropX);
    task.scene->geometry.offsetY = int(cropY);
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
        Number(env, result, "offsetX", g.offsetX);
        Number(env, result, "offsetY", g.offsetY);
        Number(env, result, "surfaceWidth", g.surfaceWidth);
        Number(env, result, "surfaceHeight", g.surfaceHeight);
        Number(env, result, "top", g.top);
        Number(env, result, "tileCount", int(g.tiles.size()));
        Number(env, result, "bufferWidth", g.bufferWidth);
        Number(env, result, "bufferHeight", g.bufferHeight);
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

void CallStageEvent(napi_env env, napi_value callback, void *, void *data) {
    std::unique_ptr<StageEventPayload> payload(static_cast<StageEventPayload *>(data));
    if (!env || !callback || !payload) { return; }
    napi_value args[2] = {};
    napi_create_int32(env, payload->layerHandle, &args[0]);
    napi_create_int32(env, payload->event, &args[1]);
    napi_value result;
    napi_call_function(env, Undefined(env), callback, 2, args, &result);
}

napi_value StageOpen(napi_env env, napi_callback_info info) {
    size_t argc = 6;
    napi_value args[6] = {};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    char surface[32] = {};
    size_t length = 0;
    int width = 0, height = 0, bufferWidth = 0, bufferHeight = 0;
    napi_valuetype type;
    napi_threadsafe_function callback = nullptr;
    bool ok = argc == 6 &&
        napi_get_value_string_utf8(env, args[0], surface, sizeof(surface), &length) == napi_ok &&
        length > 0 && length < sizeof(surface) - 1 &&
        napi_get_value_int32(env, args[1], &width) == napi_ok && width > 0 && width <= 8192 &&
        napi_get_value_int32(env, args[2], &height) == napi_ok && height > 0 && height <= 8192 &&
        napi_get_value_int32(env, args[3], &bufferWidth) == napi_ok && bufferWidth > 0 && bufferWidth <= 8192 &&
        napi_get_value_int32(env, args[4], &bufferHeight) == napi_ok && bufferHeight > 0 && bufferHeight <= 8192 &&
        uint64_t(bufferWidth) * uint64_t(bufferHeight) <= 1572864 &&
        napi_typeof(env, args[5], &type) == napi_ok && type == napi_function;
    char *end = nullptr;
    const uint64_t surfaceId = ok ? std::strtoull(surface, &end, 10) : 0;
    ok = ok && surfaceId != 0 && end && *end == '\0';
    napi_value name;
    napi_create_string_utf8(env, "shatterStageEvents", NAPI_AUTO_LENGTH, &name);
    if (ok) {
        ok = napi_create_threadsafe_function(env, args[5], nullptr, name, 0, 1, nullptr, nullptr, nullptr,
                                             CallStageEvent, &callback) == napi_ok;
    }
    int stageId = 0;
    if (ok) {
        static std::atomic<int> nextStageId{1};
        stageId = nextStageId.fetch_add(1);
        napi_unref_threadsafe_function(env, callback);
        Renderer::Get().Post([stageId, surfaceId, width, height, bufferWidth, bufferHeight, env, callback]() {
            Renderer::Get().OpenStage(stageId, surfaceId, width, height, bufferWidth, bufferHeight, env, callback);
        });
    }
    napi_value result;
    napi_create_int32(env, stageId, &result);
    return result;
}

napi_value StageAdd(napi_env env, napi_callback_info info) {
    size_t argc = 4;
    napi_value args[4] = {};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    int stageId = 0, sceneId = 0;
    double stageX = 0, stageY = 0;
    bool ok = argc == 4 &&
        napi_get_value_int32(env, args[0], &stageId) == napi_ok && stageId > 0 &&
        napi_get_value_int32(env, args[1], &sceneId) == napi_ok && sceneId > 0 &&
        napi_get_value_double(env, args[2], &stageX) == napi_ok && std::isfinite(stageX) &&
        napi_get_value_double(env, args[3], &stageY) == napi_ok && std::isfinite(stageY);
    if (ok) {
        Renderer::Get().Post([stageId, sceneId, stageX, stageY]() {
            Renderer::Get().StageAdd(stageId, sceneId, float(stageX), float(stageY));
        });
    }
    napi_value result;
    napi_get_boolean(env, ok, &result);
    return result;
}

napi_value StageBegin(napi_env env, napi_callback_info info) {
    size_t argc = 3;
    napi_value args[3] = {};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    int stageId = 0, sceneId = 0;
    double duration = 0;
    if (argc == 3 &&
        napi_get_value_int32(env, args[0], &stageId) == napi_ok && stageId > 0 &&
        napi_get_value_int32(env, args[1], &sceneId) == napi_ok && sceneId > 0 &&
        napi_get_value_double(env, args[2], &duration) == napi_ok && std::isfinite(duration)) {
        Renderer::Get().Post([stageId, sceneId, duration]() {
            Renderer::Get().StageBegin(stageId, sceneId, duration);
        });
    }
    return Undefined(env);
}

napi_value StageRemove(napi_env env, napi_callback_info info) {
    size_t argc = 2;
    napi_value args[2] = {};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    int stageId = 0, sceneId = 0;
    if (argc == 2 &&
        napi_get_value_int32(env, args[0], &stageId) == napi_ok && stageId > 0 &&
        napi_get_value_int32(env, args[1], &sceneId) == napi_ok && sceneId > 0) {
        Renderer::Get().Post([stageId, sceneId]() { Renderer::Get().StageRemove(stageId, sceneId); });
    }
    return Undefined(env);
}

napi_value StageClose(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value arg;
    int stageId = 0;
    napi_get_cb_info(env, info, &argc, &arg, nullptr, nullptr);
    if (argc == 1 && napi_get_value_int32(env, arg, &stageId) == napi_ok && stageId > 0) {
        Renderer::Get().Post([stageId]() { Renderer::Get().CloseStage(stageId); });
    }
    return Undefined(env);
}

napi_value Warm(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value arg = nullptr;
    napi_get_cb_info(env, info, &argc, &arg, nullptr, nullptr);
    std::string cacheDir;
    if (argc >= 1 && arg != nullptr) {
        napi_valuetype type = napi_undefined;
        if (napi_typeof(env, arg, &type) == napi_ok && type == napi_string) {
            size_t len = 0;
            if (napi_get_value_string_utf8(env, arg, nullptr, 0, &len) == napi_ok && len > 0 && len < 512) {
                cacheDir.resize(len);
                napi_get_value_string_utf8(env, arg, &cacheDir[0], len + 1, &len);
            }
        }
    }
    Renderer::Get().Post([dir = std::move(cacheDir)]() mutable { Renderer::Get().Warm(std::move(dir)); });
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
        {"shatterWarm", nullptr, shatter::Warm, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"shatterPrepare", nullptr, shatter::Prepare, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"shatterAttach", nullptr, shatter::Attach, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"shatterBegin", nullptr, shatter::Begin, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"shatterClose", nullptr, shatter::Close, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"shatterStageOpen", nullptr, shatter::StageOpen, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"shatterStageAdd", nullptr, shatter::StageAdd, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"shatterStageBegin", nullptr, shatter::StageBegin, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"shatterStageRemove", nullptr, shatter::StageRemove, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"shatterStageClose", nullptr, shatter::StageClose, nullptr, nullptr, nullptr, napi_default, nullptr}
    };
    napi_define_properties(env, exports, sizeof(properties) / sizeof(properties[0]), properties);
    napi_add_env_cleanup_hook(env, shatter::Cleanup, env);
}
