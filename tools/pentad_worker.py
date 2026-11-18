#!/usr/bin/env python3
"""Pentad's resident worker: one long-lived helper that runs model, OCR and file jobs off the
QML thread, queues and cancels them, and caches deterministic results.

Run: `python3 -I tools/pentad_worker.py --serve [--cache-root DIR] [--cache-mib N]`.
The shell supervises it (quickshell/services/Worker.qml); the protocol is documented in
docs/superpowers/specs/2026-11-18-model-services-design.md §7 and summarised here.

Protocol v1: one UTF-8 JSON object per line on stdin/stdout; stderr is diagnostics only.

    worker -> host  {"type":"hello","protocol":1,"worker":"1","ops":[...]}
    host -> worker  {"type":"request","id":7,"op":"image.ocr","payload":{...},"timeoutMs":120000}
    host -> worker  {"type":"cancel","id":7}
    host -> worker  {"type":"shutdown"}
    worker -> host  {"type":"progress","id":7,"data":{...}}
    worker -> host  {"type":"partial","id":7,"chunk":{...}}
    worker -> host  {"type":"result","id":7,"result":{"ok":true,"value":{...},"cached":false}}
    worker -> host  {"type":"result","id":7,"result":{"ok":false,"reason":"timeout","message":"..."}}

- Exactly one `result` per accepted request id, also after `cancel` (`cancelled`), on timeout
  (`timeout`) and on shutdown (`service-stopped`). Nothing is sent for an id after its result.
  Cancel of an unknown or finished id is ignored.
- A request line holds at most 1 MiB; a result line at most 2 MiB (a larger result becomes an
  `io` failure; a larger progress/partial line is dropped). A malformed or oversized line whose
  integer `id` can be recovered gets an `invalid-response` result, otherwise a note on stderr.
- Unknown op -> `unsupported`. At most 3 jobs run and 32 wait; more -> `busy`.
- `timeoutMs` counts from the moment the worker reads the request (default 120 s, 600 s for
  `llm.*`, at most 1 h). On cancel or timeout the job's child process groups are killed; a job
  that has not unwound 2 s later is answered anyway and finishes in the background.
- stdin EOF, `shutdown`, SIGTERM or SIGINT: cancel everything, wait up to 3 s for jobs to clean
  up, answer what is left with `service-stopped`, exit 0. The worker gets PR_SET_PDEATHSIG
  (SIGTERM) so it dies with the shell. Idle exit is the host's job: it closes stdin.

Ops: `ops` maps an op name to `handler(payload, ctx) -> result`. The built-in ones are
`file.run` (payload is exactly a `pentad_file_tool.py` job object; value is exactly that
helper's success object), `image.ocr` ({uri, language?, psm?, filterInstalled?} -> {text}),
`image.barcode` ({uri} -> {codes: [{type, text}]}), `pdf.text` ({uri} -> {text, truncated}),
`ocr.languages` ({refresh?} -> {languages}), `worker.stats` and `worker.clear-cache` (empties the
result cache, only inside its root -> {removed, cache}). After them the worker imports
`pentad_secrets`, `pentad_worker_llm` and `pentad_worker_system` when present and calls their
`register_ops(ops)`.

A handler returns `{"ok": True, "value": {...}, "cached": bool}` or
`{"ok": False, "reason": <Result reason>, "message": str, "detail"?: str}`, where the reason
is one of the `Result` reasons of packages/widget-api/v1/contracts.d.ts plus `cancelled` and
`busy`, and `detail` an optional finer cause; an unknown reason is reported as `io` with the
original in `detail`. A handler may also raise
`OpError(reason, message)`, `pentad_tool_core.ToolError` (its `reason`, default `io`) or
`pentad_tool_core.Cancelled`; any other exception becomes `io`.

`ctx`, one per request:
- `ctx.request_id`, `ctx.op`: the host's id and the op name.
- `ctx.timeout_s`: the request's time limit in seconds; `ctx.deadline` (time.monotonic()) and
  `ctx.remaining()` for what is left of it.
- `ctx.cancelled()` -> bool; `ctx.check()` raises `Cancelled` once cancelled (also on timeout
  and shutdown).
- `ctx.on_cancel(fn)`: call `fn()` from another thread on cancel (at once if already
  cancelled), e.g. to close an HTTP response the job is reading. Keep it quick; never raise.
- `ctx.progress(dict)` / `ctx.partial(dict)`: send a progress or partial line; False when it
  was not sent (request already answered, line too large or not JSON).
- `ctx.cache_root`: the cache directory; `ctx.cache`: the WorkerCache, only for results that
  depend on nothing but the input bytes, options and engine version (never `llm.*`,
  translations or anything derived from a secret).
- CLIs started through `pentad_tool_core.run()` inside a handler are tracked and killed on
  cancel. A pure-Python loop over input bytes (copy, hash) cannot be killed, so it calls
  `pentad_tool_core.check_cancelled()` once per chunk; otherwise a cancelled job keeps its
  thread after the grace. Never log payloads: they may carry secrets.

The cached ops copy their input into a private directory and key the result by the copy's
content hash. A settled file's stat key (see `_Input`) maps to that hash in the same cache,
so a repeated request for an unchanged file is answered without copying or hashing it.
"""
import argparse
import base64
import hashlib
import importlib
import json
import mimetypes
import os
import queue
import re
import signal
import stat
import sys
import tempfile
import threading
import time
import traceback
from pathlib import Path

# Sibling modules live next to this file. `python3 -I` leaves the script directory off
# sys.path; append it (never prepend) so the standard library still wins.
_HERE = os.path.dirname(os.path.abspath(__file__))
if _HERE not in sys.path:
    sys.path.append(_HERE)

import pentad_file_tool as file_tool  # noqa: E402
import pentad_tool_core as core  # noqa: E402
import pentad_tool_image as image  # noqa: E402
import pentad_tool_pdf as pdf  # noqa: E402
from pentad_tool_core import MAX_TEXT, Cancelled, Job, ToolError, check_cancelled, file_path, run, split_name  # noqa: E402
from pentad_worker_cache import WorkerCache, cache_key, default_root  # noqa: E402
from pentad_worker_cache import stat_key as input_stat_key  # noqa: E402

PROTOCOL = 1
WORKER_VERSION = '1'
MAX_REQUEST_LINE = 1024 * 1024
MAX_RESULT_LINE = 2 * 1024 * 1024
MAX_RUNNING = 3
MAX_QUEUED = 32
DEFAULT_TIMEOUT_S = 120.0
LLM_TIMEOUT_S = 600.0
MAX_TIMEOUT_S = 3600.0
CANCEL_GRACE_S = 2.0
SHUTDOWN_WAIT_S = 3.0
MAX_INPUT_BYTES = 256 * 1024 * 1024
# A file's stat key is trusted only once its times are this old (above FAT's 2 s granularity).
INPUT_SETTLE_NS = 3 * 1000 * 1000 * 1000
MAX_CODES = 64
ENGINE_TTL = 300.0
EXTENSIONS = ('pentad_secrets', 'pentad_worker_llm', 'pentad_worker_system')
OP_NAME = re.compile(r'^[a-z][a-z0-9-]*(\.[a-z][a-z0-9-]*)+$')
REASONS = frozenset((
    'unavailable', 'device-removed', 'denied', 'timeout', 'unsupported', 'conflict', 'io',
    'safe-mode', 'preview', 'superseded', 'invalid-response', 'service-missing', 'service-stopped',
    'cancelled', 'busy', 'invalid-input'))
STOP_MESSAGES = {'cancelled': 'Cancelled', 'timeout': 'Stopped after the time limit',
                 'service-stopped': 'The worker is shutting down'}
# The host writes `type` first and `id` second; recover the id only from that prefix so an
# "id" inside a damaged payload is never mistaken for the request's.
_ID_PREFIX = re.compile(rb'^\s*\{\s*(?:"type"\s*:\s*"[a-z]{1,16}"\s*,\s*)?"id"\s*:\s*(\d{1,15})\s*[,}]')


def log(message):
    try:
        sys.stderr.write(f'pentad-worker: {message}\n')
        sys.stderr.flush()
    except (OSError, ValueError):
        pass


class OpError(Exception):
    def __init__(self, reason, message=''):
        super().__init__(message)
        self.reason = reason
        self.message = message


def ok(value, cached=False):
    return {'ok': True, 'value': value, 'cached': cached}


def failure(reason, message=''):
    return {'ok': False, 'reason': reason, 'message': message}


def normalize(result):
    if not isinstance(result, dict) or not isinstance(result.get('ok'), bool):
        return failure('io', 'The operation returned an invalid result')
    if result['ok']:
        value = result.get('value', {})
        if not isinstance(value, dict):
            return failure('io', 'The operation returned an invalid result')
        return ok(value, result.get('cached') is True)
    reason = result.get('reason')
    message = result.get('message') if isinstance(result.get('message'), str) else ''
    if reason in REASONS:
        normalized = failure(reason, message[:500])
        # A finer cause next to the Result reason (e.g. a secret that is `missing` or `locked`).
        if isinstance(result.get('detail'), str) and result['detail']:
            normalized['detail'] = result['detail'][:64]
        return normalized
    normalized = failure('io', message[:500])
    if isinstance(reason, str) and reason:
        normalized['detail'] = reason[:64]
    return normalized


def encode(message):
    """One protocol line; raises TypeError/ValueError for data that is not JSON."""
    text = json.dumps(message, ensure_ascii=False, allow_nan=False, separators=(',', ':'))
    return text.encode('utf-8', 'replace') + b'\n'


class OpContext:
    def __init__(self, request, cache):
        self._request = request
        self.request_id = request.id
        self.op = request.op
        self.timeout_s = request.timeout_s
        self.deadline = request.deadline
        self.cache = cache
        self.cache_root = str(cache.root)

    def cancelled(self):
        return self._request.scope.cancelled

    def check(self):
        self._request.scope.check()

    def on_cancel(self, callback):
        self._request.scope.on_cancel(callback)

    def remaining(self):
        return max(0.0, self.deadline - time.monotonic())

    def progress(self, data):
        return self._request.emit('progress', 'data', data)

    def partial(self, chunk):
        return self._request.emit('partial', 'chunk', chunk)


class Request:
    def __init__(self, server, ident, op, handler, payload, timeout_s):
        self.server = server
        self.id = ident
        self.op = op
        self.handler = handler
        self.payload = payload
        self.timeout_s = timeout_s
        self.deadline = time.monotonic() + timeout_s
        self.scope = core.CancelScope()
        self.lock = threading.Lock()
        self.state = 'queued'  # queued -> running -> done, or queued -> done
        self.force_at = None
        self.force_reason = ''

    def begin(self):
        with self.lock:
            if self.state != 'queued':
                return False
            self.state = 'running'
            return True

    def emit(self, kind, key, data):
        if not isinstance(data, dict):
            return False
        try:
            line = encode({'type': kind, 'id': self.id, key: data})
        except (TypeError, ValueError):
            return False
        if len(line) > MAX_RESULT_LINE:
            return False
        with self.lock:
            if self.state == 'done':
                return False
            return self.server.write(line)

    def finish(self, result):
        """Send the one result of this request; False when it was already answered."""
        with self.lock:
            if self.state == 'done':
                return False
            self.state = 'done'
            self.server.write_result(self.id, result)
        self.server.forget(self, result)
        return True

    def stop(self, reason):
        """Cancel for `reason` (cancelled, timeout or service-stopped). A queued request is
        answered at once; a running one has its children killed and is answered by its thread,
        or by the watchdog after CANCEL_GRACE_S."""
        with self.lock:
            if self.state == 'done':
                return
            queued = self.state == 'queued'
            if not queued and self.force_at is None:
                self.force_at = time.monotonic() + CANCEL_GRACE_S
                self.force_reason = reason
        self.scope.cancel(reason)
        if queued:
            self.finish(self.server.stop_failure(self, self.scope.reason or reason))
        else:
            self.server.wake()

    def force(self):
        self.finish(self.server.stop_failure(self, self.scope.reason or self.force_reason or 'cancelled'))


class _ShutdownRequested(BaseException):
    pass


class Server:
    def __init__(self, ops, cache, output):
        self.ops = ops
        self.cache = cache
        self.output = output
        self.write_lock = threading.Lock()
        self.lock = threading.Lock()
        self.changed = threading.Condition(self.lock)
        self.pending = {}
        self.live = set()
        self.jobs = queue.SimpleQueue()
        self.reading = False
        self.stopping = False
        self.finished = False
        self.output_lost = False
        self.started = time.monotonic()
        self.extensions = []
        self.counts = {'completed': 0, 'failed': 0, 'cancelled': 0, 'timedOut': 0, 'busy': 0, 'cached': 0}
        self.threads = []

    # --- output ---------------------------------------------------------------

    def write(self, line):
        with self.write_lock:
            if self.output_lost:
                return False
            try:
                self.output.write(line)
                self.output.flush()
                return True
            except (OSError, ValueError):
                self.output_lost = True
        log('the host stopped reading; shutting down')
        self.request_shutdown()
        return False

    def write_result(self, ident, result):
        try:
            line = encode({'type': 'result', 'id': ident, 'result': result})
            if len(line) > MAX_RESULT_LINE:
                line = encode({'type': 'result', 'id': ident, 'result': failure('io', 'The result is too large')})
        except (TypeError, ValueError):
            line = encode({'type': 'result', 'id': ident, 'result': failure('io', 'The operation returned data that is not JSON')})
        return self.write(line)

    def stop_failure(self, request, reason):
        message = STOP_MESSAGES.get(reason, 'Cancelled')
        if reason == 'timeout':
            message = f'Stopped after the time limit of {request.timeout_s:g} s'
        return failure(reason, message)

    # --- bookkeeping ------------------------------------------------------------

    def forget(self, request, result):
        with self.lock:
            if self.pending.get(request.id) is request:
                del self.pending[request.id]
            if result.get('ok'):
                self.counts['completed'] += 1
                if result.get('cached'):
                    self.counts['cached'] += 1
            elif result.get('reason') == 'cancelled':
                self.counts['cancelled'] += 1
            elif result.get('reason') == 'timeout':
                self.counts['timedOut'] += 1
            else:
                self.counts['failed'] += 1
            self.changed.notify_all()

    def wake(self):
        with self.lock:
            self.changed.notify_all()

    def stats(self):
        with self.lock:
            running = sum(1 for request in self.pending.values() if request.state == 'running')
            value = {'protocol': PROTOCOL, 'worker': WORKER_VERSION, 'pid': os.getpid(),
                     'uptimeS': round(time.monotonic() - self.started, 3), 'ops': sorted(self.ops),
                     'extensions': list(self.extensions), 'running': running,
                     'queued': len(self.pending) - running, 'background': len(self.live), **self.counts}
        value['cache'] = self.cache.stats()
        return value

    # --- jobs -----------------------------------------------------------------

    def start(self):
        for index in range(MAX_RUNNING):
            thread = threading.Thread(target=self._job_loop, name=f'pentad-job-{index + 1}', daemon=True)
            thread.start()
            self.threads.append(thread)
        watchdog = threading.Thread(target=self._watch, name='pentad-watchdog', daemon=True)
        watchdog.start()
        self.threads.append(watchdog)

    def _job_loop(self):
        while True:
            request = self.jobs.get()
            if request is None:
                return
            if self.stopping:
                request.stop('service-stopped')
                continue
            if not request.begin():
                continue
            with self.lock:
                self.live.add(request)
            try:
                request.finish(self._call(request))
            finally:
                with self.lock:
                    self.live.discard(request)
                    self.changed.notify_all()

    def _call(self, request):
        context = OpContext(request, self.cache)
        try:
            with core.bind_scope(request.scope):
                request.scope.check()
                return normalize(request.handler(request.payload, context))
        except Cancelled:
            return self.stop_failure(request, request.scope.reason or 'cancelled')
        except OpError as error:
            return normalize(failure(error.reason, error.message))
        except ToolError as error:
            return normalize(failure(getattr(error, 'reason', 'io'), str(error)[:300]))
        except (OSError, UnicodeError, ValueError, TypeError) as error:
            return failure('io', str(error)[:300] or type(error).__name__)
        except Exception as error:  # a broken op must not take the worker down
            log(f'{request.op} failed: {type(error).__name__}\n{traceback.format_exc(limit=8)}')
            return failure('io', type(error).__name__)

    def _watch(self):
        with self.lock:
            while not self.finished:
                now = time.monotonic()
                due = []
                next_at = now + 3600
                for request in list(self.pending.values()):
                    if request.force_at is not None:
                        if now >= request.force_at:
                            due.append((request, request.force))
                        else:
                            next_at = min(next_at, request.force_at)
                    elif now >= request.deadline:
                        due.append((request, lambda request=request: request.stop('timeout')))
                    else:
                        next_at = min(next_at, request.deadline)
                if due:
                    self.lock.release()
                    try:
                        for _, action in due:
                            action()
                    finally:
                        self.lock.acquire()
                    continue
                self.changed.wait(timeout=max(0.005, next_at - now))

    # --- input ----------------------------------------------------------------

    def serve(self, stdin):
        self.start()
        try:
            while not self.stopping:
                self.reading = True
                try:
                    if self.stopping:
                        break
                    line = stdin.readline(MAX_REQUEST_LINE + 1)
                finally:
                    self.reading = False
                if not line:
                    break
                if len(line) > MAX_REQUEST_LINE and not line.endswith(b'\n'):
                    head = line[:512]
                    self.reading = True
                    try:
                        while line and not line.endswith(b'\n'):
                            line = stdin.readline(MAX_REQUEST_LINE + 1)
                    finally:
                        self.reading = False
                    self.reject(head, 'The request line is larger than 1 MiB')
                    continue
                self.handle(line)
        except _ShutdownRequested:
            pass
        self.shutdown()

    def request_shutdown(self):
        """Signal-safe: stop the read loop. Interrupts a blocking read only from the handler."""
        self.stopping = True
        if threading.current_thread() is not threading.main_thread():
            try:
                signal.pthread_kill(threading.main_thread().ident, signal.SIGTERM)
            except (OSError, ValueError, AttributeError):
                pass

    def on_signal(self, signum, frame):
        self.stopping = True
        if self.reading:
            raise _ShutdownRequested()

    def reject(self, head, message):
        match = _ID_PREFIX.match(head)
        self.answer_invalid(int(match.group(1)) if match else 0, message)

    def answer_invalid(self, ident, message):
        if ident > 0:
            with self.lock:
                in_use = ident in self.pending
                if not in_use:
                    self.counts['failed'] += 1
            if not in_use:
                self.write_result(ident, failure('invalid-response', message))
                return
        log(f'ignored a line without a usable id: {message}')

    def handle(self, line):
        if not line.strip():
            return
        try:
            message = json.loads(line)
        except (ValueError, RecursionError):
            self.reject(line[:512], 'The request line is not valid JSON')
            return
        if not isinstance(message, dict):
            self.reject(line[:512], 'The request line is not a JSON object')
            return
        kind = message.get('type')
        ident = message.get('id')
        valid_id = type(ident) is int and ident > 0
        if kind == 'request':
            if not valid_id:
                log('ignored a request without a positive integer id')
                return
            op = message.get('op')
            payload = message.get('payload', {})
            timeout_ms = message.get('timeoutMs')
            if not isinstance(op, str) or not isinstance(payload, dict) or not (
                    timeout_ms is None or (type(timeout_ms) in (int, float) and timeout_ms > 0)):
                self.answer_invalid(ident, 'The request has an invalid op, payload or timeoutMs')
                return
            self.accept(ident, op, payload, timeout_ms)
        elif kind == 'cancel':
            if valid_id:
                with self.lock:
                    request = self.pending.get(ident)
                if request is not None:
                    request.stop('cancelled')
        elif kind == 'shutdown':
            self.stopping = True
        else:
            log('ignored a message of unknown type')

    def accept(self, ident, op, payload, timeout_ms):
        handler = self.ops.get(op)
        if handler is None:
            with self.lock:
                duplicate = ident in self.pending
                if not duplicate:
                    self.counts['failed'] += 1
            if not duplicate:
                self.write_result(ident, failure('unsupported', f'Unknown operation {op[:64]}'))
            return
        if timeout_ms is None:
            timeout_s = LLM_TIMEOUT_S if op.startswith('llm.') else DEFAULT_TIMEOUT_S
        else:
            timeout_s = min(MAX_TIMEOUT_S, timeout_ms / 1000)
        request = None
        with self.lock:
            if ident in self.pending:
                log(f'ignored request {ident}: the id is still in use')
                return
            if len(self.pending) >= MAX_RUNNING + MAX_QUEUED:
                self.counts['busy'] += 1
            else:
                request = Request(self, ident, op, handler, payload, timeout_s)
                self.pending[ident] = request
                self.changed.notify_all()
        if request is None:
            self.write_result(ident, failure('busy', 'The worker queue is full'))
            return
        self.jobs.put(request)

    # --- lifetime -------------------------------------------------------------

    def shutdown(self):
        self.stopping = True
        with self.lock:
            requests = list(self.pending.values()) + [request for request in self.live if request.id not in self.pending]
        for request in requests:
            request.stop('service-stopped')
        deadline = time.monotonic() + SHUTDOWN_WAIT_S
        with self.lock:
            while self.live and time.monotonic() < deadline:
                self.changed.wait(timeout=max(0.005, deadline - time.monotonic()))
            leftover = list(self.pending.values())
            stuck = list(self.live)
        for request in leftover:
            request.finish(self.stop_failure(request, 'service-stopped'))
        for request in stuck:
            request.scope.kill_children()
        if stuck:
            log(f'{len(stuck)} job(s) did not stop in time')
        for _ in range(MAX_RUNNING):
            self.jobs.put(None)
        with self.lock:
            self.finished = True
            self.changed.notify_all()
        with self.write_lock:
            try:
                self.output.flush()
            except (OSError, ValueError):
                pass


# --- Built-in ops -------------------------------------------------------------

class _Input:
    """The input file of a cached op, opened once (following a symlink, like every file tool)
    and checked with fstat on the open descriptor: a regular file of at most MAX_INPUT_BYTES.

    `stat_key()` names the opened file by (realpath, st_dev, st_ino, st_size, st_mtime_ns,
    st_ctime_ns) so a cache hit can skip copying and hashing it. Every write, truncate,
    rename-over or chmod moves the change time, which a user cannot set, so the key changes
    with the bytes. Timestamps are coarse (one tick; 2 s on FAT), so the key is offered only for
    a file whose change and modification times are INPUT_SETTLE_NS old when it is opened: a
    later change then always lands on a different timestamp. Any doubt gives None (full path)."""

    def __init__(self, payload):
        uri = payload.get('uri')
        if not isinstance(uri, str) or not uri or len(uri) > 4096:
            raise OpError('unsupported', 'Expected a file URI')
        try:
            self.path = file_path(uri)
        except ToolError as error:
            raise OpError('unsupported', str(error)) from None
        name = self.path.name
        try:
            self.fd = os.open(self.path, os.O_RDONLY | os.O_NONBLOCK | os.O_CLOEXEC)
        except FileNotFoundError:
            raise OpError('io', f'{name} no longer exists') from None
        except OSError as error:
            raise OpError('io', f'{name}: {error.strerror or error}') from None
        try:
            self.info = os.fstat(self.fd)
            if not stat.S_ISREG(self.info.st_mode):
                raise OpError('unsupported', f'{name} is not a regular file')
            if self.info.st_size > MAX_INPUT_BYTES:
                raise OpError('unsupported', f'{name} is larger than {MAX_INPUT_BYTES // (1024 * 1024)} MiB')
        except BaseException:
            self.close()
            raise

    @staticmethod
    def _identity(info):
        return (info.st_dev, info.st_ino, info.st_mode, info.st_size, info.st_mtime_ns, info.st_ctime_ns)

    def stat_key(self):
        info = self.info
        if time.time_ns() - max(info.st_mtime_ns, info.st_ctime_ns) < INPUT_SETTLE_NS:
            return None
        try:
            real = os.path.realpath(self.path, strict=True)
        except (OSError, ValueError, RuntimeError):
            return None
        return input_stat_key(real, info)

    def unchanged(self):
        """True while the open file still has the identity and times it had when opened."""
        try:
            return self._identity(os.fstat(self.fd)) == self._identity(self.info)
        except OSError:
            return False

    def close(self):
        if self.fd is not None:
            os.close(self.fd)
            self.fd = None


class _Scratch(Job):
    """A Job with a private temporary work directory holding a copy of the input, so a cached
    result always matches the bytes it was computed from. Capability ops publish nothing."""

    def __init__(self, source):
        self.output_dir = None
        self.outputs = []
        self._links = 0
        self.work = Path(tempfile.mkdtemp(prefix='.pentad-tool-'))
        try:
            self.digest, self.size, self.inputs = self._copy(source)
        except BaseException:
            self.cleanup()
            raise

    def _copy(self, source):
        name = source.path.name
        suffix = re.sub(r'[^a-z0-9.]', '', split_name(name)[1].lower())[:12]
        target = self.work / f'source{suffix}'
        digest = hashlib.sha256()
        total = 0
        with os.fdopen(os.open(target, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600), 'wb') as handle:
            while True:
                # No process kill interrupts this loop; give the job thread back on cancel.
                check_cancelled()
                chunk = os.read(source.fd, 1024 * 1024)
                if not chunk:
                    break
                total += len(chunk)
                if total > MAX_INPUT_BYTES:
                    raise OpError('unsupported', f'{name} is larger than {MAX_INPUT_BYTES // (1024 * 1024)} MiB')
                digest.update(chunk)
                handle.write(chunk)
        return digest.hexdigest(), total, [target]

    def publish(self, produced, stem, suffix=''):
        raise ToolError('This operation does not write files')


_engines = {}
_engines_lock = threading.Lock()


def engine_version(argv):
    """First line of `<tool> --version`, kept for ENGINE_TTL; a missing tool raises `unavailable`."""
    key = tuple(argv)
    now = time.monotonic()
    with _engines_lock:
        cached = _engines.get(key)
        if cached and now - cached[0] < ENGINE_TTL:
            return cached[1]
    _, out, err = run(list(argv), None, 15)
    text = (out or b'').decode('utf-8', 'replace').strip() or (err or b'').decode('utf-8', 'replace').strip()
    version = (text.splitlines() or [argv[0]])[0][:120]
    with _engines_lock:
        _engines[key] = (time.monotonic(), version)
    return version


def _cached(ctx, op, options, payload, engine, compute):
    source = _Input(payload)
    try:
        # Fast path: a settled, unchanged file whose content hash and result are both cached
        # is answered without copying or hashing it.
        input_key = source.stat_key() if ctx.cache.enabled else None
        known = ctx.cache.input_hash(input_key) if input_key else None
        if known:
            hit = ctx.cache.get(cache_key(op, options, known, engine))
            if hit is not None:
                return ok(hit, True)
        job = _Scratch(source)
        try:
            key = cache_key(op, options, job.digest, engine)
            if input_key and job.digest != known:
                if known is None and job.size == source.info.st_size and source.unchanged():
                    ctx.cache.remember_input(input_key, job.digest)
                elif known is not None:
                    # Same stat key, different bytes: the key cannot be trusted for this file.
                    ctx.cache.forget(input_key)
            hit = ctx.cache.get(key) if job.digest != known else None
            if hit is not None:
                return ok(hit, True)
            ctx.check()
            value = compute(job)
        finally:
            job.cleanup()
    finally:
        source.close()
    ctx.cache.put(key, value)
    return ok(value)


def op_image_ocr(payload, ctx):
    engine = engine_version(['tesseract', '--version'])
    language = image.ocr_language(payload.get('language'), image.ocr_languages(), payload.get('filterInstalled') is True)
    psm = image.ocr_psm(payload.get('psm'))
    options = {'language': language, 'psm': psm}

    def compute(job):
        # Same as the bar's script: the resolved languages, the chosen --psm, no blank lines.
        result = image.image_ocr(job, {'language': language, 'filterInstalled': True, 'psm': psm, 'dropBlankLines': True})
        return {'text': result['text']}
    return _cached(ctx, 'image.ocr', options, payload, engine, compute)


_SYMBOL = re.compile(r'<symbol\b[^>]*?\btype=[\'"]([^\'"]{0,64})[\'"][^>]*>(.*?)</symbol>', re.S)
_DATA = re.compile(r'<data\b([^>]*)><!\[CDATA\[(.*?)\]\]></data>', re.S)


def parse_zbar_xml(text):
    codes = []
    for match in _SYMBOL.finditer(text):
        data = _DATA.search(match.group(2))
        if not data:
            continue
        content = data.group(2)
        if re.search(r'\bformat=[\'"]base64[\'"]', data.group(1)):
            try:
                content = base64.b64decode(''.join(content.split()), validate=True).decode('utf-8', 'replace')
            except ValueError:
                continue
        codes.append({'type': match.group(1), 'text': content[:MAX_TEXT]})
        if len(codes) >= MAX_CODES:
            break
    return codes


def op_image_barcode(payload, ctx):
    engine = engine_version(['zbarimg', '--version'])

    def compute(job):
        code, out, _ = run(['zbarimg', '--quiet', '--xml', job.link(job.inputs[0])], job.work, 60, ok_codes=(0, 4))
        return {'codes': parse_zbar_xml(out.decode('utf-8', 'replace')) if code == 0 else []}
    return _cached(ctx, 'image.barcode', {}, payload, engine, compute)


def op_pdf_text(payload, ctx):
    engine = engine_version(['pdftotext', '-v'])

    def compute(job):
        name = pdf._plain_pdf(job, job.inputs[0])
        run(['pdftotext', '-layout', '-enc', 'UTF-8', name, 'out.txt'], job.work, 300)
        text = job.scratch('out.txt').read_text('utf-8', 'replace')
        return {'text': text[:MAX_TEXT], 'truncated': len(text) > MAX_TEXT}
    return _cached(ctx, 'pdf.text', {}, payload, engine, compute)


def op_ocr_languages(payload, ctx):
    return ok({'languages': image.ocr_languages(0 if payload.get('refresh') is True else image.LANGUAGES_TTL)})


def op_file_run(payload, ctx):
    return ok(file_tool.execute(payload))


def builtin_ops(server):
    return {
        'file.run': op_file_run,
        'image.ocr': op_image_ocr,
        'image.barcode': op_image_barcode,
        'pdf.text': op_pdf_text,
        'ocr.languages': op_ocr_languages,
        'worker.stats': lambda payload, ctx: ok(server.stats()),
        'worker.clear-cache': lambda payload, ctx: ok({'removed': server.cache.clear(), 'cache': server.cache.stats()}),
    }


def load_extensions(ops, names=EXTENSIONS):
    """Import each optional module and let it add ops through `register_ops(ops)`."""
    loaded = []
    for name in names:
        try:
            module = importlib.import_module(name)
        except ModuleNotFoundError as error:
            if error.name != name:
                log(f'{name} is not usable: {error}')
            continue
        except Exception as error:
            log(f'{name} failed to load: {type(error).__name__}: {error}')
            continue
        register = getattr(module, 'register_ops', None)
        if not callable(register):
            continue
        try:
            register(ops)
            loaded.append(name)
        except Exception as error:
            log(f'{name}.register_ops failed: {type(error).__name__}: {error}')
    for op in [op for op, handler in ops.items() if not (isinstance(op, str) and OP_NAME.match(op) and callable(handler))]:
        log(f'dropped invalid op {op!r}')
        del ops[op]
    return loaded


def _die_with_parent():
    """PR_SET_PDEATHSIG(SIGTERM): end with the shell even if it is killed outright."""
    if not sys.platform.startswith('linux'):
        return
    parent = os.getppid()
    try:
        import ctypes
        ctypes.CDLL(None, use_errno=True).prctl(1, signal.SIGTERM)
    except (OSError, AttributeError):
        return
    if os.getppid() != parent:  # the parent died before the call
        os.kill(os.getpid(), signal.SIGTERM)


def main(argv=None):
    parser = argparse.ArgumentParser(description='Pentad resident worker (protocol v1 on stdin/stdout).')
    parser.add_argument('--serve', action='store_true', required=True)
    parser.add_argument('--cache-root', default='')
    parser.add_argument('--cache-mib', type=int, default=64)
    args = parser.parse_args(argv)
    if not 0 <= args.cache_mib <= 4096:
        parser.error('--cache-mib must be 0–4096')
    output = sys.stdout.buffer
    # Stray prints from extension modules must never corrupt the protocol stream.
    sys.stdout = sys.stderr
    server = Server({}, None, output)
    signal.signal(signal.SIGTERM, server.on_signal)
    signal.signal(signal.SIGINT, server.on_signal)
    _die_with_parent()
    core.set_threaded(True)
    mimetypes.init()  # its lazy first-use initialisation is not thread-safe
    root = Path(args.cache_root) if args.cache_root else default_root()
    server.cache = WorkerCache(root, max_bytes=args.cache_mib * 1024 * 1024)
    ops = builtin_ops(server)
    server.extensions = load_extensions(ops)
    server.ops = ops
    if not server.stopping:
        server.write(encode({'type': 'hello', 'protocol': PROTOCOL, 'worker': WORKER_VERSION, 'ops': sorted(ops)}))
    if not server.stopping:
        server.serve(sys.stdin.buffer)
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
