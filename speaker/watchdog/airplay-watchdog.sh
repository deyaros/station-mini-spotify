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
