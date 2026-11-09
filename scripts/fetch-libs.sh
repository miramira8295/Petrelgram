#!/bin/bash
# Download the prebuilt native libraries from GitHub Releases into
# entry/libs/arm64-v8a/.
#
# Both libraries ship in the same release and libentry.so links against BOTH
# (see entry/src/main/cpp/CMakeLists.txt). Fetching only one leaves the build
# dying in ninja with:
#   error: 'entry/libs/arm64-v8a/libtgcalls_ohos.so', needed by 'libentry.so',
#   missing and no known rule to make it
# which is why this replaces the old libtdjson-only fetch script.
set -eu
REPO="miramira8295/TelegramForHarmony"
DEST="$(dirname "$0")/../entry/libs/arm64-v8a"
LIBS="libtdjson.so libtgcalls_ohos.so"

TAG="${1:-}"
if [ -z "$TAG" ]; then
  # Resolve the newest published release rather than defaulting to the rolling
  # `tdlib-latest` tag: that tag's libtdjson.so is kept current but its
  # libtgcalls_ohos.so lags the versioned releases, so it is NOT a safe default
  # now that both libraries are required.
  TAG="$(curl -fsSL "https://api.github.com/repos/$REPO/releases/latest" \
    | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)"
  if [ -z "$TAG" ]; then
    echo "ERROR: could not resolve the latest release tag (offline, or rate-limited)."
    echo "Pass one explicitly, e.g.:  bash scripts/fetch-libs.sh v1.2.2"
    exit 1
  fi
  echo "Latest release: $TAG"
fi

mkdir -p "$DEST"
for lib in $LIBS; do
  URL="https://github.com/$REPO/releases/download/$TAG/$lib"
  echo "Downloading $URL ..."
  if ! curl -fL "$URL" -o "$DEST/$lib"; then
    echo ""
    echo "ERROR: download of $lib failed at tag $TAG. Either that release does not"
    echo "carry this asset, or you are offline. Build from source instead:"
    echo "  scripts/build-tdlib.sh        (libtdjson.so)"
    echo "  scripts/build-tgcalls-ohos.sh (libtgcalls_ohos.so)"
    exit 1
  fi
  file "$DEST/$lib"
done

# Each artifact must advertise a SONAME equal to its packaged filename so it
# matches libentry.so's DT_NEEDED. A mismatch makes the native bridge fail to
# load *silently* at runtime — no error, the app just behaves as if TDLib is
# absent (see build-tdlib.sh). Verify, and self-heal when patchelf is present.
if command -v patchelf >/dev/null 2>&1; then
  for lib in $LIBS; do
    SONAME="$(patchelf --print-soname "$DEST/$lib" 2>/dev/null || echo '')"
    if [ "$SONAME" != "$lib" ]; then
      echo "WARN: $lib advertises SONAME '$SONAME', normalizing to $lib"
      patchelf --set-soname "$lib" "$DEST/$lib"
    fi
  done
else
  echo ""
  echo "NOTE: patchelf not found; skipping the SONAME check. To verify manually"
  echo "      you can use the NDK's own reader (no extra install needed):"
  echo "        \"\$OHOS_NDK_HOME/native/llvm/bin/llvm-readelf\" -d <lib> | grep SONAME"
  echo "      If a SONAME does not match its filename, fix it with:"
  echo "        patchelf --set-soname <lib> \"$DEST/<lib>\""
fi

echo ""
echo "Done. $DEST now contains:"
for lib in $LIBS; do
  echo "  $lib"
done
