#!/bin/sh
# Build the two small Alice IPC tools as static arm64 binaries into OUT/bin:
#  - alice-text: prints Alice's state changes (used by speaker/media/duck.sh).
#    Source: hackalice wiki, contrib/station2-media/build/voice/alice-text.c,
#    (c) Yandex Station Extended contributors, CC BY 4.0 — fetched, not copied.
#  - alice-say: makes Alice say a text (tools/alice-say.c, this repository).
# usage: tools/build-alice-tools.sh OUT        (needs curl, docker)
set -eu
OUT=${1:?usage: $0 OUT}
COMMIT=71dca7f42cb4bc8b9e6b11a9ba9d6e37f647e90c
URL=https://raw.githubusercontent.com/Marker284/yandex-station-extended/$COMMIT/contrib/station2-media/build/voice/alice-text.c
HERE=$(cd "$(dirname "$0")" && pwd)

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
curl -fsSL -o "$WORK/alice-text.c" "$URL"
cp "$HERE/alice-say.c" "$WORK/"
docker run --rm -v "$WORK:/w" debian:trixie sh -c '
  set -e
  apt-get update -qq >/dev/null
  DEBIAN_FRONTEND=noninteractive apt-get install -y -qq gcc-aarch64-linux-gnu libc6-dev-arm64-cross >/dev/null
  for t in alice-text alice-say; do
    aarch64-linux-gnu-gcc -O2 -Wall -Wextra -static -o /w/$t /w/$t.c
    aarch64-linux-gnu-strip /w/$t
  done
  chmod -R a+rwX /w'
mkdir -p "$OUT/bin"
cp "$WORK/alice-text" "$WORK/alice-say" "$OUT/bin/"
echo "alice-text and alice-say in $OUT/bin"
