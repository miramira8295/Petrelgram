#!/bin/bash
# Build libtdjson.so for HarmonyOS arm64-v8a from source.
#
# Wraps https://github.com/ErBWs/tdlib-ohos-build and applies the 6 macOS /
# portability fixes discovered and verified while cross-compiling this
# project's TDLib binary (see .superpowers/sdd/task-2-report.md for the full
# investigation). Do not `source` this into an interactive shell — run it
# with bash explicitly:
#
#   bash scripts/build-tdlib.sh
#
set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DEST_LIB_DIR="$PROJECT_ROOT/entry/libs/arm64-v8a"

# Pin versions this script was validated against
# (must match tdlib-ohos-build/download/deps-version.sh)
PIN_OPENSSL="OpenSSL_1_1_1w"
PIN_TDLIB="a17f87c4cff7b90b278d12b91ba0614383aaee82"   # TDLib 1.8.65

# Overridable workspace locations (kept outside the repo on purpose: these
# hold multi-GB source/build trees that should never be committed).
#
# The build directory ends up INSIDE the binary: TDLib's assertions expand
# __FILE__, and OpenSSL compiles its OPENSSLDIR in as a constant — neither can
# be stripped afterwards. Building under the real $HOME therefore leaks the
# developer's username to anyone who runs `strings` on a released
# libtdjson.so.
#
# The upstream scripts hardcode "$HOME/tdlib" throughout, so the workspace
# can't simply be pointed elsewhere — instead the whole build runs with HOME
# overridden to a neutral directory, which every one of those paths then
# derives from.
BUILD_HOME="${TDLIB_BUILD_HOME:-/tmp/tdbuild}"
mkdir -p "$BUILD_HOME"
export HOME="$BUILD_HOME"

BUILD_REPO_DIR="${TDLIB_BUILD_REPO_DIR:-$BUILD_HOME/tdlib-ohos-build}"
WORK_DIR="${TDLIB_WORK_DIR:-$BUILD_HOME/tdlib}"

log() { echo "[build-tdlib] $*"; }
die() { echo "[build-tdlib] ERROR: $*" >&2; exit 1; }

# FIX #4: this script must run under bash (word-splitting on the CC/CXX
# strings built in post-download.sh relies on it). zsh does not split
# unquoted variables the same way and will fail with
# "no such file or directory" when it tries to exec the whole CC string as
# a single binary path.
if [ -z "${BASH_VERSION:-}" ]; then
  die "this script must be run with bash, not sh/zsh: bash scripts/build-tdlib.sh"
fi

# ---------------------------------------------------------------------------
# Preflight checks
# ---------------------------------------------------------------------------
require_cmd() {
  local cmd="$1" hint="$2"
  command -v "$cmd" >/dev/null 2>&1 || die "'$cmd' not found. $hint"
}

log "Checking prerequisites ..."
require_cmd gperf   "Install with: brew install gperf (Xcode Command Line Tools do not include it)"
require_cmd cmake   "Install with: brew install cmake"
require_cmd ninja   "Install with: brew install ninja"
require_cmd git     "Install Xcode Command Line Tools: xcode-select --install"
require_cmd clang++ "Install Xcode Command Line Tools: xcode-select --install"

[ -n "${OHOS_NDK_HOME:-}" ] || die "OHOS_NDK_HOME is not set. Example: export OHOS_NDK_HOME=/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony"
[ -d "$OHOS_NDK_HOME/native/llvm/bin" ] || die "OHOS_NDK_HOME=$OHOS_NDK_HOME does not look like a valid OpenHarmony NDK (missing native/llvm/bin). Point it at DevEco Studio's bundled NDK, e.g. /Applications/DevEco-Studio.app/Contents/sdk/default/openharmony"
export OHOS_NDK_HOME

log "Prerequisites OK. OHOS_NDK_HOME=$OHOS_NDK_HOME"

# ---------------------------------------------------------------------------
# Step 1: clone tdlib-ohos-build
# FIX #6: files lose their executable bit across this clone/copy path;
# restore it explicitly instead of relying on the checkout.
# ---------------------------------------------------------------------------
if [ ! -d "$BUILD_REPO_DIR" ]; then
  log "Cloning tdlib-ohos-build into $BUILD_REPO_DIR ..."
  git clone https://github.com/ErBWs/tdlib-ohos-build.git "$BUILD_REPO_DIR"
else
  log "Reusing existing clone at $BUILD_REPO_DIR"
fi
chmod +x "$BUILD_REPO_DIR"/download/*.sh "$BUILD_REPO_DIR"/scripts/*.sh 2>/dev/null || true
[ -f "$BUILD_REPO_DIR/build.sh" ] && chmod +x "$BUILD_REPO_DIR/build.sh"

cd "$BUILD_REPO_DIR"

ACTUAL_OPENSSL="$(grep '^V_OPENSSL=' download/deps-version.sh | cut -d= -f2)"
ACTUAL_TDLIB="$(grep '^V_TDLIB=' download/deps-version.sh | cut -d= -f2)"
if [ "$ACTUAL_OPENSSL" != "$PIN_OPENSSL" ] || [ "$ACTUAL_TDLIB" != "$PIN_TDLIB" ]; then
  log "WARNING: upstream download/deps-version.sh now pins OpenSSL=$ACTUAL_OPENSSL, TDLib=$ACTUAL_TDLIB,"
  log "         which differs from the versions this script was validated against"
  log "         (OpenSSL=$PIN_OPENSSL, TDLib=$PIN_TDLIB). Proceeding anyway, but re-verify the fixes below"
  log "         still apply if the build fails."
fi

# ---------------------------------------------------------------------------
# FIX #1: download/post-download.sh hardcodes OHOS_NDK_HOME / OHOS_SDK to the
# Linux SDK path produced by download-sdk.sh. On macOS we use DevEco Studio's
# bundled NDK instead, so rewrite the exports to default to (without
# clobbering) the caller's already-exported environment variable.
# ---------------------------------------------------------------------------
if ! grep -q 'OHOS_NDK_HOME:-' download/post-download.sh; then
  log "Applying FIX #1 (OHOS_NDK_HOME/OHOS_SDK fallback) to download/post-download.sh"
  sed -i.bak \
    -e 's|^export OHOS_SDK=.*|export OHOS_SDK=${OHOS_SDK:-$HOME/tdlib/sdk/ohos-sdk/linux}|' \
    -e 's|^export OHOS_NDK_HOME=.*|export OHOS_NDK_HOME=${OHOS_NDK_HOME:-$HOME/tdlib/sdk/ohos-sdk/linux}|' \
    download/post-download.sh
  grep -q 'export OHOS_NDK_HOME=\${OHOS_NDK_HOME:-' download/post-download.sh || \
    die "FIX #1 sed patch failed on download/post-download.sh: upstream file content may have changed, please verify download/post-download.sh"
else
  log "FIX #1 already applied, skipping"
fi

# ---------------------------------------------------------------------------
# FIX #2: `nproc` is GNU coreutils only; macOS/BSD has no such command and
# `set -eu` makes the unbound-variable-free but failing command substitution
# fatal immediately.
# ---------------------------------------------------------------------------
if grep -q 'CORES=\$(nproc)' download/post-download.sh; then
  log "Applying FIX #2 (nproc -> sysctl fallback) to download/post-download.sh"
  sed -i.bak2 \
    -e 's#^export CORES=\$(nproc)$#export CORES=$(command -v nproc >/dev/null 2>\&1 \&\& nproc || sysctl -n hw.ncpu)#' \
    download/post-download.sh
  grep -q 'command -v nproc >/dev/null' download/post-download.sh || \
    die "FIX #2 sed patch failed on download/post-download.sh: upstream file content may have changed, please verify download/post-download.sh"
else
  log "FIX #2 already applied, skipping"
fi

# ---------------------------------------------------------------------------
# FIX #3: download/download-deps.sh has a dangling `if` with no `then`/`fi`
# on the OpenSSL clone line. This is an upstream bug (any bash, any OS), not
# macOS-specific.
# ---------------------------------------------------------------------------
if grep -q '^if \[ ! -d openssl \] &&' download/download-deps.sh; then
  log "Applying FIX #3 (dangling if/then/fi) to download/download-deps.sh"
  sed -i.bak 's|^if \[ ! -d openssl \] &&|[ ! -d openssl ] \&\&|' download/download-deps.sh
  grep -q '^\[ ! -d openssl \] &&' download/download-deps.sh || \
    die "FIX #3 sed patch failed on download/download-deps.sh: upstream file content may have changed, please verify download/download-deps.sh"
else
  log "FIX #3 already applied, skipping"
fi

bash -n download/post-download.sh || die "download/post-download.sh still has a syntax error after patching"
bash -n download/download-deps.sh || die "download/download-deps.sh still has a syntax error after patching"

# ---------------------------------------------------------------------------
# Step 2: download deps + apply the OHOS platform patch to TDLib
# FIX #4: always invoke these scripts with `bash ./...`, never `source`/`.`
# them into an interactive zsh session.
# ---------------------------------------------------------------------------
mkdir -p "$WORK_DIR"
log "Downloading OpenSSL + TDLib sources into $WORK_DIR ..."
# FIX #3 rewrote the dangling `if` into `[ ! -d openssl ] && git clone ...`,
# whose exit status is 1 once openssl is already there — and it is the script's
# last command, so a re-run reports failure even though everything is present.
# Judge by what actually landed on disk instead of by the exit code.
bash ./download/download-deps.sh || log "download-deps.sh returned non-zero (deps likely already present) — verifying"
[ -d "$WORK_DIR/openssl" ] || die "OpenSSL sources missing at $WORK_DIR/openssl"
[ -d "$WORK_DIR/td" ] || die "TDLib sources missing at $WORK_DIR/td"

# Upstream's deps-version.sh pins its own TDLib commit; check out the version
# this project targets instead (kept in PIN_TDLIB above).
CURRENT_TDLIB="$(git -C "$WORK_DIR/td" rev-parse HEAD)"
if [ "$CURRENT_TDLIB" != "$PIN_TDLIB" ]; then
  log "Checking out pinned TDLib $PIN_TDLIB (was $CURRENT_TDLIB) ..."
  git -C "$WORK_DIR/td" fetch --tags origin
  git -C "$WORK_DIR/td" checkout -f "$PIN_TDLIB"
  rm -f "$WORK_DIR/td/.ohos-platform-patch-applied"
fi

if [ ! -f "$WORK_DIR/td/.ohos-platform-patch-applied" ]; then
  log "Applying patches/td-add-ohos-platform.patch ..."
  ( cd "$WORK_DIR/td" && git apply "$BUILD_REPO_DIR/patches/td-add-ohos-platform.patch" )
  touch "$WORK_DIR/td/.ohos-platform-patch-applied"
else
  log "td-add-ohos-platform.patch already applied, skipping"
fi

# ---------------------------------------------------------------------------
# Step 3: cross-compile OpenSSL (FIX #4: bash, not zsh)
# ---------------------------------------------------------------------------
log "Building OpenSSL for arm64-v8a (~3 min) ..."
bash ./scripts/openssl.sh build

# ---------------------------------------------------------------------------
# FIX #5 (the big one): TDLib's CMake skips ALL code generators (gperf mime
# tables, TL schema -> td_api/telegram_api C++) whenever
# CMAKE_CROSSCOMPILING=TRUE (which ohos.toolchain.cmake sets). The cross
# build's ninja targets still reference those generated .cpp files, so a
# bare cross-compile fails with errors like:
#   clang++: error: no such file or directory: .../mime_type_to_extension.cpp
#   clang++: error: no such file or directory: .../td_api_0.cpp
# These MUST be generated on the host (native toolchain) first, before the
# cross build runs.
# ---------------------------------------------------------------------------
log "Pre-generating TDLib sources on the host toolchain (FIX #5) ..."

# 5a: mime type gperf tables (tdutils)
(
  cd "$WORK_DIR/td/tdutils/generate"
  # The generators write into auto/, which is not checked in (TDLib 1.8.65
  # ships no placeholder for it) — gperf fails with "Can't open output file".
  mkdir -p auto
  clang++ -std=c++17 -O2 -o /tmp/generate_mime_types_gperf generate_mime_types_gperf.cpp
  /tmp/generate_mime_types_gperf mime_types.txt \
    auto/mime_type_to_extension.gperf auto/extension_to_mime_type.gperf
  gperf -m100 --output-file=auto/mime_type_to_extension.cpp auto/mime_type_to_extension.gperf
  gperf -m100 --output-file=auto/extension_to_mime_type.cpp auto/extension_to_mime_type.gperf
)

# 5b: TL/API generated sources (td_api_*.cpp, telegram_api_*.cpp,
# td_api_json_*.cpp, ...). TD_GENERATE_SOURCE_FILES + prepare_cross_compiling
# is TDLib's officially supported way to pre-generate these for a
# cross-compiling build; the output is written into the source tree under
# td/generate/auto/td/telegram/ where the cross build picks it up.
mkdir -p "$WORK_DIR/td/native-build"
(
  cd "$WORK_DIR/td/native-build"
  cmake -GNinja -DTD_GENERATE_SOURCE_FILES=ON ..
  ninja prepare_cross_compiling
)

# ---------------------------------------------------------------------------
# Step 4: cross-compile TDLib (FIX #4: bash, not zsh)
# ---------------------------------------------------------------------------
log "Cross-compiling TDLib for arm64-v8a (minutes on a modern multi-core Mac; up to ~60 min on a low-core CI runner) ..."
rm -rf "$WORK_DIR/td/.build"
bash ./scripts/tdlib.sh build

# ---------------------------------------------------------------------------
# Step 5: verify + install into entry/libs/arm64-v8a/
# ---------------------------------------------------------------------------
BUILT_LIB="$WORK_DIR/arm64-build/tdlib/libtdjson.so"
[ -f "$BUILT_LIB" ] || die "build finished but $BUILT_LIB is missing"

log "Verifying $BUILT_LIB ..."
file "$BUILT_LIB"
"$OHOS_NDK_HOME/native/llvm/bin/llvm-nm" -D --defined-only "$BUILT_LIB" | grep td_json_client \
  || die "td_json_client_* symbols missing from libtdjson.so"

mkdir -p "$DEST_LIB_DIR"
cp -p "$BUILT_LIB" "$DEST_LIB_DIR/"

# ---------------------------------------------------------------------------
# CRITICAL: normalize the SONAME to match the packaged filename.
# TDLib stamps SOVERSION into the library, so the built .so advertises an
# internal SONAME of "libtdjson.so.<version>" (e.g. libtdjson.so.1.8.54).
# The HAP packages the file as plain "libtdjson.so", and our libentry.so
# records whatever SONAME it linked against as its DT_NEEDED. If they differ,
# the dynamic linker cannot find the dependency at runtime, libentry.so fails
# to load silently, and every bridge call returns undefined/empty with NO
# crash and NO error — extremely hard to diagnose. Force the SONAME to the
# plain filename so DT_NEEDED == packaged name.
# ---------------------------------------------------------------------------
command -v patchelf >/dev/null 2>&1 \
  || die "patchelf is required to normalize the SONAME. Install it: brew install patchelf (macOS) / apt-get install patchelf (Linux)"
patchelf --set-soname libtdjson.so "$DEST_LIB_DIR/libtdjson.so"
ACTUAL_SONAME="$(patchelf --print-soname "$DEST_LIB_DIR/libtdjson.so")"
[ "$ACTUAL_SONAME" = "libtdjson.so" ] \
  || die "SONAME normalization failed: expected libtdjson.so, got $ACTUAL_SONAME"
log "SONAME normalized to libtdjson.so"

# The linker records the build machine's library search path as RUNPATH. It is
# useless at runtime (the HAP's libs directory is what matters) and leaks the
# build tree's absolute path into a published binary — drop it.
patchelf --remove-rpath "$DEST_LIB_DIR/libtdjson.so" 2>/dev/null || true

# A released .so must not carry any trace of the machine that built it.
if strings "$DEST_LIB_DIR/libtdjson.so" | grep -qE "/Users/|/Volumes/|/home/"; then
  strings "$DEST_LIB_DIR/libtdjson.so" | grep -E "/Users/|/Volumes/|/home/" | sort -u | head
  die "libtdjson.so embeds absolute build paths (see above). Build under a neutral WORK_DIR."
fi
log "No absolute build paths embedded in libtdjson.so"

log "Done: $DEST_LIB_DIR/libtdjson.so"
