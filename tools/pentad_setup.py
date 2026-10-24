#!/usr/bin/env python3
"""Switch the Hyprland session from another shell to Pentad: show the edits, apply them after a yes, keep an undo.

Pentad's own lines go into a fragment it owns (pentad.lua or pentad.conf next to the entry file); the user's
entry file gets one line that loads it. Another shell's start line is commented out only when the Lua lexer
or the hyprlang pattern says it is a single plain start statement; a systemd user service that runs the
shell is masked, and an XDG autostart entry for it is hidden. After writing, setup lets Hyprland itself
verify the result through its event socket and `hyprctl configerrors`, and rolls everything back when new
errors appear. `--undo` restores by content, or by the markers when a file was edited since.
"""

from __future__ import annotations

import argparse
import contextlib
import difflib
import hashlib
import json
import os
import re
import shlex
import shutil
import signal
import stat
import sys
import tempfile
import time
from dataclasses import dataclass, field
from datetime import datetime, timezone
from pathlib import Path

sys.path.append(str(Path(__file__).resolve().parent))  # the doctor and the lexer ship next to this file
import pentad_doctor as doctor  # noqa: E402
import pentad_lua as lua  # noqa: E402

MARKER = "[pentad setup]"
SCHEMA_VERSION = 2
NEW_FILE_MODE = 0o644
CONF_EXEC = re.compile(r"^exec(?:-once)?\s*=\s*(.+)$")
# Commenting a command joined to another one would stop the other one too; a lone trailing & only backgrounds.
SHELL_OPERATOR = re.compile(r"&&|\|\||[;|]|&(?!\s*$)")
TRAILING_AMPERSAND = re.compile(r"\s*&\s*$")
UNQUOTABLE = re.compile(r"[\"\\\r\n]")
FRAGMENT_NAMES = ("pentad.lua", "pentad.conf")
HOOK_EVENT = "hyprland.start"
# The include searches the config folder through package.path (Hyprland sets it to <config dir>/?.lua first),
# so a synced dotfiles folder keeps working on another machine, a missing fragment is not an error, and a
# reload runs the fragment again. The v1 include was dofile("<absolute pentad.lua>"); it still counts as present.
LUA_INCLUDE = 'if package.searchpath("pentad", package.path) then package.loaded.pentad = nil require("pentad") end'
LUA_REQUIRE = re.compile(r"""require\s*\(?\s*(?:"pentad"|'pentad')\s*\)?""")
STOP_TIMEOUT = 5.0  # seconds to wait for a stopped shell to exit
SWITCH_TIMEOUT = 10.0  # seconds to wait for Pentad to take over
POLL_INTERVAL = 0.25
STRING, EVENT = "<string>", "<event>"
LUA_CALL = ["hl", ".", "exec_cmd", "(", STRING, ")"]
LUA_HOOK = ["hl", ".", "on", "(", EVENT, ",", "function", "(", ")", "hl", ".", "exec_cmd", "(", STRING, ")", "end", ")"]

@dataclass
class Hooks:
    """The few things the switch does to live processes, replaceable in tests."""
    kill: object = os.kill
    sleep: object = time.sleep
    clock: object = time.monotonic

@dataclass
class Draft:
    """A file as read (None when it does not exist yet), its lines as they will be written, and what setup did to it."""
    path: Path
    before: bytes | None
    lines: list[str] = field(default_factory=list)
    role: str = "config"  # config, fragment or autostart
    commented: list[str] = field(default_factory=list)  # original lines now carrying the marker, for the marker undo
    include: list[str] = field(default_factory=list)  # the marker line and the include line appended to the entry file
    hidden: list[str] = field(default_factory=list)  # the marker line and Hidden=true put into an autostart entry
    holders: set[int] = field(default_factory=set)  # pids whose start this draft disables
    programs: dict[int, set[str]] = field(default_factory=dict)  # per holder pid, the first programs of the lines commented

    def after(self) -> bytes:
        return "".join(self.lines).encode("utf-8", "surrogateescape")

    def newline(self) -> str:
        return "\r\n" if any(line.endswith("\r\n") for line in self.lines) else "\n"

    def append(self, block: list[str]) -> None:
        newline = self.newline()
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
    units: list[str] = field(default_factory=list)  # systemd user services to mask
    stopped: list[tuple[doctor.Holder, str | None]] = field(default_factory=list)  # holders this run takes out of autostart
    lua: bool = False  # Hyprland runs a Lua config, which changes the hyprctl dispatch syntax

def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()

def shown(path: Path, env) -> str:
    return doctor.shown_path(path, env)

def refusal(path: Path, directory: Path | None, text: doctor.Text) -> str | None:
    """Say why the file must not be written, or None when it may be (a missing file may be created)."""
    if directory is None or directory not in path.parents:
        return text("файл лежить поза дозволеною текою", "the file is outside the allowed folder")
    if path.is_symlink():
        return text("файл є символічним посиланням", "the file is a symlink")
    if not path.exists():
        parent = path.parent
        while not parent.exists() and parent != parent.parent:
            parent = parent.parent
        if not os.access(parent, os.W_OK):
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

def split_keepends(text: str) -> list[str]:
    """Lines split on `\\n` only, newline kept, so line numbers agree with the lexer and the doctor's scan."""
    parts = text.split("\n")
    lines = [part + "\n" for part in parts[:-1]]
    if parts[-1]:
        lines.append(parts[-1])
    return lines

def load(path: Path) -> Draft:
    if not path.exists():
        return Draft(path, None)
    before = path.read_bytes()
    # surrogateescape keeps every byte, so an untouched line is written back exactly as it was.
    return Draft(path, before, split_keepends(before.decode("utf-8", "surrogateescape")))

def text_of(draft: Draft) -> str:
    return "".join(draft.lines)

def match_shape(tokens: list[lua.Token], shape: list[str]) -> lua.Token | None:
    """The command string token when the tokens are exactly the shape, else None."""
    if tokens and tokens[-1].text == ";":
        tokens = tokens[:-1]
    if len(tokens) != len(shape):
        return None
    command = None
    for token, expected in zip(tokens, shape):
        if expected == STRING:
            if token.kind != "string":
                return None
            command = token
        elif expected == EVENT:
            if lua.unquote(token) != HOOK_EVENT:
                return None
        elif token.text != expected or token.kind not in ("name", "keyword", "op"):
            return None
    return command

def lua_start_statement(lexed: lua.Lexed, number: int) -> tuple[str, list[lua.Token]] | None:
    """The command and the tokens when the line is one complete `hl.exec_cmd("…")` statement or the one-line start hook."""
    tokens = lexed.statement_on(number)
    if tokens is None:
        return None
    token = match_shape(tokens, LUA_CALL) or match_shape(tokens, LUA_HOOK)
    command = lua.unquote(token) if token is not None else None
    return (command, tokens) if command is not None else None

def conf_start_command(line: str) -> str | None:
    match = CONF_EXEC.match(doctor.without_comment(line, False).strip())
    return match.group(1).strip() if match else None

def start_statement(content: str, number: int, is_lua: bool) -> tuple[str, list[lua.Token]] | None:
    """The command (and the Lua tokens) when line `number` is exactly one plain start command that nothing else depends on."""
    lines = doctor.split_lines(content)
    if not 1 <= number <= len(lines) or MARKER in lines[number - 1]:
        return None
    if is_lua:
        lexed = lua.lex(content)
        found = lua_start_statement(lexed, number) if lexed.balanced else None
    else:
        command = conf_start_command(lines[number - 1])
        found = (command, []) if command is not None else None
    if found is None:
        return None
    command = TRAILING_AMPERSAND.sub("", found[0])
    return None if not command or SHELL_OPERATOR.search(command) else (command, found[1])

def plain_command(content: str, number: int, is_lua: bool) -> str | None:
    found = start_statement(content, number, is_lua)
    return found[0] if found else None

def commentable(content: str, number: int, is_lua: bool) -> bool:
    return plain_command(content, number, is_lua) is not None

def first_program(command: str) -> str:
    return doctor.first_program(command)

def commented(line: str, is_lua: bool) -> str:
    stripped = line.lstrip()
    return f"{line[:len(line) - len(stripped)]}{'--' if is_lua else '#'} {MARKER} {stripped}"

def comment(note: str, is_lua: bool) -> str:
    return f"{'--' if is_lua else '#'} {MARKER} {note}"

def owned(before: bytes | None) -> bool:
    """True when setup may regenerate the fragment: it does not exist, or its first line is setup's header."""
    if before is None:
        return True
    first = before.decode("utf-8", "replace").split("\n", 1)[0].strip()
    return first.startswith(f"-- {MARKER}") or first.startswith(f"# {MARKER}")

def include_line(fragment: Path, is_lua: bool) -> str:
    return LUA_INCLUDE if is_lua else f"source = {fragment}"

def includes_fragment(line: str, fragment: Path, env, is_lua: bool) -> bool:
    code = doctor.without_comment(line, is_lua)
    if any(spelling in code for spelling in (str(fragment), shown(fragment, env))):
        return True
    return is_lua and LUA_REQUIRE.search(code) is not None

def mask_path(unit: str, env) -> Path | None:
    base = Path(env["XDG_CONFIG_HOME"]) if env.get("XDG_CONFIG_HOME") else Path(env["HOME"]) / ".config" if env.get("HOME") else None
    return base / "systemd/user" / unit if base else None

def autostart_directory(env) -> Path | None:
    base = Path(env["XDG_CONFIG_HOME"]) if env.get("XDG_CONFIG_HOME") else Path(env["HOME"]) / ".config" if env.get("HOME") else None
    return base / "autostart" if base else None

def hide_entry(current: Draft, text: doctor.Text) -> bool:
    """Put a marked Hidden=true right after the [Desktop Entry] header; False when the header is missing."""
    for index, line in enumerate(current.lines):
        if line.strip() == "[Desktop Entry]":
            newline = current.newline()
            note = comment(text("Pentad показує це сам; запис приховано", "Pentad does this itself; entry hidden"), False)
            current.hidden = [note, "Hidden=true"]
            current.lines[index + 1:index + 1] = [note + newline, "Hidden=true" + newline]
            return True
    return False

def make_plan(found: doctor.Survey, env, text: doctor.Text) -> Plan:
    drafts: dict[Path, Draft] = {}
    refused: dict[Path, str] = {}
    manual: list[str] = []
    units: list[str] = []
    foreign_file = False
    hypr = found.directory
    autostart = autostart_directory(env)

    def draft(path: Path, directory: Path | None, role: str = "config") -> Draft | None:
        if path not in drafts and path not in refused:
            reason = refusal(path, directory, text)
            if reason is None:
                try:
                    drafts[path] = load(path)
                    drafts[path].role = role
                except OSError as error:
                    reason = text(f"не вдалося прочитати файл ({error.strerror})", f"the file could not be read ({error.strerror})")
            if reason is not None:
                refused[path] = reason
        return drafts.get(path)

    for holder in found.holders:
        title = doctor.holder_title(holder, text)
        label = holder.label or text("процес", "process")
        if holder.unit:
            path = mask_path(holder.unit, env)
            if path is None or path.exists() or path.is_symlink():
                where = shown(path, env) if path else "~/.config/systemd/user"
                manual.append(text(f"{title} Працює як служба systemd {holder.unit}, а в {where} уже є файл цієї служби, "
                                   f"тож замаскувати її не можна; вимкніть самі: systemctl --user disable --now {holder.unit}",
                                   f"{title} Runs as the systemd service {holder.unit}, and {where} already holds a unit file, "
                                   f"so it cannot be masked; disable it yourself: systemctl --user disable --now {holder.unit}"))
            else:
                units.append(holder.unit)
        for entry in holder.autostart:
            place = shown(entry.path, env)
            if entry.hidden_key:
                manual.append(text(f"{place}: запис уже має ключ Hidden; поставте в ньому Hidden=true самі.",
                                   f"{place}: the entry already has a Hidden key; set Hidden=true in it yourself."))
                continue
            if entry.user:
                current = draft(entry.path, autostart, "autostart")
                if current is None:
                    manual.append(text(f"{place}: {refused[entry.path]}; додайте Hidden=true самі.",
                                       f"{place}: {refused[entry.path]}; add Hidden=true yourself."))
                elif not current.hidden and not hide_entry(current, text):
                    manual.append(text(f"{place}: групу [Desktop Entry] не знайдено; додайте Hidden=true самі.",
                                       f"{place}: no [Desktop Entry] group found; add Hidden=true yourself."))
                elif current.hidden:
                    current.holders.add(holder.pid)
                continue
            override = autostart / entry.path.name if autostart else None
            current = draft(override, autostart, "autostart") if override else None
            if current is None:
                reason = refused.get(override) if override else text("HOME не задано", "HOME is not set")
                manual.append(text(f"{place}: {reason}; створіть {shown(override, env) if override else '~/.config/autostart/' + entry.path.name} "
                                   "із рядками [Desktop Entry] і Hidden=true самі.",
                                   f"{place}: {reason}; create {shown(override, env) if override else '~/.config/autostart/' + entry.path.name} "
                                   "with the lines [Desktop Entry] and Hidden=true yourself."))
                continue
            if current.before is not None:
                continue  # the user's own override is in effect, and the entry was taken from it
            current.lines = [line + "\n" for line in [comment(text(f"Приховує {place}: Pentad робить це сам.",
                                                                    f"Hides {place}: Pentad does this itself."), False),
                                                      "[Desktop Entry]", "Hidden=true"]]
            current.hidden = ["[Desktop Entry]", "Hidden=true"]
            current.holders.add(holder.pid)
        if not holder.starts and not holder.unit and not holder.autostart:
            where = shown(hypr, env) if hypr else text("конфігурації Hyprland", "the Hyprland config")
            manual.append(text(f"{title} Рядка його запуску в {where} не знайдено. Якщо ви вже прибрали цей рядок, "
                               "процес лишився з поточного сеансу: вийдіть і зайдіть знову. "
                               "Інакше приберіть його з автозапуску сеансу самі.",
                               f"{title} No start line for it was found in {where}. If you already removed it, "
                               "it is still running from this session: log out and back in. "
                               "Otherwise remove it from your session's autostart by hand."))
        for place in holder.starts:
            spot = doctor.shown_place(place, env)
            current = draft(place.path, hypr) if place.path.exists() else None
            if current is None:
                reason = refused.get(place.path) or text("файл зник", "the file is gone")
                manual.append(text(f"{spot}: {reason}; закоментуйте рядок самі.", f"{spot}: {reason}; comment the line out by hand."))
                continue
            is_lua = place.path.suffix == ".lua"
            index = place.number - 1
            line = current.lines[index] if 0 <= index < len(current.lines) else ""
            if MARKER in line:
                current.holders.add(holder.pid)
                continue  # already commented out for another holder that shares the line
            if is_lua and not (lexed := lua.lex(text_of(current))).balanced:
                manual.append(text(f"{spot}: файл не розбирається як Lua ({'; '.join(lexed.errors)}); закоментуйте рядок самі: {line.strip()}",
                                   f"{spot}: the file does not parse as Lua ({'; '.join(lexed.errors)}); comment the line out by hand: {line.strip()}"))
                continue
            statement = start_statement(text_of(current), place.number, is_lua)
            if statement is None or any(token.text not in line for token in statement[1]):
                # The second case cannot happen when the lexer and the line split agree; it is a guard, not a path.
                manual.append(text(f"{spot}: це не окрема проста команда запуску; закоментуйте виклик самі: {line.strip()}",
                                   f"{spot}: not a single plain start command; comment the call out by hand: {line.strip()}"))
                continue
            command = statement[0]
            program = first_program(command)
            if doctor.INTERPRETER.fullmatch(program):
                manual.append(text(f"{spot}: рядок запускає інтерпретатор {program}, тож не коментується автоматично: {line.strip()}",
                                   f"{spot}: the line runs the interpreter {program}, so it is not commented out automatically: {line.strip()}"))
                continue
            if program not in holder.words:
                manual.append(text(f"{spot}: рядок не запускає {label} безпосередньо; змініть його самі: {line.strip()}",
                                   f"{spot}: the line does not start {label} directly; change it by hand: {line.strip()}"))
                continue
            if program in doctor.SHELL_FAMILY:
                # Every Quickshell shell starts with the same program; only the config it selects tells them apart.
                known = doctor.line_variables(place.path, holder.environment, found.variables)
                names, unresolved = doctor.quickshell_line_names(command, known)
                if unresolved:
                    manual.append(text(f"{spot}: у рядку є змінна, якої нема в середовищі процесу, тож невідомо, чи це {label}; "
                                       f"закоментуйте його самі, якщо так: {line.strip()}",
                                       f"{spot}: the line uses a variable that the process environment does not hold, so it is unknown "
                                       f"whether it starts {label}; comment it out by hand if it does: {line.strip()}"))
                    continue
                if not doctor.same_quickshell(names, False, holder.config_names):
                    manual.append(text(f"{spot}: рядок запускає іншу конфігурацію Quickshell, не {label}; лишено як є: {line.strip()}",
                                       f"{spot}: the line starts another Quickshell config, not {label}; left as it is: {line.strip()}"))
                    continue
            current.commented.append(line.rstrip("\r\n"))
            current.lines[index] = commented(line, is_lua)
            current.holders.add(holder.pid)
            current.programs.setdefault(holder.pid, set()).add(program)
            foreign_file = foreign_file or place.path != found.entry
        for place in holder.calls:
            spot = doctor.shown_place(place, env)
            manual.append(text(f"{spot} викликає {label}, але може робити й іншу роботу: змініть рядок, щоб він його не викликав, а не видаляйте.",
                               f"{spot} calls {label} but may do other work too: change the line so it stops calling it rather than delete it."))

    bindings_added = False
    entry = found.entry
    if entry:
        is_lua = entry.suffix == ".lua"
        fragment = entry.with_name("pentad.lua" if is_lua else "pentad.conf")
        # The fragment's own lines do not count: it is regenerated from everything else.
        block = []
        if not any(place.path != fragment for place in found.pentad_starts):
            block.append(doctor.autostart_line(found))
        # Bindings the fragment already loads stay loaded, so a later run does not drop them.
        bound = any(holder.bindings and not holder.unit for holder in found.holders) \
            or any(place.path == fragment for place in found.bindings_loads)
        dofile = f'dofile("{found.bindings_file}")'
        if bound and found.bindings_file and not any(place.path != fragment for place in found.bindings_loads):
            if not is_lua:
                manual.extend(doctor.pentad_bindings_hint(found, text))
            elif UNQUOTABLE.search(str(found.bindings_file)):
                manual.append(text(f"Шлях {found.bindings_file} не можна записати в рядок Lua; підключіть прив'язки самі.",
                                   f"The path {found.bindings_file} cannot be written inside a Lua string; load the bindings by hand."))
            else:
                # The shipped bindings unbind the keys they use first, so they load after the user's own.
                block.append(dofile)
        if block:
            header = comment(text("Цей файл пише `pentad setup`; зміни тут можуть бути перезаписані.",
                                  "This file is written by `pentad setup`; changes here may be overwritten."), is_lua)
            own = draft(fragment, hypr, "fragment")
            if own is None:
                manual.append(text(f"{shown(fragment, env)}: {refused[fragment]}; запишіть у нього самі: {' '.join(block)}",
                                   f"{shown(fragment, env)}: {refused[fragment]}; write it by hand with: {' '.join(block)}"))
            elif not owned(own.before):
                manual.append(text(f"{shown(fragment, env)} написано не pentad setup (перший рядок не його заголовок), тож файл ваш; "
                                   f"додайте в нього самі: {' '.join(block)}",
                                   f"{shown(fragment, env)} was not written by pentad setup (its first line is not setup's header), so it is yours; "
                                   f"add to it yourself: {' '.join(block)}"))
            else:
                own.lines = [line + "\n" for line in [header, *block]]
                bindings_added = dofile in block and (own.before is None or dofile.encode("utf-8", "surrogateescape") not in own.before)
            if own is not None or fragment.is_file():  # only include a fragment that will exist
                manual.extend(include_fragment(draft, refused, entry, fragment, is_lua, hypr, env, text))
    changed = [draft for draft in drafts.values() if draft.after() != draft.before]
    # Hyprland would show a config error for a Lua file that no longer parses; do not write one.
    kept = []
    for draft in changed:
        lexed = lua.lex(text_of(draft)) if draft.path.suffix == ".lua" else None
        if lexed is not None and not lexed.balanced:
            manual.append(text(f"{shown(draft.path, env)}: після змін файл не був би коректним Lua ({'; '.join(lexed.errors)}); "
                               "його не записано, зробіть зміни самі.",
                               f"{shown(draft.path, env)}: the result would not be valid Lua ({'; '.join(lexed.errors)}); "
                               "it is not written, make the change by hand."))
            continue
        kept.append(draft)
    stopped = []
    for holder in found.holders:
        unit = holder.unit if holder.unit in units else None
        if unit or any(holder.pid in draft.holders for draft in kept):
            stopped.append((holder, unit))
    in_use = found.explicit_config or entry
    return Plan(found, kept, manual, foreign_file, bindings_added, units, stopped, bool(in_use and in_use.suffix == ".lua"))

def include_fragment(draft, refused: dict[Path, str], entry: Path, fragment: Path, is_lua: bool, hypr: Path | None,
                     env, text: doctor.Text) -> list[str]:
    """Append the one line that loads the fragment to the entry file, or say what to add by hand."""
    line = include_line(fragment, is_lua)
    name = shown(entry, env)
    if not entry.exists():
        return [text(f"Створіть {name} із рядком {line}, якщо сеанс не запускає Pentad інакше.",
                     f"Create {name} with {line}, unless your session starts Pentad another way.")]
    current = draft(entry, hypr)
    if current is None:
        return [text(f"{name}: {refused[entry]}; додайте {line} у кінець самі.", f"{name}: {refused[entry]}; add {line} at the end by hand.")]
    if any(includes_fragment(line, fragment, env, is_lua) for line in current.lines):
        return []
    if not is_lua and ("#" in str(fragment) or UNQUOTABLE.search(str(fragment))):
        return [text(f"Шлях {fragment} не можна записати в рядок конфігурації; додайте {line} у кінець {name} самі.",
                     f"The path {fragment} cannot be written on a config line; add {line} at the end of {name} by hand.")]
    if is_lua:
        lexed = lua.lex(text_of(current))
        if not lexed.balanced:
            return [text(f"{name} не розбирається як Lua ({'; '.join(lexed.errors)}); додайте {line} самі.",
                         f"{name} does not parse as Lua ({'; '.join(lexed.errors)}); add {line} by hand.")]
        if lexed.top_level_return:
            # A statement after `return` is a syntax error; the user knows where the line belongs.
            return [text(f"{name} містить return; додайте {line} перед ним самі.",
                         f"{name} has a return; add {line} before it by hand.")]
    current.include = [comment(text("Фрагмент Pentad для Hyprland", "Pentad's Hyprland fragment"), is_lua), line]
    current.append(current.include)
    return []

def unified_diff(draft: Draft, env) -> str:
    before = (draft.before or b"").decode("utf-8", "replace").splitlines()
    after = draft.after().decode("utf-8", "replace").splitlines()
    name = shown(draft.path, env)
    return "\n".join(difflib.unified_diff(before, after, name, name, lineterm="")) + "\n"

def describe(plan: Plan, env, text: doctor.Text, baseline: list[str] | None = None) -> str:
    out = [text("Налаштування Pentad", "Pentad setup")]
    if plan.found.holders:
        out += ["", text("Знайдено", "Found")] + ["  " + doctor.holder_title(holder, text) for holder in plan.found.holders]
    if plan.drafts or plan.units:
        out += ["", text("Зміни", "Changes")] + [unified_diff(draft, env).rstrip("\n") for draft in plan.drafts]
        out += [f"  systemctl --user mask {unit}" for unit in plan.units]
    if plan.manual:
        out += ["", text("Зробити вручну", "By hand")] + ["  " + item for item in plan.manual]
    notes = doctor.unchecked_notes(plan.found, text)
    if not env.get("HYPRLAND_INSTANCE_SIGNATURE"):
        notes.append(text("Зараз це не сеанс Hyprland, тож невідомо, хто малює шпалери й панелі, і зміни вище лише показано. "
                          "Запустіть pentad setup усередині сеансу Hyprland.",
                          "This is not a Hyprland session right now, so it is unknown who draws the wallpaper and panels, "
                          "and the changes above are only a preview. Run pentad setup inside a Hyprland session."))
    elif plan.found.explicit_config is not None:
        notes.extend(doctor.explicit_config_note(plan.found, env, text))
        notes.append(text("Зміни вище лише показано.", "The changes above are only a preview."))
    elif plan.bindings_added:
        notes.append(text("Hyprland перечитує конфігурацію, щойно файли змінюються, тож додані прив'язки клавіш діють одразу; "
                          "сама заміна оболонки відбудеться під час наступного входу в сеанс або зараз, якщо ви погодитеся після застосування.",
                          "Hyprland reloads its config when these files change, so the added key bindings take effect at once; "
                          "the shell switch itself happens at the next login, or now if you agree to it after applying."))
    elif plan.drafts or plan.units:
        notes.append(text("Зміни подіють під час наступного входу в сеанс або зараз, якщо ви погодитеся після застосування.",
                          "The changes take effect at the next login, or now if you agree to it after applying."))
    if plan.units:
        notes.append(text("Замаскована служба не зупиняється сама; вона не запуститься наступного разу.",
                          "A masked service is not stopped by this; it just does not start next time."))
    if plan.foreign_file:
        notes.append(text("Ці файли можуть належати до власного налаштування іншої оболонки, і її оновлення можуть повернути рядки. "
                          "Після такого оновлення запустіть pentad doctor.",
                          "These files may belong to another shell's own setup; its updates can bring the lines back. "
                          "Run pentad doctor after updating it."))
    notes.extend(doctor.activation_note(plan.found, env, text))
    if baseline:
        notes.append(text(f"Hyprland уже повідомляє про помилки в цій конфігурації ({len(baseline)}), тож pentad setup не зможе "
                          "підтвердити, що рядки Pentad завантажуються; спершу виправте їх (hyprctl configerrors).",
                          f"Hyprland already reports errors in this config ({len(baseline)}), so pentad setup cannot confirm that "
                          "Pentad's lines load; fix those first (hyprctl configerrors)."))
    if notes:
        out += ["", text("Зверніть увагу", "Heads-up")] + ["  " + note for note in notes]
    return "\n".join(out) + "\n"

def write_order(plan: Plan) -> list[Draft]:
    """Files setup creates or owns first, then other edited files, the entry file last.

    Hyprland reloads as soon as a loaded file is replaced, so the entry file must not point at a fragment
    that does not exist yet: hyprlang would report a source error and Lua would silently skip it.
    """
    def rank(draft: Draft) -> int:
        if draft.before is None or draft.role == "fragment":
            return 0
        return 2 if draft.path == plan.found.entry else 1
    return sorted(plan.drafts, key=rank)

def state_root(env) -> Path | None:
    if env.get("XDG_STATE_HOME"):
        return Path(env["XDG_STATE_HOME"]) / "pentad/setup"
    return Path(env["HOME"]) / ".local/state/pentad/setup" if env.get("HOME") else None

def write_atomically(path: Path, data: bytes) -> None:
    """Replace the file's contents in one step, keeping its mode; a new file gets the usual mode."""
    mode = stat.S_IMODE(path.stat().st_mode) if path.exists() else NEW_FILE_MODE
    path.parent.mkdir(parents=True, exist_ok=True)
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

def save_manifest(directory: Path, manifest: dict) -> None:
    (directory / "manifest.json").write_text(json.dumps(manifest, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")

# Hyprland does the checking: one reload on request, then `hyprctl configerrors`.

def config_errors(env) -> list[str] | None:
    """Hyprland's current config errors (empty strings dropped), or None when hyprctl cannot say."""
    hyprctl = doctor.which("hyprctl", env)
    output = doctor.run([hyprctl, "-j", "configerrors"], env) if hyprctl else None
    try:
        errors = json.loads(output or "")
    except ValueError:
        return None
    if not isinstance(errors, list) or not all(isinstance(error, str) for error in errors):
        return None
    return [error for error in errors if error.strip()]

def reload_and_read(env, text: doctor.Text) -> tuple[str, list[str]]:
    """Ask Hyprland for one reload and read its config errors afterwards.

    `hyprctl reload` runs the whole reload before it answers `ok` (reloadRequest in src/debug/HyprCtl.cpp
    calls Config::mgr()->reload(), which loads and runs the config in place), so the errors read next
    describe the files as they are now. Hyprland also reloads on its own whenever a loaded file is replaced;
    each of those reloads, and this one, runs the user's top-level Lua code again.
    Returns ("read", errors) or ("unknown", [reason]).
    """
    hyprctl = doctor.which("hyprctl", env)
    if hyprctl is None:
        return "unknown", [text("hyprctl не знайдено", "hyprctl not found")]
    reply = doctor.run([hyprctl, "reload"], env)
    if reply is None or reply.strip() != "ok":  # a failing request still exits 0; only the reply tells
        shown_reply = (reply or "").strip() or text("без відповіді", "no reply")
        return "unknown", [text(f"hyprctl reload не вдався ({shown_reply})", f"hyprctl reload failed ({shown_reply})")]
    errors = config_errors(env)
    if errors is None:
        return "unknown", [text("hyprctl configerrors не відповів після зміни", "hyprctl configerrors did not answer after the change")]
    return "read", errors

def verify_with_hyprland(baseline: list[str] | None, env, text: doctor.Text) -> tuple[str, list[str]]:
    """Reload, then compare Hyprland's config errors with the baseline.

    Returns ("ok", []), ("errors", new error lines) or ("unknown", [reason]).
    """
    if baseline is None:
        return "unknown", [text("hyprctl configerrors не відповів перед зміною", "hyprctl configerrors did not answer before the change")]
    state, details = reload_and_read(env, text)
    if state != "read":
        return state, details
    new = [error for error in details if error not in baseline]
    return ("errors", new) if new else ("ok", [])

def systemctl(env, *arguments: str) -> bool:
    executable = doctor.which("systemctl", env)
    return executable is not None and doctor.run([executable, "--user", *arguments], env) is not None

def is_mask_link(path: Path | None) -> bool:
    try:
        return path is not None and path.is_symlink() and os.readlink(path) == "/dev/null"
    except OSError:
        return False

def write_files(drafts: list[Draft], env, text: doctor.Text) -> tuple[list[Draft], str | None]:
    """Write the drafts in order, each after checking that the file still holds what the plan saw; stop at the first failure."""
    written: list[Draft] = []
    for draft in drafts:
        name = shown(draft.path, env)
        if read_or_none(draft.path) != draft.before:
            return written, text(f"{name} змінився після показу плану; його не записано.", f"{name} changed after the plan was shown; it was not written.")
        try:
            write_atomically(draft.path, draft.after())
        except OSError as error:
            return written, text(f"Не вдалося записати {name}: {error.strerror}.", f"Could not write {name}: {error.strerror}.")
        written.append(draft)
    return written, None

def restore_files(written: list[Draft], entry: Path | None, env, text: doctor.Text) -> list[str]:
    """Put every written file back (the entry file first, created files last) and name what could not be restored.

    A failure does not stop the rest, but a created fragment stays while the entry file still includes it,
    and a file that already holds its old bytes needs no write.
    """
    failures = []
    entry_failed = False
    order = sorted(written, key=lambda draft: (draft.before is None, draft.path != entry))
    for draft in order:
        name = shown(draft.path, env)
        if draft.before is None and entry_failed and draft.role == "fragment":
            failures.append(text(f"{name} (лишено: файл, що його підключає, не відновлено)", f"{name} (kept: the file that loads it was not restored)"))
            continue
        if read_or_none(draft.path) == draft.before:
            continue  # already back
        try:
            put_back(draft.path, draft.before)
        except OSError:
            failures.append(name)
            entry_failed = entry_failed or draft.path == entry
    return failures

def apply(plan: Plan, env, now: datetime, text: doctor.Text, hooks: Hooks, baseline: list[str] | None = None) -> tuple[list[str], int, bool]:
    """Back the files up, write them, mask the units, let Hyprland verify; undo it all when anything goes wrong.

    Returns the lines to print, the exit status, and whether the changes are in place and confirmed.
    """
    base = state_root(env)
    if base is None:
        return [text("Невідомо, де зберігати резервні копії: HOME не задано.", "Nowhere to keep backups: HOME is not set.")], 1, False
    try:
        state = new_state_directory(base, now)
        files = []
        for index, draft in enumerate(plan.drafts, 1):
            backup = None
            if draft.before is not None:
                backup = f"{index}-{draft.path.name}"
                (state / backup).write_bytes(draft.before)
            record = {"path": str(draft.path), "backup": backup, "sha256After": sha256(draft.after()), "role": draft.role}
            for key in ("commented", "include", "hidden"):
                if getattr(draft, key):
                    record[key] = list(getattr(draft, key))
            files.append(record)
        manifest = {"schemaVersion": SCHEMA_VERSION, "created": now.isoformat(), "files": files,
                    "units": [{"unit": unit, "mask": str(mask_path(unit, env))} for unit in plan.units], "verified": None}
        save_manifest(state, manifest)
    except OSError as error:
        return [text(f"Не вдалося зберегти резервні копії в {shown(base, env)}: {error.strerror}. Нічого не змінено.",
                     f"Could not save backups in {shown(base, env)}: {error.strerror}. Nothing changed.")], 1, False
    # Any `hyprctl dispatch` (a running shell sends them all the time) clears Hyprland's error list, so the
    # baseline is everything seen before the prompt and right before the write.
    before_write = config_errors(env)
    known = None if baseline is None and before_write is None else sorted(set(baseline or []) | set(before_write or []))
    written, failure = write_files(write_order(plan), env, text)
    masked: list[str] = []
    out: list[str] = []
    verdict, details = "unknown", []  # a failed write never reaches Hyprland's check
    if failure is None:
        for unit in plan.units:
            if systemctl(env, "mask", unit):
                masked.append(unit)
            else:
                out.append(text(f"Не вдалося замаскувати {unit}; вимкніть службу самі: systemctl --user disable --now {unit}",
                                f"Could not mask {unit}; disable the service yourself: systemctl --user disable --now {unit}"))
        manifest["units"] = [entry for entry in manifest["units"] if entry["unit"] in masked]
        verdict, details = verify_with_hyprland(known, env, text)
        if verdict == "errors":
            failure = text("Hyprland повідомляє про нові помилки конфігурації:", "Hyprland reports new config errors:")
            out.extend("  " + line for line in details)
    if failure is None:
        confirmed = verdict == "ok" and not known
        manifest["verified"] = confirmed
        with contextlib.suppress(OSError):
            save_manifest(state, manifest)
        if verdict == "unknown":
            out.append(text(f"Hyprland не підтвердив зміни ({details[0]}). Перевірте `hyprctl configerrors`; "
                            "скасувати можна командою `pentad setup --undo`.",
                            f"Hyprland did not confirm the changes ({details[0]}). Check `hyprctl configerrors`; "
                            "undo with `pentad setup --undo`."))
        elif known:
            out.append(text("Нових помилок нема, але Hyprland і далі повідомляє про старі, тож чи завантажуються рядки Pentad, невідомо; "
                            "виправте їх і запустіть pentad doctor.",
                            "No new errors, but Hyprland still reports the old ones, so whether Pentad's lines load is unknown; "
                            "fix them and run pentad doctor."))
        else:
            out.append(text("Hyprland перечитав конфігурацію без нових помилок.", "Hyprland reloaded the config without new errors."))
        out.append(text(f"Застосовано. Резервні копії: {shown(state, env)}; скасувати можна командою `pentad setup --undo`.",
                        f"Applied. Backups are in {shown(state, env)}; undo with `pentad setup --undo`."))
        return out, 0, confirmed
    out.insert(0, failure)
    unrestored = restore_files(written, plan.found.entry, env, text)
    for unit in masked:
        if not (is_mask_link(mask_path(unit, env)) and systemctl(env, "unmask", unit)):
            unrestored.append(unit)
    if written or masked:
        # The restore changes the files again; reload once more and say whether the config is clean now.
        state_after, after = reload_and_read(env, text)
        still = [error for error in after if error not in (known or [])] if state_after == "read" else []
        if still and verdict == "errors" and set(still) == set(details):
            # The same errors with and without Pentad's lines: they were there before, and a dispatch had
            # cleared the list the baseline was read from.
            out[0] = text("Hyprland повідомляє про помилки у вашій конфігурації, не пов'язані зі зміною Pentad:",
                          "Hyprland reports errors in your config that are not from Pentad's change:")
            out.append(text("Виправте їх, потім запустіть pentad setup знову.", "Fix them, then run pentad setup again."))
        elif still:
            out.append(text("Після відновлення Hyprland досі повідомляє про помилки:", "After the restore Hyprland still reports errors:"))
            out.extend("  " + line for line in still)
    if unrestored:
        out.append(text(f"Не вдалося відновити {', '.join(unrestored)}; резервні копії лежать у {shown(state, env)}, "
                        "а `pentad setup --undo` завершить відновлення.",
                        f"Could not restore {', '.join(unrestored)}; the backups are in {shown(state, env)}, "
                        "and `pentad setup --undo` finishes the restore."))
        manifest["rolledBack"] = "partial"  # the run stays open, so --undo can finish it
        with contextlib.suppress(OSError):
            save_manifest(state, manifest)
    else:
        if written or masked:
            out.append(text("Файли, записані до того, відновлено.", "The files written before it were restored."))
        shutil.rmtree(state, ignore_errors=True)
        out.append(text("Нічого не змінено.", "Nothing changed."))
    return out, 1, False

# Undo: by content when the file still holds what setup wrote, else by the markers.

def newest_manifest(base: Path) -> tuple[Path, dict] | None:
    """Return the newest setup run that has not been undone, with its manifest."""
    if not base.is_dir():
        return None
    for directory in sorted(base.iterdir(), reverse=True):
        try:
            manifest = json.loads((directory / "manifest.json").read_text(encoding="utf-8"))
        except (OSError, ValueError):
            continue
        if isinstance(manifest, dict) and manifest.get("schemaVersion") in (1, SCHEMA_VERSION) and "undone" not in manifest \
                and isinstance(manifest.get("files"), list):
            return directory, manifest
    return None

def unmarked(lines: list[str], entry: dict, is_lua: bool) -> tuple[list[str], list[str]]:
    """Reverse setup's marked edits by content: returns the new lines and the marked lines that were not found as written."""
    result = list(lines)
    leftovers = []

    def remove_pair(pair: list[str]) -> bool:
        for index in range(len(result) - 1):
            if result[index].rstrip("\r\n") == pair[0] and result[index + 1].rstrip("\r\n") == pair[1]:
                del result[index:index + 2]
                return True
        return False

    for pair in (entry.get("include"), entry.get("hidden")):
        if isinstance(pair, list) and len(pair) == 2 and not remove_pair(pair):
            leftovers.append(pair[1])
    for original in entry.get("commented") or []:
        expected = commented(original, is_lua)
        for index, line in enumerate(result):
            if line.rstrip("\r\n") == expected:
                newline = line[len(line.rstrip("\r\n")):]
                result[index] = original + newline
                break
        else:
            leftovers.append(commented(original, is_lua))
    return result, leftovers

def reloaded_after_undo(baseline: list[str] | None, env, text: doctor.Text) -> list[str]:
    """Reload once after the restores and say whether the config has errors now that were not there before."""
    state, errors = reload_and_read(env, text)
    if state != "read":
        return [text(f"Hyprland не підтвердив скасування ({errors[0]}).", f"Hyprland did not confirm the undo ({errors[0]}).")]
    new = [error for error in errors if error not in (baseline or [])]
    if not new:
        return []
    return [text("Після скасування Hyprland повідомляє про помилки конфігурації:", "After the undo Hyprland reports config errors:")] \
        + ["  " + line for line in new]

def undo(env, now: datetime, text: doctor.Text, stdin, hooks: Hooks | None = None) -> tuple[list[str], int]:
    """Restore the files of the newest setup run: by content where possible, by the markers after a user edit; unmask its units."""
    hooks = Hooks() if hooks is None else hooks
    base = state_root(env)
    run = newest_manifest(base) if base else None
    if run is None:
        return [text("Нема чого скасовувати.", "Nothing to undo.")], 1
    directory, manifest = run
    out, restored, failed, kept = [], 0, False, []
    hypr = doctor.hypr_directory(env)
    in_session = bool(env.get("HYPRLAND_INSTANCE_SIGNATURE"))
    baseline = config_errors(env) if in_session else None
    by_marker: list[tuple[Draft, dict, list[str]]] = []

    def is_entry(entry: dict) -> bool:
        path = Path(str(entry.get("path", "")))
        return path.parent == hypr and path.name in ("hyprland.lua", "hyprland.conf")

    # The entry file first, so nothing points at a fragment that is about to go; files setup created last,
    # since while a file that loads them stays as it is, they must stay too.
    created_entries = [entry for entry in manifest["files"] if entry.get("backup") is None]
    edited_entries = sorted((entry for entry in manifest["files"] if entry.get("backup") is not None), key=lambda entry: not is_entry(entry))
    for entry in edited_entries:
        path = Path(str(entry.get("path", "")))
        name = shown(path, env)
        backup = directory / Path(str(entry["backup"])).name
        current = read_or_none(path)
        if current is not None and current == read_or_none(backup):
            out.append(text(f"{name} уже відновлено.", f"{name} is already restored."))
            continue
        if current is None or sha256(current) != entry.get("sha256After"):
            if current is not None and any(entry.get(key) for key in ("commented", "include", "hidden")):
                draft = load(path)
                draft.lines, leftovers = unmarked(draft.lines, entry, path.suffix == ".lua")
                if draft.after() != draft.before:
                    by_marker.append((draft, entry, leftovers))
                    continue
            kept.append(name)
            out.append(text(f"Не відновлено {name}: його змінили після pentad setup; резервна копія: {shown(backup, env)}.",
                            f"Left {name} alone: it changed after pentad setup; the backup is {shown(backup, env)}."))
            continue
        try:
            put_back(path, backup.read_bytes())
            restored += 1
            out.append(text(f"Відновлено {name}.", f"Restored {name}."))
        except OSError as error:
            failed = True
            kept.append(name)
            out.append(text(f"Не вдалося відновити {name}: {error.strerror}.", f"Could not restore {name}: {error.strerror}."))
    if by_marker:
        # No longer a byte-for-byte restore, so the user sees and confirms it.
        out.append(text("Ці файли змінили після pentad setup; його позначені рядки можна скасувати так:",
                        "These files changed after pentad setup; its marked lines can be undone like this:"))
        out.extend(unified_diff(draft, env).rstrip("\n") for draft, _, _ in by_marker)
        for draft, _, leftovers in by_marker:
            for line in leftovers:
                out.append(text(f"  {shown(draft.path, env)}: позначений рядок змінено, його не чіпаємо: {line}",
                                f"  {shown(draft.path, env)}: a marked line was edited and is left alone: {line}"))
        sys.stdout.write("\n".join(out) + "\n")
        out = []
        if ask(stdin, text("Скасувати ці рядки? [y/N] ", "Undo these lines? [y/N] ")):
            for draft, _, _ in by_marker:
                name = shown(draft.path, env)
                if read_or_none(draft.path) != draft.before:
                    failed = True
                    kept.append(name)
                    out.append(text(f"{name} змінився щойно; його не записано.", f"{name} changed just now; it was not written."))
                    continue
                try:
                    write_atomically(draft.path, draft.after())
                    restored += 1
                    out.append(text(f"Знято позначені рядки в {name}.", f"Unmarked the lines in {name}."))
                except OSError as error:
                    failed = True
                    kept.append(name)
                    out.append(text(f"Не вдалося записати {name}: {error.strerror}.", f"Could not write {name}: {error.strerror}."))
        else:
            kept.extend(shown(draft.path, env) for draft, _, _ in by_marker)
            failed = True  # the run stays open: a later --undo may get a yes
            out.append(text("Позначені рядки лишено.", "The marked lines are left as they are."))
    for entry in created_entries:
        path = Path(str(entry.get("path", "")))
        name = shown(path, env)
        current = read_or_none(path)
        if current is None:
            out.append(text(f"{name} уже вилучено.", f"{name} is already removed."))
            continue
        if sha256(current) != entry.get("sha256After"):
            kept.append(name)
            out.append(text(f"Не вилучено {name}: його змінили після pentad setup.", f"Left {name} alone: it changed after pentad setup."))
            continue
        if kept:
            out.append(text(f"Не вилучено {name}: {', '.join(kept)} не відновлено й може його ще підключати.",
                            f"Left {name} alone: {', '.join(kept)} was left alone and may still load it."))
            continue
        if entry.get("role", "fragment") == "fragment" and (path.name not in FRAGMENT_NAMES or path.parent != hypr):
            out.append(text(f"Не вилучено {name}: це не фрагмент Pentad у теці Hyprland.",
                            f"Left {name} alone: it is not Pentad's fragment in the Hyprland folder."))
            continue
        try:
            put_back(path, None)
            restored += 1
            out.append(text(f"Вилучено {name}.", f"Removed {name}."))
        except OSError as error:
            failed = True
            out.append(text(f"Не вдалося вилучити {name}: {error.strerror}.", f"Could not remove {name}: {error.strerror}."))
    for entry in manifest.get("units") or []:
        unit, path = str(entry.get("unit", "")), Path(str(entry.get("mask", "")))
        if not unit:
            continue
        if not is_mask_link(path):
            out.append(text(f"Не знято маску з {unit}: {shown(path, env)} уже не посилання на /dev/null.",
                            f"Left {unit} masked: {shown(path, env)} is no longer the /dev/null link."))
        elif systemctl(env, "unmask", unit):
            restored += 1
            out.append(text(f"Знято маску з {unit}.", f"Unmasked {unit}."))
        else:
            failed = True
            out.append(text(f"Не вдалося зняти маску з {unit}: systemctl --user unmask {unit}", f"Could not unmask {unit}: systemctl --user unmask {unit}"))
    if restored and in_session:
        out.extend(reloaded_after_undo(baseline, env, text))
    if failed:
        return out, 1  # the run stays open so a second --undo can finish it
    manifest["undone"] = now.isoformat()
    try:
        save_manifest(directory, manifest)
    except OSError as error:
        out.append(text(f"Не вдалося позначити скасування в {shown(directory, env)}: {error.strerror}.",
                        f"Could not mark the undo in {shown(directory, env)}: {error.strerror}."))
        return out, 1
    return out, 0 if restored else 1

# Switching now: stop what this run took out of autostart, start Pentad the way the session would.

def pentad_start_command(root: Path, env) -> str | None:
    """`pentad start`, with --path when the launcher on PATH belongs to another install; None without a launcher."""
    launcher = doctor.which("pentad", env)
    if not launcher:
        return None
    try:
        default = (Path(launcher).resolve().parent.parent / "share/pentad/quickshell").resolve()
        same = default == root.resolve()
    except OSError:
        same = False
    return "pentad start" if same else f"pentad start --path {shlex.quote(str(root))}"

def dispatch_exec(command: str, is_lua: bool) -> list[str] | None:
    """The hyprctl arguments that run a command through the compositor; under a Lua config `dispatch` takes a Lua expression."""
    if not is_lua:
        return ["dispatch", "exec", command]
    if "'" in command or "\\" in command:
        return None
    return ["dispatch", f"hl.dsp.exec_cmd('{command}')"]

def wait_until(condition, timeout: float, hooks: Hooks) -> bool:
    deadline = hooks.clock() + timeout
    while True:
        if condition():
            return True
        if hooks.clock() >= deadline:
            return False
        hooks.sleep(POLL_INTERVAL)

def switch(plan: Plan, root: Path, env, system_root: Path, text: doctor.Text, hooks: Hooks) -> tuple[list[str], bool]:
    """Stop the holders this run disabled, start Pentad through Hyprland, and report who holds what now."""
    out = []
    alive = []
    originals = []
    for holder, unit in plan.stopped:
        label = holder.label or text("процес", "process")
        if unit:
            originals.append(f"systemctl --user unmask {unit} && systemctl --user start {unit}")
            if not systemctl(env, "stop", unit):
                out.append(text(f"Не вдалося зупинити {unit}.", f"Could not stop {unit}."))
                continue
            if not wait_until(lambda: not (system_root / f"proc/{holder.pid}").exists(), STOP_TIMEOUT, hooks):
                alive.append(f"{label} (pid {holder.pid})")
            continue
        originals.extend(line.strip() for draft in plan.drafts for line in draft.commented if holder.pid in draft.holders)
        # The process the start line started goes first: a launcher such as `dms run` would otherwise restart
        # its Quickshell child. The holder itself follows only if it is still alive.
        programs = set().union(*(draft.programs.get(holder.pid, set()) for draft in plan.drafts))
        launcher = holder.launchers[-1] if holder.launchers else None
        if launcher is not None and not (doctor.program_words(list(launcher.arguments), launcher.comm) & programs):
            launcher = None  # no commented line named it, so it is not the process the start line started
        targets = ([(launcher, " ".join(launcher.arguments)[:80])] if launcher is not None else []) + [(holder, label)]
        for process, name in targets:
            if not (system_root / f"proc/{process.pid}").exists():
                continue
            if not doctor.same_process(process, system_root):
                out.append(text(f"{name} (pid {process.pid}) уже не той процес або завершився; сигнал не надіслано.",
                                f"{name} (pid {process.pid}) is no longer the same process or has exited; no signal sent."))
                continue
            try:
                hooks.kill(process.pid, signal.SIGTERM)
            except ProcessLookupError:
                continue
            except OSError as error:
                out.append(text(f"Не вдалося зупинити {name} (pid {process.pid}): {error.strerror}.",
                                f"Could not stop {name} (pid {process.pid}): {error.strerror}."))
                continue
            if not wait_until(lambda: not (system_root / f"proc/{process.pid}").exists(), STOP_TIMEOUT, hooks):
                alive.append(f"{name} (pid {process.pid})")
    if alive:
        out.append(text(f"Досі працює: {', '.join(alive)}. Pentad його не вбиває; завершіть його самі або вийдіть із сеансу.",
                        f"Still running: {', '.join(alive)}. Pentad does not kill it; end it yourself or log out."))
    found = doctor.survey(root, env, system_root)
    if not found.pentad_roles:
        command = pentad_start_command(root, env)
        arguments = dispatch_exec(command, plan.lua) if command else None
        hyprctl = doctor.which("hyprctl", env)
        if arguments is None or hyprctl is None:
            out.append(text("Не вдалося скласти команду запуску Pentad через Hyprland; запустіть його самі: pentad start",
                            "Could not build the command that starts Pentad through Hyprland; start it yourself: pentad start"))
            return out + failure_hints(originals, text), False
        reply = doctor.run([hyprctl, *arguments], env)
        if reply is None or reply.strip() != "ok":  # a failing dispatch still exits 0; only the reply tells
            shown_reply = (reply or "").strip() or text("без відповіді", "no reply")
            out.append(text(f"hyprctl {' '.join(arguments)} не вдався ({shown_reply}); запустіть Pentad самі: {command}",
                            f"hyprctl {' '.join(arguments)} failed ({shown_reply}); start Pentad yourself: {command}"))
            return out + failure_hints(originals, text), False
    else:
        out.append(text("Pentad уже працює; його не запускали вдруге.", "Pentad is already running; it was not started again."))
    wanted = {"notifications", "panels"}  # the wallpaper appears only once one is chosen in Settings

    def taken_over() -> bool:
        nonlocal found
        found = doctor.survey(root, env, system_root)
        return wanted <= found.pentad_roles

    if wait_until(taken_over, SWITCH_TIMEOUT, hooks):
        names = ", ".join(text(*doctor.ROLE_NAMES[role]) for role in doctor.ROLE_NAMES if role in found.pentad_roles)
        out.append(text(f"Pentad тепер займає: {names}.", f"Pentad now holds: {names}."))
        return out, True
    held = ", ".join(text(*doctor.ROLE_NAMES[role]) for role in doctor.ROLE_NAMES if role in found.pentad_roles) or text("нічого", "nothing")
    out.append(text(f"Pentad за {SWITCH_TIMEOUT:g} с зайняв лише: {held}. Перевірте `pentad doctor` і `pentad logs`.",
                    f"Within {SWITCH_TIMEOUT:g} s Pentad took over only: {held}. Check `pentad doctor` and `pentad logs`."))
    return out + failure_hints(originals, text), False

def failure_hints(originals: list[str], text: doctor.Text) -> list[str]:
    out = []
    if originals:
        out.append(text("Щоб повернути попередню оболонку на цей сеанс, запустіть її так, як робив автозапуск:",
                        "To bring the previous shell back for this session, start it the way autostart did:"))
        out.extend("  " + line for line in dict.fromkeys(originals))
    out.append(text("Щоб повернути конфігурацію, виконайте `pentad setup --undo`.", "To restore the config, run `pentad setup --undo`."))
    return out

def ask(stdin, prompt: str) -> bool:
    sys.stdout.write(prompt)
    sys.stdout.flush()
    answer = stdin.readline()
    if not answer.endswith("\n"):
        sys.stdout.write("\n")
    return answer.strip().lower() in ("y", "yes")

def main(argv=None, env=None, system_root: Path = Path("/"), stdin=None, now: datetime | None = None, hooks: Hooks | None = None) -> int:
    parser = argparse.ArgumentParser(description="Switch the Hyprland config to Pentad after showing the changes and asking.")
    parser.add_argument("--root", type=Path, required=True, help="installed Pentad Quickshell root")
    parser.add_argument("--qs", default="qs", help="Quickshell executable (accepted for symmetry with pentad doctor)")
    parser.add_argument("--undo", action="store_true", help="restore the files of the last setup run")
    args = parser.parse_args(argv)
    env = os.environ if env is None else env
    stdin = sys.stdin if stdin is None else stdin
    now = datetime.now(timezone.utc) if now is None else now
    hooks = Hooks() if hooks is None else hooks
    text = doctor.Text(doctor.is_ukrainian(env))
    if args.undo:
        lines, status = undo(env, now, text, stdin, hooks)
        sys.stdout.write("\n".join(lines) + "\n")
        return status
    if not (args.root / "shell.qml").is_file():
        # Without the real root every Pentad process looks foreign and would be planned away.
        sys.stdout.write(text(f"Файлів Pentad не знайдено в {args.root}; перевірте --path або встановіть Pentad ще раз.",
                              f"Pentad files not found in {args.root}; check --path or install Pentad again.") + "\n")
        return 1
    plan = make_plan(doctor.survey(args.root, env, system_root), env, text)
    in_session = bool(env.get("HYPRLAND_INSTANCE_SIGNATURE"))
    baseline = config_errors(env) if in_session and (plan.drafts or plan.units) else None
    sys.stdout.write(describe(plan, env, text, baseline))
    if not in_session or plan.found.explicit_config is not None:
        return 1  # a preview only: without the session the other shell may be missed; with -c the files are not in use
    if not plan.drafts and not plan.units:
        sys.stdout.write("\n" + (text("Сам pentad setup нічого змінити не може; зробіть пункти вище вручну.",
                                      "pentad setup cannot make any of these changes itself; edit the items above by hand.") if plan.manual
                                 else text("Нічого змінювати: конфігурація Hyprland уже запускає Pentad.",
                                           "Nothing to change: the Hyprland config already starts Pentad.")) + "\n")
        return 0
    sys.stdout.write("\n")
    if not ask(stdin, text("Застосувати ці зміни? [y/N] ", "Apply these changes? [y/N] ")):
        sys.stdout.write(text("Нічого не змінено.", "Nothing changed.") + "\n")
        return 1
    lines, status, confirmed = apply(plan, env, now, text, hooks, baseline)
    sys.stdout.write("\n".join(lines) + "\n")
    if not confirmed:
        return status
    if not plan.stopped and plan.found.pentad_roles:
        return status
    sys.stdout.write("\n")
    if not ask(stdin, text("Перейти на Pentad зараз, не чекаючи наступного входу? [y/N] ",
                           "Switch to Pentad now instead of at the next login? [y/N] ")):
        sys.stdout.write(text("Гаразд, заміна відбудеться під час наступного входу в сеанс.", "All right, the switch happens at the next login.") + "\n")
        return status
    lines, switched = switch(plan, args.root, env, system_root, text, hooks)
    sys.stdout.write("\n".join(lines) + "\n")
    return 0 if switched else 1

if __name__ == "__main__":
    sys.exit(main())
