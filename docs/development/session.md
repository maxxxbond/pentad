# Session actions and lock

The session actions live in the control center header: the lock button is one click away, and log out, restart and power off sit behind the power button, each with a confirmation. Locking asks systemd-logind to lock the active session (`loginctl lock-session`). Hypridle handles that signal and runs its `lock_cmd`, which for Pentad is `pentad lock`.

## The lock screen

`pentad lock` starts `quickshell/lock.qml`, a second Quickshell entry point next to `shell.qml`. It runs as its own process, so stopping, restarting or crashing the main shell never ends a lock, and the lock never reloads when files in the runtime change. It reads `theme.json`, `interface.json` and `wallpaper.json` from `$XDG_CONFIG_HOME/pentad` and writes nothing.

Each screen shows the wallpaper Pentad uses for that output (blurred and dimmed), the time and date, the user's initial or `~/.face`, and the password field. It shows nothing from the session behind it: no notifications, media, window titles or clipboard. Caps Lock and the active keyboard layout are shown when Hyprland and the keyboard LEDs report them. Sleep, restart and power off appear only when logind allows them without asking (`CanSuspend`/`CanReboot`/`CanPowerOff` answer `yes`); a button runs on a second press within two seconds, and the call never asks polkit, because its dialog would open under the lock.

The views are in `quickshell/features/lock/`; the rules for the PAM conversation and the power actions are in `quickshell/logic/lock-screen.mjs`, tested by `tests/quickshell/lock-screen.test.mjs`. The fixture `lock-screen` draws the surface in a plain window with a scripted stand-in for PAM; `lock-entrypoint` loads the real entry in the isolated compositor.

### Security rules

- **The lock fails closed.** It uses the `ext-session-lock-v1` protocol: if the process dies, the compositor keeps the session locked. The only way to unlock is a PAM conversation that ends in exactly `PamResult.Success`; every other result, an error and a timeout keep it locked.
- **No bypass switch.** The entry has no debug, preview or environment switch that turns the lock into a plain window. Development uses the fixtures.
- **PAM checks the account that owns the process**, never one named by `$USER`. The service is `login` from `/etc/pam.d`. Quickshell reads every include from the directory it is given, so a vendor-only copy in `/usr/lib/pam.d` would skip the administrator's policy; without `/etc/pam.d/login` the lock is not taken and hyprlock locks instead.
- **The typed password answers only the first hidden PAM prompt.** A visible prompt or a second secret prompt (a one-time code, an expired password) is shown to the user, who types the answer; Escape abandons it. The field is cleared when the check starts and the password is dropped as soon as PAM has it.
- **No clipboard.** Paste, copy and cut are ignored in the field, so a password left on the clipboard cannot be pasted by someone else, and a visible answer is never copied out.
- **PAM text is plain text.** Messages such as pam_faillock's "account locked" are shown as one line without markup, so the user learns why a correct password failed.
- **A stalled PAM module** (a fingerprint reader, a network login) is aborted after 30 seconds.
- **The launcher trusts only a confirmed lock.** Once the compositor confirms the lock, `lock.qml` writes `locked` to `$XDG_RUNTIME_DIR/pentad-lock.state`, and clears it when an unlock begins. `pentad lock` waits up to five seconds for it; a `qs` that never confirms (for example one that failed to load the entry and kept running without it) is killed. A later `pentad lock` keeps a running instance only while the file says `locked`, and replaces one that is unlocking or stuck.
- **A crash ends the process.** The lock runs without Quickshell's crash handler, which would otherwise relaunch it in place, possibly in a loop. A non-zero exit, a missing `lock.qml`, a lock that never confirms and an unknown argument in `lock_cmd` all make `pentad lock` start `hyprlock` when it is installed.

## First-time setup

Merge `quickshell/defaults/hypridle-pentad.conf` into your own `~/.config/hypr/hypridle.conf`: it sets `lock_cmd = pentad lock`, locks before sleep and uses `inhibit_sleep = 3`. Do not replace your existing listeners with it. With a development checkout, use `lock_cmd = /path/to/pentad/scripts/pentad lock --development`.

Settings → Power → Screen and sleep edits the display-off and suspend inactivity timers in that
file (respecting `XDG_CONFIG_HOME`). Locking alone does not turn off the displays: a separate DPMS
listener does that and wakes them on activity. The settings keep the lock timer and existing sleep
command intact; “Never” disables only the chosen listener. Restart hypridle or sign in again after
saving. Missing hypridle/configuration and unsupported rules are shown without changing the session.

Pentad's key bindings (`quickshell/defaults/hyprland-quickshell.lua`, included by `pentad setup`) set `misc:allow_session_lock_restore`, so that after a crash of the lock screen `pentad lock` can start hyprlock on the locked session instead of leaving only a TTY as the way back. Keep that option if you copy the bindings by hand.

hyprlock is the fallback. To give it Pentad's look, copy `quickshell/defaults/hyprlock-basic.conf` to `~/.config/hypr/hyprlock.conf`: an opaque background, PAM, time, date and keyboard layout.

Check by hand after setting it up: lock with Super+L or from the control center, unlock with a wrong and then a correct password, lock with two monitors, sleep and wake up.

`~/.config/pentad/session.json` (`quickshell/defaults/session.json`) holds options for the lock screen, such as `showMediaOnLock` and `showWeatherOnLock`. The lock screen does not read them yet; media and weather stay off it.

## Diagnostics

- `pentad doctor` names a missing `hypridle` or `hyprlock`, a missing `/etc/pam.d/login`, and a `hypridle.conf` without `lock_cmd`.
- If Super+L does nothing, check that hypridle is running and that its `lock_cmd` is `pentad lock`. `pentad lock` reports why it fell back on standard error.
- If a correct password keeps failing, read the message under the field: pam_faillock locks the account for a few minutes after repeated failures.
- Restart and power off in the control center are offered only when logind reports `CanReboot` and `CanPowerOff`. Pentad has no suspend or hibernate action there; sleep goes through hypridle and logind.

If the lock screen fails and the screen stays a solid colour, switch to a TTY (Ctrl+Alt+F3), log in as the same user and start hyprlock on the Wayland display of the session, for example `WAYLAND_DISPLAY=wayland-1 hyprlock` (the socket name is in `$XDG_RUNTIME_DIR`); with `misc:allow_session_lock_restore` it takes over the lock. Do not kill a running locker at random: killing it too early can leave the compositor's session lock unusable.
