#!/usr/bin/env python3
"""Switch the Hyprland config from another shell to Pentad: show the edits, apply them after a yes, keep an undo.

Pentad's own lines go into a fragment it owns (pentad.lua or pentad.conf next to the entry file); the user's
entry file gets one line that loads it, and another shell's start line is commented out only when it is a
single plain start command.
"""

from __future__ import annotations

import argparse
import contextlib
import difflib
import hashlib
import json
import os
import re
import shutil
import stat
import sys
import tempfile
from dataclasses import dataclass, field
from datetime import datetime, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))  # the doctor ships next to this file
import pentad_doctor as doctor  # noqa: E402

MARKER = "[pentad setup]"
SCHEMA_VERSION = 1
NEW_FILE_MODE = 0o644
# The only start lines setup comments out: one plain call, nothing else on the line.
LUA_EXEC = re.compile(r"^hl\.exec_cmd\(\s*(?:\"([^\"\\]*)\"|'([^'\\]*)')\s*\)$")
CONF_EXEC = re.compile(r"^exec(?:-once)?\s*=\s*(.+)$")
# Commenting a command joined to another one would stop the other one too.
SHELL_OPERATOR = re.compile(r"&&|\|\||[;|&]")
# A previous line ending like this continues onto ours, so ours is not a statement of its own.
LUA_CONTINUATION = re.compile(r"(?:[=,({\[]|\.\.|[+\-*/%^<>~#]|\b(?:and|or|not|return|local))$")
UNQUOTABLE = re.compile(r"[\"\\\r\n]")
# A shell hosted by an interpreter shares its start lines with unrelated scripts; those are left to the user.
INTERPRETER = re.compile(r"python(?:3(?:\.\d+)?)?|node|gjs|sh|bash|dash|zsh|fish|lua|luajit|perl|ruby")
ASSIGNMENT = re.compile(r"[A-Za-z_][A-Za-z0-9_]*=")
FRAGMENT_NAMES = ("pentad.lua", "pentad.conf")

@dataclass
class Draft:
    """A config file as read (None when it does not exist yet), and its lines as they will be written."""
    path: Path
    before: bytes | None
    lines: list[str] = field(default_factory=list)

    def after(self) -> bytes:
        return "".join(self.lines).encode("utf-8", "surrogateescape")

    def append(self, block: list[str]) -> None:
        newline = "\r\n" if any(line.endswith("\r\n") for line in self.lines) else "\n"
        if self.lines and not self.lines[-1].endswith("\n"):
            self.lines[-1] += newline
        if self.lines:
            self.lines.append(newline)
        self.lines.extend(line + newline for line in block)

@dataclass
class Plan:
    found: doctor.Survey
    drafts: list[Draft]  # files that change, in planning order
    manual: list[str]  # edits left to the user, with the reason
    foreign_file: bool  # a start line was commented out somewhere other than the entry file
    bindings_added: bool  # the fragment being written loads Pentad's key bindings

def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()

def shown(path: Path, env) -> str:
    return doctor.shown_path(path, env)

def refusal(path: Path, directory: Path | None, text: doctor.Text) -> str | None:
    """Say why the file must not be written, or None when it may be (a missing file may be created)."""
    if directory is None or directory not in path.parents:
        return text("файл лежить поза текою Hyprland", "the file is outside the Hyprland folder")
    if path.is_symlink():
        return text("файл є символічним посиланням", "the file is a symlink")
    if not path.exists():
        if not os.access(path.parent, os.W_OK):
            return text("тека недоступна для запису", "the folder is not writable")
        return None
    if not path.is_file():
        return text("це не звичайний файл", "it is not a regular file")
    status = path.stat()
    if status.st_size > doctor.CONFIG_FILE_LIMIT:
        return text("файл більший за 256 КіБ", "the file is larger than 256 KiB")
    if status.st_nlink > 1:  # os.replace would leave the other names pointing at the old content
        return text("файл має інші жорсткі посилання", "the file has other hard links")
    if not os.access(path, os.W_OK) or not os.access(path.parent, os.W_OK):
        return text("файл недоступний для запису", "the file is not writable")
    return None

def load(path: Path) -> Draft:
    if not path.exists():
        return Draft(path, None)
    before = path.read_bytes()
    # surrogateescape keeps every byte, so an untouched line is written back exactly as it was.
    return Draft(path, before, before.decode("utf-8", "surrogateescape").splitlines(keepends=True))

def code_of(line: str, lua: bool) -> str:
    return doctor.without_comment(line, lua).strip()

def previous_code(lines: list[str], index: int, lua: bool) -> str:
    """The code of the nearest non-blank, non-comment line above the one at index."""
    for line in reversed(lines[:index]):
        code = code_of(line, lua)
        if code:
            return code
    return ""

def plain_command(line: str, lua: bool, previous: str = "") -> str | None:
    """The command when the line is exactly one plain start command that nothing else depends on, else None."""
    if MARKER in line:
        return None
    code = code_of(line, lua)
    if lua:
        match = LUA_EXEC.match(code)
        command = (match.group(1) if match.group(1) is not None else match.group(2)) if match else None
        if command is None or LUA_CONTINUATION.search(previous) or "--[" in line:
            return None
    else:
        match = CONF_EXEC.match(code)
        command = match.group(1) if match else None
    return None if command is None or SHELL_OPERATOR.search(command) else command

def commentable(line: str, lua: bool, previous: str = "") -> bool:
    return plain_command(line, lua, previous) is not None

def first_program(command: str) -> str:
    """The program a shell command runs, past `uwsm app --` and `env VAR=value` prefixes."""
    words = command.split()
    if words and words[0] == "uwsm" and "--" in words:
        words = words[words.index("--") + 1:]
    while words and (words[0] == "env" or ASSIGNMENT.match(words[0])):
        words = words[1:]
    return Path(words[0]).name if words else ""

def commented(line: str, lua: bool) -> str:
    stripped = line.lstrip()
    return f"{line[:len(line) - len(stripped)]}{'--' if lua else '#'} {MARKER} {stripped}"

def comment(note: str, lua: bool) -> str:
    return f"{'--' if lua else '#'} {MARKER} {note}"

def include_line(fragment: Path, lua: bool) -> str:
    return f'dofile("{fragment}")' if lua else f"source = {fragment}"

def make_plan(found: doctor.Survey, env, text: doctor.Text) -> Plan:
    drafts: dict[Path, Draft] = {}
    refused: dict[Path, str] = {}
    manual: list[str] = []
    foreign_file = False

    def draft(path: Path) -> Draft | None:
        if path not in drafts and path not in refused:
            reason = refusal(path, found.directory, text)
            if reason is None:
                try:
                    drafts[path] = load(path)
                except OSError as error:
                    reason = text(f"не вдалося прочитати файл ({error.strerror})", f"the file could not be read ({error.strerror})")
            if reason is not None:
                refused[path] = reason
        return drafts.get(path)

    for holder in found.holders:
        title = doctor.holder_title(holder, text)
        label = holder.label or text("процес", "process")
        if holder.unit:
            command = f"systemctl --user disable --now {holder.unit}"
            manual.append(text(f"{title} Працює як користувацька служба systemd {holder.unit}: {command}",
                               f"{title} Runs as the systemd user service {holder.unit}: {command}"))
            continue
        if not holder.starts:
            where = shown(found.directory, env) if found.directory else text("конфігурації Hyprland", "the Hyprland config")
            manual.append(text(f"{title} Рядка його запуску в {where} не знайдено. Якщо ви вже прибрали цей рядок, "
                               "процес лишився з поточного сеансу: вийдіть і зайдіть знову. "
                               "Інакше приберіть його з автозапуску сеансу самі.",
                               f"{title} No start line for it was found in {where}. If you already removed it, "
                               "it is still running from this session: log out and back in. "
                               "Otherwise remove it from your session's autostart by hand."))
        for place in holder.starts:
            spot = doctor.shown_place(place, env)
            current = draft(place.path) if place.path.exists() else None
            if current is None:
                reason = refused.get(place.path) or text("файл зник", "the file is gone")
                manual.append(text(f"{spot}: {reason}; закоментуйте рядок самі.", f"{spot}: {reason}; comment the line out by hand."))
                continue
            lua = place.path.suffix == ".lua"
            index = place.number - 1
            line = current.lines[index] if 0 <= index < len(current.lines) else ""
            if MARKER in line:
                continue  # already commented out for another holder that shares the line
            command = plain_command(line, lua, previous_code(current.lines, index, lua))
            if command is None:
                manual.append(text(f"{spot}: це не окрема проста команда запуску; закоментуйте виклик самі: {line.strip()}",
                                   f"{spot}: not a single plain start command; comment the call out by hand: {line.strip()}"))
                continue
            if any(INTERPRETER.fullmatch(word) for word in holder.words):
                manual.append(text(f"{spot}: {label} працює під інтерпретатором, тож рядок не коментується автоматично: {line.strip()}",
                                   f"{spot}: {label} runs under an interpreter, so the line is not commented out automatically: {line.strip()}"))
                continue
            if first_program(command) not in holder.words:
                manual.append(text(f"{spot}: рядок не запускає {label} безпосередньо; змініть його самі: {line.strip()}",
                                   f"{spot}: the line does not start {label} directly; change it by hand: {line.strip()}"))
                continue
            current.lines[index] = commented(line, lua)
            foreign_file = foreign_file or place.path != found.entry
        for place in holder.calls:
            spot = doctor.shown_place(place, env)
            manual.append(text(f"{spot} викликає {label}, але може робити й іншу роботу: змініть рядок, щоб він його не викликав, а не видаляйте.",
                               f"{spot} calls {label} but may do other work too: change the line so it stops calling it rather than delete it."))

    bindings_added = False
    entry = found.entry
    if entry:
        lua = entry.suffix == ".lua"
        fragment = entry.with_name("pentad.lua" if lua else "pentad.conf")
        # The fragment's own lines do not count: it is regenerated from everything else.
        block = []
        if not any(place.path != fragment for place in found.pentad_starts):
            block.append(doctor.autostart_line(found))
        # Bindings the fragment already loads stay loaded, so a later run does not drop them.
        bound = any(holder.bindings and not holder.unit for holder in found.holders) \
            or any(place.path == fragment for place in found.bindings_loads)
        dofile = f'dofile("{found.bindings_file}")'
        if bound and found.bindings_file and not any(place.path != fragment for place in found.bindings_loads):
            if not lua:
                manual.extend(doctor.pentad_bindings_hint(found, text))
            elif UNQUOTABLE.search(str(found.bindings_file)):
                manual.append(text(f"Шлях {found.bindings_file} не можна записати в рядок Lua; підключіть прив'язки самі.",
                                   f"The path {found.bindings_file} cannot be written inside a Lua string; load the bindings by hand."))
            else:
                # The shipped bindings unbind the keys they use first, so they load after the user's own.
                block.append(dofile)
        if block:
            header = comment(text("Цей файл пише `pentad setup`; зміни тут можуть бути перезаписані.",
                                  "This file is written by `pentad setup`; changes here may be overwritten."), lua)
            own = draft(fragment)
            if own is None:
                manual.append(text(f"{shown(fragment, env)}: {refused[fragment]}; запишіть у нього самі: {' '.join(block)}",
                                   f"{shown(fragment, env)}: {refused[fragment]}; write it by hand with: {' '.join(block)}"))
            else:
                own.lines = [line + "\n" for line in [header, *block]]
                bindings_added = dofile in block and (own.before is None or dofile.encode("utf-8", "surrogateescape") not in own.before)
            if own is not None or fragment.is_file():  # only include a fragment that will exist
                manual.extend(include_fragment(draft, refused, entry, fragment, lua, env, text))
    changed = [draft for draft in drafts.values() if draft.after() != draft.before]
    return Plan(found, changed, manual, foreign_file, bindings_added)

def include_fragment(draft, refused: dict[Path, str], entry: Path, fragment: Path, lua: bool, env, text: doctor.Text) -> list[str]:
    """Append the one line that loads the fragment to the entry file, or say what to add by hand."""
    line = include_line(fragment, lua)
    name = shown(entry, env)
    if not entry.exists():
        return [text(f"Створіть {name} із рядком {line}, якщо сеанс не запускає Pentad інакше.",
                     f"Create {name} with {line}, unless your session starts Pentad another way.")]
    current = draft(entry)
    if current is None:
        return [text(f"{name}: {refused[entry]}; додайте {line} у кінець самі.", f"{name}: {refused[entry]}; add {line} at the end by hand.")]
    spellings = (str(fragment), shown(fragment, env))
    if any(spelling in code_of(line, lua) for line in current.lines for spelling in spellings):
        return []
    if UNQUOTABLE.search(str(fragment)) or (not lua and "#" in str(fragment)):
        return [text(f"Шлях {fragment} не можна записати в рядок конфігурації; додайте {line} у кінець {name} самі.",
                     f"The path {fragment} cannot be written on a config line; add {line} at the end of {name} by hand.")]
    if lua and any(re.match(r"return\b", doctor.without_comment(line, True)) for line in current.lines):
        # A statement after `return` is a syntax error; the user knows where the line belongs.
        return [text(f"{name} містить return; додайте {line} перед ним самі.",
                     f"{name} has a return; add {line} before it by hand.")]
    current.append([comment(text("Фрагмент Pentad для Hyprland", "Pentad's Hyprland fragment"), lua), line])
    return []

def unified_diff(draft: Draft, env) -> str:
    before = (draft.before or b"").decode("utf-8", "replace").splitlines()
    after = draft.after().decode("utf-8", "replace").splitlines()
    name = shown(draft.path, env)
    return "\n".join(difflib.unified_diff(before, after, name, name, lineterm="")) + "\n"

def describe(plan: Plan, env, text: doctor.Text) -> str:
    out = [text("Налаштування Pentad", "Pentad setup")]
    if plan.found.holders:
        out += ["", text("Знайдено", "Found")] + ["  " + doctor.holder_title(holder, text) for holder in plan.found.holders]
    if plan.drafts:
        out += ["", text("Зміни", "Changes")] + [unified_diff(draft, env).rstrip("\n") for draft in plan.drafts]
    if plan.manual:
        out += ["", text("Зробити вручну", "By hand")] + ["  " + item for item in plan.manual]
    notes = doctor.unchecked_notes(plan.found, text)
    if not env.get("HYPRLAND_INSTANCE_SIGNATURE"):
        notes.append(text("Зараз це не сеанс Hyprland, тож невідомо, хто малює шпалери й панелі, і зміни вище лише показано. "
                          "Запустіть pentad setup усередині сеансу Hyprland.",
                          "This is not a Hyprland session right now, so it is unknown who draws the wallpaper and panels, "
                          "and the changes above are only a preview. Run pentad setup inside a Hyprland session."))
    elif plan.bindings_added:
        notes.append(text("Hyprland перечитує конфігурацію, щойно файли змінюються, тож додані прив'язки клавіш діють одразу; "
                          "сама заміна оболонки відбудеться під час наступного входу в сеанс.",
                          "Hyprland reloads its config when these files change, so the added key bindings take effect at once; "
                          "the shell switch itself happens at the next login."))
    elif plan.drafts:
        notes.append(text("Зміни подіють під час наступного входу в сеанс.", "The changes take effect at the next login."))
    if plan.foreign_file:
        notes.append(text("Ці файли можуть належати до власного налаштування іншої оболонки, і її оновлення можуть повернути рядки. "
                          "Після такого оновлення запустіть pentad doctor.",
                          "These files may belong to another shell's own setup; its updates can bring the lines back. "
                          "Run pentad doctor after updating it."))
    if notes:
        out += ["", text("Зверніть увагу", "Heads-up")] + ["  " + note for note in notes]
    return "\n".join(out) + "\n"

def state_root(env) -> Path | None:
    if env.get("XDG_STATE_HOME"):
        return Path(env["XDG_STATE_HOME"]) / "pentad/setup"
    return Path(env["HOME"]) / ".local/state/pentad/setup" if env.get("HOME") else None

def write_atomically(path: Path, data: bytes) -> None:
    """Replace the file's contents in one step, keeping its mode; a new file gets the usual mode."""
    mode = stat.S_IMODE(path.stat().st_mode) if path.exists() else NEW_FILE_MODE
    handle, temp = tempfile.mkstemp(prefix=f".{path.name}.", suffix=".pentad-setup", dir=path.parent)
    try:
        with os.fdopen(handle, "wb") as file:
            file.write(data)
            file.flush()
            os.fsync(file.fileno())
        os.chmod(temp, mode)
        os.replace(temp, path)
    except OSError:
        with contextlib.suppress(OSError):
            os.unlink(temp)
        raise

def put_back(path: Path, before: bytes | None) -> None:
    """Return a file to what it was before setup wrote it: its old bytes, or nothing."""
    if before is None:
        path.unlink(missing_ok=True)
    else:
        write_atomically(path, before)

def new_state_directory(base: Path, now: datetime) -> Path:
    stamp = now.strftime("%Y%m%dT%H%M%SZ")
    for attempt in range(1, 1000):
        candidate = base / (stamp if attempt == 1 else f"{stamp}-{attempt}")
        try:
            candidate.mkdir(parents=True, mode=0o700)
            return candidate
        except FileExistsError:
            continue
    raise FileExistsError(str(base / stamp))

def read_or_none(path: Path) -> bytes | None:
    try:
        return path.read_bytes()
    except OSError:
        return None

def apply(plan: Plan, env, now: datetime, text: doctor.Text) -> tuple[list[str], int]:
    """Back the files up, write them atomically, and undo the written ones when anything goes wrong."""
    base = state_root(env)
    if base is None:
        return [text("Невідомо, де зберігати резервні копії: HOME не задано.", "Nowhere to keep backups: HOME is not set.")], 1
    try:
        state = new_state_directory(base, now)
        files = []
        for index, draft in enumerate(plan.drafts, 1):
            backup = None
            if draft.before is not None:
                backup = f"{index}-{draft.path.name}"
                (state / backup).write_bytes(draft.before)
            files.append({"path": str(draft.path), "backup": backup, "sha256After": sha256(draft.after())})
        manifest = {"schemaVersion": SCHEMA_VERSION, "created": now.isoformat(), "files": files}
        (state / "manifest.json").write_text(json.dumps(manifest, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    except OSError as error:
        return [text(f"Не вдалося зберегти резервні копії в {shown(base, env)}: {error.strerror}. Нічого не змінено.",
                     f"Could not save backups in {shown(base, env)}: {error.strerror}. Nothing changed.")], 1
    written: list[Draft] = []
    failure = None
    for draft in plan.drafts:
        name = shown(draft.path, env)
        if read_or_none(draft.path) != draft.before:
            failure = text(f"{name} змінився після показу плану; його не записано.", f"{name} changed after the plan was shown; it was not written.")
            break
        try:
            write_atomically(draft.path, draft.after())
        except OSError as error:
            failure = text(f"Не вдалося записати {name}: {error.strerror}.", f"Could not write {name}: {error.strerror}.")
            break
        written.append(draft)
    if failure is None:
        return [text(f"Застосовано. Резервні копії: {shown(state, env)}; скасувати можна командою `pentad setup --undo`. "
                     "Щоб перейти на Pentad, вийдіть із сеансу й увійдіть знову.",
                     f"Applied. Backups are in {shown(state, env)}; undo with `pentad setup --undo`. "
                     "Log out and back in to switch to Pentad.")], 0
    out = [failure]
    unrestored = []
    for draft in written:
        try:
            put_back(draft.path, draft.before)
        except OSError:
            unrestored.append(shown(draft.path, env))
    if unrestored:
        out.append(text(f"Не вдалося відновити {', '.join(unrestored)}; резервні копії лежать у {shown(state, env)}.",
                        f"Could not restore {', '.join(unrestored)}; the backups are in {shown(state, env)}."))
    else:
        if written:
            out.append(text("Файли, записані до того, відновлено.", "The files written before it were restored."))
        shutil.rmtree(state, ignore_errors=True)
        out.append(text("Нічого не змінено.", "Nothing changed."))
    return out, 1

def newest_manifest(base: Path) -> tuple[Path, dict] | None:
    """Return the newest setup run that has not been undone, with its manifest."""
    if not base.is_dir():
        return None
    for directory in sorted(base.iterdir(), reverse=True):
        try:
            manifest = json.loads((directory / "manifest.json").read_text(encoding="utf-8"))
        except (OSError, ValueError):
            continue
        if isinstance(manifest, dict) and manifest.get("schemaVersion") == SCHEMA_VERSION and "undone" not in manifest \
                and isinstance(manifest.get("files"), list):
            return directory, manifest
    return None

def undo(env, now: datetime, text: doctor.Text) -> tuple[list[str], int]:
    """Restore the files of the newest setup run that still hold what setup wrote; remove the files it created."""
    base = state_root(env)
    run = newest_manifest(base) if base else None
    if run is None:
        return [text("Нема чого скасовувати.", "Nothing to undo.")], 1
    directory, manifest = run
    out, restored, failed, kept = [], 0, False, []
    hypr = doctor.hypr_directory(env)
    # Files setup created go last: while a file that loads them stays as it is, they must stay too.
    files = sorted(manifest["files"], key=lambda entry: entry.get("backup") is None)
    for entry in files:
        path = Path(str(entry.get("path", "")))
        name = shown(path, env)
        created = entry.get("backup") is None
        backup = None if created else directory / Path(str(entry["backup"])).name
        current = read_or_none(path)
        if current is None or sha256(current) != entry.get("sha256After"):
            kept.append(name)
            if created:
                out.append(text(f"Не вилучено {name}: його змінили після pentad setup.", f"Left {name} alone: it changed after pentad setup."))
            else:
                out.append(text(f"Не відновлено {name}: його змінили після pentad setup; резервна копія: {shown(backup, env)}.",
                                f"Left {name} alone: it changed after pentad setup; the backup is {shown(backup, env)}."))
            continue
        if created and kept:
            out.append(text(f"Не вилучено {name}: {', '.join(kept)} не відновлено й може його ще підключати.",
                            f"Left {name} alone: {', '.join(kept)} was left alone and may still load it."))
            continue
        if created and (path.name not in FRAGMENT_NAMES or path.parent != hypr):
            out.append(text(f"Не вилучено {name}: це не фрагмент Pentad у теці Hyprland.",
                            f"Left {name} alone: it is not Pentad's fragment in the Hyprland folder."))
            continue
        try:
            put_back(path, None if created else backup.read_bytes())
            restored += 1
            out.append(text(f"Вилучено {name}.", f"Removed {name}.") if created else text(f"Відновлено {name}.", f"Restored {name}."))
        except OSError as error:
            failed = True
            kept.append(name)
            out.append(text(f"Не вдалося відновити {name}: {error.strerror}.", f"Could not restore {name}: {error.strerror}."))
    if failed:
        return out, 1  # the run stays open so a second --undo can finish it
    manifest["undone"] = now.isoformat()
    try:
        (directory / "manifest.json").write_text(json.dumps(manifest, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    except OSError as error:
        out.append(text(f"Не вдалося позначити скасування в {shown(directory, env)}: {error.strerror}.",
                        f"Could not mark the undo in {shown(directory, env)}: {error.strerror}."))
        return out, 1
    return out, 0 if restored else 1

def confirmed(stdin, text: doctor.Text) -> bool:
    sys.stdout.write(text("Застосувати ці зміни? [y/N] ", "Apply these changes? [y/N] "))
    sys.stdout.flush()
    answer = stdin.readline()
    if not answer.endswith("\n"):
        sys.stdout.write("\n")
    return answer.strip().lower() in ("y", "yes")

def main(argv=None, env=None, system_root: Path = Path("/"), stdin=None, now: datetime | None = None) -> int:
    parser = argparse.ArgumentParser(description="Switch the Hyprland config to Pentad after showing the changes and asking.")
    parser.add_argument("--root", type=Path, required=True, help="installed Pentad Quickshell root")
    parser.add_argument("--qs", default="qs", help="Quickshell executable (accepted for symmetry with pentad doctor)")
    parser.add_argument("--undo", action="store_true", help="restore the files of the last setup run")
    args = parser.parse_args(argv)
    env = os.environ if env is None else env
    stdin = sys.stdin if stdin is None else stdin
    now = datetime.now(timezone.utc) if now is None else now
    text = doctor.Text(doctor.is_ukrainian(env))
    if args.undo:
        lines, status = undo(env, now, text)
        sys.stdout.write("\n".join(lines) + "\n")
        return status
    if not (args.root / "shell.qml").is_file():
        # Without the real root every Pentad process looks foreign and would be planned away.
        sys.stdout.write(text(f"Файлів Pentad не знайдено в {args.root}; перевірте --path або встановіть Pentad ще раз.",
                              f"Pentad files not found in {args.root}; check --path or install Pentad again.") + "\n")
        return 1
    plan = make_plan(doctor.survey(args.root, env, system_root), env, text)
    sys.stdout.write(describe(plan, env, text))
    if not env.get("HYPRLAND_INSTANCE_SIGNATURE"):
        return 1  # a preview only: without the session the other shell may be missed, and the heads-up says so
    if not plan.drafts:
        sys.stdout.write("\n" + (text("Сам pentad setup нічого змінити не може; зробіть пункти вище вручну.",
                                      "pentad setup cannot make any of these changes itself; edit the items above by hand.") if plan.manual
                                 else text("Нічого змінювати: конфігурація Hyprland уже запускає Pentad.",
                                           "Nothing to change: the Hyprland config already starts Pentad.")) + "\n")
        return 0
    sys.stdout.write("\n")
    if not confirmed(stdin, text):
        sys.stdout.write(text("Нічого не змінено.", "Nothing changed.") + "\n")
        return 1
    lines, status = apply(plan, env, now, text)
    sys.stdout.write("\n".join(lines) + "\n")
    return status

if __name__ == "__main__":
    sys.exit(main())
