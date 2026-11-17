# Architecture map and design contract

Read the part you need before searching. It saves a search through about 810 files. File counts were last checked on 2026-11-04, line numbers on 2026-10-23. Facts marked *uncertain* were not confirmed by running anything; check them before you rely on them.

## Repository layout

| Path | What lives there |
| --- | --- |
| `quickshell/` | The shell's runtime source. The build copies it into `dist/quickshell`. |
| `packages/widget-api/v1/` | The public widget contract: `manifest.schema.json` (JSON Schema draft 7), `contracts.d.ts` (view props and services), `README.md` (slots, settings kinds, `tool` metadata, `acceptInput`, `secret://` credentials, external plugin directory). |
| `tools/` | Python helpers that take JSON on stdin and return JSON on stdout: config store (`pentad-files.py` / `pentad_files.py`), the sidebar file tool (`pentad_file_tool.py` entry plus `pentad_tool_core`, `_pdf`, `_image`, `_media`, `_archive`), screenshots (`pentad_screenshot.py` plus `pentad_screenshot_regions.py`), wallpaper recolouring, lyrics cache, portal file picker, the Stash's content and previews (`pentad_shelf_content.py`, `pentad_shelf_preview.py`) and its clipboard bridge (`pentad_stash_clipboard.py`: paste, copy, delete of owned images), spotlight, system facts and settings for the settings window (`pentad_system.py`). The build copies the whole directory to `dist/quickshell/helpers/`. |
| `scripts/` | `pentad` (POSIX sh CLI) and the `*-quickshell.mjs` runners (see [testing](#test-layers)). `test-quickshell.mjs` copies a hard-coded list of helpers per fixture scenario. |
| `tests/` | `quickshell/*.test.mjs` (logic), `tooling/` (scripts and native runs), `files/` and `tools/` (Python `unittest`), `fixtures/`. |
| `packaging/` | `install.sh` (user, system and `DESTDIR` installs, `--uninstall`), `arch/PKGBUILD`, and the dependency list in `README.md`. `scripts/package-release.mjs` builds the release tarball. |
| `docs/development/` | Public developer documentation. `quickshell.md` (runtime, build, fixtures), `controls.md` (component contract), `popups.md` (interaction standard), `settings.md`, `widgets.md`, plus feature pages. |
| `docs/third-party/`, `LICENSES/` | Notices and license texts for icons, emoji data and other third-party material. |
| `.github/` | Issue templates and the PR template. There is no CI workflow yet. |
| `.claude/` | Agent tooling: the `guard-desktop.mjs` hook (registered in `settings.json`) and the `verify-change` and `new-widget` skills. Local worktrees under `.claude/worktrees/` are gitignored; never search them. |

Local-only (gitignored) material: `CLAUDE.local.md` (personal agent notes), `ROADMAP.md`, `docs/superpowers/` (dated specs and plans, including the binding design specs), `docs/migration/`, `docs/reviews/`, `docs/references/`, `docs/previews/`, `dist/`, `artifacts/` (local Quickshell runtime, reports, screenshots).

## Inside `quickshell/`

- **`shell.qml`** is a `ShellRoot` that creates one `Services` object and hands it to the hosts (`WallpaperHost`, `OutputHost`, `IpcBridge`, `NavigationHost`, `SpotlightHost`, `ScreenshotHost`). It reads `PENTAD_SAFE_MODE` and `PENTAD_PREVIEW`. Settings, screenshot settings, magnifier and shortcut windows sit behind `Loader`s.
- **`lock.qml`** is the second entry point: the lock screen, started as its own `qs` process by `pentad lock`. It does not create `Services`; it uses `features/lock/` and `logic/lock-screen.mjs`. Its security rules are in [session](../development/session.md#security-rules).
- **`services/`** holds 46 adapters to the system (Hyprland, audio, network, media, config, plugins, screenshot, settings, wallpaper, file tools, file picker…), many with a paired `*Request.qml` worker. **Services are not singletons**: `Services.qml` is a container passed down as a `services` property, and every adapter honours `preview` and `safeMode`. `Services.text(uk, en)` is the translation function.
- **`logic/`** holds 93 Qt-free `.mjs` modules (counted 2026-11-17) imported into QML as `import '../logic/x.mjs' as X`. Each is tested by `tests/quickshell/<name>.test.mjs`. `qml-engine-compat.test.mjs` forbids JavaScript the QML engine does not support. Never import Qt types here.
- **`components/`** is the shared UI kit: `Pentad*` controls (Button, Toggle, Slider, ComboBox, Menu, Popup, Text, Icon, ToolTip, Marquee, Control…), `AttachedPopover`, `AttachedSideSurface`, `ContinuousSurface`, `MenuGrid`, `MenuPointerIntent`, `SurfaceRegion`. The contract is `docs/development/controls.md`.
- **`theme/`** holds the only singletons: `Theme`, `Metrics`, `Motion`, `ShapeTokens` (plus `components/GeometryDiagnostics`).
- **`features/`** holds the views by area: `bar`, `cheatsheet` (the keybind cheatsheet; its overlay is `shell/CheatsheetHost.qml`, its state `services.cheatsheet`, its data `services.keybinds`; `CheatsheetView` delegates to `CheatsheetGroupCard` and the keyboard map `CheatsheetKeyboard`; its models are `logic/keybinds.mjs`, `cheatsheets.mjs` and `keyboard-map.mjs`), `keyhint` (the submap hint strip, `SubmapHintView`; its window is `shell/SubmapHintHost.qml`, its state `services.submap`, its model `logic/keybind-hints.mjs`; see [submap hint](../development/submap-hint.md)), `media`, `notifications`, `overview`, `screenshot`, `settings`, `shelf` (the Stash, shown to users as "Сховок / Stash"; the folder and ids keep the old name: `StashView`, the window frames in `shell/`, `StashQuick` for the activity tab, `StashRow`, `StashPhotoStrip`, `StashComposer`; its state lives in `services.stash`, its data in `services.shelf`), `sidebar`, `system`, `windowswitcher` (and an empty `activity`). Large views delegate parts to sibling files: `QuickSettingsGrid` to `QuickSettingsEditChip`/`EditBar`/`EditTray`/`ContextMenu`; `AudioControls` to `AudioLevelSlider` (one row for output and input), `AudioAppearanceMenu`, `AudioDeviceSection`; `SettingsField` to `SettingsSliderEditor`, `SettingsWidgetCatalogEditor`, `SettingsListEditor`, plus the wallpaper gallery and accent swatches.
- **`shell/`** holds the top-level windows and hosts: `BarWindow`, `OutputHost`, `WallpaperHost`/`WallpaperWindow`, `PopupManager`, `IpcBridge`, `SettingsWindow`, `DragIngress`, `SurfaceHost` and others.
- **`widgets/`** holds 25 built-in widgets, each a directory with `manifest.json` and `View.qml` (some also have `Controller.qml`). The build validates every manifest and writes `builtin-registry.json`; no other registration exists. External widgets load from `$XDG_CONFIG_HOME/pentad/plugins/<id>/`.
- **`plugins/`** is the widget-hosting runtime: `PluginHost`, `PentadWidget`, `PlacementController`, `SettingsForm`, `WidgetSurface`.
- **`defaults/`** holds the default config documents (`interface`, `layout`, `session`, `spotlight`, `theme` JSON) and optional compositor snippets that nothing activates automatically.
- **`tests/`** holds 64 QML fixture scenarios. A fixture builds a real `Services { preview: true; safeMode: true }` with inline fakes and prints `PENTAD_TEST {json}`.
- Every folder has a `qmldir` and is imported as `qs.<folder>` (`qs.theme`, `qs.components`, `qs.features.bar`); some files use relative imports instead.

User data: config documents in `$XDG_CONFIG_HOME/pentad/*.json`, state (notifications, shelf (the Stash), activity, organizer) in `$XDG_STATE_HOME/pentad`, written through `tools/pentad-files.py` with revision checks. Treat both as user data that must survive upgrades.

## Where a change goes

| Change | Files |
| --- | --- |
| New built-in widget | `quickshell/widgets/<name>/`, `quickshell/logic/<name>.mjs`, `tests/quickshell/<name>.test.mjs`. Use the `new-widget` skill. |
| Widget setting | the manifest's `defaults` and `settingsFields`; secret-like keys default to `""` or a `secret://` reference |
| Settings window page or control | `quickshell/logic/settings-catalog.mjs`, `settings-schema.mjs`, views in `quickshell/features/settings/`; see `docs/development/settings.md` |
| Default placement of a widget | `defaults.layout.widgets` in `quickshell/logic/config.mjs`, plus `config.test.mjs` expectations |
| Shared control behaviour | `quickshell/components/`, then `docs/development/controls.md` |
| System integration | an adapter in `quickshell/services/`, pure parsing in `logic/`, a fake in the fixture |
| Wallpaper and its palette | `services/Wallpaper.qml`, `shell/WallpaperHost.qml`/`WallpaperWindow.qml`, `logic/wallpaper.mjs`, `logic/wallpaper-palette.mjs`, `features/settings/SettingsWallpaperGallery.qml`, `tools/pentad_recolor_wallpaper.py`, transition shaders `assets/shaders/wallpaper-*.frag` (rebuild with `scripts/build-shaders.mjs`); fixture `wallpaper` |
| New Python helper module | `tools/pentad_<name>.py`; the entry appends its own directory to `sys.path` (see [before splitting](#before-splitting-a-file)); add it to the helper lists in `scripts/test-quickshell.mjs` |
| Widget API | `packages/widget-api/v1/` (schema, `contracts.d.ts`, README), `logic/plugin-manifest.mjs`, `tests/fixtures/migration/manifests.json`, compatibility notes, in one change |

## Text and translations

- What runs: `services.text("Українська", "English")` in QML (some views wrap it as `tr`), and paired `labelUk`/`labelEn` fields in manifests and the settings catalog. The language follows `interface.language` (`uk`/`en`), then `Qt.locale()`.
- `quickshell/catalogs/en.json` and `uk.json` are built and shipped but **no QML or `.mjs` file loads them** (checked 2026-10-22). Manifest `labelKey` values are shown raw. Do not add strings there unless the task is to wire them up.
- `tests/quickshell/settings-copy.test.mjs` checks the settings catalog pairs (non-empty, Ukrainian differs from English and contains Cyrillic, length limits). Nothing checks other pairs automatically, so check them in review.
- Write natural Ukrainian, not a word-for-word translation. If you are not confident in a Ukrainian string, say so in the report instead of guessing silently.

## Design contract (summary)

The binding rules come from the maintainer's design specs, which are not published; when a local copy exists (`docs/superpowers/specs/`), its sections marked "Binding user correction" win over this summary. Everyone else follows this summary and the public rules in `docs/development/controls.md`, `popups.md`, `settings.md` and `widgets.md`.

- **The stance: give the user's time back, not spend it. Calm at rest, dense on demand.** A surface stays quiet and out of the way until the user reaches for it, then puts every action a keystroke or a drag away. At rest this means restraint (no instructional text, no accent floods, no notifications clamouring, no hover-dismiss timers); once engaged it means density and speed (every verb within reach, instant feedback, no dead ends). When "calm" and "fast" conflict on a surface, resolve it this way rather than splitting the difference. The visual rules below serve this stance.
- **Borderless.** No perimeter outlines around surfaces or controls. Thin separators between rows or cells are fine. Error states get an outline in a softened palette red, plus a message.
- **Shapes.** Buttons, chips, segmented controls and the active navigation item are capsules; square icon buttons are circles; text fields and keycaps are rectangles with 6–8 px radii.
- **Radii** come from `Metrics`, never literals: `radiusCard` 14, `radiusPopover` 16, `radiusSmall` 6, `radiusMedium` 8, `radiusTag` 4, `radiusPill` for capsules. Nested radii are concentric: inner = outer − padding.
- **Spacing and type.** Base-4 spacing, compact by default (about 4 px between related rows, 24 px between sections). Text roles are 12/14/16/20 only (`textCaption`, `textBody`, `textSection`, `textTitle`). Geist is the UI typeface.
- **Stacked lines** of one small component (time over date, title over subtitle) sit solid: a fixed line box no taller than the pixel size, no `spacing`, separated by weight or colour rather than air. The 1.2 leading is for wrapped text only. Abbreviated dates carry no dots.
- **Accent** never floods a container, card or button background. It marks foreground, micro-indicators and slider tracks. Selected state = tonal elevation + 80 % foreground + an optional check.
- **Focus ring** only for keyboard focus (`visualFocus`; custom focusables call `forceActiveFocus(Qt.TabFocusReason)` on keyboard moves). Pointer selection never draws a ring.
- **Less visible text.** No instructional subtitles at rest; explanations go behind `PentadInfoButton` or a tooltip.
- **Popups.** A click inside keeps a popup open, an outside press closes it immediately, there are no hover-dismiss timers, Escape closes the newest child first ([popups](../development/popups.md)).
- **Settings rows** are at least `Metrics.settingsRowMinHeight` (40), label on the left, control on the right; lists prefer cards or chips over plain text.
- **Drag and drop** is a headline feature: keep inputs and outputs draggable both ways, prefer direct drop targets over dialogs, and use the desktop portal for file picking ([drag-and-drop](../development/drag-and-drop.md)).

Before calling a UI change done, grep the diff for `border.width`, `Theme.tokens.outline`, literal radii and literal font sizes.

## Test layers

| Layer | Command | Starts `qs`? |
| --- | --- | --- |
| Logic and static contracts | `timeout 120 node --test tests/quickshell/*.test.mjs` | No. The `*-qt` tests compile a small QJSEngine harness with `c++` and skip without the toolchain. |
| Tooling with fakes | `tests/tooling/{dev-quickshell,verify-quickshell,shelf-content,hardware-readonly,qml-recursion}.test.mjs` | No |
| `tests/tooling/quickshell.test.mjs` | part of `pnpm test` | Its build test uses a scratch output, but one test starts the fixture runner with the caller's environment: run it only in CI or an isolated session |
| Packaging, doctor, release | `python3 -m unittest discover -s tests/tooling -p 'test_*.py'`, `node --test tests/tooling/package-release.test.mjs` | No; installs into temporary prefixes with a stub `qs` |
| Python helpers | `timeout 120 python3 -m unittest discover -s tests/files -q` (also `tests/tools/test_*.py`) | No |
| Scratch build | `timeout 60 node scripts/build-quickshell.mjs --output "$SCRATCH/qs-build"` | No; validates every manifest |
| QML fixtures | `scripts/test-quickshell-headless.mjs --scenario <name> --report <path> [--appearance dark\|light] [--scale 1\|1.25\|1.5\|2] [--reduced-motion]` | Yes, in a private KWin, D-Bus and HOME. Not in quiet mode |
| Native and integration | `tests/tooling/*-native.mjs`, `scripts/verify-quickshell.mjs` | Yes; `verify-quickshell` also builds into `dist/`. Ask the user |

`ui-contract.test.mjs` compares against `ui-contract-baseline.json`, and that baseline may only shrink. `corner-contract.test.mjs` uses `corner-baseline.json`. Do not regenerate a baseline to make a test pass.

## Runtime dependencies

Required: Hyprland, Quickshell 0.3.2 or newer with the Qt 5 Compatibility and Qt SVG modules, and Python 3. Everything else is optional and listed by feature in `packaging/README.md`. The `FEATURES` table in `tools/pentad_doctor.py` is the source of truth, and `pentad doctor` checks it on the user's machine. Any new call must degrade gracefully when the program is missing ([for everyone](for-everyone.md#portability)). Node.js is needed only to build from source; Node 24 and pnpm are development tooling.

## Large files

Read these by range (`grep -n` first, then `offset`/`limit`):

| File | Lines | Status |
| --- | --- | --- |
| `quickshell/tests/control-center.qml` | 1065 | Fixture; the harness loads scenarios by file name, so it is not split |
| `quickshell/tests/control-templates.qml` | 824 | Fixture, as above |
| `services/Desktop.qml` | 750 | Not split: `tailscale-launch.test.mjs` runs its `command()` and `openTailscale()` from the source text, and the native fixtures read its internals |
| `services/Hyprland.qml` | 663 | Preview builders moved to `logic/hyprland-preview.mjs`; the command methods stay together, and `hyprland-overview-demand.test.mjs` runs its methods and `onRawEvent` from the text |
| `quickshell/tests/bar-visual.qml` | 656 | Fixture |
| `services/Audio.qml` | 621 | Volume maths moved to `logic/audio.mjs`; the state machine stays, because probes, operations and identities are shared both ways |
| `components/PentadControl.qml` | 600 | Not split: one tightly shared state, and tests read `activatePrimary` and the tooltip delays from its text |
| `features/system/QuickSettingsGrid.qml` | 591 | Split 2026-10-22; the tile delegate stays because a test reads its handler |
| `services/Screenshot.qml` | 569 | Not analysed yet |
| `features/screenshot/ScreenshotEditor.qml`, `ScreenshotToolbar.qml` | 553, 516 | Not split: `corner-baseline.json` is keyed by line number |
| `tools/pentad_screenshot.py` | 550 | Region detection moved out; everything the tests patch stays in the entry |
| `components/MenuPointerIntent.qml` | 535 | Not split: its test extracts every method and the `closeTimer`/`cursorSocket` blocks from the text |

When a task makes one of these larger, consider splitting out a focused component, and mention it instead of doing it unasked.

## Before splitting a file

Moving code between files breaks things that a build and `qmllint` do not show. Check these first; each one cost a failed attempt on 2026-10-22.

- **Tests read source text.** About 20 tests in `tests/quickshell/` read QML or Python source and extract functions or blocks by regular expression (for example `tailscale-launch`, `menu-pointer-intent`, `screenshot-capture`, `control-center-icons`, `file-tools`, `ui-contract`, `corner-contract`). Before moving code, `grep -rn '<FileName>' tests/` and read what the test extracts. Code it extracts stays where it is, with the same indentation and first-match order.
- **Baselines are keyed by path.** `ui-contract-baseline.json` counts violations per file, and that baseline may only shrink: moving a violating line into a new file fails it. Fix the violation instead, for example `ToolTip.delay: 700` → `Metrics.tooltipDelay`, and remove the entry. `corner-baseline.json` is keyed by file and line number, so any edit above a listed line fails it.
- **Never bind a property to its own name.** In `NewEditor { field: field }` the right-hand `field` resolves to the new object's own property, not to the parent's id, so the value stays `undefined`. Give the property a different name (`owner: field`). `qmllint` and the logic tests do not catch this; the `settings-window` fixture did.
- **Keep the parent's API.** Fixtures read ids, aliases and objectNames on the original root (`compactOutputSlider`, `menuGrid`, `control-center-*` names). Forward them with `property alias x: child.x` and keep objectNames unchanged.
- **Register new files** in the folder's `qmldir`, and never let a file instantiate its own type (`qml-recursion.test.mjs` scans for it).
- **Python helpers under `-I`.** The file tool runs as `python3 -I`, which leaves the script directory off `sys.path`. An entry that imports siblings appends (never prepends) its own directory, so the standard library still wins over anything in the helpers directory. Names that tests patch with `patch.object(module, …)` must stay in the module the tests load.
- **Verify like before.** Run the relevant headless fixtures on the unchanged commit first, then after the change, and compare check counts and runtime `TypeError`/`ReferenceError` lines in the logs. A worktree needs the main checkout's `artifacts` linked in for that, and the link must be removed before committing.

## Known stale documentation

None known as of 2026-10-23. Add any stale fact you find here, and fix it when your task touches it.
