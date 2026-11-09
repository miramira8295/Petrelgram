#!/bin/bash
# Deprecated: superseded by fetch-libs.sh.
#
# libentry.so links against BOTH libtdjson.so and libtgcalls_ohos.so, so a
# libtdjson-only fetch leaves the build dying in ninja. This shim forwards to
# fetch-libs.sh (which pulls both) so an old command line still produces a
# buildable tree.
set -eu
echo "NOTE: scripts/fetch-tdlib.sh is deprecated — forwarding to scripts/fetch-libs.sh,"
echo "      which fetches libtdjson.so AND libtgcalls_ohos.so (both are required)."
echo ""
exec bash "$(dirname "$0")/fetch-libs.sh" "$@"
