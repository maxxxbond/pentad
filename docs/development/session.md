# Session actions and lock

The session actions live in the control center header: the lock button is one click away, and log out, restart and power off sit behind the power button, each with a confirmation. Locking asks systemd-logind to lock the active session (`loginctl lock-session`). Hypridle must handle that signal and start hyprlock. Pentad has no CLI command or global shortcut for these actions.

## First-time setup

Merge `quickshell/defaults/hypridle-pentad.conf` into your own `~/.config/hypr/hypridle.conf`. The fragment sets `hyprlock` as the lock handler and uses `inhibit_sleep = 3`. Do not replace your existing listeners with it.

Copy `quickshell/defaults/hyprlock-basic.conf` to `~/.config/hypr/hyprlock.conf`. hyprlock reads that path automatically; the fallback has an opaque background, PAM, time, date, keyboard layout, a weather snapshot and the current MPRIS track. Without weather data or a player label, those fields stay empty.

Copy `quickshell/defaults/session.json` to `~/.config/pentad/session.json`. The optional lock-screen elements are hidden by default. To enable them, configure:

```json
{
  "schemaVersion": 1,
  "showMediaOnLock": true,
  "showWeatherOnLock": true,
  "preferredPlayerId": "",
  "weatherLocation": {
    "label": "Berlin",
    "latitude": 52.52,
    "longitude": 13.405
  },
  "fingerprint": false
}
```

Fingerprint needs a configured `fprintd` and a matching PAM profile. Normal password entry stays available. Pentad does not write a PAM profile and never hands the password to a widget.

Restart the shell after changing `session.json`, then check by hand: lock from the control center, returning with a correct and a wrong password, sleep and wake-up. The configuration fragment is not installed automatically, so that your other Hyprland and hypridle rules stay intact.

## Diagnostics

- Check `hyprlock --version`, `hypridle --version` and `/etc/pam.d/hyprlock`.
- If the lock request fails, check that hypridle is running and has `lock_cmd = hyprlock`.
- Restart and power off are offered only when logind reports `CanReboot` and `CanPowerOff`. Pentad has no suspend or hibernate action; sleep goes through hypridle and logind. The lock callback arrives through `on_lock_cmd`; a running process or a returned D-Bus call does not by itself confirm the lock.
- Weather uses the latest Open-Meteo data and refreshes every 15 minutes. With no location or no network, the widget shows an offline or empty state; password authentication does not depend on it.
- `playerctl` runs with a timeout, and metadata is Pango-escaped. If MPRIS or `playerctl` is missing, the text is hidden.

If the locker fails, do not kill another process named hyprlock at random. Check the active lock and the compositor before any recovery; killing the locker too early can leave the compositor's session lock unusable.
