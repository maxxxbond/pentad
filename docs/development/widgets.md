# Widgets: visual rules

A widget is described by `quickshell/widgets/<name>/manifest.json` (schema and validation live in `quickshell/logic/plugin-manifest.mjs`, `apiVersion: 1`) and draws its QML `entry` file. `allowedSlots` decides where it can be placed: on the bar (`navigation`, `telemetry`, `center`, `tools`, `system`) or inside the side panels (`sidebar-left`, `sidebar-right`). A widget in a panel slot is rendered inside the panel's surface, so it has to look like the rest of that surface: the same icons, sizes, radii and animations. What follows is what that means for an author.

## Create an external widget

An external widget does not need a Pentad source change or a build step. Create a directory named `example.greeting` under `$XDG_CONFIG_HOME/pentad/plugins/` (or `~/.config/pentad/plugins/` when unset), containing these two files. Install only QML you trust: external widgets run with your user's privileges, not in a sandbox. Safe mode excludes external widgets.

`manifest.json`:

```json
{
  "id": "example.greeting",
  "name": "Greeting",
  "version": "1.0.0",
  "apiVersion": 1,
  "entry": "View.qml",
  "allowedSlots": ["sidebar-left", "system"],
  "pentads": ["left-menu", "right"],
  "defaults": { "message": "" },
  "settingsFields": [
    {
      "key": "message",
      "kind": "text",
      "label": "Message",
      "labelUk": "Повідомлення",
      "labelEn": "Message"
    }
  ]
}
```

`View.qml`:

```qml
import QtQuick
import qs.components

Item {
    id: root
    required property string instanceId
    required property var context
    required property var settings
    required property var services
    required property var controller

    implicitWidth: label.implicitWidth
    implicitHeight: label.implicitHeight

    PentadText {
        id: label
        anchors.centerIn: parent
        text: root.settings.message || root.services.text("Привіт!", "Hello!")
        textFormat: Text.PlainText
        role: "body"
    }
}
```

After your next shell start, add the widget through the layout editor. Discovery makes a widget available; it does not enable a placement automatically. Each placement has a unique `instanceId` and its own settings. For a manually edited layout, add an entry like this to the existing `widgets` array, preserving the other entries:

```json
{ "instanceId": "greeting-1", "moduleId": "example.greeting", "slot": "sidebar-left", "enabled": true, "settings": {} }
```

The host supplies all five properties and merges settings before loading the view. A controller is optional: `controller` is `null` when absent or not yet loaded. Use `qs.components` and `qs.theme` imports for shared UI; do not use relative paths into the Pentad source tree from an external widget. The [API reference](../../packages/widget-api/v1/README.md) covers tool inputs, services and validation, and the [external fixture](../../quickshell/tests/fixtures/external-widget/) demonstrates shared media access.

## Declare configuration once

Use `settingsFields` to declare editable values; the host generates their controls. Supported kinds are `text`, `integer`, `number`, `boolean`, `select`, and `color`. Numeric fields accept `min` and `max`; select fields require scalar `{ "value": ..., "label": "..." }` options. Keep a `label` fallback as well as `labelUk` and `labelEn`. The generated widget settings page uses the language pair; legacy forms use the fallback. `labelKey` alone is displayed as a key, not translated through the shipped catalogs.

Defaults have one precedence order everywhere: a saved placement value overrides `manifest.defaults`, which overrides a field's `default`. An empty string, `false`, or `0` is an explicit value. Prefer declaring each default in one place; give every setting the view needs a default. The runtime rejects undeclared keys, incorrect types and values outside bounds. Framework keys beginning with `_` are reserved for placement and frame settings.

Changing a default applies to placements that have not saved that value. It must not overwrite a user's saved choice. Renaming or removing an existing field needs a migration; otherwise old placements can fail validation. Keep state local to the view when it is disposable. Add a controller only for state that must be shared by the same placement across outputs: its initial properties are `instanceId`, `settings`, and `services`, and the host disposes it when the placement is disabled or removed.

Keep subscriptions and requests tied to visibility, including `context.presented` in menu hosts. Use existing service adapters instead of adding one system poller per view, honor preview/safe mode, and handle `starting`, `unavailable`, and `error` states as well as `ready`. QML logic must remain compatible with the Qt JavaScript engine; passing a Node test alone does not prove that an imported module loads in QML.

## Shared capabilities

A widget can use Pentad's shared functions, such as a chat model, embeddings, translation, OCR, barcode reading and PDF text, without knowing which backend runs them. Declare them in the manifest (`"capabilities": ["llm.chat", "image.ocr"]`) and call `services.capabilities` with the widget's `instanceId`. The user picks the models once in the [models document](models.md), the host reports where each call runs before any data leaves, and an external widget needs the user's grant to reach a remote model. The full contract (names, inputs, limits, routing, consent, preview and safe mode) is the [Capabilities section of the API reference](../../packages/widget-api/v1/README.md#capabilities); it is not repeated here. A `tool` block that declares `llm.*` or `text.embed` must have `execution: "ai"`.

Credentials stay out of settings. A text setting whose key looks like a credential holds only a `secret://` reference, with one exception: a key ending in `Env` (for example `apiKeyEnv`) may hold the upper-case name of an environment variable, such as `OPENAI_API_KEY`, never its value. Lower-case or mixed-case values are rejected.

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
- `assets/icons/keys/` holds Pentad's own glyphs for keycaps (the Super key's Pentad and penguin logos, see its `README.md`); they are not a general icon source.
- Two different actions in one list do not share an icon.
- Size is only a `Metrics` role (`panelIcon` 16, `statusIcon` 20, `menuActionIcon` 24, `menuIcon` 26), never a number at the call site.

**To add an icon**: put the unmodified upstream file `symbols/web/<name>/materialsymbolsrounded/<name>_fill1_20px.svg`, from the revision named in the pack's `sources.json`, into the right pack and add its `file`, `url` and `sha256` there. The license is already in the repository (`LICENSES/material-symbols-Apache-2.0.txt`); add a note about the new icon to `docs/third-party/material-symbols.md`.

## Other things shared with the surface

- **Shape:** surfaces from 24 px up use `ContinuousSurface` with a `Metrics.radius*` token; round buttons and capsules use `Rectangle { radius: Math.min(width, height) / 2 }`. A nested element has radius `R − inset`. Numeric radii are not allowed.
- **Motion:** every `duration` is a `Motion` token (`press` 60, `state` 140, `reveal` 200, `short` 160, `medium` 240, `long` 320); an animation without a duration is not allowed. Tokens become 0 under reduced motion.
- **Typography:** the roles are `textBody` 14 (titles, values), `textCaption` 12 (state, metadata) and `textSection` 16; numbers use tabular digits.
- **State:** selected controls use tonal elevation and foreground emphasis; accent marks foreground and small indicators, not a filled container. Unavailable controls are dimmed and do not react to hover. Reuse the shared controls for these states.

## Verification

`tests/quickshell/control-center-icons.test.mjs` checks the pack hashes and keeps Fluent icons and outline SVGs out of the control center and widgets. `tests/quickshell/ui-contract.test.mjs` catches symbol icons and literal durations, and `tests/quickshell/corner-contract.test.mjs` catches numeric radii. Check a widget's look in an isolated harness (`node scripts/test-quickshell-headless.mjs --scenario …`), not on your desktop.

From a source checkout, run `timeout 120 node --test tests/quickshell/*.test.mjs` for logic and contract checks. The `plugin-host` isolated fixture covers an external widget, generated settings, shared services and controller disposal. Add a fixture for your own widget's empty, normal, error and recovery states. Outside quiet mode, run it through `scripts/test-quickshell-headless.mjs` with a bounded timeout and a report under `/tmp`; the ordinary fixture runner alone does not isolate the compositor. Never use a running desktop as an automated test target.
