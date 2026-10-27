#!/bin/sh
# Download the AirPlay 2 add-on of spotiya (Shairport Sync, NQPTP, Avahi and a
# private D-Bus built for the 32-bit Mini 1/2 userspace), verify it and put
# the binaries into OUT/bin. Only these binaries are used, not spotiya itself.
# usage: tools/fetch-airplay.sh OUT
set -eu
OUT=${1:?usage: $0 OUT}
REL=https://github.com/klockky/spotiya/releases/download/v0.9.4
ASSET=spotiya-airplay2-armv7.tar.gz

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
cd "$WORK"
curl -fsSL -o "$ASSET" "$REL/$ASSET"
curl -fsSL -o SUMS "$REL/AIRPLAY_SHA256SUMS"
grep " $ASSET\$" SUMS | shasum -a 256 -c -
tar -xzf "$ASSET"

mkdir -p "$OUT/bin"
for b in shairport-sync nqptp avahi-daemon dbus-daemon; do
  f=$(find . -type f -name "$b" | head -1)
  [ -n "$f" ] || { echo "$b not found in $ASSET" >&2; exit 1; }
  cp "$f" "$OUT/bin/"
done
chmod 755 "$OUT/bin/"*
echo "AirPlay binaries in $OUT/bin"
