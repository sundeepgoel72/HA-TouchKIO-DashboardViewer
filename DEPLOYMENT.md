# Deployment Runbook

## Backup First

Create a fresh backup directory:

```bash
BACKUP_DIR="/home/sundeep/codex-backups/touchkio-followup-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP_DIR"
```

Copy live files:

```bash
sudo cp /usr/local/bin/start_touchkio.sh "$BACKUP_DIR/start_touchkio.sh"
cp /home/sundeep/.config/kiosk-browser.conf "$BACKUP_DIR/kiosk-browser.conf"
cp /home/sundeep/touchkio-watchdog.sh "$BACKUP_DIR/touchkio-watchdog.sh"
cp /home/sundeep/switch-kiosk-browser.sh "$BACKUP_DIR/switch-kiosk-browser.sh"
cp /home/sundeep/kiosk-mode-benchmark.sh "$BACKUP_DIR/kiosk-mode-benchmark.sh"
cp /home/sundeep/.config/systemd/user/touchkio.service "$BACKUP_DIR/touchkio.service"
cp /home/sundeep/.config/systemd/user/touchkio-watchdog.service "$BACKUP_DIR/touchkio-watchdog.service"
cp /home/sundeep/.config/systemd/user/touchkio-watchdog.timer "$BACKUP_DIR/touchkio-watchdog.timer"
```

Record the backup path before deploying.

## Copy Changed Project Files To Live Paths

From project root:

```bash
cd /mnt/ssd/projects/HA-TouchKiosk
```

Copy only files that changed.

Launcher:

```bash
sudo cp start_touchkio.sh /usr/local/bin/start_touchkio.sh
sudo chmod 755 /usr/local/bin/start_touchkio.sh
```

Config:

```bash
cp kiosk-browser.example.conf /home/sundeep/.config/kiosk-browser.conf
```

Watchdog:

```bash
cp touchkio-watchdog.sh /home/sundeep/touchkio-watchdog.sh
chmod 755 /home/sundeep/touchkio-watchdog.sh
```

User systemd units:

```bash
cp touchkio.service /home/sundeep/.config/systemd/user/touchkio.service
cp touchkio-watchdog.service /home/sundeep/.config/systemd/user/touchkio-watchdog.service
cp touchkio-watchdog.timer /home/sundeep/.config/systemd/user/touchkio-watchdog.timer
```

## Reload And Restart

```bash
systemctl --user daemon-reload
systemctl --user reset-failed touchkio.service
systemctl --user restart touchkio.service
systemctl --user restart touchkio-watchdog.timer
```

## Validate

```bash
systemctl --user status touchkio.service touchkio-watchdog.timer --no-pager
journalctl --user -u touchkio.service -u touchkio-watchdog.service --since '15 minutes ago' --no-pager
tail -40 /home/sundeep/touchkio-watchdog.log
```

```bash
WIN_ID=$(DISPLAY=:0 XAUTHORITY=/var/run/lightdm/root/:0 xdotool search --onlyvisible --class touchkio | head -1)
DISPLAY=:0 XAUTHORITY=/var/run/lightdm/root/:0 xdotool getwindowname "$WIN_ID"
DISPLAY=:0 XAUTHORITY=/var/run/lightdm/root/:0 xdotool getwindowgeometry "$WIN_ID"
DISPLAY=:0 XAUTHORITY=/var/run/lightdm/root/:0 xprop -id "$WIN_ID" _NET_WM_STATE WM_CLASS WM_NAME
```

## Rollback

Replace changed files from `$BACKUP_DIR`, then:

```bash
systemctl --user daemon-reload
systemctl --user reset-failed touchkio.service
systemctl --user restart touchkio.service
systemctl --user restart touchkio-watchdog.timer
```
