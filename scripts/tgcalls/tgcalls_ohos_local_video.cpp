#include "tgcalls_ohos_local_video.h"

#include "camera/camera_device_info.h"
#include "desktop_capture/desktop_capturer.h"
#include "helper/camera.h"
#include "video/video_capturer.h"
#include "video/video_frame_receiver.h"
#include "video/video_info.h"

#include "api/make_ref_counted.h"
#include "api/video/i420_buffer.h"
#include "api/video/video_frame.h"
#include "libyuv.h"
#include "rtc_base/logging.h"
#include "rtc_base/thread.h"
#include "rtc_base/time_utils.h"

#include <hilog/log.h>
#include <multimedia/image_framework/image/image_receiver_native.h>
#include <native_buffer/native_buffer.h>
#include <ohcamera/camera_device.h>

#include <algorithm>
#include <cmath>
#include <map>
#include <mutex>
#include <string>
#include <utility>
#include <vector>

#define LOCAL_VIDEO_LOG(fmt, ...) \
    OH_LOG_Print(LOG_APP, LOG_INFO, 0x0000, "tgcalls-local-video", fmt, ##__VA_ARGS__)

namespace {

constexpr uint32_t kDefaultCameraWidth = 1280;
constexpr uint32_t kDefaultCameraHeight = 720;
constexpr uint32_t kDefaultScreenWidth = 720;
constexpr uint32_t kDefaultScreenHeight = 1280;
constexpr int32_t kReceiverCapacity = 4;

class NativeFrameReceiver final : public webrtc::VideoFrameReceiver {
public:
    static std::unique_ptr<NativeFrameReceiver> Create() {
        return std::make_unique<NativeFrameReceiver>();
    }

    NativeFrameReceiver() = default;

    ~NativeFrameReceiver() override {
        Release();
    }

    uint64_t GetSurfaceId() const override {
        uint64_t surfaceId = 0;
        if (receiver_ != nullptr &&
            OH_ImageReceiverNative_GetReceivingSurfaceId(receiver_, &surfaceId) != IMAGE_SUCCESS) {
            return 0;
        }
        return surfaceId;
    }

    void SetVideoFrameSize(int32_t width, int32_t height) override {
        if (width <= 0 || height <= 0 || (width_ == width && height_ == height)) {
            return;
        }
        Release();
        width_ = width;
        height_ = height;

        OH_ImageReceiverOptions *options = nullptr;
        if (OH_ImageReceiverOptions_Create(&options) != IMAGE_SUCCESS || options == nullptr) {
            LOCAL_VIDEO_LOG("image receiver options create failed");
            return;
        }
        const Image_Size size{
            static_cast<uint32_t>(width_), static_cast<uint32_t>(height_)
        };
        Image_ErrorCode result = OH_ImageReceiverOptions_SetSize(options, size);
        if (result == IMAGE_SUCCESS) {
            result = OH_ImageReceiverOptions_SetCapacity(options, kReceiverCapacity);
        }
        if (result == IMAGE_SUCCESS) {
            result = OH_ImageReceiverNative_Create(options, &receiver_);
        }
        OH_ImageReceiverOptions_Release(options);
        if (result != IMAGE_SUCCESS || receiver_ == nullptr) {
            LOCAL_VIDEO_LOG(
                "image receiver create failed result=%{public}d size=%{public}dx%{public}d",
                static_cast<int>(result), width_, height_);
            receiver_ = nullptr;
            return;
        }
        {
            std::lock_guard<std::mutex> lock(receiversMutex_);
            receivers_[receiver_] = this;
        }
        if (OH_ImageReceiverNative_On(receiver_, OnImageAvailable) != IMAGE_SUCCESS) {
            Release();
            LOCAL_VIDEO_LOG("image receiver callback registration failed");
            return;
        }
        LOCAL_VIDEO_LOG(
            "image receiver ready surface=%{public}llu size=%{public}dx%{public}d",
            static_cast<unsigned long long>(GetSurfaceId()), width_, height_);
    }

private:
    static void OnImageAvailable(OH_ImageReceiverNative *receiver) {
        NativeFrameReceiver *self = nullptr;
        {
            std::lock_guard<std::mutex> lock(receiversMutex_);
            const auto found = receivers_.find(receiver);
            if (found != receivers_.end()) {
                self = found->second;
            }
        }
        if (self != nullptr) {
            self->ReadFrame();
        }
    }

    void ReadFrame() {
        OH_ImageNative *image = nullptr;
        if (receiver_ == nullptr ||
            OH_ImageReceiverNative_ReadLatestImage(receiver_, &image) != IMAGE_SUCCESS ||
            image == nullptr) {
            return;
        }

        uint32_t *componentTypes = nullptr;
        size_t componentCount = 0;
        Image_ErrorCode result =
            OH_ImageNative_GetComponentTypes(image, nullptr, &componentCount);
        if (result != IMAGE_SUCCESS || componentCount == 0) {
            OH_ImageNative_Release(image);
            return;
        }
        std::vector<uint32_t> types(componentCount);
        componentTypes = types.data();
        result = OH_ImageNative_GetComponentTypes(
            image, &componentTypes, &componentCount);
        if (result != IMAGE_SUCCESS || componentCount == 0) {
            OH_ImageNative_Release(image);
            return;
        }

        int32_t rowStride = 0;
        OH_NativeBuffer *nativeBuffer = nullptr;
        result = OH_ImageNative_GetRowStride(image, componentTypes[0], &rowStride);
        if (result == IMAGE_SUCCESS) {
            result = OH_ImageNative_GetByteBuffer(
                image, componentTypes[0], &nativeBuffer);
        }
        if (result != IMAGE_SUCCESS || nativeBuffer == nullptr || rowStride <= 0) {
            OH_ImageNative_Release(image);
            return;
        }

        OH_NativeBuffer_Config config{};
        OH_NativeBuffer_GetConfig(nativeBuffer, &config);
        if (config.width <= 0 || config.height <= 0) {
            OH_ImageNative_Release(image);
            return;
        }
        void *address = nullptr;
        if (OH_NativeBuffer_Map(nativeBuffer, &address) != 0 || address == nullptr) {
            OH_ImageNative_Release(image);
            return;
        }

        auto i420 = webrtc::I420Buffer::Create(config.width, config.height);
        int conversion = -1;
        const auto *bytes = static_cast<const uint8_t *>(address);
        switch (config.format) {
            case NATIVEBUFFER_PIXEL_FMT_RGBA_8888:
                conversion = libyuv::ABGRToI420(
                    bytes, rowStride,
                    i420->MutableDataY(), i420->StrideY(),
                    i420->MutableDataU(), i420->StrideU(),
                    i420->MutableDataV(), i420->StrideV(),
                    config.width, config.height);
                break;
            case NATIVEBUFFER_PIXEL_FMT_YCBCR_420_SP:
                conversion = libyuv::NV12ToI420(
                    bytes, rowStride,
                    bytes + static_cast<size_t>(rowStride) * config.height, rowStride,
                    i420->MutableDataY(), i420->StrideY(),
                    i420->MutableDataU(), i420->StrideU(),
                    i420->MutableDataV(), i420->StrideV(),
                    config.width, config.height);
                break;
            case NATIVEBUFFER_PIXEL_FMT_YCRCB_420_SP:
                conversion = libyuv::NV21ToI420(
                    bytes, rowStride,
                    bytes + static_cast<size_t>(rowStride) * config.height, rowStride,
                    i420->MutableDataY(), i420->StrideY(),
                    i420->MutableDataU(), i420->StrideU(),
                    i420->MutableDataV(), i420->StrideV(),
                    config.width, config.height);
                break;
            default:
                break;
        }
        OH_NativeBuffer_Unmap(nativeBuffer);
        OH_ImageNative_Release(image);

        const uint64_t frameNumber = ++frameCount_;
        if (conversion == 0 && callback_ != nullptr) {
            if (frameNumber == 1 || frameNumber % 300 == 0) {
                LOCAL_VIDEO_LOG(
                    "capture buffer frame=%{public}llu size=%{public}dx%{public}d "
                    "format=%{public}d rowStride=%{public}d",
                    static_cast<unsigned long long>(frameNumber),
                    config.width, config.height, config.format, rowStride);
            }
            callback_->OnFrameAvailable(
                i420, rtc::TimeMicros(), webrtc::kVideoRotation_0);
        } else if (frameNumber == 1 || frameNumber % 120 == 0) {
            LOCAL_VIDEO_LOG(
                "capture buffer conversion failed frame=%{public}llu format=%{public}d "
                "size=%{public}dx%{public}d result=%{public}d",
                static_cast<unsigned long long>(frameNumber),
                config.format, config.width, config.height, conversion);
        }
    }

    void Release() {
        if (receiver_ == nullptr) {
            return;
        }
        OH_ImageReceiverNative *receiver = receiver_;
        receiver_ = nullptr;
        {
            std::lock_guard<std::mutex> lock(receiversMutex_);
            receivers_.erase(receiver);
        }
        OH_ImageReceiverNative_Off(receiver);
        OH_ImageReceiverNative_Release(receiver);
    }

    int32_t width_ = 0;
    int32_t height_ = 0;
    uint64_t frameCount_ = 0;
    OH_ImageReceiverNative *receiver_ = nullptr;

    static std::mutex receiversMutex_;
    static std::map<OH_ImageReceiverNative *, NativeFrameReceiver *> receivers_;
};

std::mutex NativeFrameReceiver::receiversMutex_;
std::map<OH_ImageReceiverNative *, NativeFrameReceiver *>
    NativeFrameReceiver::receivers_;

video::PixelFormat ToPixelFormat(Camera_Format format) {
    switch (format) {
        case CAMERA_FORMAT_RGBA_8888:
            return video::PixelFormat::RGBA;
        case CAMERA_FORMAT_YUV_420_SP:
            return video::PixelFormat::NV12;
        default:
            return video::PixelFormat::Unsupported;
    }
}

struct CameraSelection {
    std::string deviceId;
    video::VideoProfile profile{};
    bool valid = false;
};

CameraSelection SelectCamera(bool front, uint32_t requestedWidth, uint32_t requestedHeight) {
    CameraSelection best;
    double bestScore = 1.0e30;
    auto devices = ohos::CameraManager::GetInstance().GetSupportedCameras();
    for (std::size_t i = 0; i < devices.Size(); ++i) {
        Camera_Device *device = devices[i];
        const bool isFront = device->cameraPosition == CAMERA_POSITION_FRONT;
        const bool isBack = device->cameraPosition == CAMERA_POSITION_BACK;
        if ((front && !isFront) || (!front && !isBack)) {
            continue;
        }
        auto capability =
            ohos::CameraManager::GetInstance().GetSupportedCameraOutputCapability(device);
        for (uint32_t j = 0; j < capability.PreviewProfileSize(); ++j) {
            Camera_Profile *nativeProfile = capability.GetPreviewProfile(j);
            const video::PixelFormat format = ToPixelFormat(nativeProfile->format);
            if (format == video::PixelFormat::Unsupported) {
                continue;
            }
            const uint32_t width = nativeProfile->size.width;
            const uint32_t height = nativeProfile->size.height;
            const double pixels = static_cast<double>(width) * height;
            const double requestedPixels =
                static_cast<double>(requestedWidth) * requestedHeight;
            const double pixelPenalty =
                std::abs(std::log(std::max(1.0, pixels) /
                                  std::max(1.0, requestedPixels)));
            const double nativeRatio =
                static_cast<double>(std::max(width, height)) /
                std::max(1u, std::min(width, height));
            const double requestedRatio =
                static_cast<double>(std::max(requestedWidth, requestedHeight)) /
                std::max(1u, std::min(requestedWidth, requestedHeight));
            const double ratioPenalty = std::abs(nativeRatio - requestedRatio) * 3.0;
            const double oversizePenalty =
                pixels > 1920.0 * 1080.0 ? 8.0 : 0.0;
            // RGBA avoids ambiguous vendor-specific NV12/NV21 layouts.
            const double formatPenalty =
                format == video::PixelFormat::RGBA ? 0.0 : 0.35;
            const double score =
                pixelPenalty + ratioPenalty + oversizePenalty + formatPenalty;
            if (score < bestScore) {
                bestScore = score;
                best.deviceId = device->cameraId;
                best.profile = video::VideoProfile{
                    format, video::Resolution{width, height},
                    video::FrameRateRange{0, UINT32_MAX}
                };
                best.valid = true;
            }
        }
    }
    return best;
}

class CameraCapturer final : public webrtc::VideoCapturer,
                             public webrtc::VideoFrameReceiver::Callback,
                             public ohos::CameraPreviewOutput::Observer {
public:
    CameraCapturer(std::string deviceId, video::VideoProfile profile)
        : deviceId_(std::move(deviceId)), profile_(profile) {
    }

    ~CameraCapturer() override {
        Release();
    }

    void Init(
            std::unique_ptr<webrtc::VideoFrameReceiver> receiver,
            webrtc::VideoCapturer::Observer *observer) override {
        observer_ = observer;
        receiver_ = std::move(receiver);
        receiver_->SetVideoFrameSize(
            static_cast<int32_t>(profile_.resolution.width),
            static_cast<int32_t>(profile_.resolution.height));
        receiver_->SetCallback(this);
        initialized_ = receiver_->GetSurfaceId() != 0;
    }

    void Release() override {
        Stop();
        observer_ = nullptr;
        receiver_.reset();
        initialized_ = false;
    }

    void Start() override {
        if (!initialized_) {
            NotifyStarted(false);
            return;
        }
        if (started_) {
            NotifyStarted(true);
            return;
        }

        Camera_Device *selectedDevice = nullptr;
        Camera_Profile *selectedProfile = nullptr;
        auto devices = ohos::CameraManager::GetInstance().GetSupportedCameras();
        for (std::size_t i = 0; i < devices.Size(); ++i) {
            if (deviceId_ != devices[i]->cameraId) {
                continue;
            }
            selectedDevice = devices[i];
            frontFacing_ =
                selectedDevice->cameraPosition == CAMERA_POSITION_FRONT;
            uint32_t orientation = 0;
            if (OH_CameraDevice_GetCameraOrientation(
                    selectedDevice, &orientation) == CAMERA_OK) {
                cameraOrientation_ = orientation;
            }
            auto capability =
                ohos::CameraManager::GetInstance().GetSupportedCameraOutputCapability(
                    selectedDevice);
            for (uint32_t j = 0; j < capability.PreviewProfileSize(); ++j) {
                Camera_Profile *candidate = capability.GetPreviewProfile(j);
                if (ToPixelFormat(candidate->format) == profile_.format &&
                    candidate->size.width == profile_.resolution.width &&
                    candidate->size.height == profile_.resolution.height) {
                    selectedProfile = candidate;
                    break;
                }
            }
            if (selectedProfile == nullptr) {
                NotifyStarted(false);
                return;
            }

            input_ = ohos::CameraManager::GetInstance().CreateCameraInput(
                selectedDevice);
            if (input_.IsEmpty() || !input_.Open()) {
                NotifyStarted(false);
                return;
            }
            output_ = ohos::CameraManager::GetInstance().CreatePreviewOutput(
                selectedProfile, std::to_string(receiver_->GetSurfaceId()));
            if (output_.IsEmpty()) {
                Cleanup();
                NotifyStarted(false);
                return;
            }
            output_.AddObserver(this);
            session_ = ohos::CameraManager::GetInstance().CreateCaptureSession();
            if (session_.IsEmpty() || !session_.BeginConfig() ||
                !session_.AddInput(input_) ||
                !session_.AddPreviewOutput(output_) ||
                !session_.CommitConfig() ||
                !session_.Start()) {
                Cleanup();
                NotifyStarted(false);
                return;
            }
            started_ = true;
            return;
        }
        NotifyStarted(false);
    }

    void Stop() override {
        if (!started_ && session_.IsEmpty() && input_.IsEmpty() &&
            output_.IsEmpty()) {
            return;
        }
        if (!session_.IsEmpty() && started_) {
            session_.Stop();
        }
        Cleanup();
        if (started_) {
            started_ = false;
            if (observer_ != nullptr) {
                observer_->OnCapturerStopped();
            }
        }
    }

    bool IsScreencast() override {
        return false;
    }

    void OnPreviewOutputFrameStart() override {
        if (!started_) {
            started_ = true;
        }
        NotifyStarted(true);
    }

    void OnPreviewOutputFrameEnd(int32_t) override {
        if (observer_ != nullptr) {
            observer_->OnCapturerStopped();
        }
    }

    void OnPreviewOutputError(Camera_ErrorCode errorCode) override {
        LOCAL_VIDEO_LOG("camera preview error=%{public}d", static_cast<int>(errorCode));
        NotifyStarted(false);
    }

    void OnFrameAvailable(
            rtc::scoped_refptr<webrtc::VideoFrameBuffer> buffer,
            int64_t timestampUs, webrtc::VideoRotation) override {
        if (observer_ == nullptr || buffer == nullptr) {
            return;
        }
        rtc::scoped_refptr<webrtc::VideoFrameBuffer> output = buffer;
        if (frontFacing_) {
            const auto source = buffer->ToI420();
            if (source != nullptr) {
                auto mirrored =
                    webrtc::I420Buffer::Create(source->width(), source->height());
                if (libyuv::I420Mirror(
                        source->DataY(), source->StrideY(),
                        source->DataU(), source->StrideU(),
                        source->DataV(), source->StrideV(),
                        mirrored->MutableDataY(), mirrored->StrideY(),
                        mirrored->MutableDataU(), mirrored->StrideU(),
                        mirrored->MutableDataV(), mirrored->StrideV(),
                        source->width(), source->height()) == 0) {
                    output = mirrored;
                }
            }
        }
        // Harmony reports the front sensor orientation in the opposite
        // direction from the outgoing WebRTC frame convention on the tested
        // devices. Without this correction the front-camera picture is
        // upside down for both the local preview and remote participants.
        const uint32_t correctedOrientation = frontFacing_
            ? (cameraOrientation_ + 180) % 360
            : cameraOrientation_;
        const int rotation = correctedOrientation % 90 == 0
            ? static_cast<int>(correctedOrientation) : 0;
        observer_->OnFrameCaptured(
            output, timestampUs,
            static_cast<webrtc::VideoRotation>(rotation));
    }

private:
    void NotifyStarted(bool success) {
        if (observer_ != nullptr) {
            observer_->OnCapturerStarted(success);
        }
    }

    void Cleanup() {
        Camera_PreviewOutput *rawOutput = output_.Raw();
        if (!output_.IsEmpty()) {
            output_.RemoveObserver(this);
        }
        if (!input_.IsEmpty()) {
            input_.Close();
        }
        session_.Reset();
        // The helper's CreatePreviewOutput wrapper is intentionally
        // non-owning, so release the NDK output explicitly after the capture
        // session has dropped its reference.
        output_.Reset();
        if (rawOutput != nullptr) {
            OH_PreviewOutput_Release(rawOutput);
        }
        input_.Reset();
    }

    std::string deviceId_;
    video::VideoProfile profile_;
    bool initialized_ = false;
    bool started_ = false;
    bool frontFacing_ = false;
    uint32_t cameraOrientation_ = 0;
    std::unique_ptr<webrtc::VideoFrameReceiver> receiver_;
    webrtc::VideoCapturer::Observer *observer_ = nullptr;
    ohos::CameraInput input_;
    ohos::CameraPreviewOutput output_;
    ohos::CameraCaptureSession session_;
};

std::unique_ptr<webrtc::VideoCapturer> CreateCapturer(
        tgcalls_ohos::LocalVideoMode mode, uint32_t width, uint32_t height) {
    if (mode == tgcalls_ohos::LocalVideoMode::Screen) {
        const uint32_t safeWidth = width == 0 ? kDefaultScreenWidth : width;
        const uint32_t safeHeight = height == 0 ? kDefaultScreenHeight : height;
        return webrtc::DesktopCapturer::Create(video::VideoProfile{
            video::PixelFormat::RGBA,
            video::Resolution{safeWidth, safeHeight},
            video::FrameRateRange{0, UINT32_MAX}
        });
    }
    const bool front = mode == tgcalls_ohos::LocalVideoMode::CameraFront;
    const uint32_t safeWidth = width == 0 ? kDefaultCameraWidth : width;
    const uint32_t safeHeight = height == 0 ? kDefaultCameraHeight : height;
    const CameraSelection selection =
        SelectCamera(front, safeWidth, safeHeight);
    if (!selection.valid) {
        return nullptr;
    }
    return std::make_unique<CameraCapturer>(
        selection.deviceId, selection.profile);
}

}  // namespace

namespace tgcalls_ohos {

class LocalVideoSource::CapturerObserver final
    : public webrtc::VideoCapturer::Observer {
public:
    explicit CapturerObserver(LocalVideoSource *source) : source_(source) {
    }

    void OnCapturerStarted(bool success) override {
        source_->OnCapturerStarted(success);
    }

    void OnCapturerStopped() override {
        source_->OnCapturerStopped();
    }

    void OnFrameCaptured(
            rtc::scoped_refptr<webrtc::VideoFrameBuffer> buffer,
            int64_t timestampUs, webrtc::VideoRotation rotation) override {
        source_->OnFrameCaptured(buffer, timestampUs, rotation);
    }

private:
    LocalVideoSource *source_;
};

rtc::scoped_refptr<LocalVideoSource> LocalVideoSource::Create(
        LocalVideoMode mode, uint32_t width, uint32_t height,
        LocalVideoStateCallback stateCallback) {
    if (mode == LocalVideoMode::Off) {
        return nullptr;
    }
    auto capturer = CreateCapturer(mode, width, height);
    if (capturer == nullptr) {
        return nullptr;
    }
    return rtc::make_ref_counted<LocalVideoSource>(
        mode, std::move(capturer), std::move(stateCallback));
}

LocalVideoSource::LocalVideoSource(
        LocalVideoMode mode, std::unique_ptr<webrtc::VideoCapturer> capturer,
        LocalVideoStateCallback stateCallback)
    : rtc::AdaptedVideoTrackSource(2),
      mode_(mode),
      capturer_(std::move(capturer)),
      captureThread_(rtc::Thread::Create()),
      observer_(std::make_unique<CapturerObserver>(this)),
      stateCallback_(std::move(stateCallback)) {
    captureThread_->SetName("tg-local-video", this);
    captureThread_->Start();
    captureThread_->BlockingCall([this] {
        capturer_->Init(NativeFrameReceiver::Create(), observer_.get());
    });
}

LocalVideoSource::~LocalVideoSource() {
    Stop();
    if (captureThread_ != nullptr) {
        captureThread_->BlockingCall([this] {
            if (capturer_ != nullptr) {
                capturer_->Release();
                capturer_.reset();
            }
        });
        captureThread_->Stop();
    }
    observer_.reset();
}

void LocalVideoSource::Start() {
    if (started_.exchange(true)) {
        return;
    }
    state_.store(kLive);
    captureThread_->PostTask([this] {
        if (capturer_ != nullptr) {
            capturer_->Start();
        }
    });
}

void LocalVideoSource::Stop() {
    if (!started_.exchange(false)) {
        return;
    }
    if (captureThread_ != nullptr) {
        captureThread_->BlockingCall([this] {
            if (capturer_ != nullptr) {
                capturer_->Stop();
            }
        });
    }
    state_.store(kEnded);
}

LocalVideoMode LocalVideoSource::mode() const {
    return mode_;
}

void LocalVideoSource::OnCapturerStarted(bool success) {
    state_.store(success ? kLive : kEnded);
    LOCAL_VIDEO_LOG(
        "capture state mode=%{public}d active=%{public}d",
        static_cast<int>(mode_), success ? 1 : 0);
    if (!success) {
        started_.store(false);
    }
    if (stateCallback_) {
        stateCallback_(mode_, success, success ? 0 : 1);
    }
}

void LocalVideoSource::OnCapturerStopped() {
    started_.store(false);
    state_.store(kEnded);
    LOCAL_VIDEO_LOG(
        "capture stopped mode=%{public}d", static_cast<int>(mode_));
    if (stateCallback_) {
        stateCallback_(mode_, false, 0);
    }
}

void LocalVideoSource::OnFrameCaptured(
        rtc::scoped_refptr<webrtc::VideoFrameBuffer> buffer,
        int64_t timestampUs, webrtc::VideoRotation rotation) {
    if (!started_.load() || buffer == nullptr) {
        return;
    }
    const uint64_t frameNumber = ++capturedFrames_;
    if (frameNumber == 1 || frameNumber % 300 == 0) {
        LOCAL_VIDEO_LOG(
            "source frame mode=%{public}d count=%{public}llu size=%{public}dx%{public}d "
            "rotation=%{public}d",
            static_cast<int>(mode_),
            static_cast<unsigned long long>(frameNumber),
            buffer->width(), buffer->height(), static_cast<int>(rotation));
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
    if (adaptedWidth != buffer->width() ||
        adaptedHeight != buffer->height() ||
        cropWidth != buffer->width() ||
        cropHeight != buffer->height()) {
        buffer = buffer->CropAndScale(
            cropX, cropY, cropWidth, cropHeight,
            adaptedWidth, adaptedHeight);
    }
    OnFrame(webrtc::VideoFrame::Builder()
        .set_video_frame_buffer(buffer)
        .set_rotation(rotation)
        .set_timestamp_us(timestampUs)
        .build());
}

webrtc::MediaSourceInterface::SourceState LocalVideoSource::state() const {
    return state_.load();
}

bool LocalVideoSource::remote() const {
    return false;
}

bool LocalVideoSource::is_screencast() const {
    return mode_ == LocalVideoMode::Screen;
}

absl::optional<bool> LocalVideoSource::needs_denoising() const {
    return mode_ == LocalVideoMode::Screen ? false : absl::optional<bool>(true);
}

std::unique_ptr<webrtc::VideoCapturer> CreateOhosCameraCapturer(
        bool front, uint32_t width, uint32_t height,
        std::pair<int, int> *outResolution) {
    const uint32_t safeWidth = width == 0 ? kDefaultCameraWidth : width;
    const uint32_t safeHeight = height == 0 ? kDefaultCameraHeight : height;
    const CameraSelection selection = SelectCamera(front, safeWidth, safeHeight);
    if (!selection.valid) {
        return nullptr;
    }
    if (outResolution != nullptr) {
        *outResolution = std::make_pair(
            static_cast<int>(selection.profile.resolution.width),
            static_cast<int>(selection.profile.resolution.height));
    }
    return std::make_unique<CameraCapturer>(selection.deviceId, selection.profile);
}

std::unique_ptr<webrtc::VideoFrameReceiver> CreateOhosCameraFrameReceiver() {
    return NativeFrameReceiver::Create();
}

}  // namespace tgcalls_ohos
