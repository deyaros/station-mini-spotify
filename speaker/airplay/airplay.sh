#!/bin/sh
# Standalone AirPlay 2 receiver: private D-Bus -> Avahi -> NQPTP -> Shairport Sync.
# usage: airplay.sh start|stop|restart|kick|status
D=/data/opt/airplay
RUN=/run/airplay
LOG=/tmp/airplay.log
export DBUS_SYSTEM_BUS_ADDRESS=unix:path=$RUN/bus
export LD_LIBRARY_PATH=/system/vendor/quasar:/system/vendor/quasar/libs
export PATH=/bin:/sbin:/usr/bin:/usr/sbin

running() { pidof "$1" >/dev/null 2>&1; }

# start a daemon in its own session (immune to SIGHUP when the calling shell
# exits) and remember its pid
spawn() {
  name=$1; shift
  start-stop-daemon -S -b -m -p "$RUN/$name.pid" -x /bin/sh -- -c 'exec "$@" >>'"$LOG"' 2>&1' sh "$@"
}

stop_one() {
  [ -f "$RUN/$1.pid" ] && kill "$(cat "$RUN/$1.pid")" 2>/dev/null
  rm -f "$RUN/$1.pid"
}

start() {
  mkdir -p "$RUN"
  [ -f "$RUN/shairport.pid" ] && kill -0 "$(cat "$RUN/shairport.pid")" 2>/dev/null && return 0
  echo "$(date '+%F %T') starting" >> "$LOG"
  spawn dbus "$D/bin/dbus-daemon" --nofork --nopidfile --config-file "$D/etc/dbus.conf"
  i=0; while [ ! -S "$RUN/bus" ] && [ $i -lt 20 ]; do sleep 0.5; i=$((i+1)); done
  spawn avahi "$D/bin/avahi-daemon" --no-drop-root --no-rlimits --file "$D/etc/avahi.conf"
  sleep 2
  spawn nqptp "$D/bin/nqptp"
  # shairport-sync exits ("NQPTP ... does not seem to be initialised") if it
  # starts before nqptp has set up its shared memory: wait, then retry
  i=0; while ! ls /dev/shm/nqptp* >/dev/null 2>&1 && [ $i -lt 20 ]; do sleep 0.5; i=$((i+1)); done
  for try in 1 2 3; do
    sleep 2
    spawn shairport "$D/bin/shairport-sync" -c "$D/etc/shairport.conf"
    sleep 3
    kill -0 "$(cat "$RUN/shairport.pid")" 2>/dev/null && return 0
    echo "$(date '+%F %T') shairport-sync exited, retry $try" >> "$LOG"
  done
}

stop() {
  for n in shairport nqptp avahi dbus; do stop_one $n; done
  sleep 1
  rm -f "$RUN/bus"
}

case "$1" in
  start)   start ;;
  stop)    stop ;;
  restart) stop; start ;;
  kick)
    # end the current AirPlay session (this build has no "disconnect sender"
    # command): restart shairport-sync only, avahi and nqptp stay up
    stop_one shairport
    rm -f "$RUN/active"
    sleep 1
    spawn shairport "$D/bin/shairport-sync" -c "$D/etc/shairport.conf" ;;
  status)
    for n in shairport nqptp avahi dbus; do
      if [ -f "$RUN/$n.pid" ] && kill -0 "$(cat "$RUN/$n.pid")" 2>/dev/null; then
        echo "$n: running ($(cat "$RUN/$n.pid"))"
      else
        echo "$n: stopped"
      fi
    done ;;
  *) echo "usage: $0 start|stop|restart|status"; exit 1 ;;
esac
