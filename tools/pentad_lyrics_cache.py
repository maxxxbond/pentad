"""Private, bounded persistent cache for decoded LRCLIB responses."""
import json
import os
import secrets
import stat

MAX_BYTES = 4 * 1024 * 1024
MAX_ENTRIES = 64
FILENAME = "cache.json"

def _directory(root: str) -> str:
    os.makedirs(root, mode=0o700, exist_ok=True)
    root_info = os.lstat(root)
    if not stat.S_ISDIR(root_info.st_mode):
        raise ValueError("unsafe-cache-root")
    os.chmod(root, 0o700)
    parent = os.path.join(root, "pentad")
    directory = os.path.join(parent, "lyrics")
    for path in (parent, directory):
        try:
            os.mkdir(path, 0o700)
        except FileExistsError:
            info = os.lstat(path)
            if not stat.S_ISDIR(info.st_mode):
                raise ValueError("unsafe-cache-directory")
            os.chmod(path, 0o700)
    return directory

def _read_entries(directory: str) -> dict:
    path = os.path.join(directory, FILENAME)
    try:
        descriptor = os.open(path, os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0))
    except FileNotFoundError:
        return {}
    except OSError:
        return {}
    try:
        info = os.fstat(descriptor)
        if not stat.S_ISREG(info.st_mode) or info.st_size > MAX_BYTES:
            return {}
        with os.fdopen(descriptor, "r", encoding="utf-8") as stream:
            descriptor = -1
            value = json.load(stream)
    except (OSError, UnicodeError, ValueError, TypeError):
        return {}
    finally:
        if descriptor >= 0:
            os.close(descriptor)
    if not isinstance(value, dict) or value.get("version") != 1 or not isinstance(value.get("entries"), dict):
        return {}
    entries = value["entries"]
    return {key: item for key, item in entries.items()
            if isinstance(key, str) and isinstance(item, dict)}

def _bounded(entries: dict) -> dict:
    valid = {key: item for key, item in entries.items()
             if isinstance(key, str) and isinstance(item, dict)}
    valid = {key: item for key, item in valid.items()
             if len(json.dumps(item, ensure_ascii=False, separators=(",", ":")).encode("utf-8")) < MAX_BYTES}
    ordered = sorted(valid.items(), key=lambda pair: pair[1].get("savedAt", 0)
                     if isinstance(pair[1].get("savedAt", 0), (int, float)) else 0)
    while len(ordered) > MAX_ENTRIES:
        ordered.pop(0)
    while ordered:
        candidate = dict(ordered)
        encoded = json.dumps({"version": 1, "entries": candidate}, ensure_ascii=False,
                             separators=(",", ":")).encode("utf-8")
        if len(encoded) <= MAX_BYTES:
            return candidate
        ordered.pop(0)
    return {}

def read_lyrics_cache(root: str) -> dict:
    try:
        entries = _read_entries(_directory(root))
    except (OSError, ValueError):
        entries = {}
    return {"ok": True, "entries": _bounded(entries)}

def write_lyrics_cache(root: str, entries: object) -> dict:
    if not isinstance(entries, dict):
        return {"ok": False, "reason": "invalid"}
    try:
        directory = _directory(root)
        bounded = _bounded(entries)
        encoded = json.dumps({"version": 1, "entries": bounded}, ensure_ascii=False,
                             separators=(",", ":")).encode("utf-8")
        temporary = os.path.join(directory, ".cache-" + secrets.token_hex(8))
        descriptor = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        try:
            with os.fdopen(descriptor, "wb") as stream:
                stream.write(encoded)
                stream.flush()
                os.fsync(stream.fileno())
            os.replace(temporary, os.path.join(directory, FILENAME))
        finally:
            try:
                os.unlink(temporary)
            except FileNotFoundError:
                pass
    except (OSError, ValueError, TypeError, UnicodeError):
        return {"ok": False, "reason": "io"}
    return {"ok": True, "count": len(bounded)}
