#!/bin/bash
set -euo pipefail
export DISPLAY="${DISPLAY:-:0}"
export XAUTHORITY="${XAUTHORITY:-/var/run/lightdm/root/:0}"

WARMUP="${1:-90}"
SAMPLE_GAP="${2:-15}"
CONFIG=/home/sundeep/.config/kiosk-browser.conf
URL=$(awk -F= '/^KIOSK_URL=/{print $2}' "$CONFIG")

get_conf() { awk -F= -v key="$1" '$1==key {print $2}' "$CONFIG"; }

switch_mode() {
  /home/sundeep/switch-kiosk-browser.sh "$1" >/dev/null
  for _ in $(seq 1 30); do
    if systemctl --user is-active --quiet touchkio.service; then
      sleep 1
      return 0
    fi
    sleep 1
  done
  systemctl --user status touchkio.service --no-pager || true
  return 1
}

snapshot() {
  local mode="$1" marker window_class wc root rss count cpu
  if [ "$mode" = touchkio ]; then
    marker="--user-data-dir=$(get_conf TOUCHKIO_USER_DATA_DIR)"
    window_class="$(get_conf TOUCHKIO_WINDOW_CLASS)"
  else
    marker="--user-data-dir=$(get_conf CHROMIUM_USER_DATA_DIR)"
    window_class="$(get_conf CHROMIUM_WINDOW_CLASS)"
  fi
  wc=$( (xdotool search --onlyvisible --class "$window_class" 2>/dev/null || true) | wc -l | tr -d ' ')
  if [ "$mode" = chromium ] && [ "$wc" = 0 ]; then
    wc=$( (xdotool search --onlyvisible --class Chromium 2>/dev/null || true) | wc -l | tr -d ' ')
  fi
  if [ "$mode" = touchkio ]; then
    read -r root rss count cpu <<EOF_METRICS
$(ps -eo pid=,rss=,pcpu=,comm=,args= | awk -v url="$URL" '
  $4 == "touchkio" {
    count += 1; rss += $2; cpu += $3;
    if (root == "" && index($0, url)) root = $1;
  }
  END {printf "%s %d %d %.1f\n", root, rss + 0, count + 0, cpu + 0}
')
EOF_METRICS
  else
    read -r root rss count cpu <<EOF_METRICS
$(ps -eo pid=,rss=,pcpu=,args= | awk -v marker="$marker" -v url="$URL" '
  index($0, marker) {
    count += 1; rss += $2; cpu += $3;
    if (root == "" && index($0, url)) root = $1;
  }
  END {printf "%s %d %d %.1f\n", root, rss + 0, count + 0, cpu + 0}
')
EOF_METRICS
  fi
  printf 'mode=%s window_count=%s root_pid=%s proc_count=%s total_rss_kb=%s total_pcpu=%s\n' "$mode" "$wc" "${root:-}" "${count:-0}" "${rss:-0}" "${cpu:-0}"
  ps -eo pid=,ppid=,pcpu=,rss=,comm=,args= | awk -v marker="$marker" 'index($0, marker) {print}' | sort -k3,3nr | head -12 | sed 's/^/  proc /'
}

for mode in touchkio chromium; do
  echo "===== $mode ====="
  switch_mode "$mode"
  echo "warmup_seconds=$WARMUP"
  sleep "$WARMUP"
  for i in 1 2 3; do
    echo "sample=$i"
    snapshot "$mode"
    [ "$i" = 3 ] || sleep "$SAMPLE_GAP"
  done
  free | awk '/^Mem:/ {print "mem_used_kb=" $3 " mem_available_kb=" $7} /^Swap:/ {print "swap_used_kb=" $3}'
  vcgencmd measure_temp 2>/dev/null || true
  vcgencmd get_throttled 2>/dev/null || true
  echo
done
