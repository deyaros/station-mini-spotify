#!/bin/sh
# Official Spotify Soloist (arm64) on the 32-bit Yandex Station Mini 2, plus
# soloist-bridge (Alice voice commands and the center button -> Soloist).
#
# Audio path: Soloist -> apulse -> ALSA loopback card -> 32-bit arecord|aplay
# -> system "default" PCM (dmix). Soloist's libasound is 64-bit, and a 64-bit
# client in the shared dmix locks out every 32-bit one (Alice, AirPlay), so
# only the speaker's own 32-bit aplay touches dmix. The loopback card keeps
# real-time pacing for Soloist.
# usage: soloist.sh start|stop|restart|status
D=/data/opt/soloist
RUN=/run/soloist
LOG=/tmp/soloist.log
BRIDGE_LOG=/tmp/soloist-bridge.log
LOOP_LOG=/tmp/soloist-loop.log
NAME="Станция Мини"
FMT="-f S16_LE -r 44100 -c 2 -t raw -B 200000"

alive() { [ -f "$RUN/$1.pid" ] && kill -0 "$(cat "$RUN/$1.pid")" 2>/dev/null; }

start() {
  mkdir -p "$RUN" /tmp/soloist-cache "$D/data"
  # Soloist's own cache limit can't go below 100 MB, but the speaker has ~240 MB
  # of RAM and Soloist alone takes ~80-100 MB: give the cache a tiny tmpfs, so
  # Soloist quickly falls back to streaming mode (works fine) instead of
  # keeping tracks in RAM.
  grep -q " /tmp/soloist-cache " /proc/mounts || mount -t tmpfs -o size=4m tmpfs /tmp/soloist-cache
  # without swap, the default 1.8 MB reserve lets the system thrash for minutes
  # before the OOM killer acts; a bigger reserve makes it act sooner
  [ "$(cat /proc/sys/vm/min_free_kbytes)" -ge 8192 ] || echo 8192 > /proc/sys/vm/min_free_kbytes
  grep -q Loopback /proc/asound/cards || modprobe snd-aloop pcm_substreams=1
  if ! alive loop; then
    # aplay goes to "media" (/data/opt/media/.asoundrc): default + the Media Duck volume
    start-stop-daemon -S -b -m -p "$RUN/loop.pid" -x /bin/sh -- -c \
      "exec arecord -q -D hw:Loopback,1,0 $FMT | HOME=/data/opt/media aplay -q -D media $FMT >>$LOOP_LOG 2>&1"
  fi
  if ! alive soloist; then
    . "$D/etc/keys.env"
    [ -n "$SPAK" ] || { echo "no SPAK in $D/etc/keys.env" >&2; return 1; }
    # glibc.pthread.rseq=0: kernel 4.9 has no rseq and logs every attempt
    HOME=$D/data \
    APULSE_PLAYBACK_DEVICE=plughw:Loopback,0,0 \
    GLIBC_TUNABLES=glibc.pthread.rseq=0 \
    SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt \
    start-stop-daemon -S -b -m -p "$RUN/soloist.pid" -x /bin/sh -- \
      -c 'exec "$@" >>'"$LOG"' 2>&1' sh \
      "$D/lib64/ld-linux-aarch64.so.1" --library-path "$D/lib64" "$D/bin/soloist.bin" \
      -n "$NAME" -k "$SPAK" -D "$D/data" -C /tmp/soloist-cache -z 100 \
      -w 127.0.0.1:9090 -i 50
    # if memory runs out, Soloist goes first, not Alice
    sleep 1
    alive soloist && echo 1000 > "/proc/$(cat "$RUN/soloist.pid")/oom_score_adj"
  fi
  if ! alive bridge && [ -x "$D/bin/soloist-bridge" ]; then
    start-stop-daemon -S -b -m -p "$RUN/bridge.pid" -x /bin/sh -- \
      -c 'cd / && exec "$@" >>'"$BRIDGE_LOG"' 2>&1' sh "$D/bin/soloist-bridge"
  fi
  # Spotify starting during an AirPlay session ends that session
  if ! alive guard && [ -x "$D/scripts/airplay-guard.sh" ]; then
    start-stop-daemon -S -b -m -p "$RUN/guard.pid" -x "$D/scripts/airplay-guard.sh"
  fi
  # music gets quieter while Alice listens
  if ! alive duck && [ -x /data/opt/media/duck.sh ]; then
    start-stop-daemon -S -b -m -p "$RUN/duck.pid" -x /data/opt/media/duck.sh
  fi
}

stop() {
  # guard: its "soloist ctl trace" child exits by itself once Soloist is gone
  for n in duck guard bridge soloist; do
    alive $n && kill "$(cat "$RUN/$n.pid")" 2>/dev/null
    rm -f "$RUN/$n.pid"
  done
  killall alice-text 2>/dev/null
  amixer -q -c 0 sset "Media Duck" 100% 2>/dev/null
  # the loop is "sh -c 'arecord | aplay'": stop the pipeline's members too
  if alive loop; then
    kill "$(cat "$RUN/loop.pid")" 2>/dev/null
    killall arecord 2>/dev/null
    for p in $(ps | grep "[a]play -q -D default" | awk '{print $1}'); do kill "$p"; done
  fi
  rm -f "$RUN/loop.pid"
}

case "$1" in
  start)   start ;;
  stop)    stop ;;
  restart) stop; sleep 1; start ;;
  status)
    for n in soloist bridge loop guard duck; do
      if alive $n; then echo "$n: running ($(cat "$RUN/$n.pid"))"; else echo "$n: stopped"; fi
    done ;;
  *) echo "usage: $0 start|stop|restart|status"; exit 1 ;;
esac
