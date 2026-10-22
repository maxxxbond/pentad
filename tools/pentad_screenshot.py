#!/usr/bin/env python3
"""Private screenshot capture and original-resolution PNG export for Pentad."""
from __future__ import annotations

import json
import io
import math
import re
import os
import secrets
import signal
import stat
import subprocess
import sys
import tempfile
import time
from pathlib import Path

import cairo

# Sibling modules live next to this file. `python3 -I` leaves the script
# directory off sys.path; append it (never prepend) so the standard
# library still wins over anything in this directory.
_HERE = os.path.dirname(os.path.abspath(__file__))
if _HERE not in sys.path:
    sys.path.append(_HERE)

from pentad_screenshot_regions import _find_regions

MAX_DIMENSION = 16384
MAX_PIXELS = 64 * 1024 * 1024
MAX_ANNOTATIONS = 2000
MAX_POINTS = 100_000
MAX_REQUEST_BYTES = 12 * 1024 * 1024
TIMEOUT = 20
TYPES = {"brush", "line", "arrow", "rectangle", "ellipse", "text", "highlight", "redact"}

class RequestError(ValueError):
    pass

class HelperCancelled(Exception):
    pass

def _cancel_handler(_signum: int, _frame: object) -> None:
    raise HelperCancelled("screenshot operation cancelled")

def _run_command(args: list[str], *, input: bytes | None = None, timeout: int = TIMEOUT,
                 check: bool = False, capture_output: bool = False, text: bool = False) -> subprocess.CompletedProcess:
    proc = subprocess.Popen(args, stdin=subprocess.PIPE if input is not None else subprocess.DEVNULL,
                            stdout=subprocess.PIPE if capture_output else subprocess.DEVNULL,
                            stderr=subprocess.PIPE if capture_output else subprocess.DEVNULL,
                            text=text, start_new_session=True)
    try:
        stdout, stderr = proc.communicate(input=input, timeout=timeout)
    except subprocess.TimeoutExpired:
        _stop_process_group(proc)
        raise
    except BaseException:
        _stop_process_group(proc)
        raise
    result = subprocess.CompletedProcess(args, proc.returncode, stdout, stderr)
    if check and result.returncode:
        raise subprocess.CalledProcessError(result.returncode, args, stdout, stderr)
    return result

def _stop_process_group(proc: subprocess.Popen) -> None:
    try:
        os.killpg(proc.pid, signal.SIGTERM)
    except ProcessLookupError:
        pass
    try:
        proc.wait(timeout=1)
    except subprocess.TimeoutExpired:
        pass
    try:
        os.killpg(proc.pid, signal.SIGKILL)
    except ProcessLookupError:
        pass
    try:
        proc.wait()
    except ChildProcessError:
        pass

def _number(value: object, label: str) -> float:
    if isinstance(value, bool) or not isinstance(value, (int, float)) or not math.isfinite(value):
        raise RequestError(f"invalid {label}")
    return float(value)

def _session_root() -> Path:
    runtime = os.environ.get("XDG_RUNTIME_DIR")
    base = Path(runtime) if runtime else Path(tempfile.gettempdir())
    info = base.lstat()
    if not stat.S_ISDIR(info.st_mode) or (runtime and info.st_uid != os.getuid()):
        raise RequestError("unsafe runtime directory")
    return base

def _session_dir(session: object) -> Path:
    if not isinstance(session, str) or len(session) != 32 or any(c not in "0123456789abcdef" for c in session):
        raise RequestError("invalid session")
    path = _session_root() / f"pentad-screenshot-{session}"
    info = path.lstat()
    if not stat.S_ISDIR(info.st_mode) or info.st_uid != os.getuid() or stat.S_IMODE(info.st_mode) != 0o700:
        raise RequestError("invalid session directory")
    return path

def _png(path: Path) -> tuple[cairo.ImageSurface, int, int]:
    info = path.lstat()
    if not stat.S_ISREG(info.st_mode) or info.st_size <= 0 or info.st_size > 400_000_000:
        raise RequestError("invalid screenshot file")
    with path.open("rb") as stream:
        header = stream.read(24)
    if len(header) < 24 or header[:8] != b"\x89PNG\r\n\x1a\n" or header[12:16] != b"IHDR":
        raise RequestError("invalid screenshot PNG")
    width = int.from_bytes(header[16:20], "big")
    height = int.from_bytes(header[20:24], "big")
    if not (1 <= width <= MAX_DIMENSION and 1 <= height <= MAX_DIMENSION and width * height <= MAX_PIXELS):
        raise RequestError("screenshot dimensions exceed limits")
    surface = cairo.ImageSurface.create_from_png(str(path))
    if (surface.get_width(), surface.get_height()) != (width, height):
        surface.finish()
        raise RequestError("invalid screenshot dimensions")
    return surface, width, height

def _validate_document(document: object, width: int, height: int) -> tuple[dict, tuple[int, int, int, int]]:
    if (not isinstance(document, dict) or type(document.get("width")) is not int
            or type(document.get("height")) is not int or document.get("width") != width
            or document.get("height") != height):
        raise RequestError("document dimensions do not match screenshot")
    crop = document.get("crop")
    if not isinstance(crop, dict):
        raise RequestError("invalid crop")
    x, y, w, h = (_number(crop.get(k), f"crop {k}") for k in ("x", "y", "width", "height"))
    if w <= 0 or h <= 0 or x < 0 or y < 0 or x + w > width or y + h > height:
        raise RequestError("crop is outside screenshot")
    left, top = math.floor(x), math.floor(y)
    right, bottom = math.ceil(x + w), math.ceil(y + h)
    annotations = document.get("annotations")
    if not isinstance(annotations, list) or len(annotations) > MAX_ANNOTATIONS:
        raise RequestError("invalid annotations")
    count = 0
    for a in annotations:
        if not isinstance(a, dict) or a.get("type") not in TYPES:
            raise RequestError("invalid annotation")
        for key in ("x", "y", "width", "height", "strokeWidth", "fontSize"):
            if key in a:
                if abs(_number(a[key], f"annotation {key}")) > MAX_DIMENSION * 4:
                    raise RequestError("annotation geometry exceeds limits")
        if a.get("type") == "text" and (not isinstance(a.get("text"), str) or len(a["text"]) > 4096):
            raise RequestError("invalid annotation text")
        color = a.get("color", "#ff5252")
        if not isinstance(color, str) or len(color) not in (7, 9) or not color.startswith("#"):
            raise RequestError("invalid annotation color")
        try:
            int(color[1:], 16)
        except ValueError as exc:
            raise RequestError("invalid annotation color") from exc
        points = a.get("points", [])
        if not isinstance(points, list):
            raise RequestError("invalid annotation points")
        count += len(points)
        if count > MAX_POINTS:
            raise RequestError("too many annotation points")
        for point in points:
            if not isinstance(point, dict):
                raise RequestError("invalid annotation point")
            if any(abs(_number(point.get(k), f"point {k}")) > MAX_DIMENSION * 4 for k in ("x", "y")):
                raise RequestError("annotation geometry exceeds limits")
    return {"annotations": annotations}, (left, top, right - left, bottom - top)

def _rgba(value: str, alpha: float = 1.0) -> tuple[float, float, float, float]:
    raw = value[1:]
    r, g, b = (int(raw[i:i + 2], 16) / 255 for i in (0, 2, 4))
    a = int(raw[6:8], 16) / 255 if len(raw) == 8 else 1.0
    return r, g, b, a * alpha

def _draw_annotation(ctx: cairo.Context, a: dict, font_family: str) -> None:
    kind = a["type"]
    x, y = float(a.get("x", 0)), float(a.get("y", 0))
    w, h = float(a.get("width", 0)), float(a.get("height", 0))
    color = a.get("color", "#ff5252")
    stroke = max(1.0, min(100.0, float(a.get("strokeWidth", 4))))
    r, g, b, alpha = _rgba(color, .3 if kind == "highlight" else 1)
    ctx.set_source_rgba(r, g, b, alpha)
    if kind == "redact":
        ctx.set_source_rgba(r, g, b, 1)
        ctx.rectangle(x, y, w, h)
        ctx.fill()
        return
    if kind == "text":
        ctx.select_font_face(font_family, cairo.FONT_SLANT_NORMAL, cairo.FONT_WEIGHT_NORMAL)
        font_size = max(6, min(256, float(a.get("fontSize", 24))))
        ctx.set_font_size(font_size)
        ascent = ctx.font_extents()[0]
        for index, line in enumerate(a["text"].splitlines() or [""]):
            ctx.move_to(x, y + ascent + font_size * index * 1.2)
            ctx.show_text(line)
        return
    if kind in ("brush", "line", "arrow"):
        points = a.get("points") or [{"x": x, "y": y}, {"x": x + w, "y": y + h}]
        ctx.set_line_width(stroke)
        ctx.set_line_cap(cairo.LINE_CAP_ROUND)
        ctx.set_line_join(cairo.LINE_JOIN_ROUND)
        if kind == "brush" and len(points) == 1:
            ctx.arc(float(points[0]["x"]), float(points[0]["y"]), stroke / 2, 0, math.tau)
            ctx.fill()
            return
        ctx.move_to(float(points[0]["x"]), float(points[0]["y"]))
        for p in points[1:]:
            ctx.line_to(float(p["x"]), float(p["y"]))
        ctx.stroke()
        if kind == "arrow" and len(points) > 1:
            p0, p1 = points[-2], points[-1]
            dx, dy = float(p1["x"]) - float(p0["x"]), float(p1["y"]) - float(p0["y"])
            length = math.hypot(dx, dy)
            if length:
                size = max(12, stroke * 4)
                angle = math.atan2(dy, dx)
                ctx.move_to(float(p1["x"]), float(p1["y"]))
                ctx.line_to(float(p1["x"]) - size * math.cos(angle - math.pi / 6), float(p1["y"]) - size * math.sin(angle - math.pi / 6))
                ctx.move_to(float(p1["x"]), float(p1["y"]))
                ctx.line_to(float(p1["x"]) - size * math.cos(angle + math.pi / 6), float(p1["y"]) - size * math.sin(angle + math.pi / 6))
                ctx.stroke()
        return
    ctx.set_line_width(stroke)
    if kind == "ellipse":
        ctx.save()
        ctx.translate(x + w / 2, y + h / 2)
        ctx.scale(max(abs(w) / 2, .01), max(abs(h) / 2, .01))
        ctx.arc(0, 0, 1, 0, math.tau)
        ctx.restore()
    else:
        ctx.rectangle(x, y, w, h)
    if kind == "highlight":
        ctx.fill()
    else:
        ctx.stroke()

def _render(source: cairo.ImageSurface, document: dict, crop: tuple[int, int, int, int], font_family: str) -> bytes:
    x, y, width, height = crop
    output = cairo.ImageSurface(cairo.FORMAT_ARGB32, width, height)
    ctx = cairo.Context(output)
    ctx.set_source_surface(source, -x, -y)
    ctx.paint()
    ctx.save()
    ctx.translate(-x, -y)
    for annotation in document["annotations"]:
        _draw_annotation(ctx, annotation, font_family)
    ctx.restore()
    output.flush()
    png = io.BytesIO()
    output.write_to_png(png)
    output.finish()
    return png.getvalue()

def _pictures_directory() -> Path:
    try:
        result = _run_command(["xdg-user-dir", "PICTURES"], capture_output=True, text=True, timeout=5)
        value = result.stdout.strip() if result.returncode == 0 else ""
    except (OSError, subprocess.SubprocessError):
        value = ""
    return Path(value) if value.startswith("/") else Path.home() / "Pictures"

def _save(directory: object, png: bytes) -> str:
    if directory is None or directory == "":
        target_dir = _pictures_directory() / "Pentad"
    elif isinstance(directory, str) and directory and "\x00" not in directory:
        target_dir = Path(directory).expanduser()
    else:
        raise RequestError("invalid save directory")
    target_dir.mkdir(mode=0o700, parents=True, exist_ok=True)
    if not stat.S_ISDIR(target_dir.lstat().st_mode):
        raise RequestError("save target is not a directory")
    stamp = time.strftime("%Y%m%d-%H%M%S")
    for suffix in range(10000):
        name = f"Pentad-{stamp}{'-' + str(suffix) if suffix else ''}.png"
        target = target_dir / name
        fd, temporary = tempfile.mkstemp(prefix=".pentad-", suffix=".tmp", dir=target_dir)
        try:
            os.fchmod(fd, 0o600)
            with os.fdopen(fd, "wb") as stream:
                stream.write(png)
                stream.flush()
                os.fsync(stream.fileno())
            try:
                os.link(temporary, target)
                return str(target)
            except FileExistsError:
                continue
        finally:
            Path(temporary).unlink(missing_ok=True)
    raise OSError("could not choose a unique screenshot name")

def export_bindings(content: object) -> dict:
    if not isinstance(content, str) or len(content.encode("utf-8")) > 16 * 1024 or "\x00" in content:
        raise RequestError("bindings fragment must be at most 16 KiB of text")
    base = Path(os.environ.get("XDG_CONFIG_HOME") or (Path.home() / ".config")).expanduser()
    if not base.is_absolute():
        raise RequestError("config directory must be absolute")
    target_dir = base / "pentad"
    target_dir.mkdir(mode=0o700, parents=True, exist_ok=True)
    if not stat.S_ISDIR(target_dir.lstat().st_mode):
        raise RequestError("Pentad config path is not a directory")
    target = target_dir / "hyprland-screenshots.lua"
    fd, temporary = tempfile.mkstemp(prefix=".screenshots-", suffix=".tmp", dir=target_dir)
    try:
        os.fchmod(fd, 0o600)
        with os.fdopen(fd, "w", encoding="utf-8") as stream:
            stream.write(content)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, target)
        return {"ok": True, "path": str(target)}
    finally:
        Path(temporary).unlink(missing_ok=True)

def capture(output: object, requested_session: object = None, timeout: int = TIMEOUT,
            owned: list[Path] | None = None) -> dict:
    if not isinstance(output, str) or not output or len(output) > 256 or "\x00" in output:
        raise RequestError("invalid output")
    base = _session_root()
    session = requested_session if requested_session is not None else secrets.token_hex(16)
    if not isinstance(session, str) or len(session) != 32 or any(c not in "0123456789abcdef" for c in session):
        raise RequestError("invalid session")
    directory = base / f"pentad-screenshot-{session}"
    created = False
    try:
        previous_mask = signal.pthread_sigmask(signal.SIG_BLOCK, {signal.SIGTERM})
        try:
            directory.mkdir(mode=0o700)
            created = True
            if owned is not None:
                owned.append(directory)
        finally:
            signal.pthread_sigmask(signal.SIG_SETMASK, previous_mask)
        image = directory / "source.png"
        result = _run_command(["grim", "-o", output, str(image)], capture_output=True, timeout=timeout)
        if result.returncode:
            raise RequestError((result.stderr.decode(errors="replace") or "screenshot capture failed")[:1000])
        surface, width, height = _png(image)
        surface.finish()
        os.chmod(image, 0o600)
        return {"ok": True, "path": str(image), "width": width, "height": height, "session": session}
    except BaseException:
        if created:
            _remove_session(directory)
        raise

def capture_all(outputs: object, sessions: object) -> dict:
    if not isinstance(outputs, list) or not 1 <= len(outputs) <= 8:
        raise RequestError("capture-all requires 1 to 8 outputs")
    if not isinstance(sessions, list) or len(sessions) != len(outputs):
        raise RequestError("capture-all requires one session per output")
    if any(not isinstance(output, str) or not output or len(output) > 256 or "\x00" in output
           for output in outputs) or len(set(outputs)) != len(outputs):
        raise RequestError("invalid or duplicate output")
    if any(not isinstance(token, str) or len(token) != 32
           or any(c not in "0123456789abcdef" for c in token) for token in sessions):
        raise RequestError("invalid session")
    if len(set(sessions)) != len(sessions):
        raise RequestError("duplicate session")

    frames = []
    owned: list[Path] = []
    success = False
    try:
        for output, token in zip(outputs, sessions):
            result = capture(output, token, timeout=5, owned=owned)
            frames.append({"output": output, "session": result["session"], "path": result["path"],
                           "width": result["width"], "height": result["height"]})
        success = True
        return {"ok": True, "frames": frames}
    finally:
        if not success:
            for directory in owned:
                _remove_session(directory)

def _remove_session(directory: Path) -> None:
    try:
        info = directory.lstat()
        if stat.S_ISDIR(info.st_mode) and info.st_uid == os.getuid() and directory.name.startswith("pentad-screenshot-"):
            for child in directory.iterdir():
                try:
                    if child.is_file() or child.is_symlink():
                        child.unlink()
                except OSError:
                    pass
            directory.rmdir()
    except FileNotFoundError:
        pass

def export(session: object, document: object, action: object, directory: object, auto_save: object,
           font_family: object = "Sans") -> dict:
    work = _session_dir(session)
    if action not in ("copy", "save") or not isinstance(auto_save, bool):
        raise RequestError("invalid export request")
    if not isinstance(font_family, str) or not font_family or len(font_family) > 80 or not all(
            c.isalnum() or c in " -_" for c in font_family):
        raise RequestError("invalid font family")
    source, width, height = _png(work / "source.png")
    try:
        model, crop = _validate_document(document, width, height)
        png = _render(source, model, crop, font_family)
    finally:
        source.finish()
    result: dict = {"ok": False, "copied": False, "saved": False}
    save_requested = action == "save" or (action == "copy" and auto_save)
    if action == "copy":
        try:
            _run_command(["wl-copy", "--type", "image/png"], input=png, timeout=TIMEOUT, check=True)
            result["copied"] = True
        except (OSError, subprocess.SubprocessError) as exc:
            result["copyError"] = str(exc)[:1000]
    if save_requested:
        try:
            result["path"] = _save(directory, png)
            result["saved"] = True
        except (OSError, RequestError) as exc:
            result["saveError"] = str(exc)[:1000]
    result["ok"] = result["copied"] or result["saved"]
    return result

PICK_NAME = re.compile(r"^pentad-pick-[0-9a-f]{32}\.png$")
MAX_SCALE = 8

def crop(session: object, rect: object, scale: object = 1) -> dict:
    """Write the selected area of a frozen frame to a private PNG, optionally enlarged by an integer factor."""
    work = _session_dir(session)
    if not isinstance(rect, dict):
        raise RequestError("invalid crop")
    x, y, w, h = (_number(rect.get(k), f"crop {k}") for k in ("x", "y", "width", "height"))
    if isinstance(scale, bool) or not isinstance(scale, int) or not 1 <= scale <= MAX_SCALE:
        raise RequestError("invalid scale")
    source, width, height = _png(work / "source.png")
    try:
        if w <= 0 or h <= 0 or x < 0 or y < 0 or x + w > width or y + h > height:
            raise RequestError("crop is outside screenshot")
        left, top = math.floor(x), math.floor(y)
        right, bottom = math.ceil(x + w), math.ceil(y + h)
        crop_width, crop_height = right - left, bottom - top
        if crop_width * scale * crop_height * scale > MAX_PIXELS:
            raise RequestError("crop exceeds the pixel limit")
        output = cairo.ImageSurface(cairo.FORMAT_ARGB32, crop_width * scale, crop_height * scale)
        ctx = cairo.Context(output)
        ctx.scale(scale, scale)
        ctx.set_source_surface(source, -left, -top)
        if scale > 1:
            ctx.get_source().set_filter(cairo.FILTER_NEAREST)
        ctx.paint()
        output.flush()
        png = io.BytesIO()
        output.write_to_png(png)
        output.finish()
    finally:
        source.finish()
    path = _session_root() / f"pentad-pick-{secrets.token_hex(16)}.png"
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL | getattr(os, "O_NOFOLLOW", 0), 0o600)
    try:
        with os.fdopen(fd, "wb") as stream:
            stream.write(png.getvalue())
    except BaseException:
        path.unlink(missing_ok=True)
        raise
    return {"ok": True, "path": str(path), "width": crop_width * scale, "height": crop_height * scale,
            "x": left, "y": top, "cropWidth": crop_width, "cropHeight": crop_height, "scale": scale}

def discard(path: object) -> dict:
    """Remove a file written by crop(); nothing else may be removed through this."""
    if not isinstance(path, str) or "\x00" in path:
        raise RequestError("invalid path")
    target = Path(path)
    if target.parent != _session_root() or not PICK_NAME.match(target.name):
        raise RequestError("not a pick file")
    target.unlink(missing_ok=True)
    return {"ok": True}

# --- content proposals (the region engine lives in pentad_screenshot_regions) ---

def _numpy():
    try:
        import numpy
        return numpy
    except ImportError:
        return None

def proposals(session: object) -> dict:
    work = _session_dir(session)
    np = _numpy()
    source, width, height = _png(work / "source.png")
    try:
        if np is None:
            return {"ok": True, "regions": [], "reason": "numpy is unavailable"}
        # Whatever the PNG's depth (8 or 16 bit, with or without alpha), read it as plain 8-bit ARGB32.
        plain = cairo.ImageSurface(cairo.FORMAT_ARGB32, width, height)
        ctx = cairo.Context(plain)
        ctx.set_source_rgb(1, 1, 1)
        ctx.paint()
        ctx.set_source_surface(source, 0, 0)
        ctx.paint()
        plain.flush()
        stride = plain.get_stride()
        frame = np.frombuffer(plain.get_data(), dtype=np.uint8).reshape(height, stride // 4, 4)[:, :width, :3].copy()
        plain.finish()
    finally:
        source.finish()
    return {"ok": True, "regions": _find_regions(np, frame)}

def handle(request: object) -> dict:
    if not isinstance(request, dict):
        raise RequestError("request must be an object")
    operation = request.get("operation")
    if operation == "crop":
        return crop(request.get("session"), request.get("rect"), request.get("scale", 1))
    if operation == "discard":
        return discard(request.get("path"))
    if operation == "proposals":
        return proposals(request.get("session"))
    if operation == "capture":
        return capture(request.get("output"), request.get("session"))
    if operation == "capture-all":
        return capture_all(request.get("outputs"), request.get("sessions"))
    if operation == "export":
        return export(request.get("session"), request.get("document"), request.get("action"),
                      request.get("directory", ""), request.get("autoSave", False),
                      request.get("fontFamily", "Sans"))
    if operation == "cleanup":
        work = _session_dir(request.get("session"))
        _remove_session(work)
        return {"ok": True}
    if operation == "bindings":
        return export_bindings(request.get("content"))
    raise RequestError("unknown operation")

def read_request(stream: object) -> object:
    request_bytes = stream.read(MAX_REQUEST_BYTES + 1)
    if len(request_bytes) > MAX_REQUEST_BYTES:
        raise RequestError("request exceeds 12 MiB")
    return json.loads(request_bytes)

def main() -> int:
    try:
        signal.signal(signal.SIGTERM, _cancel_handler)
        request = read_request(sys.stdin.buffer)
        result = handle(request)
    except Exception as exc:
        result = {"ok": False, "error": str(exc)[:1000]}
    sys.stdout.write(json.dumps(result, separators=(",", ":")) + "\n")
    return 0 if result.get("ok") else 1

if __name__ == "__main__":
    raise SystemExit(main())
