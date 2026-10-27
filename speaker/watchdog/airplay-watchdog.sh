#!/bin/sh
# AirPlay watchdog for the standalone receiver in /data/opt/airplay.
# shairport-sync registers its AirPlay service in avahi only once, at start.
# If avahi restarts later, the service silently disappears from the network.
# Restart the stack when avahi is newer than shairport-sync or a daemon died.
LOG=/tmp/airplay-watchdog.log
AIRPLAY=/data/opt/airplay/airplay.sh

# process start time in clock ticks since boot (field 22 of /proc/PID/stat)
start_of() {
  pid=$(pidof "$1" | awk '{print $1}')
  [ -n "$pid" ] && awk '{print $22}' "/proc/$pid/stat" 2>/dev/null
}

log() { echo "$(date '+%F %T') $*" >> "$LOG"; }

SOLOIST=/data/opt/soloist/soloist.sh

log "started"
while :; do
  sleep 30
  # Soloist grows over hours and the speaker has no swap: restart it before
  # memory runs out (the whole speaker, Alice included, hangs when it does)
  # (~2-3 MB/min while playing). Below 40 MB restart it when nothing plays,
  # below 25 MB restart it anyway.
  avail=$(awk '/MemAvailable/ {print int($2 / 1024)}' /proc/meminfo)
  if [ -x "$SOLOIST" ] && [ "$avail" -lt 40 ]; then
    if [ "$avail" -lt 25 ] || ! /data/opt/soloist/bin/soloist ctl -w 127.0.0.1:9090 now 2>/dev/null | grep -q playing; then
      log "low memory (${avail} MB available): restarting soloist"
      $SOLOIST restart
    fi
  fi
  # Soloist, its voice bridge and audio loop: start whatever is not running
  if [ -x "$SOLOIST" ] && $SOLOIST status | grep -q stopped; then
    log "soloist: $($SOLOIST status | grep stopped | tr '\n' ' ')- starting"
    $SOLOIST start
  fi
  [ -x "$AIRPLAY" ] || continue
  a=$(start_of avahi-daemon)
  s=$(start_of shairport-sync)
  if [ -z "$a" ] || [ -z "$s" ]; then
    log "avahi or shairport-sync not running, restarting AirPlay"
    $AIRPLAY restart
  elif [ "$a" -gt "$s" ]; then
    log "avahi restarted after shairport-sync ($a > $s), restarting AirPlay"
    $AIRPLAY restart
  fi
done
