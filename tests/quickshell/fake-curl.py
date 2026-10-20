#!/usr/bin/env python3
"""Offline curl stand-in for the artwork QML fixture."""
import struct
import sys
import time
import zlib
from pathlib import Path

def png_chunk(kind: bytes, payload: bytes) -> bytes:
    body = kind + payload
    return struct.pack(">I", len(payload)) + body + struct.pack(">I", zlib.crc32(body) & 0xFFFFFFFF)

PNG = (
    b"\x89PNG\r\n\x1a\n"
    + png_chunk(b"IHDR", struct.pack(">IIBBBBB", 1, 1, 8, 6, 0, 0, 0))
    + png_chunk(b"IDAT", zlib.compress(b"\x00\xff\x00\x00\xff"))
    + png_chunk(b"IEND", b"")
)

def main() -> int:
    args = sys.argv[1:]
    output = args[args.index("--output") + 1]
    url = args[args.index("--url") + 1]
    if url.endswith("/slow"):
        time.sleep(1.5)
    if url.endswith("/not-found"):
        sys.stdout.write("\n404")
        return 22
    if url.endswith("/oversize"):
        Path(output).write_bytes(PNG + b"x" * (4 * 1024 * 1024 + 1))
        sys.stdout.write("\n200")
        return 0
    Path(output).write_bytes(PNG)
    sys.stdout.write("\n200")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
