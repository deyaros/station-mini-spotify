#!/bin/sh
# Lower Spotify and AirPlay while Alice is listening, so a voice command isn't
# drowned by the music. alice-text (from the hackalice wiki, CC BY 4.0) prints
# "@state N" on every change of Alice's state: 1 = listening, 0 = idle.
D=/data/opt/media
MARK=/tmp/media-duck
LEVEL=25%           # of the -30..0 dB "Media Duck" scale, about -22 dB
MAX_SECONDS=15      # safety net in case "idle" never comes

level() { amixer -q -c 0 sset "Media Duck" "$1" 2>/dev/null; }

duck_off() {
  rm -f "$MARK"
  level 100%
}

duck_on() {
  mark=$(cut -d' ' -f1 /proc/uptime)
  echo "$mark" > "$MARK"
  level "$LEVEL"
  ( sleep "$MAX_SECONDS"; [ "$(cat "$MARK" 2>/dev/null)" = "$mark" ] && duck_off ) &
}

duck_off
while :; do
  "$D/bin/alice-text" | while read -r line; do
    case "$line" in
      "@state 1") duck_on ;;
      "@state 0") [ -f "$MARK" ] && duck_off ;;
    esac
  done
  sleep 2
done
