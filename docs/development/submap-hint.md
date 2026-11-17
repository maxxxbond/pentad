# Submap hint

When Hyprland enters a submap, a key mode such as `resize`, Pentad shows a small strip near the bottom centre of the focused output that lists the binds of that submap: the keys and what they do. It appears about a quarter of a second after the submap starts, so a submap that is entered and left at once (a leader key) shows nothing, and disappears as soon as the submap is reset. A submap whose only bind is its way out, the usual pass-through mode for games, virtual machines and remote desktops, has nothing to hint at and shows no strip. The strip never takes the keyboard and lets every click through, because you are in the middle of using the submap. While no submap is active there is no window and nothing runs.

## What it shows

A muted caption names the submap, "Submap: resize" or "Режим клавіш: resize". The name comes from your config; it is shown as plain text and clipped to 40 characters.

Below it are the submap's binds in config order, each with a keycap per key and its description. The keycaps are the cheatsheet's sculpted `PentadKeycap` ([controls](controls.md#keycap)), raised on their lip over the strip's surface and neutral: the strip has no group hues. Keys get the same names as in the [cheatsheet](cheatsheet.md#what-it-shows): `Escape` is `Esc`, `Right` is `→`, and the Super key shows the logo the cheatsheet's `superKeyLogo` setting picks, the Pentad mark by default, or the word with `text` ([the Super key](cheatsheet.md#the-super-key)). A bind without a description reads as its dispatcher and argument in a muted colour, such as `resizeactive 20 0` or `submap reset`. Lua binds without a description have nothing to read, so they are left out unless the submap has no other binds; then they read "Lua function without a description".

At most 12 binds are listed; "+N" at the right of the caption counts the rest, and the cheatsheet lists them all. The binds flow into one column up to 4 binds, two up to 8 and three above, top to bottom and then left to right, with fewer columns when the output is too narrow for columns of 160 px. The strip is as wide as its content needs, at most 720 px and never wider than the output minus 32 px.

When Pentad does not know the submap's binds (they have not been read yet, the read failed, or the submap has none), the strip shows just the caption.

Descriptions make the strip readable. In `hyprland.conf`:

```ini
bind = SUPER CTRL, R, submap, resize
submap = resize
bindd = , Right, Grow to the right, resizeactive, 20 0
bindd = , Left, Shrink from the right, resizeactive, -20 0
bindd = , Escape, Leave, submap, reset
submap = reset
```

Lua binds take the `description` option, as described for the [cheatsheet](cheatsheet.md#naming-groups-in-your-config).

## Where it appears

The strip sits 32 px above the bottom edge of the output that had focus when the submap started, on the overlay layer with the namespace `pentad-submap-hint`, so a `layerrule` can address it. It reserves no space; a bottom bar from another program that reserves an exclusive zone lifts the strip above itself. It fades and rises in briefly, instantly with reduced motion, and disappears at once.

It gives way to the cheatsheet, which lists the submaps itself, and to a screenshot; when the cheatsheet closes or the screenshot ends while the submap is still active, it comes back. If its output goes away, it stays hidden until the next submap starts. There is no setting to turn it off.

## When it reads the bindings

`services/SubmapState.qml` (`services.submap`) follows Hyprland's `submap>>NAME` event through Quickshell's `Hyprland.rawEvent`; an empty name, which Hyprland sends on a reset, means no submap is active. Preview mode never subscribes. Safe mode still listens, since the event only reports.

The binds come from the cheatsheet's reader, `services/Keybinds.qml`. It runs `hyprctl binds -j` (an argument list, no shell) once when a submap becomes active, and again when Hyprland reports `configreloaded` while one is active. Switching from one submap straight to another reads nothing new, since the list holds every submap. The last list stays in memory, so the next submap shows its binds at once while they are read again. Nothing runs while no submap is active and the cheatsheet is closed. The limits and failure reasons are those of the [cheatsheet](cheatsheet.md#when-it-reads-the-bindings); on a failure the strip shows the caption only.

## Files

| File | Role |
| --- | --- |
| `quickshell/logic/keybind-hints.mjs` | The submap name as plain text, the rows to show, the "+N" count, the columns; tested by `tests/quickshell/keybind-hints.test.mjs` |
| `quickshell/services/SubmapState.qml` | `services.submap`: `name` of the active submap, `''` when none is |
| `quickshell/services/Keybinds.qml` | Runs hyprctl; shared with the cheatsheet, active while the cheatsheet is open or a submap is active |
| `quickshell/features/keyhint/SubmapHintView.qml` | The strip's content; its keycaps are `components/PentadKeycap.qml`, the Super key's logos are in `assets/icons/keys/` |
| `quickshell/shell/SubmapHintHost.qml` | The layer-shell overlay, created only while a submap is active and nothing hides it |

## Verification

```sh
timeout 120 node --test tests/quickshell/keybind-hints.test.mjs
timeout 300 node scripts/test-quickshell-headless.mjs --scenario submap-hint --report /tmp/pentad-submap-hint.json
timeout 300 node scripts/test-quickshell-headless.mjs --scenario submap-hint --report /tmp/pentad-submap-hint-light.json --appearance light --scale 2 --reduced-motion
```

The `submap-hint` fixture sets the submap name on the state service directly and checks: no window and no read while no submap is active; the real `Services` container wiring `services.submap` to the reader; the window's layer, namespace, missing keyboard focus, empty input region and reserved space; the strip's place at the bottom centre; the caption and rows of the preview sample's `resize` submap and that its keycaps are the shared `PentadKeycap`; Ukrainian; an unknown submap showing only the caption; the reset; the cheatsheet and a screenshot hiding it and its return; that it never registers with the popup manager, whose focus grab would get in the way; 12 of 14 binds in three columns with "+2" and a Lua bind left out; markup in a name shown as text; and a submap with Super binds whose Super keycaps show the Pentad logo, then the word when the controller's `superKeyLogo` is `text`. It writes `<report>.png`, `<report>.png.uk.png`, `<report>.png.empty.png`, `<report>.png.overflow.png` and `<report>.png.logo.png`.

The headless run has no Hyprland, so it does not cover the `submap>>` event itself, nor that clicks reach the window underneath: it checks the empty input region the compositor is given, not where the compositor delivers a click.
