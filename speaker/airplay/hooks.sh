#!/bin/sh
# Shairport Sync session hooks: AirPlay and Spotify (Soloist) take turns.
# begin: pause Spotify, then mark the AirPlay session as active (the flag is
# what soloist's airplay-guard checks before kicking AirPlay off).
# end:   clear the flag.
FLAG=/run/airplay/active
case "$1" in
  begin)
    /data/opt/soloist/bin/soloist ctl -w 127.0.0.1:9090 pause >/dev/null 2>&1
    touch "$FLAG" ;;
  end)
    rm -f "$FLAG" ;;
esac
exit 0
