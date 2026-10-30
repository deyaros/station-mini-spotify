#!/bin/sh
# Build alice-text (prints Alice's state changes from her local IPC; used by
# speaker/media/duck.sh) as a static arm64 binary into OUT/bin.
# Source: hackalice wiki, contrib/station2-media/build/voice/alice-text.c,
# (c) Yandex Station Extended contributors, CC BY 4.0 — fetched, not copied.
# usage: tools/build-alice-text.sh OUT        (needs curl, docker)
set -eu
OUT=${1:?usage: $0 OUT}
COMMIT=71dca7f42cb4bc8b9e6b11a9ba9d6e37f647e90c
URL=https://raw.githubusercontent.com/Marker284/yandex-station-extended/$COMMIT/contrib/station2-media/build/voice/alice-text.c

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
curl -fsSL -o "$WORK/alice-text.c" "$URL"
docker run --rm -v "$WORK:/w" debian:trixie sh -c '
  set -e
  apt-get update -qq >/dev/null
  DEBIAN_FRONTEND=noninteractive apt-get install -y -qq gcc-aarch64-linux-gnu libc6-dev-arm64-cross >/dev/null
  aarch64-linux-gnu-gcc -O2 -Wall -Wextra -static -o /w/alice-text /w/alice-text.c
  aarch64-linux-gnu-strip /w/alice-text
  chmod -R a+rwX /w'
mkdir -p "$OUT/bin"
cp "$WORK/alice-text" "$OUT/bin/"
echo "alice-text in $OUT/bin"
