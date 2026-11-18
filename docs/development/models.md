# Models: providers, roles and keys

Pentad has one shared place for the AI models its widgets use. You describe the model servers you have once, say which model plays which role, and every widget that asks for a [capability](../../packages/widget-api/v1/README.md#capabilities) such as `llm.chat` or `text.embed` follows your choice. A widget never names a model, a URL or a key.

The shell runs the calls through the [resident worker](worker.md), so nothing blocks the interface.

Status: the configuration is the `models` document described here. A Models page in the settings window is planned but not built yet. Until it exists there are two ways to fill the document: the chat widget's setup card, or editing the JSON file by hand (see [The chat widget](#the-chat-widget)).

## The document

`$XDG_CONFIG_HOME/pentad/models.json` (`~/.config/pentad/models.json` when the variable is unset). A missing file means the defaults: no providers and every role empty, so every model capability reports `not-configured`. The default is in `quickshell/defaults/models.json`; the rules are in `quickshell/logic/models.mjs`, and an invalid document is rejected with a message that names the offending key, like any other config document.

```json
{
  "schemaVersion": 1,
  "providers": [
    {
      "id": "local",
      "kind": "ollama",
      "name": "Ollama",
      "baseUrl": "http://127.0.0.1:11434",
      "credential": "",
      "credentialEnv": ""
    },
    {
      "id": "openai",
      "kind": "openai-compatible",
      "name": "OpenAI",
      "baseUrl": "https://api.openai.com/v1",
      "credential": "secret://pentad/providers/openai",
      "credentialEnv": ""
    }
  ],
  "roles": {
    "chat": "openai/gpt-5-mini",
    "fast": "local/qwen3.5:0.8b",
    "vision": "",
    "embed": "local/embeddinggemma-2:270m",
    "translate": "local/qwen3.5:9b"
  },
  "roleOptions": {
    "fast": { "keepAlive": "10m" },
    "translate": { "think": false }
  },
  "grants": {
    "example.summarizer": { "remote": true }
  },
  "privacy": { "localOnly": false },
  "worker": { "idleExitSeconds": 600, "cacheMiB": 64 }
}
```

The model names above are examples; use whatever your servers offer.

| Key | Meaning |
| --- | --- |
| `providers` | Up to 32 model servers. `id` is unique and matches `^[a-z0-9][a-z0-9-]{0,31}$`. `kind` is `ollama`, `openai-compatible`, `anthropic` or `gemini`. `name` is shown to people and defaults to the id. `baseUrl` is the server's base URL (see the endpoint rule). |
| `providers[].credential` | Empty, or a `secret://pentad/<path>` reference to a key in the keyring. |
| `providers[].credentialEnv` | Empty, or the name of an environment variable (`^[A-Z_][A-Z0-9_]{0,127}$`). Used only when `credential` is empty. |
| `roles` | Role name to `"<providerId>/<model>"`, split at the first slash, so model names may contain colons and slashes. Empty means not configured. |
| `roleOptions.<role>` | `keepAlive`: an Ollama duration such as `"5m"`, `"30s"` or `"-1"`, passed to Ollama; empty leaves residency to Ollama. `think`: `true` lets a thinking model reason before it answers (see below). |
| `grants.<widgetId>.remote` | `true` lets that external widget use a remote model. |
| `privacy.localOnly` | `true` refuses every remote model for every widget. |
| `worker.idleExitSeconds` | Seconds without work before the worker exits (10 to 86400, default 600). |
| `worker.cacheMiB` | Size of the worker's result cache (1 to 1024, default 64). It applies the next time the worker starts. |

Roles Pentad routes to: `chat`, `fast`, `vision`, `embed` and `translate`. Other role keys are kept in the file but nothing uses them yet. Unknown top-level and provider keys are preserved too, so a newer version's file survives a round trip through an older one.

A key written into the document is refused. Any key whose words include `password`, `secret`, `token`, `apiKey`, `bearer` or `authorization` anywhere in the document, nested or not, makes it invalid; use `credential` or `credentialEnv` instead.

## Routing

- `llm.chat` uses the `chat` role, the `fast` role when the widget asks for it, and the `vision` role whenever a message carries images. A missing `vision` role is reported; it is never replaced by `chat`.
- `text.embed` uses `embed`.
- `text.translate` uses `translate` when it is set. When it is plainly empty, the `trans` helper (translate-shell) runs instead, and its disclosure is `remote` with provider `translate-shell`, because it sends the text to an online translation service. Safe mode refuses it.
- `image.ocr`, `image.barcode` and `pdf.text` run on this machine and need no model.

A role that points at a provider the document no longer has is `unavailable` with reason `unknown-provider`. A local role whose server is down is reported as unavailable; it never falls back to a remote one.

## Endpoints, local and remote

The endpoint rule: `https` is accepted for any host, `http` only for this machine (`localhost`, `127.x.y.z` and `::1`). A URL with credentials, a query or a fragment is refused, because keys travel in request headers only. The same rule is checked again inside the worker before a connection is opened.

A provider is **local** when its endpoint is on this machine, and **remote** otherwise. Ollama models whose name ends in `cloud` (`name:cloud` or `name-cloud`) are served through the local daemon but forwarded to ollama.com, so they count as remote even on `127.0.0.1`. A loopback proxy that forwards elsewhere, such as a local gateway, is reported as local; whoever configured it owns that choice.

Every call reports `{ execution, provider, host, model }` before any data leaves. A widget can show it next to its Run button.

## Keys

Keys never go in the JSON file, in a widget setting, on a command line or into a log. Use one of two sources.

**The system keyring.** Pentad stores and reads keys through `secret-tool` (package `libsecret`) and a Secret Service such as GNOME Keyring or KWallet. The reference `secret://pentad/providers/openai` means the keyring item with the attribute `pentad-ref` equal to `providers/openai`. Store the key once from a terminal; `secret-tool` reads the value from standard input, so it stays out of the shell history and the process list:

```sh
secret-tool store --label "Pentad providers/openai" pentad-ref providers/openai
```

Then set `"credential": "secret://pentad/providers/openai"` on the provider. Each path segment uses only lowercase letters, digits, dot, underscore and hyphen. There is no plaintext fallback: without `secret-tool` or without a Secret Service the provider is simply unavailable.

**An environment variable.** Put the variable's name, upper case, in `credentialEnv` (for example `"OPENAI_API_KEY"`). The shell must have it in its environment when it starts. `credential` wins when both are set. An unset variable is reported as unavailable.

The worker resolves the key itself and sends it only as the provider's authentication header (`Authorization: Bearer`, `x-api-key` or `x-goog-api-key`), never in a URL. It scrubs the key from every message it returns.

Known limit: `secret-tool` answers the same way for an item that is absent and for a locked keyring that cannot ask for the password, so a locked keyring shows up as a missing key.

## Consent, preview and safe mode

- A built-in widget may use a remote model because you bound that role yourself.
- An external widget gets a remote route only when `grants["<widget id>"].remote` is `true`. Without it the call fails with `denied`, and `available` returns the refused route's disclosure.
- `privacy.localOnly: true` denies every remote route for every widget.
- In **preview** nothing starts and every call reports `preview`.
- In **safe mode** only the local operations run (`image.ocr`, `image.barcode`, `pdf.text`). Chat, embeddings, translation and secret operations report `safe-mode`.

Model output is data. The host sends user content as `user` messages, never executes model output, and an action derived from an answer needs an explicit step from you.

## The chat widget

The built-in chat (`pentad.chat`, manifest 1.1.0) declares `llm.chat` and has a **model source**:

- **Models** (`modelSource: "registry"`): the chat uses the `chat` role, or `fast` when its `modelRole` says so. This is the default for new placements.
- **Custom** (`modelSource: "custom"`): the chat keeps its own endpoint from the legacy fields (`provider`, `baseUrl`, `model`, `apiKeyEnv`, `credentialRef`). The call still goes through the worker, is disclosed and follows local-only mode.

Existing layouts are migrated once when the layout is read: a chat placement without `modelSource` becomes `custom` when it has a non-empty `baseUrl` or `model`, otherwise `registry`. All legacy keys are kept, and a stored `modelSource` always wins.

The chat header shows where the answer comes from, for example "Локально · qwen3.5:9b" or "Хмара · api.openai.com · gpt-4o". Two explicit actions fill the `models` document; neither runs on its own:

- **Connect local Ollama** (shown when no model is bound to `chat`): lists the models of `http://127.0.0.1:11434`, adds a `local` provider (or reuses one with the same endpoint) and binds only empty roles: `chat` to the largest completion model of at most 10 GB that is not a `cloud` model, `fast` to the smallest, `vision` to the chat model when it reports vision, and `embed` to the first embedding model.
- **To Models** (on a custom placement): imports that endpoint as a provider and binds the role when it is empty, then switches the placement to Models. If the role is already bound, nothing is written and the chat says which model holds it.

The chat warms its model once per presentation, when the pointer reaches the message field or the field takes focus, not merely because the panel opened, so an idle sidebar does not hold a model in memory.

## Warm-up and thinking models

`services.capabilities.warm(name)` loads the role's model before the first Run, so the first answer does not wait for a cold start. For an Ollama provider on this machine it sends an empty chat request carrying the role's `keepAlive`; for every other provider it does nothing and returns `{ ok: true, warming: false }`. It is authorized like a call, so a widget needs the capability declared. Pentad passes `keepAlive` only when a role sets it and does not fight Ollama's own unloading.

Requests send `think: false` unless the role has `roleOptions.<role>.think: true`, so a thinking model answers directly instead of spending time on a reasoning pass. Older Ollama builds that reject `think` for a model without a thinking mode are retried once without it. Very small models translate poorly; point `translate` at a larger one.

## Running the live tests

The default test suites never touch the real keyring or a real model; they use fake programs and a loopback HTTP server. The live check is opt-in and talks to your own Ollama on `http://127.0.0.1:11434`:

```sh
PENTAD_LIVE_OLLAMA=1 timeout 600 python3 -m unittest tests.tools.test_pentad_worker_live -v
```

It needs two small models pulled beforehand, `qwen3.5:0.8b` (list, warm-up and streamed chat) and `embeddinggemma-2:270m` (embeddings). Nothing is pulled, deleted or unloaded; requests use a 30 s `keepAlive`. Timings are printed to stderr.

## Known limits

- Remote providers (OpenAI-compatible, Anthropic, Gemini) are verified only against fake servers in the tests, not against the real services.
- The worker connects straight to the endpoint: no HTTP proxy support for remote providers yet, and redirects are not followed.
- A result line is at most 2 MiB; an embedding answer larger than that fails with `io`. Embeddings take at most 64 strings per call.
- `llm.chat` text is limited to 512 KiB per call and the model's answer to 1 MiB; images are at most 8 MiB each (PNG, JPEG, WebP or GIF).
- The Models settings page does not exist yet; providers are added by the chat's quick setup, by "To Models", or by hand.
