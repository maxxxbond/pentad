# How to plan and carry out a task

Read this for any task larger than a small fix, and whenever you are unsure whether to ask or decide. The short version is in [AGENTS.md](../../AGENTS.md#how-to-work).

## 1. Size the task first

Decide the size before you write code. The size sets how much planning, approval and verification the task needs. When in doubt, pick the larger size.

| Size | Typical shape | What it needs before code | Approval |
| --- | --- | --- | --- |
| **S** | Up to about 3 files in one area, clear cause, no visible behaviour change beyond the fix | Nothing written. Know the scenario you will verify | None |
| **M** | Several files in one area, a new widget from the template, a visible change to one surface | A short plan in your reply: 3–7 bullets with files, approach and checks | None, unless it changes look or behaviour the user cares about |
| **L** | Crosses services, logic and views; a new user-visible feature; a settings page; a change to defaults | A plan in chat that names the user-visible decisions separately from the technical steps | The user confirms the user-visible decisions |
| **Contract** | Widget API v1, manifest schema, config or state file formats, IPC, CLI, a new runtime dependency, removing a feature, licensing or third-party code | A decision note: context, options with trade-offs, recommendation, consequences, migration and compatibility | The user approves before code |

Do not write plan or spec files into `docs/` unless asked. Plans live in the conversation; decisions that must outlive it go where the user asks.

## 2. Think it through before coding

Answer these, briefly, for every M task and above:

1. **Who uses it, and how?** A Pentad user on a different machine, a widget author, a packager. What do they see and do?
2. **Which states exist?** Normal, empty, loading, error, recovery, the device or service missing, the device removed while in use. For a bug: the exact reproduction.
3. **What already exists?** Search `quickshell/components`, `services` and `logic` first. Reuse a shared component, service or helper before writing a new one. Extending a shared piece beats a local copy.
4. **What can break elsewhere?** Other monitors and scales, the other language, reduced motion, light theme, a widget placed in another slot, saved configs from older versions.
5. **How will I verify it?** Name the test, fixture scenario or static check per scenario. A scenario with no check is reported as `unverified`, not silently dropped.
6. **How is it undone?** A user's saved settings must survive a revert, and a migration must not destroy data.

## 3. Ask or decide

**Ask** when the decision belongs to the user:

- product scope and priorities: what to build, what to leave out;
- visible design direction: a new look, layout or interaction pattern that the design contract does not already settle;
- public contracts, data formats, new dependencies, removing behaviour;
- anything outward-facing or hard to undo: publishing, pushing, history rewrites, deleting files that are not yours, spending money.

**Decide yourself** for everything with a sensible default: naming, file placement, implementation technique, test structure, refactors inside the scope. State the assumption in one line and keep going.

When you do ask, ask once: collect the questions, give your recommendation first with the reason, and offer real alternatives. Do not ask about facts you can find in the code.

## 4. Implement

- Make the smallest change that fully solves the problem. No drive-by refactors, no speculative options, no "while I'm here".
- Match the surrounding code: naming, comment density, file layout, idiom. Pentad keeps pure models in Qt-free `quickshell/logic/*.mjs`, native adapters in `services/`, and views in `features/`, `components/` and `widgets/`.
- Give every subscription, `Timer`, `Process`, request and window an owner and a lifetime. Stop work when the surface is hidden.
- Keep user-visible text paired (Ukrainian and English) from the first line, not as a follow-up.
- Update the documentation that describes the changed behaviour in the same change.
- Do not leave `TODO`s behind. Either finish it or name it in the report as follow-up work.

## 5. When stuck

After two failed attempts with the same idea, stop. Write down what you know, what you ruled out and what you suspect, then change the approach, read the real source (Quickshell, Qt, Hyprland) or ask for help. Do not loop. Do not weaken a test, a check or the design contract to make a result pass.

## 6. Definition of done

A task is done when all of these hold:

- the scenarios from step 2 are verified, or listed as `unverified` with a reason;
- the safe checks from the verify-change skill pass for the changed files, and `qmllint` shows no new warnings in changed lines;
- user-visible text exists in both languages, and nothing depends on this machine (monitor names, paths, locale, installed apps);
- the docs that describe the behaviour are updated;
- the diff contains nothing unrelated: no debug output, no stray files, no `artifacts` symlink;
- if commits were requested, they are focused and follow [publishing rules](for-everyone.md#commits-and-history).

## 7. Report

End with a report the user can act on, in the language the user writes in:

```
Changed:    <what changed for the user, then the files>
Verified:   <scenario> — <command> — <result>
Unverified: <scenario> — <reason>
Decisions:  <assumptions made without asking, if any>
Next:       <the command or decision the user needs, if any>
```

Report faithfully. A failing test is reported with its output, a skipped step is named as skipped, and a build is never called proof that the UI works.

## 8. Learning from feedback

- A user correction about design or behaviour is binding from then on. If it is general (it applies beyond the current file), propose adding it to the design contract or the relevant `docs/development` page, so it reaches every contributor and not just one agent's memory.
- Personal working preferences of the maintainer (how they like reports, which branch to use) belong in the agent's memory, not in the repository.
- Never record secrets, tokens or personal data in memory, docs or commit messages.
