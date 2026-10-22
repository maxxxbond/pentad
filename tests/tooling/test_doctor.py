import importlib.util
import io
import re
import sys
import tempfile
import unittest
from contextlib import redirect_stdout
from pathlib import Path
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("pentad_doctor", ROOT / "tools/pentad_doctor.py")
doctor = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = doctor  # dataclasses resolve annotations through the module registry
SPEC.loader.exec_module(doctor)

def write(path: Path, text: str = "", mode: int = 0o644) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")
    path.chmod(mode)

class DoctorTests(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory(prefix="pentad-doctor-test-")
        self.addCleanup(temp.cleanup)
        self.temp = Path(temp.name)
        self.system = self.temp / "system"
        self.bin = self.temp / "bin"
        self.root = self.temp / "runtime"
        write(self.root / "shell.qml")
        write(self.root / "builtin-registry.json", "[]\n")
        write(self.system / "etc/os-release", 'NAME="Arch Linux"\nID=arch\n')
        qml = self.system / "usr/lib/qt6/qml"
        write(qml / "QtQuick/qmldir")
        write(qml / "Qt5Compat/GraphicalEffects/qmldir")
        write(self.system / "usr/lib/qt6/plugins/imageformats/libqsvg.so")
        self.fake("qs", 'echo "quickshell 0.3.2, revision 0123456"')
        self.fake("fc-list", 'printf "%s\\n" "Geist" "Noto Color Emoji,Noto Color Emoji"')
        self.fake("Hyprland")
        for feature in doctor.FEATURES:
            for need in feature.needs:
                if need.kind == "program":
                    self.fake(need.name)
        self.env = {"PATH": str(self.bin), "LANG": "en_US.UTF-8", "HYPRLAND_INSTANCE_SIGNATURE": "test"}
        modules = patch.object(doctor.importlib.util, "find_spec", return_value=object())
        modules.start()
        self.addCleanup(modules.stop)

    def fake(self, name: str, body: str = "true") -> None:
        write(self.bin / name, f"#!/bin/sh\n{body}\n", 0o755)

    def run_doctor(self) -> tuple[str, int]:
        output = io.StringIO()
        with redirect_stdout(output):
            status = doctor.main(["--root", str(self.root), "--qs", "qs"], self.env, self.system)
        return output.getvalue(), status

    def test_complete_system_passes_and_warns_about_a_notification_daemon(self):
        write(self.system / "proc/42/comm", "mako\n")
        output, status = self.run_doctor()
        self.assertEqual(status, 0, output)
        self.assertNotIn("missing", output)
        self.assertIn("ok       Quickshell 0.3.2", output)
        self.assertIn("mako is running", output)
        self.assertNotIn("pacman", output)

    def test_old_quickshell_fails_with_the_arch_package(self):
        self.fake("qs", 'echo "quickshell 0.2.1"')
        output, status = self.run_doctor()
        self.assertEqual(status, 1)
        self.assertIn("missing  Quickshell 0.2.1: version 0.3.2 or newer is needed", output)
        self.assertIn("sudo pacman -S --needed quickshell", output)

    def test_missing_runtime_files_fail(self):
        (self.root / "builtin-registry.json").unlink()
        output, status = self.run_doctor()
        self.assertEqual(status, 1)
        self.assertIn("missing  Pentad files", output)

    def test_missing_optional_program_only_disables_its_feature(self):
        (self.bin / "wf-recorder").unlink()
        (self.bin / "wl-copy").unlink()
        output, status = self.run_doctor()
        self.assertEqual(status, 0)
        self.assertIn("missing  Screen recording: needs wf-recorder", output)
        self.assertIn("missing  Screenshots: needs wl-copy (wl-clipboard)", output)
        self.assertRegex(output, r"For every feature: sudo pacman -S --needed wl-clipboard wf-recorder\n")

    def test_one_alternative_is_enough(self):
        (self.bin / "brightnessctl").unlink()
        output, _ = self.run_doctor()
        self.assertIn("ok       Brightness", output)

    def test_other_distributions_get_program_names_without_pacman(self):
        write(self.system / "etc/os-release", "ID=fedora\n")
        (self.bin / "wl-copy").unlink()
        (self.bin / "qs").unlink()
        output, status = self.run_doctor()
        self.assertEqual(status, 1)
        self.assertIn("Screenshots: needs wl-copy\n", output)
        self.assertNotIn("pacman", output)
        self.assertIn("distribution's package manager", output)

    def test_unknown_qt_layout_is_not_a_failure(self):
        for path in sorted((self.system / "usr/lib/qt6").rglob("*"), reverse=True):
            path.unlink() if path.is_file() else path.rmdir()
        output, status = self.run_doctor()
        self.assertEqual(status, 0, output)
        self.assertIn("unknown  Qt SVG", output)

    def test_ukrainian_locale(self):
        self.env["LANG"] = "uk_UA.UTF-8"
        del self.env["HYPRLAND_INSTANCE_SIGNATURE"]
        output, _ = self.run_doctor()
        self.assertTrue(output.startswith("Перевірка Pentad\n"))
        self.assertIn("є        Знімки екрана", output)
        self.assertIn("Зараз це не сеанс Hyprland", output)

    def test_arch_package_lists_every_package_the_doctor_suggests(self):
        pkgbuild = (ROOT / "packaging/arch/PKGBUILD").read_text(encoding="utf-8")
        listed = set(re.findall(r"^  '([^':]+):", pkgbuild, re.MULTILINE))
        listed.update(name.split(">=")[0] for name in re.findall(r"'([^']+)'", pkgbuild.split("depends=(", 1)[1].split(")", 1)[0]))
        suggested = {need.arch for feature in doctor.FEATURES for need in feature.needs if need.arch}
        suggested.discard("systemd")
        self.assertEqual(suggested - listed, set())
        self.assertLessEqual({"quickshell", "hyprland", "qt6-5compat", "qt6-svg"}, listed)

if __name__ == "__main__":
    unittest.main()
