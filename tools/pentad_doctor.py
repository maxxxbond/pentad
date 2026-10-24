#!/usr/bin/env python3
"""Report which programs and modules Pentad finds, without changing anything."""

from __future__ import annotations

import argparse
import glob
import importlib.util
import json
import os
import re
import shutil
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path

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
    Feature("Екран блокування", "Lock screen", (program("hyprlock"), program("hypridle"))),
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
CONFIG_FILE_LIMIT = 256 * 1024
START_LINE_LIMIT = 5

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

def without_comment(line: str, lua: bool) -> str:
    """Cut a trailing comment; in Lua only outside quotes, so `uwsm app -- waybar` survives."""
    if not lua:
        return line.split("#", 1)[0]
    quote, index = "", 0
    while index < len(line):
        char = line[index]
        if quote:
            if char == "\\":
                index += 1
            elif char == quote:
                quote = ""
        elif char in "\"'":
            quote = char
        elif line.startswith("--", index):
            return line[:index]
        index += 1
    return line

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
            lua = path.suffix == ".lua"
            lines.extend((path, number, without_comment(line, lua)) for number, line in enumerate(content.splitlines(), 1))
    return lines

def command_words(arguments: list[str], comm: str) -> set[str]:
    words = {Path(arguments[0]).name if arguments else "", comm.strip()} - {""}
    # Nix wraps programs as .name-wrapped, and comm cuts that to 15 characters (.quickshell-wra).
    words |= {match.group(1) for word in words if (match := re.fullmatch(r"\.(.+?)-wra(?:p|pp|ppe|pped)?", word))}
    return words | SHELL_FAMILY if words & SHELL_FAMILY else words

def find_starts(words: set[str], lines: list[tuple[Path, int, str]], env) -> tuple[list[str], int]:
    """Return the start lines that run one of the command words, and how many key bindings do."""
    if not words:
        return [], 0
    alternatives = "|".join(re.escape(word) for word in sorted(words))
    pattern = re.compile(rf"(?:^|[\s\"'(=/])(?:{alternatives})(?=$|[\s\"')])")
    starts, bindings = [], 0
    for path, number, line in lines:
        if "exec" in line and pattern.search(line):
            if "bind" in line:
                bindings += 1
            else:
                starts.append(f"{shown_path(path, env)}:{number}")
    return starts, bindings

def holder_paragraph(pid: int, roles: set[str], lines: list[tuple[Path, int, str]], directory: Path | None,
                     env, system_root: Path, text: Text) -> str:
    arguments = command_line(pid, system_root)
    comm = read_proc(pid, "comm", system_root).strip()
    label = " ".join(arguments)[:80] or comm or text("процес", "process")
    names = ", ".join(text(*ROLE_NAMES[role]) for role in ROLE_NAMES if role in roles)
    out = [text(f"{label} (pid {pid}) займає: {names}.", f"{label} (pid {pid}) holds: {names}.")]
    words = command_words(arguments, comm)
    unit = systemd_service(pid, words, system_root)
    if unit:
        command = f"systemctl --user disable --now {unit}"
        out.append(text(f"Працює як користувацька служба systemd {unit}: {command}",
                        f"Runs as the systemd user service {unit}: {command}"))
    else:
        starts, bindings = find_starts(words, lines, env)
        place = shown_path(directory, env) if directory else ""
        if starts:
            prefix = text("Запускається з ", "Started from ")
            indent = " " * len(prefix)
            out.append(prefix + starts[0])
            out.extend(indent + start for start in starts[1:START_LINE_LIMIT])
            if len(starts) > START_LINE_LIMIT:
                more = len(starts) - START_LINE_LIMIT
                out.append(indent + text(f"і ще {more}", f"and {more} more"))
        elif place:
            out.append(text(f"Pentad не знайшов рядка його запуску в {place}; перевірте цю теку й автозапуск сеансу.",
                            f"Pentad found no start line for it in {place}; check that folder and your session's autostart."))
        else:
            out.append(text("Рядок його запуску не шукали: невідомо, де лежить конфігурація Hyprland; "
                            "перевірте автозапуск вашого сеансу.",
                            "Its start line was not searched for because the Hyprland config location is unknown; "
                            "check your session's autostart."))
        if bindings:
            out.append(text(f"Його також викликають прив'язки клавіш: {bindings} (у {place}).",
                            f"Also called by {bindings} key {'binding' if bindings == 1 else 'bindings'} in {place}."))
    out.append(text("Приберіть його з автозапуску й запустіть Pentad командою `pentad start`, "
                    "потім знову запустіть pentad doctor.",
                    "Remove it from autostart and start Pentad with `pentad start`, then run pentad doctor again."))
    return "\n".join(out[:1] + ["  " + line for line in out[1:]])

def shell_conflicts(root: Path, env, system_root: Path, text: Text) -> list[str]:
    """Return one paragraph per foreign process holding notifications or screen surfaces, then what could not be checked."""
    holders: dict[int, set[str]] = {}
    unchecked = []
    owners = notification_owners(env)
    if owners is None:
        unchecked.append(text("Не вдалося перевірити, хто показує сповіщення: busctl відсутній або не відповів.",
                              "Could not check who shows notifications: busctl is missing or did not answer."))
    for pid in owners or []:
        holders.setdefault(pid, set()).add("notifications")
    if env.get("HYPRLAND_INSTANCE_SIGNATURE"):
        layers = layer_holders(env)
        if layers is None:
            unchecked.append(text("Не вдалося перевірити шпалери й панелі: hyprctl -j layers не відповів.",
                                  "Could not check wallpaper and panels: hyprctl -j layers did not answer."))
        for pid, roles in (layers or {}).items():
            holders.setdefault(pid, set()).update(roles)
    foreign = {pid: roles for pid, roles in holders.items() if not is_pentad(command_line(pid, system_root), root)}
    directory = hypr_directory(env)
    lines = config_lines(directory) if foreign and directory else []
    return [holder_paragraph(pid, foreign[pid], lines, directory, env, system_root, text)
            for pid in sorted(foreign)] + unchecked

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
    warnings.extend(shell_conflicts(root, env, system_root, text))
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
