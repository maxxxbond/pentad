# DankMaterialShell wallpaper transitions

Source: https://github.com/AvengeMedia/DankMaterialShell, commit `e978bae02d8566228c8b064da3dec33f157a1309`, files `quickshell/Shaders/frag/wp_wipe.frag`, `wp_disc.frag`, `wp_pixelate.frag` and `wp_iris_bloom.frag`.
Copyright (c) 2025 Avenge Media LLC, MIT. License: `LICENSES/dankmaterialshell-MIT.txt`. DankMaterialShell credits its wallpaper effects to Ly-sec and [Noctalia](https://github.com/noctalia-dev/noctalia-shell).

Pentad adapts the effect maths of these four fragment shaders for its wallpaper transitions: `quickshell/assets/shaders/wallpaper-wipe.frag`, `wallpaper-disc.frag`, `wallpaper-pixelate.frag` and `wallpaper-iris.frag`, compiled to the `.frag.qsb` files next to them with `node scripts/build-shaders.mjs`. Each source names its origin in a header comment. No QML from DankMaterialShell is used; `shell/WallpaperWindow.qml` drives the shaders itself.

Changes: removed the fill-mode sampling (Pentad's image layers already fill the screen, so the shaders sample screen-sized textures directly), replaced the smoothness, screen-size and image-size uniforms with fixed edge widths and an `aspect` uniform, reworked the radius and edge ranges so the first and last frames need no special cases, gave the wipe one formula for all four sides, fixed the iris to the screen's centre, and renamed the uniforms and samplers to Pentad's conventions.
