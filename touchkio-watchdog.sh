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
KIOSK_URL="${KIOSK_URL:-http://192.168.1.72:8123/rpi-touch/display}"
KIOSK_WIDTH="${KIOSK_WIDTH:-1920}"
KIOSK_HEIGHT="${KIOSK_HEIGHT:-1080}"
KIOSK_X="${KIOSK_X:-0}"
KIOSK_Y="${KIOSK_Y:-0}"
MAX_FAILS=2

mkdir -p "$STATE_DIR"

ts() { date --iso-8601=seconds; }
log() {
  local msg="$(ts) mode=$KIOSK_BROWSER $*"
  echo "$msg" >> "$LOG_FILE"
  # Also send to stdout so it appears in systemd journal
  echo "$msg"
}

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

# Use timeout for X11 commands to prevent hanging
timeout_xdotool() {
  timeout 5 env DISPLAY="$DISPLAY" XAUTHORITY="$XAUTHORITY" xdotool "$@" 2>/dev/null || true
}

timeout_xprop() {
  timeout 5 env DISPLAY="$DISPLAY" XAUTHORITY="$XAUTHORITY" xprop "$@" 2>/dev/null || true
}

WINDOW_COUNT=$(timeout_xdotool search --onlyvisible --class "$WINDOW_CLASS" | wc -l | tr -d ' ')
if [ "$KIOSK_BROWSER" = "chromium" ] && [ "$WINDOW_COUNT" = "0" ]; then
  WINDOW_COUNT=$(timeout_xdotool search --onlyvisible --class Chromium | wc -l | tr -d ' ')
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
WINDOW_ID=""
WINDOW_NAME=""
WINDOW_FULLSCREEN="unknown"
WINDOW_GEOMETRY="unknown"
if [ "$(systemctl --user is-active touchkio.service 2>/dev/null || true)" != "active" ]; then
  REASON="touchkio.service is not active"
elif [ "$WINDOW_COUNT" != "1" ]; then
  REASON="expected 1 visible $WINDOW_CLASS window, found $WINDOW_COUNT"
else
  # Get the window ID for detailed checks
  WINDOW_ID=$(timeout_xdotool search --onlyvisible --class "$WINDOW_CLASS" | head -n 1)
  if [ -n "$WINDOW_ID" ]; then
    WINDOW_NAME=$(timeout_xdotool getwindowname "$WINDOW_ID" | head -n 1)
    # Check window geometry
    WINDOW_GEOM=$(timeout_xdotool getwindowgeometry --shell "$WINDOW_ID" 2>/dev/null || echo "WIDTH=0;HEIGHT=0;X=0;Y=0")
    eval "$WINDOW_GEOM"
    WINDOW_GEOMETRY="${WIDTH}x${HEIGHT}+${X}+${Y}"

    WINDOW_STATES=$(timeout_xprop -id "$WINDOW_ID" _NET_WM_STATE)
    if echo "$WINDOW_STATES" | grep -q "_NET_WM_STATE_FULLSCREEN"; then
      WINDOW_FULLSCREEN="present"
    else
      WINDOW_FULLSCREEN="absent"
    fi

    if [ "$WIDTH" != "$KIOSK_WIDTH" ] || [ "$HEIGHT" != "$KIOSK_HEIGHT" ] || [ "$X" != "$KIOSK_X" ] || [ "$Y" != "$KIOSK_Y" ]; then
      REASON="window geometry ${WIDTH}x${HEIGHT}+${X}+${Y} does not match expected ${KIOSK_WIDTH}x${KIOSK_HEIGHT}+${KIOSK_X}+${KIOSK_Y}"
    elif [ "$WINDOW_FULLSCREEN" != "present" ]; then
      REASON="window is not in fullscreen state"
    fi
  else
    REASON="could not get window ID for visible $WINDOW_CLASS window"
  fi
fi

if [ -z "$REASON" ] && [ -z "${ROOT_PID:-}" ]; then
  REASON="root kiosk process for $KIOSK_URL not found"
elif [ -z "$REASON" ] && [ "${PROC_COUNT:-0}" -eq 0 ]; then
  REASON="no kiosk processes found for marker $MARKER"
elif [ -z "$REASON" ] && [ "${TOTAL_RSS_KB:-0}" -gt "$MAX_RSS_KB" ]; then
  REASON="kiosk RSS ${TOTAL_RSS_KB}KB exceeds ${MAX_RSS_KB}KB"
fi

if [ -z "$REASON" ]; then
  if [ "$(fail_count)" != "0" ]; then
    log "health recovered; resetting fail count"
  fi
  set_fail_count 0
  log "healthy window_count=$WINDOW_COUNT window_id=${WINDOW_ID:-unknown} window_name=${WINDOW_NAME:-unknown} window_geometry=$WINDOW_GEOMETRY fullscreen=$WINDOW_FULLSCREEN root_pid=$ROOT_PID proc_count=$PROC_COUNT total_rss_kb=$TOTAL_RSS_KB"
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
