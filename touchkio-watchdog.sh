#!/bin/bash
set -euo pipefail

CONFIG=/home/sundeep/.config/kiosk-browser.conf
if [ -r "$CONFIG" ]; then
  # shellcheck disable=SC1090
  . "$CONFIG"
fi

export DISPLAY="${DISPLAY:-:0}"
export XAUTHORITY="${XAUTHORITY:-/var/run/lightdm/root/:0}"

STATE_DIR=/home/sundeep/.cache/touchkio-watchdog
FAIL_FILE="$STATE_DIR/fail-count"
LOCK_FILE="$STATE_DIR/lock"
LOG_FILE=/home/sundeep/touchkio-watchdog.log
KIOSK_BROWSER="${KIOSK_BROWSER:-touchkio}"
KIOSK_URL="${KIOSK_URL:-http://192.168.1.72:8123/rpi-touch/view-1}"
MAX_FAILS=2

mkdir -p "$STATE_DIR"

ts() { date --iso-8601=seconds; }
log() { echo "$(ts) mode=$KIOSK_BROWSER $*" >> "$LOG_FILE"; }

exec 9>"$LOCK_FILE"
if ! flock -n 9; then
  log "another watchdog instance is already running; exiting"
  exit 0
fi

fail_count() {
  if [ -s "$FAIL_FILE" ]; then
    cat "$FAIL_FILE"
  else
    echo 0
  fi
}

set_fail_count() { echo "$1" > "$FAIL_FILE"; }

case "$KIOSK_BROWSER" in
  touchkio)
    WINDOW_CLASS="${TOUCHKIO_WINDOW_CLASS:-touchkio}"
    MARKER="--user-data-dir=${TOUCHKIO_USER_DATA_DIR:-/home/sundeep/.touchkio1}"
    MAX_RSS_KB="${TOUCHKIO_MAX_RSS_KB:-2300000}"
    ;;
  chromium)
    WINDOW_CLASS="${CHROMIUM_WINDOW_CLASS:-chromium}"
    MARKER="--user-data-dir=${CHROMIUM_USER_DATA_DIR:-/home/sundeep/.chromium-kiosk-view1}"
    MAX_RSS_KB="${CHROMIUM_MAX_RSS_KB:-1800000}"
    ;;
  *)
    WINDOW_CLASS="$KIOSK_BROWSER"
    MARKER="$KIOSK_URL"
    MAX_RSS_KB=2300000
    ;;
esac

WINDOW_COUNT=$( (xdotool search --onlyvisible --class "$WINDOW_CLASS" 2>/dev/null || true) | wc -l | tr -d ' ')
if [ "$KIOSK_BROWSER" = "chromium" ] && [ "$WINDOW_COUNT" = "0" ]; then
  WINDOW_COUNT=$( (xdotool search --onlyvisible --class Chromium 2>/dev/null || true) | wc -l | tr -d ' ')
fi

read -r ROOT_PID MARKER_RSS_KB MARKER_PROC_COUNT <<EOF_METRICS
$(ps -eo pid=,rss=,args= | awk -v marker="$MARKER" -v url="$KIOSK_URL" '
  index($0, marker) {
    count += 1; rss += $2;
    if (root == "" && index($0, url)) root = $1;
  }
  END {print root, rss + 0, count + 0}
')
EOF_METRICS

if [ "$KIOSK_BROWSER" = "touchkio" ]; then
  TOTAL_RSS_KB=$(ps -C touchkio -o rss= 2>/dev/null | awk '{s+=$1; c+=1} END {print s+0}')
  PROC_COUNT=$(ps -C touchkio -o pid= 2>/dev/null | wc -l | tr -d ' ')
else
  TOTAL_RSS_KB="$MARKER_RSS_KB"
  PROC_COUNT="$MARKER_PROC_COUNT"
fi

REASON=""
if [ "$(systemctl --user is-active touchkio.service 2>/dev/null || true)" != "active" ]; then
  REASON="touchkio.service is not active"
elif [ "$WINDOW_COUNT" != "1" ]; then
  REASON="expected 1 visible $WINDOW_CLASS window, found $WINDOW_COUNT"
elif [ -z "${ROOT_PID:-}" ]; then
  REASON="root kiosk process for $KIOSK_URL not found"
elif [ "${PROC_COUNT:-0}" -eq 0 ]; then
  REASON="no kiosk processes found for marker $MARKER"
elif [ "${TOTAL_RSS_KB:-0}" -gt "$MAX_RSS_KB" ]; then
  REASON="kiosk RSS ${TOTAL_RSS_KB}KB exceeds ${MAX_RSS_KB}KB"
fi

if [ -z "$REASON" ]; then
  if [ "$(fail_count)" != "0" ]; then
    log "health recovered; resetting fail count"
  fi
  set_fail_count 0
  log "healthy window_count=$WINDOW_COUNT root_pid=$ROOT_PID proc_count=$PROC_COUNT total_rss_kb=$TOTAL_RSS_KB"
  exit 0
fi

COUNT=$(fail_count)
COUNT=$((COUNT + 1))
set_fail_count "$COUNT"
log "failed check $COUNT/$MAX_FAILS: $REASON; proc_count=${PROC_COUNT:-0} total_rss_kb=${TOTAL_RSS_KB:-0}"

if [ "$COUNT" -ge "$MAX_FAILS" ]; then
  log "restarting touchkio.service after $COUNT consecutive failed checks"
  systemctl --user restart touchkio.service
  set_fail_count 0
fi
