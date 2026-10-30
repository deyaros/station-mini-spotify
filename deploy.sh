#!/bin/sh
# Install Spotify Soloist + Alice voice bridge + standalone AirPlay on a rooted
# Yandex Station Mini 2 over adb.
# usage: ./deploy.sh SPEAKER_IP soloist_release_arm64.tar.gz keys.env
# needs: adb, curl, python3, bsdtar, xz, git, docker; on the speaker: root adb
# and yse/Entware (https://hackalice.me/start/packages/)
set -eu
IP=${1:?usage: $0 SPEAKER_IP SOLOIST_TARBALL KEYS_FILE}
TARBALL=${2:?soloist_release_arm64.tar.gz from developer.spotify.com}
KEYS=${3:?keys.env, see keys.env.example}
HERE=$(cd "$(dirname "$0")" && pwd)
DEV=$IP:5555
A="adb -s $DEV"

STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT
mkdir -p "$STAGE/soloist/bin" "$STAGE/airplay/etc"

echo "== fetching components"
"$HERE/tools/fetch-debian-libs.sh" "$STAGE/soloist"
"$HERE/tools/build-apulse.sh" "$STAGE/soloist"
"$HERE/tools/fetch-bridge.sh" "$STAGE/soloist"
"$HERE/tools/fetch-airplay.sh" "$STAGE/airplay"
"$HERE/tools/build-alice-tools.sh" "$STAGE/media"
mkdir -p "$STAGE/tar"
tar -xzf "$TARBALL" -C "$STAGE/tar"
mv "$STAGE/tar/soloist" "$STAGE/soloist/bin/soloist.bin"

echo "== speaker"
adb connect "$DEV" >/dev/null
$A shell 'id -u' | grep -qx 0 || { echo "no root adb on $DEV" >&2; exit 1; }
$A shell '[ -x /data/opt/bin/yse ]' || { echo "install yse first (hackalice.me/start/packages)" >&2; exit 1; }
$A shell '/data/opt/bin/yse install ent:curl ent:jq ent:gawk' >/dev/null

$A shell '/data/opt/soloist/soloist.sh stop 2>/dev/null; /data/opt/airplay/airplay.sh stop 2>/dev/null; mkdir -p /data/opt/soloist/etc /data/opt/soloist/data /data/opt/airplay/etc /data/opt/bin /data/opt/media/bin; chmod 700 /data/opt/soloist/etc'
$A push "$STAGE/media/bin" /data/opt/media/ >/dev/null
$A push "$HERE/speaker/media/duck.sh" /data/opt/media/duck.sh >/dev/null
$A push "$HERE/speaker/media/asoundrc" /data/opt/media/.asoundrc >/dev/null
$A push "$STAGE/soloist/." /data/opt/soloist/ >/dev/null
$A push "$HERE/speaker/soloist/soloist-wrapper" /data/opt/soloist/bin/soloist >/dev/null
$A push "$HERE/speaker/soloist/soloist.sh" /data/opt/soloist/soloist.sh >/dev/null
$A push "$HERE/speaker/soloist/airplay-guard.sh" /data/opt/soloist/scripts/airplay-guard.sh >/dev/null
$A push "$KEYS" /data/opt/soloist/etc/keys.env >/dev/null
$A push "$STAGE/airplay/bin" /data/opt/airplay/ >/dev/null
for f in shairport.conf dbus.conf avahi.conf; do
  $A push "$HERE/speaker/airplay/$f" /data/opt/airplay/etc/$f >/dev/null
done
$A push "$HERE/speaker/airplay/airplay.sh" /data/opt/airplay/airplay.sh >/dev/null
$A push "$HERE/speaker/airplay/hooks.sh" /data/opt/airplay/hooks.sh >/dev/null
$A push "$HERE/speaker/watchdog/airplay-watchdog.sh" /data/opt/bin/airplay-watchdog.sh >/dev/null
for f in speaker/soloist/S99soloist speaker/airplay/S99airplay speaker/watchdog/S99zzairplaywd; do
  $A push "$HERE/$f" "/data/opt/${f##*/}" >/dev/null
done

$A shell '
  set -e
  chmod 600 /data/opt/soloist/etc/keys.env
  chmod 755 /data/opt/soloist/bin/* /data/opt/soloist/lib64/ld-linux-aarch64.so.1 \
            /data/opt/soloist/soloist.sh /data/opt/soloist/scripts/*.sh \
            /data/opt/airplay/bin/* /data/opt/airplay/*.sh /data/opt/bin/airplay-watchdog.sh \
            /data/opt/media/bin/* /data/opt/media/duck.sh
  mount -o remount,rw /
  for f in S99soloist S99airplay S99zzairplaywd; do
    cp /data/opt/$f /etc/init.d/$f && chmod 755 /etc/init.d/$f
  done
  sync; mount -o remount,ro /
'
$A shell '/etc/init.d/S99airplay start; /etc/init.d/S99soloist start; /etc/init.d/S99zzairplaywd start' >/dev/null
sleep 8
$A shell '/data/opt/airplay/airplay.sh status; /data/opt/soloist/soloist.sh status'
echo "== done: pick the speaker in the Spotify app once to log in"
