#!/usr/bin/env bash
# 为 OHOS arm64 编一份 rlottie（静态库），给 TGS 贴纸做原生渲染。
#
# **为什么不继续用 @ohos/lottie。** 那是 JS 实现，renderer 只能是 'canvas'
# （TgsStickerView 里那句注释："the only supported renderer"），每一帧都在 UI
# 线程上重算形状再画一遍。代价直接写在代码里：会话同时只允许 4 张动起来
# （MAX_LIVE_CHAT_TGS）、面板 14 张，超出的画静态缩略图。
#
# **为什么不像 webm 那样整段预解码。** 2026-09-14 在设备上读了 25 个真实 .tgs
# 的头：24 个是 60fps × 3 秒 = **180 帧**、512×512。按气泡尺寸 256px 算，
# 180 × 256KB = 46MB 一张，整段驻留不可能。而 Lottie 任意一帧都能独立渲染
# （不像 VP9 有帧间预测），所以正确的形状是**后台按需渲染 + 两三帧的环形缓冲**，
# 内存只有 0.5~0.8MB。
#
# 用法：
#   bash scripts/build-rlottie-ohos.sh
# 产物（不进版本库，同 libvpx）：
#   third_party/rlottie-ohos/arm64-v8a/librlottie.a
#   third_party/rlottie-ohos/include/*.h
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_ROOT="${RLOTTIE_BUILD_ROOT:-/tmp/telegramforharmony-rlottie-build}"
DEVECO_SDK_ROOT="${DEVECO_SDK_ROOT:-/Applications/DevEco-Studio.app/Contents/sdk/default}"
OHOS_NATIVE="${OHOS_NATIVE:-$DEVECO_SDK_ROOT/openharmony/native}"

# 钉 master 的当前头（2026-09-14）。rlottie 最后一个 tag 是 v0.2（2020），
# 之后三年多的修复都只在 master 上，钉 tag 等于自愿放弃它们。
PIN_RLOTTIE="683bbaa39dd0d366cf6b4bc300b4dfbee677ea6b"

SRC_DIR="$BUILD_ROOT/rlottie"
OUT_DIR="$BUILD_ROOT/build-ohos-arm64"
DEST_DIR="$PROJECT_ROOT/third_party/rlottie-ohos"

log() { printf '\033[36m[rlottie]\033[0m %s\n' "$*"; }
die() { printf '\033[31m[rlottie] %s\033[0m\n' "$*" >&2; exit 1; }

[ -f "$OHOS_NATIVE/build/cmake/ohos.toolchain.cmake" ] \
    || die "找不到 OHOS 的 cmake 工具链文件：$OHOS_NATIVE/build/cmake/ohos.toolchain.cmake"
command -v cmake >/dev/null || die "缺 cmake"
command -v ninja >/dev/null || die "缺 ninja"

mkdir -p "$BUILD_ROOT"
if [ ! -d "$SRC_DIR/.git" ]; then
    log "拉取 rlottie"
    git clone https://github.com/Samsung/rlottie "$SRC_DIR"
fi
git -C "$SRC_DIR" rev-parse --verify -q "$PIN_RLOTTIE^{commit}" >/dev/null \
    || git -C "$SRC_DIR" fetch origin
git -C "$SRC_DIR" checkout -q --detach "$PIN_RLOTTIE"
log "已切到 $PIN_RLOTTIE"

rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR"

# 关掉的三项都有理由：
#   LOTTIE_MODULE=OFF   —— 那是用 dlopen 去加载外部图片解码模块的可选件；贴纸
#                          里的位图图层我们不支持，开着只会引入一条 dlopen 路径。
#   LOTTIE_THREAD=OFF   —— rlottie 自带的任务线程池。我们自己按需渲染（一次
#                          一帧），再叠一层线程池只是抢 CPU。
#
#     ⚠️ **关掉它的代价：`vthread_local` 会展开成空**（src/vector/vglobal.h:74）。
#     于是 vrle.cpp 的 Scratch_Object、lottieitem.cpp 的 Dash_Vector 这些
#     "每线程一份"的临时缓冲变成**全进程一份**。2026-09-14 真机上换来一次
#     SIGSEGV（写未映射地址，栈在 rlottie 光栅化里）——因为 napi 的 async work
#     跑在 FFRT 线程池上，两张贴纸同时渲染就撞在同一块缓冲上。
#     **所以 cpp/tgs_render.cpp 把所有 rlottie 调用收到了自己的一条线程上。**
#     这两件事是绑定的：谁要把 LOTTIE_THREAD 改回 ON，或者把那条线程去掉，
#     都得先读懂另一半。
#   LOTTIE_TEST/EXAMPLE —— 不编测试和示例。
# LOTTIE_CACHE 保持默认开：它缓存的是**解析后的模型**，同一张贴纸反复播不必
# 重新解析 JSON，正是我们的用法。
log "configure"
# rlottie 的 CMakeLists 写的是 cmake_minimum_required(VERSION 3.2)，而新版
# cmake 已经删掉了对 <3.5 的兼容。这一项就是告诉它"按 3.5 的策略配"，
# 不改上游源码。
cmake -S "$SRC_DIR" -B "$OUT_DIR" -G Ninja \
    -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
    -DCMAKE_TOOLCHAIN_FILE="$OHOS_NATIVE/build/cmake/ohos.toolchain.cmake" \
    -DOHOS_ARCH=arm64-v8a \
    -DOHOS_PLATFORM=OHOS \
    -DCMAKE_BUILD_TYPE=Release \
    -DBUILD_SHARED_LIBS=OFF \
    -DLOTTIE_MODULE=OFF \
    -DLOTTIE_THREAD=OFF \
    -DLOTTIE_TEST=OFF \
    -DLOTTIE_EXAMPLE=OFF \
    -DCMAKE_POSITION_INDEPENDENT_CODE=ON

log "build"
cmake --build "$OUT_DIR" --parallel

LIB="$(find "$OUT_DIR" -name 'librlottie.a' | head -1)"
[ -n "$LIB" ] || die "没找到 librlottie.a"

mkdir -p "$DEST_DIR/arm64-v8a" "$DEST_DIR/include"
cp "$LIB" "$DEST_DIR/arm64-v8a/librlottie.a"
cp "$SRC_DIR/inc/"*.h "$DEST_DIR/include/"
log "产物：$DEST_DIR/arm64-v8a/librlottie.a ($(du -h "$DEST_DIR/arm64-v8a/librlottie.a" | cut -f1))"
log "头文件：$(ls "$DEST_DIR/include" | tr '\n' ' ')"
