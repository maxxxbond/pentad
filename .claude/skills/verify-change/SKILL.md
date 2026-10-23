---
name: verify-change
description: Use when a Pentad change (QML, logic .mjs, Python helpers, scripts, widget manifests) is about to be called done, fixed, passing or ready to commit, or when asked to verify, test or check a change in this repository.
---

# Verifying a Pentad change

## Overview

AGENTS.md section "Feature testing" is the contract; this skill is the runnable form of it. The user's live shell runs from `dist/quickshell` (`scripts/pentad --development`), so a command that rebuilds `dist/` or starts `qs` changes their desktop. Safe checks run first, then the report states what remains `unverified`.

**Violating the letter of these rules is violating their spirit.**

## Command safety

| Command | Status | Why |
|---|---|---|
| `timeout 120 node --test tests/quickshell/*.test.mjs` | SAFE | Pure logic, plus isolated QtQml harnesses (no `qs`) |
| `timeout 120 node --test tests/tooling/dev-quickshell.test.mjs tests/tooling/verify-quickshell.test.mjs tests/tooling/shelf-content.test.mjs tests/tooling/hardware-readonly.test.mjs tests/tooling/qml-recursion.test.mjs` | SAFE | Fake `qs`, temp roots or static scans. Not `tests/tooling/quickshell.test.mjs` as a whole: one test starts the fixture runner with your environment (its build test alone, `--test-name-pattern='self-contained runtime tree'`, builds into scratch and is safe) |
| `timeout 300 node --test tests/tooling/package-release.test.mjs` | SAFE | Builds the release tarball into temp dirs and installs it without Node |
| `timeout 120 python3 -m unittest discover -s tests/files -q` | SAFE | Config store and lyrics cache; run from repo root (no pytest installed) |
| `timeout 300 python3 -m unittest discover -s tests/tools -p 'test_*.py' -q` | SAFE | For `tools/*.py` changes: file tool (real qpdf/ImageMagick/ffmpeg on temp files), screenshot, pickers |
| `timeout 120 python3 -m unittest discover -s tests/tooling -p 'test_*.py' -q` | SAFE | Packaging (`install.sh` builds into a temp dir and installs into temp prefixes with a stub `qs`), `pentad doctor`, wallpaper recolour, spotlight |
| `timeout 25 /usr/lib/qt6/bin/qmllint <file>` / `qmlformat <file> >/dev/null` | SAFE | Static |
| `timeout 60 node scripts/build-quickshell.mjs --output "$SCRATCH/qs-build"` | SAFE | Build into scratch, never `dist/` |
| `timeout 300 node scripts/test-quickshell-headless.mjs …` | NOT IN QUIET MODE | Isolated KWin/D-Bus/HOME. Fine when no game runs and `~/.cache/pentad-focus` is absent |
| `pnpm test`, `pnpm build:qs`, `node scripts/build-quickshell.mjs` (no `--output`) | USER RUNS IT | Rewrites the live `dist/quickshell`. The user applies changes to the live shell themselves |
| `pnpm dev:qs/start:qs/start`, `scripts/pentad start/stop/restart/dev/panel/…`, `qs ipc`, `qs kill`, `scripts/test-quickshell.mjs` (non-headless), `qs` on the real desktop | FORBIDDEN | Touches the live shell or the user's desktop |

`$SCRATCH` is the session scratchpad directory or a `mktemp -d` you remove afterwards. Every command gets a `timeout`.

The hook `.claude/hooks/guard-desktop.mjs` enforces most of this table. When it blocks a command, mark that check `unverified` with the hook's reason. Don't rephrase the command to get past it.

## Steps

1. **Scope.** `git status --short` and `git diff --stat`; list changed files by kind (QML, `quickshell/logic/*.mjs`, manifest, catalog, script, Python, docs).
   Docs-only change → no runtime checks; report that and stop.
2. **Scenarios.** Before running anything, write down: main action, empty data, error and recovery; for a bug fix, the reproduction. Each scenario maps to a test or ends up `unverified`.
3. **Logic tests.** Run the matching `tests/quickshell/<name>.test.mjs` for each changed `quickshell/logic/<name>.mjs`, then the full SAFE suites from the table. When a scenario has no test and is pure logic, add a regression test in the existing `node:test` + `assert/strict` style.
4. **QML static checks.** For each changed `.qml`: `qmlformat` must exit 0 (parse check). `qmllint` exits 0 even with warnings and baseline files already carry many `[unqualified]` warnings, so compare against HEAD. Lint the HEAD copy next to the file, not in `$SCRATCH`: a copy elsewhere loses its relative imports and reports a different count.
   ```sh
   base="$(dirname "$f")/.lint-base-$(basename "$f")"
   git show HEAD:"$f" > "$base" && timeout 25 /usr/lib/qt6/bin/qmllint "$base" 2>&1 | grep -c Warning; rm -f "$base"
   timeout 25 /usr/lib/qt6/bin/qmllint "$f" 2>&1 | grep -c Warning
   ```
   Report new warnings in the changed lines; ignore pre-existing noise. A new file has no HEAD copy; read its warnings and look for unresolved ids or properties you introduced. Lint never catches `name: name` (a property bound to itself, which leaves it `undefined`); grep new instances for that pattern.
5. **Text and manifests.** Every new user-visible string is a `services.text("Українська", "English")` pair or a `labelUk`/`labelEn` pair, with natural Ukrainian. `quickshell/catalogs/*.json` is not loaded at runtime; if it changed anyway, confirm `en.json` and `uk.json` have identical key sets. If a `manifest.json` changed, the scratch build in step 6 validates it.
6. **Scratch build.** `node scripts/build-quickshell.mjs --output "$SCRATCH/qs-build"`; it validates every built-in manifest and entry file. Delete the scratch build afterwards.
7. **UI behaviour.** Check quiet mode first, the way the guard hook does: `pgrep -x cs2`, `test -e ~/.cache/pentad-focus`, and a Steam game as a `reaper` process whose command line contains `SteamLaunch`:
   ```sh
   for p in $(pgrep -x reaper); do tr '\0' ' ' < /proc/$p/cmdline | grep -q SteamLaunch && echo "steam game $p"; done
   ```
   Do not use `pgrep -f SteamLaunch`: it matches the shell running the check itself.
   - **Quiet mode** → list every UI scenario (interaction, open/close, focus, overflow, scaling) as `unverified — quiet mode`.
   - **Otherwise** → run the relevant scenarios with `scripts/test-quickshell-headless.mjs` under `timeout`, one at a time. Save reports and screenshots under `/tmp` or `artifacts/`, and confirm afterwards that none of *your* harness processes remain (match your report path; other sessions may run their own harness, never touch theirs).
   - For a refactor or a risky change, run the same scenarios on the unchanged commit first (a detached `git worktree add`) and compare check counts and the `TypeError`/`ReferenceError`/binding-loop lines in the logs. A scenario that already failed before your change is reported as pre-existing, not as yours.
   - In a worktree, `qs` lives in the main checkout's gitignored `artifacts/`: link it in (`ln -s <main>/artifacts <worktree>/artifacts`) and remove the link before committing.

   Never fall back to the live desktop, and never treat a screenshot as proof that an interaction works.
8. **Report.** Use the format below. If the user asks for a verification log entry, ask where it should go; there is no log file in the repository any more.

## Report format

```
Verified:   <scenario> — <command> — <result, e.g. 12/12 pass>
Unverified: <scenario> — <reason, e.g. needs isolated Quickshell run>
Commands:   <each command run, with its timeout>
Artifacts:  <paths under /tmp or artifacts/, or "none">
```

## Red flags: stop

- "I'll just run `pnpm test`, it's the standard suite" → it rebuilds the live `dist/`. Ask first.
- "qmllint exited 0, so the QML is clean" → the exit code ignores warnings. Compare against HEAD.
- "`QT_QPA_PLATFORM=offscreen` is isolated enough" → it isn't. Only `test-quickshell-headless.mjs` counts as isolated.
- "The user is playing, but it's only a headless run" → quiet mode blocks headless runs too.
- "The build passed, so the UI works" → a build only proves parsing and manifest validity.
- "The logic tests and qmllint are green, so the split is fine" → moved QML can still bind to `undefined`; only the fixtures that load it show that.
- "This fixture fails, so my change broke it" → check the unchanged commit first; some fail for environment reasons (the virtual KWin has no screen-capture protocol for `bar-tools-ui`).
- Leaving a watcher, compositor or scratch build behind.
