#include "tgcalls/FakeAudioDeviceModule.h"
#include "tgcalls/group/GroupInstanceCustomImpl.h"
#include "tgcalls_ohos_local_video.h"

#include "api/video/video_frame.h"
#include "api/video/video_sink_interface.h"
#include "libyuv.h"

#include <hilog/log.h>
#include <native_buffer/native_buffer.h>
#include <ohaudio/native_audio_routing_manager.h>
#include <ohaudio/native_audio_session_manager.h>
#include <ohaudio/native_audiocapturer.h>
#include <ohaudio/native_audiorenderer.h>
#include <ohaudio/native_audiostreambuilder.h>
#include <native_window/external_window.h>

#include <chrono>
#include <atomic>
#include <cerrno>
#include <cmath>
#include <condition_variable>
#include <cstdlib>
#include <functional>
#include <map>
#include <poll.h>
#include <string>
#include <thread>
#include <unistd.h>
#include <vector>

#define TGLOG(fmt, ...) OH_LOG_Print(LOG_APP, LOG_INFO, 0x0000, "tgcalls-audio", fmt, ##__VA_ARGS__)
#define TGVLOG(fmt, ...) OH_LOG_Print(LOG_APP, LOG_INFO, 0x0000, "tgcalls-video", fmt, ##__VA_ARGS__)

#include <algorithm>
#include <array>
#include <cstdint>
#include <cstring>
#include <memory>
#include <mutex>
#include <set>

namespace {

using JoinCallback = void (*)(void *, uint32_t, const char *);
using StateCallback = void (*)(void *, bool);
using AudioActivityCallback = void (*)(void *, uint32_t, bool);
using LocalVideoStateCallback = void (*)(void *, int, bool, int);
using VideoGeometryCallback = void (*)(void *, const char *, int, int);
using BroadcastRequestCallback = void (*)(
    void *, uint64_t, int, int64_t, int64_t, int32_t, int);

struct AudioActivityState {
    bool speaking = false;
    int audibleFrames = 0;
    std::chrono::steady_clock::time_point lastAudible{};
};

class OhosBroadcastPartTask final : public tgcalls::BroadcastPartTask {
public:
    explicit OhosBroadcastPartTask(std::function<void(int64_t)> completion)
        : timeCompletion_(std::move(completion)) {
    }

    explicit OhosBroadcastPartTask(std::function<void(tgcalls::BroadcastPart &&)> completion)
        : partCompletion_(std::move(completion)) {
    }

    void cancel() override {
        std::lock_guard<std::mutex> lock(mutex_);
        cancelled_ = true;
        timeCompletion_ = nullptr;
        partCompletion_ = nullptr;
    }

    void completeTime(int64_t timestampMilliseconds) {
        std::function<void(int64_t)> completion;
        {
            std::lock_guard<std::mutex> lock(mutex_);
            if (cancelled_) { return; }
            cancelled_ = true;
            completion = std::move(timeCompletion_);
            partCompletion_ = nullptr;
        }
        if (completion) { completion(timestampMilliseconds); }
    }

    void completePart(tgcalls::BroadcastPart &&part) {
        std::function<void(tgcalls::BroadcastPart &&)> completion;
        {
            std::lock_guard<std::mutex> lock(mutex_);
            if (cancelled_) { return; }
            cancelled_ = true;
            completion = std::move(partCompletion_);
            timeCompletion_ = nullptr;
        }
        if (completion) { completion(std::move(part)); }
    }

private:
    std::mutex mutex_;
    bool cancelled_ = false;
    std::function<void(int64_t)> timeCompletion_;
    std::function<void(tgcalls::BroadcastPart &&)> partCompletion_;
};

class OhosAudioRenderer final : public tgcalls::FakeAudioDeviceModule::Renderer {
public:
    OhosAudioRenderer() {
        const OH_AudioCommon_Result managerResult =
            OH_AudioManager_GetAudioSessionManager(&audioSessionManager_);
        const bool initialCommunicationMode = PreferredMediaRouteUsesSco();
        const OH_AudioCommon_Result sceneResult = audioSessionManager_ != nullptr
            ? OH_AudioSessionManager_SetScene(
                audioSessionManager_, initialCommunicationMode
                    ? AUDIO_SESSION_SCENE_VOICE_COMMUNICATION
                    : AUDIO_SESSION_SCENE_MEDIA)
            : AUDIOCOMMON_RESULT_ERROR_INVALID_PARAM;
        const OH_AudioCommon_Result deactivatedCallbackResult = audioSessionManager_ != nullptr
            ? OH_AudioSessionManager_RegisterSessionDeactivatedCallback(
                audioSessionManager_, OnSessionDeactivated)
            : AUDIOCOMMON_RESULT_ERROR_INVALID_PARAM;
        const OH_AudioCommon_Result stateCallbackResult = audioSessionManager_ != nullptr
            ? OH_AudioSessionManager_RegisterStateChangeCallback(
                audioSessionManager_, OnSessionStateChanged)
            : AUDIOCOMMON_RESULT_ERROR_INVALID_PARAM;
        const bool configured = CreateRendererLocked(initialCommunicationMode);
        TGLOG("audio session config: manager=%{public}d scene=%{public}d "
              "initialCommunication=%{public}d "
              "deactivatedCb=%{public}d stateCb=%{public}d renderer=%{public}d",
              static_cast<int>(managerResult), static_cast<int>(sceneResult),
              initialCommunicationMode ? 1 : 0,
              static_cast<int>(deactivatedCallbackResult), static_cast<int>(stateCallbackResult),
              configured ? 1 : 0);
    }

    ~OhosAudioRenderer() override {
        std::lock_guard<std::mutex> lifecycleLock(lifecycleMutex_);
        if (renderer_ != nullptr) {
            OH_AudioRenderer_Stop(renderer_);
            OH_AudioRenderer_Release(renderer_);
            renderer_ = nullptr;
        }
        if (audioSessionManager_ != nullptr) {
            if (audioSessionActivated_) {
                OH_AudioSessionManager_DeactivateAudioSession(audioSessionManager_);
                audioSessionActivated_ = false;
            }
            OH_AudioSessionManager_UnregisterStateChangeCallback(
                audioSessionManager_, OnSessionStateChanged);
            OH_AudioSessionManager_UnregisterSessionDeactivatedCallback(
                audioSessionManager_, OnSessionDeactivated);
            audioSessionManager_ = nullptr;
        }
    }

    void Start() {
        EnsureStarted();
    }

    // 1:1 通话的听筒/扬声器切换。仅改变默认输出偏好；耳机等外设仍优先。
    bool SetPreferredOutputDevice(bool speaker) {
        std::lock_guard<std::mutex> lifecycleLock(lifecycleMutex_);
        if (renderer_ == nullptr) {
            return false;
        }
        const OH_AudioStream_Result result = OH_AudioRenderer_SetDefaultOutputDevice(
            renderer_, speaker ? AUDIO_DEVICE_TYPE_SPEAKER : AUDIO_DEVICE_TYPE_EARPIECE);
        TGLOG("preferred output device: speaker=%{public}d result=%{public}d",
              speaker ? 1 : 0, static_cast<int>(result));
        return result == AUDIOSTREAM_SUCCESS;
    }

    bool SetMicrophoneActive(bool active) {
        microphoneActive_.store(active, std::memory_order_release);
        const bool communicationMode = active || PreferredMediaRouteUsesSco();
        routeEvaluationPending_.store(false, std::memory_order_release);
        TGLOG("microphone route evaluation: active=%{public}d communication=%{public}d",
              active ? 1 : 0, communicationMode ? 1 : 0);
        return SetCommunicationMode(communicationMode);
    }

    // Bluetooth headsets cannot play an A2DP media stream while their SCO
    // microphone path is active. Keep receive-only live rooms on media volume,
    // but rebuild the inner hardware renderer as VOICE_COMMUNICATION while the
    // local microphone is unmuted. The FakeAudioDeviceModule keeps the same
    // Renderer object, so WebRTC playout continues across the route switch.
    bool SetCommunicationMode(bool enabled) {
        std::lock_guard<std::mutex> lifecycleLock(lifecycleMutex_);
        if (communicationMode_ == enabled && renderer_ != nullptr) {
            return true;
        }

        const bool previousMode = communicationMode_;
        OH_AudioStream_State previousState = AUDIOSTREAM_STATE_INVALID;
        const bool shouldRestart = rendererStarted_.load(std::memory_order_acquire) ||
            (renderer_ != nullptr &&
             OH_AudioRenderer_GetCurrentState(renderer_, &previousState) == AUDIOSTREAM_SUCCESS &&
             previousState == AUDIOSTREAM_STATE_RUNNING);
        if (renderer_ != nullptr) {
            OH_AudioRenderer_Stop(renderer_);
            OH_AudioRenderer_Release(renderer_);
            renderer_ = nullptr;
        }
        rendererStarted_.store(false, std::memory_order_release);

        OH_AudioCommon_Result deactivateResult = AUDIOCOMMON_RESULT_SUCCESS;
        if (audioSessionManager_ != nullptr &&
            OH_AudioSessionManager_IsAudioSessionActivated(audioSessionManager_)) {
            deactivateResult =
                OH_AudioSessionManager_DeactivateAudioSession(audioSessionManager_);
        }
        audioSessionActivated_ = false;
        const OH_AudioCommon_Result sceneResult = audioSessionManager_ != nullptr
            ? OH_AudioSessionManager_SetScene(
                audioSessionManager_, enabled
                    ? AUDIO_SESSION_SCENE_VOICE_COMMUNICATION
                    : AUDIO_SESSION_SCENE_MEDIA)
            : AUDIOCOMMON_RESULT_ERROR_INVALID_PARAM;

        const bool configured = CreateRendererLocked(enabled);
        if (!configured) {
            // Preserve receive audio if the requested route cannot be built.
            if (audioSessionManager_ != nullptr) {
                OH_AudioSessionManager_SetScene(
                    audioSessionManager_, previousMode
                        ? AUDIO_SESSION_SCENE_VOICE_COMMUNICATION
                        : AUDIO_SESSION_SCENE_MEDIA);
            }
            CreateRendererLocked(previousMode);
        }
        if (shouldRestart && renderer_ != nullptr) {
            EnsureStartedLocked();
        }
        TGLOG("renderer mode switch: requestedCommunication=%{public}d configured=%{public}d "
              "previousState=%{public}d deactivate=%{public}d scene=%{public}d activeMode=%{public}d",
              enabled ? 1 : 0, configured ? 1 : 0, static_cast<int>(previousState),
              static_cast<int>(deactivateResult), static_cast<int>(sceneResult),
              communicationMode_ ? 1 : 0);
        return configured;
    }

    bool Render(const tgcalls::AudioFrame &frame) override {
        if (frame.audio_samples == nullptr || frame.num_samples == 0) {
            return true;
        }
        if (frame.samples_per_sec != kSampleRate || frame.num_channels != kChannels ||
            frame.bytes_per_sample != kFrameBytes) {
            TGLOG("unsupported PCM: rate=%{public}u channels=%{public}zu bytesPerFrame=%{public}zu",
                  frame.samples_per_sec, frame.num_channels, frame.bytes_per_sample);
            return false;
        }
        if (routeEvaluationPending_.exchange(false, std::memory_order_acq_rel) &&
            !microphoneActive_.load(std::memory_order_acquire)) {
            SetCommunicationMode(PreferredMediaRouteUsesSco());
        }
        const auto *data = reinterpret_cast<const uint8_t *>(frame.audio_samples);
        int16_t peak = 0;
        for (size_t i = 0; i < frame.num_samples; ++i) {
            const int32_t value = static_cast<int32_t>(frame.audio_samples[i]);
            const int16_t absolute = static_cast<int16_t>(
                value < 0 ? std::min(-value, 32767) : value);
            if (absolute > peak) { peak = absolute; }
        }
        if (!logged_) {
            logged_ = true;
            TGLOG("first frame: samples_per_sec=%{public}u num_channels=%{public}zu num_samples=%{public}zu "
                  "bytes_per_sample=%{public}zu totalBytes=%{public}zu peak=%{public}d",
                  frame.samples_per_sec, frame.num_channels, frame.num_samples, frame.bytes_per_sample,
                  frame.num_samples * sizeof(int16_t), static_cast<int>(peak));
        }
        // FakeAudioDeviceModule starts pulling silence before the SFU join has
        // completed. Do not build seconds of stale silence while the renderer
        // is still prepared. Session connectivity starts OHAudio; a non-zero
        // frame remains a fallback if media wins that race.
        const bool hasSignal = peak > 0;
        if (!hasSignal && !rendererStarted_.load(std::memory_order_acquire)) {
            return true;
        }
        if (hasSignal && !loggedFirstSignal_) {
            loggedFirstSignal_ = true;
            TGLOG("first mixed PCM signal peak=%{public}d; starting renderer", static_cast<int>(peak));
        }
        // FakeAudioDeviceModule's NeedMorePlayData result is the TOTAL number
        // of int16 samples across all channels (960 for 10 ms stereo), while
        // bytes_per_sample is the size of one interleaved sample frame (4).
        // Multiplying both read twice past WebRTC's 1920-byte playout buffer,
        // producing static and replacing valid remote speech with OOB memory.
        size_t byteCount = frame.num_samples * sizeof(int16_t);
        byteCount -= byteCount % kFrameBytes;  // whole 2ch/S16 frames only
        if (byteCount == 0) {
            return true;
        }
        bool logProducerHealth = false;
        size_t queuedBytes = 0;
        {
            std::lock_guard<std::mutex> lock(mutex_);
            renderCalls_ += 1;
            // If one block exceeds the whole buffer, keep only its tail (frame-aligned).
            if (byteCount > buffer_.size()) {
                data += byteCount - buffer_.size();
                byteCount = buffer_.size();
            }
            // Evict WHOLE frames so read_ never lands mid-sample; a byte-granular
            // eviction desynchronises L/R and turns speech into continuous noise.
            const size_t freeSpace = buffer_.size() - size_;
            if (byteCount > freeSpace) {
                size_t evict = byteCount - freeSpace;
                evict += (kFrameBytes - evict % kFrameBytes) % kFrameBytes;  // round up to a frame
                if (evict > size_) { evict = size_; }
                read_ = (read_ + evict) % buffer_.size();
                size_ -= evict;
            }
            for (size_t i = 0; i < byteCount; ++i) {
                buffer_[write_] = data[i];
                write_ = (write_ + 1) % buffer_.size();
            }
            size_ += byteCount;
            if (renderCalls_ == 200) {
                logProducerHealth = true;
                queuedBytes = size_;
            }
        }
        if (logProducerHealth) {
            int64_t framesWritten = -1;
            uint32_t hardwareUnderflows = 0;
            OH_AudioStream_Result framesResult = AUDIOSTREAM_ERROR_INVALID_PARAM;
            OH_AudioStream_Result underflowResult = AUDIOSTREAM_ERROR_INVALID_PARAM;
            {
                std::lock_guard<std::mutex> lifecycleLock(lifecycleMutex_);
                if (renderer_ != nullptr) {
                    framesResult = OH_AudioRenderer_GetFramesWritten(renderer_, &framesWritten);
                    underflowResult = OH_AudioRenderer_GetUnderflowCount(renderer_, &hardwareUnderflows);
                }
            }
            TGLOG("PCM producer health: renders=%{public}u queuedBytes=%{public}zu framesWritten=%{public}lld "
                  "framesResult=%{public}d hardwareUnderflows=%{public}u underflowResult=%{public}d",
                  renderCalls_, queuedBytes, static_cast<long long>(framesWritten),
                  static_cast<int>(framesResult), hardwareUnderflows, static_cast<int>(underflowResult));
        }
        // Audio focus and the hardware stream can be revoked while the JS
        // process and WebRTC transport stay alive (screen-off, calls, route
        // changes). Re-check the real OHAudio state once a second so a stale
        // rendererStarted_ flag can't leave decoded audio permanently silent.
        const bool shouldCheckRenderer = hasSignal &&
            (!rendererStarted_.load(std::memory_order_acquire) || renderCalls_ % 100 == 0);
        if (shouldCheckRenderer) {
            EnsureStarted();
        }
        return true;
    }

    int32_t WaitForUs() override {
        // FakeAudioDeviceModule sleeps *after* each render. Returning a fixed
        // 10 ms therefore adds processing time on every cycle and slowly
        // starves OHAudio. Schedule against a steady absolute 10 ms clock.
        const auto now = std::chrono::steady_clock::now();
        if (!clockStarted_) {
            clockStarted_ = true;
            nextFrameAt_ = now + std::chrono::milliseconds(10);
            return 10000;
        }
        nextFrameAt_ += std::chrono::milliseconds(10);
        if (nextFrameAt_ <= now || nextFrameAt_ - now > std::chrono::milliseconds(20)) {
            nextFrameAt_ = now + std::chrono::milliseconds(10);
        }
        return static_cast<int32_t>(std::chrono::duration_cast<std::chrono::microseconds>(
            nextFrameAt_ - now).count());
    }

private:
    bool PreferredMediaRouteUsesSco() {
        OH_AudioRoutingManager *routingManager = nullptr;
        const OH_AudioCommon_Result managerResult =
            OH_AudioManager_GetAudioRoutingManager(&routingManager);
        OH_AudioDeviceDescriptorArray *devices = nullptr;
        const OH_AudioCommon_Result devicesResult = routingManager != nullptr
            ? OH_AudioRoutingManager_GetPreferredOutputDevice(
                routingManager, AUDIOSTREAM_USAGE_MOVIE, &devices)
            : AUDIOCOMMON_RESULT_ERROR_INVALID_PARAM;
        const uint32_t deviceCount = devices != nullptr ? devices->size : 0;
        OH_AudioDevice_Type firstDeviceType = AUDIO_DEVICE_TYPE_INVALID;
        bool usesSco = false;
        if (devicesResult == AUDIOCOMMON_RESULT_SUCCESS && devices != nullptr) {
            for (uint32_t index = 0; index < devices->size; ++index) {
                OH_AudioDevice_Type deviceType = AUDIO_DEVICE_TYPE_INVALID;
                if (devices->descriptors[index] != nullptr &&
                    OH_AudioDeviceDescriptor_GetDeviceType(
                        devices->descriptors[index], &deviceType) ==
                        AUDIOCOMMON_RESULT_SUCCESS) {
                    if (index == 0) {
                        firstDeviceType = deviceType;
                    }
                    if (deviceType == AUDIO_DEVICE_TYPE_BLUETOOTH_SCO) {
                        usesSco = true;
                    }
                }
            }
            OH_AudioRoutingManager_ReleaseDevices(routingManager, devices);
        }
        TGLOG("preferred media route: manager=%{public}d devices=%{public}d "
              "count=%{public}u firstType=%{public}d sco=%{public}d",
              static_cast<int>(managerResult), static_cast<int>(devicesResult),
              deviceCount, static_cast<int>(firstDeviceType), usesSco ? 1 : 0);
        return usesSco;
    }

    bool CreateRendererLocked(bool communicationMode) {
        OH_AudioStreamBuilder *builder = nullptr;
        if (OH_AudioStreamBuilder_Create(&builder, AUDIOSTREAM_TYPE_RENDERER) != AUDIOSTREAM_SUCCESS) {
            return false;
        }
        // Use the long-standing callback ABI used by OpenHarmony's own native
        // renderer test. All fields are initialized: older platform builds can
        // otherwise interpret uninitialized optional callbacks and stop their
        // write loop unpredictably.
        OH_AudioRenderer_Callbacks callbacks{};
        callbacks.OH_AudioRenderer_OnWriteData = WriteData;
        callbacks.OH_AudioRenderer_OnInterruptEvent = OnInterrupt;
        callbacks.OH_AudioRenderer_OnStreamEvent = OnStreamEvent;
        callbacks.OH_AudioRenderer_OnError = OnError;
        OH_AudioRenderer *nextRenderer = nullptr;
        const OH_AudioStream_Usage usage = communicationMode
            ? AUDIOSTREAM_USAGE_VOICE_COMMUNICATION
            : AUDIOSTREAM_USAGE_MOVIE;
        const OH_AudioStream_Result outputChangeCallbackResult =
            OH_AudioStreamBuilder_SetRendererOutputDeviceChangeCallback(
                builder, OnOutputDeviceChanged, this);
        const bool configured =
            OH_AudioStreamBuilder_SetSamplingRate(builder, kSampleRate) == AUDIOSTREAM_SUCCESS &&
            OH_AudioStreamBuilder_SetChannelCount(builder, kChannels) == AUDIOSTREAM_SUCCESS &&
            OH_AudioStreamBuilder_SetSampleFormat(builder, AUDIOSTREAM_SAMPLE_S16LE) == AUDIOSTREAM_SUCCESS &&
            OH_AudioStreamBuilder_SetEncodingType(builder, AUDIOSTREAM_ENCODING_TYPE_RAW) == AUDIOSTREAM_SUCCESS &&
            // The WebRTC pull thread and the hardware renderer use independent
            // clocks. NORMAL mode gives the system enough elasticity to absorb
            // their small drift; FAST mode repeatedly underruns on real devices
            // and is heard as clicks/static.
            OH_AudioStreamBuilder_SetLatencyMode(builder, AUDIOSTREAM_LATENCY_MODE_NORMAL) == AUDIOSTREAM_SUCCESS &&
            OH_AudioStreamBuilder_SetRendererInfo(builder, usage) == AUDIOSTREAM_SUCCESS &&
            OH_AudioStreamBuilder_SetRendererCallback(builder, callbacks, this) == AUDIOSTREAM_SUCCESS &&
            outputChangeCallbackResult == AUDIOSTREAM_SUCCESS &&
            OH_AudioStreamBuilder_GenerateRenderer(builder, &nextRenderer) == AUDIOSTREAM_SUCCESS;
        OH_AudioStreamBuilder_Destroy(builder);

        OH_AudioStream_Result fallbackDeviceResult = AUDIOSTREAM_SUCCESS;
        if (configured && communicationMode) {
            // Headsets still win while attached. When they disconnect during a
            // live conversation, use the speaker rather than the earpiece.
            fallbackDeviceResult = OH_AudioRenderer_SetDefaultOutputDevice(
                nextRenderer, AUDIO_DEVICE_TYPE_SPEAKER);
        }
        OH_AudioStream_State state = AUDIOSTREAM_STATE_INVALID;
        const bool prepared = configured && nextRenderer != nullptr &&
            OH_AudioRenderer_GetCurrentState(nextRenderer, &state) == AUDIOSTREAM_SUCCESS;
        int32_t callbackFrames = 0;
        const bool callbackSizeReady = configured && nextRenderer != nullptr &&
            OH_AudioRenderer_GetFrameSizeInCallback(nextRenderer, &callbackFrames) ==
                AUDIOSTREAM_SUCCESS;
        TGLOG("renderer config: configured=%{public}d usage=%{public}s fallbackDevice=%{public}d "
              "outputChangeCb=%{public}d prepared=%{public}d state=%{public}d callbackFrames=%{public}d "
              "callbackSizeReady=%{public}d rate=48000 ch=2 fmt=S16LE latency=normal",
              configured ? 1 : 0, communicationMode ? "voice_communication" : "movie",
              static_cast<int>(fallbackDeviceResult),
              static_cast<int>(outputChangeCallbackResult), prepared ? 1 : 0,
              static_cast<int>(state), callbackFrames, callbackSizeReady ? 1 : 0);
        if (!configured || nextRenderer == nullptr) {
            if (nextRenderer != nullptr) {
                OH_AudioRenderer_Release(nextRenderer);
            }
            return false;
        }
        renderer_ = nextRenderer;
        communicationMode_ = communicationMode;
        rendererStarted_.store(false, std::memory_order_release);
        return true;
    }

    void EnsureStarted() {
        std::lock_guard<std::mutex> lifecycleLock(lifecycleMutex_);
        EnsureStartedLocked();
    }

    void EnsureStartedLocked() {
        if (renderer_ == nullptr) {
            return;
        }
        OH_AudioCommon_Result sessionResult = AUDIOCOMMON_RESULT_ERROR_INVALID_PARAM;
        audioSessionActivated_ = audioSessionManager_ != nullptr &&
            OH_AudioSessionManager_IsAudioSessionActivated(audioSessionManager_);
        if (audioSessionManager_ != nullptr && !audioSessionActivated_) {
            OH_AudioSession_Strategy strategy{};
            strategy.concurrencyMode = CONCURRENCY_MIX_WITH_OTHERS;
            sessionResult = OH_AudioSessionManager_ActivateAudioSession(
                audioSessionManager_, &strategy);
            audioSessionActivated_ = sessionResult == AUDIOCOMMON_RESULT_SUCCESS &&
                OH_AudioSessionManager_IsAudioSessionActivated(audioSessionManager_);
        }
        OH_AudioStream_State before = AUDIOSTREAM_STATE_INVALID;
        const OH_AudioStream_Result stateResult = OH_AudioRenderer_GetCurrentState(renderer_, &before);
        const OH_AudioStream_Result startResult = before == AUDIOSTREAM_STATE_RUNNING
            ? AUDIOSTREAM_SUCCESS : OH_AudioRenderer_Start(renderer_);
        OH_AudioStream_State after = AUDIOSTREAM_STATE_INVALID;
        const OH_AudioStream_Result afterResult = OH_AudioRenderer_GetCurrentState(renderer_, &after);
        const bool started = startResult == AUDIOSTREAM_SUCCESS;
        rendererStarted_.store(started, std::memory_order_release);
        TGLOG("renderer lazy start: sessionResult=%{public}d sessionActive=%{public}d stateResult=%{public}d "
              "before=%{public}d startResult=%{public}d afterResult=%{public}d after=%{public}d",
              static_cast<int>(sessionResult), audioSessionActivated_ ? 1 : 0,
              static_cast<int>(stateResult), static_cast<int>(before), static_cast<int>(startResult),
              static_cast<int>(afterResult), static_cast<int>(after));
    }

    static int32_t WriteData(
            OH_AudioRenderer *, void *userData, void *audioData, int32_t audioDataSize) {
        auto *self = static_cast<OhosAudioRenderer *>(userData);
        if (self == nullptr || audioData == nullptr || audioDataSize <= 0) {
            return 0;
        }
        auto *output = static_cast<uint8_t *>(audioData);
        const size_t requested = static_cast<size_t>(audioDataSize);
        // Always provide a complete callback buffer. Supplying silence for a
        // not-yet-produced tail keeps the hardware pull loop alive.
        std::memset(output, 0, requested);
        size_t copied = 0;
        {
            std::lock_guard<std::mutex> lock(self->mutex_);
            copied = std::min(requested, self->size_);
            copied -= copied % kFrameBytes;  // consume whole frames only
            for (size_t i = 0; i < copied; ++i) {
                output[i] = self->buffer_[self->read_];
                self->read_ = (self->read_ + 1) % self->buffer_.size();
            }
            self->size_ -= copied;
        }
        if (copied == 0) {
            self->underruns_ += 1;
            if (self->underruns_ == 1 || self->underruns_ % 200 == 0) {
                TGLOG("renderer waiting for PCM, underruns=%{public}u", self->underruns_);
            }
        } else if (!self->loggedFirstHardwareWrite_) {
            self->loggedFirstHardwareWrite_ = true;
            TGLOG("first hardware PCM write bytes=%{public}zu requested=%{public}zu",
                  copied, requested);
        }
        // The legacy callback ABI ignores the return value; OpenHarmony's
        // official native renderer sample returns zero after filling the full
        // supplied buffer.
        return 0;
    }

    static int32_t OnInterrupt(OH_AudioRenderer *, void *userData, OH_AudioInterrupt_ForceType type,
            OH_AudioInterrupt_Hint hint) {
        auto *self = static_cast<OhosAudioRenderer *>(userData);
        TGLOG("renderer interrupt: type=%{public}d hint=%{public}d",
              static_cast<int>(type), static_cast<int>(hint));
        if (self != nullptr && (hint == AUDIOSTREAM_INTERRUPT_HINT_PAUSE ||
            hint == AUDIOSTREAM_INTERRUPT_HINT_STOP || hint == AUDIOSTREAM_INTERRUPT_HINT_MUTE ||
            hint == AUDIOSTREAM_INTERRUPT_HINT_RESUME || hint == AUDIOSTREAM_INTERRUPT_HINT_UNMUTE)) {
            self->rendererStarted_.store(false, std::memory_order_release);
        }
        return 0;
    }

    static int32_t OnStreamEvent(OH_AudioRenderer *, void *, OH_AudioStream_Event event) {
        TGLOG("renderer stream event=%{public}d", static_cast<int>(event));
        return 0;
    }

    static void OnOutputDeviceChanged(
            OH_AudioRenderer *, void *userData, OH_AudioStream_DeviceChangeReason reason) {
        auto *self = static_cast<OhosAudioRenderer *>(userData);
        TGLOG("renderer output device changed: reason=%{public}d", static_cast<int>(reason));
        if (self != nullptr) {
            // The service migrates the stream itself. Re-check its state on the
            // next non-silent WebRTC frame so unplug/reconnect and screen-off
            // recovery do not rely on a stale local RUNNING flag.
            self->rendererStarted_.store(false, std::memory_order_release);
            self->routeEvaluationPending_.store(true, std::memory_order_release);
        }
    }

    static int32_t OnError(OH_AudioRenderer *, void *, OH_AudioStream_Result error) {
        TGLOG("renderer error=%{public}d", static_cast<int>(error));
        return 0;
    }

    static int32_t OnSessionDeactivated(OH_AudioSession_DeactivatedEvent event) {
        TGLOG("audio session deactivated reason=%{public}d", static_cast<int>(event.reason));
        return 0;
    }

    static void OnSessionStateChanged(OH_AudioSession_StateChangedEvent event) {
        TGLOG("audio session state hint=%{public}d", static_cast<int>(event.stateChangeHint));
    }

    // One 2-channel signed-16-bit sample frame = 4 bytes. All ring-buffer
    // pointer moves are multiples of this so L/R stay aligned.
    static constexpr uint32_t kSampleRate = 48000;
    static constexpr size_t kChannels = 2;
    static constexpr size_t kFrameBytes = kChannels * sizeof(int16_t);
    // Two seconds of 48 kHz, stereo, signed 16-bit PCM.
    std::array<uint8_t, 48000 * 2 * 2 * 2> buffer_{};
    std::mutex mutex_;
    size_t read_ = 0;
    size_t write_ = 0;
    size_t size_ = 0;
    uint32_t underruns_ = 0;
    uint32_t renderCalls_ = 0;
    bool logged_ = false;
    bool loggedFirstSignal_ = false;
    bool loggedFirstHardwareWrite_ = false;
    bool clockStarted_ = false;
    std::chrono::steady_clock::time_point nextFrameAt_{};
    std::mutex lifecycleMutex_;
    std::atomic<bool> rendererStarted_{false};
    std::atomic<bool> microphoneActive_{false};
    std::atomic<bool> routeEvaluationPending_{false};
    OH_AudioRenderer *renderer_ = nullptr;
    OH_AudioSessionManager *audioSessionManager_ = nullptr;
    bool audioSessionActivated_ = false;
    bool communicationMode_ = false;
};

// Microphone side of FakeAudioDeviceModule. The capturer is opened only after
// the user explicitly unmutes, so joining a call never starts the microphone.
class OhosAudioRecorder final : public tgcalls::FakeAudioDeviceModule::Recorder {
public:
    ~OhosAudioRecorder() override {
        Stop();
    }

    bool Start() {
        std::lock_guard<std::mutex> lifecycleLock(lifecycleMutex_);
        if (capturer_ != nullptr) {
            OH_AudioStream_State state = AUDIOSTREAM_STATE_INVALID;
            const bool running = OH_AudioCapturer_GetCurrentState(capturer_, &state) == AUDIOSTREAM_SUCCESS &&
                state == AUDIOSTREAM_STATE_RUNNING;
            const bool restarted = running || OH_AudioCapturer_Start(capturer_) == AUDIOSTREAM_SUCCESS;
            active_.store(restarted, std::memory_order_release);
            TGLOG("capturer resume: before=%{public}d restarted=%{public}d",
                  static_cast<int>(state), restarted ? 1 : 0);
            return restarted;
        }
        OH_AudioStreamBuilder *builder = nullptr;
        if (OH_AudioStreamBuilder_Create(&builder, AUDIOSTREAM_TYPE_CAPTURER) != AUDIOSTREAM_SUCCESS) {
            return false;
        }
        OH_AudioCapturer_Callbacks callbacks{};
        callbacks.OH_AudioCapturer_OnReadData = ReadData;
        const bool configured =
            OH_AudioStreamBuilder_SetSamplingRate(builder, kSampleRate) == AUDIOSTREAM_SUCCESS &&
            OH_AudioStreamBuilder_SetChannelCount(builder, kChannels) == AUDIOSTREAM_SUCCESS &&
            OH_AudioStreamBuilder_SetSampleFormat(builder, AUDIOSTREAM_SAMPLE_S16LE) == AUDIOSTREAM_SUCCESS &&
            OH_AudioStreamBuilder_SetEncodingType(builder, AUDIOSTREAM_ENCODING_TYPE_RAW) == AUDIOSTREAM_SUCCESS &&
            OH_AudioStreamBuilder_SetLatencyMode(builder, AUDIOSTREAM_LATENCY_MODE_NORMAL) == AUDIOSTREAM_SUCCESS &&
            OH_AudioStreamBuilder_SetCapturerInfo(builder, AUDIOSTREAM_SOURCE_TYPE_VOICE_COMMUNICATION) ==
                AUDIOSTREAM_SUCCESS &&
            OH_AudioStreamBuilder_SetCapturerCallback(builder, callbacks, this) == AUDIOSTREAM_SUCCESS &&
            OH_AudioStreamBuilder_GenerateCapturer(builder, &capturer_) == AUDIOSTREAM_SUCCESS;
        OH_AudioStreamBuilder_Destroy(builder);
        const bool started = configured && capturer_ != nullptr &&
            OH_AudioCapturer_Start(capturer_) == AUDIOSTREAM_SUCCESS;
        TGLOG("capturer config: configured=%{public}d started=%{public}d rate=48000 ch=1 fmt=S16LE",
              configured ? 1 : 0, started ? 1 : 0);
        if (!started) {
            if (capturer_ != nullptr) {
                OH_AudioCapturer_Release(capturer_);
                capturer_ = nullptr;
            }
            return false;
        }
        active_.store(true);
        return true;
    }

    void Stop() {
        std::lock_guard<std::mutex> lifecycleLock(lifecycleMutex_);
        active_.store(false);
        if (capturer_ != nullptr) {
            OH_AudioCapturer_Stop(capturer_);
            OH_AudioCapturer_Release(capturer_);
            capturer_ = nullptr;
        }
        std::lock_guard<std::mutex> dataLock(dataMutex_);
        read_ = 0;
        write_ = 0;
        size_ = 0;
    }

    tgcalls::AudioFrame Record() override {
        tgcalls::AudioFrame frame{};
        if (!active_.load()) { return frame; }
        constexpr size_t required = kSamplesPerFrame * kBytesPerSample;
        {
            std::lock_guard<std::mutex> lock(dataMutex_);
            if (size_ < required) { return frame; }
            auto *output = reinterpret_cast<uint8_t *>(frameBuffer_.data());
            for (size_t i = 0; i < required; ++i) {
                output[i] = buffer_[read_];
                read_ = (read_ + 1) % buffer_.size();
            }
            size_ -= required;
        }
        frame.audio_samples = frameBuffer_.data();
        frame.num_samples = kSamplesPerFrame;
        frame.bytes_per_sample = kBytesPerSample;
        frame.num_channels = kChannels;
        frame.samples_per_sec = kSampleRate;
        frame.elapsed_time_ms = -1;
        frame.ntp_time_ms = -1;
        return frame;
    }

    int32_t WaitForUs() override {
        const auto now = std::chrono::steady_clock::now();
        if (!clockStarted_) {
            clockStarted_ = true;
            nextFrameAt_ = now + std::chrono::milliseconds(10);
            return 10000;
        }
        nextFrameAt_ += std::chrono::milliseconds(10);
        if (nextFrameAt_ <= now || nextFrameAt_ - now > std::chrono::milliseconds(20)) {
            nextFrameAt_ = now + std::chrono::milliseconds(10);
        }
        return static_cast<int32_t>(std::chrono::duration_cast<std::chrono::microseconds>(
            nextFrameAt_ - now).count());
    }

private:
    static int32_t ReadData(OH_AudioCapturer *, void *userData, void *data, int32_t length) {
        auto *self = static_cast<OhosAudioRecorder *>(userData);
        if (self == nullptr || data == nullptr || length <= 0 || !self->active_.load()) { return 0; }
        auto *input = static_cast<const uint8_t *>(data);
        size_t byteCount = static_cast<size_t>(length);
        byteCount -= byteCount % kBytesPerSample;
        std::lock_guard<std::mutex> lock(self->dataMutex_);
        if (byteCount > self->buffer_.size()) {
            input += byteCount - self->buffer_.size();
            byteCount = self->buffer_.size();
        }
        const size_t freeSpace = self->buffer_.size() - self->size_;
        if (byteCount > freeSpace) {
            size_t evict = byteCount - freeSpace;
            evict += evict % kBytesPerSample;
            if (evict > self->size_) { evict = self->size_; }
            self->read_ = (self->read_ + evict) % self->buffer_.size();
            self->size_ -= evict;
        }
        for (size_t i = 0; i < byteCount; ++i) {
            self->buffer_[self->write_] = input[i];
            self->write_ = (self->write_ + 1) % self->buffer_.size();
        }
        self->size_ += byteCount;
        return 0;
    }

    static constexpr uint32_t kSampleRate = 48000;
    static constexpr size_t kChannels = 1;
    static constexpr size_t kBytesPerSample = sizeof(int16_t);
    static constexpr size_t kSamplesPerFrame = kSampleRate / 100;
    std::array<uint8_t, kSampleRate * kBytesPerSample> buffer_{};
    std::array<int16_t, kSamplesPerFrame> frameBuffer_{};
    std::mutex lifecycleMutex_;
    std::mutex dataMutex_;
    size_t read_ = 0;
    size_t write_ = 0;
    size_t size_ = 0;
    std::atomic<bool> active_{false};
    bool clockStarted_ = false;
    std::chrono::steady_clock::time_point nextFrameAt_{};
    OH_AudioCapturer *capturer_ = nullptr;
};

// Receives decoded I420 frames from tgcalls and blits them to an XComponent's
// OHNativeWindow as RGBA. Thread-safe swap of the target window.
class OhosVideoSink : public rtc::VideoSinkInterface<webrtc::VideoFrame> {
public:
    OhosVideoSink(
            std::string endpointId,
            std::function<void(const std::string &, int, int)> geometryCallback = {})
        : endpointId_(std::move(endpointId)),
          geometryCallback_(std::move(geometryCallback)) {
    }

    ~OhosVideoSink() override {
        Release();
    }

    void SetWindow(OHNativeWindow *window, int surfaceWidth = 0, int surfaceHeight = 0) {
        std::lock_guard<std::mutex> lock(mutex_);
        if (window_ != nullptr && window_ != window) {
            OH_NativeWindow_DestroyNativeWindow(window_);
        }
        window_ = window;
        geometrySet_ = false;
        firstFrameFlushed_ = false;
        inputFrameCount_ = 0;
        surfaceWidth_ = surfaceWidth;
        surfaceHeight_ = surfaceHeight;
        if (window_ != nullptr) {
            const int32_t format = NATIVEBUFFER_PIXEL_FMT_RGBA_8888;
            const uint64_t usage = NATIVEBUFFER_USAGE_CPU_READ |
                NATIVEBUFFER_USAGE_CPU_WRITE | NATIVEBUFFER_USAGE_MEM_DMA;
            const int32_t formatResult = OH_NativeWindow_NativeWindowHandleOpt(window_, SET_FORMAT, format);
            const int32_t usageResult = OH_NativeWindow_NativeWindowHandleOpt(window_, SET_USAGE, usage);
            const int32_t swapResult = OH_NativeWindow_NativeWindowHandleOpt(window_, SET_SWAP_INTERVAL, 0);
            const int32_t scalingResult = OH_NativeWindow_NativeWindowSetScalingModeV2(
                window_, OH_SCALING_MODE_SCALE_FIT_V2);
            TGVLOG("native window configured endpoint=%{public}s format=%{public}d usage=%{public}d "
                   "swap=%{public}d scaling=%{public}d surface=%{public}dx%{public}d",
                   endpointId_.c_str(), formatResult, usageResult, swapResult, scalingResult,
                   surfaceWidth_, surfaceHeight_);
        }
    }

    void OnFrame(const webrtc::VideoFrame &frame) override {
        std::lock_guard<std::mutex> lock(mutex_);
        if (window_ == nullptr) {
            return;
        }
        ++inputFrameCount_;
        if (inputFrameCount_ == 1) {
            TGVLOG("video sink received first frame endpoint=%{public}s %{public}dx%{public}d rotation=%{public}d",
                   endpointId_.c_str(), frame.width(), frame.height(), static_cast<int>(frame.rotation()));
        }
        const int width = frame.width();
        const int height = frame.height();
        if (width <= 0 || height <= 0) {
            return;
        }
        const bool swapDimensions = frame.rotation() == webrtc::kVideoRotation_90 ||
            frame.rotation() == webrtc::kVideoRotation_270;
        const int outputWidth = swapDimensions ? height : width;
        const int outputHeight = swapDimensions ? width : height;
        if (outputWidth != lastFrameWidth_ || outputHeight != lastFrameHeight_) {
            lastFrameWidth_ = outputWidth;
            lastFrameHeight_ = outputHeight;
            if (geometryCallback_) {
                geometryCallback_(endpointId_, outputWidth, outputHeight);
            }
        }
        const int canvasWidth = surfaceWidth_ > 0 ? surfaceWidth_ : outputWidth;
        const int canvasHeight = surfaceHeight_ > 0 ? surfaceHeight_ : outputHeight;
        if (!geometrySet_ || canvasWidth != geometryWidth_ || canvasHeight != geometryHeight_) {
            const int32_t geometryResult = OH_NativeWindow_NativeWindowHandleOpt(
                window_, SET_BUFFER_GEOMETRY, canvasWidth, canvasHeight);
            if (geometryResult != 0) {
                TGVLOG("set geometry failed endpoint=%{public}s result=%{public}d %{public}dx%{public}d",
                       endpointId_.c_str(), geometryResult, canvasWidth, canvasHeight);
                return;
            }
            geometrySet_ = true;
            geometryWidth_ = canvasWidth;
            geometryHeight_ = canvasHeight;
        }
        OHNativeWindowBuffer *buffer = nullptr;
        int releaseFenceFd = -1;
        if (inputFrameCount_ == 1) {
            TGVLOG("requesting first native buffer endpoint=%{public}s", endpointId_.c_str());
        }
        const int32_t requestResult = OH_NativeWindow_NativeWindowRequestBuffer(
            window_, &buffer, &releaseFenceFd);
        if (inputFrameCount_ == 1) {
            TGVLOG("first native buffer requested endpoint=%{public}s result=%{public}d fence=%{public}d",
                   endpointId_.c_str(), requestResult, releaseFenceFd);
        }
        if (requestResult != 0 || buffer == nullptr) {
            TGVLOG("request buffer failed endpoint=%{public}s result=%{public}d",
                   endpointId_.c_str(), requestResult);
            return;
        }
        // RequestBuffer returns a release fence owned by the producer. Wait
        // until the consumer is done with this buffer, then close it. It must
        // not be reused as the acquire fence passed to FlushBuffer.
        if (releaseFenceFd >= 0) {
            pollfd descriptor{};
            descriptor.fd = releaseFenceFd;
            descriptor.events = POLLIN;
            int pollResult = -1;
            do {
                pollResult = poll(&descriptor, 1, 3000);
            } while (pollResult < 0 && (errno == EINTR || errno == EAGAIN));
            close(releaseFenceFd);
            if (pollResult <= 0) {
                TGVLOG("release fence wait failed endpoint=%{public}s result=%{public}d errno=%{public}d",
                       endpointId_.c_str(), pollResult, errno);
                OH_NativeWindow_NativeWindowAbortBuffer(window_, buffer);
                return;
            }
        }
        BufferHandle *handle = OH_NativeWindow_GetBufferHandleFromNative(buffer);
        if (handle == nullptr || handle->virAddr == nullptr) {
            TGVLOG("native buffer address unavailable endpoint=%{public}s handle=%{public}p address=%{public}p",
                   endpointId_.c_str(), handle, handle == nullptr ? nullptr : handle->virAddr);
            OH_NativeWindow_NativeWindowAbortBuffer(window_, buffer);
            return;
        }
        auto i420 = frame.video_frame_buffer()->ToI420();
        if (i420 == nullptr) {
            TGVLOG("I420 conversion unavailable endpoint=%{public}s", endpointId_.c_str());
            OH_NativeWindow_NativeWindowAbortBuffer(window_, buffer);
            return;
        }
        auto *dst = static_cast<uint8_t *>(handle->virAddr);
        const int visibleWidth = canvasWidth;
        const int visibleHeight = canvasHeight;
        // Some BufferHandle implementations expose stride in pixels while
        // newer ones expose bytes. Infer it safely for RGBA8888.
        const int dstStride = handle->stride >= visibleWidth * 4
            ? handle->stride : handle->stride * 4;
        if (handle->width < visibleWidth || handle->height < visibleHeight ||
            visibleWidth <= 0 || visibleHeight <= 0 || dstStride < visibleWidth * 4 ||
            static_cast<int64_t>(dstStride) * visibleHeight > handle->size) {
            TGVLOG("invalid native buffer endpoint=%{public}s w=%{public}d h=%{public}d stride=%{public}d size=%{public}d",
                   endpointId_.c_str(), handle->width, handle->height, handle->stride, handle->size);
            OH_NativeWindow_NativeWindowAbortBuffer(window_, buffer);
            return;
        }
        // Convert into an orientation-correct intermediate frame, then fit it
        // into the actual XComponent-sized canvas. NativeWindow's FIT mode is
        // ignored by some TEXTURE consumers, so aspect ratio is enforced here.
        std::vector<uint8_t> unrotated(static_cast<size_t>(width) * height * 4);
        int convertResult = libyuv::I420ToABGR(
            i420->DataY(), i420->StrideY(),
            i420->DataU(), i420->StrideU(),
            i420->DataV(), i420->StrideV(),
            unrotated.data(), width * 4, width, height);
        std::vector<uint8_t> oriented(static_cast<size_t>(outputWidth) * outputHeight * 4);
        if (convertResult == 0) {
            if (frame.rotation() == webrtc::kVideoRotation_0) {
                oriented.swap(unrotated);
            } else {
                libyuv::RotationMode rotation = libyuv::kRotate0;
                if (frame.rotation() == webrtc::kVideoRotation_90) { rotation = libyuv::kRotate90; }
                if (frame.rotation() == webrtc::kVideoRotation_180) { rotation = libyuv::kRotate180; }
                if (frame.rotation() == webrtc::kVideoRotation_270) { rotation = libyuv::kRotate270; }
                convertResult = libyuv::ARGBRotate(
                    unrotated.data(), width * 4, oriented.data(), outputWidth * 4,
                    width, height, rotation);
            }
        }
        const double fitScale = std::min(
            static_cast<double>(visibleWidth) / outputWidth,
            static_cast<double>(visibleHeight) / outputHeight);
        const int contentWidth = std::max(1, std::min(
            visibleWidth, static_cast<int>(std::lround(outputWidth * fitScale))));
        const int contentHeight = std::max(1, std::min(
            visibleHeight, static_cast<int>(std::lround(outputHeight * fitScale))));
        const int offsetX = (visibleWidth - contentWidth) / 2;
        const int offsetY = (visibleHeight - contentHeight) / 2;
        // Opaque black letterbox. OHOS RGBA_8888 matches libyuv ABGR bytes.
        for (int row = 0; row < visibleHeight; ++row) {
            std::fill_n(reinterpret_cast<uint32_t *>(dst + row * dstStride),
                        visibleWidth, 0xFF000000u);
        }
        if (convertResult == 0) {
            convertResult = libyuv::ARGBScale(
                oriented.data(), outputWidth * 4, outputWidth, outputHeight,
                dst + offsetY * dstStride + offsetX * 4, dstStride,
                contentWidth, contentHeight, libyuv::kFilterBilinear);
        }
        if (convertResult != 0) {
            TGVLOG("RGBA conversion failed endpoint=%{public}s result=%{public}d",
                   endpointId_.c_str(), convertResult);
            OH_NativeWindow_NativeWindowAbortBuffer(window_, buffer);
            return;
        }
        Region region{};
        const int32_t flushResult = OH_NativeWindow_NativeWindowFlushBuffer(
            window_, buffer, -1, region);
        if (flushResult != 0) {
            TGVLOG("flush buffer failed endpoint=%{public}s result=%{public}d",
                   endpointId_.c_str(), flushResult);
            OH_NativeWindow_NativeWindowAbortBuffer(window_, buffer);
            return;
        }
        if (!firstFrameFlushed_) {
            firstFrameFlushed_ = true;
            TGVLOG("first video frame flushed endpoint=%{public}s %{public}dx%{public}d rotation=%{public}d "
                   "buffer=%{public}dx%{public}d content=%{public}dx%{public}d stride=%{public}d",
                   endpointId_.c_str(), width, height, static_cast<int>(frame.rotation()),
                   handle->width, handle->height, contentWidth, contentHeight, handle->stride);
        }
    }

    void Release() {
        std::lock_guard<std::mutex> lock(mutex_);
        if (window_ != nullptr) {
            OH_NativeWindow_DestroyNativeWindow(window_);
            window_ = nullptr;
        }
    }

private:
    std::mutex mutex_;
    std::string endpointId_;
    std::function<void(const std::string &, int, int)> geometryCallback_;
    OHNativeWindow *window_ = nullptr;
    bool geometrySet_ = false;
    bool firstFrameFlushed_ = false;
    uint64_t inputFrameCount_ = 0;
    int surfaceWidth_ = 0;
    int surfaceHeight_ = 0;
    int geometryWidth_ = 0;
    int geometryHeight_ = 0;
    int lastFrameWidth_ = 0;
    int lastFrameHeight_ = 0;
};

struct Session {
    Session(StateCallback callback, void *context,
            BroadcastRequestCallback broadcastCallback, void *broadcastContext,
            AudioActivityCallback audioCallback, void *audioContext,
            LocalVideoStateCallback localVideoCallback, void *localVideoContext,
            VideoGeometryCallback geometryCallback, void *geometryContext,
            bool presentation)
        : stateCallback(callback), callbackContext(context),
          broadcastRequestCallback(broadcastCallback), broadcastCallbackContext(broadcastContext),
          audioActivityCallback(audioCallback), audioActivityCallbackContext(audioContext),
          localVideoStateCallback(localVideoCallback),
          localVideoStateCallbackContext(localVideoContext),
          videoGeometryCallback(geometryCallback),
          videoGeometryCallbackContext(geometryContext),
          isPresentation(presentation),
          localVideoPreviewSink(std::make_shared<OhosVideoSink>(
              presentation ? "__local_screen__" : "__local_camera__",
              [this](const std::string &endpointId, int width, int height) {
                  notifyVideoGeometry(endpointId, width, height);
              })) {
        auto descriptor = tgcalls::GroupInstanceDescriptor{};
        descriptor.threads = tgcalls::Threads::getThreads();
        descriptor.config.need_log = false;
        descriptor.networkStateUpdated = [this](tgcalls::GroupNetworkState state) {
            if (!isPresentation && state.isConnected && audioRenderer) {
                audioRenderer->Start();
            }
            if (stateCallback) {
                stateCallback(callbackContext, state.isConnected);
            }
        };
        descriptor.onAudioFrame = [this](uint32_t ssrc, const tgcalls::AudioFrame &frame) {
            bool first = false;
            bool firstAudible = false;
            bool activityChanged = false;
            bool speaking = false;
            int16_t peak = 0;
            if (frame.audio_samples != nullptr && frame.num_samples > 0) {
                const size_t sampleCount = frame.num_samples * frame.num_channels;
                for (size_t i = 0; i < sampleCount; ++i) {
                    const int32_t value = static_cast<int32_t>(frame.audio_samples[i]);
                    const int16_t absolute = static_cast<int16_t>(
                        value < 0 ? std::min(-value, 32767) : value);
                    if (absolute > peak) { peak = absolute; }
                }
            }
            {
                std::lock_guard<std::mutex> lock(remoteAudioMutex);
                first = loggedRemoteAudioSsrcs.insert(ssrc).second;
                if (peak > 32) {
                    firstAudible = loggedAudibleRemoteAudioSsrcs.insert(ssrc).second;
                }
                auto &activity = remoteAudioActivity[ssrc];
                const auto now = std::chrono::steady_clock::now();
                if (peak > 32) {
                    activity.lastAudible = now;
                    activity.audibleFrames = std::min(activity.audibleFrames + 1, 3);
                    // Two consecutive 10 ms frames reject isolated decoder
                    // clicks while still lighting the microphone immediately.
                    if (!activity.speaking && activity.audibleFrames >= 2) {
                        activity.speaking = true;
                        activityChanged = true;
                    }
                } else {
                    activity.audibleFrames = 0;
                    // A short hangover makes natural gaps between syllables
                    // stable; sustained silence turns the indicator off.
                    if (activity.speaking &&
                        now - activity.lastAudible >= std::chrono::milliseconds(650)) {
                        activity.speaking = false;
                        activityChanged = true;
                    }
                }
                speaking = activity.speaking;
            }
            if (activityChanged && audioActivityCallback != nullptr) {
                TGLOG("remote audio activity: ssrc=%{public}u speaking=%{public}d peak=%{public}d",
                      ssrc, speaking ? 1 : 0, static_cast<int>(peak));
                audioActivityCallback(audioActivityCallbackContext, ssrc, speaking);
            }
            if ((first || firstAudible) && frame.audio_samples != nullptr && frame.num_samples > 0) {
                TGLOG("first remote decoded frame: ssrc=%{public}u rate=%{public}u channels=%{public}zu "
                      "samplesPerChannel=%{public}zu peak=%{public}d audible=%{public}d",
                      ssrc, frame.samples_per_sec, frame.num_channels, frame.num_samples,
                      static_cast<int>(peak), firstAudible ? 1 : 0);
            }
        };
        descriptor.initialInputDeviceId = "default";
        descriptor.initialOutputDeviceId = "default";
        audioRenderer = std::make_shared<OhosAudioRenderer>();
        audioRecorder = std::make_shared<OhosAudioRecorder>();
        tgcalls::FakeAudioDeviceModule::Options audioOptions;
        audioOptions.samples_per_sec = 48000;
        audioOptions.num_channels = 2;
        descriptor.createAudioDeviceModule =
            tgcalls::FakeAudioDeviceModule::Creator(audioRenderer, audioRecorder, audioOptions);
        descriptor.requestCurrentTime = [this](std::function<void(int64_t)> completion) {
            return requestCurrentTime(std::move(completion));
        };
        descriptor.requestAudioBroadcastPart = [this](
                int64_t timestampMilliseconds, int64_t durationMilliseconds,
                std::function<void(tgcalls::BroadcastPart &&)> completion) {
            return requestBroadcastPart(
                1, timestampMilliseconds, durationMilliseconds, 0,
                tgcalls::VideoChannelDescription::Quality::Thumbnail, std::move(completion));
        };
        descriptor.requestVideoBroadcastPart = [this](
                int64_t timestampMilliseconds, int64_t durationMilliseconds, int32_t channelId,
                tgcalls::VideoChannelDescription::Quality quality,
                std::function<void(tgcalls::BroadcastPart &&)> completion) {
            return requestBroadcastPart(
                2, timestampMilliseconds, durationMilliseconds, channelId, quality, std::move(completion));
        };
        descriptor.useDummyChannel = !isPresentation;
        descriptor.disableIncomingChannels = isPresentation;
        descriptor.disableAudioInput = isPresentation;
        descriptor.initialEnableNoiseSuppression = false;
        // Telegram Desktop advertises Generic video capability even for a
        // receive-only participant. Leaving the default None makes the join
        // payload omit video information, so the server response can omit the
        // shared codec/payload description that IncomingVideoChannel needs.
        descriptor.videoContentType = isPresentation
            ? tgcalls::VideoContentType::Screencast
            : tgcalls::VideoContentType::Generic;
        descriptor.videoCodecPreferences = {
            tgcalls::VideoCodecName::H264,
            tgcalls::VideoCodecName::VP8,
            tgcalls::VideoCodecName::VP9,
        };
        instance = std::make_unique<tgcalls::GroupInstanceCustomImpl>(std::move(descriptor));
        instance->setIsMuted(true);
        audioActivityThread = std::thread([this] { runAudioActivityWatchdog(); });
    }

    ~Session() {
        {
            std::lock_guard<std::mutex> lock(broadcastMutex);
            stopped = true;
            broadcastTasks.clear();
        }
        audioActivityThreadStopped.store(true, std::memory_order_release);
        rtc::scoped_refptr<tgcalls_ohos::LocalVideoSource> outgoingSource;
        {
            std::lock_guard<std::mutex> lock(localVideoMutex);
            outgoingSource.swap(localVideoSource);
        }
        if (outgoingSource != nullptr) {
            static_cast<rtc::VideoSourceInterface<webrtc::VideoFrame> *>(
                outgoingSource.get())->RemoveSink(localVideoPreviewSink.get());
            outgoingSource->Stop();
        }
        if (instance) {
            instance->setVideoSource({});
            instance->stop();
            instance.reset();
        }
        if (audioActivityThread.joinable()) {
            audioActivityThread.join();
        }
        std::lock_guard<std::mutex> lock(videoMutex);
        for (auto &entry : videoSinks) {
            entry.second->Release();
        }
        videoSinks.clear();
        videoDescriptions.clear();
        registeredVideoSinks.clear();
        localVideoPreviewSink->Release();
    }

    void runAudioActivityWatchdog() {
        while (!audioActivityThreadStopped.load(std::memory_order_acquire)) {
            std::this_thread::sleep_for(std::chrono::milliseconds(100));
            std::vector<uint32_t> stoppedSources;
            const auto now = std::chrono::steady_clock::now();
            {
                std::lock_guard<std::mutex> lock(remoteAudioMutex);
                for (auto &entry : remoteAudioActivity) {
                    auto &activity = entry.second;
                    if (activity.speaking &&
                        now - activity.lastAudible >= std::chrono::milliseconds(650)) {
                        activity.speaking = false;
                        activity.audibleFrames = 0;
                        stoppedSources.push_back(entry.first);
                    }
                }
            }
            if (audioActivityThreadStopped.load(std::memory_order_acquire)) { break; }
            for (uint32_t ssrc : stoppedSources) {
                if (audioActivityCallback != nullptr) {
                    TGLOG("remote audio activity watchdog: ssrc=%{public}u speaking=0", ssrc);
                    audioActivityCallback(audioActivityCallbackContext, ssrc, false);
                }
            }
        }
    }

    void resumeMedia() {
        if (!isPresentation && audioRenderer) { audioRenderer->Start(); }
    }

    bool setLocalVideo(int rawMode, uint32_t width, uint32_t height) {
        if (!instance || rawMode < static_cast<int>(tgcalls_ohos::LocalVideoMode::Off) ||
            rawMode > static_cast<int>(tgcalls_ohos::LocalVideoMode::Screen)) {
            return false;
        }
        const auto mode = static_cast<tgcalls_ohos::LocalVideoMode>(rawMode);
        if ((isPresentation && mode != tgcalls_ohos::LocalVideoMode::Off &&
             mode != tgcalls_ohos::LocalVideoMode::Screen) ||
            (!isPresentation && mode == tgcalls_ohos::LocalVideoMode::Screen)) {
            return false;
        }
        rtc::scoped_refptr<tgcalls_ohos::LocalVideoSource> next;
        if (mode != tgcalls_ohos::LocalVideoMode::Off) {
            next = tgcalls_ohos::LocalVideoSource::Create(
                mode, width, height,
                [this](tgcalls_ohos::LocalVideoMode changedMode, bool active, int error) {
                    if (localVideoStateCallback != nullptr) {
                        localVideoStateCallback(
                            localVideoStateCallbackContext,
                            static_cast<int>(changedMode), active, error);
                    }
                });
            if (next == nullptr) {
                if (localVideoStateCallback != nullptr) {
                    localVideoStateCallback(
                        localVideoStateCallbackContext, rawMode, false, 2);
                }
                return false;
            }
            rtc::VideoSinkWants previewWants;
            static_cast<rtc::VideoSourceInterface<webrtc::VideoFrame> *>(
                next.get())->AddOrUpdateSink(localVideoPreviewSink.get(), previewWants);
        }

        rtc::scoped_refptr<tgcalls_ohos::LocalVideoSource> previous;
        {
            std::lock_guard<std::mutex> lock(localVideoMutex);
            previous.swap(localVideoSource);
            localVideoSource = next;
        }
        if (next != nullptr) {
            instance->setVideoSource([next] {
                return rtc::scoped_refptr<webrtc::VideoTrackSourceInterface>(next);
            });
            next->Start();
        } else {
            instance->setVideoSource({});
        }
        if (previous != nullptr) {
            static_cast<rtc::VideoSourceInterface<webrtc::VideoFrame> *>(
                previous.get())->RemoveSink(localVideoPreviewSink.get());
            previous->Stop();
        }
        TGVLOG(
            "local video requested mode=%{public}d size=%{public}ux%{public}u",
            rawMode, width, height);
        return true;
    }

    void setLocalVideoSurface(
            uint64_t surfaceId, uint32_t surfaceWidth, uint32_t surfaceHeight) {
        if (surfaceId == 0) {
            localVideoPreviewSink->SetWindow(nullptr, 0, 0);
            return;
        }
        OHNativeWindow *window = nullptr;
        if (OH_NativeWindow_CreateNativeWindowFromSurfaceId(surfaceId, &window) != 0 ||
            window == nullptr) {
            TGVLOG(
                "failed to create local preview window surface=%{public}llu",
                (unsigned long long)surfaceId);
            return;
        }
        localVideoPreviewSink->SetWindow(
            window, static_cast<int>(surfaceWidth), static_cast<int>(surfaceHeight));
        TGVLOG(
            "local preview surface set surface=%{public}llu size=%{public}ux%{public}u",
            (unsigned long long)surfaceId, surfaceWidth, surfaceHeight);
    }

    std::shared_ptr<tgcalls::BroadcastPartTask> requestCurrentTime(
            std::function<void(int64_t)> completion) {
        auto task = std::make_shared<OhosBroadcastPartTask>(std::move(completion));
        const uint64_t requestId = registerBroadcastTask(task);
        if (requestId == 0 || broadcastRequestCallback == nullptr) {
            task->completeTime(0);
            return task;
        }
        broadcastRequestCallback(broadcastCallbackContext, requestId, 0, 0, 0, 0, 0);
        return task;
    }

    std::shared_ptr<tgcalls::BroadcastPartTask> requestBroadcastPart(
            int kind, int64_t timestampMilliseconds, int64_t durationMilliseconds, int32_t channelId,
            tgcalls::VideoChannelDescription::Quality quality,
            std::function<void(tgcalls::BroadcastPart &&)> completion) {
        auto task = std::make_shared<OhosBroadcastPartTask>(std::move(completion));
        const uint64_t requestId = registerBroadcastTask(task);
        if (requestId == 0 || broadcastRequestCallback == nullptr) {
            tgcalls::BroadcastPart part;
            part.timestampMilliseconds = timestampMilliseconds;
            part.status = tgcalls::BroadcastPart::Status::NotReady;
            task->completePart(std::move(part));
            return task;
        }
        int mappedQuality = 0;
        if (quality == tgcalls::VideoChannelDescription::Quality::Medium) {
            mappedQuality = 1;
        } else if (quality == tgcalls::VideoChannelDescription::Quality::Full) {
            mappedQuality = 2;
        }
        broadcastRequestCallback(
            broadcastCallbackContext, requestId, kind, timestampMilliseconds,
            durationMilliseconds, channelId, mappedQuality);
        return task;
    }

    uint64_t registerBroadcastTask(const std::shared_ptr<OhosBroadcastPartTask> &task) {
        std::lock_guard<std::mutex> lock(broadcastMutex);
        if (stopped) { return 0; }
        const uint64_t id = nextBroadcastRequestId++;
        broadcastTasks[id] = task;
        return id;
    }

    std::shared_ptr<OhosBroadcastPartTask> takeBroadcastTask(uint64_t requestId) {
        std::lock_guard<std::mutex> lock(broadcastMutex);
        const auto it = broadcastTasks.find(requestId);
        if (it == broadcastTasks.end()) { return nullptr; }
        auto task = it->second.lock();
        broadcastTasks.erase(it);
        return task;
    }

    std::shared_ptr<OhosVideoSink> getOrCreateVideoSink(const std::string &endpointId, bool &needsRegistration) {
        std::lock_guard<std::mutex> lock(videoMutex);
        auto it = videoSinks.find(endpointId);
        if (it == videoSinks.end()) {
            it = videoSinks.emplace(
                endpointId,
                std::make_shared<OhosVideoSink>(
                    endpointId,
                    [this](const std::string &id, int width, int height) {
                        notifyVideoGeometry(id, width, height);
                    })
            ).first;
        }
        needsRegistration = registeredVideoSinks.insert(endpointId).second;
        return it->second;
    }

    void notifyVideoGeometry(const std::string &endpointId, int width, int height) {
        if (videoGeometryCallback != nullptr) {
            videoGeometryCallback(
                videoGeometryCallbackContext, endpointId.c_str(), width, height);
        }
    }

    void submitVideoDescriptions() {
        if (!instance) {
            return;
        }
        std::vector<tgcalls::VideoChannelDescription> channels;
        {
            std::lock_guard<std::mutex> lock(videoMutex);
            channels.reserve(videoDescriptions.size());
            for (const auto &entry : videoDescriptions) {
                channels.push_back(entry.second);
            }
        }
        instance->setRequestedVideoChannels(std::move(channels));
        instance->getStats([](tgcalls::GroupInstanceStats stats) {
            if (stats.incomingVideoStats.empty()) {
                TGVLOG("video stats: no SFU quality report yet");
                return;
            }
            for (const auto &entry : stats.incomingVideoStats) {
                TGVLOG("video stats endpoint=%{public}s receiving=%{public}d available=%{public}d",
                       entry.first.c_str(), entry.second.receivingQuality, entry.second.availableQuality);
            }
        });
    }

    StateCallback stateCallback = nullptr;
    void *callbackContext = nullptr;
    BroadcastRequestCallback broadcastRequestCallback = nullptr;
    void *broadcastCallbackContext = nullptr;
    AudioActivityCallback audioActivityCallback = nullptr;
    void *audioActivityCallbackContext = nullptr;
    LocalVideoStateCallback localVideoStateCallback = nullptr;
    void *localVideoStateCallbackContext = nullptr;
    VideoGeometryCallback videoGeometryCallback = nullptr;
    void *videoGeometryCallbackContext = nullptr;
    bool isPresentation = false;
    std::mutex broadcastMutex;
    bool stopped = false;
    uint64_t nextBroadcastRequestId = 1;
    std::map<uint64_t, std::weak_ptr<OhosBroadcastPartTask>> broadcastTasks;
    std::shared_ptr<OhosAudioRenderer> audioRenderer;
    std::shared_ptr<OhosAudioRecorder> audioRecorder;
    std::mutex remoteAudioMutex;
    std::set<uint32_t> loggedRemoteAudioSsrcs;
    std::set<uint32_t> loggedAudibleRemoteAudioSsrcs;
    std::map<uint32_t, AudioActivityState> remoteAudioActivity;
    std::atomic<bool> audioActivityThreadStopped{false};
    std::thread audioActivityThread;
    std::mutex videoMutex;
    std::map<std::string, std::shared_ptr<OhosVideoSink>> videoSinks;
    std::map<std::string, tgcalls::VideoChannelDescription> videoDescriptions;
    std::set<std::string> registeredVideoSinks;
    std::mutex localVideoMutex;
    rtc::scoped_refptr<tgcalls_ohos::LocalVideoSource> localVideoSource;
    std::shared_ptr<OhosVideoSink> localVideoPreviewSink;
    std::unique_ptr<tgcalls::GroupInstanceCustomImpl> instance;
};

}  // namespace

extern "C" {

__attribute__((visibility("default"))) void *tgcalls_ohos_create(
        StateCallback callback, void *context,
        BroadcastRequestCallback broadcastCallback, void *broadcastContext,
        AudioActivityCallback audioCallback, void *audioContext,
        LocalVideoStateCallback localVideoCallback, void *localVideoContext,
        VideoGeometryCallback geometryCallback, void *geometryContext,
        bool presentation) {
    try {
        return new Session(
            callback, context, broadcastCallback, broadcastContext,
            audioCallback, audioContext, localVideoCallback, localVideoContext,
            geometryCallback, geometryContext,
            presentation);
    } catch (...) {
        return nullptr;
    }
}

__attribute__((visibility("default"))) void tgcalls_ohos_complete_broadcast_time(
        void *opaque, uint64_t requestId, int64_t timestampMilliseconds) {
    auto *session = static_cast<Session *>(opaque);
    if (!session) { return; }
    auto task = session->takeBroadcastTask(requestId);
    if (task) { task->completeTime(timestampMilliseconds); }
}

__attribute__((visibility("default"))) void tgcalls_ohos_complete_broadcast_part(
        void *opaque, uint64_t requestId, int64_t timestampMilliseconds,
        int status, double responseTimestamp, const uint8_t *data, size_t length) {
    auto *session = static_cast<Session *>(opaque);
    if (!session) { return; }
    auto task = session->takeBroadcastTask(requestId);
    if (!task) { return; }
    tgcalls::BroadcastPart part;
    part.timestampMilliseconds = timestampMilliseconds;
    part.responseTimestamp = responseTimestamp;
    if (status == 0) {
        part.status = tgcalls::BroadcastPart::Status::Success;
    } else if (status == 2) {
        part.status = tgcalls::BroadcastPart::Status::ResyncNeeded;
    } else {
        part.status = tgcalls::BroadcastPart::Status::NotReady;
    }
    if (data != nullptr && length > 0) {
        part.data.assign(data, data + length);
    }
    task->completePart(std::move(part));
}

__attribute__((visibility("default"))) void tgcalls_ohos_emit_join_payload(
        void *opaque, JoinCallback callback, void *context) {
    auto *session = static_cast<Session *>(opaque);
    if (!session || !session->instance || !callback) {
        return;
    }
    session->instance->emitJoinPayload([callback, context](const tgcalls::GroupJoinPayload &payload) {
        callback(context, payload.audioSsrc, payload.json.c_str());
    });
}

__attribute__((visibility("default"))) void tgcalls_ohos_set_join_response(void *opaque, const char *payload) {
    auto *session = static_cast<Session *>(opaque);
    if (session && session->instance && payload) {
        session->instance->setJoinResponsePayload(payload);
    }
}

__attribute__((visibility("default"))) void tgcalls_ohos_set_connection_mode(
        void *opaque, int mode, bool isUnifiedBroadcast) {
    auto *session = static_cast<Session *>(opaque);
    if (!session || !session->instance) {
        return;
    }
    auto mapped = tgcalls::GroupConnectionMode::GroupConnectionModeNone;
    if (mode == 1) {
        mapped = tgcalls::GroupConnectionMode::GroupConnectionModeRtc;
    } else if (mode == 2) {
        mapped = tgcalls::GroupConnectionMode::GroupConnectionModeBroadcast;
    }
    session->instance->setConnectionMode(mapped, false, isUnifiedBroadcast);
}

__attribute__((visibility("default"))) void tgcalls_ohos_resume_media(void *opaque) {
    auto *session = static_cast<Session *>(opaque);
    if (session) { session->resumeMedia(); }
}

__attribute__((visibility("default"))) bool tgcalls_ohos_set_muted(void *opaque, bool muted) {
    auto *session = static_cast<Session *>(opaque);
    if (!session || !session->instance || !session->audioRecorder || !session->audioRenderer) {
        return false;
    }
    if (!muted) {
        // Establish a full-duplex communication route before opening a
        // Bluetooth microphone. Otherwise the capturer moves the headset to
        // SCO while a MOVIE renderer remains on the suspended media path.
        if (!session->audioRenderer->SetMicrophoneActive(true)) { return false; }
        if (!session->audioRecorder->Start()) {
            session->audioRenderer->SetMicrophoneActive(false);
            return false;
        }
    }
    session->instance->setIsMuted(muted);
    if (muted) {
        session->audioRecorder->Stop();
        // Keep a communication renderer when the active headset route remains
        // SCO; a MOVIE stream routed onto SCO is accepted but inaudible on
        // HarmonyOS. Return to media volume only when A2DP/speaker is real.
        session->audioRenderer->SetMicrophoneActive(false);
    }
    TGLOG("local microphone state: muted=%{public}d", muted ? 1 : 0);
    return true;
}

__attribute__((visibility("default"))) bool tgcalls_ohos_set_local_video(
        void *opaque, int mode, uint32_t width, uint32_t height) {
    auto *session = static_cast<Session *>(opaque);
    return session != nullptr && session->setLocalVideo(mode, width, height);
}

__attribute__((visibility("default"))) void tgcalls_ohos_set_local_video_surface(
        void *opaque, uint64_t surfaceId,
        uint32_t surfaceWidth, uint32_t surfaceHeight) {
    auto *session = static_cast<Session *>(opaque);
    if (session != nullptr) {
        session->setLocalVideoSurface(surfaceId, surfaceWidth, surfaceHeight);
    }
}

__attribute__((visibility("default"))) void tgcalls_ohos_set_video_surface(
        void *opaque, const char *endpointId, uint64_t surfaceId,
        uint32_t surfaceWidth, uint32_t surfaceHeight) {
    auto *session = static_cast<Session *>(opaque);
    if (!session || !session->instance || endpointId == nullptr || endpointId[0] == '\0') {
        return;
    }
    bool needsRegistration = false;
    auto sink = session->getOrCreateVideoSink(endpointId, needsRegistration);
    if (needsRegistration) {
        session->instance->addIncomingVideoOutput(
            endpointId, std::weak_ptr<rtc::VideoSinkInterface<webrtc::VideoFrame>>(sink));
    }
    if (surfaceId == 0) {
        sink->SetWindow(nullptr, 0, 0);
        return;
    }
    OHNativeWindow *window = nullptr;
    if (OH_NativeWindow_CreateNativeWindowFromSurfaceId(surfaceId, &window) != 0 || window == nullptr) {
        TGVLOG("failed to create native window endpoint=%{public}s surface=%{public}llu",
               endpointId, (unsigned long long)surfaceId);
        return;
    }
    sink->SetWindow(window, static_cast<int>(surfaceWidth), static_cast<int>(surfaceHeight));
    TGVLOG("video surface set endpoint=%{public}s surface=%{public}llu size=%{public}ux%{public}u",
           endpointId, (unsigned long long)surfaceId, surfaceWidth, surfaceHeight);
}

// ssrcGroups encoded as "semantics=ssrc,ssrc;semantics=ssrc,..." (compact).
__attribute__((visibility("default"))) void tgcalls_ohos_set_video_channel(
        void *opaque, const char *endpointId, uint32_t audioSsrc, const char *ssrcGroups) {
    auto *session = static_cast<Session *>(opaque);
    if (!session || !session->instance || !endpointId) {
        return;
    }
    tgcalls::VideoChannelDescription channel;
    channel.audioSsrc = audioSsrc;
    channel.endpointId = endpointId;
    channel.minQuality = tgcalls::VideoChannelDescription::Quality::Thumbnail;
    channel.maxQuality = tgcalls::VideoChannelDescription::Quality::Full;
    if (ssrcGroups != nullptr) {
        std::string s(ssrcGroups);
        size_t start = 0;
        while (start < s.size()) {
            size_t semi = s.find(';', start);
            std::string group = s.substr(start, semi == std::string::npos ? std::string::npos : semi - start);
            size_t eq = group.find('=');
            if (eq != std::string::npos) {
                tgcalls::MediaSsrcGroup g;
                g.semantics = group.substr(0, eq);
                std::string ids = group.substr(eq + 1);
                size_t p = 0;
                while (p < ids.size()) {
                    size_t comma = ids.find(',', p);
                    std::string tok = ids.substr(p, comma == std::string::npos ? std::string::npos : comma - p);
                    if (!tok.empty()) {
                        const auto ssrc = static_cast<uint32_t>(strtoul(tok.c_str(), nullptr, 10));
                        if (ssrc != 0 && std::find(g.ssrcs.begin(), g.ssrcs.end(), ssrc) == g.ssrcs.end()) {
                            g.ssrcs.push_back(ssrc);
                        }
                    }
                    if (comma == std::string::npos) { break; }
                    p = comma + 1;
                }
                if (!g.ssrcs.empty()) {
                    channel.ssrcGroups.push_back(std::move(g));
                }
            }
            if (semi == std::string::npos) { break; }
            start = semi + 1;
        }
    }
    {
        std::lock_guard<std::mutex> lock(session->videoMutex);
        session->videoDescriptions[endpointId] = std::move(channel);
    }
    bool needsRegistration = false;
    auto sink = session->getOrCreateVideoSink(endpointId, needsRegistration);
    if (needsRegistration) {
        session->instance->addIncomingVideoOutput(
            endpointId, std::weak_ptr<rtc::VideoSinkInterface<webrtc::VideoFrame>>(sink));
    }
    session->submitVideoDescriptions();
    TGVLOG("video channel requested endpoint=%{public}s audioSsrc=%{public}u groups=%{public}s",
           endpointId, audioSsrc, ssrcGroups != nullptr ? ssrcGroups : "");
}

__attribute__((visibility("default"))) void tgcalls_ohos_remove_video_channel(
        void *opaque, const char *endpointId) {
    auto *session = static_cast<Session *>(opaque);
    if (!session || !session->instance || endpointId == nullptr) {
        return;
    }
    std::shared_ptr<OhosVideoSink> sink;
    {
        std::lock_guard<std::mutex> lock(session->videoMutex);
        session->videoDescriptions.erase(endpointId);
        auto it = session->videoSinks.find(endpointId);
        if (it != session->videoSinks.end()) {
            sink = it->second;
            session->videoSinks.erase(it);
        }
        session->registeredVideoSinks.erase(endpointId);
    }
    if (sink) {
        sink->SetWindow(nullptr);
    }
    session->submitVideoDescriptions();
}

__attribute__((visibility("default"))) void tgcalls_ohos_clear_video(void *opaque) {
    auto *session = static_cast<Session *>(opaque);
    if (!session) {
        return;
    }
    if (session->instance) {
        session->instance->setRequestedVideoChannels({});
    }
    std::map<std::string, std::shared_ptr<OhosVideoSink>> sinks;
    {
        std::lock_guard<std::mutex> lock(session->videoMutex);
        sinks.swap(session->videoSinks);
        session->videoDescriptions.clear();
        session->registeredVideoSinks.clear();
    }
    for (auto &entry : sinks) {
        entry.second->SetWindow(nullptr);
    }
}

__attribute__((visibility("default"))) void tgcalls_ohos_destroy(void *opaque) {
    delete static_cast<Session *>(opaque);
}

}  // extern "C"

// ---------------------------------------------------------------------------
// 1对1 通话（tgcalls Instance/InstanceV2）。与上面的群会话完全独立。
// ---------------------------------------------------------------------------

#include "tgcalls/Instance.h"
#include "tgcalls/InstanceImpl.h"
#include "tgcalls/StaticThreads.h"
#include "tgcalls/VideoCaptureInterface.h"
#include "tgcalls/v2/InstanceV2Impl.h"
#include "tgcalls/v2/InstanceV2ReferenceImpl.h"
#include "tgcalls/third-party/json11.hpp"

namespace {

#define TGCLOG(fmt, ...) OH_LOG_Print(LOG_APP, LOG_INFO, 0x0000, "tgcalls-call", fmt, ##__VA_ARGS__)

using CallStateCallback = void (*)(void *, int); // 0 connecting 1 ready 2 failed 3 reconnecting
using CallSignalingCallback = void (*)(void *, const uint8_t *, size_t);
using CallRemoteMediaCallback = void (*)(void *, int, int);

int Base64Value(char c) {
    if (c >= 'A' && c <= 'Z') { return c - 'A'; }
    if (c >= 'a' && c <= 'z') { return c - 'a' + 26; }
    if (c >= '0' && c <= '9') { return c - '0' + 52; }
    if (c == '+') { return 62; }
    if (c == '/') { return 63; }
    return -1;
}

std::vector<uint8_t> Base64Decode(const std::string &input) {
    std::vector<uint8_t> out;
    int acc = 0;
    int bits = 0;
    for (const char c : input) {
        if (c == '=' || c == '\n' || c == '\r') {
            continue;
        }
        const int value = Base64Value(c);
        if (value < 0) {
            continue;
        }
        acc = (acc << 6) | value;
        bits += 6;
        if (bits >= 8) {
            bits -= 8;
            out.push_back(static_cast<uint8_t>((acc >> bits) & 0xFF));
        }
    }
    return out;
}

std::string ToHex(const std::vector<uint8_t> &data) {
    static const char *kDigits = "0123456789abcdef";
    std::string out;
    out.reserve(data.size() * 2);
    for (const uint8_t b : data) {
        out.push_back(kDigits[b >> 4]);
        out.push_back(kDigits[b & 0x0F]);
    }
    return out;
}

void EnsureCallImplementationsRegistered() {
    static const bool registered = [] {
        tgcalls::Register<tgcalls::InstanceImpl>();
        tgcalls::Register<tgcalls::InstanceV2Impl>();
        tgcalls::Register<tgcalls::InstanceV2ReferenceImpl>();
        return true;
    }();
    (void)registered;
}

// TDLib callStateReady.protocol.library_versions 按服务端偏好排序；取其中
// 第一个本库也支持的版本。远端列表为空时退回本库首选。
std::string PickCallVersion(const std::string &remoteVersionsJson) {
    EnsureCallImplementationsRegistered();
    const std::vector<std::string> supported = tgcalls::Meta::Versions();
    std::string parseError;
    const json11::Json parsed = json11::Json::parse(remoteVersionsJson, parseError);
    if (parseError.empty() && parsed.is_array()) {
        for (const auto &entry : parsed.array_items()) {
            if (!entry.is_string()) {
                continue;
            }
            const std::string &candidate = entry.string_value();
            if (std::find(supported.begin(), supported.end(), candidate) != supported.end()) {
                return candidate;
            }
        }
    }
    // 本库首选：InstanceV2Impl 的最高版本（与官方移动端默认一致）。
    if (std::find(supported.begin(), supported.end(), "9.0.0") != supported.end()) {
        return "9.0.0";
    }
    return supported.empty() ? std::string("2.7.7") : supported.back();
}

struct ParsedCallServers {
    std::vector<tgcalls::RtcServer> rtcServers;
    std::vector<tgcalls::Endpoint> endpoints; // 传统 InstanceImpl 需要 reflector 端点
};

// 解析 TDLib callStateReady.servers（JSON 数组）。
// callServerTypeWebrtc → STUN/TURN；callServerTypeTelegramReflector →
// login="reflector" + password=hex(peer_tag) 的 TURN 表项（ReflectorPort 约定）。
ParsedCallServers ParseCallServers(const std::string &serversJson) {
    ParsedCallServers out;
    std::string parseError;
    const json11::Json parsed = json11::Json::parse(serversJson, parseError);
    if (!parseError.empty() || !parsed.is_array()) {
        TGCLOG("servers json parse failed: %{public}s", parseError.c_str());
        return out;
    }
    for (const auto &entry : parsed.array_items()) {
        const std::string ip = entry["ip_address"].string_value();
        const std::string ipv6 = entry["ipv6_address"].string_value();
        const uint16_t port = static_cast<uint16_t>(entry["port"].int_value());
        const int64_t id = static_cast<int64_t>(entry["id"].number_value());
        const json11::Json &type = entry["type"];
        const std::string typeName = type["@type"].string_value();
        if (ip.empty() || port == 0) {
            continue;
        }
        if (typeName == "callServerTypeWebrtc") {
            tgcalls::RtcServer server;
            server.id = static_cast<uint8_t>(id);
            server.host = ip;
            server.port = port;
            server.login = type["username"].string_value();
            server.password = type["password"].string_value();
            server.isTurn = type["supports_turn"].bool_value();
            server.isTcp = false;
            out.rtcServers.push_back(server);
            if (type["supports_stun"].bool_value() && server.isTurn) {
                // STUN 与 TURN 共存时补一份 STUN 表项（isTurn=false）。
                tgcalls::RtcServer stun = server;
                stun.isTurn = false;
                stun.login.clear();
                stun.password.clear();
                out.rtcServers.push_back(stun);
            }
        } else if (typeName == "callServerTypeTelegramReflector") {
            const std::vector<uint8_t> peerTag =
                Base64Decode(type["peer_tag"].string_value());
            tgcalls::RtcServer server;
            server.id = static_cast<uint8_t>(id);
            server.host = ip;
            server.port = port;
            server.login = "reflector";
            server.password = ToHex(peerTag);
            server.isTurn = true;
            server.isTcp = type["is_tcp"].bool_value();
            out.rtcServers.push_back(server);
            // 传统实现（2.7.7/5.0.0）走 Endpoint 列表。
            tgcalls::Endpoint endpoint;
            endpoint.endpointId = id;
            endpoint.host = tgcalls::EndpointHost{ip, ipv6};
            endpoint.port = port;
            endpoint.type = tgcalls::EndpointType::UdpRelay;
            const size_t tagLen = std::min(peerTag.size(), sizeof(endpoint.peerTag));
            std::memcpy(endpoint.peerTag, peerTag.data(), tagLen);
            out.endpoints.push_back(endpoint);
        }
    }
    return out;
}

class PrivateCallSession {
public:
    PrivateCallSession(
            const std::string &encryptionKeyBase64, bool isOutgoing,
            const std::string &serversJson, bool isVideo,
            const std::string &remoteVersionsJson,
            CallStateCallback onState, CallSignalingCallback onSignaling,
            CallRemoteMediaCallback onRemoteMedia, void *ctx)
        : stateCallback(onState), signalingCallback(onSignaling),
          remoteMediaCallback(onRemoteMedia), callbackContext(ctx) {
        EnsureCallImplementationsRegistered();
        const std::vector<uint8_t> keyBytes = Base64Decode(encryptionKeyBase64);
        auto key = std::make_shared<std::array<uint8_t, tgcalls::EncryptionKey::kSize>>();
        if (keyBytes.size() != key->size()) {
            TGCLOG("encryption key size mismatch: %{public}zu", keyBytes.size());
            failed = true;
            return;
        }
        std::copy(keyBytes.begin(), keyBytes.end(), key->begin());
        ParsedCallServers servers = ParseCallServers(serversJson);
        const std::string version = PickCallVersion(remoteVersionsJson);
        TGCLOG("creating call instance version=%{public}s servers=%{public}zu "
               "endpoints=%{public}zu outgoing=%{public}d video=%{public}d",
               version.c_str(), servers.rtcServers.size(), servers.endpoints.size(),
               isOutgoing ? 1 : 0, isVideo ? 1 : 0);

        audioRenderer = std::make_shared<OhosAudioRenderer>();
        audioRecorder = std::make_shared<OhosAudioRecorder>();
        tgcalls::FakeAudioDeviceModule::Options audioOptions;
        audioOptions.samples_per_sec = 48000;
        audioOptions.num_channels = 2;

        if (isVideo) {
            videoCapture = tgcalls::VideoCaptureInterface::Create(
                tgcalls::StaticThreads::getThreads(), "front");
        }

        tgcalls::Descriptor descriptor = {
            .version = version,
            .config = tgcalls::Config{
                .initializationTimeout = 30.0,
                .receiveTimeout = 20.0,
                .dataSaving = tgcalls::DataSaving::Never,
                .enableP2P = true,
                .allowTCP = false,
                .enableStunMarking = false,
                .enableAEC = true,
                .enableNS = true,
                .enableAGC = true,
                .enableVolumeControl = false,
                .maxApiLayer = 92,
                .enableHighBitrateVideo = false,
                .preferredVideoCodecs = {},
                .protocolVersion = tgcalls::ProtocolVersion::V0
            },
            .endpoints = std::move(servers.endpoints),
            .rtcServers = std::move(servers.rtcServers),
            .initialNetworkType = tgcalls::NetworkType::WiFi,
            .encryptionKey = tgcalls::EncryptionKey(std::move(key), isOutgoing),
            .videoCapture = videoCapture,
            .stateUpdated = [this](tgcalls::State state) {
                int mapped = 0;
                switch (state) {
                    case tgcalls::State::Established:
                        mapped = 1;
                        if (audioRenderer) {
                            audioRenderer->Start();
                            audioRenderer->SetMicrophoneActive(true);
                        }
                        // 录音器必须显式 Start 才会采集：active_ 为 false 时
                        // Record() 恒返回空帧，对端就是纯静音。
                        if (audioRecorder) {
                            audioRecorder->Start();
                        }
                        break;
                    case tgcalls::State::Failed:
                        mapped = 2;
                        break;
                    case tgcalls::State::Reconnecting:
                        mapped = 3;
                        break;
                    default:
                        mapped = 0;
                        break;
                }
                TGCLOG("call state=%{public}d", mapped);
                if (stateCallback) {
                    stateCallback(callbackContext, mapped);
                }
            },
            .remoteMediaStateUpdated = [this](
                    tgcalls::AudioState audioState, tgcalls::VideoState videoState) {
                if (remoteMediaCallback) {
                    remoteMediaCallback(
                        callbackContext,
                        audioState == tgcalls::AudioState::Muted ? 1 : 0,
                        videoState == tgcalls::VideoState::Active ? 1 : 0);
                }
            },
            .signalingDataEmitted = [this](const std::vector<uint8_t> &data) {
                if (signalingCallback) {
                    signalingCallback(callbackContext, data.data(), data.size());
                }
            },
            .createAudioDeviceModule =
                tgcalls::FakeAudioDeviceModule::Creator(audioRenderer, audioRecorder, audioOptions)
        };

        remoteSink = std::make_shared<OhosVideoSink>("__call_remote__");
        instance = tgcalls::Meta::Create(version, std::move(descriptor));
        if (instance == nullptr) {
            TGCLOG("Meta::Create returned null for version=%{public}s", version.c_str());
            failed = true;
            return;
        }
        instance->setIncomingVideoOutput(
            std::weak_ptr<rtc::VideoSinkInterface<webrtc::VideoFrame>>(remoteSink));
        if (videoCapture != nullptr) {
            videoCapture->setState(tgcalls::VideoState::Active);
        }
    }

    ~PrivateCallSession() {
        if (instance != nullptr) {
            // stop() 的完成回调在内部线程触发；同步等待避免拆除竞态。
            std::mutex doneMutex;
            std::condition_variable doneCondition;
            bool done = false;
            instance->stop([&](tgcalls::FinalState) {
                std::lock_guard<std::mutex> lock(doneMutex);
                done = true;
                doneCondition.notify_all();
            });
            std::unique_lock<std::mutex> lock(doneMutex);
            doneCondition.wait_for(lock, std::chrono::seconds(2), [&] { return done; });
            instance.reset();
        }
        if (localSink != nullptr) {
            localSink->SetWindow(nullptr);
        }
        if (remoteSink != nullptr) {
            remoteSink->SetWindow(nullptr);
        }
        videoCapture.reset();
    }

    void ReceiveSignaling(const uint8_t *data, size_t len) {
        if (instance != nullptr && data != nullptr && len > 0) {
            instance->receiveSignalingData(std::vector<uint8_t>(data, data + len));
        }
    }

    void SetMuted(bool muted) {
        if (instance == nullptr) {
            return;
        }
        if (!muted) {
            // 与群会话相同的开麦顺序：先建立全双工路由再开采集，
            // 蓝牙耳机才能正确切到 SCO。
            if (audioRenderer) {
                audioRenderer->SetMicrophoneActive(true);
            }
            if (audioRecorder) {
                audioRecorder->Start();
            }
        }
        instance->setMuteMicrophone(muted);
    }

    void SetVideo(int mode) {
        if (instance == nullptr) {
            return;
        }
        if (mode == 0) {
            if (videoCapture != nullptr) {
                videoCapture->setState(tgcalls::VideoState::Inactive);
            }
            return;
        }
        const std::string device = mode == 2 ? "back" : "front";
        if (videoCapture == nullptr) {
            videoCapture = tgcalls::VideoCaptureInterface::Create(
                tgcalls::StaticThreads::getThreads(), device);
            if (videoCapture == nullptr) {
                TGCLOG("video capture create failed device=%{public}s", device.c_str());
                return;
            }
            AttachLocalSink();
            instance->setVideoCapture(videoCapture);
        } else {
            videoCapture->switchToDevice(device, false);
            instance->sendVideoDeviceUpdated();
        }
        videoCapture->setState(tgcalls::VideoState::Active);
    }

    void SetAudioOutput(bool speaker) {
        if (audioRenderer != nullptr) {
            audioRenderer->SetPreferredOutputDevice(speaker);
        }
    }

    void SetLocalSurface(uint64_t surfaceId) {
        if (localSink == nullptr) {
            localSink = std::make_shared<OhosVideoSink>("__call_local__");
            AttachLocalSink();
        }
        BindWindow(localSink, surfaceId);
    }

    void SetRemoteSurface(uint64_t surfaceId) {
        if (remoteSink != nullptr) {
            BindWindow(remoteSink, surfaceId);
        }
    }

private:
    void AttachLocalSink() {
        if (videoCapture != nullptr && localSink != nullptr) {
            videoCapture->setOutput(localSink);
        }
    }

    static void BindWindow(const std::shared_ptr<OhosVideoSink> &sink, uint64_t surfaceId) {
        if (surfaceId == 0) {
            TGCLOG("call surface cleared");
            sink->SetWindow(nullptr, 0, 0);
            return;
        }
        OHNativeWindow *window = nullptr;
        if (OH_NativeWindow_CreateNativeWindowFromSurfaceId(surfaceId, &window) != 0 ||
            window == nullptr) {
            TGCLOG("call surface bind failed surface=%{public}llu",
                   static_cast<unsigned long long>(surfaceId));
            return;
        }
        TGCLOG("call surface bound surface=%{public}llu",
               static_cast<unsigned long long>(surfaceId));
        sink->SetWindow(window);
    }

public:
    bool failed = false;

private:
    std::unique_ptr<tgcalls::Instance> instance;
    std::shared_ptr<tgcalls::VideoCaptureInterface> videoCapture;
    std::shared_ptr<OhosAudioRenderer> audioRenderer;
    std::shared_ptr<OhosAudioRecorder> audioRecorder;
    std::shared_ptr<OhosVideoSink> remoteSink;
    std::shared_ptr<OhosVideoSink> localSink;
    CallStateCallback stateCallback = nullptr;
    CallSignalingCallback signalingCallback = nullptr;
    CallRemoteMediaCallback remoteMediaCallback = nullptr;
    void *callbackContext = nullptr;
};

std::string g_callVersionsJson;

}  // namespace

extern "C" {

__attribute__((visibility("default"))) void *tgcalls_call_create(
        const char *encryptionKeyBase64, int isOutgoing, const char *serversJson,
        int isVideo, const char *remoteVersionsJson,
        void (*onState)(void *, int),
        void (*onSignaling)(void *, const uint8_t *, size_t),
        void (*onRemoteMedia)(void *, int, int), void *ctx) {
    if (encryptionKeyBase64 == nullptr || serversJson == nullptr) {
        return nullptr;
    }
    auto *session = new PrivateCallSession(
        encryptionKeyBase64, isOutgoing != 0, serversJson, isVideo != 0,
        remoteVersionsJson != nullptr ? remoteVersionsJson : "",
        onState, onSignaling, onRemoteMedia, ctx);
    if (session->failed) {
        delete session;
        return nullptr;
    }
    return session;
}

__attribute__((visibility("default"))) void tgcalls_call_receive_signaling(
        void *call, const uint8_t *data, size_t len) {
    if (call != nullptr) {
        static_cast<PrivateCallSession *>(call)->ReceiveSignaling(data, len);
    }
}

__attribute__((visibility("default"))) void tgcalls_call_set_muted(void *call, int muted) {
    if (call != nullptr) {
        static_cast<PrivateCallSession *>(call)->SetMuted(muted != 0);
    }
}

__attribute__((visibility("default"))) void tgcalls_call_set_video(void *call, int mode) {
    if (call != nullptr) {
        static_cast<PrivateCallSession *>(call)->SetVideo(mode);
    }
}

__attribute__((visibility("default"))) void tgcalls_call_set_audio_output(
        void *call, int speaker) {
    if (call != nullptr) {
        static_cast<PrivateCallSession *>(call)->SetAudioOutput(speaker != 0);
    }
}

__attribute__((visibility("default"))) void tgcalls_call_set_local_surface(
        void *call, uint64_t surfaceId) {
    if (call != nullptr) {
        static_cast<PrivateCallSession *>(call)->SetLocalSurface(surfaceId);
    }
}

__attribute__((visibility("default"))) void tgcalls_call_set_remote_surface(
        void *call, uint64_t surfaceId) {
    if (call != nullptr) {
        static_cast<PrivateCallSession *>(call)->SetRemoteSurface(surfaceId);
    }
}

__attribute__((visibility("default"))) const char *tgcalls_call_versions_json(void) {
    EnsureCallImplementationsRegistered();
    if (g_callVersionsJson.empty()) {
        std::string json = "[";
        const std::vector<std::string> versions = tgcalls::Meta::Versions();
        for (size_t i = 0; i < versions.size(); ++i) {
            if (i > 0) {
                json += ",";
            }
            json += "\"" + versions[i] + "\"";
        }
        json += "]";
        g_callVersionsJson = json;
    }
    return g_callVersionsJson.c_str();
}

__attribute__((visibility("default"))) void tgcalls_call_destroy(void *call) {
    delete static_cast<PrivateCallSession *>(call);
}

}  // extern "C"
