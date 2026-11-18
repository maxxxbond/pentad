"""Bounded, revision-checked storage for Pentad JSON documents."""
from __future__ import annotations

import fcntl
import hashlib
import os
import secrets
import stat
import tempfile
import time
from urllib.parse import unquote, urlsplit
from contextlib import contextmanager
from pathlib import Path

MAX_BYTES = 1024 * 1024
LOCK_TIMEOUT_SECONDS = 5
CONFIG_NAMES = frozenset({"theme", "layout", "interface", "session", "spotlight", "plugin-state", "screenshots", "wallpaper", "models"})
STATE_NAMES = frozenset({"notifications", "shelf", "activity", "organizer"})
DOCUMENT_NAMES = CONFIG_NAMES | STATE_NAMES
ARTWORK_MAX_BYTES = 4 * 1024 * 1024
ARTWORK_CACHE_MAX_BYTES = 16 * 1024 * 1024
ARTWORK_CACHE_MAX_COUNT = 12
ARTWORK_PENDING_MAX_BYTES = 16 * 1024 * 1024
ARTWORK_PENDING_MAX_COUNT = 4
ARTWORK_PENDING_STALE_SECONDS = 120

class StoreError(Exception):
    reason = "io"

class Conflict(StoreError):
    reason = "conflict"

class ReadOnly(StoreError):
    reason = "read-only"

class LockTimeout(StoreError):
    reason = "timeout"

class InvalidDocument(StoreError):
    reason = "invalid"

def _name(name: str) -> str:
    if name not in DOCUMENT_NAMES:
        raise InvalidDocument("unknown document")
    return name

def _root(root: os.PathLike[str] | str, *, create: bool = False) -> Path:
    path = Path(root).absolute()
    if create:
        path.mkdir(mode=0o700, parents=True, exist_ok=True)
    else:
        try:
            path.lstat()
        except FileNotFoundError:
            return path
    info = path.lstat()
    if not stat.S_ISDIR(info.st_mode):
        raise InvalidDocument("root is not a directory")
    if create:
        os.chmod(path, 0o700)
    return path

def _target(root: Path, name: str) -> Path:
    return root / f"{_name(name)}.json"

def _read(path: Path) -> tuple[str | None, str | None]:
    try:
        fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    except FileNotFoundError:
        return None, None
    except OSError as exc:
        if exc.errno in (getattr(os, "ELOOP", 40),):
            raise InvalidDocument("symlink target refused") from exc
        raise
    try:
        info = os.fstat(fd)
        if not stat.S_ISREG(info.st_mode):
            raise InvalidDocument("non-regular target refused")
        if info.st_size > MAX_BYTES:
            raise InvalidDocument("document exceeds 1 MiB")
        chunks = []
        total = 0
        while True:
            chunk = os.read(fd, min(65536, MAX_BYTES + 1 - total))
            if not chunk:
                break
            chunks.append(chunk)
            total += len(chunk)
            if total > MAX_BYTES:
                raise InvalidDocument("document exceeds 1 MiB")
        data = b"".join(chunks)
        text = data.decode("utf-8")
        return text, hashlib.sha256(data).hexdigest()
    finally:
        os.close(fd)

@contextmanager
def _locked(root: Path):
    lock_path = root / ".lock"
    flags = os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW
    fd = os.open(lock_path, flags, 0o600)
    try:
        if not stat.S_ISREG(os.fstat(fd).st_mode):
            raise InvalidDocument("lock is not a regular file")
        os.fchmod(fd, 0o600)
        deadline = time.monotonic() + LOCK_TIMEOUT_SECONDS
        while True:
            try:
                fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
                break
            except BlockingIOError:
                if time.monotonic() >= deadline:
                    raise LockTimeout("timed out waiting for document lock")
                time.sleep(min(0.05, max(0, deadline - time.monotonic())))
        yield
    finally:
        os.close(fd)

def read_document(root: os.PathLike[str] | str, name: str) -> dict:
    name = _name(name)
    root_path = _root(root)
    try:
        root_path.lstat()
    except FileNotFoundError:
        return {"ok": True, "revision": None}
    path = _target(root_path, name)
    text, revision = _read(path)
    return {"ok": True, "revision": revision, **({"text": text} if text is not None else {})}

def _write_locked(root: Path, name: str, text: str, expected_revision: str | None) -> dict:
    if not isinstance(text, str):
        raise InvalidDocument("text must be a string")
    data = text.encode("utf-8")
    if len(data) > MAX_BYTES:
        raise InvalidDocument("document exceeds 1 MiB")
    path = _target(root, name)
    _current, revision = _read(path)
    if revision != expected_revision:
        raise Conflict("document revision changed")
    fd = -1
    temp_name = None
    try:
        fd, temp_name = tempfile.mkstemp(prefix=f".{name}.", suffix=".tmp", dir=root)
        os.fchmod(fd, 0o600)
        with os.fdopen(fd, "wb") as stream:
            fd = -1
            stream.write(data)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temp_name, path)
        temp_name = None
        dir_fd = os.open(root, os.O_RDONLY | getattr(os, "O_DIRECTORY", 0))
        try:
            os.fsync(dir_fd)
        finally:
            os.close(dir_fd)
        return {"ok": True, "revision": hashlib.sha256(data).hexdigest()}
    except PermissionError as exc:
        raise ReadOnly(str(exc)) from exc
    finally:
        if fd >= 0:
            os.close(fd)
        if temp_name:
            try:
                os.unlink(temp_name)
            except FileNotFoundError:
                pass

def write_document(root: os.PathLike[str] | str, name: str, text: str, expected_revision: str | None) -> dict:
    root_path = _root(root, create=True)
    with _locked(root_path):
        return _write_locked(root_path, name, text, expected_revision)

def checkpoint_document(root: os.PathLike[str] | str, name: str) -> dict:
    root_path = _root(root, create=True)
    name = _name(name)
    with _locked(root_path):
        text, revision = _read(_target(root_path, name))
        if text is None:
            raise InvalidDocument("cannot checkpoint a missing document")
        recovery = root_path / ".checkpoints"
        try:
            recovery.mkdir(mode=0o700)
        except FileExistsError:
            pass
        info = recovery.lstat()
        if not stat.S_ISDIR(info.st_mode):
            raise InvalidDocument("checkpoint directory is not a directory")
        os.chmod(recovery, 0o700)
        checkpoint_id = secrets.token_hex(16)
        checkpoint_path = recovery / checkpoint_id
        fd = os.open(checkpoint_path, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
        try:
            with os.fdopen(fd, "wb") as stream:
                stream.write(text.encode("utf-8"))
                stream.flush()
                os.fsync(stream.fileno())
            dir_fd = os.open(recovery, os.O_RDONLY | getattr(os, "O_DIRECTORY", 0))
            try:
                os.fsync(dir_fd)
            finally:
                os.close(dir_fd)
        except BaseException:
            try:
                checkpoint_path.unlink()
            except OSError:
                pass
            raise
        return {"ok": True, "revision": revision, "checkpointId": checkpoint_id}

def restore_document(root: os.PathLike[str] | str, name: str, checkpoint_id: str, expected_revision: str | None) -> dict:
    root_path = _root(root)
    name = _name(name)
    if not isinstance(checkpoint_id, str) or len(checkpoint_id) != 32 or any(c not in "0123456789abcdef" for c in checkpoint_id):
        raise InvalidDocument("invalid checkpoint id")
    recovery = root_path / ".checkpoints"
    info = recovery.lstat()
    if not stat.S_ISDIR(info.st_mode):
        raise InvalidDocument("checkpoint directory is not a directory")
    os.chmod(recovery, 0o700)
    text, _ = _read(recovery / checkpoint_id)
    if text is None:
        raise InvalidDocument("checkpoint not found")
    with _locked(root_path):
        result = _write_locked(root_path, name, text, expected_revision)
        return dict(result, text=text)

def _artwork_root(root: os.PathLike[str] | str, *, create: bool = False) -> Path:
    path = Path(root).absolute()
    if create:
        path.mkdir(mode=0o700, parents=True, exist_ok=True)
    info = path.lstat()
    if not stat.S_ISDIR(info.st_mode):
        raise InvalidDocument("artwork cache root is not a directory")
    if create:
        os.chmod(path, 0o700)
    return path

def _artwork_id(value: object) -> int:
    if isinstance(value, bool) or not isinstance(value, int) or value < 1 or value > 2**53 - 1:
        raise InvalidDocument("invalid artwork request id")
    return value

def _artwork_stage(root: Path, request_id: int) -> Path:
    return root / f".pending-{request_id}.part"

def _artwork_entry(root: Path, request_id: int) -> Path:
    return root / f"cover-{request_id}.img"

def artwork_prepare(root: os.PathLike[str] | str, request_id: object) -> dict:
    request_id = _artwork_id(request_id)
    root_path = _artwork_root(root, create=True)
    stage = _artwork_stage(root_path, request_id)
    with _locked(root_path):
        now = time.time()
        pending = []
        for path in root_path.iterdir():
            if not path.name.startswith(".pending-") or not path.name.endswith(".part"):
                continue
            try:
                info = path.lstat()
            except FileNotFoundError:
                continue
            if not stat.S_ISREG(info.st_mode):
                continue
            if now - info.st_mtime > ARTWORK_PENDING_STALE_SECONDS:
                path.unlink()
                continue
            pending.append((path, info.st_size))
        if len(pending) >= ARTWORK_PENDING_MAX_COUNT or sum(size for _, size in pending) + ARTWORK_MAX_BYTES > ARTWORK_PENDING_MAX_BYTES:
            raise InvalidDocument("artwork loader is at its pending request limit")
        fd = os.open(stage, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
        os.close(fd)
    return {"ok": True, "path": str(stage), "url": stage.as_uri()}

def artwork_copy_local(root: os.PathLike[str] | str, request_id: object, uri: object) -> dict:
    request_id = _artwork_id(request_id)
    if not isinstance(uri, str):
        raise InvalidDocument("invalid local artwork URI")
    parsed = urlsplit(uri)
    if parsed.scheme.lower() != "file" or parsed.netloc.lower() not in ("", "localhost") or parsed.query or parsed.fragment:
        raise InvalidDocument("invalid local artwork URI")
    source_path = unquote(parsed.path)
    if not source_path.startswith("/") or "\x00" in source_path:
        raise InvalidDocument("invalid local artwork path")
    root_path = _artwork_root(root, create=True)
    source_fd = os.open(source_path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    stage = _artwork_stage(root_path, request_id)
    target_fd = -1
    try:
        source_info = os.fstat(source_fd)
        if not stat.S_ISREG(source_info.st_mode) or source_info.st_size <= 0 or source_info.st_size > ARTWORK_MAX_BYTES:
            raise InvalidDocument("local artwork exceeds 4 MiB or is empty")
        artwork_prepare(root_path, request_id)
        target_fd = os.open(stage, os.O_WRONLY | os.O_TRUNC | os.O_NOFOLLOW, 0o600)
        total = 0
        while True:
            chunk = os.read(source_fd, min(65536, ARTWORK_MAX_BYTES + 1 - total))
            if not chunk:
                break
            total += len(chunk)
            if total > ARTWORK_MAX_BYTES:
                raise InvalidDocument("local artwork exceeds 4 MiB")
            view = memoryview(chunk)
            while view:
                written = os.write(target_fd, view)
                view = view[written:]
        if total == 0:
            raise InvalidDocument("local artwork is empty")
        os.fsync(target_fd)
        return {"ok": True, "path": str(stage), "url": stage.as_uri(), "size": total}
    except BaseException:
        try:
            stage.unlink()
        except FileNotFoundError:
            pass
        raise
    finally:
        os.close(source_fd)
        if target_fd >= 0:
            os.close(target_fd)

def _artwork_entries(root: Path) -> list[Path]:
    entries = []
    for path in root.iterdir():
        if not path.name.startswith("cover-") or not path.name.endswith(".img"):
            continue
        try:
            info = path.lstat()
        except FileNotFoundError:
            continue
        if stat.S_ISREG(info.st_mode):
            entries.append(path)
    return entries

def artwork_commit(root: os.PathLike[str] | str, request_id: object) -> dict:
    request_id = _artwork_id(request_id)
    root_path = _artwork_root(root)
    stage = _artwork_stage(root_path, request_id)
    try:
        info = stage.lstat()
    except FileNotFoundError as exc:
        raise InvalidDocument("artwork staging file is missing") from exc
    if not stat.S_ISREG(info.st_mode) or info.st_size <= 0 or info.st_size > ARTWORK_MAX_BYTES:
        try:
            stage.unlink()
        except FileNotFoundError:
            pass
        raise InvalidDocument("artwork exceeds 4 MiB or is empty")

    with _locked(root_path):
        entries = _artwork_entries(root_path)
        entries.sort(key=lambda path: (path.stat().st_mtime_ns, path.name))
        total = sum(path.stat().st_size for path in entries)
        incoming = info.st_size
        evicted = []
        while entries and (len(entries) >= ARTWORK_CACHE_MAX_COUNT or total + incoming > ARTWORK_CACHE_MAX_BYTES):
            old = entries.pop(0)
            total -= old.stat().st_size
            old.unlink()
            try:
                evicted.append(int(old.name[len("cover-"):-len(".img")]))
            except ValueError:
                pass
        target = _artwork_entry(root_path, request_id)
        try:
            current = target.lstat()
            if not stat.S_ISREG(current.st_mode):
                raise InvalidDocument("artwork cache target is not a regular file")
            target.unlink()
        except FileNotFoundError:
            pass
        os.replace(stage, target)
        os.chmod(target, 0o600)
        return {"ok": True, "path": str(target), "url": target.as_uri(), "size": incoming, "evicted": evicted}

def artwork_touch(root: os.PathLike[str] | str, request_id: object) -> dict:
    request_id = _artwork_id(request_id)
    root_path = _artwork_root(root)
    target = _artwork_entry(root_path, request_id)
    info = target.lstat()
    if not stat.S_ISREG(info.st_mode) or info.st_size > ARTWORK_MAX_BYTES:
        raise InvalidDocument("invalid artwork cache entry")
    os.utime(target, None, follow_symlinks=False)
    return {"ok": True}

def artwork_remove(root: os.PathLike[str] | str, request_id: object) -> dict:
    request_id = _artwork_id(request_id)
    root_path = _artwork_root(root, create=True)
    for target in (_artwork_stage(root_path, request_id), _artwork_entry(root_path, request_id)):
        try:
            info = target.lstat()
        except FileNotFoundError:
            continue
        if stat.S_ISREG(info.st_mode):
            target.unlink()
    return {"ok": True}
