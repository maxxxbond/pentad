# Widgets: visual rules

A widget is described by `quickshell/widgets/<name>/manifest.json` (schema and validation live in `quickshell/logic/plugin-manifest.mjs`, `apiVersion: 2`) and draws its QML `entry` file. `allowedSlots` decides where it can be placed: on the bar (`navigation`, `telemetry`, `center`, `tools`, `system`) or inside the side panels (`sidebar-left`, `sidebar-right`). A widget in a panel slot is rendered inside the panel's surface, so it has to look like the rest of that surface: the same icons, sizes, radii and animations. What follows is what that means for an author.

## Sections (pentads), placement and frame

Pentad splits the layout into five sections: `left-menu`, `left`, `center`, `right` and `right-menu` (left menu, left section, center, right section, right menu). A new or updated widget declares a `pentads` array in `manifest.json`: unique, non-empty, known ids only. Old manifests without `pentads` stay valid (`validateManifest(m, { requirePentads: true })` requires the field); all built-in widgets already have it. Setting keys that start with `_` are reserved by the framework.

The framework adds two blocks to every widget's settings page (`widgetSettingsPage` in `quickshell/logic/widget-settings.mjs`):

- **Placement**: the sections the widget is active in (at least one always stays enabled) and, for each active section, `Position` 1–9 and `Size`: Icon/Row/Tile for menus, Icon/Label/Full for bar sections.
- **Frame** (the "General" tab): outer margin 0–16 and inner padding 0–12 in steps of 4, background None/Subtle/Solid, and a scaled preview. The inner radius is `Metrics.radiusCard − margin`.

The values are stored in `layout.widgets[i].settings` under the keys `_zones`, `_margin`, `_padding`, `_bg`, `_order_<section>` and `_size_<section>`. They are checked by `validatePlacementSettings` (`quickshell/logic/pentads.mjs`), `config.mjs` and `validateSettings`, and applied by `logic/placement.mjs` (`placementsForSlot`): `BarSlot`, `SidebarView` and `RightPanel` show the widget in the slot of its first allowed section, order widgets by `_order_*`, add the outer margin and inner padding (`WidgetSurface` draws the `subtle`/`solid` background) and pass the `placementZone` and `placementSize` fields in `context` (widgets may take them into account). The default frame values are neutral (0 / 0 / `none`), so a widget with no stored keys looks the same as before; without `_zones` the old `slot` applies.

### Section-to-slot mapping

The single source of truth is the `zoneSlots` table in `quickshell/logic/pentads.mjs`.

| Section | Slots (`allowedSlots`) |
| --- | --- |
| `left-menu` | `sidebar-left` |
| `left` | `navigation`, `telemetry` |
| `center` | `center` |
| `right` | `tools`, `system` |
| `right-menu` | `sidebar-right` |

The split of `navigation`/`telemetry` (left section) and `tools`/`system` (right section) is settled; change it only by editing the rows of this table. `validateManifest` checks through it that `pentads` and `allowedSlots` agree: every section has at least one slot in `allowedSlots`, and every slot is covered by some section.

## Icons

- **SVG only, through `PentadIcon`.** Symbols (`› × ✓ + ●`) and font ligatures are not allowed as icons; an icon-only button is `PentadButton { iconSource }` with a localized `accessibleName`.
- **One set: Google Material Symbols Rounded, filled (FILL=1), optical size 20 px.** Take icons from the pinned packs, where every file has an upstream URL and a SHA-256 in the neighboring `sources.json`:
  - `assets/icons/material/controls/`: toggles, network, session, editing (wifi, bluetooth, flight, dark_mode, lock, power_settings_new, edit, add, remove, check…);
  - `assets/icons/material/media/`: media and navigation;
  - `assets/icons/material/screenshot/`: screenshot editor tools;
  - `assets/icons/material/tools/`: the panel tool catalog (data_object, straighten, qr_code_2, chat_bubble, extension, star, folder_open, input).
- **The root of `assets/icons/material/` is mixed** and is not a source for new widgets: it holds both the bar's filled icons and original Pentad outline drawings (bell, cross, sun, shield, moon, bed…) approved for the bar only. An outline icon next to filled ones is the same flaw that was fixed in the control center.
- `assets/icons/fluent/` and `assets/icons/tabler/` are not used for new widgets (Tabler stays with the bar telemetry).
- Two different actions in one list do not share an icon.
- Size is only a `Metrics` role (`panelIcon` 16, `statusIcon` 20, `menuActionIcon` 24, `menuIcon` 26), never a number at the call site.

**To add an icon**: put the unmodified upstream file `symbols/web/<name>/materialsymbolsrounded/<name>_fill1_20px.svg`, from the revision named in the pack's `sources.json`, into the right pack and add its `file`, `url` and `sha256` there. The license is already in the repository (`LICENSES/material-symbols-Apache-2.0.txt`); add a note about the new icon to `docs/third-party/material-symbols.md`.

## Other things shared with the surface

- **Shape:** surfaces from 24 px up use `ContinuousSurface` with a `Metrics.radius*` token; round buttons and capsules use `Rectangle { radius: Math.min(width, height) / 2 }`. A nested element has radius `R − inset`. Numeric radii are not allowed.
- **Motion:** every `duration` is a `Motion` token (`press` 60, `state` 140, `reveal` 200, `short` 160, `medium` 240, `long` 320); an animation without a duration is not allowed. Tokens become 0 under reduced motion.
- **Typography:** the roles are `textBody` 14 (titles, values), `textCaption` 12 (state, metadata) and `textSection` 16; numbers use tabular digits.
- **State:** "on" is shown by an accent fill with `onAccent` ink, not a translucent tint; unavailable is dimmed (opacity 0.58) and does not react to hover.

## Verification

`tests/quickshell/control-center-icons.test.mjs` checks the pack hashes and keeps Fluent icons and outline SVGs out of the control center and widgets. `tests/quickshell/ui-contract.test.mjs` catches symbol icons and literal durations, and `tests/quickshell/corner-contract.test.mjs` catches numeric radii. Check a widget's look in an isolated harness (`node scripts/test-quickshell-headless.mjs --scenario …`), not on your desktop.
