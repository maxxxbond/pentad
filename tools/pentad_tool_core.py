"""Shared plumbing for the sidebar file tools: errors, CLI runner, jobs and option parsers.

The one-shot helper (`pentad_file_tool.py`) runs one job in the main thread and is cancelled
by SIGTERM. The resident worker (`pentad_worker.py`) runs jobs in threads instead: it calls
`set_threaded()` once, and binds a `CancelScope` to each job thread with `bind_scope()`, so
`run()` records every child it starts and `CancelScope.cancel()` can kill their process
groups from another thread.
"""
import contextlib
import mimetypes
import os
import re
import shutil
import signal
import stat
import subprocess
import tempfile
import threading
from pathlib import Path
from urllib.parse import quote, urlsplit
from urllib.request import url2pathname


MAX_INPUTS = 100
MAX_REQUEST = 1024 * 1024
MAX_TEXT = 256 * 1024
TAR_SUFFIXES = ('.tar', '.tar.gz', '.tgz', '.tar.xz', '.txz', '.tar.zst', '.tzst', '.tar.bz2', '.tbz2', '.tbz')
STACKED_SUFFIXES = TAR_SUFFIXES + ('.tar.lz', '.tar.lzma')


class ToolError(Exception):
    """`reason` is the widget API Result reason the worker reports; the one-shot CLI ignores it."""
    def __init__(self, message, detail='', reason='io'):
        super().__init__(message)
        self.detail = detail
        self.reason = reason


class Cancelled(BaseException):
    pass


# --- Cancellation in threaded (worker) mode ----------------------------------

_threaded = False
_local = threading.local()


def set_threaded(enabled=True):
    """Switch run() to thread-safe process creation (no preexec_fn). The worker calls this once."""
    global _threaded
    _threaded = bool(enabled)


class CancelScope:
    """Cancellation state of one job. Children started by run() while the scope is bound to the
    job's thread are tracked, and cancel() kills their process groups from any thread."""

    def __init__(self):
        self._lock = threading.Lock()
        self._processes = set()
        self._callbacks = []
        self.cancelled = False
        self.reason = ''

    def cancel(self, reason='cancelled'):
        with self._lock:
            if self.cancelled:
                return False
            self.cancelled = True
            self.reason = reason
            processes = list(self._processes)
            callbacks = list(self._callbacks)
            self._callbacks = []
        for process in processes:
            _kill_group(process)
        for callback in callbacks:
            try:
                callback()
            except Exception:  # a broken callback must not stop the other ones
                pass
        return True

    def on_cancel(self, callback):
        """Call `callback()` when the scope is cancelled (at once if it already is)."""
        with self._lock:
            if not self.cancelled:
                self._callbacks.append(callback)
                return
        try:
            callback()
        except Exception:
            pass

    def check(self):
        if self.cancelled:
            raise Cancelled()

    def attach(self, process):
        """Track a started child; kill it at once and return False if the scope is already cancelled."""
        with self._lock:
            if not self.cancelled:
                self._processes.add(process)
                return True
        _kill_group(process)
        return False

    def detach(self, process):
        with self._lock:
            self._processes.discard(process)

    def kill_children(self):
        with self._lock:
            processes = list(self._processes)
        for process in processes:
            _kill_group(process)


def current_scope():
    return getattr(_local, 'scope', None)


@contextlib.contextmanager
def bind_scope(scope):
    """Bind `scope` to the calling thread for the duration of the block."""
    previous = getattr(_local, 'scope', None)
    _local.scope = scope
    try:
        yield scope
    finally:
        _local.scope = previous


def _cancel(signum, frame):
    raise Cancelled()


def _kill_group(process):
    # The child leads its own session (start_new_session), so its pid is the group id. Linux
    # does not reuse a pid while a group with that id still has members.
    try:
        os.killpg(process.pid, signal.SIGKILL)
    except (ProcessLookupError, PermissionError):
        pass


def _kill(process):
    _kill_group(process)
    try:
        process.wait(timeout=5)
    except subprocess.TimeoutExpired:
        pass


def _first_line(data):
    text = data.decode('utf-8', 'replace') if isinstance(data, bytes) else str(data or '')
    lines = [line.strip() for line in text.splitlines() if line.strip()]
    errors = [line for line in lines if re.search(r'error|invalid|fail|cannot|can\'t|unable|not ', line, re.I)]
    return ((errors or lines or [''])[-1])[:200]


def _die_with_parent():
    # The CLI gets its own process group for clean cancellation; this keeps it from outliving
    # the helper if the shell kills the helper outright.
    try:
        import ctypes
        ctypes.CDLL(None, use_errno=True).prctl(1, signal.SIGKILL)  # PR_SET_PDEATHSIG
    except (OSError, AttributeError):
        pass


def run(argv, cwd, timeout, stdin=None, ok_codes=(0,)):
    """Run a CLI in its own process group; return (code, stdout, stderr).

    With a CancelScope bound to the thread the child is tracked by the scope, and a cancelled
    scope raises Cancelled instead of returning. preexec_fn is not safe with threads, so in
    threaded mode the child does not get PR_SET_PDEATHSIG; the worker kills tracked groups on
    cancel and shutdown instead."""
    name = argv[0]
    scope = current_scope()
    if scope is not None:
        scope.check()
    extra = {} if _threaded else {'preexec_fn': _die_with_parent}
    try:
        process = subprocess.Popen(argv, cwd=cwd, start_new_session=True,
            stdin=subprocess.PIPE if stdin is not None else subprocess.DEVNULL,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, **extra)
    except FileNotFoundError:
        raise ToolError(f'{name} is not installed', reason='unavailable') from None
    if scope is not None:
        scope.attach(process)
    try:
        out, err = process.communicate(stdin, timeout=timeout)
    except subprocess.TimeoutExpired:
        _kill(process)
        raise ToolError(f'{name} took longer than {timeout} s and was stopped', reason='timeout') from None
    except BaseException:
        _kill(process)
        raise
    finally:
        if scope is not None:
            scope.detach(process)
    if scope is not None:
        scope.check()
    if process.returncode not in ok_codes:
        raise ToolError(_first_line(err) or _first_line(out) or f'{name} failed with exit code {process.returncode}',
                        (err or b'').decode('utf-8', 'replace'))
    return process.returncode, out, err


def file_path(uri):
    parsed = urlsplit(uri)
    if parsed.scheme != 'file' or parsed.netloc not in ('', 'localhost') or not parsed.path.startswith('/') or parsed.query or parsed.fragment:
        raise ToolError('Only local files are supported')
    path = url2pathname(parsed.path)
    if '\0' in path:
        raise ToolError('Invalid file URI')
    return Path(path)


def file_uri(path):
    return 'file://' + quote(str(path), safe='/')


def split_name(name):
    """Return (stem, suffix) keeping stacked archive suffixes such as .tar.gz together."""
    lower = name.lower()
    for suffix in sorted(STACKED_SUFFIXES, key=len, reverse=True):
        if lower.endswith(suffix) and len(name) > len(suffix):
            return name[:-len(suffix)], name[-len(suffix):]
    stem, dot, extension = name.rpartition('.')
    return (stem, '.' + extension) if dot and stem else (name, '')


def describe(path):
    info = path.stat()
    folder = stat.S_ISDIR(info.st_mode)
    size = sum(child.stat().st_size for child in path.rglob('*') if child.is_file() and not child.is_symlink()) if folder else info.st_size
    mime = 'inode/directory' if folder else mimetypes.guess_type(path.name)[0] or 'application/octet-stream'
    return {'kind': 'folder' if folder else 'file', 'mimeType': mime, 'uri': file_uri(path), 'name': path.name, 'sizeBytes': size}


class Job:
    def __init__(self, inputs):
        self.inputs = inputs
        self.output_dir = self._output_dir(inputs[0].parent if inputs else None)
        self.work = Path(tempfile.mkdtemp(prefix='.pentad-tool-', dir=self.output_dir))
        self.outputs = []
        self._links = 0

    @staticmethod
    def _output_dir(preferred):
        if preferred and os.access(preferred, os.W_OK | os.X_OK):
            return preferred
        downloads = Path(os.environ.get('XDG_DOWNLOAD_DIR') or Path.home() / 'Downloads') / 'Pentad'
        downloads.mkdir(parents=True, exist_ok=True)
        return downloads

    def link(self, path, name=None):
        """Expose an input inside the work directory under a neutral (or chosen) name."""
        if name is None:
            self._links += 1
            name = f'input-{self._links}{split_name(path.name)[1].lower()}'
            name = re.sub(r'[^a-z0-9.-]', '', name) or f'input-{self._links}'
        os.symlink(path, self.work / name)
        return name

    def scratch(self, name):
        return self.work / name

    def publish(self, produced, stem, suffix=''):
        """Move a produced file or folder to a fresh name beside the inputs; never overwrite."""
        produced = Path(produced)
        if not produced.exists():
            raise ToolError('The tool finished without producing a file')
        folder = produced.is_dir()
        stem = (stem.strip() or 'Output')[:180]
        for index in range(1, 1000):
            candidate = self.output_dir / (f'{stem}{suffix}' if index == 1 else f'{stem} ({index}){suffix}')
            try:
                if folder:
                    candidate.mkdir()
                else:
                    os.close(os.open(candidate, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o644))
            except FileExistsError:
                continue
            try:
                os.replace(produced, candidate)
            except OSError:
                if folder:
                    candidate.rmdir()
                else:
                    candidate.unlink(missing_ok=True)
                raise
            self.outputs.append(candidate)
            return candidate
        raise ToolError('Could not find a free output name')

    def cleanup(self):
        shutil.rmtree(self.work, ignore_errors=True)

    def discard_outputs(self):
        for path in self.outputs:
            if path.is_dir():
                shutil.rmtree(path, ignore_errors=True)
            else:
                path.unlink(missing_ok=True)
        self.outputs = []


def choice(options, key, allowed, default):
    value = options.get(key, default)
    if isinstance(value, (int, float)) and not isinstance(value, bool):
        value = str(int(value))
    if value not in allowed:
        raise ToolError(f'Unsupported {key}: {value}')
    return value


def secret(options, key='password'):
    value = options.get(key)
    if not isinstance(value, str) or not value:
        raise ToolError('Enter a password')
    if '\n' in value or '\r' in value or '\0' in value or len(value) > 512:
        raise ToolError('The password cannot contain line breaks')
    return value


def parse_pages(spec, count):
    """Parse '1-3, 5, 8-', '-2' and 'z'/'end' into a page list (1-based, order kept, no repeats)."""
    if not isinstance(spec, str) or not spec.strip():
        raise ToolError('Enter pages, for example 1-3, 5')
    if len(spec) > 1000:
        raise ToolError('The page list is too long')
    def bound(token, fallback):
        if token in (None, ''):
            return fallback
        if token in ('z', 'end', 'last'):
            return count
        return int(token)
    pages = []
    for part in spec.lower().replace(' ', '').split(','):
        if not part:
            continue
        match = re.fullmatch(r'(\d+|z|end|last)?(-(\d+|z|end|last)?)?', part)
        if not match or not (match.group(1) or match.group(2)):
            raise ToolError(f'Cannot read page range “{part}”')
        start = bound(match.group(1), 1)
        end = bound(match.group(3), count) if match.group(2) else start
        for page in (start, end):
            if not 1 <= page <= count:
                raise ToolError(f'Page {page} is outside 1–{count}')
        step = 1 if end >= start else -1
        for page in range(start, end + step, step):
            if page not in pages:
                pages.append(page)
    if not pages:
        raise ToolError('Enter pages, for example 1-3, 5')
    return pages


def page_ranges(pages):
    """Compress [1,2,3,7] into '1-3,7' for qpdf."""
    ranges, start, previous = [], None, None
    for page in pages + [None]:
        if start is not None and page is not None and previous is not None and page == previous + 1:
            previous = page
            continue
        if start is not None:
            ranges.append(str(start) if start == previous else f'{start}-{previous}')
        start = previous = page
    return ','.join(ranges)


def parse_time(value, label):
    if value in (None, ''):
        return None
    text = str(value).strip()
    match = re.fullmatch(r'(?:(\d+):)?(?:(\d+):)?(\d+(?:\.\d+)?)', text)
    if not match:
        raise ToolError(f'{label} must look like 75, 1:15 or 0:01:15.5')
    parts = [part for part in match.groups() if part is not None]
    seconds = 0.0
    for part in parts:
        seconds = seconds * 60 + float(part)
    return seconds


def human_size(size):
    for unit in ('B', 'KB', 'MB', 'GB'):
        if size < 1024 or unit == 'GB':
            return f'{size:.0f} {unit}' if unit == 'B' else f'{size:.1f} {unit}'
        size /= 1024
    return f'{size} B'


def _savings(before, after, skipped):
    parts = []
    if before:
        parts.append(f'{human_size(before)} → {human_size(after)}, saved {round(100 - after * 100 / before)}%')
    if skipped:
        parts.append(f'{skipped} already optimal, left as is')
    return {'summary': '; '.join(parts) or 'Nothing to do'}
