# Aider Handover: TouchKIO Kiosk Fixes

## Project State

Repository directory:

```text
/mnt/ssd/projects/HA-TouchKiosk
```

GitHub repository:

```text
https://github.com/sundeepgoel72/HA-TouchKIO-DashboardViewer
```

Baseline:

```text
branch: master
tag: v0.2
commit: 1310c14
```

The current project root contains exact baseline copies of the active kiosk scripts and user systemd units. Make code changes in this project directory first, test them here, then deploy changed files to their live paths only after backup and validation.

The kiosk runtime is now intended to be config-driven instead of hardcoded. Real machine-specific config should live outside the repo in a local `~/.config` or `~/.nv` path, while Git only carries example files such as `*.example.conf` and example service templates. Keep the real config paths and any generated local config files in `.gitignore`.

## Target Host

```text
host: 192.168.1.176
hostname: 6-72-RpiTouch
user: sundeep
role: Raspberry Pi touchscreen kiosk for Home Assistant
dashboard URL: http://192.168.1.72:8123/rpi-touch/display
```

## Live File Mapping

Project file to live destination:

```text
start_touchkio.sh              -> /usr/local/bin/start_touchkio.sh
kiosk-browser.example.conf     -> /home/sundeep/.config/kiosk-browser.conf
touchkio-watchdog.sh           -> /home/sundeep/touchkio-watchdog.sh
switch-kiosk-browser.sh        -> /home/sundeep/switch-kiosk-browser.sh
kiosk-mode-benchmark.sh        -> /home/sundeep/kiosk-mode-benchmark.sh
touchkio.service               -> /home/sundeep/.config/systemd/user/touchkio.service
touchkio-watchdog.service      -> /home/sundeep/.config/systemd/user/touchkio-watchdog.service
touchkio-watchdog.timer        -> /home/sundeep/.config/systemd/user/touchkio-watchdog.timer
```

Planned config split for the refactor:

```text
kiosk-browser.example.conf      -> tracked in Git
kiosk-browser.conf             -> local only, ignored
any generated local config      -> local only, ignored
```

## Current Known Issues

1. TouchKIO is not fullscreen.
   - Runtime X11 inspection showed a visible TouchKIO window at `1728x972` positioned `96,54`.
   - The physical X11 screen is `1920x1080`.
   - `_NET_WM_STATE` did not include `_NET_WM_STATE_FULLSCREEN`.
   - `_NET_WM_ALLOWED_ACTIONS` includes `_NET_WM_ACTION_FULLSCREEN`, so X11 fullscreen enforcement is viable.

2. Kiosk does reliably reload when stopped.
   - `touchkio.service` uses `Restart=always`.
   - Clean TouchKIO exits restart under systemd.

3. Watchdog misses the bad fullscreen state.
   - `touchkio-watchdog.sh` checks visible window count, root process, process count, RSS, geometry, and fullscreen state.
   - X11 calls are bounded with short timeouts.
   - The watchdog logs health details to both the log file and the user journal.

4. Watchdog diagnostics are hard to read from systemd.
   - Useful health details are written only to `/home/sundeep/touchkio-watchdog.log`.
   - `journalctl --user -u touchkio-watchdog.service` only shows start/finish.

5. X11 probes are not bounded.
   - Watchdog uses `xdotool` directly.
   - Add short `timeout` wrappers to avoid timer jobs hanging on X11 problems.

6. Configuration is still too hardcoded.
   - Browser URL, window geometry, user-data-dir, and watchdog thresholds are still embedded in the current scripts and config flow.
   - Refactor the runtime to read those values from a config file outside the repo.
   - Track only example config files in Git.

## Fix Requirements

Make narrow changes only. Do not switch permanently to Chromium. Do not rewrite the kiosk model.

Required behavior:

1. `touchkio.service` restarts TouchKIO after both failed and clean exits.
2. TouchKIO becomes a real fullscreen X11 window after startup.
3. The watchdog detects missing, multiple, non-fullscreen, or wrong-geometry TouchKIO windows.
4. The watchdog restarts `touchkio.service` after repeated failed checks.
5. Watchdog health and failure messages are visible in both its log file and the user journal.
6. X11 checks have short timeouts.
7. Runtime config comes from local-only config files, not from repo-tracked machine-specific values.
8. Git contains only example config files, not the live local config.

Recommended implementation shape:

1. Update `touchkio.service`:
   - `Restart=always` is already in place.
   - Keep `RestartSec=10`.
   - Keep `systemd --user` ownership.

2. Update `start_touchkio.sh`:
   - Keep TouchKIO as the default path.
   - Replace direct `exec "$TOUCHKIO_BIN" ...` with a launched child process so the script can apply X11 fullscreen state after the window appears, then `wait` for TouchKIO.
   - Use `wmctrl` or `xdotool` to find the visible TouchKIO window by class.
   - Apply move/resize to `KIOSK_X`, `KIOSK_Y`, `KIOSK_WIDTH`, `KIOSK_HEIGHT`.
   - Apply `_NET_WM_STATE_FULLSCREEN`.
   - Keep the script running as the systemd main process until TouchKIO exits, and return TouchKIO's exit code.
   - Add configurable values in `kiosk-browser.conf` if needed, such as `TOUCHKIO_ENFORCE_FULLSCREEN=true` and `TOUCHKIO_FULLSCREEN_WAIT_SECONDS=20`.

3. Update `touchkio-watchdog.sh`:
   - Add helper functions for bounded X11 commands, for example `timeout 5 env DISPLAY=... XAUTHORITY=... xdotool ...`.
   - Detect exactly one visible TouchKIO window.
   - Read that window's geometry and require `1920x1080+0+0` based on config values.
   - Read `_NET_WM_STATE` and require `_NET_WM_STATE_FULLSCREEN`.
   - Log the window id, name, geometry, fullscreen state, process count, and RSS on healthy checks.
   - On failure, log the exact reason and restart after `MAX_FAILS`.
   - Emit log lines to stdout as well as `/home/sundeep/touchkio-watchdog.log`.

## Development Rules

1. First modify project files only.
2. Validate project scripts with `bash -n`.
3. Create a fresh live backup before copying anything to live paths.
4. Deploy only the files that changed.
5. Run `systemctl --user daemon-reload` after unit changes.
6. Restart and validate the user services.
7. Commit changes after successful local validation.
8. Push code changes and tag/release only after deployment validation.

## Commands To Start

```bash
cd /mnt/ssd/projects/HA-TouchKiosk
git status --short --branch
git log --oneline --decorate -3
bash -n start_touchkio.sh
bash -n touchkio-watchdog.sh
bash -n switch-kiosk-browser.sh
bash -n kiosk-mode-benchmark.sh
```

## Do Not Do

Do not:

- change Home Assistant dashboard config
- delete old backup directories
- disable unrelated services, cron jobs, or timers
- switch permanently to Chromium
- factory reset anything
- commit tokens, cookies, or Home Assistant secrets
- reboot without checking whether the display is actively being used
- commit live config files or private overrides
