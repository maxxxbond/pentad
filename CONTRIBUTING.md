# Contributing to Pentad

Thank you for helping. Pick an open issue, or propose a focused improvement first: a visual fix, a documentation correction or a test scenario report is always useful.

## Reporting problems

Bugs and feature ideas go through the issue templates. Search existing issues first, and remove personal data, device identifiers and credentials from logs before posting. Report security vulnerabilities privately as described in [SECURITY](SECURITY.md), never in a public issue.

## Widget authors and designers

Pentad aims to make it practical to create a useful widget with a coherent visual language. Geist is the primary UI typeface; shared components provide geometry, interaction states and accessibility, and authors are free in composition, content and visualization within those rules. All widgets and menus follow the [shared popup interaction standard](docs/development/popups.md): clicks inside keep the window open, an outside press closes it immediately, and there are no hover-dismiss timers. See [controls](docs/development/controls.md) for the component contract.

Local experiments need no approval. The widget contract is experimental and not a stable public SDK; changes to it must update its contract documentation and compatibility notes together.

## Architecture and setup

Use [Quickshell development](docs/development/quickshell.md) for the runtime, build and live-reload workflow. Keep pure models, native adapters and views separate, use event subscriptions for service state, and give every subscription, timeout and window a clear lifetime. A missing battery is normal, an unknown percentage differs from zero, and a removed audio device invalidates its pending commands.

## Pull requests

1. Explain the user-visible behavior and keep the change focused.
2. Use shared components and semantic theme tokens; include screenshots for UI changes.
3. Cover relevant empty, error and recovery states.
4. Run the logic tests: `node --test tests/quickshell/*.test.mjs`. Run graphical scenarios only in an isolated, headless session (private compositor, D-Bus and temporary HOME/XDG directories), never against your live desktop.
5. State which checks you ran and which you could not; mark the latter as unverified.
6. Preserve upstream authorship and license notices for copied code and describe its source and local changes (see [third-party notices](docs/third-party)). Only copy code whose license is compatible with GPL-3.0-only.
7. User-visible text needs both a Ukrainian and an English string: `services.text("Українська", "English")` in QML, and the paired `labelUk`/`labelEn` fields in manifests and the settings catalog. The JSON files in `quickshell/catalogs/` are not loaded at runtime. Do not hard-code a language, locale, monitor name or personal path: defaults must work on any machine.
8. If an AI tool wrote part of the change, you remain responsible for it. Read it, run it, and be able to explain it in review.

## License and sign-off

Pentad is licensed under GPL-3.0-only ([LICENSE](LICENSE)). By contributing you agree that your contribution is licensed under the same terms, and you keep your own copyright. There is no copyright assignment or CLA.

Sign every commit with the [Developer Certificate of Origin](https://developercertificate.org/): add `Signed-off-by: Your Name <you@example.com>` with `git commit -s`. It states that you wrote the change or otherwise have the right to submit it under this license. Pull requests with unsigned commits will be asked to add the sign-off. Use a name you are comfortable having in the public history. The requirement applies from the first public push of the repository; earlier commits, all by the founding maintainer, predate it and many carry no sign-off.

The Pentad name and logo are not covered by the GPL; see [TRADEMARK](TRADEMARK.md) before using them in a fork or a package.

The founding maintainer (maxxxbond) reviews contributions and has the final say on what is merged. Funding does not grant extra merge or governance rights.
