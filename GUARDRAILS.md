# Guardrails

1. Back up live files before deployment.
2. Make project changes first; deploy only after static tests pass.
3. Prefer narrow changes to the active failing layer.
4. Do not rewrite the whole kiosk setup unless evidence proves the current model cannot work.
5. Validate shell scripts with `bash -n`.
6. Use `systemd --user` as the main ownership model.
7. Do not disable unrelated cron jobs, services, or timers.
8. Do not change Home Assistant dashboard config unless explicitly asked.
9. Do not switch permanently from TouchKIO to Chromium unless explicitly asked.
10. Keep secrets and Home Assistant tokens out of Git.
11. Document every deployed change and validation result.
12. Ask before rebooting if the touchscreen may be in active use.
13. Keep live config outside the repo in local `~/.config` or `~/.nv` files.
14. Commit only example config files and add real local config files to `.gitignore`.

