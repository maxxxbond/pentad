# Keybind cheatsheet

The cheatsheet is a centred card over the focused output that lists the key bindings Hyprland reports, grouped and searchable. It reads the bindings from Hyprland itself, so it shows what is actually bound, whether the config is `hyprland.lua` or `hyprland.conf`, including binds that other programs added at runtime.

## Opening it

| Way | What to use |
| --- | --- |
| Key | Super+/ in Pentad's bindings (`defaults/hyprland-quickshell.lua`), which bind the global shortcut `pentad:cheatsheet` |
| Traditional config | `bind = SUPER, SLASH, global, pentad:cheatsheet` |
| Command line | `pentad cheatsheet <open\|close\|toggle>` |
| IPC | `qs ipc call pentad request cheatsheet '{"action":"toggle"}'`; the reply carries `open` |

The shortcut and the command toggle. Opening the cheatsheet closes the bar menus, the overview and Spotlight.

## What it shows

Each row has a keycap per key on the left and the description on the right. Modifiers come first, always in the order Super, Ctrl, Alt, Shift (then Caps, Mod2, Mod3 and Mod5 when a bind uses them). Keys get the names printed on keycaps: `Slash` is `/`, `Return` is `Enter`, `Escape` is `Esc`, `Page_Down` is `PgDn`, arrows are arrows, `mouse:272`, `mouse:273` and `mouse:274` are `LMB`, `RMB` and `MMB`, `mouse_down` and `mouse_up` are `Scroll ↓` and `Scroll ↑`, media and brightness keys get short names such as `Vol +` and `Play`, and `code:49` is shown by the US legend of that physical key, `` ` ``. A keycode with no legend reads `Key NN`. A bind that repeats a held modifier, such as `SUPER + SUPER_L`, shows the modifier once, and the same keys with the same description (a press and a release bind, or the left and right Super) show once.

Groups come in this order:

1. Groups named in descriptions, in the order the config first uses them.
2. Binds without a group, by dispatcher: Workspaces (`workspace`, `movetoworkspace…`), Windows (`movefocus`, `movewindow`, `killactive`, `fullscreen`, `togglefloating`, `pin`, `swapwindow`, `resizeactive` and similar), Launch (`exec`) and Other. Without a description they read as the dispatcher and its argument, in a muted colour: `exec foot`, `workspace 3`.
3. One group per submap, "Submap: resize". Every bind inside a submap goes there.

The groups flow into three columns from 860 px of width, two from 560 px and one below; each group goes to the shortest column. The card is at most 920 px wide and 80 % of the screen tall; a longer list scrolls. A search that narrows the list does not shrink the card, so the search field stays where it is.

## Built-in references

The selector also offers Pentad, Neovim, Browser, Git, Terminal and kitty references. These ship with the shell and remain available when Hyprland cannot report bindings or the referenced application is not installed. They describe standard shortcuts, not detected application settings; custom mappings can differ.

Pentad covers the project's default global bindings and shortcuts inside its surfaces. Use the live Hyprland list to check actual global mappings. Neovim groups commands by mode and task. Browser covers common Linux Firefox and Chromium shortcuts. Git covers everyday repository commands, history and undo, and first-time setup; placeholders such as file and branch must be replaced before running a command, and `restore file` discards edits for good. Terminal describes Bash/Zsh Emacs editing bindings and common shell navigation; custom bindings and terminal emulators can differ. kitty lists the emulator's default `kitty_mod` (Ctrl+Shift) shortcuts for the clipboard, scrollback, windows, tabs, font size and hints; the prompt-jump and last-output rows need kitty's shell integration, and a customised `kitty.conf` can change any of them. These references do not execute commands or change application configuration.

Reference labels and descriptions are available in Ukrainian and English; search matches both languages. Changing the reference clears the search and returns the list to the top. “Show all” applies only to live Hyprland bindings.

## Naming groups in your config

Write the description as `Group: text`. The part before the first colon becomes the group, the rest the row's text. The colon needs a space after it, so `Open https://example.org` or `Alarm at 12:30` stay whole.

```ini
bindd = SUPER, Return, App: Terminal, exec, foot
bindd = SUPER, Q, Window: Close, killactive
```

```lua
hl.bind("SUPER + Slash", hl.dsp.global("pentad:cheatsheet"), { description = "Pentad: Keybind cheatsheet" })
```

## Lua binds

A bind that runs Lua reports the dispatcher `__lua` (Hyprland 0.55), `HL.Dispatcher(name)` or `function: 0x…` (0.56), with a line or function number as its argument, so its description is the only readable text. Lua binds with a description are shown like any other. Lua binds without one are hidden; the "Show all" switch in the header lists them too, as "Lua function without a description", which still tells you that the keys are taken. The switch keeps its position between openings; the search starts empty each time.

## Search and keys

The search field has the keyboard as soon as the card opens. Every word must match the row's description, a key name (`super`, `/`, or the raw name `slash`), the dispatcher or its argument, or the group's name in either language (`вікна` finds the Windows group).

| Key | Action |
| --- | --- |
| Typing | Filters the rows |
| ↑ / ↓, Page Up / Page Down | Scroll the list |
| Esc | Clears the search, then closes |

A press beside the card or a click on another output closes it, and it steps aside before a screenshot and when a bar menu opens.

## When it reads the bindings

`services/Keybinds.qml` runs `hyprctl binds -j` (an argument list, no shell) only on demand: each time the cheatsheet opens, and again when Hyprland reports `configreloaded` while it is open. Nothing runs while it is closed; the last list stays in memory, so a reopen shows it at once while it is read again. Safe mode still reads the list, since the command changes nothing. Preview mode uses the built-in sample in `logic/keybinds-sample.mjs` and never runs hyprctl.

If hyprctl is missing, exits with an error, takes longer than 5 seconds or prints more than 1 MiB, the card says "Hyprland is not answering" with the reason and a "Try again" button. A failed re-read keeps the list already shown. At most 2000 binds are read, and long descriptions and arguments are clipped.

## Files

| File | Role |
| --- | --- |
| `quickshell/logic/cheatsheets.mjs` | Built-in bilingual reference catalog; tested by `tests/quickshell/cheatsheets.test.mjs` |
| `quickshell/logic/keybinds.mjs` | Parsing, grouping, key names, search, column layout; tested by `tests/quickshell/keybinds.test.mjs` with `tests/fixtures/hyprland-binds.json` |
| `quickshell/services/Keybinds.qml` | Runs hyprctl and holds `state` (`loading`, `ready`, `unavailable` with a `reason`) |
| `quickshell/services/CheatsheetController.qml` | `services.cheatsheet`: `open`, `query`, `showAll`, `show()`, `hide()`, `toggle()` |
| `quickshell/features/cheatsheet/CheatsheetView.qml` | The card's content |
| `quickshell/shell/CheatsheetHost.qml` | The layer-shell overlay, created only while open; registered with `PopupManager` as `cheatsheet` |

## Verification

```sh
timeout 120 node --test tests/quickshell/keybinds.test.mjs
timeout 300 node scripts/test-quickshell-headless.mjs --scenario cheatsheet --report /tmp/pentad-cheatsheet.json
timeout 300 node scripts/test-quickshell-headless.mjs --scenario cheatsheet --report /tmp/pentad-cheatsheet-light.json --appearance light --scale 2
```

The `cheatsheet` fixture opens the overlay on the preview sample and checks groups, keycaps, three columns, "Show all", the search, "Nothing found", both languages, Esc, a press inside and beside the card, a screenshot and a bar menu. Separate adapters outside preview run other programs instead of hyprctl (a missing one, `false`, `printf`, `head`) to check the unavailable reasons, parsing of real process output, the size limit and a 240-bind list that scrolls. It writes `<report>.png`, `<report>.png.uk.png` and `<report>.png.unavailable.png`. HyprlandFocusGrab needs Hyprland, so closing on a click on another output is not covered by the headless run.
