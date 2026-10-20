# Pentad Widget API v2

Widgets target Quickshell 0.3.2 or newer and declare `apiVersion: 2` in a JSON manifest. `allowedSlots` is required and may contain only `navigation`, `telemetry`, `center`, `tools`, `system`, `sidebar-left`, or `sidebar-right`. Validate a manifest before loading its QML with `manifest.schema.json`; the runtime validator additionally checks duplicate setting keys, defaults against field types, numeric bounds, and an optional requested slot.

`entry` and optional `controller` paths are relative `.qml` paths inside the plugin directory. Absolute paths, URI schemes, backslashes, percent escapes, query/fragment characters, NUL, empty path segments, `.` and `..` segments are rejected. The host owns placement and provides each loaded view these required initial properties: `instanceId: string`, `context: Context`, `settings: Record<string, unknown>`, `services: WidgetServices`, and `controller: Readonly<Record<string, unknown>>`. `Context` contains `outputId`, `slot`, `compact`, and `preview`; inline menu hosts also provide `presented` so views can release tracking while hidden. See [contracts.d.ts](./contracts.d.ts) for the stable TypeScript shapes.

Settings fields use `key`, a human `label` or translated `labelKey`, and one `kind`: `text`, `integer`, `number`, `boolean`, `select`, or `color`. Select options are `{ "value": ..., "label": "..." }`; numeric fields may set `min` and `max`. Put field defaults in `defaults` or on the field. The settings validator fills field defaults, then manifest defaults, then supplied values, and validates the merged result so missing values retain defaults and defaults obey bounds. Unknown settings are rejected.

Services are injected as a shared read-only container. Each adapter exposes a read-only `state` union (`starting`, `ready` with `value`, `unavailable` with `reason`, or `error` with `message`). Async command methods return a request ID and emit `commandFinished(requestId, result)`; `Result` carries success or a documented failure reason. Media state includes `positionMicros`, `lengthMicros`, `trackId`, `playerId`, `sourceId`, and capabilities. See the exact types in [contracts.d.ts](./contracts.d.ts).

Never put passwords, tokens, or API keys in a manifest or settings value. Declare credentials as references such as `"credentials": { "serviceToken": "secret://plugins.example.serviceToken" }`; the secret value remains in the host credential store and is never passed to widget views. Keep views driven by shared Pentad components and let the host own focus, placement, and lifecycle.

Manifests may opt into the sidebar tool catalog with a `tool` object. It requires `protocolVersion: 1`, a category and keywords, accepted and produced MIME type arrays, `execution` (`local`, `network`, or `ai`), `multiple`, `maxItems` (1–100), and `maxBytes` (1–10 MiB). Use MIME wildcards such as `image/*` only when the view actually handles every advertised input. These declarations drive discovery and compatibility; they are not a QML sandbox or permission boundary. Ingress must not run network or AI work automatically, and a view must require an explicit action to execute.

Tool views implement `acceptInput(items, choice)` to receive typed catalog inputs. `items` is an array of `{ kind, mimeType, compatibleTypes, value?, uri?, name?, sizeBytes? }`; `choice` is `''` to fill only an empty draft, `replace`, or `append`. The host first offers the no-choice call and shows explicit choices if the view refuses because it already has input. A tool must return `false` without mutation when it cannot accept the supplied shape or choice. Set `canAppendInput: true` only when append is meaningful. Save drafts with `services.toolWorkspace.setDraft(manifest.id, value)` so they survive tool switching. Catalog-only modules should provide defaults for any settings fields they require; a selected enabled placement reuses that placement's settings and instance identity.

The built-in file reader opens only explicitly selected local regular files, bounds total input, and decodes supported text as UTF-8. For image/PDF classification it checks common file signatures and falls back to the filename extension; this is a routing hint, not proof of the file's contents. Current built-ins accept text and JSON contents, while image/PDF inputs are reported as unsupported until a tool implements them. Remote HTTP(S) URLs are kept as URL values and are never fetched on drop.

To add an external local tool, create `$XDG_CONFIG_HOME/pentad/plugins/example.trim/` (`~/.config/pentad/plugins/example.trim/` when `XDG_CONFIG_HOME` is unset), put `manifest.json` and `View.qml` there, and restart Quickshell. The plugin scanner discovers manifests from that directory; a valid tool that allows `sidebar-left` appears in the searchable catalog. Tool metadata enables discovery and typed routing only: each view still validates its own input and requires an explicit Run action.

```json
{
  "id": "example.trim",
  "name": "Trim text",
  "version": "1.0.0",
  "apiVersion": 2,
  "entry": "View.qml",
  "allowedSlots": ["sidebar-left"],
  "tool": {
    "protocolVersion": 1,
    "category": "Text",
    "keywords": ["trim", "whitespace"],
    "accepts": ["text/plain"],
    "produces": ["text/plain"],
    "execution": "local",
    "multiple": false,
    "maxItems": 1,
    "maxBytes": 65536
  }
}
```

The view can keep a draft and opt into text input like this. Returning `false` on an empty `choice` preserves existing text so the host can offer Replace or Append; update the draft only after checking the type and size. Put actual transformation work behind a separate button.

```qml
TextArea {
    id: draft
    text: services.toolWorkspace.draftFor("example.trim")
    onTextChanged: services.toolWorkspace.setDraft("example.trim", text)
}

function acceptInput(items, choice) {
    if (!Array.isArray(items) || items.length !== 1 || typeof items[0].value !== "string") return false
    if (draft.text && !choice) return false
    const incoming = items.map(item => item.value).join("\n")
    const next = choice === "append" && draft.text ? draft.text + incoming : incoming
    let bytes
    try { bytes = encodeURIComponent(next).replace(/%[0-9a-f]{2}|./gi, "x").length }
    catch (error) { return false }
    if (bytes > 65536) return false
    draft.text = next
    return true
}
```

Run the contract and catalog logic tests with `pnpm run test:qs:logic`, build the shell with `pnpm run build:qs`, and use `pnpm run check:qs` for host Quickshell checks.

Example API v2 views receive the same five properties regardless of slot or output. The shared `services.media` object is the same adapter for every view instance.

The built-in `pentad.audio-mixer` reuses one view in `sidebar-right` (under the main audio controls), `sidebar-left`, or as an icon with an attached popover in `tools`/`system`. New configurations enable `mixer-main` in the right menu and provide a disabled `mixer-bar` placement. Existing saved layouts gain disabled placements only where missing. Enable or move these placements in the layout editor; enabling both provides the menu and bar forms simultaneously. For custom placements, use a unique `instanceId`, `moduleId: "pentad.audio-mixer"`, one of these slots, `enabled: true`, and `settings: {}`.

`services.audio.state.value.streams` contains playback streams with lifetime-safe `id`, application/media labels, confirmed `volume`/`muted`, and `pendingVolume`, `pendingMute`, `requestedVolume`. Use the lifetime token with `setStreamVolume(id, 0..1)` or `toggleStreamMute(id)`; both return request IDs and emit the adapter's `commandFinished` signal. Retain a unique consumer ID via `retainMixer` only while displayed, and call `releaseMixer` on hiding/destruction. Stream tracking stops after the last consumer releases. This is a volume/mute mixer, and does not match every stream to a particular window or browser tab.
