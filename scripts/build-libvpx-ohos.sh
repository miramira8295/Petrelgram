#!/usr/bin/env bash
# 为 OHOS arm64 编一份**只含 VP9 解码器**的 libvpx，供透明 webm 贴纸使用。
#
# **为什么不复用 tgcalls 里那份。** libtgcalls_ohos.so 里确实已经有
# "WebM Project VP9 Decoder v1.13.1-599-gdf655cf4f"（随 WebRTC 的 third_party
# 编进去的），但那个 .so 是 stripped 的，vpx 的 C API 一个都没导出，dlsym 不到。
# 要让它导出就得重拉 WebRTC 那棵树重编——那是几个小时加几十 GB。单独编一份
# 只含解码器的 libvpx 是几分钟、约 1MB。
#
# **为什么不用系统的 OH_AVCodec。** 2026-08-20 在一台海思设备上枚举过系统全部
# 19 个视频解码器：vvc/hevc/avc/h263/mpeg2/mp4v-es/mpeg/msvideo1/wmv3/mjpeg/
# dvvideo/rawvideo/cinepak/rv30/rv40——没有 VP9，也没有 VP8。华为文档写 VP9
# 解码 API 23+ 支持，同页也写了"能力和设备强相关"。贴纸这种 512px/30fps/3s/
# 256KB 的东西本来就适合软解，不值得为它赌设备能力。
#
# 用法：
#   bash scripts/build-libvpx-ohos.sh
# 产物：
#   third_party/libvpx-ohos/arm64-v8a/libvpx.a
#   third_party/libvpx-ohos/include/vpx/*.h
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_ROOT="${LIBVPX_BUILD_ROOT:-/tmp/telegramforharmony-libvpx-build}"
DEVECO_SDK_ROOT="${DEVECO_SDK_ROOT:-/Applications/DevEco-Studio.app/Contents/sdk/default}"
OHOS_NATIVE="${OHOS_NATIVE:-$DEVECO_SDK_ROOT/openharmony/native}"

# **钉 v1.17.0-rc2，不跟 tgcalls 里那份（v1.13.1-599）对齐。**
#
# 为什么用 rc 而不是正式的 v1.16.0：1.16→1.17 之间有一条直接影响本用途的行为
# 变更——`vp9,yuvconfig2image: set img->{w,h} to yv12->y_{width,height}`，
# CHANGELOG 里明确列为 Upgrading 项：img->w/h 从"stride 与对齐高度"改成"真实
# 宽高"。按旧语义写合成代码，将来升级会静默地把右边缘写成垃圾。与其钉在旧语义
# 上等着踩，不如直接按新语义写。rc2 的 CHANGELOG 已写着 "2026-08-07 v1.17.0"，
# 等于定稿只差正式 tag，且声明与上一版 ABI 兼容。
#
# **但合成代码不依赖这个差异**：一律用 d_w/d_h（显示宽高，两版语义都一样）加
# 显式的 stride[]，而不是 w/h。这样即便将来再变也不受影响——钉新版是为了别踩，
# 用 d_w/d_h 是为了根本不碰这个雷。
# 至于版本对齐：一开始想着"两份 VP9 解码器都在包里，版本一致行为才一致"，但那个理由站不住：
# 两份互不来往（一份在 tgcalls 内部给视频通话用，这份给贴纸用），而这份要解的
# 是**从网络下来的不可信数据**——解码器的安全与健壮性修复远比版本齐整重要。
# 1.13.1 是 2023 年的，到 1.16.0 之间有三年的修复。
PIN_LIBVPX="86ecca1d566d4e892e8100933832a9510d68a039" # v1.17.0-rc2

SRC_DIR="$BUILD_ROOT/libvpx"
OUT_DIR="$BUILD_ROOT/build-ohos-arm64"
DEST_DIR="$PROJECT_ROOT/third_party/libvpx-ohos"

log() { printf '\033[36m[libvpx]\033[0m %s\n' "$*"; }
die() { printf '\033[31m[libvpx] %s\033[0m\n' "$*" >&2; exit 1; }

[ -d "$OHOS_NATIVE/llvm/bin" ] || die "找不到 OHOS native 工具链：$OHOS_NATIVE"
[ -x "$OHOS_NATIVE/llvm/bin/clang" ] || die "找不到 OHOS clang：$OHOS_NATIVE/llvm/bin/clang"

mkdir -p "$BUILD_ROOT"

if [ ! -d "$SRC_DIR/.git" ]; then
    log "拉取 libvpx"
    # 不加 --filter=blob:none：googlesource 不接受按 SHA 单独 fetch，缺的 blob
    # 补不回来，checkout 会以"无法读取树"失败。整个仓库约 100MB，直接全克隆。
    git clone https://chromium.googlesource.com/webm/libvpx "$SRC_DIR"
fi
git -C "$SRC_DIR" rev-parse --verify -q "$PIN_LIBVPX^{commit}" >/dev/null \
    || git -C "$SRC_DIR" fetch origin
git -C "$SRC_DIR" checkout -q --detach "$PIN_LIBVPX"
log "已切到 $PIN_LIBVPX"

TOOLCHAIN="$OHOS_NATIVE/llvm/bin"
SYSROOT="$OHOS_NATIVE/sysroot"
TARGET_TRIPLE="aarch64-linux-ohos"

# libvpx 的 configure 会故意把 CC/CXX/CFLAGS 做未加引号的单词拆分，再交给
# check_cmd 执行。因此 DevEco Studio 的默认 Windows 安装目录（名字中有空格）会
# 被截成 `/d/Applications/DevEco`，即使调用本脚本时正确引用了 DEVECO_SDK_ROOT
# 也没用。给每个工具做一个位于 /tmp、路径中无空格的薄包装，同时把同样会被
# 拆开的 --sysroot 固定在 clang 包装里。
TOOL_WRAPPER_DIR="$(mktemp -d /tmp/telegramforharmony-libvpx-toolchain.XXXXXX)"
cleanup_tool_wrappers() {
    rm -f "$TOOL_WRAPPER_DIR/clang" "$TOOL_WRAPPER_DIR/clang++" \
        "$TOOL_WRAPPER_DIR/llvm-ar" "$TOOL_WRAPPER_DIR/llvm-ranlib" \
        "$TOOL_WRAPPER_DIR/llvm-nm"
    rmdir "$TOOL_WRAPPER_DIR"
}
trap cleanup_tool_wrappers EXIT

write_tool_wrapper() {
    local wrapper="$1"
    local tool="$2"
    shift 2
    {
        printf '#!/usr/bin/env bash\nexec '
        printf '%q ' "$tool" "$@"
        printf '"$@"\n'
    } > "$wrapper"
    chmod +x "$wrapper"
}

write_tool_wrapper "$TOOL_WRAPPER_DIR/clang" "$TOOLCHAIN/clang" \
    "--target=$TARGET_TRIPLE" "--sysroot=$SYSROOT" "-ffile-prefix-map=$SRC_DIR=."
write_tool_wrapper "$TOOL_WRAPPER_DIR/clang++" "$TOOLCHAIN/clang++" \
    "--target=$TARGET_TRIPLE" "--sysroot=$SYSROOT" "-ffile-prefix-map=$SRC_DIR=."
write_tool_wrapper "$TOOL_WRAPPER_DIR/llvm-ar" "$TOOLCHAIN/llvm-ar"
write_tool_wrapper "$TOOL_WRAPPER_DIR/llvm-ranlib" "$TOOLCHAIN/llvm-ranlib"
write_tool_wrapper "$TOOL_WRAPPER_DIR/llvm-nm" "$TOOLCHAIN/llvm-nm"

rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR"
cd "$OUT_DIR"

# --target=arm64-linux-gcc 只是让 configure 走 arm64+linux 那套开关；真正的
# 编译器由下面的 CC/CXX/LD 指定，指向 OHOS 的 clang。
#
# 关掉的东西都是贴纸用不上的：VP8 两侧、VP9 编码器、示例、工具、文档、单测。
# 只留 VP9 解码器，产物才压得住体积。
#
# --enable-vp9-highbitdepth 不开：Telegram 贴纸是 8bit，开了平白多一份代码路径。
log "configure"
CC="$TOOL_WRAPPER_DIR/clang" \
CXX="$TOOL_WRAPPER_DIR/clang++" \
AR="$TOOL_WRAPPER_DIR/llvm-ar" \
RANLIB="$TOOL_WRAPPER_DIR/llvm-ranlib" \
NM="$TOOL_WRAPPER_DIR/llvm-nm" \
LD="$TOOL_WRAPPER_DIR/clang" \
CFLAGS="-O2 -fPIC" \
"$SRC_DIR/configure" \
    --target=arm64-linux-gcc \
    --enable-vp9-decoder \
    --disable-vp8 \
    --disable-vp9-encoder \
    --disable-examples \
    --disable-tools \
    --disable-docs \
    --disable-unit-tests \
    --disable-webm-io \
    --disable-libyuv \
    --enable-static \
    --disable-shared \
    --enable-pic \
    --disable-runtime-cpu-detect \
    > "$OUT_DIR/configure.log" 2>&1 || {
        tail -30 "$OUT_DIR/configure.log"
        [ ! -f "$OUT_DIR/config.log" ] || {
            printf '\n[libvpx] config.log 最后 40 行：\n' >&2
            tail -40 "$OUT_DIR/config.log" >&2
        }
        die "configure 失败"
    }

log "编译"
make -j"$(sysctl -n hw.ncpu 2>/dev/null || nproc)" > "$OUT_DIR/build.log" 2>&1 \
    || { tail -40 "$OUT_DIR/build.log"; die "编译失败"; }

[ -f "$OUT_DIR/libvpx.a" ] || die "没产出 libvpx.a"

log "安装到 $DEST_DIR"
rm -rf "$DEST_DIR"
mkdir -p "$DEST_DIR/arm64-v8a" "$DEST_DIR/include/vpx"
cp "$OUT_DIR/libvpx.a" "$DEST_DIR/arm64-v8a/libvpx.a"
# 公开头文件加 configure 生成的 vpx_config.h——vpx_integer.h 会 include 它。
cp "$SRC_DIR"/vpx/*.h "$DEST_DIR/include/vpx/"
cp "$OUT_DIR/vpx_config.h" "$DEST_DIR/include/vpx/"

cat > "$DEST_DIR/README.md" <<EOF
libvpx（**仅 VP9 解码器**），供透明 webm 贴纸使用。

由 scripts/build-libvpx-ohos.sh 生成，请勿手工修改。
- 版本：$PIN_LIBVPX
- 目标：$TARGET_TRIPLE
- 开关：--enable-vp9-decoder --disable-vp8 --disable-vp9-encoder

为什么不复用 libtgcalls_ohos.so 里那份 VP9 解码器、为什么不用系统
OH_AVCodec，见构建脚本开头的注释。
EOF

log "完成：$(du -h "$DEST_DIR/arm64-v8a/libvpx.a" | cut -f1)"
"$TOOLCHAIN/llvm-nm" --defined-only "$DEST_DIR/arm64-v8a/libvpx.a" 2>/dev/null \
    | grep -c "vpx_codec_vp9_dx" | xargs echo "[libvpx] vpx_codec_vp9_dx 符号数:"
