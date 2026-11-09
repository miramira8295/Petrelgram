#!/bin/bash
# Build the pinned Telegram group-call engine for HarmonyOS arm64-v8a.
# The first build downloads several gigabytes and can take tens of minutes.
set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_ROOT="${TGCALLS_BUILD_ROOT:-/tmp/telegramforharmony-tgcalls-build}"
DEVECO_SDK_ROOT="${DEVECO_SDK_ROOT:-/Applications/DevEco-Studio.app/Contents/sdk/default}"
OHOS_NATIVE="${OHOS_NATIVE:-$DEVECO_SDK_ROOT/openharmony/native}"
HMOS_NATIVE="${HMOS_NATIVE:-$DEVECO_SDK_ROOT/hms/native}"

PIN_OHOS_WEBRTC="cebf29b750017b57c4bcbaaf1fe57c553d7b47e4"
PIN_WEBRTC_THIRD_PARTY="8bc95681d66c67b16516023758213df89774a825"
PIN_GN="2de5327bfac4c9bcde7a07960d6ae344b13075b2"
PIN_TG_OWT="afd9d5d31798d3eacf9ed6c30601e91d0f1e4d60" # 2023-12-21, WebRTC M120-compatible
PIN_TGCALLS="b9fa8b84d8abe741183f157218ac038c596a54a5" # 2024-01-25

WEBRTC_DIR="$BUILD_ROOT/ohos_webrtc"
THIRD_PARTY_DIR="$BUILD_ROOT/webrtc_third_party"
GN_DIR="$BUILD_ROOT/gn"
TG_OWT_DIR="$BUILD_ROOT/tg_owt"
TGCALLS_DIR="$BUILD_ROOT/tgcalls"
WEBRTC_OUT="$WEBRTC_DIR/out/ohos-arm64-release"
TG_OWT_OUT="$TG_OWT_DIR/build-ohos-arm64"
DEST="$PROJECT_ROOT/entry/libs/arm64-v8a/libtgcalls_ohos.so"

log() { echo "[build-tgcalls] $*"; }
die() { echo "[build-tgcalls] ERROR: $*" >&2; exit 1; }
require_cmd() { command -v "$1" >/dev/null 2>&1 || die "'$1' is required"; }

require_cmd git
require_cmd cmake
require_cmd ninja
require_cmd python3
[ -f "$HMOS_NATIVE/build/cmake/hmos.toolchain.bisheng.cmake" ] || \
    die "HarmonyOS NDK not found below $HMOS_NATIVE"
[ -d "$OHOS_NATIVE/sysroot" ] || die "OpenHarmony native SDK not found below $OHOS_NATIVE"
mkdir -p "$BUILD_ROOT"

checkout_pin() {
    local url="$1" dir="$2" commit="$3"
    if [ ! -d "$dir/.git" ]; then
        log "Cloning $url"
        git clone --filter=blob:none --no-checkout "$url" "$dir"
    fi
    git -C "$dir" fetch --depth=1 origin "$commit"
    git -C "$dir" checkout --detach "$commit"
}

apply_once() {
    local repo="$1" patch="$2"
    if git -C "$repo" apply --reverse --check "$patch" >/dev/null 2>&1; then
        return
    fi
    git -C "$repo" apply --check "$patch" || die "patch no longer applies: $patch"
    git -C "$repo" apply "$patch"
}

checkout_pin https://gitee.com/openharmony-sig/ohos_webrtc.git "$WEBRTC_DIR" "$PIN_OHOS_WEBRTC"
checkout_pin https://gitee.com/zhong-luping/webrtc_third_party.git "$THIRD_PARTY_DIR" "$PIN_WEBRTC_THIRD_PARTY"
checkout_pin https://gn.googlesource.com/gn "$GN_DIR" "$PIN_GN"
checkout_pin https://github.com/desktop-app/tg_owt.git "$TG_OWT_DIR" "$PIN_TG_OWT"
checkout_pin https://github.com/TelegramMessenger/tgcalls.git "$TGCALLS_DIR" "$PIN_TGCALLS"

git -C "$TG_OWT_DIR" submodule update --init --depth=1
if [ -e "$WEBRTC_DIR/third_party" ] && [ ! -L "$WEBRTC_DIR/third_party" ]; then
    die "$WEBRTC_DIR/third_party exists and is not a symlink"
fi
ln -sfn "$THIRD_PARTY_DIR/third_party" "$WEBRTC_DIR/third_party"

if [ "$(uname -s)" = "Darwin" ]; then
    apply_once "$WEBRTC_DIR" "$SCRIPT_DIR/tgcalls/ohos-webrtc-macos-host.patch"
fi
apply_once "$TG_OWT_DIR" "$SCRIPT_DIR/tgcalls/tg_owt-ohos.patch"
apply_once "$TGCALLS_DIR" "$SCRIPT_DIR/tgcalls/tgcalls-rtmp-audio-crackle.patch"
apply_once "$TGCALLS_DIR" "$SCRIPT_DIR/tgcalls/tgcalls-avio-owned-buffer.patch"

if [ ! -x "$GN_DIR/out/gn" ]; then
    log "Building the host GN executable"
    # gen.py runs `git describe --match initial-commit`; our shallow, tag-less
    # GN clone has no such tag, so it aborts. Hide .git during gen.py so it
    # takes the no-git fallback (version "0 (UNKNOWN)") and proceeds.
    (
        cd "$GN_DIR"
        moved=0
        if [ -e .git ]; then mv .git .git.hidden && moved=1; fi
        set +e
        python3 build/gen.py
        rc=$?
        set -e
        if [ "$moved" = 1 ]; then mv .git.hidden .git; fi
        [ "$rc" -eq 0 ] || exit 1
        ninja -C out
    )
fi

# ffmpeg/H264 must be enabled or nothing references //third_party/ffmpeg and GN
# never emits ffmpeg_internal, so the broadcast-decode archive can't be built.
GN_ARGS="target_os=\"ohos\" target_cpu=\"arm64\" is_debug=false rtc_include_tests=false ohos_sdk_native_root=\"$OHOS_NATIVE/\" rtc_use_h264=true proprietary_codecs=true ffmpeg_branding=\"Chrome\" rtc_initialize_ffmpeg=true"
if [ "$(uname -s)" = "Darwin" ]; then
    require_cmd xcrun
    MACOS_SYSROOT="$(xcrun --sdk macosx --show-sdk-path)"
    GN_ARGS="$GN_ARGS sysroot=\"$MACOS_SYSROOT\""
fi
log "Building OHOS WebRTC third-party archives"
"$GN_DIR/out/gn" gen "$WEBRTC_OUT" --root="$WEBRTC_DIR" --args="$GN_ARGS"
ninja -C "$WEBRTC_OUT" webrtc obj/third_party/ffmpeg/libffmpeg_internal.a

log "Building tg_owt + tgcalls"
cmake -S "$TG_OWT_DIR" -B "$TG_OWT_OUT" -G Ninja \
    -DCMAKE_TOOLCHAIN_FILE="$HMOS_NATIVE/build/cmake/hmos.toolchain.bisheng.cmake" \
    -DCMAKE_BUILD_TYPE=Release \
    -DOHOS_SDK_NATIVE="$OHOS_NATIVE" \
    -DHMOS_SDK_NATIVE="$HMOS_NATIVE" \
    -DOHOS_ARCH=arm64-v8a \
    -DTG_OWT_SPECIAL_TARGET=ohos \
    -DTG_OWT_USE_PROTOBUF=OFF \
    -DTG_OWT_BUILD_AUDIO_BACKENDS=OFF \
    -DTG_OWT_USE_X11=OFF \
    -DTG_OWT_USE_PIPEWIRE=OFF \
    -DTG_OWT_FFMPEG_INCLUDE_PATH="$WEBRTC_DIR/third_party/ffmpeg/chromium/config/Chrome/ohos/arm64;$WEBRTC_DIR/third_party/ffmpeg" \
    -DTG_OWT_OPUS_INCLUDE_PATH="$WEBRTC_DIR/third_party/opus/src/include" \
    -DTG_OWT_OPENSSL_INCLUDE_PATH="$WEBRTC_DIR/third_party/boringssl/src/include" \
    -DTG_OWT_LIBJPEG_INCLUDE_PATH="$WEBRTC_DIR/third_party/libjpeg_turbo" \
    -DTG_OWT_LIBVPX_INCLUDE_PATH="$WEBRTC_DIR/third_party/libvpx/source/libvpx" \
    -DTGCALLS_SOURCE_DIR="$TGCALLS_DIR" \
    -DTGCALLS_BRIDGE_SOURCE="$SCRIPT_DIR/tgcalls/tgcalls_ohos_bridge.cpp" \
    -DOHOS_WEBRTC_OBJ_DIR="$WEBRTC_OUT/obj" \
    -DOHOS_WEBRTC_SOURCE_DIR="$WEBRTC_DIR/sdk/ohos/src/ohos_webrtc" \
    -DTGCALLS_OHOS_CMAKE="$SCRIPT_DIR/tgcalls/tgcalls-ohos.cmake"
ninja -C "$TG_OWT_OUT" tgcalls_ohos

mkdir -p "$(dirname "$DEST")"
"$HMOS_NATIVE/BiSheng/bin/llvm-strip" --strip-unneeded \
    -o "$DEST" "$TG_OWT_OUT/libtgcalls_ohos.so"
"$HMOS_NATIVE/BiSheng/bin/llvm-nm" -D --defined-only "$DEST" | \
    grep tgcalls_ohos_emit_join_payload >/dev/null || die "expected bridge symbols are missing"
log "Done: $DEST"
