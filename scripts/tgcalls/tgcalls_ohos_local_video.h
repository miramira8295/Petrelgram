#ifndef TELEGRAM_FOR_HARMONY_TGCALLS_OHOS_LOCAL_VIDEO_H
#define TELEGRAM_FOR_HARMONY_TGCALLS_OHOS_LOCAL_VIDEO_H

#include "api/media_stream_interface.h"
#include "api/video/video_rotation.h"
#include "media/base/adapted_video_track_source.h"

#include <atomic>
#include <cstdint>
#include <functional>
#include <memory>
#include <utility>

namespace webrtc {
class VideoCapturer;
class VideoFrameBuffer;
class VideoFrameReceiver;
}  // namespace webrtc

namespace rtc {
class Thread;
}  // namespace rtc

namespace tgcalls_ohos {

enum class LocalVideoMode : int {
    Off = 0,
    CameraFront = 1,
    CameraBack = 2,
    Screen = 3,
};

using LocalVideoStateCallback = std::function<void(LocalVideoMode, bool, int)>;

class LocalVideoSource : public rtc::AdaptedVideoTrackSource {
public:
    static rtc::scoped_refptr<LocalVideoSource> Create(
        LocalVideoMode mode, uint32_t width, uint32_t height,
        LocalVideoStateCallback stateCallback);

    ~LocalVideoSource() override;

    void Start();
    void Stop();
    LocalVideoMode mode() const;

    // Called by the HarmonyOS capturer adapter.
    void OnCapturerStarted(bool success);
    void OnCapturerStopped();
    void OnFrameCaptured(
        rtc::scoped_refptr<webrtc::VideoFrameBuffer> buffer,
        int64_t timestampUs, webrtc::VideoRotation rotation);

protected:
    LocalVideoSource(
        LocalVideoMode mode, std::unique_ptr<webrtc::VideoCapturer> capturer,
        LocalVideoStateCallback stateCallback);

private:
    // MediaSourceInterface.
    SourceState state() const override;
    bool remote() const override;

    // VideoTrackSourceInterface.
    bool is_screencast() const override;
    absl::optional<bool> needs_denoising() const override;

    class CapturerObserver;

    LocalVideoMode mode_;
    std::unique_ptr<webrtc::VideoCapturer> capturer_;
    std::unique_ptr<rtc::Thread> captureThread_;
    std::unique_ptr<CapturerObserver> observer_;
    LocalVideoStateCallback stateCallback_;
    // The tgcalls sender queries the source immediately after setVideoSource.
    // Report live while the platform capturer starts asynchronously; failures
    // transition to ended through the native state callback.
    std::atomic<SourceState> state_{kLive};
    std::atomic<bool> started_{false};
    std::atomic<uint64_t> capturedFrames_{0};
};

// 1:1 通话平台采集器的构件：按前后摄选择相机并创建采集器（供
// tgcalls_ohos_platform.cpp 的 makeVideoCapturer 复用同一套相机机制）。
// outResolution 返回实际选中的预览分辨率（宽、高）。
std::unique_ptr<webrtc::VideoCapturer> CreateOhosCameraCapturer(
    bool front, uint32_t width, uint32_t height,
    std::pair<int, int> *outResolution);
std::unique_ptr<webrtc::VideoFrameReceiver> CreateOhosCameraFrameReceiver();

}  // namespace tgcalls_ohos

#endif  // TELEGRAM_FOR_HARMONY_TGCALLS_OHOS_LOCAL_VIDEO_H
