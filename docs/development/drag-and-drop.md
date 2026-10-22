# Quickshell drag-and-drop

Drag files, web images, links or text over the center/right part of the bar to reveal Shelf immediately. Hold files, URLs or text over the left part for 300 ms to reveal the sidebar tools. Drop on the bar or continue into the opened panel. Panels opened by drag close 220 ms after leaving their interaction area; a panel already open manually retains its normal dismissal policy.

In the activity panel, drag over the Shelf or LocalSend tab to select that destination. Shelf accepts local file URI lists, web-image HTML, bookmarks and text. It deduplicates stored entries and keeps local originals in place. Its tiles export CopyAction URI lists without moving the grid. LocalSend accepts the same files and launches the installed application with separate decoded absolute path arguments. Device selection happens in LocalSend; handing off files does not confirm a network transfer. The installed application's changelog and [upstream argument loader](https://github.com/localsend/localsend/blob/main/app/lib/provider/selection/selected_sending_files_provider.dart) establish support for initial file paths. Cloud remains unavailable until a folder adapter is configured.

The sidebar accepts URI lists and plain text including charset MIME variants. Typed compatibility checks preserve the selected tool and draft on unsupported input. General drops offer compatible tools and quick actions (see Sidebar drag mode); targeted drops populate the selected tool, requiring replace/append when a draft already exists unless they arrive through a quick action. Drops never run a tool or send an AI request. Local file type/content checks use the existing bounded reader.

Overview drags use a separate visual proxy above workspace cards. Only the current lifetime/generation token can move a window, using MoveAction. A drop onto its source workspace is a no-op; repeated/stale tokens, pinned/grouped clients and invalid destinations are rejected. Escape and disappearing source windows cancel the proxy and clear dragging state. Releasing a cancelled drag cannot activate the window. Accepted moves await the adapter's existing compositor confirmation.

## Verification

- The visual navigation fixture sends native Qt mouse press/move/release across workspace cards, verifies one move without focus loss or dismissal, then cancels another drag with Escape before release.
- Bar ingress and auto-dismiss use injected offers in a native QML fixture. LocalSend's argument handoff uses a harmless executable in the media fixture. Physical GTK/file-manager ↔ Qt round trips and actual device transfers need a manual check.

Run the native scenarios in the isolated harness, never on your own desktop:

```sh
node scripts/test-quickshell-headless.mjs --scenario drag-and-drop --report /tmp/pentad-dnd.json
node scripts/test-quickshell-headless.mjs --scenario window-navigation-visual --report /tmp/pentad-window-dnd.json
node scripts/test-quickshell-headless.mjs --scenario sidebar-tools --report /tmp/pentad-sidebar-dnd.json
```

## Shelf preview and export correction

Both the activity menu and standalone shelf widget now use the same Nautilus-inspired grid: Adwaita MIME/folder icons, two-line labels, transparent resting tiles and tonal selection in Pentad's palette. Control-click selects multiple files. A single click selects; double-click/Enter opens; Delete/removal only removes a reference. The standalone popup scrolls its grid.

`ShelfFiles` runs `pentad_shelf_preview.py` asynchronously. Gio supplies availability and content type; GNOME DesktopThumbnailFactory uses the standard mtime-checked thumbnail cache and installed thumbnailers, including Evince for PDF. Metadata and thumbnails stay outside the persisted Shelf document. Missing originals are dimmed and cannot start an export. Unsupported previews retain the file icon. The helper accepts at most 50 local URIs, streams metadata before thumbnails and has cancellation/deadline bounds.

Drag-out explicitly captures a visual, marks Drag active and calls native `startDrag(CopyAction)`. It does not bind native drag lifetime to a pointer handler that loses its grab. The activity surface suppresses focus-grab dismissal during export and remains loaded until export completes.

`--scenario shelf-files` verifies image and PDF thumbnail generation, visible preview delivery, MIME/folder metadata, multi-selection, a stable source tile and actual URI delivery to another native Wayland window. The test generates compositor pointer events through KWin's libei/EIS API. Its driver refuses to run unless both the Wayland socket and explicitly created D-Bus socket belong to the disposable headless test directory. No events reach the user's compositor or bus.

```sh
node scripts/test-quickshell-headless.mjs --scenario shelf-files --report /tmp/pentad-shelf-files.json
```

The native fixture proves cross-window export through the compositor. A separate physical GTK/Nautilus destination acceptance check remains useful for application-specific handling.

## Universal Shelf

Web-image drops create persistent cards from the offered HTML image, srcset, title and source URL. Remote previews load when cards are visible; a permanent local image file is created only by Download. The highest offered srcset candidate is downloaded to XDG Downloads/Pentad with unique names, temporary files, a 50 MiB transfer limit and a 60-second deadline. The helper validates image headers and decodes a thumbnail before publishing the file. Failed transfers keep the card with Retry download; downloaded cards open and export their local file while retaining Open source. Removing a card does not delete files.

Ordinary links preserve their offered anchor or Netscape title for reading later; text stays plain text and opens in a selectable full-note reader. Spotify track drops become link cards with a disabled Loader stub. No Spotify metadata fetch, playback or audio download occurs. Empty URI-list offers fall back to other useful formats. LocalSend remains local-file-only. Existing version 1 file entries retain their format; new optional kinds share the 50-entry and 1 MiB document limits.

The content helper uses Python HTMLParser and GdkPixbuf; source HTML is never executed. Both Shelf surfaces share the same card grid and scroll their content. Native Shelf checks cover queued card creation, explicit download, failed-image retry, local-file export, disabled Spotify stub and successful image rendering; existing native file round trips remain covered by shelf-files.

Actual third-party downloads still depend on the offered URL being available without the browser session; failures keep the card and offer retry.

## Compact composition

The shared shelf uses a header/count, a contained file canvas and a stable selection action strip. All local files and saved web/text entries use the same 150 px tile rhythm. Names occupy two readable lines with quieter type/source metadata. Inline remove buttons are replaced by contextual and selection actions. Right-click/Menu opens relevant actions; Shift selects a range, Control toggles items, arrows move selection and Delete removes references. Notes, explicit downloads, retry and the disabled Spotify loader remain available through the shared action strip. The canvas accepts drops across its full area and empty state. The activity and widget presentations both scroll the shared shelf.

## Shelf drop geometry regression

The compact layout placed the accepting DropArea inside a zero-sized child of a Column. Native Qt drag hit testing skipped that branch, although direct receiveDrop calls and outbound exports passed. ShelfGrid now uses a full-sized Item for hit testing and an internal Column for implicit content height. The DropArea fills the root without contributing to layout sizing.

The shelf-files native fixture now exports from a PentadScrollView and drops into a real ShelfGrid, first empty and then populated, instead of a generic recipient DropArea. Both multi-file and downloaded-image URI deliveries pass.

## Drag feedback and quieter shelf

The resting header shows only its title and item count. The empty canvas uses one invitation; selection actions appear only while something is selected. Persistent saved-count prose and drag-out instructions are removed. During native hover, the bar highlights the destination and the shelf tints its canvas, dims tiles and shows a non-interactive release target. A successful Shelf command produces a short confirmation; failed commands retain the error. Motion respects reduced-motion preferences.

## Sidebar file and text tools

PDF tools, Image converter, Image text, Video and audio, Archive and Checksum share `features/sidebar/FileToolView.qml`. Each declares its actions in `logic/file-tools.mjs`; `tools/pentad_file_tool.py` runs one action per job. A dropped or chosen file stays a reference: the bounded reader now returns images, PDFs, video, audio and archives by URI without reading them, so `maxBytes` limits only inline text. Every file item also carries `application/x-pentad-local-file`, which Archive and Checksum accept instead of listing every MIME type.

The helper links inputs into a private work directory under neutral names, runs `qpdf`, Ghostscript, Poppler, ImageMagick, Tesseract, zbar, ffmpeg, 7-Zip or tar with argument lists, and publishes each result beside the first input under a fresh name (`report-compressed.pdf`, `photo (2).webp`). It never overwrites or deletes originals; an unwritable folder falls back to `~/Downloads/Pentad`. PDF passwords travel through a 0600 qpdf argument file, never the command line. Cancel sends SIGTERM; the helper stops its CLI process group and removes partial output, and the CLI dies with the helper if the shell kills it. Results that are not smaller (compression) are discarded and reported. Translate is the only networked tool and runs `trans` only when Translate is pressed.

Encode / decode, Timestamp converter, Color converter, Text case and YAML ↔ JSON are pure `logic/text-tools.mjs` functions, except YAML, which calls `yq`.

```sh
python3 -m unittest tests.tools.test_file_tool tests.tools.test_read_input
node --test tests/quickshell/file-tools.test.mjs tests/quickshell/text-tools.test.mjs
node scripts/test-quickshell-headless.mjs --scenario sidebar-file-tools --report /tmp/pentad-sidebar-file-tools.json
```

The headless scenario drops staged fixtures through the real sidebar and checks PDF page extraction, state across tool switches, password protection and a wrong password, rejection of an image on the PDF tool, WebP conversion, QR reading, ZIP extraction, checksum comparison and each text tool. Video jobs, OCR with real scans and the FileDialog picker are covered only by the helper tests or need a manual check.

## Sidebar drag mode

Anything dragged over the open drawer switches it into drag mode (`DropActions.qml`). A thumbnail and the item's name lead, followed by up to six quick-action tiles (`quickActions` in `logic/file-tools.mjs`: Compress PDF, To JPG, Make GIF, Extract here, Zip…) and the other compatible tools. File types are guessed from names while hovering, because the reader only runs after release; the reader's verdict still decides. When a tool is open and accepts the input, its own tile comes first ("Add to PDF tools").

Releasing on a quick action opens that tool with the input (replacing earlier files) and the action and its options selected, with keyboard focus on the run button, so Enter starts it. Nothing runs on drop. Releasing elsewhere in the drawer keeps the general flow, and the catalog then shows the same quick actions above the compatible tools; pressing one delivers the pending input. Leaving one drop target for another keeps drag mode for 120 ms, so moving between tiles never flickers.

At rest, the catalog shows four pinned tiles (favorites, then recent tools, then suggestions), Recent results with real thumbnails from the Shelf preview helper (`ToolPreviews`), and tools grouped by category. Searching, filtering or pending input flattens the list. Recent results and every published output row are native drag sources (`FileDragSource.qml`, the Shelf export pattern, `text/uri-list` with CopyAction): drag one into a browser upload, chat or file manager, or back onto a sidebar tile. While such a drag runs, `ToolWorkspace.exports` keeps the drawer open and releases its focus grab. A click opens the file.

`sidebar-file-tools` also covers drag-mode tiles for PDFs and text, the current-tool tile, hover continuity across targets, a tile drop that replaces earlier files and preselects the action, general-drop quick actions and a WebP preset, Recent results and the sectioned catalog. Native drag-out to another application needs the compositor input driver and remains a manual check.
