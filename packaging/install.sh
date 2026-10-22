#!/bin/sh
set -eu

usage() {
  printf '%s\n' 'Usage: packaging/install.sh [--prefix DIR] [--runtime DIR] [--uninstall]' \
    '' \
    'Installs Pentad for the current user in ~/.local, or in /usr/local when run as root.' \
    '  --prefix DIR   install under DIR instead (also PREFIX=DIR); packagers add DESTDIR=...' \
    '  --runtime DIR  install an already built Quickshell runtime instead of building one' \
    '  --uninstall    remove Pentad from the prefix; your settings in ~/.config/pentad stay'
}

fail() {
  printf '%s\n' "$1" >&2
  exit 1
}

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
action=install
runtime=
while [ "$#" -gt 0 ]; do
  case "$1" in
    --prefix) [ "$#" -ge 2 ] || { usage >&2; exit 2; }; PREFIX=$2; shift 2 ;;
    --runtime) [ "$#" -ge 2 ] || { usage >&2; exit 2; }; runtime=$2; shift 2 ;;
    --uninstall) action=uninstall; shift ;;
    -h|--help) usage; exit 0 ;;
    *) printf 'Unknown argument: %s\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
done
if [ -z "${PREFIX-}" ]; then
  if [ "$(id -u)" -eq 0 ]; then PREFIX=/usr/local; else PREFIX=${HOME:?HOME is not set}/.local; fi
fi
prefix=$PREFIX
destdir=${DESTDIR:-}
case "$prefix" in
  /*) ;;
  *) printf 'PREFIX must be an absolute path: %s\n' "$prefix" >&2; exit 2 ;;
esac
launcher=$destdir$prefix/bin/pentad
share=$destdir$prefix/share/pentad
legacy_helper=$destdir$prefix/lib/pentad/tools/recolor_wallpaper.py

# Replacing or removing files under a running shell breaks it; staged installs (DESTDIR) are never live.
if [ -z "$destdir" ] && [ -d "$share/quickshell" ] && command -v qs >/dev/null 2>&1; then
  running=$(qs list --path "$share/quickshell" --json 2>/dev/null) || running=
  case "$running" in
    *'"id"'*) fail "Pentad is running from $share/quickshell. Stop it with 'pentad stop', run this again, then 'pentad start'." ;;
  esac
fi

remove_legacy_helper() {
  rm -f "$legacy_helper"
  rmdir "${legacy_helper%/*}" "${legacy_helper%/*/*}" 2>/dev/null || true
}

if [ "$action" = uninstall ]; then
  [ -f "$launcher" ] || [ -d "$share" ] || fail "Pentad is not installed in $destdir$prefix."
  if [ -f "$launcher" ]; then
    grep -q 'pentad start' "$launcher" || fail "$launcher is not the Pentad launcher; leaving it in place."
    rm -f "$launcher"
  fi
  rm -rf "$share"
  remove_legacy_helper
  printf 'Removed Pentad from %s%s.\n' "$destdir" "$prefix"
  printf 'Your settings and state stay in ~/.config/pentad and ~/.local/state/pentad; delete them if you no longer need them.\n'
  exit 0
fi

staging=
work=$(mktemp -d "${TMPDIR:-/tmp}/pentad-install.XXXXXX")
trap 'rm -rf "$work" ${staging:+"$staging"}' EXIT
trap 'exit 130' INT TERM
if [ -z "$runtime" ]; then
  if [ -f "$script_dir/runtime/shell.qml" ]; then
    # A release tarball ships the runtime prebuilt.
    runtime=$script_dir/runtime
  elif [ -f "$script_dir/quickshell/shell.qml" ]; then
    command -v node >/dev/null 2>&1 || fail 'Building Pentad from source needs Node.js (only while installing). Install Node.js, or use a release tarball, which needs no build.'
    node "$script_dir/scripts/build-quickshell.mjs" --output "$work/quickshell"
    runtime=$work/quickshell
  else
    fail "Neither a prebuilt runtime nor the Pentad source was found in $script_dir."
  fi
fi
[ -f "$runtime/shell.qml" ] || fail "Not a Pentad Quickshell runtime: $runtime"

mkdir -p "$share"
staging=$(mktemp -d "$share/.quickshell-new.XXXXXX")
cp -R "$runtime/." "$staging/"
chmod -R u+rwX,go+rX,go-w "$staging"
# Swap the whole tree so files removed upstream do not linger from an older version.
if [ -e "$share/quickshell" ]; then
  mv "$share/quickshell" "$staging.old"
fi
mv "$staging" "$share/quickshell"
rm -rf "$staging.old"
install -Dm755 "$script_dir/scripts/pentad" "$launcher"
remove_legacy_helper

printf 'Installed Pentad in %s%s.\n' "$destdir" "$prefix"
[ -z "$destdir" ] || exit 0
case ":$PATH:" in
  *":$prefix/bin:"*) ;;
  *) printf '\n%s/bin is not in your PATH. Add it in your shell profile, for example:\n  export PATH="%s/bin:$PATH"\n' "$prefix" "$prefix" ;;
esac
printf '%s\n' '' 'Next steps:' \
  '  1. Check what Pentad finds on this system:  pentad doctor' \
  '  2. Start Pentad with Hyprland. In hyprland.lua:' \
  '       hl.on("hyprland.start", function () hl.exec_cmd("pentad start") end)' \
  '     or in hyprland.conf:  exec-once = pentad start' \
  "  3. Key bindings to include in hyprland.lua: $prefix/share/pentad/quickshell/defaults/hyprland-quickshell.lua"
