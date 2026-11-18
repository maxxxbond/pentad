"""System facts for the resident worker (pentad_worker.py loads this module and calls
`register_ops(ops)`).

Ops:

- `system.vram` `{}` -> `{available: false}` or `{available: true, source, totalBytes, usedBytes,
  gpus: [{vendor, totalBytes, usedBytes, source}]}`. Best effort and read-only, with no new
  dependency: AMD cards report through `/sys/class/drm/card<N>/device/mem_info_vram_{total,used}`;
  NVIDIA through `nvidia-smi --query-gpu=...` when that program is on PATH. Anything else is
  `available: false`. `totalBytes`/`usedBytes` are those of the card with the most memory (the
  one a local model server most likely uses); `gpus` lists every card found, largest first.

Nothing here is written, cached or sent anywhere; the numbers describe the whole card, not only
what Pentad or a model server uses.
"""
import os
import re
import shutil
import sys

_HERE = os.path.dirname(os.path.abspath(__file__))
if _HERE not in sys.path:
    sys.path.append(_HERE)

from pentad_tool_core import ToolError, run  # noqa: E402

# Tests point this at a fake tree; the op only ever reads below it.
SYSFS_ROOT = '/sys'
NVIDIA_TIMEOUT_S = 5
MAX_GPUS = 16
_CARD = re.compile(r'card[0-9]{1,3}')
_VENDORS = {'0x1002': 'AMD', '0x10de': 'NVIDIA', '0x8086': 'Intel'}
_MIB = 1024 * 1024
_MAX_BYTES = 1 << 50  # 1 PiB: anything above is a misread, not a card


def _read_int(path):
    try:
        with open(path, 'rb') as handle:
            text = handle.read(64).decode('ascii', 'replace').strip()
    except OSError:
        return None
    return int(text) if text.isdigit() and 0 <= int(text) < _MAX_BYTES else None


def _read_text(path, limit=32):
    try:
        with open(path, 'rb') as handle:
            return handle.read(limit).decode('ascii', 'replace').strip()
    except OSError:
        return ''


def sysfs_gpus(root=None):
    """Cards that report VRAM through the amdgpu sysfs files."""
    base = os.path.join(root if root is not None else SYSFS_ROOT, 'class', 'drm')
    try:
        names = sorted(name for name in os.listdir(base) if _CARD.fullmatch(name))
    except OSError:
        return []
    gpus = []
    for name in names[:MAX_GPUS]:
        device = os.path.join(base, name, 'device')
        total = _read_int(os.path.join(device, 'mem_info_vram_total'))
        used = _read_int(os.path.join(device, 'mem_info_vram_used'))
        if not total or used is None:
            continue
        vendor = _VENDORS.get(_read_text(os.path.join(device, 'vendor')).lower(), 'GPU')
        gpus.append({'vendor': vendor, 'totalBytes': total, 'usedBytes': min(used, total), 'source': 'sysfs'})
    return gpus


def nvidia_gpus():
    """Cards nvidia-smi reports, in bytes; [] when it is missing or fails."""
    program = shutil.which('nvidia-smi')
    if not program:
        return []
    try:
        _, out, _ = run([program, '--query-gpu=memory.total,memory.used', '--format=csv,noheader,nounits'],
                        None, NVIDIA_TIMEOUT_S)
    except ToolError:
        return []
    gpus = []
    for line in out.decode('utf-8', 'replace').splitlines()[:MAX_GPUS]:
        parts = [part.strip() for part in line.split(',')]
        if len(parts) != 2 or not all(part.isdigit() for part in parts):
            continue
        total, used = int(parts[0]) * _MIB, int(parts[1]) * _MIB
        if 0 < total < _MAX_BYTES:
            gpus.append({'vendor': 'NVIDIA', 'totalBytes': total, 'usedBytes': min(used, total), 'source': 'nvidia-smi'})
    return gpus


def op_vram(payload, ctx):
    gpus = sysfs_gpus()
    ctx.check()
    if not gpus:
        gpus = nvidia_gpus()
    if not gpus:
        return {'ok': True, 'value': {'available': False}}
    gpus.sort(key=lambda gpu: -gpu['totalBytes'])
    first = gpus[0]
    return {'ok': True, 'value': {'available': True, 'source': first['source'], 'totalBytes': first['totalBytes'],
                                  'usedBytes': first['usedBytes'], 'gpus': gpus}}


def register_ops(ops):
    """Add system.vram to the worker's op table."""
    ops['system.vram'] = op_vram
