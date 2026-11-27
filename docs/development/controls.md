# Quickshell control standard

The implemented core consists of independent capability definitions, service state, templates and placement. The full menu editor remains a later step.

Visual rules for widget authors (icons, shape, motion, typography) are in [widgets.md](widgets.md).

## Capabilities and state

`logic/control-model.mjs` holds the registry of definitions. `controlDefinition(id, { label, icon })` returns an independent copy of a definition. Capabilities combine: `primary` is a named command, `toggle` switches, `choice` selects by a stable ID, `range` is a range with a step and a unit, and `details` gives access to an expanded interface. `lifecycle` sets the state names and the allowed commands; the number of states is derived from the array. Recording supports `idle → record.start` and `recording → record.stop`; pause would need separate service support.

`PentadControl` receives `definition`, `controlState`, `presentation` and an optional `popupManager`. State comes from the service: `available`, `active`, `pending`, `error`, `unavailableReason`, `subtitle`, `value`, `confirmedValue`, `choices`, `selectedId` and `lifecycleState`. The component emits `commandRequested(action, value)`, `detailsRequested()` and `contextRequested()`. The function-block adapter routes them to the existing service methods. The layout contains no executable code.

Bluetooth uses independent toggle and details targets. Audio combines mute, level and device selection by device ID. Unavailability or pending state blocks a discrete command; details and context stay available. A change of appearance does not change service state. A slider's confirmed value is separate from the requested one; a passive update does not send a command.

## Interactions

**Less text:** keep short action names, the values that are needed and important state. Move extra explanation into passive tooltips on hover and keyboard focus, or behind a small `?` button next to the control it explains. Reuse an existing tooltip; if there is none, build it when moving the explanation. The `?` button opens the explanation on click and from the keyboard, has an accessible name and a comfortable hit area. Required input hints, significant consequences of an action and errors stay visible where needed.

`PentadInfoButton` takes `helpText` and a meaningful `accessibleName`: it has no separate Qt tooltip. Resting the pointer on it for `Metrics.tooltipDelay`, or moving keyboard focus onto it, shows the explanation bubble passively: it takes no focus and closes when both the pointer and focus leave (the pointer may cross onto the bubble). A click or Space pins it and moves focus into it, so its action is reachable; Escape, a press outside the bubble and the `?`, or another click on the `?` close it. The bubble sits above the `?` (below it when there is no room) with a tail on the button, stays inside the window, and balances wrapped text across its lines. On the light theme it is dark ink; on the dark theme it is `surfaceOverlay` with the overlay shadow. While it is open the `?` becomes an accent dot. Two optional parts: `helpMedia` puts a clip or image above the text (`helpMediaRatio`, 16:9 by default; mp4, webm, mkv, mov and ogv loop muted through `PentadHelpVideo.qml`, anything else is an `AnimatedImage` that stays still with reduced motion), and `helpActionText` adds one capsule action under the text, which opens `helpActionUrl` externally when it is set (with the open-in-new mark), emits `helpActionTriggered()` and closes the bubble. Action text is user-visible, so pass it as a `services.text()` pair. Extra help for a `PentadMenu` item is set through `entries[].description`; it is available in the tooltip and in the description for assistive technology.

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

This description is stored in `layout.controlCenter`. The current control-center adapter accepts network, bluetooth, vpn, energy, airplane, inhibit, overnight (overnight mode, `services.overnight`; the default grid lists it hidden, so the editor offers it without filling a seventh round button), night, dnd, appearance (dark theme, stores `theme.appearance`) and screenshot (closes the panel and opens the screenshot editor). Adding another definition needs an adapter for its commands and state; a definition's presence in the registry does not by itself add a feature to the panel. `validateMenuLayout` checks the version, unique IDs, template compatibility, minimum and maximum spans, and the absence of foreign fields, without mutating its input.

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

`PentadSegmented` is the one segmented control and tab switcher: a capsule track with a lighter thumb that slides to the selected segment. Segments have equal width; `implicitWidth` fits the widest label (at least `segmentMinimumWidth` per option, 96 px by default, and 160 overall) and `height` defaults to `Metrics.controlMedium`. A host that wants short labels to stay compact, such as a settings row, lowers `segmentMinimumWidth`. The track and the thumb are true capsules (`ContinuousSurface { capsule: true }`).

```qml
PentadSegmented {
    accessibleName: "Range"
    options: [{ value: "day", label: "Day" }, { value: "week", label: "Week" }]
    value: settings.range
    onActivated: function(v) { settings.saveRange(v); }
}
```

- `options` is `[{ value, label, icon? }]`. The host owns the state: `value` selects the segment and `activated(value)` reports a request; the control never changes `value` itself.
- Optional per option: `iconOnly: true` shows just the `icon` (the `label` still names the segment for assistive tech and in a `PentadHint` on hover; give such a control an explicit `width`); `marked: true` puts a small accent dot after the label; `description` becomes the segment's accessible description (say there what the mark means).
- For page tabs set `activateOnPress: true` (the segment commits on press instead of on release) and `tabList: true` (the control reports `PageTabList` and the segments `PageTab` instead of radio buttons). `segmentObjectName: "tab-"` names the segments `tab-0`, `tab-1`, ... for tests; `indicator` is the thumb and `segments` the segment `Repeater`.
- Keyboard: arrows move the focus ring (reversed in RTL), Home and End jump to the ends, Space and Enter select. The ring shows only after keyboard use.
- Colors come from the theme (`surface` track, overridable with `fill` where the control sits on a `surface` background, `surfaceOverlay` thumb, `text` for the selected label, `textMuted` for the others); the thumb animation respects reduced motion.

## Wheel picker

`PentadWheelPicker` is a set of drums behind one selection band, for picking a time or any short list by turning it. `columns` is a list of `{ id, label, options, loop, width }` (width defaults to 64); `value` maps a column id to its chosen option string; `edited(column, option)` reports what the user picked. A looping column wraps (hours, minutes); one that does not stops at its ends with a small rubber band (AM/PM).

```qml
PentadWheelPicker {
    accessibleName: "Alarm time"
    columns: [
        { id: "hour", label: "Hour", options: hours, loop: true },
        { id: "minute", label: "Minute", options: minutes, loop: true }
    ]
    value: ({ hour: settings.hour, minute: settings.minute })
    onEdited: (column, option) => settings[column] = option
}
```

Drag, flick, mouse wheel, a tap on a row, and the keyboard (Up/Down, PageUp/PageDown, Home/End) all work. A change of `value` from outside turns the drum, the short way round a loop, and sends no `edited`. The focus ring is for keyboard focus only. With reduced motion every change lands at once. A drum that is hidden or at rest runs no frames. `PentadWheelColumn` is the single drum, for a layout that needs one. The maths is `logic/wheel-picker.mjs`; the motion follows [Kokonut UI's wheel picker](../third-party/kokonutui-wheel-picker.md).

## Section header

`PentadSectionHeader` is the one header above a group of rows or cards: a `textCaption` line in muted ink, an optional count badge after it and optional trailing content on the far side. The component never changes case; the caller passes the text as it should read.

```qml
PentadSectionHeader {
    width: parent.width
    text: services.text("Нещодавні", "Recent")
    count: recent.count          // -1 (the default) hides the badge
    PentadButton { text: services.text("Очистити", "Clear"); controlHeight: Metrics.controlSmall; onClicked: recent.clear() }
}
```

- Children become the trailing content, laid out in a row at the end. A long label elides before it pushes the badge or the trailing content out.
- Accessible role `Heading`, named by `text`; the count is its description. RTL mirrors the order.

## List row

`PentadListRow` is the one interactive row in a list: an optional icon, a title over an optional subtitle and an optional trailing slot. The title and subtitle are a solid stack told apart by size and colour, not by a gap.

```qml
PentadListRow {
    width: parent.width
    iconSource: Qt.resolvedUrl("../assets/icons/material/wifi-symbolic.svg")
    title: network.name
    subtitle: services.text("Підключено", "Connected")
    onActivated: network.openDetails()
    PentadToggle { accessibleName: network.name; checked: network.enabled; onToggled: network.setEnabled(checked) }
}
```

- At least `Metrics.settingsRowMinHeight` (44) tall; a subtitle or a tall trailing control grows it in steps of 4. Title and subtitle elide inside the row.
- Click, Space and Enter emit `activated()`. A trailing control that takes the press keeps it, so its click does not also activate the row.
- Nothing is drawn at rest; hover and press lay the ink over the row at `Metrics.stateHover` and `Metrics.statePressed`. The focus edge shows only after keyboard focus. Accessible role `Button`, named by `title`, described by `subtitle`.
- Children become the trailing content. In RTL the icon moves to the right and the trailing slot to the left.

## Chip

`PentadChip` is the one filter or choice chip: a capsule `Metrics.controlSmall` tall with a label and an optional count. Selected is tonal elevation, a brighter medium-weight label and an accent check mark, never an accent fill.

```qml
Flow {
    spacing: Metrics.space1
    Repeater {
        model: filters
        delegate: PentadChip {
            required property var modelData
            text: modelData.label
            count: modelData.count     // -1 hides it
            checked: view.filter === modelData.id
            onToggled: view.setFilter(modelData.id)
        }
    }
}
```

- The host owns `checked`: click, Space and Enter only emit `toggled()`. Do not set `checkable`.
- A chip given less width than it needs elides its label and keeps the count. Accessible role `CheckBox` with the checked state.
- `removable: true` makes the chip an active filter the user can drop: it looks selected, ends in a close mark instead of leading with the check, and `toggled()` means "remove". Name it for assistive tech with what it removes (`Accessible.name`).

## Keycap

`PentadKeycap` is the one drawn key: a key legend that looks like a physical key seen from above and a little in front. A raised face, lighter than the surface, with a soft vertical gradient and a 1 px highlight along its top edge, stands on a darker lip, so it reads as raised in both themes; a large key can sculpt the face inside the cap's walls. It is not a control: it takes no input and no focus. The cheatsheet's rows and keyboard map and the submap hint use it.

```qml
Flow {
    spacing: Metrics.space1
    Repeater {
        model: bind.keys
        delegate: PentadKeycap {
            required property string modelData
            required property int index
            text: modelData
            size: 24                                  // the height, lip included
            width: Math.min(column.keyWidth, measured(modelData))
            hue: index === bind.keys.length - 1 ? group.hue : "transparent"
            base: card.fill                           // the surface it stands on
        }
    }
}
```

- `text` is a centred `textCaption` legend in medium weight, plain text, wrapping anywhere when the width is short (the key then grows taller). Give the keycap an explicit width measured from the font; its implicit size fits the legend.
- `icon` draws a symbolic SVG (`PentadIcon`, `iconSize` px, 60 % of `size` by default) on the face in place of the legend, in the legend's colour; the cheatsheet and the submap hint use it for the Super key's logo. `text` still names the key, and the icon is only built when it is set.
- `hue` (transparent by default) colours the legend, in demibold, and tints the face (`hueTint`, 14 % by default) and the lip of a raised key; `hueInk` (the hue by default) is the legend's colour on such a key, for a host that tints more strongly and needs a lighter legend. It is for categorical colour such as the cheatsheet's group hues, never the accent: the face stays a surface tone, so a hue never floods the key.
- `lip` (2 by default) lies inside the height: changing `look` never moves the layout. `base` is the colour the key stands on; the lip of an unsculpted key is a shade of it, so pass the card or surface behind the key.
- `inset` (0 by default) sculpts a large key: the face sits that far inside the skirt's sides and half as far below its top, so the skirt shows as a lit back wall, side walls and a shaded front lip, all shades of the cap's own face. The skirt's corners are then `radiusMedium`, the face's `radiusSmall`. `lifted` raises a sculpted face by a pixel, for hover. Keep 0 for small keys: the 24 px keycaps of lists stay a face over a lip.
- `look` is `raised` (the default), `quiet` (a free key: the same shape, a dimmer face and a muted `textMuted` legend) or `pressed` (a held key: the selected tone, an inner shade along the top, the face lowered by the lip so the lip is gone, in a darker skirt).
- `stateLayer` lays the foreground over the face at the usual state strengths (`Metrics.stateHover`, `Metrics.statePressed`) for a host that makes the key interactive. `face`, `legend` and `topInset` are exposed; `ink` is the legend's colour for a host that draws its own legends. Children declared inside a keycap sit on its face and move with it when it is pressed.
- Colours come from the theme tokens only (tints and shades of `surface`, `surfaceOverlay`, `text`). The face and the skirt are two rectangles under one text (or one icon), with no layer effect, so long lists of keycaps stay cheap; only a keycap with an `icon` adds the icon's tint.

## Empty state

`PentadEmptyState` replaces a bare line of grey text where a list or panel has nothing to show: a centred muted icon, one muted line and, when `actionText` is set, one capsule action.

```qml
PentadEmptyState {
    anchors.fill: parent
    visible: stash.count === 0
    iconSource: Qt.resolvedUrl("../assets/icons/material/stash/sticky-note-2-symbolic.svg")
    text: services.text("Перетягніть сюди файли, посилання або текст", "Drop files, links or text here")
    actionText: services.text("Додати файл", "Add file")
    onActionRequested: stash.pickFiles()
}
```

- The line wraps inside the component when the space is narrow; it never widens its parent. Keep it to one short sentence; it is not a place for instructions.
- The action uses the `surfaceOverlay` fill, so it stays visible on a raised panel. `actionButton` exposes it for tests and focus chains.

The `design-system` fixture shows all four in their states (with and without count, subtitle, icon, trailing content and action; long Ukrainian text; RTL) and checks their activation and that they fit their space.

## Toggle

`PentadToggle` is a shared component built on `QtQuick.Controls.Basic.Switch`. The track is 44 × 26 px with a round handle, and the interactive height is 36 px. It supports click, Space, drag, RTL, focus and reduced motion. Without `text` it shows only the toggle; in that case always set `accessibleName`.

The empty track is a layer of the foreground (`Metrics.trackRest`) over whatever is behind the toggle, so it reads on a card, on a popover and on the bare surface alike, and it fills with the accent as the handle travels. Hover lays `Metrics.stateHover` over the track, a held handle widens by 3 px towards the middle of the track, and a disabled toggle drops to `Metrics.stateDisabled`.

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

## Dropdown

`PentadComboBox` is the one dropdown: a borderless capsule with the chevron in a round well, built on `QtQuick.Controls.Basic.ComboBox`, so `model`, `textRole`, `valueRole`, `displayText`, `currentIndex` and `activated` work as in Qt. Its list moves on springs (`dropdownSprings` in `quickshell/logic/spring.mjs`, the stiffness and damping of the motion study it was drawn from): the list drops out on a height spring that overshoots once, the rows of the first screen fall in one after another, one highlight stretches between rows with a stiff leading edge and a soft trailing one, and a pick draws the check, rolls the new value into the box and folds the list away. Every close folds: a pick waits 240 ms for the check first; Escape, a press outside and a second click on the box fold at once. A host's change at rest lands without motion, and reduced motion lands every change at once.

Closing starts at once: `popup.opened` and `listOpen` turn false on the first frame, and that is what tests and hosts should read. `popup.visible` stays true while the list folds away (Qt keeps a popup visible during its exit), and a folding list takes presses over it without picking. A click on the box while the list folds opens it again from where it is. The box keeps the keyboard focus while the list is open, so Up, Down, Enter, Space and Escape act on the list.

With a `textRole`, an entry may also carry `marked: true` (a small accent dot after its text in the list) and `description` (the row's accessible description), as `PentadSegmented` options do, so a segmented control that falls back to a dropdown keeps its marks.

A custom `delegate` leaves its `background` empty, since the moving highlight marks the row, and takes the fall with `opacity: box.rowLevel(index)` and `transform: Translate { y: box.rowDrop(index) }`; its picking `MouseArea` sets `enabled: box.listOpen`. `AudioDeviceSection.qml` is the example.

`PentadSpringDropdown` is the same motion as a standalone status picker for an array of `{ text, color }`, with a coloured dot per entry. With `keepCentred` the trigger and its menu lift by half the menu so the pair stays centred where it sits. Its menu covers the window with a press catcher, so every close animates. The `combo-motion` and `spring-dropdown` fixtures drive both through keyboard, pointer, a press outside, Escape and reduced motion.

With `fitContent` the box is as wide as its longest choice (never under 96 px) instead of the fixed 160 px, so a host that lets controls keep their own width, such as a settings row, gets a dropdown that fits what it says.

## Fields

`PentadTextField` is the one text field: a borderless 6 px rectangle that takes the tonal level its host names with `fill`. Its line of text is centred in the whole height, so a field as short as `Metrics.controlSmall` (28) keeps its text level with the text of the buttons and dropdowns beside it. `PentadSpinBox` is the stepper: an 8 px rectangle with its two arrows at the trailing end, the upper one in the top half and the lower one in the bottom half. Both take `capsule: true` where the host's controls are capsules: the box is then drawn as a true capsule, and the stepper's arrows stand side by side at full height, clear of the round end. A settings row passes `Metrics.settingsFieldCapsule`; elsewhere a field stays a rectangle.

## Attached surfaces

`AttachedPopover` takes `anchorItem` and optional `barItem`, `manager` and `contentItem`, and provides `open()`, `close()`, `toggle()`, `opened`, `surface` and `window`. The content sets `implicitHeight` and a width or `implicitWidth`. For a Column an explicit width is enough: the height is taken from its content automatically. Fill in only the rows you need; context buttons are 28 px high with a 4 px gap.

The fill of an open trigger and of the surface is shared. The outline uses continuous corners and a neck to the actual trigger, including the shift near a screen edge. `SurfaceRegion` excludes transparent parts from the input region. Passive tooltips on the bar use the same `surfaceGeometry` from `continuous-corners.mjs`: continuous concave shoulders to the lower edge of `BarFace` and continuous lower corners, with no sharp vertices; the 16 px shoulders and corners shrink proportionally to fit the preset's height (for 28 px, 14 + 14 px); a short `Discord` tooltip is about 96 × 28 px, and a title with details grows with its content. Interactive menus attached to a real `BarFace` use the attached-surface contract: 32 px concave upper shoulders and 32 px continuous lower corners from `continuous-corners.mjs`, straight sides between them and 16 px inner padding. The outline of a short passive tooltip is not stretched to the height of a menu. Tooltips and interactive `AttachedPopover`s away from the bar keep the outline with a neck. `PentadToolTip` sizes itself by text with a width limit, supports a second line and is transparent to input. The outline and text animations respect reduced motion.

## Verification

Telemetry uses the shared `AttachedPopover`. The content in `TelemetryDetails` is made of circular indicators with no square backing and no repeated popups. The name and percentage of CPU/GPU/RAM sit inside the circle; compact RAM/VRAM data is under it. GPUs are labeled briefly (`GPU 0`, `GPU 1`), and the full details stay in the accessible name. Network has just two lines with arrows and compact speeds (`↓16K/s`, `↑15K/s`), with the name under the circle; full units are available through accessibility. Four metrics use two columns, five or more use three. An incomplete last row is centered, and circles do not stretch. The base circle diameter is 76 px, the cell is 80 × 96 px and the gap is 8 px. Labels support Ukrainian and English. Missing values are shown as "—" with an empty indicator, not as zero. Polling is once a second, and indicators persist between measurements.

Away from the bar there is one hint type: `PentadHint`, the same `PentadBubble` speech bubble that `PentadInfoButton` opens, with its tail on the item it is declared in. Declare it inside the control with `text` and `shown` (usually `hovered || visualFocus`); never use the attached `ToolTip.*` of QtQuick.Controls, which draws the Basic style's white outlined box. `axis: "horizontal"` puts it beside the item, for menu entries, dropdown rows, a collapsed rail or a vertical toolbar; `gap` clears a padded surface. A hint never takes focus, and since a popup cannot let the pointer through, it steps aside when the pointer enters it and stays away until `shown` drops and rises again. The bar's drop-down tooltips stay `PentadToolTip`.

Passive tooltips appear after the cursor rests for `Metrics.tooltipDelay` (700 ms), the same in `PentadToolTip`, `PentadHint`, `PentadInfoButton` and `PentadMenu`; individual components do not set their own delay. While any `PentadHint` is on screen, or for 600 ms after the last one hid, the next one shows at once. While the shared bar tooltip is still visible, moving to a neighboring button shows it at once. The bar tooltip drops out from under the lower edge of `BarFace` and hides back the same way over `Motion.medium` with `Easing.OutCubic` in both directions: a sharp start and a smooth stop at the end; away from the bar, tooltips fade in. Reduced motion turns the animation off. Bar tooltips use fixed presets from `Metrics`: `compact` is 96 × 28 px, `label` is 160 × 28 px and `status` is 240 × 48 px. In `PentadToolTip`, `sizeMode: "auto"` picks the format before showing and holds it until fully hidden; a change of text does not rebuild the visible surface. `status` always reserves two 16 px lines, even if the second is empty. A long line is truncated within the set width. Sound, network and battery use `status`; sound also sets `animateContent: false`, so fast updates do not shift the text or wait in the animation queue. On a narrow screen the surface width is limited to the available space. Tooltips away from the bar keep a size by content.

`pentad.audio-mixer` is a reusable mixer of playback streams. In `sidebar-right` it is rendered through `PluginHost` under the shared audio controls; in `tools` and `system` it opens from an icon through `AttachedPopover`. `sidebar-left` is supported too. New configurations enable `mixer-main` in the menu; existing ones get disabled `mixer-main` and `mixer-bar` placements if no such placements exist yet. They can be enabled and moved in the layout editor.

One application can have several audio streams; each has its own level 0–100% and mute. Frequencies are not adjustable, and a link to a specific window or tab is not guaranteed. Native sliders persist across value updates by stream lifetime ID, so a state update does not interrupt a drag. The list is limited in height and scrolls. `retainMixer` / `releaseMixer` keep tracking only while at least one widget form is shown. The [service and placement contract](../../packages/widget-api/v1/README.md) describes the API in more detail.

Node tests check contracts, config migration and geometry. `control-templates` checks the native QML templates and adapters with fake services; `control-center` checks the integration of the current menu. `bar-visual` captures the QML content of a tooltip and checks the junction coordinates and both screen edges. The private KWin in that scenario provides no `grim` screencopy, so a capture of the shared bar-and-popup composition is unavailable; it is not replaced by a painted copy of the popup. Other graphical scenarios run in a private compositor and D-Bus. QtTest does not create a real Wayland input serial: checking a click outside a native popup needs a separate check with real input in a session.

## Optical alignment

Keep layout boxes, hit targets and focus geometry stable. Apply optical corrections
to artwork inside the shared component, before directional rotation; callers must
not repeat them. `PentadChevron` centres its bundled 24-unit artwork with a
size-relative half-unit translation, including during rotation. Unknown application
and tray artwork remains unchanged.

Use text baselines for adjacent labels and preserve `PentadText.solid` for compact
stacks. Do not derive offsets from individual translated strings. Additional icon
or text corrections require rendered comparison in the isolated UI harness at
scales 1, 1.25, 1.5 and 2, in both languages and themes; geometry alone does not
establish perceived visual weight.
