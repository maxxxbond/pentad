# Menu pointer behavior

The shared attached menu receives native pointer input on Hyprland and stays open
after the pointer enters its controls. A temporary corridor connects both upper
icon corners to both upper menu-body corners. Entering the body cancels the leave
timer; the corridor keeps a bounded lifetime.

## Design notes

**Interactive overlay window.** A `PopupWindow` becomes a tooltip when its native
focus grab is disabled in favor of the global manager, and native Hyprland
pointer input then does not reach it (the same scenario works on KWin). Enabling
both grabs dismisses the menu at once. `AttachedPopover` therefore uses an
interactive overlay `PanelWindow` with one shared focus owner and a standalone
fallback.

**Logical origins.** Layer surfaces do not provide reliable global Qt window
origins. Bar, SurfaceHost and menu content expose their logical origin for
pointer and anchor mapping. Quickshell scales the Ignore reservation sentinel
from -1 to -2 at 200%, and explicit Normal placement compensates for the owning
bar reservation. Menu content is a descendant of its hover field. Reopening resets
stale samples, mapping children protect their parent, and closing a tray menu
always removes its manager registration.

**Sampled safe region.** `MenuPointerIntent` uses the convex hull of the complete
source and target rectangles, expanded by a 4 px buffer; the same hull drives the
diagnostic overlay. While the root pointer-dismiss branch is active, it sends one
read-only Hyprland `j/cursorpos` request at a time, polling every 40 ms with a
150 ms timeout; each parsed sample is normalized once and shared with descendant
controllers. A fresh sample inside the hull has no close deadline. The first
sample outside starts a 350 ms grace period, re-entry cancels it, and a fresh
sample more than 80 px from the connected branch may dismiss early. Hover open
takes 180 ms. Initial anchor hover does not arm dismissal: only actually observed
movement or entry into the menu body does, so a stationary cursor does not close
a freshly opened menu. Tests cover this with synthetic points and never call a
live compositor.

**Tray menu height.** Height is computed from the model entries (30 px for a
normal row, 9 px for a separator): seven rows and four separators give 246 px of
content, and the attached-menu padding makes it 278 px. `AttachedPopover` also
requests a `QQuickWindow` frame after implicit size changes, retrying at most
eight times at 32 ms intervals, because the layer-shell runtime only schedules
polish for size requests and a pending native resize could otherwise leave the
window at a stale size. `TrayMenuLevel.traceLayout()` records the received
entries, row counts, labels, intrinsic list height, preferred and actual window
height and viewport height when menu diagnostics are enabled.

## Native checks

`scripts/test-menu-pointer-native.py` runs the checks in an isolated session.
Every invocation owns private compositor sockets, a private D-Bus, HOME/XDG
directories and fake services, and terminates and reaps its own processes. No
input or IPC reaches your desktop.

```sh
python3 scripts/test-menu-pointer-native.py --compositor hyprland --scale 1 --report /tmp/pentad-native-hyprland-1.json
python3 scripts/test-menu-pointer-native.py --compositor hyprland --scale 1.25 --report /tmp/pentad-native-hyprland-1.25.json
python3 scripts/test-menu-pointer-native.py --compositor hyprland --scale 2 --report /tmp/pentad-native-hyprland-2.json
python3 scripts/test-menu-pointer-native.py --compositor kwin --scale 1 --report /tmp/pentad-native-kwin.json
```

The runner exercises actual compositor pointer motion and clicks, hover beyond
the grace interval, leaving, reopening, disabled rows, nested submenus, leaf
activation, Escape, ordinary dropdowns, right-edge placement, passive focus
behavior, empty and asynchronously populated menus, wheel scrolling and focus
scrolling. A dropdown inside the production SurfaceHost receives hover and closes
independently of its parent. Hyprland also tests native outside-click dismissal
with pointer dismissal disabled; KWin lacks that Hyprland focus-grab check.
Escape uses native `wtype` on Hyprland and QtTest on KWin. Scale values are Qt
logical scaling on an 800×600 private output. Each report has adjacent `.log` and
`.png` artifacts.

A private Gio D-Bus StatusNotifierItem/DBusMenu provider tests the real
Quickshell native model over three open/close cycles with delayed `AboutToShow`
replies, including partial asynchronous content growing to an 11-row, 278 px menu,
reopening, and a cursor held still for 500 ms after each opening.

Existing fixtures run through the same runner with `--scenario tray-context-menu`,
`--scenario control-templates` and `--scenario popups`.

## Static and logic checks

- `node --test --test-isolation=none tests/quickshell/*.test.mjs`
- `node scripts/build-quickshell.mjs --output /tmp/pentad-menu-build`
- `qmllint -I quickshell` over the modified menu, SurfaceHost, PopupManager and fixture QML.
- Both native input drivers compile with `cc -Wall -Wextra -Werror` and their pkg-config dependencies.
- `python3 -m py_compile scripts/test-menu-pointer-native.py` and `git diff --check`.

## Known limits

Physical multi-output transitions, hotplug, mixed per-monitor compositor scaling
and additional third-party reserved panels are not verified. Negative output
coordinates are covered by logic tests. The native tests use production
components with fixture menu data, so a specific application's incomplete menu
opening has to be checked with that application.
