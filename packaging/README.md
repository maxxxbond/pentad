# Installing Pentad

Build the Quickshell runtime first with `pnpm run build:qs`, then install with
`sudo packaging/install.sh`. Package builders can stage the same layout by
setting `DESTDIR` and `PREFIX`, for example:

```sh
DESTDIR="$pkgdir" PREFIX=/usr packaging/install.sh
```

The install tree includes `/usr/bin/pentad`, the Quickshell runtime under
`/usr/share/pentad/quickshell`, and the wallpaper helper under
`/usr/lib/pentad/tools/`. Python 3 and Quickshell 0.3.2 or newer are required
runtime dependencies, including the Qt 5 Compatibility graphical effects QML
module (`qt5compat` on Arch) for telemetry's alpha mask. ImageMagick is optional; install it to enable
`pentad recolor-wallpaper` and the "Theme colors" wallpaper tint.

Pentad draws the wallpaper itself on the background layer once one is chosen in
Settings → Wallpaper; until then it draws nothing there. Stop any other wallpaper
daemon or shell background, or it will cover Pentad's. Bind keys to
`pentad wallpaper random|next|previous` or `pentad wallpaper set <file>`.

The native screenshot editor uses `grim`, `wl-copy` (wl-clipboard), and Python
Pycairo (`python-cairo` on Arch). `xdg-user-dir` is used when available to find
the Pictures folder. No external annotation application is required. Right-click
the screenshot button to configure shortcuts and export a Hyprland Lua fragment;
the fragment is not activated automatically.
