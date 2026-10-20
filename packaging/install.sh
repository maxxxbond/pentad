#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
prefix=${PREFIX:-/usr}
destdir=${DESTDIR:-}
quickshell_source=$script_dir/dist/quickshell

case "$prefix" in
  /*) ;;
  *) printf 'PREFIX must be an absolute path: %s\n' "$prefix" >&2; exit 2 ;;
esac
[ -d "$quickshell_source" ] || {
  printf 'Quickshell runtime is missing; run the project build first: %s\n' "$quickshell_source" >&2
  exit 1
}

install -Dm755 "$script_dir/scripts/pentad" "$destdir$prefix/bin/pentad"
install -Dm644 "$script_dir/scripts/tools/recolor_wallpaper.py" \
  "$destdir$prefix/lib/pentad/tools/recolor_wallpaper.py"
mkdir -p "$destdir$prefix/share/pentad/quickshell"
cp -a "$quickshell_source/." "$destdir$prefix/share/pentad/quickshell/"

printf 'Installed Pentad under %s%s\n' "$destdir" "$prefix"
printf 'Optional wallpaper recoloring requires ImageMagick (magick).\n'
