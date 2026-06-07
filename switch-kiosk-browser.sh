#!/bin/bash
set -euo pipefail
MODE="${1:-}"
if [ "$MODE" != "touchkio" ] && [ "$MODE" != "chromium" ]; then
  echo "Usage: $0 touchkio|chromium" >&2
  exit 64
fi
CONFIG=/home/sundeep/.config/kiosk-browser.conf
if [ ! -f "$CONFIG" ]; then
  echo "Missing $CONFIG" >&2
  exit 1
fi
sed -i "s/^KIOSK_BROWSER=.*/KIOSK_BROWSER=$MODE/" "$CONFIG"
systemctl --user reset-failed touchkio.service >/dev/null 2>&1 || true
systemctl --user restart touchkio.service
mkdir -p /home/sundeep/.cache/touchkio-watchdog
echo 0 > /home/sundeep/.cache/touchkio-watchdog/fail-count
printf 'Switched kiosk mode to %s\n' "$MODE"
