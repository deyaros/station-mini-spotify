#!/bin/sh
# Fetch soloist-bridge and its helper scripts from Horohi/soloist-station-lite
# at a pinned commit (that repository has no license, so its code is not part
# of this one), apply our patch to the search script and build the bridge as a
# static aarch64 binary in a throwaway Alpine container.
# usage: tools/fetch-bridge.sh OUT        (needs git, docker)
set -eu
OUT=${1:?usage: $0 OUT}
REPO=https://github.com/Horohi/soloist-station-lite.git
COMMIT=b02e066661681791ca445f17a31bc96fd718323e
HERE=$(cd "$(dirname "$0")/.." && pwd)

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
git clone -q "$REPO" "$WORK/src"
git -C "$WORK/src" checkout -q "$COMMIT"
(cd "$WORK/src" && patch -p1 < "$HERE/speaker/soloist/search_and_play.patch")

mkdir -p "$OUT/bin" "$OUT/scripts"
cp "$WORK/src/scripts/search_and_play.sh" "$WORK/src/scripts/toggle.sh" "$OUT/scripts/"

docker run --rm -v "$WORK/src/src:/src" alpine:3.20 sh -c '
  apk add -q clang lld llvm >/dev/null &&
  clang --target=aarch64-linux-gnu -fuse-ld=lld -static -nostdlib \
        -fno-stack-protector -fno-builtin -O2 \
        -o /src/soloist-bridge /src/soloist-bridge.c &&
  llvm-strip -s /src/soloist-bridge'
cp "$WORK/src/src/soloist-bridge" "$OUT/bin/"
chmod 755 "$OUT/bin/soloist-bridge" "$OUT/scripts/"*.sh
echo "bridge and scripts in $OUT"
