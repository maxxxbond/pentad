# Native screenshot editor

Pentad provides a native Quickshell/QML region selector and annotation editor.
Left-click the bar screenshot button to capture and edit a region. Right-click
it for quick-copy mode and screenshot settings. CLI entry points are
`pentad screenshot edit`, `copy`, `window`, `monitor`, and `settings`, with the
same `--development`/`--path` options as other commands.

Region modes freeze each connected monitor, including its open Pentad menus
and settings, before dismissing menus or showing any selection overlay. The
selector waits for menu dismissal only after capture succeeds. Selecting a region chooses that monitor and closes the other
overlays. Up to eight monitors are supported; one region does not span monitor
boundaries. Window mode selects the active window's visible rectangle; if no
eligible active window exists, the selector allows a manual region instead.

The editor includes brush, line, arrow, rectangle, ellipse, text, highlight,
opaque redaction, crop, annotation selection/move/delete, color/size editing,
and undo/redo. Double-click a text annotation with the selection tool to edit
it. Mouse wheel zooms around the pointer; middle-button drag pans. Crop mode
allows moving the crop and dragging its corners/edges. Changing a crop does
not discard annotations outside it, so widening it recovers them. Exported
PNG contains only the current crop and visible annotation pixels.

Default editor keys are V/B/L/A/R/O/T/H/X/C for select/brush/line/arrow/rectangle/
ellipse/text/highlight/redact/crop; Ctrl+Z and Ctrl+Shift+Z undo/redo; Delete
removes the selection. Ctrl+C copies and keeps the editor open, Ctrl+S saves,
Enter copies and closes. In text entry, Enter commits text, Shift+Enter adds a
line and Escape cancels text entry. Escape otherwise cancels the current
gesture or asks to discard changed work before closing. Text is limited to
4096 characters and exceeding the limit reports an error rather than
silently truncating input.

Screenshot settings are stored in the regular revision-checked
`screenshots.json` config document. They include local/global keys, save
directory, auto-save after copying and last-used annotation style. An empty
key disables its action. Duplicate normalized keys within the same group are
rejected. Empty save directory uses the XDG Pictures directory plus `Pentad`,
falling back to `~/Pictures/Pentad` when xdg-user-dir is unavailable.

Global keys are proposed as Super+Shift+S (edit), Super+Ctrl+S (quick copy),
Alt+Print (window), Print (monitor). Settings export the desired bindings into
`$XDG_CONFIG_HOME/pentad/hyprland-screenshots.lua` (or
`~/.config/pentad/hyprland-screenshots.lua`). Source that fragment from your
Hyprland Lua configuration after the other keybinding imports. Each configured
combination is unbound before registering its Pentad action, so old or
custom screenshot handlers cannot fire alongside the new action. Unconfigured
combinations remain untouched.
Export never activates bindings or reloads the compositor automatically.

Runtime requirements: Python 3 with Pycairo, grim, and wl-copy. No Satty,
Swappy or ImageMagick is required by this editor. Capture/export helpers are
short-lived, use argv rather than shell interpolation, keep source PNGs in
private session directories, and support bounded cancellation. PNG output
uses original image pixels independently of screen scale and zoom. Copy and
save outcomes are tracked independently; export errors keep the editor open
with retry available. Rendered PNGs contain no editor history or metadata for
hidden annotations. The editor has no blur/pixelation or scrolling capture.
Text recognition and area recording are bar tools that use the same selection
overlay; see "Choosing an area for other tools" below.

Validation: pure JS model/settings/window-geometry tests, Python tests using
generated PNGs and fake capture/clipboard commands, QML parsing/static lint,
and the packaging build. Live capture, clipboard ownership, compositor
unmapping, multi-output keyboard focus and text-rendering agreement need a
manual check in a real session.

The Node suite also runs `tests/quickshell/screenshot-qt.test.mjs`, which
compiles a small QCoreApplication/QJSEngine check when C++ and Qt development
packages are available. It imports the screenshot modules and configuration
in Qt's JavaScript engine, then exercises editing, shortcuts and window APIs.
It creates no GUI, shell or service connections. This catches syntax such as
object spread that Node accepts but Qt does not. On systems without the
development packages the test reports an explicit skip.

## Behavior notes

**Look.** The editor uses bundled Material SVGs, borderless continuous surfaces,
a wrapping toolbar, a keyboard-accessible palette and contextual stroke/text
controls. Copy success shows a temporary check icon; saved paths and recoverable
errors stay visible. Settings keep Hyprland setup help behind an information
button and show the binding-replacement consequence before export.

**Key export and conflicts.** Hyprland's Lua `unbind` matches its argument as a
literal string, so a binding registered as `CTRL + SUPER + S` is not removed by
`SUPER + CTRL + S` (upstream discussion:
https://github.com/hyprwm/Hyprland/discussions/16095). A leftover handler for a
combination, such as a scratchpad toggle, then fires alongside the screenshot
action. The exporter therefore unbinds every modifier permutation, in spaced and
compact forms, before installing one canonical action, and only for the
configured screenshot combinations. A regression test models the literal-string
API and checks that unrelated bindings survive. The fragment maps Print to
monitor editing, Super+Shift+S to region editing, Super+Ctrl+S to immediate
region copying and Alt+Print to active-window editing. If the compositor does
not reread its files on its own, reload its configuration after exporting;
restarting Pentad alone does not load Hyprland keys.

**Capture ordering.** A screenshot starts capture before closing settings,
cancelling navigation or asking PopupManager to hide menus. Once all requested
frames are frozen, the menu-close gate runs and its ready signal reveals the
selector. `selectionPending` prevents stale, duplicate and cancelled ready
signals from reopening it, and a capture failure never starts menu dismissal.
To capture an open menu, press the screenshot hotkey while it is visible:
clicking another surface can still dismiss native application menus before
Pentad receives the action. `tests/quickshell/screenshot-capture.test.mjs` runs
the service's real JavaScript with fake process completions, timers and popup
signals and covers capture-before-dismissal and dismissal-before-selection in
all four modes, duplicate requests, empty results, preview mode, errors and
recovery, stale-session cleanup and gate timeout. It does not instantiate QML,
Quickshell or a compositor.

**Focus lifecycle.** A screenshot session remembers the previous client by
address and instanceId (falling back to MRU when a menu owns focus). Closing
first clears `active`, which releases layer keyboard interactivity and hides the
hosts, and only then clears frame and editor data. `ScreenshotHost` reports both
requested visibility and `backingWindowVisible`; focus is restored only after
every backing window has hidden, on the next event-loop turn. Deferred callbacks
check the session serial, preview/safe mode, any newer menu or navigation
session and the client's unchanged identity, so a late callback cannot refocus
an editor that is gone and removed windows or reused addresses are ignored.
`Hyprland.focusWindow(ref, forceDispatch)` takes an optional force flag used
only for this return: Hyprland can still report the same active client while a
layer surface owns keyboard focus, so the usual `activeAddress` no-op is
bypassed. Other callers are unaffected.

**Selector.** Region selection dims the frozen frame with a light grey glass
veil. The system cursor is hidden and replaced by a hairline crosshair with an
open centre pixel and an image-pixel coordinate readout (the region size while
dragging). Hovering a window clears the veil over it, frames it and shows a
camera badge with the window title. A dragged region and the chosen selection
are clear holes with a light frame; after selection, eight handles resize the
region from any tool, and the crop tool still moves it.

**Toolbar.** The toolbar appears only after a region is chosen. Dividers group
frame tools (select, crop), drawing tools, a colour chip and a stroke/text-size
chip (each opening its own popover), history, and save/copy/close. A grip at its
leading end drags it along the selection contour only:
`quickshell/logic/screenshot-toolbar.mjs` projects the pointer onto the nearest
edge, inside or outside the selection, and the toolbar turns vertical on the
left and right edges. Outside placements without room hug the inner side, and
everything is clamped to the output.

The `screenshot-editor` headless scenario
(`node scripts/test-quickshell-headless.mjs --scenario screenshot-editor`)
renders a synthetic desktop to PNG in a private virtual KWin output and captures
window hover, crosshair, region drag, selection with the default dock, the
toolbar docked vertically on both sides and the colour popover. It drives canvas
state and toolbar drag signals directly instead of generating pointer input, so
real pointer delivery, the hidden cursor on Hyprland, live capture and the
clipboard need a manual check.

## Choosing an area for other tools

The selection overlay doubles as the area chooser for everything that works on part of the screen
(OCR, translate, search by image, QR scan, ruler, magnifier and area recording). There is no `slurp`
or per-tool capture any more.

- `Screenshot.pick(token, { label, scale, output })` freezes the screen like a screenshot, shows the same
  overlay and, once an area is chosen, emits `picked(token, result)`; closing without a choice emits
  `pickCancelled(token)`. `result` has `path` (a private PNG of the crop, enlarged by the integer `scale`),
  `rect` (image pixels), `outputId` and `logical` (compositor coordinates, or `null` when the monitor layout
  is unknown). The caller removes the file when it is done (`tools/pentad_screenshot.py` `discard`).
- While choosing, the pointer highlights the smallest thing under it: content found in the frozen pixels
  (`image`, `text`, `panel`; `tools/pentad_screenshot.py` `proposals`, which needs numpy and quietly offers
  nothing without it), then the window, then the whole screen. The wheel steps up and down that chain; a
  click picks the highlighted level and a drag picks any area.
- The same suggestions and wheel work in the normal screenshot modes.

Checks: `python3 -m unittest tests/tools/test_pentad_pick.py` (helper), `tests/quickshell/screenshot-capture.test.mjs`
(service), `node tests/tooling/bar-tools-native.mjs` (Desktop service with a stand-in picker) and
`node tests/tooling/bar-tools-ui.mjs` (real bar and overlay in the private headless compositor; set
`PENTAD_QS_BIN` to a Quickshell binary).
