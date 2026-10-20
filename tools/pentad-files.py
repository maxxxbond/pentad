#!/usr/bin/env python3
"""One-request JSON stdin/stdout entry point for the Pentad file helper."""
import json
import os
import argparse
import sys

from pentad_files import (
    CONFIG_NAMES, STATE_NAMES, Conflict, InvalidDocument, ReadOnly, StoreError,
    artwork_commit, artwork_copy_local, artwork_prepare, artwork_remove, artwork_touch,
    checkpoint_document, read_document, restore_document, write_document,
)
from pentad_lyrics_cache import read_lyrics_cache, write_lyrics_cache

def main() -> int:
    try:
        parser = argparse.ArgumentParser()
        parser.add_argument("--config-root", required=True)
        parser.add_argument("--state-root", required=True)
        parser.add_argument("--cache-root", default="")
        args = parser.parse_args()
        request_limit = 6 * 1024 * 1024 + 4096
        raw = sys.stdin.buffer.read(request_limit + 1)
        if len(raw) > request_limit:
            raise InvalidDocument("request exceeds transport limit")
        request = json.loads(raw.decode("utf-8"))
        if not isinstance(request, dict):
            raise InvalidDocument("request must be an object")
        operation = request.get("operation")
        if operation in {"lyrics-cache-read", "lyrics-cache-write"}:
            if not args.cache_root:
                raise InvalidDocument("lyrics cache root is required")
            if operation == "lyrics-cache-read":
                result = read_lyrics_cache(args.cache_root)
            else:
                result = write_lyrics_cache(args.cache_root, request.get("entries"))
            sys.stdout.write(json.dumps(result, separators=(",", ":"), ensure_ascii=False) + "\n")
            return 0
        if operation in {"artwork-prepare", "artwork-copy-local", "artwork-commit", "artwork-touch", "artwork-remove"}:
            if not args.cache_root:
                raise InvalidDocument("artwork cache root is required")
            request_id = request.get("requestId")
            if operation == "artwork-prepare":
                result = artwork_prepare(os.path.join(args.cache_root, "pentad", "artwork"), request_id)
            elif operation == "artwork-copy-local":
                result = artwork_copy_local(os.path.join(args.cache_root, "pentad", "artwork"), request_id, request.get("uri"))
            elif operation == "artwork-commit":
                result = artwork_commit(os.path.join(args.cache_root, "pentad", "artwork"), request_id)
            elif operation == "artwork-touch":
                result = artwork_touch(os.path.join(args.cache_root, "pentad", "artwork"), request_id)
            else:
                result = artwork_remove(os.path.join(args.cache_root, "pentad", "artwork"), request_id)
            sys.stdout.write(json.dumps(result, separators=(",", ":"), ensure_ascii=False) + "\n")
            return 0
        name = request.get("name")
        if name in CONFIG_NAMES:
            root = args.config_root
        elif name in STATE_NAMES:
            root = args.state_root
        else:
            raise InvalidDocument("unknown document")
        if operation == "read":
            result = read_document(root, name)
        elif operation == "write":
            if "expectedRevision" not in request:
                raise InvalidDocument("expectedRevision is required")
            result = write_document(root, name, request.get("text"), request["expectedRevision"])
        elif operation == "checkpoint":
            result = checkpoint_document(root, name)
        elif operation == "restore":
            if "expectedRevision" not in request:
                raise InvalidDocument("expectedRevision is required")
            result = restore_document(root, name, request.get("checkpointId"), request["expectedRevision"])
        else:
            raise InvalidDocument("unknown operation")
    except Conflict as exc:
        result = {"ok": False, "reason": "conflict"}
    except ReadOnly:
        result = {"ok": False, "reason": "read-only"}
    except (StoreError, OSError, UnicodeError, ValueError, KeyError, TypeError) as exc:
        result = {"ok": False, "reason": getattr(exc, "reason", "io")}
    sys.stdout.write(json.dumps(result, separators=(",", ":"), ensure_ascii=False) + "\n")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
