// Client side of the Pentad worker protocol v1 (tools/pentad_worker.py), spec section 7.
// One UTF-8 JSON object per line in each direction. The QML adapter (Worker.qml) owns the
// Process, the 5 s hello timer and the restart timer; this model owns ids, queueing before
// hello, callbacks keyed by id and the restart/backoff decision. It never touches a process:
// it is given write(line) (the line already ends in a newline) and is fed receive(line).
//
// Every request gets exactly one onResult call with a plain object:
//   { ok: true, value, cached? }  or  { ok: false, reason, message? }
// including `service-stopped` when the worker dies, `cancelled` and `unavailable`.
// Callbacks only ever receive plain JSON objects (no arrays at the top level of a signal).

export const WORKER_PROTOCOL = 1;
export const WORKER_REQUEST_LIMIT = 1024 * 1024;
export const WORKER_HELLO_TIMEOUT_MS = 5000;
export const WORKER_BACKOFF_MS = [1000, 2000, 4000, 8000, 16000, 30000];
export const WORKER_CRASH_LIMIT = 5;
export const WORKER_CRASH_WINDOW_MS = 120000;
export const WORKER_DEFAULT_TIMEOUT_MS = 120000;
export const WORKER_LLM_TIMEOUT_MS = 600000;
// Ops of protocol v1: what accepts() answers for before the worker has said hello.
export const WORKER_OPS = [
  'file.run', 'image.ocr', 'image.barcode', 'pdf.text', 'ocr.languages', 'text.translate',
  'llm.chat', 'llm.embed', 'llm.models', 'llm.warm', 'secret.status', 'secret.store', 'secret.clear', 'worker.stats'
];

const isPlain = value => !!value && typeof value === 'object' && !Array.isArray(value);
const fail = (reason, message) => ({ ok: false, reason, message: message || '' });

export function defaultTimeoutMs(op) {
  return typeof op === 'string' && op.indexOf('llm.') === 0 ? WORKER_LLM_TIMEOUT_MS : WORKER_DEFAULT_TIMEOUT_MS;
}

// Returns the line to write (with newline), or null when the request cannot be encoded
// or exceeds the 1 MiB request limit.
export function encodeRequest(id, op, payload, timeoutMs) {
  let body = '';
  try { body = JSON.stringify({ type: 'request', id, op, payload: payload === undefined ? {} : payload, timeoutMs }); } catch (error) { return null; }
  if (typeof body !== 'string' || utf8Length(body) > WORKER_REQUEST_LIMIT) return null;
  return body + '\n';
}

// The worker limits bytes, not UTF-16 code units: Cyrillic text is two bytes per character.
export function utf8Length(text) {
  let bytes = 0;
  for (let i = 0; i < text.length; i++) {
    const code = text.charCodeAt(i);
    if (code < 0x80) bytes += 1;
    else if (code < 0x800) bytes += 2;
    else if (code >= 0xd800 && code <= 0xdbff && i + 1 < text.length) { bytes += 4; i++; }
    else bytes += 3;
  }
  return bytes;
}

export function encodeCancel(id) { return JSON.stringify({ type: 'cancel', id }) + '\n'; }
export function encodeShutdown() { return JSON.stringify({ type: 'shutdown' }) + '\n'; }

// Parses one worker line: { message } for a JSON object, { empty } for a blank line, { error } otherwise.
export function decodeLine(line) {
  if (typeof line !== 'string') return { error: true };
  const text = line.trim();
  if (!text) return { empty: true };
  let message = null;
  try { message = JSON.parse(text); } catch (error) { return { error: true }; }
  return isPlain(message) && typeof message.type === 'string' ? { message } : { error: true };
}

export function backoffMs(crashes) {
  const index = Math.max(0, Math.min(WORKER_BACKOFF_MS.length - 1, crashes - 1));
  return WORKER_BACKOFF_MS[index];
}

export class WorkerClient {
  // options: { write(line), now() } ; now defaults to Date.now.
  constructor(options) {
    const opts = options || {};
    this.writeLine = typeof opts.write === 'function' ? opts.write : () => {};
    this.clock = typeof opts.now === 'function' ? opts.now : () => Date.now();
    this.nextId = 1;
    this.entries = new Map();   // id -> { op, onProgress, onPartial, onResult, timeoutMs, line, sent }
    this.crashes = [];
    this.opSet = null;          // ops announced by the last hello
    this.retiring = false;
    this.state = 'idle';        // idle | starting | ready | crash-loop | unavailable
    this.lastActivityMs = this.clock();
  }

  get busyCount() { return this.entries.size; }

  // True when requests wait and no process is running or coming: the adapter should start one.
  get needsStart() { return this.state === 'idle' && this.entries.size > 0; }

  // Whether the worker takes this op: any v1 op while it can still start, the announced set when ready.
  accepts(op) {
    if (typeof op !== 'string') return false;
    if (this.state === 'crash-loop' || this.state === 'unavailable') return false;
    if (this.state === 'ready' && this.opSet) return this.opSet.has(op);
    return WORKER_OPS.indexOf(op) >= 0;
  }

  // Returns the request id. onResult is called exactly once, possibly before this returns.
  request(op, payload, options) {
    const opts = options || {};
    const id = this.nextId++;
    const entry = {
      op,
      onProgress: typeof opts.onProgress === 'function' ? opts.onProgress : null,
      onPartial: typeof opts.onPartial === 'function' ? opts.onPartial : null,
      onResult: typeof opts.onResult === 'function' ? opts.onResult : null,
      timeoutMs: Number.isFinite(opts.timeoutMs) && opts.timeoutMs > 0 ? Math.floor(opts.timeoutMs) : defaultTimeoutMs(op),
      line: '',
      sent: false
    };
    this.lastActivityMs = this.clock();
    if (typeof op !== 'string' || !op) { this.settle(entry, fail('invalid-input', 'missing op')); return id; }
    if (payload !== undefined && !isPlain(payload)) { this.settle(entry, fail('invalid-input', 'payload must be an object')); return id; }
    if (this.state === 'crash-loop' || this.state === 'unavailable') { this.settle(entry, fail('unavailable', this.state)); return id; }
    if (this.state === 'ready' && this.opSet && !this.opSet.has(op)) { this.settle(entry, fail('unsupported', op)); return id; }
    entry.line = encodeRequest(id, op, payload, entry.timeoutMs);
    if (entry.line === null) { this.settle(entry, fail('invalid-input', 'request is larger than 1 MiB or not serializable')); return id; }
    this.entries.set(id, entry);
    if (this.state === 'ready' && !this.retiring) this.send(entry);
    return id;
  }

  // Queued requests settle at once as cancelled; sent ones get a cancel line and the worker's result.
  cancel(id) {
    const entry = this.entries.get(id);
    if (!entry) return false;
    if (!entry.sent) {
      this.entries.delete(id);
      this.settle(entry, fail('cancelled'));
      return true;
    }
    this.writeLine(encodeCancel(id));
    return true;
  }

  // The process is running: wait for hello. Returns the same shape as stopped().
  started() {
    if (this.state === 'crash-loop' || this.state === 'unavailable') return this.decision(false, 0);
    this.state = 'starting';
    this.retiring = false;
    this.opSet = null;
    for (const entry of this.entries.values()) entry.sent = false;
    this.lastActivityMs = this.clock();
    return this.decision(false, 0);
  }

  // The 5 s hello timer fired. The adapter must kill the process (kill: true); no restart follows.
  helloTimedOut() {
    if (this.state !== 'starting') return this.decision(false, 0);
    this.makeUnavailable();
    const out = this.decision(false, 0);
    out.kill = true;
    return out;
  }

  // The process ended. Returns { restart, delayMs, state }.
  stopped(nowMs) {
    const at = Number.isFinite(nowMs) ? nowMs : this.clock();
    this.lastActivityMs = at;
    this.opSet = null;
    if (this.state === 'unavailable' || this.state === 'crash-loop') return this.decision(false, 0);
    const intentional = this.retiring;
    this.retiring = false;
    // Sent requests are lost with the process and never replayed; queued ones survive.
    const lost = [];
    for (const [id, entry] of [...this.entries]) if (entry.sent) { this.entries.delete(id); lost.push(entry); }
    for (const entry of lost) this.settle(entry, fail('service-stopped', 'worker stopped'));
    if (intentional) {
      this.state = 'idle';
      return this.decision(this.entries.size > 0, 0);
    }
    const kept = [];
    for (const time of this.crashes) if (at - time < WORKER_CRASH_WINDOW_MS) kept.push(time);
    kept.push(at);
    this.crashes = kept;
    if (this.crashes.length >= WORKER_CRASH_LIMIT) {
      this.state = 'crash-loop';
      this.failQueued('unavailable', 'crash-loop');
      return this.decision(false, 0);
    }
    const restart = this.entries.size > 0;
    this.state = restart ? 'starting' : 'idle';
    return this.decision(restart, backoffMs(this.crashes.length));
  }

  // Intentional stop (idle exit, shell shutdown): asks the worker to shut down; not a crash.
  // The adapter then closes the process and calls stopped() as usual.
  retire() {
    if (this.state === 'idle') return;
    this.retiring = true;
    if (this.state === 'ready') this.writeLine(encodeShutdown());
  }

  // Leaves crash-loop / unavailable, e.g. after the user asks to retry.
  reset() {
    this.crashes = [];
    this.retiring = false;
    if (this.state === 'crash-loop' || this.state === 'unavailable') this.state = 'idle';
  }

  // Feeds one stdout line. Returns { kill: true } when the process must be killed.
  receive(line) {
    const decoded = decodeLine(line);
    if (decoded.empty) return { kill: false };
    this.lastActivityMs = this.clock();
    if (decoded.error) return { kill: false };
    const message = decoded.message;
    if (message.type === 'hello') return this.hello(message);
    if (this.state !== 'ready') return { kill: false };
    const id = message.id;
    if (!Number.isInteger(id) || !this.entries.has(id)) return { kill: false };
    const entry = this.entries.get(id);
    if (message.type === 'progress') {
      if (entry.onProgress) this.guard(entry.onProgress, isPlain(message.data) ? message.data : {});
    } else if (message.type === 'partial') {
      if (entry.onPartial) this.guard(entry.onPartial, isPlain(message.chunk) ? message.chunk : {});
    } else if (message.type === 'result') {
      this.entries.delete(id);
      const result = message.result;
      this.settle(entry, isPlain(result) && typeof result.ok === 'boolean' ? result : fail('invalid-response', 'malformed result'));
    }
    return { kill: false };
  }

  hello(message) {
    if (this.state !== 'starting') return { kill: false };
    if (message.protocol !== WORKER_PROTOCOL) {
      this.makeUnavailable();
      return { kill: true };
    }
    this.opSet = new Set(Array.isArray(message.ops) ? message.ops.filter(op => typeof op === 'string') : []);
    this.state = 'ready';
    for (const [id, entry] of [...this.entries]) {
      if (!this.opSet.has(entry.op)) { this.entries.delete(id); this.settle(entry, fail('unsupported', entry.op)); }
      // A retire during start keeps queued work for the next process instead of losing it.
      else if (!this.retiring) this.send(entry);
    }
    return { kill: false };
  }

  send(entry) {
    entry.sent = true;
    this.writeLine(entry.line);
  }

  makeUnavailable() {
    this.state = 'unavailable';
    this.failQueued('unavailable', 'worker unavailable');
  }

  failQueued(reason, message) {
    const all = [...this.entries.values()];
    this.entries.clear();
    for (const entry of all) this.settle(entry, fail(reason, message));
  }

  settle(entry, result) {
    if (entry.onResult) this.guard(entry.onResult, result);
  }

  guard(callback, value) {
    try { callback(value); } catch (error) { /* a failing callback must not break the protocol loop */ }
  }

  decision(restart, delayMs) {
    return { restart: restart, delayMs: delayMs, state: this.state };
  }
}
