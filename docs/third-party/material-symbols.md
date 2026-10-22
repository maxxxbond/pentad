# Material Symbols Rounded

Source: https://github.com/google/material-design-icons/tree/737e3324305806514d7909874fa1818ae1808232

PanelIcon embeds Google Rounded, filled (FILL=1) SVGs at the 20px optical size, the smallest upstream optical size. Other panel icons display the SVGs at 18px. Telemetry instead renders the installed Material Symbols Rounded variable font at 16px with FILL=1, wght=600, opsz=16, GRAD=0 through Pango/Cairo. GTK symbolic classes and black foreground fill are the only SVG adaptations. License: `LICENSES/material-symbols-Apache-2.0.txt`.

CPU uses planner_review, GPU developer_board, RAM memory, and network swap_vert. Live usage sectors remain Cairo drawings. Existing Material Symbols Rounded text icons elsewhere remain Google symbols. App-owned tray graphics retain their artwork.

Regenerate the standalone resource with `node scripts/build-panel-icons.mjs`.

The notification bell (`notifications`), close cross (`close`) and brightness sun (`brightness`) are original Pentad outline drawings, stored alongside this pack for bundling. They are not Google artwork. The generator exports the available icon names from the actual SVG files; `PanelIcon` uses this registry for fallback selection.

Telemetry uses 20px discs and 2px icon/value spacing. Each disc is drawn into an isolated Cairo group; DEST_OUT removes the glyph alpha before compositing onto the capsule. This preserves the actual background through the icon on hover and under live sectors. The font is already required by the existing Material text icons.

## Quickshell media SVGs (2026-10-11)

`quickshell/assets/icons/material/media/` contains 21 unmodified Rounded,
filled 20px-optical-size SVGs from the same pinned Google revision above.
They replace font ligatures in media transport, source selection, lyrics,
karaoke, missing-artwork and central-menu controls (including smartphone,
cloud and description). Each upstream URL and SHA-256 is
recorded in `sources.json` beside the files. The Apache-2.0 license is
bundled at `LICENSES/material-symbols-Apache-2.0.txt`. These controls no
longer depend on a locally installed Material Symbols font or emoji fallback.
`cloud-upload-symbolic.svg` (2026-10-23) is the one outlined (FILL=0)
cloud_upload SVG of that revision; it can stand in for the drawn arrow of a drop zone (`PentadFileDrop.iconSource`).

## Screenshot editor SVGs (2026-10-15)

`quickshell/assets/icons/material/screenshot/` bundles 17 unmodified Google
Material Symbols Rounded, filled, 20px SVGs from revision
`737e3324305806514d7909874fa1818ae1808232`: near_me, edit, horizontal_rule,
north_east, rectangle, circle, text_fields, ink_highlighter, format_color_fill,
crop, undo, redo, content_copy, save, check, palette and error.
Their exact upstream URLs and SHA-256 hashes are recorded in the adjacent
`sources.json`. License: `LICENSES/material-symbols-Apache-2.0.txt`.
The editor also reuses the pinned media pack's close, add, remove and
settings-fragment description SVGs. No font glyph fallback is used for
screenshot tool, history, export or close buttons.

## Control center SVGs (2026-10-19)

`quickshell/assets/icons/material/controls/` bundles 23 unmodified Google
Material Symbols Rounded, filled, 20px SVGs from revision
`737e3324305806514d7909874fa1818ae1808232`: wifi, bluetooth, flight,
dark_mode, vpn_key, coffee, notifications_off, speed, eco, light_mode, lock,
logout, restart_alt, power_settings_new, edit, check, add, remove,
open_in_full, contrast, screenshot_region, settings and bedtime. They replace the stroked outline
drawings and Fluent session glyphs that the control center used to mix, so the
whole surface draws one filled family (contract rule R6). Upstream URLs and
SHA-256 hashes are recorded in the adjacent `sources.json` and verified by
`tests/quickshell/control-center-icons.test.mjs`. License:
`LICENSES/material-symbols-Apache-2.0.txt`.

## Tool catalog SVGs (2026-10-19)

`quickshell/assets/icons/material/tools/` bundles 8 unmodified Google
Material Symbols Rounded, filled, 20px SVGs from revision
`737e3324305806514d7909874fa1818ae1808232`: data_object, straighten,
qr_code_2, chat_bubble, extension, star, folder_open and input. They replace
the font ligatures the sidebar tool catalog used; the catalog also reuses the
media pack's search, close, format_align_left and arrow_forward SVGs. Upstream
URLs and SHA-256 hashes are recorded in the adjacent `sources.json` and
verified by `tests/quickshell/control-center-icons.test.mjs`. License:
`LICENSES/material-symbols-Apache-2.0.txt`.

## Notification SVGs (2026-10-19)

`quickshell/assets/icons/material/notifications/` bundles 5 unmodified Google
Material Symbols Rounded, filled, 20px SVGs from revision
`737e3324305806514d7909874fa1818ae1808232`: close, send, notifications,
clear_all and reply. They replace the font ligatures the notification cards
used. URLs and SHA-256 hashes are in the adjacent `sources.json` and verified
by `tests/quickshell/control-center-icons.test.mjs`.

## Stash SVGs (2026-10-23)

`quickshell/assets/icons/material/stash/` bundles 6 unmodified Google
Material Symbols Rounded, filled, 20px SVGs from revision
`737e3324305806514d7909874fa1818ae1808232`: push_pin, link, more_horiz,
sticky_note_2, open_in_new and close_fullscreen. They mark pinning, links and
notes, the row menu, and the switch between the Stash overlay and window; the
Stash also reuses the media, controls, screenshot and tools packs. URLs and
SHA-256 hashes are in the adjacent `sources.json` and verified by
`tests/quickshell/control-center-icons.test.mjs`. License:
`LICENSES/material-symbols-Apache-2.0.txt`.

## Bar status SVGs (2026-10-22)

`quickshell/assets/icons/material/status/` bundles 4 unmodified Google
Material Symbols Rounded, filled, 20px SVGs from revision
`737e3324305806514d7909874fa1818ae1808232`: mic_off, signal_wifi_bad, lan
and tv. With the existing wifi, wifi_off, volume_up, volume_off, mic and
battery glyphs they make the bar status cluster one filled family; the
microphone no longer comes from the system icon theme. `tv` also replaces the
stroked display-speaker drawing for HDMI and DisplayPort audio outputs. URLs
and SHA-256 hashes are in the adjacent `sources.json` and verified by
`tests/quickshell/control-center-icons.test.mjs`.
