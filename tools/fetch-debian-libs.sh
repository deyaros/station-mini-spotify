#!/bin/sh
# Download the Debian 13 (trixie) arm64 libraries that the official Soloist
# binary and apulse need, verify them against Debian's package index and put
# the shared objects into OUT/lib64.
# usage: tools/fetch-debian-libs.sh OUT
set -eu
OUT=${1:?usage: $0 OUT}
MIRROR=https://deb.debian.org/debian
PKGS="libc6 libgcc-s1 libatomic1 libasound2t64 libglib2.0-0t64 libpcre2-8-0 apulse"

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$OUT/lib64"

curl -fsSL -o "$WORK/Packages.xz" "$MIRROR/dists/trixie/main/binary-arm64/Packages.xz"
xz -dc "$WORK/Packages.xz" | python3 -I -c '
import sys
want = set(sys.argv[1].split())
for blk in sys.stdin.read().split("\n\n"):
    f = dict(l.split(": ", 1) for l in blk.splitlines() if ": " in l and not l.startswith(" "))
    if f.get("Package") in want:
        print(f["Package"], f["Filename"], f["SHA256"])
' "$PKGS" > "$WORK/list"

while read -r pkg fpath sha; do
  deb="$WORK/${fpath##*/}"
  curl -fsSL -o "$deb" "$MIRROR/$fpath"
  echo "$sha  $deb" | shasum -a 256 -c - >/dev/null
  mkdir -p "$WORK/x/$pkg"
  (cd "$WORK/x/$pkg" && bsdtar -xf "$deb" && bsdtar -xf data.tar.*)
  echo "ok $pkg"
done < "$WORK/list"

L=usr/lib/aarch64-linux-gnu
for f in ld-linux-aarch64.so.1 libc.so.6 libm.so.6 libdl.so.2 libpthread.so.0 librt.so.1 libresolv.so.2; do
  cp -L "$WORK/x/libc6/$L/$f" "$OUT/lib64/"
done
cp -L "$WORK/x/libgcc-s1/$L/libgcc_s.so.1" \
      "$WORK/x/libatomic1/$L/libatomic.so.1" \
      "$WORK/x/libasound2t64/$L/libasound.so.2" \
      "$WORK/x/libglib2.0-0t64/$L/libglib-2.0.so.0" \
      "$WORK/x/libpcre2-8-0/$L/libpcre2-8.so.0" \
      "$WORK/x/apulse/$L/apulse/libpulse.so.0" \
      "$WORK/x/apulse/$L/apulse/libpulse-simple.so.0" "$OUT/lib64/"
echo "libraries in $OUT/lib64"
