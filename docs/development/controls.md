# Quickshell control standard

The implemented core consists of independent capability definitions, service state, templates and placement. The full menu editor remains a later step.

Visual rules for widget authors (icons, shape, motion, typography) are in [widgets.md](widgets.md).

## Capabilities and state

`logic/control-model.mjs` holds the registry of definitions. `controlDefinition(id, { label, icon })` returns an independent copy of a definition. Capabilities combine: `primary` is a named command, `toggle` switches, `choice` selects by a stable ID, `range` is a range with a step and a unit, and `details` gives access to an expanded interface. `lifecycle` sets the state names and the allowed commands; the number of states is derived from the array. Recording supports `idle → record.start` and `recording → record.stop`; pause would need separate service support.

`PentadControl` receives `definition`, `controlState`, `presentation` and an optional `popupManager`. State comes from the service: `available`, `active`, `pending`, `error`, `unavailableReason`, `subtitle`, `value`, `confirmedValue`, `choices`, `selectedId` and `lifecycleState`. The component emits `commandRequested(action, value)`, `detailsRequested()` and `contextRequested()`. The function-block adapter routes them to the existing service methods. The layout contains no executable code.

Bluetooth uses independent toggle and details targets. Audio combines mute, level and device selection by device ID. Unavailability or pending state blocks a discrete command; details and context stay available. A change of appearance does not change service state. A slider's confirmed value is separate from the requested one; a passive update does not send a command.

## Interactions

**Less text:** keep short action names, the values that are needed and important state. Move extra explanation into passive tooltips on hover and keyboard focus, or behind a small `?` button next to the control it explains. Reuse an existing tooltip; if there is none, build it when moving the explanation. The `?` button opens the explanation on click and from the keyboard, has an accessible name and a comfortable hit area. Required input hints, significant consequences of an action and errors stay visible where needed.

`PentadInfoButton` takes `helpText` and a meaningful `accessibleName`: it shows a tooltip on hover or focus and opens an explanation bubble on click or from the keyboard. Escape and a press outside the explanation close it. The bubble sits above the `?` (below it when there is no room) with a tail on the button, stays inside the window, and balances wrapped text across its lines. On the light theme it is dark ink; on the dark theme it is `surfaceOverlay` with the overlay shadow. While it is open the `?` becomes an accent dot. Two optional parts: `helpMedia` puts a clip or image above the text (`helpMediaRatio`, 16:9 by default; mp4, webm, mkv, mov and ogv loop muted through `PentadHelpVideo.qml`, anything else is an `AnimatedImage` that stays still with reduced motion), and `helpActionText` adds one capsule action under the text, which opens `helpActionUrl` externally when it is set (with the open-in-new mark), emits `helpActionTriggered()` and closes the bubble. Action text is user-visible, so pass it as a `services.text()` pair. Extra help for a `PentadMenu` item is set through `entries[].description`; it is available in the tooltip and in the description for assistive technology.

| Area | Left click / keyboard | Right click / Menu / Shift+F10 | Scroll |
| --- | --- | --- | --- |
| Primary button | Primary action; for a toggle, switching | Compact context with extra actions or appearance | Does not trigger a discrete action |
| Details arrow | Opens the expanded control | The element's context | No action |
| Slider | Absolute value by click or drag; native Slider keys | The element's context | Relative change by step; fractional deltas accumulate |
| Device selector | Choose from the list by ID | The element's context | On the bar, the existing output-switching gestures are kept |
| Statistic element | Expanded data, if provided | Per the widget's contract | Per the widget's contract |
| Bar status indicator with discrete states | Primary action, or the next state when there is nothing else to do | The full list of states, the current one marked; choosing applies it by ID | Steps through the states, one per notch, wrapping around |

### Bar status indicators

A status indicator on the bar is informative at rest: it shows the current state itself (the layout code, the device's icon, the charge level), not a generic glyph, and its tooltip names that state in full. When the state is one of several discrete values, **scroll over the indicator switches between them**. This is the bar's standard gesture for such indicators, not a per-widget exception, and new indicators follow it:

- Scroll up moves to the next state, scroll down to the previous one; the list wraps around. Fractional touchpad deltas accumulate into whole notches, and leaving the indicator drops the remainder.
- The next notch counts from the state already requested, so fast scrolling does not wait for the service's confirmation. The indicator shows the requested state at once and falls back to the reported one if no confirmation arrives.
- While scrolling, the tooltip reveals the new state in the scroll direction, without waiting for the hover delay.
- Right click, Menu or Shift+F10 opens an `AttachedPopover` with every state; the current one is drawn as `checked`. Choosing closes the popover and applies the state.
- Left click, Space and Enter run the primary action (mute for audio). An indicator without one moves to the next state.
- An indicator with a single state stays visible and informative but does not react to scroll or clicks.

Implemented by the keyboard layout (`features/bar/KeyboardLayoutIndicator.qml`) and the audio output and input (`features/bar/StatusCluster.qml`: left click mutes, scroll and the right-click list switch the device).

#### States of a bar element

Every element on the bar is in exactly one of these states, and only one layer is drawn above the bar at a time:

| State | Entered by | Drawn above the bar |
| --- | --- | --- |
| Rest | Default | Nothing; the element itself shows the current state |
| Hover | Pointer over the element, after the tooltip delay | The passive tooltip |
| Feedback | Scroll or left click that changed the state | The tooltip at once, held for a moment after the pointer leaves |
| Open | Right click, Menu, Shift+F10, or a click whose action is to open | The popover; no tooltip |

An open popover wins over every tooltip of the same bar, including one held by feedback: `PentadToolTip` checks the popup manager and stays hidden while any popover owned by the bar's window is open, so a left click followed by a right click never leaves the tooltip on top of the list. A held feedback tooltip is dropped when the popover opens; after it closes, a tooltip appears again only while the pointer is over an element.

Hover shows only a passive tooltip. A dropdown opens on click or from the keyboard; moving the cursor from the trigger to its content keeps the menu open, and leaving both the trigger and the menu with no button pressed closes it within at most 300 ms. Closing pauses during a drag; if the button is released outside the menu, the menu stays open until the cursor returns. Tray-menu submenus open to the right on hovering an item that has child actions. If the cursor moves through a triangular corridor toward an open submenu, switching to a neighboring item waits for the rest of the same 300 ms limit; leaving the corridor allows an immediate switch. Hovering again does not renew the wait. Keyboard focus alone does not close a menu: Escape closes the deepest level, and the next Escape returns to or closes its parent level. Closing the owner closes the whole submenu branch. Primary drawer surfaces do not close on hover; sliders, forms and passive hover details have their own policy and do not inherit automatic menu closing. On the bar, primary actions run with a left click. The context menu shows state without duplicating the toggle, the screenshot or record start/stop; the screenshot keeps an extra color-picking action. The content is at least 192 px wide, and the title and state are shown on one line. Unavailable actions do not run.

## Templates and cells

`icon`, `compact`, `tile`, `row`, `range-horizontal` and `range-vertical` are allowed only for compatible definitions. `MenuGrid` places visible elements first-fit in a grid of 3, 4 or 6 columns (`layout.controlCenter.columns`; without the field, 4, as in old saved layouts), and in two columns in a narrow container; span widths are limited by the container. Identity is determined by `instanceId`, and state is kept by the service. Templates with text take at least half a line; an icon takes one cell.

At rest, a line of equal-height elements that has free cells stretches them proportionally (`layoutMenu(..., { fill: true })`), so the grid shows no holes; lines crossed by a taller element stay as they are. In edit mode the real sizes and the free cells are visible.

```json
{
  "version": 1,
  "columns": 6,
  "items": [
    {
      "instanceId": "bluetooth",
      "definitionId": "bluetooth",
      "template": "tile",
      "columnSpan": 2,
      "rowSpan": 2,
      "visible": true
    }
  ]
}
```

This description is stored in `layout.controlCenter`. The current control-center adapter accepts network, bluetooth, vpn, energy, airplane, inhibit, night, dnd, appearance (dark theme, stores `theme.appearance`) and screenshot (closes the panel and opens the screenshot editor). Adding another definition needs an adapter for its commands and state; a definition's presence in the registry does not by itself add a feature to the panel. `validateMenuLayout` checks the version, unique IDs, template compatibility, minimum and maximum spans, and the absence of foreign fields, without mutating its input.

### Grid editor

The pencil in the header (or "Edit grid" in the right-click menu) turns on editing. Above the grid appear a 3 / 4 / 6 column switch, "Reset" and "Done"; below the grid are the hidden elements, which come back with one press. Each element can be dragged (the others smoothly make room), pulled by the corner handle to resize in whole cells, or hidden with the "−" button. The appearance is derived from the size, like Android widgets (`templateForSpan`): one cell is a round button, from half a line it is a row with state, and from half a line and two rows it is a tile. Changing the number of columns recalculates the spans (`rescaleMenu`) while keeping the appearance: the smallest size of a class and a full line move to the same class, the rest scale, so 6 → 3 → 6 restores the same layout.

Keyboard: Tab moves between elements, the arrows reorder them, Shift with the arrows resizes, Delete hides, Enter or Escape finishes. All changes go into a draft; the config is written once, when editing ends (by the pencil, "Done", closing the panel or opening details), and only if the layout changed.

Brightness, volume and microphone are the same kind of grid element (`levelControlIds`): they can be dragged, hidden and resized. One row is a horizontal slider (from half a line); from two rows it is a vertical capsule (from one cell) that fills from the bottom: the icon and mute at the bottom, the value at the top, and the device-selection chevron only in a capsule of three rows or more. Right click on volume or microphone switches "Horizontal" (full line) / "Vertical" (1 × 3). Layouts saved before this get the missing sliders at the end (`withLevelControls`); `layout.audioPresentation` remains a valid key but no longer affects the appearance.

Right click on a control-center element lets you keep a compatible appearance and size in cells. The top, middle and bottom areas of the right menu keep the current height distribution; a builder will be able to use the same validator and renderer.

## Geometry diagnostics

Right click on a quick-settings card → **Geometry diagnostics**. From the keyboard, the context menu opens with Menu or Shift+F10 on the card. The switch applies only for the current session; turning it off removes all labels. The overlay does not take input and does not change the layout.

Currently the nested round Wi-Fi, Bluetooth and VPN buttons in the `row` template are wired in. This is a targeted check of nested geometry, not an automatic audit of the whole UI tree. Other components can be connected through `GeometryOverlay` with the actual inner rectangle, two radii and the curve types. For `ContinuousSurface`, the real `contour` is passed.

Labels: the card's size, `Ø` of the inner button, `r` outer/inner radius, `p` top/bottom/side inset. An accent outline means consistent, red means a violation, muted means `unverified` because of incomplete data. Codes: `radius-mismatch`, `unequal-insets`, `curve-mismatch`, `outside`. On a long card, only the three open sides of the circle are compared; free space for text is not counted as an inset. The tolerance is 0.5 logical px. Different curve types are flagged even with equal numeric radii.

In the short labels, `r≠`, `insets≠` and `curve≠` correspond to these violations; the arrow after the radii shows the expected inner radius. A pure check without launching the shell: `node --test tests/quickshell/geometry-diagnostics.test.mjs`.

## Segmented control

`PentadSegmented` is the one segmented control and tab switcher: a capsule track with a lighter thumb that slides to the selected segment. Segments have equal width; `implicitWidth` fits the widest label (at least 96 px per option, 160 overall) and `height` defaults to `Metrics.controlMedium`.

```qml
PentadSegmented {
    accessibleName: "Range"
    options: [{ value: "day", label: "Day" }, { value: "week", label: "Week" }]
    value: settings.range
    onActivated: function(v) { settings.saveRange(v); }
}
```

- `options` is `[{ value, label, icon? }]`. The host owns the state: `value` selects the segment and `activated(value)` reports a request; the control never changes `value` itself.
- For page tabs set `activateOnPress: true` (the segment commits on press instead of on release) and `tabList: true` (the control reports `PageTabList` and the segments `PageTab` instead of radio buttons). `segmentObjectName: "tab-"` names the segments `tab-0`, `tab-1`, ... for tests; `indicator` is the thumb and `segments` the segment `Repeater`.
- Keyboard: arrows move the focus ring (reversed in RTL), Home and End jump to the ends, Space and Enter select. The ring shows only after keyboard use.
- Colors come from the theme (`surface` track, overridable with `fill` where the control sits on a `surface` background, `surfaceOverlay` thumb, `text` for the selected label, `textMuted` for the others); the thumb animation respects reduced motion.

## Toggle

`PentadToggle` is a shared component built on `QtQuick.Controls.Basic.Switch`. The track is 44 × 26 px with a round handle, and the interactive height is 36 px. It supports click, Space, drag, RTL, focus and reduced motion. Without `text` it shows only the toggle; in that case always set `accessibleName`.

```qml
PentadToggle {
    text: "Keep awake"
    accessibleName: text
    checked: settings.keepAwake
    requestedEnabled: settings.writable
    pending: settings.saving
    error: settings.error !== ""
    onToggled: settings.saveKeepAwake(checked)
}
```

`pending` blocks repeated input and shows an indicator in the handle. `requestedEnabled: false` dims the toggle; `error` adds an error outline. Commands and confirmation stay with the caller. For asynchronous system commands, use `onClicked` and a `checked` binding that becomes active when the request completes, as in `QuickSettingsDetails.qml`: an error returns the confirmed state. The accent color comes from the theme. The visual reference is a Material-like switch; the implementation uses Pentad's own components and tokens.

## Attached surfaces

`AttachedPopover` takes `anchorItem` and optional `barItem`, `manager` and `contentItem`, and provides `open()`, `close()`, `toggle()`, `opened`, `surface` and `window`. The content sets `implicitHeight` and a width or `implicitWidth`. For a Column an explicit width is enough: the height is taken from its content automatically. Fill in only the rows you need; context buttons are 28 px high with a 4 px gap.

The fill of an open trigger and of the surface is shared. The outline uses continuous corners and a neck to the actual trigger, including the shift near a screen edge. `SurfaceRegion` excludes transparent parts from the input region. Passive tooltips on the bar use the same `surfaceGeometry` from `continuous-corners.mjs`: continuous concave shoulders to the lower edge of `BarFace` and continuous lower corners, with no sharp vertices; the 16 px shoulders and corners shrink proportionally to fit the preset's height (for 28 px, 14 + 14 px); a short `Discord` tooltip is about 96 × 28 px, and a title with details grows with its content. Interactive menus attached to a real `BarFace` use the attached-surface contract: 32 px concave upper shoulders and 32 px continuous lower corners from `continuous-corners.mjs`, straight sides between them and 16 px inner padding. The outline of a short passive tooltip is not stretched to the height of a menu. Tooltips and interactive `AttachedPopover`s away from the bar keep the outline with a neck. `PentadToolTip` sizes itself by text with a width limit, supports a second line and is transparent to input. The outline and text animations respect reduced motion.

## Verification

Telemetry uses the shared `AttachedPopover`. The content in `TelemetryDetails` is made of circular indicators with no square backing and no repeated popups. The name and percentage of CPU/GPU/RAM sit inside the circle; compact RAM/VRAM data is under it. GPUs are labeled briefly (`GPU 0`, `GPU 1`), and the full details stay in the accessible name. Network has just two lines with arrows and compact speeds (`↓16K/s`, `↑15K/s`), with the name under the circle; full units are available through accessibility. Four metrics use two columns, five or more use three. An incomplete last row is centered, and circles do not stretch. The base circle diameter is 76 px, the cell is 80 × 96 px and the gap is 8 px. Labels support Ukrainian and English. Missing values are shown as "—" with an empty indicator, not as zero. Polling is once a second, and indicators persist between measurements.

Passive tooltips appear after the cursor rests for `Metrics.tooltipDelay` (700 ms), the same in `PentadToolTip`, `PentadInfoButton` and `PentadMenu`; individual components do not set their own delay. While the shared bar tooltip is still visible, moving to a neighboring button shows it at once. The bar tooltip drops out from under the lower edge of `BarFace` and hides back the same way over `Motion.medium` with `Easing.OutCubic` in both directions: a sharp start and a smooth stop at the end; away from the bar, tooltips fade in. Reduced motion turns the animation off. Bar tooltips use fixed presets from `Metrics`: `compact` is 96 × 28 px, `label` is 160 × 28 px and `status` is 240 × 48 px. In `PentadToolTip`, `sizeMode: "auto"` picks the format before showing and holds it until fully hidden; a change of text does not rebuild the visible surface. `status` always reserves two 16 px lines, even if the second is empty. A long line is truncated within the set width. Sound, network and battery use `status`; sound also sets `animateContent: false`, so fast updates do not shift the text or wait in the animation queue. On a narrow screen the surface width is limited to the available space. Tooltips away from the bar keep a size by content.

`pentad.audio-mixer` is a reusable mixer of playback streams. In `sidebar-right` it is rendered through `PluginHost` under the shared audio controls; in `tools` and `system` it opens from an icon through `AttachedPopover`. `sidebar-left` is supported too. New configurations enable `mixer-main` in the menu; existing ones get disabled `mixer-main` and `mixer-bar` placements if no such placements exist yet. They can be enabled and moved in the layout editor.

One application can have several audio streams; each has its own level 0–100% and mute. Frequencies are not adjustable, and a link to a specific window or tab is not guaranteed. Native sliders persist across value updates by stream lifetime ID, so a state update does not interrupt a drag. The list is limited in height and scrolls. `retainMixer` / `releaseMixer` keep tracking only while at least one widget form is shown. The [service and placement contract](../../packages/widget-api/v2/README.md) describes the API in more detail.

Node tests check contracts, config migration and geometry. `control-templates` checks the native QML templates and adapters with fake services; `control-center` checks the integration of the current menu. `bar-visual` captures the QML content of a tooltip and checks the junction coordinates and both screen edges. The private KWin in that scenario provides no `grim` screencopy, so a capture of the shared bar-and-popup composition is unavailable; it is not replaced by a painted copy of the popup. Other graphical scenarios run in a private compositor and D-Bus. QtTest does not create a real Wayland input serial: checking a click outside a native popup needs a separate check with real input in a session.
