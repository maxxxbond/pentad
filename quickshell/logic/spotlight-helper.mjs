// Client side of the persistent Spotlight helper protocol (tools/pentad_spotlight.py --serve).
// One request per line: {"id":n,"request":{...}}; one reply per line: {"id":n,"result":{...}}.
// The QML adapter owns the process and timers; this model owns ids and pending callbacks,
// so a reply is delivered at most once and a reply nobody waits for any more is dropped.
// Methods return `lines` to write to the helper and `calls`, [done, result] pairs for the
// caller to invoke once the bookkeeping is consistent.
//
// The helper answers in order, so a request made per keystroke (file search) passes a `key`:
// at most one request per key is in flight, and while it runs only the newest one waits;
// older waiting ones settle at once as `superseded` and never cost a search.

export const HELPER_REQUEST_LIMIT = 1024 * 1024;

export class HelperClient {
  constructor() {
    this.nextId = 1;
    this.entries = new Map();
    this.ready = false;
  }
  get idle() { return this.entries.size === 0; }
  get waiting() {
    for (const entry of this.entries.values()) if (entry.sent) return true;
    return false;
  }
  // Returns { lines, calls }, or { error } when the request can never be sent.
  request(payload, done, key) {
    if (typeof done !== 'function') return { error: 'invalid' };
    if (!payload || typeof payload !== 'object' || Array.isArray(payload)) return { error: 'invalid' };
    let body = '';
    try { body = JSON.stringify(payload); } catch (error) { return { error: 'invalid' }; }
    const id = this.nextId++;
    const line = `{"id":${id},"request":${body}}\n`;
    if (line.length - 1 > HELPER_REQUEST_LIMIT) return { error: 'io' };
    const calls = [];
    const group = typeof key === 'string' && key ? key : '';
    if (group) for (const [other, entry] of [...this.entries]) {
      if (entry.key !== group || entry.sent) continue;
      this.entries.delete(other);
      calls.push([entry.done, { ok: false, reason: 'superseded' }]);
    }
    this.entries.set(id, { done, line, key: group, sent: false });
    return { lines: this.flush(), calls };
  }
  // Marks and returns every line that may go out now, in request order.
  flush() {
    if (!this.ready) return [];
    const busy = new Set();
    for (const entry of this.entries.values()) if (entry.sent && entry.key) busy.add(entry.key);
    const lines = [];
    for (const entry of this.entries.values()) {
      if (entry.sent || (entry.key && busy.has(entry.key))) continue;
      entry.sent = true;
      if (entry.key) busy.add(entry.key);
      lines.push(entry.line);
    }
    return lines;
  }
  // The process is running: everything queued may go out.
  started() {
    this.ready = true;
    return this.flush();
  }
  // The process is going away (idle stop, kill): later requests queue for the next one.
  retire() { this.ready = false; }
  receive(text) {
    let message;
    try { message = JSON.parse(text); } catch (error) { return { calls: [], lines: [], broken: true }; }
    if (!message || typeof message !== 'object' || Array.isArray(message)) return { calls: [], lines: [], broken: true };
    const entry = Number.isSafeInteger(message.id) ? this.entries.get(message.id) : undefined;
    if (!entry || !entry.sent) return { calls: [], lines: [], broken: false };
    this.entries.delete(message.id);
    const result = message.result && typeof message.result === 'object' && !Array.isArray(message.result)
      ? message.result : { ok: false, reason: 'io' };
    return { calls: [[entry.done, result]], lines: this.flush(), broken: false };
  }
  fail(reason, includeQueued) {
    const calls = [];
    for (const [id, entry] of [...this.entries]) {
      if (!includeQueued && !entry.sent) continue;
      this.entries.delete(id);
      calls.push([entry.done, { ok: false, reason }]);
    }
    return calls;
  }
  // No reply arrived in time: fail what the process holds; queued requests wait for a restart.
  timeout() {
    this.ready = false;
    return this.fail('timeout', false);
  }
  // The process exited (`started`) or never started. Requests it held fail; requests queued
  // while it was going away ask for a restart, unless it could not start at all.
  stopped(started) {
    this.ready = false;
    const calls = this.fail(started ? 'io' : 'unavailable', !started);
    return { calls, restart: this.entries.size > 0 };
  }
}
