# tgcalls for HarmonyOS

`scripts/build-tgcalls-ohos.sh` reproduces the arm64 shared library used by
the app and installs it at `entry/libs/arm64-v8a/libtgcalls_ohos.so`.

The compatibility set is intentionally pinned:

- OpenHarmony-SIG `ohos_webrtc` at `cebf29b` (WebRTC M120)
- `tg_owt` at `afd9d5d` (2023-12-21)
- `tgcalls` at `b9fa8b8` (2024-01-25)

The build also backports upstream tgcalls commit `8133188` (2025-11-08),
"fix audio cracks on rtmp stream". The patch corrects the stereo ring-buffer
capacity check, retains unfinished unified audio when advancing segments, and
increases buffering without requiring the ABI-incompatible 2026 WebRTC stack.
It also fixes `AVIOContextImpl` ownership: FFmpeg now owns a buffer allocated
with `av_malloc`, avoiding a deterministic double-free on HarmonyOS when an
RTMP audio segment is destroyed.

The 2023-12-21 date belongs only to the matching `tg_owt` revision; it is not
the application's release date. As of July 2026, upstream `tgcalls`
`development` and `desktop-app/tg_owt` `master` no longer compile against the
available HarmonyOS WebRTC M120 port: the public WebRTC API, ref-counting,
task/environment, codec and platform layers changed together. Updating only
the two commit hashes produces an ABI-incompatible build, so the reproducible
production path stays on this matched set until the current `tg_owt` platform
layer is forward-ported to OHOS.

Build on macOS with DevEco Studio installed:

```bash
bash scripts/build-tgcalls-ohos.sh
```

The first run downloads several gigabytes and can take tens of minutes. Set
`TGCALLS_BUILD_ROOT`, `DEVECO_SDK_ROOT`, `OHOS_NATIVE`, or `HMOS_NATIVE` to
override the defaults.

This integration provides:

- valid Telegram group-call join payloads and RTC transport;
- OHAudio 48 kHz PCM playout and microphone capture, with frame-aligned ring
  buffers and absolute-clock pacing to avoid drift/underrun crackle;
- multiple incoming camera and screen-share channels rendered to independent
  ArkUI XComponent surfaces, including rotation and dynamic resolution;
- outgoing microphone audio, front/back Camera NDK capture and
  AVScreenCapture screen sharing for ordinary RTC group calls; captured
  surfaces are converted to I420 before entering the existing WebRTC encoder,
  and camera/screen sources can be replaced without leaving the room;
- TDLib-backed broadcast part loading, with tgcalls/FFmpeg demux, decoding and
  A/V synchronisation for both normal split streams and RTMP `unified` streams.

The native camera/screen publisher feeds Telegram's RTC group-call sender,
which covers both a single local camera tile and rooms with multiple
participant streams. Telegram's administrator-created `is_rtmp_stream` mode
uses a separate RTMP ingest URL and stream key; this library decodes that mode
for viewers but does not pretend its RTC video source is an RTMP encoder.

Licensing: tgcalls is LGPL-3.0; tg_owt/WebRTC and their bundled dependencies
retain their upstream licenses. Distributors of the generated shared library
must include the applicable notices and satisfy the corresponding source and
relinking requirements.
