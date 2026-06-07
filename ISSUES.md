# Issues / Resolved Notes

## 1. TouchKIO Window Is Not Fullscreen

Observed runtime state:

```text
screen: 1920x1080
TouchKIO window: 1728x972 at 96,54
_NET_WM_STATE: _NET_WM_STATE_FOCUSED
_NET_WM_ALLOWED_ACTIONS includes: _NET_WM_ACTION_FULLSCREEN
```

Status:

- Addressed in `start_touchkio.sh` by waiting for the window, then applying geometry and fullscreen via `wmctrl`.

Acceptance criteria:

- Exactly one visible TouchKIO window.
- Geometry is `1920x1080` at `0,0`.
- `_NET_WM_STATE_FULLSCREEN` is present.
- State survives service restart.

## 2. Kiosk Does Auto-Reload After Stop

Status:

- Addressed in `touchkio.service` with `Restart=always` and `RestartSec=10`.

Acceptance criteria:

- If the TouchKIO process exits cleanly, systemd restarts it.
- If the process crashes, systemd restarts it.
- Restart is visible in `journalctl --user -u touchkio.service`.

## 3. Watchdog Reports Healthy For Bad Window State

Status:

- Addressed in `touchkio-watchdog.sh` with geometry checks, `_NET_WM_STATE_FULLSCREEN` validation, and bounded X11 calls.

Current watchdog checks:

- service active
- one visible window by class
- root process found
- process count nonzero
- RSS below threshold

Missing checks:

- fullscreen state
- exact window geometry
- bounded X11 command execution

Acceptance criteria:

- Watchdog reports non-fullscreen or wrong-geometry state as failed.
- Watchdog restarts service after repeated failed checks.
- Healthy logs include window id, geometry, fullscreen status, process count, and RSS.

## 4. Diagnostics Are Split

Status:

- Addressed in `touchkio-watchdog.sh` by logging to both `/home/sundeep/touchkio-watchdog.log` and stdout.

Acceptance criteria:

- Each watchdog health/failure message is written to the log file and stdout.
- `journalctl --user -u touchkio-watchdog.service` shows useful health details.
