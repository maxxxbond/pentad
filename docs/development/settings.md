# Pentad settings window

A schema-driven settings window: a grouped sidebar, search, pages with sections and card rows, and a sheet for adding widgets. The window reads the existing configuration documents and writes changes only through `services.config.save`. The rules for less text and for controls are in [controls.md](controls.md).

## Purpose

- One entry point for the settings the shell actually controls: appearance, language, bar, control center, widgets, Spotlight, notifications, screenshots, session, shortcuts, system.
- Every page is described by data (the catalog); QML only displays it. Adding an item means changing the catalog, not QML.
- Visible text is the name, the value and any significant error. Explanations go into `PentadInfoButton` (`helpText`).
- The "Devices" group (Network, Bluetooth, Sound, Power) embeds the control center's live components and services through `panel` items, so both places share one behaviour. The "System" group adds Date & time, Default apps and About through `SettingsSystemPanel.qml` and `services.systemSettings` (`tools/pentad_system.py`: `timedatectl`, `xdg-mime`, `/proc` and `/etc/os-release`; reads run when a page opens, writes are refused in preview and safe mode). Displays and input devices are not part of it yet.

## File map

Logic (pure `.mjs`, tested with `node --test`), `quickshell/logic/`:

| File | Role |
| --- | --- |
| `settings-catalog.mjs` | Data: `groupCaptions` and `pages` (fifteen pages; "Bar tools" is a tab of the "Bar" page, and the old id `bar-tools` opens it over IPC) |
| `settings-schema.mjs` | `groups`, `controls`, `validateCatalog`, `manifestFor` (a projection into `settingsFields` for `validateSettings`) |
| `settings-bindings.mjs` | `readValue`, `writeValue`, `commitCheck`: read and write a path in a document without mutating the input |
| `settings-search.mjs` | `matches`, `search`: search that normalizes apostrophes and case |
| `settings-nav.mjs` | `flatPages`, `initialNav`, `selectPage`, `selectTab`, `moveSelection` |
| `settings-controller.mjs` | Pure state of the single pending request (`pendingId`, `pendingKey`, `error`) |
| `settings-list.mjs` | `moveItem`: reorders a list of options |
| `settings-shortcut.mjs` | Shortcuts: `fromQtEvent`, `normalizeShortcut`, `shortcutError`, `isShortcut`, `shortcutParts`; a modifier is required, except for `F<n>` and `Print` |
| `settings-color.mjs` | `normalizeColor`, `sameColor`, `defaultSwatches`; the `#RRGGBB` rule is the same as in `resolveTheme` (`isHexColor` in `theme.mjs`) |
| `settings-flow.mjs` | A finite-state wizard: `createFlow`, `setDraft`, `canContinue`, `next`, `back`, `progress`, `isLast` |

QML components, `quickshell/features/settings/` (registered in `qmldir`): `SettingsSidebar`, `SettingsNavItem`, `SettingsPage`, `SettingsSection`, `SettingsRow`, `SettingsField`, `SettingsOptionList`, `SettingsOptionCards`, `SettingsColorField`, `SettingsFontField`, `SettingsChipSet`, `SettingsShortcutField`, `SettingsWidgetCatalog`, `SettingsPlacementArt`, `SettingsPentadPicker`, `SettingsPentadGlyph`, `SettingsFramePreview`, `SettingsSearchResults`, `AddWidgetSheet`, `WidgetSettings`. `ScreenshotSettings` is the body of the screenshot dialog (title, sections, action bar), hosted by `shell/ScreenshotSettingsWindow.qml`.

The look follows these rules:

- Borderless: no outlines around surfaces and controls. Divider lines between rows and cells are allowed: a section is one `surfaceRaised` card (`Metrics.radiusCard` = 14) with no outline, its rows (`SettingsRow`) sit on it and draw a thin `Theme.tokens.outline` line with a 16 px inset above themselves; a row outside a section draws its own card. Fields on a card take the next tonal level (`fill: surfaceOverlay`).
- A focus ring only from the keyboard: standard controls through `visualFocus`; custom focusable elements (chips, swatches, cards, segments, cells) are built on `Control`, so they have `visualFocus` too; moving focus with the arrows calls `forceActiveFocus(Qt.TabFocusReason)` so the ring stays. A mouse click draws no ring.
- An error is an outline in the palette's status red with transparency (`Qt.alpha(Theme.tokens.error, 0.7)`) and a light tint, plus the message text; on a row inside a section the outline is concentric (card radius − 4).
- Capsules are the standard: `PentadButton`, chips (`SettingsChipSet`), segmented switches (`PentadSegmented`, with a concentric thumb: half the height − inset) and the active navigation item (`SettingsNavItem`) have `extent: height / 2` (a square icon becomes a circle). Input fields and keycaps stay rectangles of 6–8 px (`Metrics.radiusSmall`/`radiusMedium`); the window and sheets use `Metrics.radiusPopover` = 16; the inner radius is the outer one minus the inset; all insets are multiples of 4.
- A row is the name on the left and the control on the right (the "name above the field" layout was rejected). The sidebar has no footer: the theme switch was removed until the light theme is fully implemented.
- The accent marks indicators only (the changed marker, active sections in the placement thumbnail, the selection check) and does not fill containers.

The controller is `quickshell/services/SettingsController.qml`, available as `services.settings`. Properties: `open`, `pageId`, `tabId`, `query`, `pendingId`, `pendingKey`, `error`, `flow`, `widgetId` (the widget instance whose page replaces the catalog page) and `status` (`""`, `saving`, `saved`, `undo`, for the page header). Functions: `openPage(pageId?)`, `close()`, `setQuery(text)`, `commit(item, value)`, `runAction(name)`, `openWidget(instanceId)`, `closeWidget()`, `resetPage(pageId | page)` (one entry at a time, no undo) and `undo()` (reverts the last change; available for 5 s after "Saved").

Pure state helpers: `logic/settings-state.mjs` (`modifiedItems`, `enabledWidgetCount`). The `.mjs` logic imported by QML must not use `structuredClone`, object spread `{ ...x }` or module-level `flatMap`: the QML engine does not support them (`tests/quickshell/qml-engine-compat.test.mjs`). The scenarios `settings-primitives`, `settings-field` and `settings-window` run through `scripts/test-quickshell-headless.mjs`.

The window is `quickshell/shell/SettingsWindow.qml`, wired into `quickshell/shell.qml` through `Loader { active: services.settings.open }`, like `ScreenshotSettingsWindow`.

IPC: the `settings` command in `quickshell/shell/IpcBridge.qml` with the payload `{ page? }`. `page` must be a string, otherwise the reply is `{ ok: false, reason: 'invalid-payload' }`. The reply is `{ ok }`; an unknown `page` does not open the window.

## Catalog contract

```
Page   = { id, group: 'personalization'|'devices'|'shell'|'behavior'|'system', icon, labelUk, labelEn, keywords: string[], tabs?: Tab[], sections: Section[] }
Tab    = { id, labelUk, labelEn }
Section= { id, tab?: string, collapsible?: boolean, labelUk, labelEn, helpUk?, helpEn?, items: Item[] }
Item   = { key: string,            // unique within the page; also the manifest field key
           kind: 'text'|'integer'|'number'|'boolean'|'select'|'color',   // data type, as in plugin-manifest.mjs
           control: 'toggle'|'segmented'|'dropdown'|'slider'|'stepper'|'text'|'font'|'color'|'options'|'cards'|'shortcut'|'list'|'chips'|'catalog'|'panel'|'button'|'link'|'value',
           document: 'theme'|'layout'|'interface'|'spotlight'|'notifications'|'session',
           path: string,           // a dotted path inside the document
           labelUk, labelEn, helpUk?, helpEn?, icon?, keywords?: string[],
           options?: {value, labelUk, labelEn}[], min?, max?, step?, default?,
           unit?: string,          // slider/stepper only: the unit next to the numeric field
           prefix?: string,        // text only: a prefix before the field
           art?: string,           // cards: the preview key (also allowed in options[i].art)
           action?: string,        // for control 'button' | 'link', run by SettingsController
           visibleWhen?: { key: string, equals: unknown } }
```

The newer controls:

- `cards`: selection cards with a preview (`kind: 'select'`, `options` required; `art` sets the preview and `SettingsOptionCards.artDelegate` draws it); the arrows move the selection, with radio semantics.
- `color`: presets and a `#RRGGBB` field (`kind: 'color'`); commit on Enter/blur, Esc restores the value, and the error appears under the field.
- `shortcut`: keycaps and a record button (`kind: 'text'`); a modifier is required, except for `F<n>` and `Print`; Esc cancels; `default` must be a valid shortcut.
- `list`: a reorderable list with a per-item switch (`kind: 'select'`; drag or Alt+Up/Down); it is not projected in `manifestFor` (the value is an array), and items cannot be removed.
- `font`: a choice of installed families (`kind: 'text'`): the button shows the current family in its own face, and the popup has a filter and a list of `Qt.fontFamilies()`, each row in its own font.
- `chips`: multi-select with chips (`kind: 'select'`, `choices: {value, labelUk, labelEn}[]` required, `sentinel`/`sentinelUk`/`sentinelEn` set the "Auto" chip); the value is a sentinel string or a non-empty array of codes in selection order (`logic/settings-chips.mjs`: `toggleChoice`, `isSentinel`, `selectedChoices`); used for `spotlight.emoji.languages`.
- `panel`: a live device panel (`panel: 'wifi'|'bluetooth'|'bluetooth-devices'|'bluetooth-nearby'|'sound'|'mixer'|'power'|'brightness'|'datetime'|'default-apps'|'about'`, list in `panels` of `settings-schema.mjs`), drawn by `SettingsDevicePanel.qml` (system panels by `SettingsSystemPanel.qml`). It has no `document`/`path`, is full-bleed with no caption, and is skipped by `manifestFor` and the default checks. Wi-Fi, sound and the mixer reuse `NetworkControls`, `AudioControls` and `ApplicationMixer`; power and brightness are rows on one card (`logic/settings-devices.mjs`). Panels are destroyed with the page, so the Wi-Fi scan and the mixer probes stop when it is left; brightness borrows the bar windows' adapters and never releases them. Bluetooth goes through `services.quickSettings` (`pairBluetoothDevice`, `forgetBluetoothDevice`, `setBluetoothDiscovering`); the nearby card scans only while it exists and only stops a scan it started. Pairing has no agent yet, so devices that ask for a PIN fail with a message.
- `catalog`: cards of installed widgets (`kind: 'select'`, the value is the array of `layout.widgets` placements): a section thumbnail, the name from the manifest, the module id, an `enabled` switch, a gear (`openWidget`), delete, drag or Alt+arrows for order, and the last card triggers the `widgets.add` action. The row has no card and no caption (`bare`); it is not projected in `manifestFor`.
- `slider` has a numeric field (clamped to `min`/`max`/`step`) and `unit`; `text` has an optional `prefix`.
- Row: `SettingsField` binds `modified` (the value differs from `default`) and `resetRequested()` (commits `default`) only if `SettingsRow` declares them.
- The catalog does not yet contain `cards`/`shortcut`/`list` entries: there are no matching keys in `parseDocument`; the "Shortcuts" page remains a read-only view.

Validation reuses `validateSettings` from `plugin-manifest.mjs`: `manifestFor(page)` projects the data items onto `settingsFields` (`label` = `labelEn`). Type checks are not duplicated.

Copy rules (checked by `tests/quickshell/settings-copy.test.mjs`):

- every Uk/En pair (groups, pages, tabs, sections, items, options) is non-empty;
- Ukrainian differs from English, except for an explicit allow-list in the test (proper names: `Spotlight`, and `English` as a language name in its own spelling);
- no name is longer than 32 characters in either language;
- help texts (`helpUk`/`helpEn`) exist only as a pair.

Texts go through `services.text(uk, en)`; the `@pentad/i18n` catalogs (`packages/i18n/src/locales/{en,uk}.json`) are not used for this window, as for the rest of the Quickshell interface (decision: the JSON catalogs were not changed).

## How to add a page or an item

1. Make sure the key exists in `parseDocument` in `logic/config.mjs` and in `defaults/*.json`. Keys are not invented.
2. An item on an existing page: add an `Item` object to the `items` of the right section in `settings-catalog.mjs` (there is a `toggle(...)` helper for a switch). Set `labelUk` and `labelEn`; for `select`/`segmented`/`dropdown`, `options`; for `slider`, `min < max` and `step > 0`; `default` must match `defaults/*.json`.
3. A new page: add a `Page` with a unique `id`, a `group` from the five groups, an `icon` (a path relative to `quickshell/assets/icons/`, and the file must exist) and `keywords` in both languages. A new group needs changes to `groups` (`settings-schema.mjs`) and `groupCaptions`.
4. A hidden item: `visibleWhen: { key, equals }` with a key from the same page.
5. An action (`button`/`link`): set `action` and add a branch to `SettingsController.runAction`.
6. Run `node --test tests/quickshell/settings-*.test.mjs`. The schema, search and copy tests will check the catalog; no QML change is needed.

## Option keys and their consumers

Every key below is validated in `parseDocument` (`logic/config.mjs`), and older documents without it get the default, which keeps the previous behaviour. `tests/quickshell/settings-catalog.test.mjs` checks that each catalog `default` matches `defaults` in `config.mjs`.

| Key | Values (default) | Read by |
| --- | --- | --- |
| `layout.clockFormat` | `24h`, `12h` (`24h`) | `widgets/clock/Controller.qml` through `timePattern` in `logic/clock.mjs` |
| `layout.clockDate` | `day-month`, `month-day`, `hidden` (`day-month`) | the same controller through `datePattern`; `hidden` leaves a one-line clock |
| `layout.showBatteryPercent` | boolean (`false`) | `features/bar/StatusCluster.qml`, next to the battery icon |
| `layout.workspaceCount` | 1–8 (`5`) | empty numbered workspaces offered by `workspaceChoicesForOutput` (`logic/workspaces.mjs`) in the bar switcher and the workspaces widget |
| `interface.firstDayOfWeek` | `auto`, `monday`, `sunday`, `saturday` (`auto`) | `services/Organizer.qml` through `weekStart` (`logic/organizer.mjs`); `auto` takes the locale's day |
| `interface.levelOverlay` | boolean (`true`) | `features/system/LevelOverlay.qml`; errors still show when it is off |
| `interface.notificationTimeout` | 2–30 seconds (`7`) | `popupPolicy` in `logic/notifications.mjs`; an app's own timeout and critical urgency still win |
| `interface.notificationPopups` | 1–5 (`3`) | the same policy; older popups move to the center |
| `interface.stashWindow` | `overlay`, `window` (`overlay`) | `services/StashController.qml` (`services.stash.mode`): a centered overlay or a normal tiling window; changed with `setMode` |
| `spotlight.calculator`, `spotlight.webSearch` | boolean (`true`) | `createDefaultProviders` in `logic/spotlight-providers.mjs` |
| `spotlight.webEngine` | an id from `webSearchEngines` (`duckduckgo`) | the same factory; the query leaves the machine only when the user picks the web row |
| `spotlight.clipboardEnter` | `paste`, `copy` (`paste`) | `activate` in `services/Spotlight.qml`: `paste` copies the entry, closes and sends the paste keys to the window Spotlight opened over; `copy` keeps the older copy-only Enter |
| `spotlight.pasteShortcut` | `auto`, `ctrl-v`, `ctrl-shift-v`, `shift-insert` (`auto`) | `pasteKeys` in `logic/spotlight-providers.mjs`; `auto` uses Ctrl+Shift+V for known terminal classes |
| `wallpaper.transition` | `fade`, `wipe`, `disc`, `pixelate`, `iris`, `random`, `none` (`fade`) | `shell/WallpaperWindow.qml` through `pickTransition` in `logic/wallpaper.mjs`: `fade` cross-fades the two image layers; `wipe`, `disc`, `pixelate` and `iris` draw a shader from `assets/shaders/` over them only while the change runs; `random` picks one of those five for each change. Reduced motion makes every change instant |

## Screen and sleep timers

The Power page embeds `SettingsIdlePanel`, backed by `SystemSettings.idle` and
`tools/pentad_idle.py` through the existing system helper. The two selectors edit independent
hypridle inactivity timers: display power-off and suspend. Neither changes the lock timer.
Display power-off includes a resume command so keyboard or pointer activity can wake the displays.
New display listeners use Hyprland's Lua DPMS dispatcher; existing legacy DPMS commands are retained.

The helper reads `$XDG_CONFIG_HOME/hypr/hypridle.conf` (falling back to `~/.config`). It supports
ordinary multiline `general` and `listener` blocks, variables, direct DPMS and suspend commands,
and the conventional `$suspend_cmd` variable. Other listeners, commands, conditions, comments,
file permissions and custom timeout values are preserved. “Never” comments out the selected
listener with `# pentad-idle-disabled: `; choosing a time restores its original commands and options.
Changing a variable-based timeout replaces only that listener's value, leaving shared variables alone.

Writes use a bounded lock, a content revision and atomic replacement; a conflicting edit is rejected
and the UI refreshes the confirmed values. Includes (`source`), duplicate matching listeners,
unsupported syntax, symlinks, invalid UTF-8 and oversized files are read-only. Missing config or
hypridle shows an unavailable state with Refresh; Pentad does not create an autostart or enable a
service. Users with a custom `hypridle --config` path or custom timer scripts should edit those
manually. All helper tests use temporary files and fake programs.

Saved changes take effect after the user restarts hypridle or signs in again. The panel reports
this requirement after a successful change. It does not restart services, invoke the stored commands,
or change the user's running session. Preview launches no helper and safe mode allows reads only.

Regression coverage lives in `tests/tools/test_pentad_idle.py`, `test_pentad_system.py`,
`tests/quickshell/settings-system.test.mjs` and the isolated `settings-window` fixture. The fixture
checks both languages, confirmed values while saving, conflicts, Never, missing dependencies,
recovery, keyboard and pointer popup dismissal. Its gallery flags select the theme and reduced motion.

## How saving works

- A single pending request. `commit(item, value)` first calls `canCommit`; if `pendingId` is not empty, it returns `''` and changes nothing, and the pending request is not lost.
- `commitCheck(documents, item, value)` builds a copy of the document through `writeValue` and runs it through `parseDocument`. An invalid value (`layout.barHeight = 50`, `theme.accent = 'red'`) is rejected with a `message`, and the write does not start; the controller sets `error`.
- Writes go only through `services.config.save(name, document)`. `services.config.documents` is not mutated. `reduceCommit` takes the request id that `save` returned; an empty id means the request was not sent.
- `commandFinished(requestId, result)` clears the pending state (`reduceFinished`). Success clears the error; a failure or a `conflict` (the file was changed elsewhere) keeps the error text, and the row returns to the confirmed value. Foreign `requestId`s are ignored.
- Checkpoints (`config.checkpoint`) are taken for the `layout` and `theme` documents; the identifiers are kept in the controller's memory, and `config.restore` needs at least one checkpoint.

## Adding a widget

`AddWidgetSheet` (the `widgets.add` action sets `flow = 'add-widget'`, and `SettingsWindow` loads the sheet): one sheet with a card for every installed widget (`registryFromCatalog` from `logic/settings-widget-flow.mjs`), with a thumbnail of the supported sections, the name, the id and an "Added" mark for existing instances. Choosing a card builds a placement through `buildPlacement` (the first supported slot of the first section, default parameters), commits `layout.widgets` and, after `commandFinished`, opens the new widget's page (`openWidget`), which has the "General" and "Placement" tabs. Esc or a tap outside the sheet closes it. There is no step-by-step wizard.

## Step state machine (`settings-flow.mjs`)

The pure module is kept for future multi-step editors; no QML uses it at the moment. Every function returns a new object and does not mutate its input.

| Function | Action |
| --- | --- |
| `createFlow(steps, draft)` | `{ steps, draft, index: 0, errors: [] }`; `step = { id, icon, labelUk, labelEn, isNew?, validate(draft): string[] }` |
| `setDraft(flow, patch)` | merges `patch` into the draft and clears `errors` |
| `canContinue(flow)` | `true` if there are steps and the current step's `validate` returns an empty array |
| `next(flow)` | with errors, stays on the step and returns `errors`; otherwise moves on; on the last step the state does not change |
| `back(flow)` | one step back, not below 0 |
| `progress(flow)` | `{ index, total, ratio }` (the index starts at 1; an empty flow gives zeros) |
| `isLast(flow)` | `true` on the last step |

The controller marks the active flow in `flow` (`'add-widget'` after the `widgets.add` action); the module has no separate `finish` function.

## Verification

The table records the original window implementation. Screen and sleep timer coverage was added
later; its interactions passed in dark/100% and light/200% with reduced motion. The light run still
reproduces the existing `font-second-click-closes` failure, also present with the unchanged views.

| Check | Status | Command or reason |
| --- | --- | --- |
| Logic and catalog: schema, bindings, search, navigation, controller, list, wizard, copy | passed (10 files, 89 tests) | `node --test tests/quickshell/settings-*.test.mjs tests/quickshell/config.test.mjs tests/quickshell/plugin-manifest.test.mjs` (110 tests in total, 110 passed, 0 failed when this was written; `settings-widget-flow.test.mjs` was added by parallel work) |
| Catalog copy (Uk/En pairs, length, allow-list) | passed (7 tests) | `node --test tests/quickshell/settings-copy.test.mjs` |
| Config and plugin-manifest regression | passed (21 tests in `config.test.mjs` and `plugin-manifest.test.mjs` together) | the same command as in the first row |
| All QML files in `features/settings/`, `SettingsController.qml`, `SettingsWindow.qml`, `IpcBridge.qml` | unverified | no graphical run: Quickshell was not launched |
| `tests/settings-*.qml` | unverified | a run needs Quickshell |
| Visual match to the three reference images (A, B, C) | unverified | needs an isolated headless harness and a human review |
| Keyboard, focus, a narrow window (<720) and 200% scale | unverified | the same |
| IPC `settings` on a live shell | unverified | live IPC is off limits to automated checks |

## Known gaps

- Restore works only after a checkpoint in the same session: checkpoint identifiers live in the controller's memory. `config.restore` errors are not shown to the user.
- The "Shortcuts" page is a read-only view; its values come from the catalog, not from the real bindings, so they may drift apart.
- The `session` keys come from `defaults/session.json` (`showMediaOnLock`, `showWeatherOnLock`, `preferredPlayerId`), because `parseDocument` has no branch for `session`: session values do not go through meaningful validation in `commitCheck`.
- The control-center list (`controlCenterItems`) shows element ids; widgets take their name from the manifest and fall back to the id only without a manifest.
- `settings-flow.mjs` has no `finish` and is not used by QML since the wizard was replaced by the sheet.
- The original verification table does not cover all graphical behavior; see the timer coverage above.
