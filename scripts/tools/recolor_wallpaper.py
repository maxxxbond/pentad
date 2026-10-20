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

def make_lut() -> bytes:
    """Return the 256 RGB samples used by the original PPM CLUT."""
    pixels = bytearray()
    for value in range(256):
        position = value / 255.0
        for (start, first), (end, second) in zip(STOPS, STOPS[1:]):
            if start <= position <= end:
                factor = (position - start) / (end - start)
                pixels.extend(
                    math.floor(a + factor * (b - a) + 0.5)
                    for a, b in zip(first, second)
                )
                break
    return bytes(pixels)

def recolor(input_path: Path, output_path: Path, magick: str = "magick") -> None:
    executable = shutil.which(magick)
    if executable is None:
        raise RuntimeError(
            "ImageMagick 'magick' was not found. Install ImageMagick to recolor wallpapers."
        )
    if not input_path.is_file():
        raise FileNotFoundError(f"Input image does not exist: {input_path}")

    with tempfile.TemporaryDirectory(prefix="pentad-moldavite-") as temp_dir:
        clut_path = Path(temp_dir) / "moldavite-clut.ppm"
        clut_path.write_bytes(b"P6\n256 1\n255\n" + make_lut())
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
    args = parser.parse_args(argv)
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
        recolor(source, destination)
    except FileNotFoundError as error:
        print(str(error), file=sys.stderr)
        return 1
    except subprocess.CalledProcessError as error:
        print(f"ImageMagick failed with exit status {error.returncode}.", file=sys.stderr)
        return error.returncode or 1
    except RuntimeError as error:
        print(str(error), file=sys.stderr)
        return 127
    print(f"Created Moldavite wallpaper: {destination}")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
