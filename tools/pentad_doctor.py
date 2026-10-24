#!/usr/bin/env python3
"""Report which programs and modules Pentad finds, without changing anything."""

from __future__ import annotations

import argparse
import glob
import importlib.util
import json
import os
import re
import shlex
import shutil
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path

sys.path.append(str(Path(__file__).resolve().parent))  # the lexer ships next to this file; appended so stdlib wins
import pentad_lua as lua  # noqa: E402

MINIMUM_QUICKSHELL = (0, 3, 2)
GEIST_URL = "https://github.com/vercel/geist-font"

@dataclass(frozen=True)
class Need:
    kind: str  # program, python or font
    name: str
    arch: str = ""

def program(name: str, arch: str = "") -> Need:
    return Need("program", name, arch if arch else name)

def python_module(name: str, arch: str) -> Need:
    return Need("python", name, arch)

def font(name: str, arch: str = "") -> Need:
    return Need("font", name, arch)

@dataclass(frozen=True)
class Feature:
    label_uk: str
    label_en: str
    needs: tuple[Need, ...]
    any_of: bool = False

# Arch package names come from the official repositories; programs without one show only their name.
FEATURES = (
    Feature("Знімки екрана", "Screenshots",
            (program("grim"), program("wl-copy", "wl-clipboard"), python_module("cairo", "python-cairo"))),
    Feature("Запис екрана", "Screen recording", (program("wf-recorder"),)),
    Feature("Історія буфера обміну", "Clipboard history", (program("cliphist"), program("wl-copy", "wl-clipboard"))),
    Feature("Запуск застосунків і посилань", "Opening apps and links",
            (program("gtk-launch", "gtk3"), program("xdg-open", "xdg-utils"))),
    Feature("Емодзі", "Emoji", (font("Noto Color Emoji", "noto-fonts-emoji"),)),
    Feature("Гучність", "Volume", (program("wpctl", "wireplumber"),)),
    Feature("Перемикання аудіовиходу", "Switching audio output", (program("pactl", "libpulse"),)),
    Feature("Візуалізатор звуку", "Audio visualizer", (program("cava"),)),
    Feature("Мережа і VPN", "Network and VPN", (program("nmcli", "networkmanager"),)),
    Feature("Bluetooth", "Bluetooth", (program("bluetoothctl", "bluez-utils"),)),
    Feature("Tailscale", "Tailscale", (program("tailscale"),)),
    # The shell talks to the daemon over D-Bus; powerprofilesctl only shows that the daemon is installed.
    Feature("Профілі живлення", "Power profiles",
            (program("powerprofilesctl", "power-profiles-daemon"), program("busctl", "systemd"))),
    Feature("Яскравість", "Brightness", (program("brightnessctl"), program("ddcutil")), any_of=True),
    Feature("Нічне світло", "Night light", (program("hyprsunset"),)),
    Feature("Піпетка кольору", "Color picker", (program("hyprpicker"),)),
    Feature("Не вимикати екран", "Keep awake", (program("systemd-inhibit", "systemd"),)),
    Feature("Дата й час", "Date and time", (program("timedatectl", "systemd"),)),
    Feature("Типові застосунки", "Default apps", (program("xdg-mime", "xdg-utils"),)),
    Feature("Сеанс: вимкнення, перезавантаження, вихід", "Session: power off, restart, log out",
            (program("busctl", "systemd"), program("loginctl", "systemd"))),
    # hypridle turns Super+L, idle and sleep into `pentad lock`; hyprlock takes over if that fails.
    Feature("Екран блокування", "Lock screen", (program("hypridle"),)),
    Feature("Запасний екран блокування", "Fallback lock screen", (program("hyprlock"),)),
    Feature("Тексти пісень, погода, обкладинки", "Lyrics, weather and album art", (program("curl"),)),
    Feature("Сповіщення від інструментів", "Notices from tools", (program("notify-send", "libnotify"),)),
    Feature("Вибір файлів", "File picker",
            (python_module("gi", "python-gobject"), program("zenity")), any_of=True),
    Feature("Попередній перегляд у Сховку", "Stash previews", (python_module("gi", "python-gobject"),)),
    Feature("Буфер обміну у Сховку", "Stash clipboard", (program("wl-copy", "wl-clipboard"), program("wl-paste", "wl-clipboard"))),
    Feature("Зображення і кольори шпалер", "Image tools and wallpaper colors", (program("magick", "imagemagick"),)),
    Feature("Аудіо- і відеоінструменти", "Audio and video tools", (program("ffmpeg"),)),
    Feature("Інструменти PDF", "PDF tools",
            (program("qpdf"), program("gs", "ghostscript"), program("pdftoppm", "poppler"),
             program("pdftotext", "poppler"))),
    Feature("Архіви", "Archives", (program("7z", "7zip"), program("zstd"))),
    Feature("Розпізнавання тексту", "Text recognition", (program("tesseract"),)),
    Feature("QR-коди", "QR codes", (program("zbarimg", "zbar"), program("qrencode"))),
    Feature("Переклад", "Translation", (program("trans", "translate-shell"), program("jq")), any_of=True),
    Feature("Віджет YAML", "YAML widget", (program("yq", "go-yq"),)),
    Feature("LocalSend", "LocalSend", (Need("program", "localsend"),)),
)

NOTIFICATIONS_NAME = "org.freedesktop.Notifications"
# Hyprland layer levels: 0 is background, 1 to 3 are bottom, top and overlay.
LAYER_ROLES = {"0": "wallpaper", "1": "panels", "2": "panels", "3": "panels"}
ROLE_NAMES = {"notifications": ("сповіщення", "notifications"), "wallpaper": ("шпалери", "wallpaper"),
              "panels": ("панелі та накладки", "panels and overlays")}
SHELL_FAMILY = {"qs", "quickshell"}
QUICKSHELL_SHORTCUT = re.compile(r"\bglobal\b.*\bquickshell:")  # hl.dsp.global("quickshell:x") or `global, quickshell:x`
PENTAD_SHORTCUT = re.compile(r"\bglobal\b.*\bpentad:")
PENTAD_START = re.compile(r"(?:^|[\s\"'(=/])pentad\s+start\b")
CONFIG_FILE_LIMIT = 256 * 1024
START_LINE_LIMIT = 5
# A program hosted by one of these is known by its script, never by the interpreter.
INTERPRETER = re.compile(r"python(?:3(?:\.\d+)?)?|node|nodejs|bun|deno|gjs|sh|bash|dash|zsh|fish|lua(?:jit|5\.\d)?|perl|ruby|php")
SHELL_INTERPRETER = re.compile(r"sh|bash|dash|zsh|fish")
# Names that say nothing about which shell this is: a config called `shell`, a script called `main`.
GENERIC_NAMES = frozenset({"shell", "quickshell", "config", "qs", "main", "init", "index", "app", "run", "start", "default",
                           "__main__"})
# Launchers that pass through to the real program; their names must not become words to search for.
WRAPPERS = frozenset({"uwsm", "app2unit", "systemd-run", "dbus-launch", "dbus-run-session", "env", "nohup", "setsid", "timeout",
                      "nice", "exec", "systemd-cat"})
# The parent chain stops here: the compositor, the session or a login manager started the process, not a launcher of its own.
SESSION_PROGRAMS = frozenset({"Hyprland", "hyprland", "systemd", "init", "start-hyprland", "login", "greetd", "sddm",
                              "sddm-helper", "gdm", "lightdm", "ly", "lemurs"})
ASSIGNMENT = re.compile(r"[A-Za-z_][A-Za-z0-9_]*=")
KNOWN_NOTIFIERS = frozenset({"mako", "dunst", "swaync", "fnott", "wired", "xfce4-notifyd", "notification-daemon", "deadd-notification-center"})
MAX_ANCESTORS = 32

class Text:
    def __init__(self, ukrainian: bool):
        self.ukrainian = ukrainian

    def __call__(self, uk: str, en: str) -> str:
        return uk if self.ukrainian else en

def is_ukrainian(env) -> bool:
    for key in ("LANGUAGE", "LC_ALL", "LC_MESSAGES", "LANG"):
        value = env.get(key, "")
        if value:
            return value.split(":")[0].startswith("uk")
    return False

def which(name: str, env) -> str | None:
    return shutil.which(name, path=env.get("PATH", os.defpath))

def run(command: list[str], env) -> str | None:
    try:
        result = subprocess.run(command, capture_output=True, text=True, timeout=5, env=dict(env))
    except (OSError, subprocess.SubprocessError):
        return None
    return result.stdout + result.stderr if result.returncode == 0 else None

def quickshell_version(qs: str, env) -> tuple[int, int, int] | None:
    executable = which(qs, env)
    output = run([executable, "--version"], env) if executable else None
    match = re.search(r"(\d+)\.(\d+)\.(\d+)", output or "")
    return tuple(int(part) for part in match.groups()) if match else None

def qt_directories(env, system_root: Path) -> tuple[list[Path], list[Path]]:
    """Return candidate Qt 6 QML and plugin directories, most specific first."""
    qml, plugins = [], []
    for tool, flag in (("qtpaths6", "--query"), ("qtpaths", "--query"), ("qmake6", "-query")):
        executable = which(tool, env)
        if not executable:
            continue
        for key, target in (("QT_INSTALL_QML", qml), ("QT_INSTALL_PLUGINS", plugins)):
            value = (run([executable, flag, key], env) or "").strip()
            if value:
                target.append(Path(value))
    for key in ("QML_IMPORT_PATH", "QML2_IMPORT_PATH"):
        qml.extend(Path(part) for part in env.get(key, "").split(":") if part)
    for pattern in ("usr/lib/qt6", "usr/lib64/qt6", "usr/lib/*/qt6"):
        for base in sorted(glob.glob(str(system_root / pattern))):
            qml.append(Path(base) / "qml")
            plugins.append(Path(base) / "plugins")
    return [path for path in qml if (path / "QtQuick/qmldir").is_file()], [path for path in plugins if path.is_dir()]

def font_families(env) -> set[str] | None:
    executable = which("fc-list", env)
    output = run([executable, ":", "family"], env) if executable else None
    if output is None:
        return None
    return {family.strip().lower() for line in output.splitlines() for family in line.split(",") if family.strip()}

def has(need: Need, env, families: set[str] | None) -> bool | None:
    if need.kind == "program":
        return which(need.name, env) is not None
    if need.kind == "python":
        return importlib.util.find_spec(need.name) is not None
    if families is None:
        return None
    return need.name.lower() in families

def notification_owners(env) -> list[int] | None:
    """Return the pids owning the notification name on the session bus, or None when it cannot be checked."""
    busctl = which("busctl", env)
    if not busctl:
        return None
    call = [busctl, "--user", "call", "org.freedesktop.DBus", "/org/freedesktop/DBus", "org.freedesktop.DBus"]
    owned = run(call + ["NameHasOwner", "s", NOTIFICATIONS_NAME], env)
    answer = re.fullmatch(r"b (true|false)", (owned or "").strip())
    if not answer:
        return None
    if answer.group(1) == "false":
        return []
    owner = run(call + ["GetConnectionUnixProcessID", "s", NOTIFICATIONS_NAME], env)
    pid = re.fullmatch(r"u (\d+)", (owner or "").strip())
    return [int(pid.group(1))] if pid else None

def layer_holders(env) -> dict[int, set[str]] | None:
    """Return the roles (wallpaper, panels) each pid draws on Hyprland layers, or None when it cannot be checked."""
    hyprctl = which("hyprctl", env)
    output = run([hyprctl, "-j", "layers"], env) if hyprctl else None
    holders: dict[int, set[str]] = {}
    try:
        for monitor in json.loads(output or "").values():
            for level, layers in monitor["levels"].items():
                for layer in layers:
                    pid = layer["pid"]
                    if level in LAYER_ROLES and isinstance(pid, int) and pid > 0:
                        holders.setdefault(pid, set()).add(LAYER_ROLES[level])
    except (ValueError, KeyError, TypeError, AttributeError):
        return None
    return holders

def read_proc(pid: int, name: str, system_root: Path) -> str:
    try:
        return (system_root / f"proc/{pid}/{name}").read_text(encoding="utf-8", errors="replace")
    except OSError:
        return ""

def command_line(pid: int, system_root: Path) -> list[str]:
    return [argument for argument in read_proc(pid, "cmdline", system_root).split("\0") if argument]

def proc_stat(pid: int, system_root: Path) -> list[str]:
    """The fields of /proc/<pid>/stat after the command name, so index 1 is the parent, 4 the tty, 19 the start time."""
    text = read_proc(pid, "stat", system_root)
    close = text.rfind(")")  # the name is in parentheses and may itself hold spaces or parentheses
    return text[close + 1:].split() if close >= 0 else []

def parent_pid(pid: int, system_root: Path) -> int | None:
    fields = proc_stat(pid, system_root)
    return int(fields[1]) if len(fields) > 1 and fields[1].isdigit() else None

def has_tty(pid: int, system_root: Path) -> bool:
    fields = proc_stat(pid, system_root)
    return len(fields) > 4 and fields[4] != "0"

def start_time(pid: int, system_root: Path) -> str:
    """The process start time in clock ticks; with the command line it tells a reused pid from the same process."""
    fields = proc_stat(pid, system_root)
    return fields[19] if len(fields) > 19 else ""

def nix_unwrapped(name: str) -> str:
    """Nix wraps programs as .name-wrapped, and comm cuts that to 15 characters (.quickshell-wra)."""
    match = re.fullmatch(r"\.(.+?)-wra(?:p|pp|ppe|pped)?", name)
    return match.group(1) if match else name

def first_program(command: str) -> str:
    """The program a shell command runs, past a leading [rules] block, `uwsm app --` and `env VAR=value`."""
    command = command.strip()
    if command.startswith("["):
        close = command.find("]")
        command = command[close + 1:] if close >= 0 else ""
    words = command.split()
    if words and words[0] == "uwsm" and "--" in words:
        words = words[words.index("--") + 1:]
    while words and (words[0] == "env" or ASSIGNMENT.match(words[0])):
        words = words[1:]
    return Path(words[0]).name if words else ""

def script_word(path: str) -> str:
    """The name a script is known by: its stem, or `<folder>/<file>` when the stem says nothing (main.py)."""
    script = Path(path)
    return f"{script.parent.name}/{script.name}" if script.stem in GENERIC_NAMES and script.parent.name else script.stem

def script_words(program: str, arguments: list[str]) -> set[str]:
    """What an interpreter runs: the script's name, or for `sh -c` the command's first program; empty when interactive."""
    rest = arguments[1:]
    for index, argument in enumerate(rest):
        if argument == "-c" and SHELL_INTERPRETER.fullmatch(program):
            command = first_program(rest[index + 1]) if index + 1 < len(rest) else ""
            return set() if not command or INTERPRETER.fullmatch(command) else {command}
        if argument in ("-c", "-e") or argument.startswith("--"):
            return set()  # inline code, or an option whose value cannot be told from a script
        if argument.startswith("-"):
            continue
        return {script_word(argument)}
    return set()

def quickshell_words(arguments: list[str]) -> set[str]:
    """The config name of a Quickshell instance (`-c NAME`), or the folder or file name behind `-p PATH`."""
    names = set()
    for index, argument in enumerate(arguments):
        value = None
        if argument in ("-c", "--config", "-p", "--path") and index + 1 < len(arguments):
            value = arguments[index + 1]
        elif argument.startswith(("--config=", "--path=")):
            value = argument.split("=", 1)[1]
        if value is None:
            continue
        name = Path(value).name if argument[:2] in ("-p", "--") and "/" in value else value
        if name.endswith(".qml"):
            name = name[:-4]
        if name in GENERIC_NAMES and "/" in value:
            name = Path(value).parent.name
        names.add(name)
        if name.endswith("-shell"):  # noctalia-shell is started as `noctalia`
            names.add(name[:-len("-shell")])
    return names - GENERIC_NAMES - {""}

def program_words(arguments: list[str], comm: str) -> set[str]:
    """The words one process is known by: its program, its script under an interpreter, its Quickshell config."""
    program = nix_unwrapped(Path(arguments[0]).name if arguments else comm.strip())
    if INTERPRETER.fullmatch(program):
        return script_words(program, arguments)
    words = {program, nix_unwrapped(comm.strip())} - {""}
    if words & SHELL_FAMILY:
        words |= SHELL_FAMILY | quickshell_words(arguments)
    return words - WRAPPERS

def holder_words(pid: int, arguments: list[str], comm: str, system_root: Path) -> set[str]:
    """The process's own words plus those of the launchers above it, up to the compositor or the session.

    A shell such as DankMaterialShell is started as `dms run`, which then runs Quickshell; the config
    names the launcher, so the launcher's name has to be a word. The walk stops at anything a user
    started by hand (a process with a terminal, or an interactive shell).
    """
    words = program_words(arguments, comm)
    seen = {pid}
    current = parent_pid(pid, system_root)
    for _ in range(MAX_ANCESTORS):
        if current is None or current <= 1 or current in seen:
            break
        seen.add(current)
        ancestor_arguments = command_line(current, system_root)
        ancestor_comm = read_proc(current, "comm", system_root).strip()
        program = nix_unwrapped(Path(ancestor_arguments[0]).name if ancestor_arguments else ancestor_comm)
        if program in SESSION_PROGRAMS or has_tty(current, system_root):
            break
        more = program_words(ancestor_arguments, ancestor_comm)
        if not more and INTERPRETER.fullmatch(program):
            break
        words |= more
        current = parent_pid(current, system_root)
    return words

def is_pentad(arguments: list[str], root: Path) -> bool:
    """True when the command line has --path (or -p) pointing at this Pentad root."""
    for index, argument in enumerate(arguments):
        if argument in ("--path", "-p") and index + 1 < len(arguments):
            value = arguments[index + 1]
        elif argument.startswith("--path="):
            value = argument[len("--path="):]
        else:
            continue
        try:
            if Path(value).resolve() == root.resolve():
                return True
        except (OSError, RuntimeError):
            continue
    return False

def systemd_service(pid: int, words: set[str], system_root: Path) -> str | None:
    """Return the systemd service named after the process, judged by its cgroup.

    A child inherits its parent's cgroup, so a shell started from a terminal service
    (foot-server.service, tmux.service) must not be taken for that service.
    """
    for line in read_proc(pid, "cgroup", system_root).splitlines():
        if line.startswith("0::"):
            unit = line[3:].rsplit("/", 1)[-1]
            if unit.endswith(".service") and "@" not in unit and unit.removesuffix(".service") in words:
                return unit
    return None

def hypr_directory(env) -> Path | None:
    if env.get("XDG_CONFIG_HOME"):
        return Path(env["XDG_CONFIG_HOME"]) / "hypr"
    return Path(env["HOME"]) / ".config/hypr" if env.get("HOME") else None

def shown_path(path: Path, env) -> str:
    home = env.get("HOME")
    if home:
        try:
            return "~/" + path.relative_to(home).as_posix()
        except ValueError:
            pass
    return str(path)

def without_comment(line: str, is_lua: bool) -> str:
    """Cut a trailing comment: `#` in hyprlang, `--` outside strings in Lua (so `uwsm app -- waybar` survives)."""
    if not is_lua:
        return line.split("#", 1)[0]
    codes = lua.code_lines(line)
    return codes[0] if codes else ""

def code_lines(content: str, is_lua: bool) -> list[str]:
    """Every line of a config file without comments; Lua lines inside long comments or strings are empty."""
    if is_lua:
        return lua.code_lines(content)
    return [without_comment(line, False) for line in content.splitlines()]

def config_lines(directory: Path) -> list[tuple[Path, int, str]]:
    """Return every line of the *.lua and *.conf files under the directory, with comments removed."""
    lines = []
    for current, directories, files in os.walk(directory):
        directories[:] = sorted(name for name in directories if not name.startswith("."))
        for name in sorted(files):
            path = Path(current) / name
            if path.suffix not in (".lua", ".conf"):
                continue
            try:
                if path.stat().st_size > CONFIG_FILE_LIMIT:
                    continue
                content = path.read_text(encoding="utf-8", errors="replace")
            except OSError:
                continue
            lines.extend((path, number, line) for number, line in enumerate(code_lines(content, path.suffix == ".lua"), 1))
    return lines

@dataclass(frozen=True)
class Place:
    path: Path
    number: int  # 1-based line number

@dataclass(frozen=True)
class AutostartEntry:
    """An XDG autostart entry in effect (a user file shadows a system file of the same name)."""
    path: Path
    user: bool  # lives in the user's autostart folder, so it can be edited in place
    program: str  # the first program of its Exec line
    hidden_key: bool  # the [Desktop Entry] group already has a Hidden key

@dataclass(frozen=True)
class Activation:
    """A D-Bus activation file for the notification name: what the bus would start on request."""
    path: Path
    program: str
    unit: str | None  # SystemdService=, when the bus hands the start to systemd

@dataclass(frozen=True)
class Holder:
    """A foreign process that holds notifications or screen surfaces, and where the session runs it."""
    pid: int
    label: str  # the command line cut to 80 characters, else the comm name, else empty
    roles: frozenset[str]
    unit: str | None  # the systemd user service named after it
    starts: tuple[Place, ...]
    calls: tuple[Place, ...]
    bindings: int
    words: frozenset[str]  # the command words the config was searched for
    autostart: tuple[AutostartEntry, ...] = ()  # XDG autostart entries that run it
    start_time: str = ""  # /proc start time, to tell the same process from a reused pid later
    arguments: tuple[str, ...] = ()

@dataclass(frozen=True)
class Survey:
    """Everything the doctor and `pentad setup` know about the other shell and the Hyprland config."""
    directory: Path | None  # the hypr config directory, when its location is known
    entry: Path | None  # hyprland.lua when it exists, else hyprland.conf; None without a config directory
    holders: tuple[Holder, ...]
    pentad_starts: tuple[Place, ...]  # non-binding lines that run `pentad start`
    bindings_file: Path | None  # the shipped key bindings, when the runtime has them
    bindings_loads: tuple[Place, ...]  # lines that load or copy them
    unchecked: tuple[str, ...]  # probes that could not run: notifications, layers
    pentad_roles: frozenset[str] = frozenset()  # what Pentad itself holds right now
    explicit_config: Path | None = None  # the file Hyprland was started with (-c) when it is not the entry file
    activation: Activation | None = None  # a D-Bus activation file for notifications that names another daemon

def desktop_entry(path: Path) -> dict[str, str] | None:
    """The keys of the [Desktop Entry] group (unlocalised), or None when the file cannot be read."""
    try:
        content = path.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return None
    keys, inside = {}, False
    for line in content.splitlines():
        line = line.strip()
        if line.startswith("["):
            inside = line == "[Desktop Entry]"
        elif inside and "=" in line and not line.startswith("#"):
            key, value = line.split("=", 1)
            keys.setdefault(key.strip(), value.strip())
    return keys

def exec_program(value: str) -> str:
    """The first program of a desktop Exec line, without field codes."""
    try:
        words = shlex.split(value)
    except ValueError:
        words = value.split()
    return first_program(" ".join(word for word in words if not word.startswith("%")))

def autostart_directories(env, system_root: Path) -> list[tuple[Path, bool]]:
    user = Path(env["XDG_CONFIG_HOME"]) if env.get("XDG_CONFIG_HOME") else Path(env["HOME"]) / ".config" if env.get("HOME") else None
    directories = [(user / "autostart", True)] if user else []
    system = env.get("XDG_CONFIG_DIRS", "").split(":") if env.get("XDG_CONFIG_DIRS") else [str(system_root / "etc/xdg")]
    directories.extend((Path(base) / "autostart", False) for base in system if base)
    return directories

def autostart_entries(env, system_root: Path) -> list[AutostartEntry]:
    """Every XDG autostart entry that would run in a Hyprland session; the first folder wins for a name."""
    entries: dict[str, AutostartEntry | None] = {}
    for directory, user in autostart_directories(env, system_root):
        try:
            names = sorted(path.name for path in directory.iterdir() if path.suffix == ".desktop")
        except OSError:
            continue
        for name in names:
            if name in entries:
                continue
            keys = desktop_entry(directory / name)
            entries[name] = None
            if keys is None or keys.get("Type", "Application") != "Application" or not keys.get("Exec"):
                continue
            if keys.get("Hidden", "").lower() == "true":
                continue
            shown_in = [item for item in keys.get("OnlyShowIn", "").split(";") if item]
            if (shown_in and "Hyprland" not in shown_in) or "Hyprland" in keys.get("NotShowIn", "").split(";"):
                continue
            entries[name] = AutostartEntry(directory / name, user, exec_program(keys["Exec"]), "Hidden" in keys)
    return [entry for entry in entries.values() if entry is not None]

def data_directories(env, system_root: Path) -> list[Path]:
    user = Path(env["XDG_DATA_HOME"]) if env.get("XDG_DATA_HOME") else Path(env["HOME"]) / ".local/share" if env.get("HOME") else None
    directories = [user] if user else []
    system = env.get("XDG_DATA_DIRS", "").split(":") if env.get("XDG_DATA_DIRS") else ["usr/local/share", "usr/share"]
    directories.extend(system_root / base if not Path(base).is_absolute() else Path(base) for base in system if base)
    return directories

def notifications_activation(env, system_root: Path) -> Activation | None:
    """The D-Bus activation file that would start a daemon for the notification name, if any."""
    for directory in data_directories(env, system_root):
        try:
            paths = sorted((directory / "dbus-1/services").glob("*.service"))
        except OSError:
            continue
        for path in paths:
            try:
                content = path.read_text(encoding="utf-8", errors="replace")
            except OSError:
                continue
            keys = dict(line.strip().split("=", 1) for line in content.splitlines() if "=" in line and not line.startswith("#"))
            if keys.get("Name", "").strip() == NOTIFICATIONS_NAME and keys.get("Exec"):
                unit = keys.get("SystemdService", "").strip() or None
                return Activation(path, exec_program(keys["Exec"]), unit)
    return None

def hyprland_pid(env) -> int | None:
    """The pid of the running Hyprland instance, from hyprctl's instance list."""
    signature = env.get("HYPRLAND_INSTANCE_SIGNATURE")
    hyprctl = which("hyprctl", env)
    output = run([hyprctl, "-j", "instances"], env) if hyprctl and signature else None
    try:
        for instance in json.loads(output or ""):
            if instance.get("instance") == signature and isinstance(instance.get("pid"), int):
                return instance["pid"]
    except (ValueError, AttributeError, TypeError):
        return None
    return None

def hyprland_config_in_use(env, system_root: Path) -> Path | None:
    """The config file Hyprland was told to use with -c/--config or HYPRLAND_CONFIG, else None for the default."""
    pid = hyprland_pid(env)
    if pid is None:
        return None
    arguments = command_line(pid, system_root)
    for index, argument in enumerate(arguments):
        if argument in ("-c", "--config") and index + 1 < len(arguments):
            return Path(arguments[index + 1])
        if argument.startswith("--config="):
            return Path(argument[len("--config="):])
    for variable in read_proc(pid, "environ", system_root).split("\0"):
        if variable.startswith("HYPRLAND_CONFIG=") and variable[len("HYPRLAND_CONFIG="):]:
            return Path(variable[len("HYPRLAND_CONFIG="):])
    return None

def find_starts(words: set[str], lines: list[tuple[Path, int, str]]) -> tuple[list[Place], list[Place], int]:
    """Return the lines that start the program, the lines that only call the running one, and the key binding count."""
    if not words:
        return [], [], 0
    alternatives = "|".join(re.escape(word) for word in sorted(words))
    pattern = re.compile(rf"(?:^|[\s\"'(=/])(?:{alternatives})(?=$|[\s\"')])")
    starts, calls, bindings = [], [], 0
    for path, number, line in lines:
        runs = "exec" in line and pattern.search(line)
        # A Quickshell config without its own appid registers its global shortcuts as quickshell:<name>.
        shortcut = bool(words & SHELL_FAMILY) and QUICKSHELL_SHORTCUT.search(line)
        if "bind" in line and (runs or shortcut):
            bindings += 1
        elif runs:
            # `qs -c ii ipc call …` talks to the running shell, often inside a line that does other work.
            talks = all(re.match(r"[^;&|\"')]*\bipc\b", line[match.end():]) for match in pattern.finditer(line))
            (calls if talks else starts).append(Place(path, number))
    return starts, calls, bindings

def describe_holder(pid: int, roles: set[str], lines: list[tuple[Path, int, str]], system_root: Path,
                    autostart: list[AutostartEntry] = ()) -> Holder:
    arguments = command_line(pid, system_root)
    comm = read_proc(pid, "comm", system_root).strip()
    words = holder_words(pid, arguments, comm, system_root)
    starts, calls, bindings = find_starts(words, lines)
    entries = tuple(entry for entry in autostart if entry.program and entry.program in words)
    return Holder(pid, " ".join(arguments)[:80] or comm, frozenset(roles), systemd_service(pid, words, system_root),
                  tuple(starts), tuple(calls), bindings, frozenset(words), entries, start_time(pid, system_root), tuple(arguments))

def same_process(holder: Holder, system_root: Path) -> bool:
    """True while the holder's pid still belongs to the process the survey saw."""
    return (start_time(holder.pid, system_root) == holder.start_time
            and tuple(command_line(holder.pid, system_root)) == holder.arguments)

def survey(root: Path, env, system_root: Path) -> Survey:
    """Probe who holds notifications and screen surfaces, then scan the Hyprland config for them and for Pentad."""
    holders: dict[int, set[str]] = {}
    unchecked = []
    owners = notification_owners(env)
    if owners is None:
        unchecked.append("notifications")
    for pid in owners or []:
        holders.setdefault(pid, set()).add("notifications")
    if env.get("HYPRLAND_INSTANCE_SIGNATURE"):
        layers = layer_holders(env)
        if layers is None:
            unchecked.append("layers")
        for pid, roles in (layers or {}).items():
            holders.setdefault(pid, set()).update(roles)
    foreign = {pid: roles for pid, roles in holders.items() if not is_pentad(command_line(pid, system_root), root)}
    pentad_roles = frozenset(role for pid, roles in holders.items() if pid not in foreign for role in roles)
    directory = hypr_directory(env)
    lines = config_lines(directory) if directory else []
    entry = None
    if directory and directory.is_dir():
        entry = directory / "hyprland.lua"
        if not entry.is_file():
            entry = directory / "hyprland.conf"
    explicit = hyprland_config_in_use(env, system_root) if env.get("HYPRLAND_INSTANCE_SIGNATURE") else None
    if explicit is not None and entry is not None:
        try:
            if explicit.resolve() == entry.resolve():
                explicit = None
        except OSError:
            pass
    bindings_file = root / "defaults/hyprland-quickshell.lua"
    # Already loaded: a dofile of the shipped file, or a copy of it inside the config.
    loads = tuple(Place(path, number) for path, number, line in lines
                  if bindings_file.name in line or ("bind" in line and PENTAD_SHORTCUT.search(line)))
    starts = tuple(Place(path, number) for path, number, line in lines
                   if "exec" in line and "bind" not in line and PENTAD_START.search(line))
    autostart = autostart_entries(env, system_root)
    described = tuple(describe_holder(pid, foreign[pid], lines, system_root, autostart) for pid in sorted(foreign))
    activation = notifications_activation(env, system_root)
    if activation is not None and not (activation.program in KNOWN_NOTIFIERS
                                       or any(activation.program in holder.words or (activation.unit and activation.unit == holder.unit)
                                              for holder in described)):
        activation = None  # a bystander such as a desktop's name waiter; not worth a warning
    return Survey(directory, entry, described, starts, bindings_file if bindings_file.is_file() else None, loads,
                  tuple(unchecked), pentad_roles, explicit, activation)

def holder_title(holder: Holder, text: Text) -> str:
    label = holder.label or text("процес", "process")
    names = ", ".join(text(*ROLE_NAMES[role]) for role in ROLE_NAMES if role in holder.roles)
    return text(f"{label} (pid {holder.pid}) займає: {names}.", f"{label} (pid {holder.pid}) holds: {names}.")

def shown_place(place: Place, env) -> str:
    return f"{shown_path(place.path, env)}:{place.number}"

def listed(prefix: str, places: list[str], text: Text) -> list[str]:
    indent = " " * len(prefix)
    out = [prefix + places[0]] + [indent + place for place in places[1:START_LINE_LIMIT]]
    if len(places) > START_LINE_LIMIT:
        more = len(places) - START_LINE_LIMIT
        out.append(indent + text(f"і ще {more}", f"and {more} more"))
    return out

def pentad_bindings_hint(found: Survey, text: Text) -> list[str]:
    bindings = found.bindings_file
    if not bindings or found.bindings_loads:
        return []
    if found.entry and found.entry.suffix == ".lua":
        line = f'dofile("{bindings}")'
        return [text(f"Прив'язки Pentad спершу знімають клавіші, які він використовує: додайте {line} у кінець своїх прив'язок.",
                     f"Pentad's key bindings unbind the keys it uses first: add {line} at the end of your key bindings.")]
    return [text(f"Прив'язки клавіш Pentad лежать у {bindings}; скопіюйте потрібні.",
                 f"Pentad's key bindings are in {bindings}; copy the ones you want.")]

def autostart_sentence(entry: AutostartEntry, env, text: Text) -> str:
    place = shown_path(entry.path, env)
    return text(f"Запускається записом автозапуску XDG {place}.", f"Started by the XDG autostart entry {place}.")

def holder_paragraph(holder: Holder, found: Survey, env, text: Text) -> str:
    out = [holder_title(holder, text)]
    if holder.unit:
        command = f"systemctl --user disable --now {holder.unit}"
        out.append(text(f"Працює як користувацька служба systemd {holder.unit}: `pentad setup` замаскує її, "
                        f"або вимкніть самі: {command}",
                        f"Runs as the systemd user service {holder.unit}: `pentad setup` masks it, "
                        f"or disable it yourself: {command}"))
        out.extend(autostart_sentence(entry, env, text) for entry in holder.autostart)
    else:
        out.extend(autostart_sentence(entry, env, text) for entry in holder.autostart)
        place = shown_path(found.directory, env) if found.directory else ""
        if holder.starts:
            out.extend(listed(text("Запускається з ", "Started from "), [shown_place(p, env) for p in holder.starts], text))
        elif holder.autostart:
            pass  # the autostart entry above is where it starts
        elif place:
            out.append(text(f"Pentad не знайшов рядка його запуску в {place}. Якщо ви вже прибрали цей рядок, "
                            "процес лишився з поточного сеансу: вийдіть і зайдіть знову. "
                            "Інакше перевірте цю теку й автозапуск сеансу.",
                            f"Pentad found no start line for it in {place}. If you already removed it, "
                            "it is still running from this session: log out and back in. "
                            "Otherwise check that folder and your session's autostart."))
        else:
            out.append(text("Рядок його запуску не шукали: невідомо, де лежить конфігурація Hyprland; "
                            "перевірте автозапуск вашого сеансу.",
                            "Its start line was not searched for because the Hyprland config location is unknown; "
                            "check your session's autostart."))
        if holder.calls:
            out.extend(listed(text("Викликається з ", "Also called from "), [shown_place(p, env) for p in holder.calls], text))
            out.append(text("Ці рядки можуть робити й іншу роботу: змініть їх, щоб вони його не викликали, а не видаляйте.",
                            "These lines may do other work too: change them so they stop calling it rather than delete them."))
        if holder.bindings:
            out.append(text(f"Його також викликають прив'язки клавіш: {holder.bindings} (у {place}).",
                            f"Also called by {holder.bindings} key {'binding' if holder.bindings == 1 else 'bindings'} in {place}."))
            out.extend(pentad_bindings_hint(found, text))
    if holder.starts or holder.unit or holder.autostart:  # only then can setup act on this holder
        out.append(text("Приберіть його з автозапуску й запустіть Pentad командою `pentad start`, "
                        "потім знову запустіть pentad doctor, або виконайте `pentad setup`, і він зробить це за вас.",
                        "Remove it from autostart and start Pentad with `pentad start`, then run pentad doctor again, "
                        "or run `pentad setup` to do that for you."))
    else:
        out.append(text("Приберіть його з автозапуску й запустіть Pentad командою `pentad start`, "
                        "потім знову запустіть pentad doctor.",
                        "Remove it from autostart and start Pentad with `pentad start`, then run pentad doctor again."))
    return "\n".join(out[:1] + ["  " + line for line in out[1:]])

def unchecked_notes(found: Survey, text: Text) -> list[str]:
    notes = {"notifications": text("Не вдалося перевірити, хто показує сповіщення: busctl відсутній або не відповів.",
                                   "Could not check who shows notifications: busctl is missing or did not answer."),
             "layers": text("Не вдалося перевірити шпалери й панелі: hyprctl -j layers не відповів.",
                            "Could not check wallpaper and panels: hyprctl -j layers did not answer.")}
    return [notes[probe] for probe in found.unchecked]

def explicit_config_note(found: Survey, env, text: Text) -> list[str]:
    """Say when Hyprland runs a config file other than the one in the hypr folder, so edits there would not count."""
    if found.explicit_config is None:
        return []
    config, directory = shown_path(found.explicit_config, env), shown_path(found.directory, env) if found.directory else "~/.config/hypr"
    return [text(f"Hyprland запущено з конфігурацією {config}, тож файли в {directory} зараз не використовуються; "
                 "pentad setup їх не змінюватиме, лише покаже план.",
                 f"Hyprland was started with the config {config}, so the files in {directory} are not the ones in use; "
                 "pentad setup will not edit them and only shows its plan.")]

def activation_note(found: Survey, env, text: Text) -> list[str]:
    """A heads-up about a D-Bus activation file that would start another notification daemon on demand."""
    activation = found.activation
    if activation is None:
        return []
    place = shown_path(activation.path, env)
    if activation.unit:
        return [text(f"Файл активації D-Bus {place} запускає службу {activation.unit}, щойно хтось попросить сповіщення, "
                     "поки жоден сервер сповіщень не працює; замаскована служба не запуститься.",
                     f"The D-Bus activation file {place} starts the service {activation.unit} as soon as something asks for "
                     "notifications while no notification server runs; a masked service does not start.")]
    return [text(f"Файл активації D-Bus {place} запускає {activation.program}, щойно хтось попросить сповіщення, "
                 "поки жоден сервер сповіщень не працює. Pentad показує сповіщення сам, тож запускайте його раніше за "
                 f"такі програми; якщо {activation.program} повертається, причина в цьому файлі (з його пакета).",
                 f"The D-Bus activation file {place} starts {activation.program} as soon as something asks for notifications "
                 f"while no notification server runs. Pentad shows notifications itself, so start it before such programs; "
                 f"if {activation.program} keeps coming back, that file (from its package) is why.")]

def shell_conflicts(found: Survey, env, text: Text) -> list[str]:
    """Return one paragraph per foreign process holding notifications or screen surfaces, a note when nothing
    in the Hyprland config starts Pentad, then what could not be checked."""
    return ([holder_paragraph(holder, found, env, text) for holder in found.holders]
            + explicit_config_note(found, env, text) + activation_note(found, env, text)
            + autostart_note(found, env, text) + unchecked_notes(found, text))

def autostart_line(found: Survey) -> str:
    lua = found.entry is not None and found.entry.suffix == ".lua"
    return 'hl.on("hyprland.start", function () hl.exec_cmd("pentad start") end)' if lua else "exec-once = pentad start"

def autostart_note(found: Survey, env, text: Text) -> list[str]:
    """Say how to start Pentad with Hyprland when no line in the config does."""
    if not found.entry or found.pentad_starts:
        return []
    line, place, directory = autostart_line(found), shown_path(found.entry, env), shown_path(found.directory, env)
    return [text(f"Pentad не знайшов у {directory} рядка, що запускає Pentad разом із Hyprland. "
                 f"Додайте {line} у {place}, якщо сеанс не запускає його інакше.",
                 f"Pentad found no line in {directory} that starts Pentad with Hyprland. "
                 f"Add {line} to {place}, unless your session starts it another way.")]

LOCK_CMD = re.compile(r"^\s*lock_cmd\s*=\s*\S")

def lock_notes(env, system_root: Path, text: Text) -> list[str]:
    """Problems that would leave the screen unlocked or the password unchecked."""
    notes = []
    # The lock reads PAM from /etc/pam.d only; a vendor copy in /usr/lib/pam.d would skip local policy.
    if not (system_root / "etc/pam.d/login").is_file():
        vendor = (system_root / "usr/lib/pam.d/login").is_file()
        notes.append(text("Екран блокування Pentad не вмикається без /etc/pam.d/login, тож блокує hyprlock"
                          + (": скопіюйте /usr/lib/pam.d/login до /etc/pam.d." if vendor else "."),
                          "The Pentad lock screen does not start without /etc/pam.d/login, so hyprlock locks instead"
                          + (": copy /usr/lib/pam.d/login to /etc/pam.d." if vendor else ".")))
    directory = hypr_directory(env)
    config = directory / "hypridle.conf" if directory else None
    if config and which("hypridle", env):
        try:
            content = "" if not config.exists() else config.read_text(encoding="utf-8", errors="replace") \
                if config.stat().st_size <= CONFIG_FILE_LIMIT else None
        except OSError:
            content = None
        if content is not None and not any(LOCK_CMD.match(without_comment(line, False)) for line in content.splitlines()):
            notes.append(text(f"У {shown_path(config, env)} немає lock_cmd, тож Super+L, простій і сон не блокують "
                              "екран. Додайте lock_cmd = pentad lock.",
                              f"{shown_path(config, env)} has no lock_cmd, so Super+L, idle and sleep do not lock "
                              "the screen. Add lock_cmd = pentad lock."))
    return notes

def is_arch(system_root: Path) -> bool:
    try:
        text = (system_root / "etc/os-release").read_text(encoding="utf-8")
    except OSError:
        return False
    fields = dict(line.split("=", 1) for line in text.splitlines() if "=" in line)
    ids = f"{fields.get('ID', '')} {fields.get('ID_LIKE', '')}".replace('"', "").split()
    return "arch" in ids

class Report:
    def __init__(self, text: Text, color: bool):
        self.text = text
        self.color = color
        self.lines: list[str] = []

    def heading(self, title: str) -> None:
        self.lines.extend(["", title])

    def row(self, state: str, label: str, detail: str = "") -> None:
        words = {"ok": self.text("є", "ok"), "missing": self.text("бракує", "missing"),
                 "unknown": self.text("невідомо", "unknown")}
        colors = {"ok": "32", "missing": "31", "unknown": "33"}
        word = f"{words[state]:<9}"
        if self.color:
            word = f"\033[{colors[state]}m{word}\033[0m"
        self.lines.append(f"  {word}{label}{': ' + detail if detail else ''}")

    def note(self, line: str) -> None:
        self.lines.append(f"  {line}")

def describe(need: Need, arch: bool) -> str:
    return f"{need.name} ({need.arch})" if arch and need.arch and need.arch != need.name else need.name

def check(root: Path, qs: str, env, system_root: Path, color: bool) -> tuple[str, int, list[str]]:
    text = Text(is_ukrainian(env))
    report = Report(text, color)
    arch = is_arch(system_root)
    required_packages: list[str] = []
    optional_packages: list[str] = []
    missing_required = False

    def require(ok: bool | None, label: str, detail: str, package: str = "") -> None:
        nonlocal missing_required
        report.row("ok" if ok else "unknown" if ok is None else "missing", label, "" if ok else detail)
        if ok is False:
            missing_required = True
            if package:
                required_packages.append(package)

    report.lines.append(text("Перевірка Pentad", "Pentad doctor"))
    report.heading(text("Потрібно", "Required"))
    runtime_ok = (root / "shell.qml").is_file() and (root / "builtin-registry.json").is_file()
    require(runtime_ok, text("Файли Pentad", "Pentad files"),
            text(f"не знайдено в {root}; встановіть Pentad ще раз", f"not found in {root}; install Pentad again"))
    version = quickshell_version(qs, env)
    minimum = ".".join(map(str, MINIMUM_QUICKSHELL))
    if version is None:
        require(False, "Quickshell", text(f"не знайдено {qs}; потрібна версія {minimum} або новіша",
                                          f"{qs} not found; version {minimum} or newer is needed"), "quickshell")
    else:
        shown = ".".join(map(str, version))
        require(version >= MINIMUM_QUICKSHELL, f"Quickshell {shown}",
                text(f"потрібна версія {minimum} або новіша", f"version {minimum} or newer is needed"), "quickshell")
    require(which("Hyprland", env) is not None or which("hyprland", env) is not None, "Hyprland",
            text("не знайдено", "not found"), "hyprland")
    report.row("ok", f"Python {sys.version_info.major}.{sys.version_info.minor}")
    qml, plugins = qt_directories(env, system_root)
    compat = any((path / "Qt5Compat/GraphicalEffects/qmldir").is_file() for path in qml) if qml else None
    require(compat, text("Сумісність із Qt 5 (Qt5Compat)", "Qt 5 Compatibility (Qt5Compat)"),
            text("модуль не знайдено", "module not found"), "qt6-5compat")
    svg = any((path / "imageformats/libqsvg.so").is_file() for path in plugins) if plugins else None
    require(svg, "Qt SVG", text("модуль не знайдено", "module not found"), "qt6-svg")

    families = font_families(env)
    report.heading(text("Рекомендовано", "Recommended"))
    geist = has(font("Geist"), env, families)
    report.row("ok" if geist else "unknown" if geist is None else "missing", text("Шрифт Geist", "Geist font"),
               "" if geist else text(f"без нього панель бере типовий шрифт; {GEIST_URL}",
                                     f"without it the bar uses the default font; {GEIST_URL}"))

    report.heading(text("Можливості", "Features"))
    for feature in FEATURES:
        label = text(feature.label_uk, feature.label_en)
        states = [has(need, env, families) for need in feature.needs]
        missing = [need for need, state in zip(feature.needs, states) if state is False]
        if feature.any_of:
            ok = True if any(states) else None if None in states else False
            missing = missing if ok is False else []
        else:
            ok = False if missing else None if None in states else True
        detail = text("бракує ", "needs ") + ", ".join(dict.fromkeys(describe(need, arch) for need in missing))
        report.row("ok" if ok else "unknown" if ok is None else "missing", label, detail if missing else "")
        for need in (missing[:1] if feature.any_of else missing):
            if need.arch:
                optional_packages.append(need.arch)

    warnings = []
    if not env.get("HYPRLAND_INSTANCE_SIGNATURE"):
        warnings.append(text("Зараз це не сеанс Hyprland; Pentad запускається всередині Hyprland.",
                             "This is not a Hyprland session right now; Pentad runs inside Hyprland."))
    warnings.extend(shell_conflicts(survey(root, env, system_root), env, text))
    warnings.extend(lock_notes(env, system_root, text))
    if warnings:
        report.heading(text("Зверніть увагу", "Heads-up"))
        for warning in warnings:
            for line in warning.split("\n"):
                report.note(line)

    if arch and (required_packages or optional_packages):
        report.heading(text("Встановити (Arch)", "Install (Arch)"))
        if required_packages:
            report.note("sudo pacman -S --needed " + " ".join(dict.fromkeys(required_packages)))
        if optional_packages:
            report.note(text("Для всіх можливостей: ", "For every feature: ")
                        + "sudo pacman -S --needed " + " ".join(dict.fromkeys(optional_packages)))
    elif missing_required:
        report.heading(text("Що далі", "Next"))
        report.note(text("Встановіть відсутнє менеджером пакетів вашого дистрибутива.",
                         "Install what is missing with your distribution's package manager."))
    packages = list(dict.fromkeys(required_packages)) if arch else []
    return "\n".join(report.lines) + "\n", 1 if missing_required else 0, packages

def main(argv=None, env=None, system_root: Path = Path("/")) -> int:
    parser = argparse.ArgumentParser(description="Check what Pentad needs on this system.")
    parser.add_argument("--root", type=Path, required=True, help="installed Pentad Quickshell root")
    parser.add_argument("--qs", default="qs", help="Quickshell executable")
    parser.add_argument("--required-packages", action="store_true",
                        help="print only the missing required Arch packages, for the installer")
    args = parser.parse_args(argv)
    env = os.environ if env is None else env
    color = sys.stdout.isatty() and "NO_COLOR" not in env and env.get("TERM") != "dumb"
    output, status, packages = check(args.root, args.qs, env, system_root, color)
    sys.stdout.write(" ".join(packages) + "\n" if args.required_packages else output)
    return status

if __name__ == "__main__":
    sys.exit(main())
