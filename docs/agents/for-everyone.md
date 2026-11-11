# Building for other people and publishing

Pentad is developed on one machine but made for many. Read this before any change to defaults, dependencies, user data, network access, licensing or the widget API, and before any commit, release or publication step. The short version is in [AGENTS.md](../../AGENTS.md#building-for-other-people).

## Who we build for

- **Users** on Arch or EndeavourOS with Hyprland, on hardware we have never seen: one monitor or four, scale 1 to 2, laptop or desktop, no battery, no brightness control, no Tailscale, a different language and locale, a light theme, reduced motion.
- **Widget authors** who build on the widget API and the shared components, and who need it to keep working after they publish.
- **Packagers** who install Pentad into `/usr` and need accurate dependencies.
- **Reviewers and contributors** who read the code and history without the conversation that produced it.

The maintainer's taste sets the design direction. The maintainer's machine never sets the defaults.

## Portability

- Never hard-code a monitor name, output layout, user name, home path, locale, language, keyboard layout, installed application or wallpaper. Use XDG base directories, the compositor's actual outputs and the config documents.
- Every external program is optional until the README and packaging say otherwise. Check that it exists, degrade gracefully when it does not, and say what is missing behind an info button or tooltip. Never crash, spin or spam the log.
- Hardware absence is normal: no battery, no backlight, no microphone, no network. An unknown value differs from zero. A device removed while in use cancels its pending commands.
- Defaults must work on a clean install with an empty `$XDG_CONFIG_HOME/pentad`. If a feature needs setup, the empty state explains it in one line and offers the action.
- Test at another scale and in the other language whenever you change layout. Text grows longer in Ukrainian; layouts must not clip or overlap.

## User data and compatibility

- Config documents (`$XDG_CONFIG_HOME/pentad/*.json`) and state (`$XDG_STATE_HOME/pentad`) belong to the user. A new version must read documents written by older versions. When a format changes, add parsing for the old shape and a test for the migration. Never silently drop a user's setting.
- Write user files atomically, with the existing revision-checked store (`tools/pentad-files.py`), and never follow a symlink into a place the user did not choose.
- The widget API v1 is experimental, but external authors rely on it. A change updates `packages/widget-api/v1/` (schema, `contracts.d.ts`, README), the runtime validator, the example or template, and the compatibility notes, all in the same change. Removals and renames need a deprecation path, not a silent break.

## Accessibility and comfort

- Everything reachable by pointer is reachable by keyboard; Escape always backs out. Focus is visible for keyboard users only.
- Respect reduced motion. Animations communicate state; they never gate an action.
- Information is never carried by colour alone. Contrast holds in both themes.
- Use the four text roles and the shared components; they carry sizing, states and accessibility for free.

## Performance and battery

- Prefer event subscriptions to polling. When polling is unavoidable, use a bounded interval, at most one request in flight, a timeout, and stop when the surface is hidden.
- Hidden surfaces do no work. Loaders unload what is not shown. Timers and processes have owners.
- Do not add startup work to the bar for a feature the user has not placed.

## Privacy and security

Pentad runs with the user's privileges and is not a sandbox. [SECURITY.md](../../SECURITY.md) defines what matters; design so those reports never happen.

- **Untrusted input:** notification text, window titles, media metadata, clipboard and dropped content, file names, URLs, manifest and settings values. Never interpolate them into a shell string. Pass argument arrays to processes, validate paths, and escape rich text before display.
- **Network:** a request goes only where its feature needs, sends only what the feature needs, and its destination is documented in that feature's docs. No telemetry, analytics or update checks without an explicit decision by the maintainer.
- **Secrets:** API keys and tokens live behind `secret://` references, never in config defaults, logs, test fixtures, screenshots or commit messages.
- **Files:** temporary files go into a private `mkdtemp` directory and are removed. Caches respect size limits. The Stash and screenshots never leave the machine without a user action.
- **Widgets:** a widget may do only what its manifest declares. A bug that lets it exceed that is a security bug.

## Licensing and third-party material

- Pentad is GPL-3.0-only. Copy code, icons, fonts or data only under a compatible license. Keep the upstream copyright and license notice, add the license text to `LICENSES/` and a notice to `docs/third-party/`, and describe the source and your changes in the commit.
- Do not reproduce copyrighted code from memory. When you adapt an upstream project (Omarchy, Noctalia and others named in the README), cite the file and commit you adapted.
- The Pentad name and logo are covered by [TRADEMARK.md](../../TRADEMARK.md), not by the GPL. Do not put Pentad branding on third-party material or forks.

## Commits and history

Everything committed is public as soon as the repository is pushed, and it stays in history after deletion. Assume every commit will be read by strangers.

- Commit only when the user asks, or when the session's instructions say to. Never push, force-push, rewrite history, create tags or releases, or change repository visibility without an explicit instruction for that specific action.
- One logical change per commit. The subject is imperative, at most about 72 characters, optionally with a `type(scope):` prefix (`fix(media):`, `test:`, `style:`). The body explains the user-visible behaviour and why, not a file list.
- Sign off every commit with `git commit -s` (Developer Certificate of Origin, required by [CONTRIBUTING.md](../../CONTRIBUTING.md#license-and-sign-off)). Add the AI attribution trailer the tool provides (`Co-Authored-By: …`).
- Before committing, read the staged diff and check for secrets, tokens, personal paths (`/home/<name>`), e-mail addresses, device identifiers, real notification or chat content, and screenshots of a real desktop. Use fixture data instead.
- Never commit `dist/`, `artifacts/`, an `artifacts` symlink, `__pycache__`, editor files, or a gitignored local-only document.

## Pull requests and screenshots

- Follow `.github/PULL_REQUEST_TEMPLATE.md`: user-visible behaviour first, a focused change, checks run and checks left `unverified`.
- Screenshots and recordings come from the isolated headless fixtures with fixture data, never from the live desktop. Show both themes when the change is visual, and the other language when the layout depends on text.

## Documentation

- A user-visible change updates the matching page in `docs/development/` (or the widget API README) in the same change.
- Keep the README's requirements in step with what the code actually calls. A new runtime dependency goes into the README, `packaging/README`, the `FEATURES` table in `tools/pentad_doctor.py`, the PKGBUILD's `optdepends` (a test keeps those two in step), and the feature's docs.
- Write documentation in English, in plain and specific sentences, for someone who has never seen the conversation that produced the change.
