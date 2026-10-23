# Packaging Pentad

The user-facing install steps are in the [README](../README.md#install). This page is for packagers and for reference.

## install.sh

`packaging/install.sh` installs from a source checkout or from a release tarball:

- In a checkout it builds the Quickshell runtime into a temporary directory first. That needs Node.js (any current LTS; the build uses only its standard library), but not pnpm or `node_modules`.
- In a release tarball it installs the prebuilt `runtime/` and needs no Node.js.
- `--runtime DIR` installs an already built runtime, for example one from `node scripts/build-quickshell.mjs --output DIR`.

Without `PREFIX` it installs into `~/.local`, or into `/usr/local` when run as root. Package builders stage the layout with `DESTDIR` and `PREFIX` (or `--prefix`):

```sh
DESTDIR="$pkgdir" PREFIX=/usr packaging/install.sh
```

After a real install (not a `DESTDIR` stage) on a system with `pacman`, it asks `pentad doctor --required-packages` for missing required packages. On a terminal it offers `sudo pacman -S --needed …` and runs it only after a yes; without a terminal it prints the command. Optional packages are never offered here. An install swaps the whole runtime directory, so files removed upstream do not linger. Outside `DESTDIR`, install and `--uninstall` refuse to run while Pentad is running from that prefix. `--uninstall` removes the launcher and the runtime, and keeps the user's settings and state in `~/.config/pentad` and `~/.local/state/pentad`.

## Install tree

- `PREFIX/bin/pentad`: the launcher. It finds the runtime at `../share/pentad/quickshell` relative to itself, following symlinks, so any prefix works without `--path`.
- `PREFIX/share/pentad/quickshell`: the runtime, with QML, assets, defaults, `LICENSE` and `LICENSES/`, and the Python helpers in `helpers/`.

Earlier versions also installed the recolor helper as `PREFIX/lib/pentad/tools/recolor_wallpaper.py`. The launcher now uses the copy in `helpers/`, and `install.sh` removes the old file.

## Dependencies

`pentad doctor` checks all of these on the user's machine, groups the optional ones by feature, and on Arch prints the `pacman` command for what is missing. Its `FEATURES` table in `tools/pentad_doctor.py` is the source of truth. `tests/tooling/test_doctor.py` checks that the Arch package lists every package the doctor suggests.

Required at runtime:

| What | Why | Arch package |
| --- | --- | --- |
| Hyprland | the compositor Pentad runs in | `hyprland` |
| Quickshell 0.3.2 or newer | the shell runtime | `quickshell` |
| Qt 5 Compatibility module | telemetry's alpha mask (`Qt5Compat.GraphicalEffects`) | `qt6-5compat` |
| Qt SVG | icons | `qt6-svg` |
| Python 3 | helpers for files, screenshots, Spotlight and wallpapers | `python` |

Recommended: the [Geist](https://github.com/vercel/geist-font) font, the default UI typeface. Without it Qt falls back to the default sans-serif font. It is not in the official Arch repositories.

Optional. A missing program only turns off the feature that uses it:

| Feature | Programs (Arch package) |
| --- | --- |
| Screenshots | `grim`, `wl-copy` (`wl-clipboard`), Pycairo (`python-cairo`); NumPy (`python-numpy`) speeds up region detection |
| Screen recording | `wf-recorder` |
| Clipboard history | `cliphist`, `wl-copy` |
| Opening apps and links | `gtk-launch` (`gtk3`), `xdg-open` (`xdg-utils`) |
| Emoji | Noto Color Emoji (`noto-fonts-emoji`) |
| Volume, audio output | `wpctl` (`wireplumber`), `pactl` (`libpulse`) |
| Audio visualizer | `cava` |
| Network and VPN, Bluetooth, Tailscale | `nmcli` (`networkmanager`), `bluetoothctl` (`bluez-utils`), `tailscale` |
| Power profiles, brightness | `power-profiles-daemon` with `busctl` (`systemd`), `brightnessctl` or `ddcutil` |
| Night light, color picker | `hyprsunset`, `hyprpicker` |
| Session, lock screen, keep awake | `busctl`, `loginctl`, `systemd-inhibit` (`systemd`), `hyprlock`, `hypridle` |
| Settings: date and time, default apps | `timedatectl` (`systemd`; changes ask polkit), `xdg-mime` (`xdg-utils`) |
| Lyrics, weather, album art | `curl` |
| Notices from tools | `notify-send` (`libnotify`) |
| File picker, shelf previews | PyGObject (`python-gobject`) with xdg-desktop-portal, or `zenity` for the picker |
| Image tools, wallpaper colors | `magick` (`imagemagick`) |
| Audio and video, PDF, archives | `ffmpeg`, `qpdf`, `gs` (`ghostscript`), `pdftoppm` and `pdftotext` (`poppler`), `7z` (`7zip`), `zstd` |
| Text recognition, QR codes | `tesseract` with `tesseract-data-eng`, `zbarimg` (`zbar`), `qrencode` |
| Translation, YAML widget, LocalSend | `trans` (`translate-shell`) or `jq`, `yq` (`go-yq`), `localsend` |

Pentad serves desktop notifications and draws the wallpaper itself once one is chosen in Settings → Wallpaper. Another notification daemon (mako, dunst, swaync) or wallpaper daemon (hyprpaper, swaybg, swww) conflicts with it; `pentad doctor` warns when one is running. Bind keys to `pentad wallpaper random|next|previous` or `pentad wallpaper set <file>`.

The native screenshot editor needs no external annotation application. `xdg-user-dir` is used when available to find the Pictures folder. Right-click the screenshot button to configure shortcuts and export a Hyprland Lua fragment; the fragment is not activated automatically.

## Arch package

`packaging/arch/PKGBUILD` builds `pentad-git` from the checkout it lives in:

```sh
cd packaging/arch
makepkg -si
```

`makepkg` updates the `pkgver` line from git; do not commit that change. For the AUR, point `source` at the public repository and build from `$srcdir` instead of `$startdir/../..`.

## Release tarball

```sh
node scripts/package-release.mjs [--output DIRECTORY]
```

It writes `pentad-<version>.tar.gz` and a `.sha256` file to `dist/release/` by default. The tarball contains the prebuilt `runtime/`, `scripts/pentad`, `packaging/install.sh`, the README and the licenses, so users install it with `packaging/install.sh` and no build tools. It is reproducible: file times come from the last commit, or from `SOURCE_DATE_EPOCH`. Publishing a release stays a maintainer decision.
