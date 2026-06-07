# Test Plan

Run tests in this order.

## Static Tests

```bash
cd /mnt/ssd/projects/HA-TouchKiosk
bash -n start_touchkio.sh
bash -n touchkio-watchdog.sh
bash -n switch-kiosk-browser.sh
bash -n kiosk-mode-benchmark.sh
```

If unit files changed:

```bash
systemd-analyze --user verify touchkio.service touchkio-watchdog.service touchkio-watchdog.timer
```

If `systemd-analyze --user verify` is not useful on this host, continue with `daemon-reload` validation after backup/deploy.

## Pre-Deploy Runtime Inspection

```bash
systemctl --user status touchkio.service touchkio-watchdog.service touchkio-watchdog.timer --no-pager
systemctl --user list-timers --all | grep -E 'touchkio|NEXT|LEFT' || true
journalctl --user -u touchkio.service -u touchkio-watchdog.service --since '2 hours ago' --no-pager
tail -80 /home/sundeep/touchkio-watchdog.log
```

```bash
WIN_ID=$(DISPLAY=:0 XAUTHORITY=/var/run/lightdm/root/:0 xdotool search --onlyvisible --class touchkio | head -1)
DISPLAY=:0 XAUTHORITY=/var/run/lightdm/root/:0 xdotool getwindowname "$WIN_ID"
DISPLAY=:0 XAUTHORITY=/var/run/lightdm/root/:0 xdotool getwindowgeometry "$WIN_ID"
DISPLAY=:0 XAUTHORITY=/var/run/lightdm/root/:0 xprop -root _NET_ACTIVE_WINDOW 2>&1 || true
DISPLAY=:0 XAUTHORITY=/var/run/lightdm/root/:0 xprop -id "$WIN_ID" _NET_WM_STATE WM_CLASS WM_NAME _NET_WM_ALLOWED_ACTIONS 2>&1 || true
```

## Deploy Validation

After copying changed files to live paths:

```bash
sudo chmod 755 /usr/local/bin/start_touchkio.sh
chmod 755 /home/sundeep/touchkio-watchdog.sh /home/sundeep/switch-kiosk-browser.sh /home/sundeep/kiosk-mode-benchmark.sh
bash -n /usr/local/bin/start_touchkio.sh
bash -n /home/sundeep/touchkio-watchdog.sh
systemctl --user daemon-reload
systemctl --user restart touchkio.service
systemctl --user restart touchkio-watchdog.timer
```

Confirm service:

```bash
systemctl --user status touchkio.service touchkio-watchdog.timer --no-pager
journalctl --user -u touchkio.service --since '10 minutes ago' --no-pager
```

Confirm fullscreen:

```bash
WIN_ID=$(DISPLAY=:0 XAUTHORITY=/var/run/lightdm/root/:0 xdotool search --onlyvisible --class touchkio | head -1)
DISPLAY=:0 XAUTHORITY=/var/run/lightdm/root/:0 xdotool getwindowname "$WIN_ID"
DISPLAY=:0 XAUTHORITY=/var/run/lightdm/root/:0 xdotool getwindowgeometry "$WIN_ID"
DISPLAY=:0 XAUTHORITY=/var/run/lightdm/root/:0 xprop -id "$WIN_ID" _NET_WM_STATE WM_CLASS WM_NAME 2>&1 || true
```

Expected:

```text
Geometry: 1920x1080
Position: 0,0
_NET_WM_STATE_FULLSCREEN present
```

## Watchdog Healthy Test

Run once manually:

```bash
/home/sundeep/touchkio-watchdog.sh
tail -20 /home/sundeep/touchkio-watchdog.log
journalctl --user -u touchkio-watchdog.service --since '5 minutes ago' --no-pager
```

Expected:

- exit code `0`
- healthy line includes geometry and fullscreen state

## Controlled Restart Tests

Clean process exit behavior:

```bash
ROOT_PID=$(pgrep -fo '/usr/bin/touchkio .*--web-url')
kill -TERM "$ROOT_PID"
sleep 20
systemctl --user status touchkio.service --no-pager
```

Expected:

- service is active again
- journal shows restart

Watchdog failure behavior:

```bash
DISPLAY=:0 XAUTHORITY=/var/run/lightdm/root/:0 wmctrl -r :ACTIVE: -b remove,fullscreen 2>&1 || true
/home/sundeep/touchkio-watchdog.sh
/home/sundeep/touchkio-watchdog.sh
systemctl --user status touchkio.service --no-pager
tail -40 /home/sundeep/touchkio-watchdog.log
```

Expected:

- first run records failed check
- second run restarts `touchkio.service`
- fail count resets after restart/healthy state

## Optional Reboot Test

Ask before rebooting if the display may be in use.

```bash
sudo reboot
```

After reconnect:

```bash
systemctl --user status touchkio.service touchkio-watchdog.timer --no-pager
WIN_ID=$(DISPLAY=:0 XAUTHORITY=/var/run/lightdm/root/:0 xdotool search --onlyvisible --class touchkio | head -1)
DISPLAY=:0 XAUTHORITY=/var/run/lightdm/root/:0 xdotool getwindowgeometry "$WIN_ID"
```
