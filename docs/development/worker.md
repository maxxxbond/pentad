# The resident worker

The worker is one long-lived Python process, `tools/pentad_worker.py`, that the shell supervises. It runs OCR, barcode and PDF jobs, the sidebar file tools, model calls and key lookups off the QML thread, queues and cancels them, and caches deterministic results. This page is for contributors; users configure models in [models](models.md), and widget authors use the [capabilities contract](../../packages/widget-api/v1/README.md#capabilities).

## Why a resident process

The QML engine is single-threaded: a model call, an OCR run or a large file read on it freezes the interface. Before the worker, every helper call also started a fresh Python process. One supervised process keeps the interpreter and its imports warm, memoises `tesseract --version` and the installed OCR languages, bounds the number of concurrent jobs and gives every job one cancel path. It uses only the Python standard library.

"Warm" here is honest and small: a live process, those memoised facts and the result cache. There is no in-process OCR engine, and Ollama keeps its own model residency.

## Pieces

| File | Role |
| --- | --- |
| `tools/pentad_worker.py` | The server: protocol loop, queue, timeouts, cancel, shutdown and the built-in ops. Its docstring is the short reference. |
| `tools/pentad_worker_llm.py` | `llm.*` and `text.translate` ops: Ollama, OpenAI-compatible, Anthropic and Gemini over plain HTTP. |
| `tools/pentad_secrets.py` | `secret.*` ops and key resolution through `secret-tool`. |
| `tools/pentad_worker_cache.py` | The result cache. |
| `quickshell/logic/worker-protocol.mjs` | The client side: ids, queueing before hello, callbacks and the restart decision. Pure, tested with `node:test`. |
| `quickshell/services/Worker.qml` | Owns the `Process`, the hello timer, the restart timer and the idle timer. `services.worker` on the shared container, for built-in services only: widget views and controllers are not given it. |
| `quickshell/services/Capabilities.qml` | The capability service: binds widgets to manifests (`attach`/`detach`, host only) and sends capability calls. Policy lives in `quickshell/logic/capabilities.mjs`. |
| `quickshell/plugins/WidgetServices.qml`, `CapabilityFacade.qml` | What a widget receives as `services` and `services.capabilities`: for a built-in widget the container without the worker, for an external one only the documented services (`quickshell/logic/widget-services.mjs`), and the capability service fixed to that widget's instance (`quickshell/logic/capability-port.mjs`). |
| `quickshell/services/FileTools.qml` | Sends `file.run` to the worker, and falls back to the one-shot `pentad_file_tool.py` when the worker is unavailable or does not know the op. |
| `quickshell/logic/models.mjs` | The `models` document and role resolution. |

The shell starts it as `python3 -I pentad_worker.py --serve --cache-root <dir> --cache-mib <n>`. `-I` keeps the script directory off `sys.path`, so the worker appends its own directory itself, after the standard library.

## Lifecycle

- **Lazy start.** Nothing runs until the first request. Preview never starts a process; every request answers `preview`.
- **Hello.** The host sends nothing before the worker's `hello`. No `hello` within 5 s, or a `protocol` other than 1, kills the process and the worker becomes `unavailable`; queued requests fail with `unavailable`. It recovers by itself on later use (see Recovery), and `retry()` clears the state at once.
- **Idle exit.** With no request in flight for `worker.idleExitSeconds` (default 600), the host sends `shutdown` and closes the process. This is not a crash. The next request starts a new worker.
- **Crash restart.** An unexpected exit restarts the worker while requests are waiting, with a delay of 1, 2, 4, 8, 16, then 30 s. Five crashes within 120 s put the client in `crash-loop`: queued and new requests fail with `unavailable` until the worker recovers.
- **Recovery.** A worker that is `unavailable` or in `crash-loop` gets one fresh start per 30 s: the first capability call, warm-up, model listing or file tool run made at least 30 s after it went down resets the client and starts a new process. If that one fails too, the 30 s start again. Reading availability never restarts it.
- **Requests that were already sent** when the process died fail with `service-stopped` and are never replayed. Requests still queued in the shell survive and go to the next process.
- **Dies with the shell.** The worker ends when stdin closes, and it sets `PR_SET_PDEATHSIG` (SIGTERM) so it ends even if the shell is killed. On `shutdown`, EOF, SIGTERM or SIGINT it cancels everything, waits up to 3 s for jobs to clean up, answers what is left with `service-stopped` and exits 0.
- **Settings.** `worker.idleExitSeconds` and `worker.cacheMiB` come from the `models` document. A new cache size applies to the next process: `Worker.qml` retires the running one when its command changes.
- **Safe mode.** The worker itself is not stopped in safe mode, but `services.capabilities` refuses everything that is not local (`llm.*`, `text.embed`, `text.translate`, `secret.*`) with `safe-mode` before it reaches the worker.

`services.capabilities.state` exposes `worker: idle | starting | ready | crash-loop` for views that want to show it.

## Protocol v1

One UTF-8 JSON object per line on stdin and stdout. stderr is for diagnostics only, and the worker redirects stray `print` output there so it can never corrupt the stream.

```
worker -> host  {"type":"hello","protocol":1,"worker":"1","ops":["file.run","image.ocr", ...]}
host -> worker  {"type":"request","id":7,"op":"image.ocr","payload":{"uri":"file:///tmp/a.png"},"timeoutMs":120000}
host -> worker  {"type":"cancel","id":7}
host -> worker  {"type":"shutdown"}
worker -> host  {"type":"progress","id":7,"data":{...}}
worker -> host  {"type":"partial","id":7,"chunk":{"text":"..."}}
worker -> host  {"type":"result","id":7,"result":{"ok":true,"value":{"text":"..."},"cached":false}}
worker -> host  {"type":"result","id":7,"result":{"ok":false,"reason":"timeout","message":"..."}}
```

- `id` is a positive integer chosen by the host, unique for the worker's lifetime. The host writes `type` first and `id` second, so a damaged line's id can still be recovered.
- Every accepted request gets exactly one `result`, including after `cancel` (`cancelled`), on a timeout (`timeout`) and on shutdown (`service-stopped`). Nothing is sent for an id after its result.
- A malformed or oversized line whose id can be recovered gets an `invalid-response` result; otherwise it is ignored with a note on stderr. An unknown op answers `unsupported`. A full queue answers `busy`.
- `reason` is a `Result` reason from `packages/widget-api/v1/contracts.d.ts`, plus `cancelled` and `busy`. An op may add a finer `detail`.

### Ops

| Op | Payload | Value |
| --- | --- | --- |
| `file.run` | exactly a `pentad_file_tool.py` job object | that helper's success object |
| `image.ocr` | `{ uri, language?, psm?, filterInstalled? }` | `{ text }` |
| `image.barcode` | `{ uri }` | `{ codes: [{ type, text }] }` |
| `pdf.text` | `{ uri }` | `{ text, truncated }` |
| `ocr.languages` | `{ refresh? }` | `{ languages }` |
| `text.translate` | `{ text, target, source? }` | `{ text }`, through `trans` |
| `llm.chat` | `{ provider, model, messages, temperature?, maxTokens?, keepAlive?, think? }` | `{ text, usage?, finishReason? }`, streamed as `partial({ text })` |
| `llm.embed` | `{ provider, model, input: [string] }` | `{ vectors, dims }` |
| `llm.models` | `{ provider }` | `{ models: [{ name, sizeBytes?, parameterSize?, capabilities? }] }` |
| `llm.warm` | `{ provider, model, keepAlive? }` | `{ warmed, loadMs?, wallMs? }` |
| `secret.status` | `{ ref }` | `{ status: "stored" \| "missing" \| "unavailable" }` |
| `secret.store` | `{ ref, value }` | `{ status: "stored" }` |
| `secret.clear` | `{ ref }` | `{ status: "missing" }` |
| `worker.stats` | none | counters, queue sizes, loaded extensions and cache statistics |

`provider` is `{ kind, baseUrl, credential, credentialEnv }`: references only, never a key value. The worker resolves the key itself. `secret.store` is the one op that carries a secret in its payload, so never log payloads. Capability calls reach the worker through `routeCall` in `logic/capabilities.mjs`, which validates the input and turns a capability into one of these ops.

### Limits

| Limit | Value |
| --- | --- |
| Request line | 1 MiB (the client refuses a larger request with `invalid-input` before sending) |
| Result line | 2 MiB; a larger result becomes an `io` failure, and an oversized progress or partial line is dropped |
| Concurrency | 3 running and 32 queued; more answers `busy` |
| Timeout | `timeoutMs` from the host, default 120 s and 600 s for `llm.*`, at most 1 h |
| Input file | 256 MiB for the cached file ops |
| LLM | model text 1 MiB, connect timeout 8 s, at most 100 messages |

A request's timeout counts from the moment the worker reads it, so time spent queued counts.

### Cancellation

A `cancel` for a queued request answers `cancelled` at once. For a running one, the job's child process groups are killed and its HTTP connection is closed; the job answers `cancelled` when it unwinds. A job that has not unwound 2 s later is answered anyway and finishes in the background. A timeout works the same way with the reason `timeout`. A cancel for an unknown or finished id is ignored. On the host side, `WorkerClient.cancel` settles a request that was never sent immediately, without involving the worker.

## The result cache

- **What is cached:** only deterministic local ops that depend on nothing but the input bytes, the options and the engine version: `image.ocr`, `image.barcode` and `pdf.text`. Never `llm.*`, translations, secret ops or anything derived from a secret.
- **Key:** sha256 over the op, the canonical options, the input's content hash and the engine version (the first line of `tesseract --version` and similar). A changed file, option or engine is a miss; nothing needs invalidating. On a miss the worker copies the input into a private scratch directory and hashes the copy, so a cached result always matches the bytes it was computed from.
- **Fast path:** after a full copy, the worker also records an index entry keyed by the file's real path, device, inode, size, mtime and ctime (from `fstat` on the open descriptor). The next call on the same unchanged file finds its content hash there and answers without copying or hashing: a cached `pdf.text` on a 64 MiB PDF takes about 0.2 ms instead of about 58 ms. A file whose mtime or ctime is less than 3 s old, or that changed during the copy, is never indexed, which covers coarse filesystem timestamps; any change moves ctime, so it misses. Index entries live in the same cache and share its size cap.
- **Cancellation:** long pure-Python loops (input copy and hashing, archive checksums) call `check_cancelled()` per chunk, so a cancelled or timed-out job gives its thread back instead of running to the end.
- **Where:** `$XDG_CACHE_HOME/pentad/worker/` (`~/.cache/pentad/worker/` when unset), a 0700 directory with one 0600 JSON file per entry.
- **Size:** capped by `worker.cacheMiB` (default 64) and 1000 entries; the entries with the oldest modification time go first, and a hit refreshes the entry's time. Any cache failure degrades to a miss and never fails the request.
- A result served from the cache has `cached: true`.

## Adding an op

1. Write `handler(payload, ctx)` in a module the worker can import, returning `{"ok": True, "value": {...}}` or `{"ok": False, "reason": ..., "message": ...}`. Raising `OpError(reason, message)` or `ToolError` works too; any other exception becomes `io`.
2. Honour cancellation: call `ctx.check()` between steps, use `ctx.on_cancel(fn)` to close a socket, and use `pentad_tool_core.run()` for child processes so they are tracked and killed. Report progress with `ctx.progress(dict)` and streamed output with `ctx.partial(dict)`.
3. Expose `register_ops(ops)` that adds your handlers to the table. The worker imports the modules named in `EXTENSIONS` in `pentad_worker.py` (`pentad_secrets`, `pentad_worker_llm`) and calls it; a module that fails to import is skipped with a stderr note. Op names are dotted lowercase (`^[a-z][a-z0-9-]*(\.[a-z][a-z0-9-]*)+$`); an invalid name is dropped.
4. Use `ctx.cache` only for results that depend on nothing but the input, the options and the engine version.
5. Add the op name to `WORKER_OPS` in `worker-protocol.mjs` (the client accepts only listed ops before the worker has said hello), and, if a capability should reach it, to `knownCapabilities` and `routeCall` in `capabilities.mjs`. A new Python module also goes into the helper lists in `scripts/test-quickshell.mjs`, as for any helper.
6. Never log payloads: they may carry secrets.

## Testing

- `node --test tests/quickshell/worker-protocol.test.mjs tests/quickshell/capabilities.test.mjs tests/quickshell/models.test.mjs` covers the client, the policy and the document with no process.
- `python3 -m unittest tests.tools.test_pentad_worker tests.tools.test_pentad_worker_cache tests.tools.test_pentad_worker_llm tests.tools.test_pentad_secrets` runs the real worker over its protocol. Fake `tesseract`, `zbarimg`, `qpdf` and `secret-tool` scripts are put first on `PATH`, and a loopback `http.server` speaks the Ollama, OpenAI, Anthropic and Gemini wire formats, so nothing touches the real keyring, desktop or a model.
- The `worker` fixture exercises `Worker.qml`, `Capabilities.qml` and `FileTools.qml` against the real `pentad_worker.py`, started without its model module so nothing can reach a network, with a recording fake `tesseract` and a stand-in worker that speaks a future protocol. Run it through the isolated runner, for example `node scripts/test-quickshell-headless.mjs --scenario worker --report /tmp/worker-report.json`.
- The opt-in live check against a local Ollama is described in [models](models.md#running-the-live-tests).

## Benchmark

`python3 scripts/bench-worker.py` measures start to hello, the round trip of an empty op, and OCR cold, warm and cached next to bare `tesseract` and the one-shot helper, plus `pdf.text` on generated PDFs. It prints numbers and asserts nothing. Everything runs in a private temporary directory with its own cache root; OCR is skipped without `tesseract`, and the PDF part without `pdftotext` or `qpdf`.

Example numbers from one development machine, not a guarantee: hello in about 53 ms; about 2.5 ms of worker overhead over bare `tesseract`; OCR of a generated image about 112 ms uncached through the worker against about 214 ms for the one-shot helper, and about 0.2 ms from the cache. A warm local chat (`qwen3.5:0.8b` on Ollama) produced its first token in about 74 ms after a cold model load of about 3 s, which is why warm-up matters more than anything else for local models.
