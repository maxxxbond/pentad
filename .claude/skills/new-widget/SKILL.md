---
name: new-widget
description: Use when the user asks to create, add or scaffold a new built-in Pentad Quickshell widget under quickshell/widgets.
disable-model-invocation: true
argument-hint: <name> <slot> ["English title" "Українська назва"]
---

# Scaffolding a built-in Pentad widget

## Overview

A built-in widget is a directory in `quickshell/widgets/<name>/`. `scripts/build-quickshell.mjs` finds every `manifest.json` there, validates it with `quickshell/logic/plugin-manifest.mjs` and writes `builtin-registry.json`. No other registration is needed. Logic stays in a Qt-free `.mjs` module so `node:test` can cover it.

Arguments: `$ARGUMENTS`. Ask only for values that are missing. `name` must match `^[a-z][a-z0-9]*(-[a-z0-9]+)*$` and must not already exist in `quickshell/widgets/`. `slot` is one of `navigation telemetry center tools system sidebar-left sidebar-right`.

## Files to create

Templates are in this skill's `templates/` directory. Replace `__NAME__`, `__SLOT__`, `__TITLE_EN__`, and `__LOGIC__` (PascalCase name + `Logic`, e.g. `CounterLogic`).

| Template | Destination |
|---|---|
| `manifest.json` | `quickshell/widgets/<name>/manifest.json` |
| `View.qml` | `quickshell/widgets/<name>/View.qml` |
| `Controller.qml` | `quickshell/widgets/<name>/Controller.qml` |
| `logic.mjs` | `quickshell/logic/<name>.mjs` |
| `logic.test.mjs` | `tests/quickshell/<name>.test.mjs` |

Adjust the templates to the request:
- **No state or services** → drop `Controller.qml`, the `"controller"` key and the `controller` property's `required` (use `property var controller: null`, as in `widgets/qr/View.qml`).
- **Sidebar tool that accepts input** → add a `"tool"` block and an `acceptInput(items, choice)` function; follow `widgets/qr/` (manifest and View) and `logic/tool-catalog.mjs`.
- **Settings** → every `defaults` key needs a `settingsFields` entry (`kind`: text, integer, number, boolean, select, color). Keys that look like password/token/api-key must default to `""` or a `secret://` reference.

## Text and translations

- In QML, write visible strings as `root.tr('Українська', 'English')`; it delegates to `services.text(uk, en)`.
- Add `"widget.<name>.title"` to **both** `quickshell/catalogs/en.json` and `uk.json`, next to the other `widget.*.title` keys. The two catalogs must keep identical key sets.
- If the Ukrainian title isn't given, ask for it. Don't guess translations silently.

## Default placement (only on request)

A widget appears for users only after it's placed. Add a default placement only if the user asks. The entry goes in `defaults.layout.widgets` in `quickshell/logic/config.mjs`, for example `{ instanceId: '<name>-main', moduleId: 'pentad.<name>', slot: '<slot>', enabled: true, settings: {} }`. Then update the `config.test.mjs` expectations that list default placements.

## Done when

1. `timeout 60 node --test tests/quickshell/<name>.test.mjs` passes.
2. `timeout 60 node scripts/build-quickshell.mjs --output <scratch dir>` reports one more built-in widget than before. Never build into `dist/`: the user's live shell runs from there.
3. `qmlformat` exits 0 for each new `.qml` file.
4. Finish with the verify-change skill. It decides whether rendering can be checked in the isolated harness (not in quiet mode) or stays `unverified`.

## Common mistakes

- Id/directory mismatch: the id is `pentad.<name>` and the directory is `<name>`.
- Importing Qt types into `logic/<name>.mjs`. That breaks `node:test`.
- A `defaults` key without a matching `settingsFields` entry. The validator rejects it.
- Running `pnpm build:qs` or `pnpm test` to check the widget. Both rewrite the live `dist/quickshell`.
