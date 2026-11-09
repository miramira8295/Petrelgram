#include "tgcalls/platform/fake/FakeInterface.h"

#include "api/video_codecs/builtin_video_decoder_factory.h"
#include "api/video_codecs/builtin_video_encoder_factory.h"
#include "api/video_codecs/video_decoder.h"
#include "api/video/video_frame.h"
#include "media/base/adapted_video_track_source.h"
#include "rtc_base/thread.h"

#include "tgcalls/VideoCapturerInterface.h"
#include "tgcalls/VideoCaptureInterface.h"
#include "tgcalls_ohos_local_video.h"
#include "video/video_capturer.h"
#include "video/video_frame_receiver.h"
#include "api/make_ref_counted.h"

#include <hilog/log.h>

#include <atomic>
#include <memory>
#include <mutex>
#include <utility>

#define TGVDECLOG(fmt, ...) OH_LOG_Print(LOG_APP, LOG_INFO, 0x0000, "tgcalls-decoder", fmt, ##__VA_ARGS__)

namespace tgcalls {
namespace {

class LoggingVideoDecoder final : public webrtc::VideoDecoder {
public:
    LoggingVideoDecoder(std::string codec, std::unique_ptr<webrtc::VideoDecoder> inner)
        : codec_(std::move(codec)), inner_(std::move(inner)), callbackProxy_(this) {
    }

    bool Configure(const Settings &settings) override {
        const bool ok = inner_ != nullptr && inner_->Configure(settings);
        TGVDECLOG("configure codec=%{public}s ok=%{public}d cores=%{public}d max=%{public}dx%{public}d impl=%{public}s",
                  codec_.c_str(), ok ? 1 : 0, settings.number_of_cores(),
                  settings.max_render_resolution().Width(), settings.max_render_resolution().Height(),
                  inner_ ? inner_->GetDecoderInfo().implementation_name.c_str() : "null");
        return ok;
    }

    int32_t Decode(const webrtc::EncodedImage &image, bool missingFrames, int64_t renderTimeMs) override {
        const uint32_t count = ++decodeCount_;
        const int32_t result = inner_ ? inner_->Decode(image, missingFrames, renderTimeMs) : -1;
        if (count == 1 || result != 0 || count % 300 == 0) {
            TGVDECLOG("input codec=%{public}s count=%{public}u bytes=%{public}zu size=%{public}ux%{public}u key=%{public}d missing=%{public}d result=%{public}d",
                      codec_.c_str(), count, image.size(), image._encodedWidth, image._encodedHeight,
                      image._frameType == webrtc::VideoFrameType::kVideoFrameKey ? 1 : 0,
                      missingFrames ? 1 : 0, result);
        }
        return result;
    }

    int32_t RegisterDecodeCompleteCallback(webrtc::DecodedImageCallback *callback) override {
        callback_ = callback;
        const int32_t result = inner_ ? inner_->RegisterDecodeCompleteCallback(&callbackProxy_) : -1;
        TGVDECLOG("callback codec=%{public}s result=%{public}d", codec_.c_str(), result);
        return result;
    }

    int32_t Release() override {
        return inner_ ? inner_->Release() : 0;
    }

    DecoderInfo GetDecoderInfo() const override {
        return inner_ ? inner_->GetDecoderInfo() : DecoderInfo{};
    }

private:
    class CallbackProxy final : public webrtc::DecodedImageCallback {
    public:
        explicit CallbackProxy(LoggingVideoDecoder *owner) : owner_(owner) {
        }

        int32_t Decoded(webrtc::VideoFrame &frame) override {
            owner_->LogOutput(frame);
            return owner_->callback_ ? owner_->callback_->Decoded(frame) : 0;
        }

        int32_t Decoded(webrtc::VideoFrame &frame, int64_t decodeTimeMs) override {
            owner_->LogOutput(frame);
            return owner_->callback_ ? owner_->callback_->Decoded(frame, decodeTimeMs) : 0;
        }

        void Decoded(webrtc::VideoFrame &frame, absl::optional<int32_t> decodeTimeMs,
                     absl::optional<uint8_t> qp) override {
            owner_->LogOutput(frame);
            if (owner_->callback_) {
                owner_->callback_->Decoded(frame, decodeTimeMs, qp);
            }
        }

    private:
        LoggingVideoDecoder *owner_;
    };

    void LogOutput(const webrtc::VideoFrame &frame) {
        const uint32_t count = ++outputCount_;
        if (count == 1 || count % 300 == 0) {
            TGVDECLOG("output codec=%{public}s count=%{public}u size=%{public}dx%{public}d",
                      codec_.c_str(), count, frame.width(), frame.height());
        }
    }

    std::string codec_;
    std::unique_ptr<webrtc::VideoDecoder> inner_;
    webrtc::DecodedImageCallback *callback_ = nullptr;
    CallbackProxy callbackProxy_;
    std::atomic<uint32_t> decodeCount_{0};
    std::atomic<uint32_t> outputCount_{0};
};

class LoggingVideoDecoderFactory final : public webrtc::VideoDecoderFactory {
public:
    LoggingVideoDecoderFactory() : inner_(webrtc::CreateBuiltinVideoDecoderFactory()) {
        for (const auto &format : inner_->GetSupportedFormats()) {
            TGVDECLOG("supported=%{public}s", format.ToString().c_str());
        }
    }

    std::vector<webrtc::SdpVideoFormat> GetSupportedFormats() const override {
        return inner_->GetSupportedFormats();
    }

    CodecSupport QueryCodecSupport(const webrtc::SdpVideoFormat &format,
                                   bool referenceScaling) const override {
        return inner_->QueryCodecSupport(format, referenceScaling);
    }

    std::unique_ptr<webrtc::VideoDecoder> CreateVideoDecoder(
            const webrtc::SdpVideoFormat &format) override {
        auto decoder = inner_->CreateVideoDecoder(format);
        TGVDECLOG("create format=%{public}s ok=%{public}d", format.ToString().c_str(), decoder ? 1 : 0);
        return decoder
            ? std::make_unique<LoggingVideoDecoder>(format.name, std::move(decoder))
            : nullptr;
    }

private:
    std::unique_ptr<webrtc::VideoDecoderFactory> inner_;
};

}  // namespace

std::unique_ptr<webrtc::VideoEncoderFactory> FakeInterface::makeVideoEncoderFactory(
        bool preferHardwareEncoding, bool isScreencast) {
    return webrtc::CreateBuiltinVideoEncoderFactory();
}

std::unique_ptr<webrtc::VideoDecoderFactory> FakeInterface::makeVideoDecoderFactory() {
    return std::make_unique<LoggingVideoDecoderFactory>();
}

namespace {

#define TGPCLOG(fmt, ...) OH_LOG_Print(LOG_APP, LOG_INFO, 0x0000, "tgcalls-platform", fmt, ##__VA_ARGS__)

// 1:1 通话的被动视频源：平台采集器把相机帧推进来，tgcalls 的
// VideoCaptureInterfaceImpl 将它作为 outgoing video track source。
// 注意：不能 final —— rtc::make_ref_counted 需要以子类形式包一层 RefCountedObject。
class OhosRelayVideoSource : public rtc::AdaptedVideoTrackSource {
public:
    OhosRelayVideoSource() : rtc::AdaptedVideoTrackSource(2) {
    }

    void PushFrame(
            rtc::scoped_refptr<webrtc::VideoFrameBuffer> buffer,
            int64_t timestampUs, webrtc::VideoRotation rotation) {
        if (buffer == nullptr) {
            return;
        }
        int adaptedWidth = 0;
        int adaptedHeight = 0;
        int cropWidth = 0;
        int cropHeight = 0;
        int cropX = 0;
        int cropY = 0;
        const bool rotated =
            rotation == webrtc::kVideoRotation_90 ||
            rotation == webrtc::kVideoRotation_270;
        const bool wanted = rotated
            ? AdaptFrame(
                buffer->height(), buffer->width(), timestampUs,
                &adaptedHeight, &adaptedWidth, &cropHeight, &cropWidth,
                &cropY, &cropX)
            : AdaptFrame(
                buffer->width(), buffer->height(), timestampUs,
                &adaptedWidth, &adaptedHeight, &cropWidth, &cropHeight,
                &cropX, &cropY);
        if (!wanted) {
            return;
        }
        if (adaptedWidth != buffer->width() || adaptedHeight != buffer->height() ||
            cropWidth != buffer->width() || cropHeight != buffer->height()) {
            buffer = buffer->CropAndScale(
                cropX, cropY, cropWidth, cropHeight, adaptedWidth, adaptedHeight);
        }
        OnFrame(webrtc::VideoFrame::Builder()
            .set_video_frame_buffer(buffer)
            .set_rotation(rotation)
            .set_timestamp_us(timestampUs)
            .build());
    }

    SourceState state() const override {
        return kLive;
    }

    bool remote() const override {
        return false;
    }

    bool is_screencast() const override {
        return false;
    }

    absl::optional<bool> needs_denoising() const override {
        return absl::optional<bool>(true);
    }
};

// 1:1 通话平台采集器：把 OHOS 相机帧同时喂给 relay source（编码上行）和
// uncropped sink（本地预览）。deviceId "back" 选后摄，其余选前摄。
class OhosPlatformVideoCapturer final : public tgcalls::VideoCapturerInterface,
                                        public webrtc::VideoCapturer::Observer {
public:
    OhosPlatformVideoCapturer(
            rtc::scoped_refptr<OhosRelayVideoSource> source, std::string deviceId,
            std::function<void(tgcalls::VideoState)> stateUpdated,
            std::function<void(tgcalls::PlatformCaptureInfo)> captureInfoUpdated,
            std::pair<int, int> &outResolution)
        : source_(std::move(source)),
          stateUpdated_(std::move(stateUpdated)),
          captureInfoUpdated_(std::move(captureInfoUpdated)) {
        const bool front = deviceId != "back";
        capturer_ = tgcalls_ohos::CreateOhosCameraCapturer(front, 0, 0, &resolution_);
        outResolution = resolution_;
        if (capturer_ == nullptr) {
            TGPCLOG("camera capturer unavailable device=%{public}s", deviceId.c_str());
            return;
        }
        captureThread_ = rtc::Thread::Create();
        captureThread_->SetName("tg-call-video", this);
        captureThread_->Start();
        captureThread_->BlockingCall([this] {
            capturer_->Init(tgcalls_ohos::CreateOhosCameraFrameReceiver(), this);
        });
        if (captureInfoUpdated_) {
            tgcalls::PlatformCaptureInfo info;
            info.shouldBeAdaptedToReceiverAspectRate = true;
            info.rotation = 0;
            captureInfoUpdated_(info);
        }
    }

    ~OhosPlatformVideoCapturer() override {
        if (captureThread_ != nullptr) {
            captureThread_->BlockingCall([this] {
                if (capturer_ != nullptr) {
                    if (running_.load()) {
                        capturer_->Stop();
                    }
                    capturer_->Release();
                    capturer_.reset();
                }
            });
            captureThread_->Stop();
        }
    }

    void setState(tgcalls::VideoState state) override {
        if (capturer_ == nullptr || captureThread_ == nullptr) {
            if (state == tgcalls::VideoState::Active && stateUpdated_) {
                stateUpdated_(tgcalls::VideoState::Inactive);
            }
            return;
        }
        const bool wantRunning = state == tgcalls::VideoState::Active;
        if (running_.exchange(wantRunning) == wantRunning) {
            return;
        }
        captureThread_->PostTask([this, wantRunning] {
            if (capturer_ == nullptr) {
                return;
            }
            if (wantRunning) {
                capturer_->Start();
            } else {
                capturer_->Stop();
            }
        });
        if (stateUpdated_) {
            stateUpdated_(wantRunning
                ? tgcalls::VideoState::Active : tgcalls::VideoState::Inactive);
        }
    }

    void setPreferredCaptureAspectRatio(float aspectRatio) override {
    }

    void setUncroppedOutput(
            std::shared_ptr<rtc::VideoSinkInterface<webrtc::VideoFrame>> sink) override {
        std::lock_guard<std::mutex> lock(sinkMutex_);
        uncroppedSink_ = std::move(sink);
    }

    int getRotation() override {
        return 0; // 旋转已按帧携带（VideoRotation），无须整体旋转。
    }

    // webrtc::VideoCapturer::Observer
    void OnCapturerStarted(bool success) override {
        TGPCLOG("call camera started success=%{public}d", success ? 1 : 0);
        if (!success && stateUpdated_) {
            running_.store(false);
            stateUpdated_(tgcalls::VideoState::Inactive);
        }
    }

    void OnCapturerStopped() override {
        TGPCLOG("call camera stopped");
    }

    void OnFrameCaptured(
            rtc::scoped_refptr<webrtc::VideoFrameBuffer> buffer,
            int64_t timestampUs, webrtc::VideoRotation rotation) override {
        if (!running_.load() || buffer == nullptr) {
            return;
        }
        if (source_ != nullptr) {
            source_->PushFrame(buffer, timestampUs, rotation);
        }
        std::shared_ptr<rtc::VideoSinkInterface<webrtc::VideoFrame>> sink;
        {
            std::lock_guard<std::mutex> lock(sinkMutex_);
            sink = uncroppedSink_;
        }
        if (sink != nullptr) {
            sink->OnFrame(webrtc::VideoFrame::Builder()
                .set_video_frame_buffer(buffer)
                .set_rotation(rotation)
                .set_timestamp_us(timestampUs)
                .build());
        }
    }

private:
    rtc::scoped_refptr<OhosRelayVideoSource> source_;
    std::function<void(tgcalls::VideoState)> stateUpdated_;
    std::function<void(tgcalls::PlatformCaptureInfo)> captureInfoUpdated_;
    std::unique_ptr<webrtc::VideoCapturer> capturer_;
    std::unique_ptr<rtc::Thread> captureThread_;
    std::pair<int, int> resolution_{0, 0};
    std::atomic<bool> running_{false};
    std::mutex sinkMutex_;
    std::shared_ptr<rtc::VideoSinkInterface<webrtc::VideoFrame>> uncroppedSink_;
};

}  // namespace

rtc::scoped_refptr<webrtc::VideoTrackSourceInterface> FakeInterface::makeVideoSource(
        rtc::Thread *signalingThread, rtc::Thread *workerThread) {
    return rtc::make_ref_counted<OhosRelayVideoSource>();
}

bool FakeInterface::supportsEncoding(const std::string &codecName) {
    const auto factory = webrtc::CreateBuiltinVideoEncoderFactory();
    if (factory == nullptr) {
        return false;
    }
    for (const auto &format : factory->GetSupportedFormats()) {
        if (format.name == codecName) {
            return true;
        }
    }
    return false;
}

void FakeInterface::adaptVideoSource(
        rtc::scoped_refptr<webrtc::VideoTrackSourceInterface> videoSource,
        int width, int height, int fps) {
}

std::unique_ptr<VideoCapturerInterface> FakeInterface::makeVideoCapturer(
        rtc::scoped_refptr<webrtc::VideoTrackSourceInterface> source, std::string deviceId,
        std::function<void(VideoState)> stateUpdated,
        std::function<void(PlatformCaptureInfo)> captureInfoUpdated,
        std::shared_ptr<PlatformContext> platformContext, std::pair<int, int> &outResolution) {
    auto relay = rtc::scoped_refptr<OhosRelayVideoSource>(
        static_cast<OhosRelayVideoSource *>(source.get()));
    return std::make_unique<OhosPlatformVideoCapturer>(
        std::move(relay), std::move(deviceId), std::move(stateUpdated),
        std::move(captureInfoUpdated), outResolution);
}

std::unique_ptr<PlatformInterface> CreatePlatformInterface() {
    return std::make_unique<FakeInterface>();
}

}  // namespace tgcalls
