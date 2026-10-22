#!/usr/bin/env python3
"""Apply Pentad's five-stop Moldavite luminance map with ImageMagick."""

from __future__ import annotations

import argparse
import math
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

STOPS = (
    (0.00, (17, 19, 17)),
    (0.20, (25, 29, 24)),
    (0.50, (62, 75, 54)),
    (0.75, (134, 150, 119)),
    (1.00, (235, 240, 230)),
)

def parse_stops(text: str) -> tuple[tuple[float, tuple[int, int, int]], ...]:
    """Parse "0:#111311,0.5:#3E4B36,1:#EBF0E6" into ascending stops from 0 to 1."""
    stops = []
    for part in text.split(","):
        position, _, color = part.strip().partition(":")
        color = color.strip()
        if len(color) != 7 or color[0] != "#":
            raise ValueError(f"Invalid stop color: {part!r}")
        try:
            rgb = tuple(int(color[index:index + 2], 16) for index in (1, 3, 5))
            stops.append((float(position), rgb))
        except ValueError as error:
            raise ValueError(f"Invalid stop: {part!r}") from error
    if not 2 <= len(stops) <= 8:
        raise ValueError("Use between 2 and 8 stops.")
    positions = [position for position, _ in stops]
    if positions[0] != 0 or positions[-1] != 1 or any(b <= a for a, b in zip(positions, positions[1:])):
        raise ValueError("Stop positions must rise from 0 to 1.")
    return tuple(stops)

def make_lut(stops=STOPS) -> bytes:
    """Return the 256 RGB samples of the PPM CLUT (the original Moldavite map by default)."""
    pixels = bytearray()
    for value in range(256):
        position = value / 255.0
        for (start, first), (end, second) in zip(stops, stops[1:]):
            if start <= position <= end:
                factor = (position - start) / (end - start)
                pixels.extend(
                    math.floor(a + factor * (b - a) + 0.5)
                    for a, b in zip(first, second)
                )
                break
    return bytes(pixels)

def recolor(input_path: Path, output_path: Path, magick: str = "magick", stops=STOPS) -> None:
    executable = shutil.which(magick)
    if executable is None:
        raise RuntimeError(
            "ImageMagick 'magick' was not found. Install ImageMagick to recolor wallpapers."
        )
    if not input_path.is_file():
        raise FileNotFoundError(f"Input image does not exist: {input_path}")

    with tempfile.TemporaryDirectory(prefix="pentad-moldavite-") as temp_dir:
        clut_path = Path(temp_dir) / "moldavite-clut.ppm"
        clut_path.write_bytes(b"P6\n256 1\n255\n" + make_lut(stops))
        subprocess.run(
            [
                executable,
                str(input_path),
                "-colorspace", "Gray",
                "-auto-level",
                "-type", "TrueColor",
                str(clut_path),
                "-clut",
                str(output_path),
            ],
            check=True,
        )

def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        prog="pentad recolor-wallpaper",
        description="Map wallpaper luminance to Pentad's five-stop Moldavite palette.",
    )
    parser.add_argument("input", type=Path, help="source wallpaper image")
    parser.add_argument(
        "output", nargs="?", type=Path,
        help="output image (default: <input-name>-moldavite.<extension>)",
    )
    parser.add_argument(
        "--stops",
        help="luminance stops as position:#RRGGBB pairs, e.g. 0:#111311,0.75:#869677,1:#EBF0E6",
    )
    args = parser.parse_args(argv)
    try:
        stops = parse_stops(args.stops) if args.stops else STOPS
    except ValueError as error:
        print(str(error), file=sys.stderr)
        return 2
    source = args.input.expanduser().resolve()
    destination = (
        args.output.expanduser().resolve()
        if args.output
        else source.with_name(f"{source.stem}-moldavite{source.suffix}")
    )
    if destination == source:
        print("Output path must be different from the input image.", file=sys.stderr)
        return 2
    try:
        recolor(source, destination, stops=stops)
    except FileNotFoundError as error:
        print(str(error), file=sys.stderr)
        return 1
    except subprocess.CalledProcessError as error:
        print(f"ImageMagick failed with exit status {error.returncode}.", file=sys.stderr)
        return error.returncode or 1
    except RuntimeError as error:
        print(str(error), file=sys.stderr)
        return 127
    print(f"Created {'recolored' if args.stops else 'Moldavite'} wallpaper: {destination}")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
