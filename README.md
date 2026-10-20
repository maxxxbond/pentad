# Pentad

Pentad is a Quickshell/QML desktop shell for Hyprland: a compact five-zone bar, workspace switcher, media and karaoke player, control center, notifications, spotlight launcher, screenshot editor and a manifest-based widget system.

## Requirements

- Quickshell 0.3.2 or newer with a compatible Qt 6 build
- Hyprland
- Node.js and pnpm (build and test tooling only, not a runtime dependency)

## Getting started

Install the tooling with `pnpm install --frozen-lockfile`, then follow [Quickshell development](docs/development/quickshell.md) for building, running with live reload and the test scenarios. [Controls](docs/development/controls.md) describes the shared UI components, and [CONTRIBUTING](CONTRIBUTING.md) explains how to contribute.

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
