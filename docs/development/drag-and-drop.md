# Quickshell drag-and-drop

Hold files, web images, links or text over the center/right part of the bar for 300 ms to reveal the Stash tab, or over the left part for 300 ms to reveal the sidebar tools; a drag that only passes over the bar opens nothing. Only one panel opened by the drag is open at a time: moving to the other side closes it. The target zone is a soft rounded capsule inset from the bar edges that glides between sides, without accent tint or underline. Over the left zone the drawer already enters drag mode while hidden, so it appears with quick actions. Drop on the bar or continue into the opened panel. Panels opened by drag close 220 ms after leaving their interaction area; a panel already open manually retains its normal dismissal policy.

In the activity panel, drag over the Stash or LocalSend tab to select that destination. The Stash accepts local file URI lists, web-image HTML, bookmarks and text. It deduplicates stored entries and keeps local originals in place. Its rows and photos export CopyAction URI lists without moving. LocalSend accepts the same files and launches the installed application with separate decoded absolute path arguments. Device selection happens in LocalSend; handing off files does not confirm a network transfer. The installed application's changelog and [upstream argument loader](https://github.com/localsend/localsend/blob/main/app/lib/provider/selection/selected_sending_files_provider.dart) establish support for initial file paths. Cloud remains unavailable until a folder adapter is configured.

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

## Stash window

Shelf is now called Stash (Ukrainian: Сховок). Only the user-visible name changed; the widget id `pentad.shelf`, the state file `shelf.json`, `services.shelf`, `features/shelf/` and the scenario names `shelf` and `shelf-files` stay as they are. The tile grid (`ShelfGrid`, `FileTile`, `ContentTile`) is retired. The Stash is one compact view, `StashView`, shown in a window of its own, plus a quick tab in the activity menu. The sections after this one describe the earlier tile grid and keep their history; where they say "tile", "card" or "grid", read "row" or "photo", and the old 50-entry limit is now 300 unpinned plus 50 pinned entries.

### Opening it

- The global shortcut `pentad:stash`. Bind it in Hyprland, for example (same style as [Spotlight](spotlight.md)):

  ```ini
  bind = SUPER, S, global, pentad:stash
  ```

- The `stash` command of the `pentad` IPC target, with the payload `{"action": "toggle"}` (the default), `"open"` or `"close"`.
- The "Увесь Сховок · N" / "All of Stash · N" button in the activity menu's quick tab.
- The `pentad.shelf` bar widget button.

In `window` mode the shortcut focuses the open window instead of hiding it.

### Overlay and window

`interface.stashWindow` is `'overlay'` (default) or `'window'`; the header button detaches the overlay into a window or attaches it back. The query, filter, selection, unsent draft, scroll position and expanded days live in `services.stash` (`StashController`), so switching mode keeps them.

- **Overlay.** A centered layer-shell surface, 520 px wide and up to 70 % of the screen high. Esc closes it (after it clears a non-empty search first), and so does a click outside. During a drag-out it fades to 0.15 opacity and lets input through, then comes back when the drag ends or is cancelled.
- **Window.** A Quickshell `FloatingWindow` titled "Сховок" or "Stash" (it follows the shell language). Quickshell 0.3.2 offers no per-window app-id, so the window has the class `org.quickshell`. A Hyprland window rule has to match that class together with the title, so other Quickshell windows stay out of it:

  ```ini
  windowrule = float, class:^(org\.quickshell)$, title:^(Сховок|Stash)$
  windowrule = size 520 640, class:^(org\.quickshell)$, title:^(Сховок|Stash)$
  ```

  Without a rule the window tiles like any other.

### Keys

| Key | Action |
| --- | --- |
| ↑ / ↓ | Move the selection (Shift extends it) |
| Enter | Open the selected entry |
| Ctrl+C | Copy it |
| P | Pin or unpin |
| Delete | Remove from the Stash |
| Ctrl+V | Paste text, a link, files or an image from the clipboard |
| / | Focus the search field |
| Esc | Clear the search, then close the overlay |

P and `/` also work on the Ukrainian layout, where they arrive as з and the period key.

### Data

`shelf.json` is `schemaVersion: 2`. Each entry has `addedAt` (an ISO time, or an empty string for entries migrated from version 1, which show under "Раніше / Earlier"), `pinned`, and, for clipboard images saved by the Stash, `owned: true`. Owned images live in `$XDG_STATE_HOME/pentad/stash/`; removing an owned entry deletes that file and nothing else. Entries that are not owned are references to files elsewhere and are never touched. Version 1 documents migrate on load and are saved once as version 2.

The limits are 300 unpinned plus 50 pinned entries, and the document stays at or below 1 MiB. An addition that would break either limit is refused with a visible message and leaves the document unchanged. Nothing is cleaned automatically.

`tools/pentad_stash_clipboard.py` (operations `paste`, `copy` and `delete`) talks to the clipboard through `wl-clipboard`, and `delete` removes only files inside the stash directory. `wl-clipboard` is optional: when it is missing, the Stash shows "Немає доступу до буфера обміну. Встановіть wl-clipboard." / "Can't reach the clipboard. Install wl-clipboard." under the list and nothing else breaks. An empty clipboard says so ("Буфер обміну порожній." / "The clipboard is empty."), and any other failed paste or copy reads "Не вдалося виконати дію з буфером обміну." / "The clipboard action failed.". A paste takes at most 100 files, one image up to 32 MiB or text up to 64 KiB; anything bigger is refused with `item-too-large` ("Це завелике для Сховку." / "This is too large for the Stash."), while `too-large` ("Сховок переповнений…" / "Stash is full…") is reserved for the 1 MiB document cap. Copy sends text and links as `text/plain`, files as `text/uri-list` and owned or downloaded photos as an image whose type follows the file extension (`image/png`, `image/jpeg`, `image/webp`…, and `image/png` for an unknown extension).

### Quick tab

The activity menu's Stash tab is a compact drop-and-grab view, not a second Stash. It shows a drop zone (48 px while the Stash has entries, 92 px while a drag hovers the tab or the Stash is empty), up to 6 recent photos, the 3 latest other rows and the "Увесь Сховок · N" button, which opens the Stash and closes the menu. A drag that started in the Stash does not drop back onto the bar's centre, so a Stash item never lands in the Stash again. The activity menu may not be built yet when a drag reaches the bar's centre (see [popups](popups.md)): the drag starts building it during the dwell, and a drop that arrives first opens the menu, which finishes the build before the drop reaches the Stash tab.

### Verification

```sh
node scripts/test-quickshell-headless.mjs --scenario stash-window --report /tmp/pentad-stash-window.json
node scripts/test-quickshell-headless.mjs --scenario shelf --report /tmp/pentad-shelf.json
node scripts/test-quickshell-headless.mjs --scenario shelf-files --report /tmp/pentad-shelf-files.json
```

`stash-window` covers sections, keys, the composer, both frames, the mode switch and the drag-out pass-through; `shelf` covers the service (pins, notes, paste, copy, owned deletes, limits, v1 migration), the web-drop and download paths through `StashView`, and the quick tab; `shelf-files` covers thumbnails and native drag-and-drop between windows.

## Shelf preview and export correction

Both the activity menu and the standalone widget then used the same Nautilus-inspired grid: Adwaita MIME/folder icons, two-line labels, transparent resting tiles and tonal selection in Pentad's palette. Control-click selects multiple files. A single click selects; double-click/Enter opens; Delete/removal only removes a reference. The standalone popup scrolls its grid.

`ShelfFiles` runs `pentad_shelf_preview.py` asynchronously. Gio supplies availability and content type; GNOME DesktopThumbnailFactory uses the standard mtime-checked thumbnail cache and installed thumbnailers, including Evince for PDF. Metadata and thumbnails stay outside the persisted Stash document. Missing originals are dimmed and cannot start an export. Unsupported previews retain the file icon. The helper accepts at most 350 local URIs (the largest Stash plus headroom), reports each file's `size` with its metadata, streams metadata before thumbnails and has cancellation/deadline bounds.

Drag-out explicitly captures a visual, marks Drag active and calls native `startDrag(CopyAction)`. It does not bind native drag lifetime to a pointer handler that loses its grab. The activity surface suppresses focus-grab dismissal during export and remains loaded until export completes.

`--scenario shelf-files` verifies image and PDF thumbnail generation, visible preview delivery, MIME/folder metadata, multi-selection, a stable source tile and actual URI delivery to another native Wayland window. The test generates compositor pointer events through KWin's libei/EIS API. Its driver refuses to run unless both the Wayland socket and explicitly created D-Bus socket belong to the disposable headless test directory. No events reach the user's compositor or bus.

```sh
node scripts/test-quickshell-headless.mjs --scenario shelf-files --report /tmp/pentad-shelf-files.json
```

The native fixture proves cross-window export through the compositor. A separate physical GTK/Nautilus destination acceptance check remains useful for application-specific handling.

## Universal Stash

Web-image drops create persistent cards from the offered HTML image, srcset, title and source URL. Remote previews load when cards are visible; a permanent local image file is created only by Download. The highest offered srcset candidate is downloaded to XDG Downloads/Pentad with unique names, temporary files, a 50 MiB transfer limit and a 60-second deadline. The helper validates image headers and decodes a thumbnail before publishing the file. Failed transfers keep the card with Retry download; downloaded cards open and export their local file while retaining Open source. Removing a card does not delete files.

Ordinary links preserve their offered anchor or Netscape title for reading later; text stays plain text and opens in a selectable full-note reader. Spotify track drops become link cards with a disabled Loader stub. No Spotify metadata fetch, playback or audio download occurs. Empty URI-list offers fall back to other useful formats. LocalSend remains local-file-only. Existing version 1 file entries retain their format; new optional kinds share the entry and 1 MiB document limits.

The content helper uses Python HTMLParser and GdkPixbuf; source HTML is never executed. Both Stash surfaces shared the same card grid and scrolled their content. Native Stash checks cover queued card creation, explicit download, failed-image retry, local-file export, disabled Spotify stub and successful image rendering; existing native file round trips remain covered by shelf-files.

Actual third-party downloads still depend on the offered URL being available without the browser session; failures keep the card and offer retry.

## Compact composition

The shared Stash used a header/count, a contained file canvas and a stable selection action strip. All local files and saved web/text entries use the same 150 px tile rhythm. Names occupy two readable lines with quieter type/source metadata. Inline remove buttons are replaced by contextual and selection actions. Right-click/Menu opens relevant actions; Shift selects a range, Control toggles items, arrows move selection and Delete removes references. Notes, explicit downloads, retry and the disabled Spotify loader remain available through the shared action strip. The canvas accepts drops across its full area and empty state. The activity and widget presentations both scrolled the shared Stash.

## Stash drop geometry regression

The compact layout placed the accepting DropArea inside a zero-sized child of a Column. Native Qt drag hit testing skipped that branch, although direct receiveDrop calls and outbound exports passed. ShelfGrid now uses a full-sized Item for hit testing and an internal Column for implicit content height. The DropArea fills the root without contributing to layout sizing.

The shelf-files native fixture exported from a PentadScrollView and dropped into a real ShelfGrid, first empty and then populated, instead of a generic recipient DropArea; it now exports from a `StashView` row or photo and drops into an empty and then a populated `StashView`, plus the quick tab. Both multi-file and downloaded-image URI deliveries pass.

## Drag feedback and quieter Stash

The resting header shows only its title and item count. The empty canvas uses one invitation; selection actions appear only while something is selected. Persistent saved-count prose and drag-out instructions are removed. During native hover, the bar highlights the destination and the Stash tints its canvas, dims tiles and shows a non-interactive release target. A successful Stash command produced a short confirmation; failed commands retain the error. Motion respects reduced-motion preferences.

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

At rest, the catalog shows four pinned tiles (favorites, then recent tools, then suggestions), Recent results with real thumbnails from the Stash preview helper (`ToolPreviews`), and tools grouped by category. Searching, filtering or pending input flattens the list. Recent results and every published output row are native drag sources (`FileDragSource.qml`, the Stash export pattern, `text/uri-list` with CopyAction): drag one into a browser upload, chat or file manager, or back onto a sidebar tile. While such a drag runs, `ToolWorkspace.exports` keeps the drawer open and releases its focus grab. A click opens the file.

`sidebar-file-tools` also covers drag-mode tiles for PDFs and text, the current-tool tile, hover continuity across targets, a tile drop that replaces earlier files and preselects the action, general-drop quick actions and a WebP preset, Recent results and the sectioned catalog. Native drag-out to another application needs the compositor input driver and remains a manual check.

## Choosing files

Choose files (catalog) and Choose/Add (inside a tool) open the desktop's own file chooser through `tools/pentad_pick_files.py`: the xdg-desktop-portal FileChooser, or zenity when no portal answers. The drawer is a layer above normal windows, so `FilePicker` hides it while the chooser is open and reopens it afterwards, including on cancel. Chosen files arrive through `ToolWorkspace.picked` and the usual reader, so they behave like a drop: Choose files finds a compatible tool, Choose fills the current tool and Add appends to its files. Qt's built-in dialog remains only as a fallback where the service is missing. The headless scenario drives this path with a fake helper; the real portal dialog needs a manual check on the desktop.
