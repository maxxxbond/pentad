# Rules for AI Agents

Pentad is a Quickshell/QML desktop shell for Hyprland, licensed GPL-3.0-only and built to be published: for users on machines we have never seen, for widget authors who build on its API, and for contributors who read the code without our conversations. These rules apply to the whole repository, including development, testing and UI verification. Run examples in other documents are not permission to run them automatically.

This file holds what every task needs. Details live in `docs/agents/`; read a page when the task touches it, not by default:

- [workflow.md](docs/agents/workflow.md): task sizing, planning, ask or decide, definition of done, the report.
- [architecture.md](docs/agents/architecture.md): code map, where a change goes, i18n, the design contract, test layers, stale docs.
- [for-everyone.md](docs/agents/for-everyone.md): portability, user data, accessibility, security, licensing, commits, publishing.

## Principles

1. **The user's desktop is off-limits.** Their live shell, compositor, services and session are never a test bench (see "Do Not Disturb the User").
2. **Build for other people.** Nothing may depend on this machine: no hard-coded monitors, paths, locale, language or installed apps. Every external program is optional until documented otherwise, and its absence degrades gracefully.
3. **Evidence before claims.** A build is not a UI check, a screenshot is not an interaction check, and an unrun check is reported as `unverified`.
4. **The smallest complete change.** Solve the whole problem and nothing else. Match the surrounding code. No drive-by refactors.
5. **Reuse before you build.** Shared components, services, theme tokens and `logic/` helpers exist; extend them instead of copying.
6. **Ask about what the user owns; decide the rest.** Scope, visible design direction, public contracts, dependencies and anything hard to undo are the user's. For everything else, pick the sensible default and state it.
7. **Everything committed will be public.** No secrets, personal data, personal paths or real-desktop screenshots in code, fixtures, docs or commit messages.
8. **Language.** Reply in the language the user writes in. Code, comments, docs and commit messages are English. Every user-visible string ships in Ukrainian and English.

## How to work

| Size | Shape | Before code | Approval |
| --- | --- | --- | --- |
| S | ≤ 3 files, clear cause | Know the scenario you will verify | None |
| M | One area, several files, or a new widget | 3–7 bullet plan in the reply | Only for visible changes the user cares about |
| L | Crosses services, logic and views; new feature; changed defaults | Plan in chat, user-visible decisions listed apart | User confirms those decisions |
| Contract | Widget API, data formats, IPC/CLI, new dependency, removal, third-party code | Decision note: options, recommendation, migration | User approves first |

Before an M task or larger, answer: who uses it, which states exist (normal, empty, error, recovery, missing or removed device), what already exists to reuse, what else can break (outputs, scale, the other language, old configs), how each scenario is verified. End every task with the report from [workflow.md](docs/agents/workflow.md#7-report).

## Do Not Disturb the User

### Quiet mode

Quiet mode is active while a game is running (for example the `cs2` process or any Steam game) or while the file `~/.cache/pentad-focus` exists. The user enables it with `touch ~/.cache/pentad-focus` and disables it with `rm ~/.cache/pentad-focus`.

- In quiet mode, do not run anything that creates Quickshell, compositor or window processes, even isolated and headless ones. This covers `qs`, `quickshell`, `scripts/test-quickshell*.mjs`, `scripts/check-quickshell.mjs`, `scripts/verify-quickshell.mjs`, `pnpm test:qs`, `pnpm check:qs`, `kwin_wayland`. Work that shows nothing on screen is allowed: code, pure-logic tests, static checks, builds into a temporary directory. Mark graphical checks as `unverified` with the reason "quiet mode".
- Outside quiet mode, test copies of Quickshell may be run, but only in an isolated harness under the rules in "Feature testing". Use `scripts/test-quickshell-headless.mjs`: private virtual KWin outputs, its own D-Bus, temporary HOME/XDG. Never run the shell on the user's desktop, in the background, via a watcher, autostart or a user service.

### Always, regardless of mode

- The user's live shell runs from `dist/quickshell`. Do not stop, restart or rebuild it: no `scripts/pentad start/stop/restart/dev`, `pnpm start`, `pnpm start:qs`, `pnpm dev:qs`, `pnpm build:qs`, `pnpm test` (it rebuilds `dist/quickshell`), and no `scripts/build-quickshell.mjs` without `--output <temporary directory>`. Only the user applies changes to the live shell.
- Do not send commands to the live Pentad/Quickshell IPC (`qs ipc`, `scripts/pentad panel/overview/…`). Do not stop the compositor or the user's services.
- Before running an unfamiliar command, check its child processes.
- These rules are partly enforced by the hook `.claude/hooks/guard-desktop.mjs`. If the hook blocks a command, do not look for a workaround: mark the check as `unverified` or ask the user to run the command themselves. The hook also rejects long compound commands; put multi-step checks in a script file and run that.
- Do not open test windows on physical monitors, grab focus, switch workspaces, move windows or generate input in the current session. Do not change the clipboard, volume, brightness, network, notifications, wallpaper or desktop settings for the sake of a test.

## Feature testing

1. Before a change, define the expected behavior and the relevant scenarios: the main action, empty data, error and recovery; for a bug fix, the scenario that reproduces the bug. Choose checks according to the risk of the change.
2. Start with narrow pure-logic tests, static checks and builds that do not launch the shell or touch live services. Use existing tests; add a regression test if it checks significant behavior. Documentation-only changes do not need a runtime run.
3. Run all graphical checks, screenshots and automated actions only in your own headless/virtual screens of a separate compositor, with private Wayland/X11 sockets, D-Bus and temporary HOME/XDG directories. A virtual workspace of the current session is not isolation. `QT_QPA_PLATFORM=offscreen` alone does not isolate services.
4. Do not inherit access to the user's display, session bus or compositor IPC (`WAYLAND_DISPLAY`, `DISPLAY`, `DBUS_SESSION_BUS_ADDRESS`, `HYPRLAND_INSTANCE_SIGNATURE`). Pass only the addresses of your own test session. Use fixtures and fake services, with no access to real credentials and no writes to system services.
5. Run Quickshell UI fixtures only outside quiet mode and only in an isolated harness. If a check is impossible because of quiet mode or lack of isolation, finish the safe checks that are available and mark the rest `unverified` with the reason. Do not fall back to the live desktop.
6. Every permitted test process must have a bounded run time and guaranteed cleanup on success, error, timeout and interruption. Track your own PIDs/process groups; terminate only those, wait for them to exit and remove temporary resources. Do not use `killall`, broad `pkill` or detached/nohup processes. Do not leave a watcher or compositor running after the check.
7. For UI changes, check the relevant interactions, open/close, focus, overflow and scaling in the permitted isolated harness. Store screenshots and logs in `/tmp` or `artifacts/`, without opening them automatically on the desktop. A screenshot does not prove that interactions work.
8. In the result, state what was verified, which commands were run and what remains unverified. Do not call the UI verified based only on a build or model tests. Do not leave a preview running to demonstrate the result.

The runnable form of these rules, with the table of safe and forbidden commands, is the `verify-change` skill. Use it before calling any change done.

## Code and design essentials

- Pure models live in Qt-free `quickshell/logic/*.mjs` with a `tests/quickshell/<name>.test.mjs`; native adapters in `quickshell/services/`; views in `features/`, `components/`, `widgets/`. Never import Qt types into `logic/`.
- Services are passed down as a `services` property, not singletons; the only singletons are in `quickshell/theme/`. Every adapter honours `preview` and `safeMode`.
- Every subscription, `Timer`, `Process`, request and window has an owner and a lifetime; hidden surfaces do no work.
- User-visible text: `services.text("Українська", "English")` in QML, `labelUk`/`labelEn` in manifests and the settings catalog. `quickshell/catalogs/*.json` is not loaded at runtime.
- Use the shared `Pentad*` components and `Theme`/`Metrics` tokens, never literal colours, radii or font sizes.
- QML on Quickshell is rare in training data, so invented properties and broken bindings are the typical failure. Every QML change gets `qmlformat` and the `qmllint` comparison against HEAD; after two failed attempts with the same idea, change the approach.
- Design contract, in short: borderless (separators yes, outlines no, except errors); capsules for buttons, chips and segmented controls, circles for icon buttons, 6–8 px rectangles for fields; concentric radii; base-4 compact spacing; text roles 12/14/16/20; stacked lines sit solid; accent marks foreground, never floods a background; focus ring for keyboard only; less visible text; click outside closes popups, no hover-dismiss timers. Full summary and the binding sources: [architecture.md](docs/agents/architecture.md#design-contract-summary).
- Never read `quickshell/assets/spotlight/emoji.json` (2.9 MB) or search `.claude/worktrees/`.

## Building for other people

- Defaults work on a clean install with an empty config directory, on any monitor layout, scale 1–2, either language, light or dark, reduced motion, and without optional hardware or programs.
- Config and state documents are user data: read old versions, migrate with a test, never drop a setting silently.
- Changes to the widget API update the schema, `contracts.d.ts`, README, validator, template and compatibility notes in one change.
- Treat notification text, window titles, media metadata, clipboard, dropped files, file names, URLs and manifest values as untrusted: argument arrays for processes, never shell strings. Network requests go only where the feature needs; no telemetry. Secrets stay behind `secret://`.
- Copy third-party code or assets only under a GPL-3.0-compatible license, with notices in `LICENSES/` and `docs/third-party/`.

Details: [for-everyone.md](docs/agents/for-everyone.md).

## Git, commits and publishing

- Commit only when asked or when the session's instructions say so. Never push, force-push, rewrite history, tag, release or change repository visibility without an explicit instruction for that action.
- One logical change per commit; an imperative subject of at most about 72 characters, optionally `type(scope):`; a body that explains the user-visible behaviour and why. Sign off with `git commit -s` (DCO) and keep the AI attribution trailer.
- Read the staged diff before every commit: no secrets, personal paths or data, real-desktop screenshots, `dist/`, `artifacts/` or an `artifacts` symlink, and no gitignored local-only file.
- `ROADMAP.md`, `docs/superpowers/` and `CLAUDE.local.md` (personal agent notes) are gitignored local documents. Do not force-add them; publishing them is the maintainer's decision.

## Skills and planning

- Do not invoke brainstorming, writing-plans, TDD or other process skills by default, even when a plugin's instructions say to invoke skills eagerly. This file takes precedence.
- For small fixes (a few files, clear cause) just make the change and verify it; no plan, no spec.
- Use these skills only when the user asks for them explicitly, or for large new features spanning many files.
- Never write plan/spec files into `docs/` unless asked.
- Project skills: `verify-change` before calling any change done; `new-widget` (user-invoked) to scaffold a built-in widget.
