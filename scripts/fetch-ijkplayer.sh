#!/bin/bash
# 取自编的 ijkplayer har（2026-10-10 起不用 ohpm 上的 @ohos/ijkplayer，见 fork：
# https://gitcode.com/shaoewn/ohos_ijkplayer 的 petrelgram 分支）。har 13MB 级，不进版本库。
#
# 版本以 oh-package.json5 里 "file:./libs/ijkplayer-<版本>.har" 为准：
#   1. libs/ 下已有 → 什么都不做；
#   2. 从 fork 的 Release（标签 v<版本>）下载；
#   3. 下载不到且隔壁有 fork 源码（../ohos_ijkplayer）→ 就地编一份（要求 fork 当前版本号一致）。
# 用法：bash scripts/fetch-ijkplayer.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REPO_URL="${IJKPLAYER_REPO_URL:-https://gitcode.com/shaoewn/ohos_ijkplayer}"
FORK_DIR="${IJKPLAYER_FORK_DIR:-$ROOT/../ohos_ijkplayer}"
DEVECO="${DEVECO_HOME:-/Applications/DevEco-Studio.app/Contents}"

HAR_REL="$(grep -o 'file:./libs/ijkplayer-[^"]*\.har' "$ROOT/oh-package.json5" | sed 's|file:./||')"
[ -n "$HAR_REL" ] || { echo "oh-package.json5 里没有 file:./libs/ijkplayer-*.har 依赖"; exit 1; }
HAR="$ROOT/$HAR_REL"
VERSION="$(basename "$HAR" .har | sed 's/^ijkplayer-//')"

if [ -f "$HAR" ]; then
  echo "已有 $HAR_REL"
  exit 0
fi
mkdir -p "$(dirname "$HAR")"

URL="$REPO_URL/releases/download/v$VERSION/ijkplayer-$VERSION.har"
echo "下载 $URL"
if curl -fsSL -o "$HAR.part" "$URL"; then
  mv "$HAR.part" "$HAR"
  echo "完成：$HAR_REL"
  exit 0
fi
rm -f "$HAR.part"

if [ ! -d "$FORK_DIR/ijkplayer" ]; then
  echo "下载失败，且 $FORK_DIR 下没有 fork 源码。先 git clone -b petrelgram $REPO_URL.git $FORK_DIR"
  exit 1
fi
FORK_VERSION="$(grep -o '"version": "[^"]*"' "$FORK_DIR/ijkplayer/oh-package.json5" | cut -d'"' -f4)"
if [ "$FORK_VERSION" != "$VERSION" ]; then
  echo "fork 当前版本是 $FORK_VERSION，需要 $VERSION：先在 fork 里切到 v$VERSION 再编"
  exit 1
fi
echo "从 fork 源码编 $VERSION"
(
  cd "$FORK_DIR"
  [ -d ijkplayer/src/main/cpp/third_party/ffmpeg/ffmpeg ] || bash scripts/fetch-deps.sh
  export DEVECO_SDK_HOME="$DEVECO/sdk" PATH="$DEVECO/tools/node/bin:$PATH"
  "$DEVECO/tools/ohpm/bin/ohpm" install >/dev/null
  "$DEVECO/tools/hvigor/bin/hvigorw" assembleHar --mode module -p module=ijkplayer@default \
    -p product=default -p buildMode=release --no-daemon >/dev/null
)
cp "$FORK_DIR/ijkplayer/build/default/outputs/default/ijkplayer.har" "$HAR"
echo "完成：$HAR_REL"
