# Quickshell development


Pentad's Quickshell runtime targets Quickshell 0.3.2 or newer and a compatible Qt package cohort. Node.js is used only for build, environment checks, and fixtures; it is not part of the installed shell runtime. The runtime tree is assembled at `dist/quickshell` and contains the QML source, assets, translation catalogs, and defaults needed after installation.

Reusable controls, interaction bindings, attached popovers and declarative menu placements are documented in [controls.md](controls.md).

## Live development

From this repository, run `pnpm dev:qs` (or `scripts/pentad dev`). It selects the local Quickshell 0.3.2 binary when available, builds the current source, and starts Pentad. Saving files in `quickshell/`, `tools/`, or `LICENSES/` automatically builds and restarts Pentad after a 250 ms debounce. Builds run in a separate staging directory; a failed build leaves the running shell intact. Multiple saves during a build are queued for the next build. Runtime errors and shell logs appear in the same terminal; fixing the source and saving retries the launch.

The watcher selects instances by the exact `dist/quickshell/shell.qml` config path, stops them by instance ID, and waits for their processes to exit before replacing the runtime. Other Quickshell configs keep running. Only one development watcher can own this tree at a time.

Press Enter or type `r` followed by Enter to rebuild manually. Ctrl+C stops the watcher and its Pentad child. `pnpm dev:qs --safe-mode` disables native writes for inspection. `--qs /absolute/path/to/qs` selects another runtime >= 0.3.2.

For manual control:

```sh
scripts/pentad status --development
scripts/pentad logs --development
scripts/pentad stop --development
scripts/pentad restart --development
```

Development restart stages a fresh build and starts Pentad in the foreground without watching. While `dev:qs` is running, use Enter in its terminal instead. Installed configs support the same lifecycle commands with `--path INSTALL_ROOT` or the default installed path.

## Build and environment check

Build the self-contained QML tree with:

```sh
node scripts/build-quickshell.mjs
node scripts/check-quickshell.mjs
```

The build copies the local `quickshell/` tree, including assets, JSON catalogs, and defaults, plus the bounded filesystem helpers into `dist/quickshell`. It includes root `LICENSE` and `LICENSES/`. `builtin-registry.json` is generated deterministically from every `quickshell/widgets/**/manifest.json`; the build prints how many built-in widgets it found. Symlinks are omitted. The build needs no legacy checkout and never fetches upstream sources.

The environment check reads `qs --version`, Qt metadata, and the cohort's `qmllint`, then asks Quickshell itself to load the required modules in a short offscreen probe. It rejects versions below 0.3.2 before launching that probe. Importing the Notifications module does not create a notification server or request its D-Bus name. A live IPC availability probe is opt-in with `node scripts/check-quickshell.mjs --native`; it contacts the current Quickshell IPC endpoint and does not create or modify system configuration.

The report includes the installed Quickshell revision and the visible Qt package cohort. Quickshell 0.2.1 is rejected because it is below the 0.3.2 floor. The observed package cohort is environment evidence, not a portable Qt ABI guarantee.

## Run the shell and CLI

```sh
scripts/pentad start --development
scripts/pentad start --development --safe-mode
scripts/pentad start --path "/absolute/path/to/quickshell install"
scripts/pentad ping --development
scripts/pentad panel activity toggle --development
scripts/pentad panel right toggle --development
scripts/pentad workspace-super Super_L press --development
scripts/pentad workspace-super Super_L release --development
scripts/pentad ping --path "/absolute/path/to/quickshell install"
```

Without an option, the wrapper uses the runtime installed next to it, `PREFIX/share/pentad/quickshell` for a wrapper at `PREFIX/bin/pentad` (symlinks are followed), and falls back to `/usr/share/pentad/quickshell`. `doctor` reports required and optional dependencies without touching a running shell. `--path` selects that exact installation root and supports spaces. Development mode selects this repository's `dist/quickshell`. `start` checks the Quickshell 0.3.2 floor without Node.js and uses `--no-duplicate`. Safe mode gates native actions and writes. `panel <left|right|activity> <open|close|toggle>` selects a transient surface on the focused output. Workspace modifier requests are idempotent; `workspace-slot <1..9>` follows the existing ordinal routing and is denied in preview/safe mode. Rejected IPC responses and unknown arguments exit nonzero. The optional `defaults/hyprland-quickshell.lua` fragment shows modifier bindings; no running Hyprland config is rewritten.

## Fixture scenarios

```sh
node scripts/test-quickshell.mjs --scenario runtime --report /tmp/pentad-runtime.json
node scripts/test-quickshell.mjs --scenario output-lifecycle --report /tmp/pentad-output.json
node scripts/test-quickshell.mjs --scenario design-system --report /tmp/pentad-design.json
pnpm run test:qs -- --scenario bar --report /tmp/pentad-bar.json
pnpm run test:qs -- --scenario media --report /tmp/pentad-media.json
pnpm run test:qs -- --scenario popups --report /tmp/pentad-popups.json
pnpm run test:qs -- --scenario window-navigation --report /tmp/pentad-window-navigation.json
pnpm run test:qs -- --scenario spotlight --report /tmp/pentad-spotlight.json
```

The runner accepts only registered scenarios, checks the Quickshell 0.3.2 floor, rejects missing fixtures, and starts the matching `quickshell/tests/<scenario>.qml`. Each run gets private temporary XDG config, data, state, and cache directories, a sanitized child environment (preview and safe mode enabled), and a hard 30-second timeout. It finds `PENTAD_TEST <json>` anywhere in each log line and requires event status `pass` plus `checks[].passed === true`; missing checks cannot pass. It writes a JSON report with `pass`, `fail`, or `blocked` status, environment facts, checks, and any captured log path. A blocked or failed run exits nonzero. Missing fixture, display, imports, version, or process launch cannot be reported as a pass.

The active Wayland socket is required for a graphical run. The runner passes its absolute socket path while keeping `XDG_RUNTIME_DIR` inside the disposable directory, omits the session D-Bus address, sets `HOME` to the temporary directory, and does not inherit arbitrary environment variables. QML fixtures must use fake services and must not instantiate the Notifications server, change audio/network state, or access chat credentials. Live native integration checks require a separately explicit `--native` probe; the fixture runner has no native mode.

### README images

`node scripts/readme-images.mjs` renders the `showcase` fixture in the isolated headless session and writes `docs/assets/readme/hero.png` and `media.png` with ImageMagick. The fixture composes the real bar, control center and music menu over a generated wallpaper with invented data. Images in the repository never come from a real desktop.

## Local Quickshell runtime

Pentad needs Quickshell 0.3.2 or newer, which many distributions do not package yet. If your system `qs` is older, build a pinned revision into the gitignored `artifacts/quickshell-runtime/` directory. `scripts/pentad ... --development` selects `artifacts/quickshell-runtime/bin/qs` automatically when it is executable, for both startup and IPC; otherwise it uses `qs` from `PATH`. Installed and explicit `--path` launches keep using `PATH`. Standalone checks and fixtures need `PATH="$PWD/artifacts/quickshell-runtime/bin:$PATH"`. This build survives temporary-directory cleanup; rebuild it after an incompatible Qt update or if the artifacts directory is removed.

Preview from the repository root:

```sh
pnpm run build:qs
PENTAD_PREVIEW=1 scripts/pentad start --development --safe-mode
```

Stop the foreground preview with Ctrl+C. To create the local runtime with CMake, Ninja, a C++ compiler and the Quickshell build dependencies:

```sh
mkdir -p artifacts/quickshell-runtime/source artifacts/quickshell-runtime/bin
curl --fail --location https://github.com/quickshell-mirror/quickshell/archive/4f508be500dea6e5732cc3d50382a0048b17e7b1.tar.gz -o artifacts/quickshell-runtime/source.tar.gz
tar -xzf artifacts/quickshell-runtime/source.tar.gz -C artifacts/quickshell-runtime/source --strip-components=1
cmake -S artifacts/quickshell-runtime/source -B artifacts/quickshell-runtime/build -G Ninja -DCMAKE_BUILD_TYPE=Release -DDISTRIBUTOR=Pentad-local-preview -DGIT_REVISION=4f508be500dea6e5732cc3d50382a0048b17e7b1
cmake --build artifacts/quickshell-runtime/build -j6
ln -sfn ../build/src/quickshell artifacts/quickshell-runtime/bin/qs
```

Weather is a tool in the **left menu**. Its **Choose city / Change city** control opens location search in place. Enter at least two characters and choose a city; the existing layout-save flow stores its name, region, country, coordinates and time zone together. Temperature units and manual coordinates remain available in the generic widget settings form. Search uses a 300 ms debounce, at most five validated Open-Meteo results, and the existing bounded HTTPS transport. Changing the query or closing search cancels the lookup. Provider requests are disabled in preview/safe mode; the sidebar fixture supplies synthetic geocoding and forecasts and makes no network requests. Live provider access and localization remain separate acceptance gates.

Additional scenarios: `design-system` captures a PNG beside the JSON report and accepts `--appearance light`, `--scale 1.25`, `--accent '#56789a'`, and `--reduced-motion`; `plugin-host` checks shared media and controller lifecycle; `config-store` checks real helper operations in disposable XDG roots. These checks do not establish full bar/player parity.

`window-navigation` and `spotlight` currently exercise the migrated JavaScript logic in the actual QML engine with synthetic data. They cover MRU/recycled-window identities, game recognition, overview normalization/layout, launcher providers and stale query/action guards. Their passing reports do not establish a working launcher UI, Alt-Tab keyboard delivery, clipboard integration or live window focus/movement.

Run the consolidated Q02–Q07 acceptance suite with an explicit Quickshell binary:

```sh
pnpm run test:qs:integration -- --qs /path/to/qs --report-dir /private/path/quickshell-integration
```

The runner checks the 0.3.2 version floor before starting fixtures, builds the runtime, runs the migration baseline, Node and Python helper tests, all registered runtime scenarios, and native network, NetworkManager health, power, audio, desktop, brightness, lyrics, visualizer, MPRIS, and IPC checks. Native writes use fake backends/utilities or private D-Bus players. It uses a private temporary command alias so every fixture resolves the selected `--qs` binary without changing the installed system command. Reports default to a timestamped directory under `artifacts/migration/integration-final/`; report directories and files use owner-only permissions. The optional `--actual` flag lets only the visualizer fixture use the real CAVA executable; the default uses its fake producer. Each scenario retains its JSON report, captured output, command exit status, and result checks. Missing fixtures, missing checks, runtime errors, and failed assertions prevent an overall pass.

The consolidated runner resolves the actual installed Geist before isolating HOME, stages that font into its private XDG data directory, and uses private fontconfig cache/config paths. Each visual fixture then copies it into its own temporary XDG font directory and checks `Qt.fontFamilies()` before passing; no font is bundled into the release by this workflow. Font fallback remains visible as a failed gallery check. The bar report includes both the primary capture and the native telemetry popup capture.

Read-only hardware sampling is separate from the fake acceptance suite:

```sh
node tests/tooling/hardware-readonly.mjs --qs /path/to/qs --report /private/path/hardware-readonly.json
```

This probe reads the real Network, Audio, Power, and Desktop adapters with safe mode enabled and private HOME/XDG config/data/state/cache directories. It retains only availability, counts, profile, and aggregate/per-card telemetry; it omits network names and application metadata. It performs no setters or daemon restarts. Optional battery/sensor absence is reported as absence. A passing sample does not establish real command, hotplug, reconnect, or compositor-input acceptance.

NetworkManager ownership is observed through bounded read-only `busctl` probes because Quickshell 0.3.2 has no dynamic backend-readiness signal. Runtime loss/recovery is supported when the native NetworkManager backend existed at shell startup. If `Networking.backend` was `None` at startup, Quickshell 0.3.2 cannot recreate it; a shell restart is required.

`bar` captures wide and compact layouts and verifies physical island centering. `media` checks synchronized source selection, independent placement preferences, karaoke overhang, and producer release when hidden; its audio frames and tracks are synthetic. `popups` checks actual Wayland popup lifecycle. `node tests/tooling/media-native.mjs --qs artifacts/quickshell-runtime/bin/qs --report /tmp/pentad-media-native.json` separately runs GJS test players on a private `dbus-run-session` bus and verifies commands, capabilities, seek guards, and source disappearance/reappearance. GJS belongs to this development fixture, not the installed runtime.

Lyrics lookups use bounded `curl` requests (12-second deadline, 1 MiB body limit, 64-entry cache, and ten-minute HTTP 429 backoff). CAVA is optional and shared by visible, playing consumers; missing audio analysis is unavailable rather than simulated.

### Live telemetry refresh regression

`node scripts/test-quickshell.mjs --scenario telemetry-live --report /tmp/pentad-telemetry-live.json`
reads actual Linux procfs/DRM in safe mode and verifies three refreshes within
three seconds without transiently missing telemetry. The shared sampler polls every
1000 ms, keeps the previous complete snapshot while reading, and publishes only
after both procfs and DRM settle. An unfinished read is never restarted by the
next poll; disabling telemetry cancels it. It performs no hardware setters. Use the local
0.3.2 runtime on PATH as above. The `bar-visual` fixture separately uses synthetic
data to check retained indicator objects, updated sectors/labels and integral
status-icon scene coordinates; it does not prove physical-seat interaction.

`node scripts/test-quickshell-headless.mjs --scenario telemetry-motion --report /tmp/pentad-telemetry-motion.json`
checks rendered frames during repeated 250 ms updates: GPU slots and bar discs
retain identity, arcs interpolate from the previous value without clearing, and
reduced motion updates directly. Both popup rings and masked bar sectors use
native Qt Quick Shapes with 240 ms transitions, rather than repainting Canvas
textures. GPU models contain a stable slot count, not the changing sample array.
The `desktop-native` fixture additionally checks five complete GPU snapshots,
including reads slower than a simulated 250 ms polling interval, and cancellation on disable.
