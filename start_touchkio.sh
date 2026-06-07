#!/bin/bash
set -euo pipefail

CONFIG=/home/sundeep/.config/kiosk-browser.conf
if [ -r "$CONFIG" ]; then
  # shellcheck disable=SC1090
  . "$CONFIG"
fi

export DISPLAY="${DISPLAY:-:0}"
export XAUTHORITY="${XAUTHORITY:-/var/run/lightdm/root/:0}"

KIOSK_BROWSER="${KIOSK_BROWSER:-touchkio}"
KIOSK_URL="${KIOSK_URL:-http://192.168.1.72:8123/rpi-touch/display}"
KIOSK_WIDTH="${KIOSK_WIDTH:-1920}"
KIOSK_HEIGHT="${KIOSK_HEIGHT:-1080}"
KIOSK_X="${KIOSK_X:-0}"
KIOSK_Y="${KIOSK_Y:-0}"
KIOSK_ZOOM="${KIOSK_ZOOM:-1.0}"

# Configurable fullscreen enforcement for TouchKIO
TOUCHKIO_ENFORCE_FULLSCREEN="${TOUCHKIO_ENFORCE_FULLSCREEN:-true}"
TOUCHKIO_FULLSCREEN_WAIT_SECONDS="${TOUCHKIO_FULLSCREEN_WAIT_SECONDS:-20}"

case "$KIOSK_BROWSER" in
  touchkio)
    TOUCHKIO_BIN="${TOUCHKIO_BIN:-/usr/bin/touchkio}"
    TOUCHKIO_USER_DATA_DIR="${TOUCHKIO_USER_DATA_DIR:-/home/sundeep/.touchkio1}"
    TOUCHKIO_WEB_WIDGET="${TOUCHKIO_WEB_WIDGET:-false}"
    TOUCHKIO_WINDOW_CLASS="${TOUCHKIO_WINDOW_CLASS:-touchkio}"
    
    # Launch TouchKIO in background so we can apply window management
    "$TOUCHKIO_BIN" \
      --web-url="$KIOSK_URL" \
      --user-data-dir="$TOUCHKIO_USER_DATA_DIR" \
      --window-x="$KIOSK_X" --window-y="$KIOSK_Y" \
      --window-width="$KIOSK_WIDTH" --window-height="$KIOSK_HEIGHT" \
      --web-zoom="$KIOSK_ZOOM" \
      --web-widget="$TOUCHKIO_WEB_WIDGET" &
    
    TOUCHKIO_PID=$!
    
    # Enforce fullscreen and proper geometry if enabled
    if [ "$TOUCHKIO_ENFORCE_FULLSCREEN" = "true" ]; then
      echo "Waiting for TouchKIO window to appear..."
      WINDOW_ID=""
      for i in $(seq 1 $TOUCHKIO_FULLSCREEN_WAIT_SECONDS); do
        WINDOW_ID=$(timeout 5 xdotool search --onlyvisible --class "$TOUCHKIO_WINDOW_CLASS" 2>/dev/null | head -n 1 || true)
        if [ -n "$WINDOW_ID" ]; then
          break
        fi
        sleep 1
      done
      
      if [ -n "$WINDOW_ID" ]; then
        echo "Found TouchKIO window: $WINDOW_ID"
        # Move and resize window to proper dimensions
        timeout 5 xdotool windowmove "$WINDOW_ID" "$KIOSK_X" "$KIOSK_Y" 2>/dev/null || true
        timeout 5 xdotool windowsize "$WINDOW_ID" "$KIOSK_WIDTH" "$KIOSK_HEIGHT" 2>/dev/null || true
        # Set fullscreen state
        timeout 5 xdotool windowstate --add _NET_WM_STATE_FULLSCREEN "$WINDOW_ID" 2>/dev/null || true
        echo "Applied fullscreen and geometry to TouchKIO window"
      else
        echo "Warning: Could not find TouchKIO window after $TOUCHKIO_FULLSCREEN_WAIT_SECONDS seconds"
      fi
    fi
    
    # Wait for TouchKIO process to complete and return its exit code
    wait "$TOUCHKIO_PID"
    exit $?
    ;;
  chromium)
    CHROMIUM_BIN="${CHROMIUM_BIN:-auto}"
    if [ "$CHROMIUM_BIN" = "auto" ]; then
      CHROMIUM_BIN=$(command -v chromium-browser || command -v chromium || true)
    fi
    if [ -z "$CHROMIUM_BIN" ] || [ ! -x "$CHROMIUM_BIN" ]; then
      echo "Chromium binary not found" >&2
      exit 127
    fi
    CHROMIUM_USER_DATA_DIR="${CHROMIUM_USER_DATA_DIR:-/home/sundeep/.chromium-kiosk-view1}"
    CHROMIUM_REMOTE_DEBUGGING_PORT="${CHROMIUM_REMOTE_DEBUGGING_PORT:-9222}"
    mkdir -p "$CHROMIUM_USER_DATA_DIR"

    debug_flags=()
    if [ "$CHROMIUM_REMOTE_DEBUGGING_PORT" != "0" ]; then
      debug_flags=(--remote-debugging-address=127.0.0.1 --remote-debugging-port="$CHROMIUM_REMOTE_DEBUGGING_PORT")
    fi

    exec "$CHROMIUM_BIN" \
      --kiosk "$KIOSK_URL" \
      --user-data-dir="$CHROMIUM_USER_DATA_DIR" \
      --window-position="$KIOSK_X,$KIOSK_Y" \
      --window-size="$KIOSK_WIDTH,$KIOSK_HEIGHT" \
      --force-device-scale-factor="$KIOSK_ZOOM" \
      --no-first-run \
      --disable-first-run-ui \
      --disable-session-crashed-bubble \
      --disable-infobars \
      --disable-translate \
      --autoplay-policy=no-user-gesture-required \
      --check-for-update-interval=31536000 \
      "${debug_flags[@]}"
    ;;
  *)
    echo "Unsupported KIOSK_BROWSER=$KIOSK_BROWSER (use touchkio or chromium)" >&2
    exit 64
    ;;
esac
