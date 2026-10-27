#!/bin/sh
# When Spotify (Soloist) starts playing during an AirPlay session, end the
# AirPlay session. The other direction is the AirPlay "begin" hook, which
# pauses Soloist (/data/opt/airplay/hooks.sh).
FLAG=/run/airplay/active
LOG=/tmp/airplay-guard.log

while :; do
  /data/opt/soloist/bin/soloist ctl -w 127.0.0.1:9090 trace 2>/dev/null |
  while read -r ts json; do
    case "$json" in
      *'"type":"playback_state","status":"playing"'*)
        [ -f "$FLAG" ] || continue
        # ignore events right after the AirPlay hook paused Soloist
        [ $(( $(date +%s) - $(date -r "$FLAG" +%s) )) -ge 3 ] || continue
        echo "$(date '+%F %T') Spotify started during AirPlay: ending AirPlay session" >> "$LOG"
        /data/opt/airplay/airplay.sh kick ;;
    esac
  done
  sleep 3
done
