#!/bin/sh
# Build apulse (MIT) for arm64 with patches/apulse-flush.patch and put
# libpulse.so.0 / libpulse-simple.so.0 into OUT/lib64, replacing Debian's.
# Stock apulse ignores flush and keeps playing its ~1 s buffer after a pause,
# so every track skip started with the tail of the previous track.
# usage: tools/build-apulse.sh OUT        (needs git, docker)
set -eu
OUT=${1:?usage: $0 OUT}
REPO=https://github.com/i-rinat/apulse.git
COMMIT=5d654cecd18474b4e0d885e774bc41fcbbc9818b
HERE=$(cd "$(dirname "$0")/.." && pwd)

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
git clone -q "$REPO" "$WORK/apulse"
git -C "$WORK/apulse" checkout -q "$COMMIT"
git -C "$WORK/apulse" apply "$HERE/patches/apulse-flush.patch"

# cross-compile against Debian 13 arm64, the same glibc/glib as in lib64
docker run --rm -v "$WORK:/w" debian:trixie sh -c '
  set -e
  dpkg --add-architecture arm64
  apt-get update -qq >/dev/null
  DEBIAN_FRONTEND=noninteractive apt-get install -y -qq crossbuild-essential-arm64 \
    cmake pkg-config libglib2.0-dev:arm64 libasound2-dev:arm64 >/dev/null
  mkdir -p /w/build && cd /w/build
  PKG_CONFIG_LIBDIR=/usr/lib/aarch64-linux-gnu/pkgconfig:/usr/share/pkgconfig \
    cmake ../apulse -DCMAKE_C_COMPILER=aarch64-linux-gnu-gcc -DCMAKE_BUILD_TYPE=Release >/dev/null
  make -j4 >/dev/null
  aarch64-linux-gnu-strip libpulse.so.0 libpulse-simple.so.0
  chmod -R a+rwX /w'
mkdir -p "$OUT/lib64"
cp "$WORK/build/libpulse.so.0" "$WORK/build/libpulse-simple.so.0" "$OUT/lib64/"
echo "patched apulse in $OUT/lib64"
