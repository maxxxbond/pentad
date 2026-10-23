#!/usr/bin/env python3
"""Report which programs and modules Pentad finds, without changing anything."""

from __future__ import annotations

import argparse
import glob
import importlib.util
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
    Feature("Профілі живлення", "Power profiles", (program("powerprofilesctl", "power-profiles-daemon"),)),
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
    Feature("Попередній перегляд на полиці", "Shelf previews", (python_module("gi", "python-gobject"),)),
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

NOTIFICATION_DAEMONS = ("mako", "dunst", "swaync", "fnott", "notify-osd")
WALLPAPER_DAEMONS = ("hyprpaper", "swaybg", "swww-daemon", "awww-daemon", "wpaperd", "mpvpaper")

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

def running_processes(system_root: Path) -> set[str]:
    names = set()
    for comm in glob.glob(str(system_root / "proc/[0-9]*/comm")):
        try:
            names.add(Path(comm).read_text(encoding="utf-8").strip())
        except OSError:
            continue
    return names

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

    processes = running_processes(system_root)
    warnings = []
    if not env.get("HYPRLAND_INSTANCE_SIGNATURE"):
        warnings.append(text("Зараз це не сеанс Hyprland; Pentad запускається всередині Hyprland.",
                             "This is not a Hyprland session right now; Pentad runs inside Hyprland."))
    for name in NOTIFICATION_DAEMONS:
        if name in processes:
            warnings.append(text(f"Працює {name}: Pentad сам показує сповіщення, тож вимкніть {name} в автозапуску.",
                                 f"{name} is running: Pentad shows notifications itself, so remove {name} from autostart."))
    for name in WALLPAPER_DAEMONS:
        if name in processes:
            warnings.append(text(f"Працює {name}: він закриє шпалери Pentad, щойно ви виберете їх у налаштуваннях.",
                                 f"{name} is running: it covers Pentad's wallpaper once you pick one in Settings."))
    if warnings:
        report.heading(text("Зверніть увагу", "Heads-up"))
        for warning in warnings:
            report.note(warning)

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
