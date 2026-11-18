"""Result cache of the resident worker for deterministic local operations.

Only results that depend on nothing but the input bytes, the options and the engine version
belong here (OCR, barcodes, PDF text). Never store model output, translations or anything
derived from a secret.

Layout: one JSON file per entry, `<root>/<key>.json`, mode 0600, inside a 0700 directory
(normally `$XDG_CACHE_HOME/pentad/worker`). The key is sha256 over the operation, canonical
options, the input's content hash and the engine version, so a changed file, option or engine
is a miss and nothing needs invalidating. The cache stays below `max_bytes` and `max_entries`
by removing the entries with the oldest mtime; a hit refreshes the entry's mtime. Every failure
(unwritable directory, damaged entry) degrades to a miss and never fails the request.
"""
import hashlib
import json
import os
import stat
import tempfile
import threading
import time
from pathlib import Path

FORMAT = 1
DEFAULT_MAX_BYTES = 64 * 1024 * 1024
DEFAULT_MAX_ENTRIES = 1000
_NAME_LENGTH = 64 + len('.json')


def default_root():
    base = os.environ.get('XDG_CACHE_HOME') or ''
    if not os.path.isabs(base):
        base = str(Path.home() / '.cache')
    return Path(base) / 'pentad' / 'worker'


def content_hash(data):
    return hashlib.sha256(data).hexdigest()


def cache_key(op, options, input_hash, engine):
    """sha256 over (op, canonical options, input content hash, engine version)."""
    canonical = json.dumps([FORMAT, op, options, input_hash, engine], sort_keys=True,
                           ensure_ascii=True, separators=(',', ':'))
    return hashlib.sha256(canonical.encode('ascii')).hexdigest()


class WorkerCache:
    def __init__(self, root, max_bytes=DEFAULT_MAX_BYTES, max_entries=DEFAULT_MAX_ENTRIES):
        self.root = Path(root)
        self.max_bytes = max(0, int(max_bytes))
        self.max_entries = max(0, int(max_entries))
        self.hits = 0
        self.misses = 0
        self.stores = 0
        self.evictions = 0
        self._lock = threading.Lock()
        self._index = {}  # name -> (mtime, size)
        self.enabled = self.max_bytes > 0 and self.max_entries > 0 and self._prepare()
        if self.enabled:
            self._scan()
            with self._lock:
                self._evict_locked()

    def _prepare(self):
        try:
            self.root.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
            try:
                self.root.mkdir(mode=0o700)
            except FileExistsError:
                pass
            info = os.lstat(self.root)
            # Refuse a symlink or someone else's directory rather than writing results into it.
            if not stat.S_ISDIR(info.st_mode) or info.st_uid != os.getuid():
                return False
            if stat.S_IMODE(info.st_mode) != 0o700:
                os.chmod(self.root, 0o700)
            return True
        except OSError:
            return False

    @staticmethod
    def _valid_name(name):
        return len(name) == _NAME_LENGTH and name.endswith('.json') and all(c in '0123456789abcdef' for c in name[:64])

    def _scan(self):
        index = {}
        try:
            with os.scandir(self.root) as entries:
                for entry in entries:
                    if entry.name.startswith('.tmp-'):
                        # Left behind by a worker that died mid-write.
                        try:
                            if time.time() - entry.stat(follow_symlinks=False).st_mtime > 3600:
                                os.unlink(entry.path)
                        except OSError:
                            pass
                        continue
                    if not self._valid_name(entry.name):
                        continue
                    try:
                        info = entry.stat(follow_symlinks=False)
                    except OSError:
                        continue
                    if stat.S_ISREG(info.st_mode):
                        index[entry.name] = (info.st_mtime, info.st_size)
        except OSError:
            pass
        with self._lock:
            self._index = index

    def _path(self, key):
        return self.root / f'{key}.json'

    def get(self, key):
        """Return the cached value dict for `key`, or None."""
        if not self.enabled:
            return None
        path = self._path(key)
        try:
            descriptor = os.open(path, os.O_RDONLY | os.O_NOFOLLOW)
            with os.fdopen(descriptor, 'rb') as handle:
                data = handle.read(self.max_bytes + 1)
            entry = json.loads(data.decode('utf-8'))
            if not isinstance(entry, dict) or entry.get('format') != FORMAT or entry.get('key') != key \
                    or not isinstance(entry.get('value'), dict):
                raise ValueError('damaged cache entry')
        except FileNotFoundError:
            with self._lock:
                self.misses += 1
                self._index.pop(path.name, None)
            return None
        except (OSError, ValueError):
            self._remove(path.name)
            with self._lock:
                self.misses += 1
            return None
        now = time.time()
        try:
            os.utime(path, (now, now))
        except OSError:
            pass
        with self._lock:
            self.hits += 1
            if path.name in self._index:
                self._index[path.name] = (now, self._index[path.name][1])
        return entry['value']

    def put(self, key, value):
        """Store `value` (a JSON-serialisable dict). Returns True when it was written."""
        if not self.enabled:
            return False
        try:
            data = json.dumps({'format': FORMAT, 'key': key, 'value': value}, ensure_ascii=False,
                              separators=(',', ':')).encode('utf-8', 'replace')
        except (TypeError, ValueError):
            return False
        # One entry may not take more than a quarter of the cache.
        if len(data) > self.max_bytes // 4:
            return False
        path = self._path(key)
        temporary = None
        try:
            descriptor, temporary = tempfile.mkstemp(prefix='.tmp-', dir=self.root)
            with os.fdopen(descriptor, 'wb') as handle:
                os.fchmod(handle.fileno(), 0o600)
                handle.write(data)
            os.replace(temporary, path)
            temporary = None
            info = os.lstat(path)
        except OSError:
            if temporary:
                try:
                    os.unlink(temporary)
                except OSError:
                    pass
            return False
        with self._lock:
            self.stores += 1
            self._index[path.name] = (info.st_mtime, info.st_size)
            self._evict_locked()
        return True

    def _evict_locked(self):
        total = sum(size for _, size in self._index.values())
        if total <= self.max_bytes and len(self._index) <= self.max_entries:
            return
        for name, (_, size) in sorted(self._index.items(), key=lambda item: item[1][0]):
            if total <= self.max_bytes and len(self._index) <= self.max_entries:
                break
            try:
                os.unlink(self.root / name)
            except FileNotFoundError:
                pass
            except OSError:
                continue
            del self._index[name]
            total -= size
            self.evictions += 1

    def _remove(self, name):
        try:
            os.unlink(self.root / name)
        except OSError:
            pass
        with self._lock:
            self._index.pop(name, None)

    def stats(self):
        with self._lock:
            return {'enabled': self.enabled, 'entries': len(self._index),
                    'bytes': sum(size for _, size in self._index.values()),
                    'maxBytes': self.max_bytes, 'maxEntries': self.max_entries,
                    'hits': self.hits, 'misses': self.misses, 'stores': self.stores, 'evictions': self.evictions}
