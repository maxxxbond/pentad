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

From the top: the title with the number of rows shown, the list or keyboard switch, "Show all" and the close button; the sheet selector; the search; a row of filter chips; in the list view the "Key shortcuts" strip; then the groups. Each group is its own quiet card at `Metrics.radiusCard`, its raised fill faintly tinted (6 %) with the group's hue, with its heading inside, set at the section size (16) in demibold and in the hue.

Each row reads like a line of a contents page: a keycap per key on the left, a quiet dotted leader, and the description against the right edge. The keycaps are the shared sculpted `PentadKeycap` ([controls](controls.md#keycap)): a face lighter than the card over a darker 2 px lip, so they stand raised in both themes. The last keycap of a row, the main key, carries the group's hue as its legend colour and a light tint of its face. The leader is one line of dots on a 6 px grid shared by the whole card, so the dots of neighbouring rows line up; it ends a gap before the description and disappears when fewer than four dots fit. A description too long for its row elides and shows in full in a hint on hover. Modifiers come first, always in the order Super, Ctrl, Alt, Shift (then Caps, Mod2, Mod3 and Mod5 when a bind uses them). Keys get the names printed on keycaps: `Slash` is `/`, `Return` is `Enter`, `Escape` is `Esc`, `Page_Down` is `PgDn`, arrows are arrows, `mouse:272`, `mouse:273` and `mouse:274` are `LMB`, `RMB` and `MMB`, `mouse_down` and `mouse_up` are `Scroll ↓` and `Scroll ↑`, media and brightness keys get short names such as `Vol +` and `Play`, and `code:49` is shown by the US legend of that physical key, `` ` ``. A keycode with no legend reads `Key NN`. A bind that repeats a held modifier, such as `SUPER + SUPER_L`, shows the modifier once, and the same keys with the same description (a press and a release bind, or the left and right Super) show once.

Groups come in this order:

1. Groups named in descriptions, in the order the config first uses them.
2. Binds without a group, by dispatcher: Workspaces (`workspace`, `movetoworkspace…`), Windows (`movefocus`, `movewindow`, `killactive`, `fullscreen`, `togglefloating`, `pin`, `swapwindow`, `resizeactive` and similar), Launch (`exec`) and Other. Without a description they read as the dispatcher and its argument, in a muted colour: `exec foot`, `workspace 3`.
3. One group per submap, "Submap: resize". Every bind inside a submap goes there.

The group cards flow into three columns from 860 px of width, two from 560 px and one below, 8 px apart; each group goes to the shortest column. The card is at most 920 px wide and 80 % of the screen tall; a longer list scrolls. A search or filter that narrows the list does not shrink the card, so the search field stays where it is, and every change of the search or a filter takes the list back to its top.

### Group hues

Every group has a hue from a palette of eight (`logic/keybind-hues.mjs`), tuned separately for the dark and the light theme so each reads as text on its tinted card and on a keycap. The heading, the main keys of the rows, the group's keys on the keyboard map, its dot in the map's legend and its name in the map's detail line share it. Pentad's dispatcher groups keep one hue on every config: Workspaces lavender, Windows sky blue, Launch amber, Other slate; every submap is coral. A group named in descriptions, and each group of a reference sheet, takes a hue picked from its id: the first free one in the sheet that differs from its neighbours in the list. When a sheet has more groups than free hues, a group shares the hue of another group named in descriptions that is not its neighbour. The hues come from the whole sheet, so a search, a filter or "Show all" never recolours a group, and the same groups always get the same hues.

The palette is the cheatsheet's own and not a theme token: `Theme.tokens` is reachable from external widgets through `qs.theme`, and these colours are not part of that contract.

### Key shortcuts

In the list view, above the groups, a strip headed "Key shortcuts" ("Ключові") shows up to four binds worth learning first, each as a quiet tile with the combination set large (20, bold; the keys joined by a muted "+", the main key in its group's hue) over the action in the caption size. The rule is `keyShortcuts()` in `logic/keybinds.mjs`, and nothing about it is saved:

- On the live bindings: the described binds of the group named "Pentad" (any case) when the config has one; otherwise the described binds outside submaps in list order (groups in the order the config first uses them, binds in config order).
- On a reference sheet: the rows of its first group.
- A bind is skipped when it has more than three keys, when its keys joined with "+" run longer than 12 characters, or when an earlier tile already has its description (Super alone and Super+Space both search applications; the first one stays).
- At most four tiles; fewer than two qualifying binds show no strip.

The strip scrolls with the list. It is hidden in the keyboard view and while any filter is on (the search, a modifier chip, the key chip or "Duplicates"). Four tiles share one row on a card with room for two group columns; a narrower card puts two per row, and a combination too wide for its tile at 20 is set at 16.

### Filter chips

Under the search, one capsule chip per modifier that a bind of the current sheet uses: Super, Ctrl, Alt, Shift, and Caps, Mod2, Mod3 or Mod5 when a bind uses them. Selected chips narrow the list to the binds that hold all of them (Super and Shift keeps Super+Shift+L, not Super+L). A sheet without modifiers, such as Git, has no chip row at all.

On the live bindings, a "Duplicates" chip with a count appears when some keys fire two different actions: the same submap, the same modifiers, the same key, and both on press or both on release. A press and a release bind on one key are a pair, not a conflict, and `Super_L` is not the same trigger as `SUPER + SUPER_L` even though both read "Super". Two binds on one trigger that share a description share a row, and that row counts as a duplicate too. The chip shows only the duplicate rows, including a Lua bind without a description that "Show all" would otherwise hide, so both sides of a conflict are visible; each of them carries a small muted mark at its end, named "These keys also do something else".

A key picked on the keyboard map adds a removable chip at the end of the row ("Q" with a close mark). It keeps the binds on that key; picking the key again or the chip removes it.

### Keyboard view

The switch in the header turns the top of the body into a keyboard map: a 75 % ANSI board (`logic/keyboard-map.mjs`, `CheatsheetKeyboard.qml`) in its own card above the usual list, which the search and the chips still narrow. The map shows one modifier layer, exactly the selected modifier chips: in the Super layer, Super+Q is on Q, Super+Shift+Q is not. Its keys are `PentadKeycap`s with a 3 px lip, kept inside each key's cell so the grid never moves. Keys bound in the layer stand raised, in the hue of their bind's group (legend and a light tint of the face); a key with binds from more than one group stays neutral. Keys large enough to put the legend in the corner also show the bind's description or a "×2" count. Free keys lie flat and a little sunken, with a quiet legend. The held modifiers are pressed in: no lip, an inner shade along the top, the face lowered by the lip; a bound key also presses in while the pointer holds it. Under the board a legend names the groups that have a key in the layer, each with a dot in its hue, in the order of the list. Under the legend one line sums up the layer ("21 bound · 4 not on the keyboard": mouse buttons, media keys and sequences have no key), or, for the key under the pointer or the keyboard cursor, names its binds, each group's name in its hue.

- A click on a modifier key (either Ctrl, Alt or Shift) toggles that modifier chip, so it adds or removes it from the layer.
- A click on a bound key filters the list to that key; a free key does nothing.
- When the keyboard view opens with no modifier chip selected (switching to it, a new opening, another sheet), it selects the sheet's busiest layer once, for example Super on most configs or Ctrl for the Browser reference. Clearing the chips afterwards leaves the plain layer.

The switch is offered where the map means something: the sheet must have binds outside submaps of which at least half land on a key (`usable()` in `keyboard-map.mjs`; the live bindings and the Pentad, Browser, Terminal and kitty references qualify, Git and Neovim do not), and the card must have room for two group columns (560 px), below which keys would be too small to read. Elsewhere the list shows, and the choice is kept for the next sheet that has a map.

### State

The search, the modifier, key and duplicate filters start empty on every opening and whenever the sheet changes. "Show all" and the list or keyboard choice stay between openings, in memory only; nothing is written to a file or the config.

## Built-in references

The selector also offers Pentad, Neovim, Browser, Git, Terminal and kitty references. These ship with the shell and remain available when Hyprland cannot report bindings or the referenced application is not installed. They describe standard shortcuts, not detected application settings; custom mappings can differ.

Pentad covers the project's default global bindings and shortcuts inside its surfaces. Use the live Hyprland list to check actual global mappings. Neovim groups commands by mode and task. Browser covers common Linux Firefox and Chromium shortcuts. Git covers everyday repository commands, history and undo, and first-time setup; placeholders such as file and branch must be replaced before running a command, and `restore file` discards edits for good. Terminal describes Bash/Zsh Emacs editing bindings and common shell navigation; custom bindings and terminal emulators can differ. kitty lists the emulator's default `kitty_mod` (Ctrl+Shift) shortcuts for the clipboard, scrollback, windows, tabs, font size and hints; the prompt-jump and last-output rows need kitty's shell integration, and a customised `kitty.conf` can change any of them. These references do not execute commands or change application configuration.

Reference labels and descriptions are available in Ukrainian and English; search matches both languages. Changing the reference clears the search and the filters and returns the list to the top. “Show all” and the duplicates chip apply only to live Hyprland bindings.

When the cheatsheet opens it notes which reference fits the window that had focus (`sheetForWindow()` in `logic/cheatsheets.mjs`, from the window's class and title as Hyprland reports them, read before the overlay takes the keyboard): Neovim for Neovide or for a terminal whose title names `nvim` or `vim` (a browser tab about vim stays a browser), kitty for kitty, Browser for Firefox, Chromium and similar browsers, Terminal for other terminals. That reference moves to second place in the selector, right after "Live bindings", with a small accent dot and the accessible description "for the focused app". The card still opens on the sheet it was on. In the narrow drop-down that replaces the selector when the labels do not fit, the reference keeps its place and its dot.

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

The search field has the keyboard as soon as the card opens, and typing always lands there, wherever the focus is. Every word must match the row's description, a key name (`super`, `/`, or the raw name `slash`), the dispatcher or its argument, or the group's name in either language (`вікна` finds the Windows group).

| Key | Action |
| --- | --- |
| Typing | Filters the rows |
| ↑ / ↓, Page Up / Page Down | Scroll the list |
| Ctrl+Tab / Ctrl+Shift+Tab | Next or previous sheet, in the order the selector shows them |
| Tab / Shift+Tab | Move through the header, the selector, the search, the chips and the keyboard map |
| Space or Enter on a chip | Toggles it |
| Arrows, then Space or Enter on the map | Move the map's cursor; press the key under it, as a click does |
| Esc | Clears the search, the key filter and the duplicates filter together, then closes |

A press beside the card or a click on another output closes it, and it steps aside before a screenshot and when a bar menu opens.

## When it reads the bindings

`services/Keybinds.qml` runs `hyprctl binds -j` (an argument list, no shell) only on demand: each time the cheatsheet opens or Hyprland enters a submap (for the [submap hint](submap-hint.md)), and again when Hyprland reports `configreloaded` meanwhile. Nothing runs while the cheatsheet is closed and no submap is active; the last list stays in memory, so a reopen shows it at once while it is read again. Safe mode still reads the list, since the command changes nothing. Preview mode uses the built-in sample in `logic/keybinds-sample.mjs` and never runs hyprctl.

If hyprctl is missing, exits with an error, takes longer than 5 seconds or prints more than 1 MiB, the card says "Hyprland is not answering" with the reason and a "Try again" button. A failed re-read keeps the list already shown. At most 2000 binds are read, and long descriptions and arguments are clipped.

## Files

| File | Role |
| --- | --- |
| `quickshell/logic/cheatsheets.mjs` | Built-in bilingual reference catalog and `sheetForWindow()`; tested by `tests/quickshell/cheatsheets.test.mjs` |
| `quickshell/logic/keybinds.mjs` | Parsing, grouping, key names, duplicate triggers, search and filters (`mods`, `key`, `duplicates`), modifier counts, column layout, the "Key shortcuts" rule (`keyShortcuts()`); tested by `tests/quickshell/keybinds.test.mjs` with `tests/fixtures/hyprland-binds.json` |
| `quickshell/logic/keybind-hues.mjs` | The group palette for both themes, which group gets which hue, a key's shared group and the map's legend; tested by `tests/quickshell/keybind-hues.test.mjs`, including the contrast of every hue on the theme's own surfaces |
| `quickshell/logic/keybinds-sample.mjs` | The preview sample, with a submap, Lua binds and one duplicate pair (Super+P) |
| `quickshell/logic/keyboard-map.mjs` | The 75 % layout, a layer's binds placed on its keys, the layers by use, `usable()`, arrow moves; tested by `tests/quickshell/keyboard-map.test.mjs` |
| `quickshell/services/Keybinds.qml` | Runs hyprctl and holds `state` (`loading`, `ready`, `unavailable` with a `reason`) |
| `quickshell/services/CheatsheetController.qml` | `services.cheatsheet`: `open`, `sheet`, `query`, `showAll`, `view`, `mods`, `key`, `duplicates`, `contextSheet`, `show()`, `hide()`, `toggle()`, `selectSheet()` and the filter setters |
| `quickshell/features/cheatsheet/CheatsheetView.qml` | The card's content: header, selector, search, chips, the keyboard card and the group columns |
| `quickshell/features/cheatsheet/CheatsheetGroupCard.qml` | One group as a tinted card, its rows (keycaps, leader, action) and the duplicate mark |
| `quickshell/features/cheatsheet/CheatsheetShortcuts.qml` | The "Key shortcuts" strip |
| `quickshell/features/cheatsheet/CheatsheetKeyboard.qml` | The keyboard map, its legend and its detail line |
| `quickshell/components/PentadKeycap.qml` | The sculpted keycap shared with the submap hint |
| `quickshell/shell/CheatsheetHost.qml` | The layer-shell overlay, created only while open; registered with `PopupManager` as `cheatsheet` |

## Verification

```sh
timeout 120 node --test tests/quickshell/keybinds.test.mjs tests/quickshell/keybind-hues.test.mjs tests/quickshell/keyboard-map.test.mjs tests/quickshell/cheatsheets.test.mjs
timeout 300 node scripts/test-quickshell-headless.mjs --scenario cheatsheet --report /tmp/pentad-cheatsheet.json
timeout 300 node scripts/test-quickshell-headless.mjs --scenario cheatsheet --report /tmp/pentad-cheatsheet-light.json --appearance light --scale 2
```

The `cheatsheet` fixture opens the overlay on the preview sample and checks the tinted group cards, the sculpted keycaps and the hued main keys, the group hues (headings, neighbours apart), a contents-page row (leader, action against the right edge), the "Key shortcuts" strip (its four tiles and their order), three columns, "Show all", the search (which hides the strip), "Nothing found", both languages, Esc, a press inside and beside the card, a screenshot and a bar menu. With real pointer and key events it then checks the modifier chips (Tab and Space, then clicks, alone and combined; a chip hides the strip too), the duplicates chip and its marks, the keyboard view (the default layer, bound and held keys, raised, flat and pressed keys in one grid, a bound key in its group's hue and Super+P neutral, the legend, a modifier key toggling its chip, a bound key filtering the list and adding the removable key chip, the same key clearing it), that typing reaches the search from anywhere, the Esc order, Ctrl+Tab and Ctrl+Shift+Tab, Git without chips or switch, the reference for the focused app in second place with its mark, and what a reopening resets and keeps, the group hues included. Separate adapters outside preview run other programs instead of hyprctl (a missing one, `false`, `printf`, `head`) to check the unavailable reasons, parsing of real process output, the size limit and a 240-bind list that scrolls and has no strip, since none of its combinations is short enough. Last, the view in its own windows at 360 px (the list, without the switch) and 600 px (the smallest map). It writes `<report>.png`, and `.uk.png`, `.unavailable.png`, `.chips.png` (a modifier chip selected), `.keys.png`, `.keys.uk.png`, `.narrow.png` and `.medium.png` after it. HyprlandFocusGrab needs Hyprland, so closing on a click on another output is not covered by the headless run, and the focused window is set on the controller directly.
