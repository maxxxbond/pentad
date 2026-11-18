# Pentad Widget API v1

This is the initial public widget contract. Earlier development snapshots used a provisional version number of 2; those unpublished manifests must change `apiVersion` to `1`. Only version 1 is accepted. The manifest structure and saved layout/settings documents do not require a migration, and no compatibility alias for the provisional version is provided.

Widgets target Quickshell 0.3.2 or newer and declare `apiVersion: 1` in a JSON manifest. `allowedSlots` is required and may contain only `navigation`, `telemetry`, `center`, `tools`, `system`, `sidebar-left`, or `sidebar-right`. Validate a manifest before loading its QML with `manifest.schema.json`; the runtime validator additionally checks duplicate setting keys, defaults against field types, numeric bounds, and an optional requested slot.

`entry` and optional `controller` paths are relative `.qml` paths inside the plugin directory. Absolute paths, URI schemes, backslashes, percent escapes, query/fragment characters, NUL, empty path segments, `.` and `..` segments are rejected. The host owns placement and provides each loaded view these required initial properties: `instanceId: string`, `context: Context`, `settings: Record<string, unknown>`, `services: WidgetServices`, and `controller: Readonly<Record<string, unknown>>`. `Context` contains `outputId`, `slot`, `compact`, and `preview`; inline menu hosts also provide `presented` so views can release tracking while hidden. See [contracts.d.ts](./contracts.d.ts) for the stable TypeScript shapes.

Settings fields use `key`, a human `label` or `labelKey`, and one `kind`: `text`, `integer`, `number`, `boolean`, `select`, or `color`. `labelKey` is currently a literal fallback, not a catalog translation lookup; use `label` plus `labelUk`/`labelEn` for the generated widget settings page. Select options are `{ "value": ..., "label": "..." }`; numeric fields may set `min` and `max`. Put field defaults in `defaults` or on the field, preferably in one place. The settings validator fills field defaults, then manifest defaults, then supplied values, and validates the merged result so missing values retain defaults and defaults obey bounds. The generated editor uses the same precedence, including explicit empty strings, `false`, and `0`. Unknown settings are rejected.

For a complete two-file external widget, placement instructions and configuration guidance, start with [Create an external widget](../../../docs/development/widgets.md#create-an-external-widget).

The contract includes the metadata already used by the generated settings editor:

- `pentads` declares allowed sections (`left-menu`, `left`, `center`, `right`, `right-menu`) and must agree with `allowedSlots`. When omitted, sections are derived from the slots.
- Fields and select options accept string `labelUk`/`labelEn` translations alongside the fallback label. Fields also accept `help`/`helpUk`/`helpEn`, `group`/`groupUk`/`groupEn`, and a positive finite numeric `step`.
- `showWhen: { "key": "enabled", "equals": true }` controls a field's visibility in the generated widget settings page. The key names a setting and `equals` is a string, number or boolean. Legacy `SettingsForm` hosts use fallback labels and do not implement grouping or conditional visibility.
- Placement hosts can add `placementZone` and `placementSize` to `context`; menu hosts may add `presented`. Treat these properties as optional.
- `controller` is `null` when absent or still loading. A controller receives only `instanceId`, `settings`, and `services`; views receive all five host properties.
- The documented service container includes `apiVersion` (the string `"1"`), `preview`, `safeMode`, and `text(uk, en)`. Other adapters in the runtime are not all covered by the published TypeScript declarations.

The JSON schema, runtime validator and TypeScript declarations describe these fields together. Malformed metadata (for example a numeric label or a non-positive step) is rejected before QML loads.

Services are injected as a shared read-only container. Each adapter exposes a read-only `state` union (`starting`, `ready` with `value`, `unavailable` with `reason`, or `error` with `message`). Async command methods return a request ID and emit `commandFinished(requestId, result)`; `Result` carries success or a documented failure reason. Media state includes `positionMicros`, `lengthMicros`, `trackId`, `playerId`, `sourceId`, and capabilities. `services.capabilities` follows the same conventions and is described under [Capabilities](#capabilities). `Result.reason` also includes `cancelled` and `busy`. See the exact types in [contracts.d.ts](./contracts.d.ts).

Never put passwords, tokens, or API keys in a manifest or settings value. A text setting whose key looks like a credential (`password`, `secret`, `token`, `apiKey`) accepts only an empty string or a `secret://` reference. The one exception is a key ending in `Env`, such as `apiKeyEnv`, which may hold the name of an environment variable (`OPENAI_API_KEY`), never its value. Declare credentials as references such as `"credentials": { "serviceToken": "secret://plugins.example.serviceToken" }`; the secret value remains in the host credential store and is never passed to widget views. Keep views driven by shared Pentad components and let the host own focus, placement, and lifecycle.

Manifests may opt into the sidebar tool catalog with a `tool` object. It requires `protocolVersion: 1`, a category and keywords, accepted and produced MIME type arrays, `execution` (`local`, `network`, or `ai`), `multiple`, `maxItems` (1–100), and `maxBytes` (1–10 MiB). Use MIME wildcards such as `image/*` only when the view actually handles every advertised input. These declarations drive discovery and compatibility; they are not a QML sandbox or permission boundary. Ingress must not run network or AI work automatically, and a view must require an explicit action to execute.

Tool views implement `acceptInput(items, choice)` to receive typed catalog inputs. `items` is an array of `{ kind, mimeType, compatibleTypes, value?, uri?, name?, sizeBytes? }`; `choice` is `''` to fill only an empty draft, `replace`, or `append`. The host first offers the no-choice call and shows explicit choices if the view refuses because it already has input. A tool must return `false` without mutation when it cannot accept the supplied shape or choice. Set `canAppendInput: true` only when append is meaningful. Save drafts with `services.toolWorkspace.setDraft(manifest.id, value)` so they survive tool switching. Catalog-only modules should provide defaults for any settings fields they require; a selected enabled placement reuses that placement's settings and instance identity.

The built-in file reader opens only explicitly selected local regular files, bounds total input, and decodes supported text as UTF-8. For image/PDF classification it checks common file signatures and falls back to the filename extension; this is a routing hint, not proof of the file's contents. Current built-ins accept text and JSON contents, while image/PDF inputs are reported as unsupported until a tool implements them. Remote HTTP(S) URLs are kept as URL values and are never fetched on drop.

To add an external local tool, create `$XDG_CONFIG_HOME/pentad/plugins/example.trim/` (`~/.config/pentad/plugins/example.trim/` when `XDG_CONFIG_HOME` is unset), put `manifest.json` and `View.qml` there, and restart Quickshell. The plugin scanner discovers manifests from that directory; a valid tool that allows `sidebar-left` appears in the searchable catalog. Tool metadata enables discovery and typed routing only: each view still validates its own input and requires an explicit Run action.

```json
{
  "id": "example.trim",
  "name": "Trim text",
  "version": "1.0.0",
  "apiVersion": 1,
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
    if (!Array.isArray(items) || items.length !== 1 || !items[0] || typeof items[0].value !== "string") return false
    if (!["", "replace", "append"].includes(choice)) return false
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

## Capabilities

A capability is a named function the host provides: a chat model, embeddings, translation, OCR, barcode reading, PDF text. A widget asks for the capability and never names a model or a backend. The user chooses those once in Pentad's settings, and every widget follows.

Compatibility: this is an additive part of API v1 and `apiVersion` stays `1`. Hosts that predate it ignore the `capabilities` manifest key and have no `services.capabilities`, so guard the service (`services.capabilities && …`) if the widget should also load there.

### Declare

```json
{ "capabilities": ["llm.chat", "image.ocr"] }
```

`capabilities` is an array of at most 16 unique dotted lowercase names (`^[a-z][a-z0-9-]*(\.[a-z][a-z0-9-]*)+$`). A call to a capability the manifest does not declare fails with `denied`. A well-formed name the host does not know is not a manifest error; calling it reports `unsupported`, so a manifest may list capabilities of a newer host. When the manifest also has a `tool` block, its `execution` must match what the capabilities do: any `llm.*` capability or `text.embed` requires `"ai"`, and `text.translate` requires `"network"` or `"ai"`.

| Capability | `input` | `value` on success |
| --- | --- | --- |
| `llm.chat` | `{ messages: [{ role, content, images? }], temperature?, maxTokens? }` | `{ text }`, also streamed through `partial` |
| `text.embed` | `{ input: [string] }` | `{ vectors: [[number]], dims }` |
| `text.translate` | `{ text, target, source? }` | `{ text }` |
| `image.ocr` | `{ uri, language?, psm?, filterInstalled? }` | `{ text }` |
| `image.barcode` | `{ uri }` | `{ codes: [{ type, text }] }` |
| `pdf.text` | `{ uri }` | `{ text }` |

Limits: `llm.chat` takes 1–100 messages of at most 16 KiB each, with `role` one of `system`, `user`, `assistant`; `images` are `file:///` URIs (at most 8 per message, 16 per call) on `user` messages only; all message text together is at most 512 KiB. `text.embed` takes 1–64 non-empty strings of at most 16 KiB. `text.translate` takes at most 64 KiB of text; `target` and `source` are language tags such as `uk` or `zh-CN`. `uri` is always a `file:///` URI. Input outside these shapes fails with `invalid-input` and a `message` that names the field. Unknown input keys are ignored.

### Call

```ts
available(name: string, instanceId: string): Availability   // { available, reason?, disclosure? }
call(name: string, input: object, options: { instanceId: string, role?: 'chat' | 'fast' }): string  // request ID
cancel(requestId: string): void
warm(name: string, instanceId: string): { ok, warming } | Failure  // load the local model ahead of Run
// signals: progress(requestId, data), partial(requestId, chunk), commandFinished(requestId, result)
```

Call `warm` once when your tool opens or is shown, not on every keystroke. A local model can take seconds to load and well under a second to answer once loaded; warming hides the load. It follows the same declaration, safe-mode and consent rules as `call`, and does nothing for remote providers or local tools.

Pass the widget's own `instanceId`. The host binds each loaded view and controller to its manifest; an instance it has not bound is `denied`. `call` returns a request ID at once and never blocks the interface. The first `progress` of every call is `{ stage: "started", disclosure }`. `commandFinished` carries `{ ok: true, value, cached }` or `{ ok: false, reason, message? }`; `cached` is true when a local operation was answered from the result cache. After `cancel` the call still finishes, with reason `cancelled`. When too many jobs are queued the reason is `busy`; retry later.

```qml
Connections {
    target: root.services.capabilities
    function onPartial(requestId, chunk) {
        if (requestId === root.requestId) answer.text += chunk.text
    }
    function onCommandFinished(requestId, result) {
        if (requestId !== root.requestId) return
        root.requestId = ""
        if (result.ok) answer.text = result.value.text
        else root.message = result.reason
    }
}

function summarize(text) {
    answer.text = ""
    requestId = services.capabilities.call("llm.chat", {
        messages: [
            { role: "system", content: "Summarize the user's text in three sentences." },
            { role: "user", content: text }
        ]
    }, { instanceId: root.instanceId, role: "fast" })
}
```

Capabilities compose in the widget: finish one call, then start the next with its value, for example `image.ocr` and then `llm.chat` on the recognized text. Start work only from an explicit user action, and cancel pending requests when the view is destroyed.

### Routing and disclosure

`llm.chat` uses the user's `chat` role, the `fast` role when `options.role` is `"fast"`, and the `vision` role whenever a message carries images. `text.embed` uses the `embed` role. `text.translate` uses the `translate` role when the user has set one and otherwise the `translate-shell` helper, which is a network service. `image.ocr`, `image.barcode` and `pdf.text` always run on the local machine.

Every call says where it runs before any data leaves: `{ execution: "local" | "remote", provider, host, model }`. `available(name, instanceId)` returns the same disclosure, so a view can show it next to its Run button:

```qml
readonly property var chatAvailability: services.capabilities.available("llm.chat", instanceId)

Text {
    visible: chatAvailability.available
    text: chatAvailability.available ? chatAvailability.disclosure.model + " · " + chatAvailability.disclosure.host : ""
}
```

`local` means the request goes to this machine (`localhost`, `127.x.y.z`, `::1`) and the model runs there. Ollama models tagged `cloud` (for example `name:cloud` or `name-cloud`) are served through the local daemon but forwarded to ollama.com, so they are disclosed as `remote`. A loopback proxy that forwards elsewhere (for example a local LiteLLM gateway) is reported as `local`; the user who set it up owns that choice.

When `available` is false, `reason` says why: `not-configured` (the user has bound no model to the role), `denied`, `unsupported`, `preview`, `safe-mode`, or another documented reason. A role that is not configured or not reachable is reported as such. The host never substitutes another role or falls back from a local model to a remote one.

### Remote consent, preview and safe mode

- A widget that is not built into Pentad reaches a remote provider only after the user grants it remote access in the Models settings. Without the grant a remotely routed call fails with `denied`, and `available` returns `denied` together with the disclosure of the refused route. Calls that resolve to a local model need no grant.
- When the user turns on local-only mode, every remotely routed call is `denied`, for every widget.
- In preview nothing runs: every call and `available` report `preview`.
- In safe mode only the local operations run (`image.ocr`, `image.barcode`, `pdf.text`). `llm.chat`, `text.embed` and `text.translate` report `safe-mode`.

Content from the clipboard, the screen or a file is data, not instructions. Send it as a `user` message, keep your own instructions in the `system` message, and never act on model output without an explicit user step. API keys stay in the host: a widget never receives a key, a provider URL or a credential reference.

Run the contract and catalog logic tests with `pnpm run test:qs:logic`, build the shell with `pnpm run build:qs`, and use `pnpm run check:qs` for host Quickshell checks.

Example API v1 views receive the same five properties regardless of slot or output. The shared `services.media` object is the same adapter for every view instance.

The built-in `pentad.audio-mixer` reuses one view in `sidebar-right` (under the main audio controls), `sidebar-left`, or as an icon with an attached popover in `tools`/`system`. New configurations enable `mixer-main` in the right menu and provide a disabled `mixer-bar` placement. Existing saved layouts gain disabled placements only where missing. Enable or move these placements in the layout editor; enabling both provides the menu and bar forms simultaneously. For custom placements, use a unique `instanceId`, `moduleId: "pentad.audio-mixer"`, one of these slots, `enabled: true`, and `settings: {}`.

`services.audio.state.value.streams` contains playback streams with lifetime-safe `id`, application/media labels, confirmed `volume`/`muted`, and `pendingVolume`, `pendingMute`, `requestedVolume`. Use the lifetime token with `setStreamVolume(id, 0..1)` or `toggleStreamMute(id)`; both return request IDs and emit the adapter's `commandFinished` signal. Retain a unique consumer ID via `retainMixer` only while displayed, and call `releaseMixer` on hiding/destruction. Stream tracking stops after the last consumer releases. This is a volume/mute mixer, and does not match every stream to a particular window or browser tab.
