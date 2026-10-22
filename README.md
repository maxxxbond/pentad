# Pentad

Pentad is a Quickshell/QML desktop shell for Hyprland: a compact five-zone bar, workspace switcher, media and karaoke player, control center, notifications, spotlight launcher, screenshot editor and a manifest-based widget system.

## Install

Pentad needs Hyprland, Quickshell 0.3.2 or newer with the Qt 5 Compatibility and Qt SVG modules, and Python 3. Everything else is optional: a missing program only turns off the feature that uses it.

Choose one way:

- **Arch Linux**, from a clone of this repository: `cd packaging/arch && makepkg -si`. It pulls in the required packages and lists the optional ones.
- **Release tarball**, with no build tools: unpack `pentad-<version>.tar.gz`, enter the directory and run `packaging/install.sh`.
- **From source** on any distribution: run `packaging/install.sh` in a clone. It needs Node.js while installing, but not pnpm.

`packaging/install.sh` installs into `~/.local` without sudo; with `sudo` it installs into `/usr/local`, and `--prefix DIR` picks another place. If `~/.local/bin` is not in your `PATH`, the installer tells you how to add it.

Then:

1. Run `pentad doctor`. It shows what Pentad found, which features a missing program turns off, and on Arch the `pacman` command that installs the rest.
2. Start Pentad with Hyprland. In `hyprland.lua`:

   ```lua
   hl.on("hyprland.start", function () hl.exec_cmd("pentad start") end)
   ```

   or in `hyprland.conf`: `exec-once = pentad start`. Pentad shows notifications and draws the wallpaper itself, so remove other notification and wallpaper daemons (mako, dunst, hyprpaper, swaybg) from autostart.
3. Copy the key bindings you want from `share/pentad/quickshell/defaults/hyprland-quickshell.lua` in the install prefix: a bare Super tap or Super+Space for search, Super+Tab for the overview and Alt+Tab for the window switcher.

To update, run `pentad stop`, install the new version the same way, then `pentad start`. To remove Pentad, run `packaging/install.sh --uninstall` (with the same prefix) or `sudo pacman -R pentad-git`. Your settings stay in `~/.config/pentad`.

Packagers: see [packaging](packaging/README.md) for the install layout and the full dependency list.

## Development

Building and testing need Node.js 24 and pnpm; neither is a runtime dependency. Install the tooling with `pnpm install --frozen-lockfile`, then follow [Quickshell development](docs/development/quickshell.md) for building, running with live reload and the test scenarios. [Controls](docs/development/controls.md) describes the shared UI components, and [CONTRIBUTING](CONTRIBUTING.md) explains how to contribute.

## References and inspiration

Pentad is an independent project. These designs and projects shaped its look and ideas:

- [Material Design 3](https://m3.material.io) for color roles, shape and motion principles
- [Nothing OS](https://nothing.tech) for its restrained, monochrome visual language
- macOS for the menu bar, Spotlight and overall interaction polish
- [end-4/dots-hyprland](https://github.com/end-4/dots-hyprland) for Quickshell shell ideas, including window selection in the screenshot tool
- [Noctalia](https://docs.noctalia.dev) for declarative extension manifests and settings

## License

Copyright (C) 2026 maxxxbond and Pentad contributors.

Pentad is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License, version 3 only. It is distributed without any warranty.

See [LICENSE](LICENSE) (GPL-3.0-only). Report vulnerabilities privately as described in [SECURITY](SECURITY.md). Third-party notices are in [LICENSES](LICENSES) and [docs/third-party](docs/third-party). The Pentad name and marks are covered by [TRADEMARK](TRADEMARK.md).
