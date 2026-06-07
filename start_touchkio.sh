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
KIOSK_URL="${KIOSK_URL:-http://192.168.1.72:8123/rpi-touch/view-1}"
KIOSK_WIDTH="${KIOSK_WIDTH:-1920}"
KIOSK_HEIGHT="${KIOSK_HEIGHT:-1080}"
KIOSK_X="${KIOSK_X:-0}"
KIOSK_Y="${KIOSK_Y:-0}"
KIOSK_ZOOM="${KIOSK_ZOOM:-1.0}"

case "$KIOSK_BROWSER" in
  touchkio)
    TOUCHKIO_BIN="${TOUCHKIO_BIN:-/usr/bin/touchkio}"
    TOUCHKIO_USER_DATA_DIR="${TOUCHKIO_USER_DATA_DIR:-/home/sundeep/.touchkio1}"
    TOUCHKIO_WEB_WIDGET="${TOUCHKIO_WEB_WIDGET:-false}"
    exec "$TOUCHKIO_BIN" \
      --web-url="$KIOSK_URL" \
      --user-data-dir="$TOUCHKIO_USER_DATA_DIR" \
      --window-x="$KIOSK_X" --window-y="$KIOSK_Y" \
      --window-width="$KIOSK_WIDTH" --window-height="$KIOSK_HEIGHT" \
      --web-zoom="$KIOSK_ZOOM" \
      --web-widget="$TOUCHKIO_WEB_WIDGET"
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
