import os
import pty
import re
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
INSTALL = ROOT / "packaging/install.sh"

def arch_host() -> bool:
    try:
        release = Path("/etc/os-release").read_text(encoding="utf-8")
    except OSError:
        return False
    return shutil.which("pacman") is not None and re.search(r"^ID(_LIKE)?=.*\barch\b", release, re.MULTILINE) is not None

class InstallPackagingTests(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory(prefix="pentad-install-test-")
        self.addCleanup(temp.cleanup)
        self.temp = Path(temp.name)
        # Stand-ins: these tests must never reach a real Quickshell instance or change system packages.
        fake_bin = self.temp / "fake-bin"
        fake_bin.mkdir()
        self.log = self.temp / "privileged.log"
        fakes = {
            "qs": 'case "$1" in\n  list) echo "${PENTAD_FAKE_INSTANCES:-[]}" ;;\n'
                  '  --version) echo "quickshell ${PENTAD_FAKE_QS_VERSION:-0.3.2}" ;;\n  *) exit 3 ;;\nesac',
            "sudo": f'printf "%s\\n" "$*" >> "{self.log}"',
            "pacman": f'printf "pacman %s\\n" "$*" >> "{self.log}"',
        }
        for name, body in fakes.items():
            (fake_bin / name).write_text(f"#!/bin/sh\n{body}\n", encoding="utf-8")
            (fake_bin / name).chmod(0o755)
        self.env = {key: value for key, value in os.environ.items() if key not in ("PREFIX", "DESTDIR")}
        self.env.update({"HOME": str(self.temp / "home"), "PATH": f"{fake_bin}:{os.environ['PATH']}",
                         "TMPDIR": str(self.temp), "LANG": "C"})

    def install(self, *args, check=True, **env):
        return subprocess.run([str(INSTALL), *args], cwd=self.temp, env={**self.env, **env},
                              stdin=subprocess.DEVNULL, capture_output=True, text=True, check=check)

    def install_on_terminal(self, answer: bytes, **env) -> str:
        main, terminal = pty.openpty()
        process = subprocess.Popen([str(INSTALL)], cwd=self.temp, env={**self.env, **env},
                                   stdin=terminal, stdout=terminal, stderr=terminal)
        os.close(terminal)
        os.write(main, answer)
        output = b""
        while True:
            try:
                chunk = os.read(main, 4096)
            except OSError:  # the terminal closes once the installer exits
                break
            if not chunk:
                break
            output += chunk
        os.close(main)
        self.assertEqual(process.wait(timeout=120), 0, output.decode(errors="replace"))
        return output.decode(errors="replace")

    @unittest.skipUnless(arch_host(), "the package offer only runs on Arch with pacman")
    def test_missing_quickshell_is_offered_and_installed_only_after_yes(self):
        result = self.install(PENTAD_FAKE_QS_VERSION="0.2.1")
        self.assertRegex(result.stdout, r"Install them with: sudo pacman -S --needed .*\bquickshell\b")
        self.assertFalse(self.log.exists())

        output = self.install_on_terminal(b"n\n", PENTAD_FAKE_QS_VERSION="0.2.1")
        self.assertIn("? [y/N]", output)
        self.assertIn("Install them later with: sudo pacman", output)
        self.assertFalse(self.log.exists())

        self.install_on_terminal(b"y\n", PENTAD_FAKE_QS_VERSION="0.2.1")
        self.assertRegex(self.log.read_text(encoding="utf-8"), r"^pacman -S --needed .*\bquickshell\b")

    def test_nothing_is_offered_when_required_packages_are_present(self):
        result = self.install()
        self.assertNotRegex(result.stdout, r"Pentad needs these packages:.*\bquickshell\b")
        self.assertFalse(self.log.exists())

    def test_user_install_without_prefix_goes_to_local_and_uninstalls(self):
        result = self.install()
        prefix = self.temp / "home/.local"
        launcher = prefix / "bin/pentad"
        runtime = prefix / "share/pentad/quickshell"
        self.assertTrue(os.access(launcher, os.X_OK))
        self.assertTrue((runtime / "shell.qml").is_file())
        self.assertTrue((runtime / "helpers/pentad_doctor.py").is_file())
        self.assertTrue((runtime / "helpers/pentad_setup.py").is_file())
        self.assertIn("is not in your PATH", result.stdout)
        self.assertIn(f"{launcher} doctor", result.stdout)
        self.assertIn(f"exec-once = {launcher} start", result.stdout)
        on_path = self.install(PATH=f"{prefix / 'bin'}:{self.env['PATH']}")
        self.assertIn("system:  pentad doctor", on_path.stdout)
        self.assertNotIn("is not in your PATH", on_path.stdout)
        self.assertEqual([path.name for path in runtime.parent.iterdir()], ["quickshell"])

        doctor = subprocess.run([str(launcher), "doctor"], env=self.env, capture_output=True, text=True)
        self.assertIn("ok       Pentad files", doctor.stdout, doctor.stderr)
        self.assertIn("ok       Quickshell 0.3.2", doctor.stdout)
        linked = self.temp / "elsewhere/pentad"
        linked.parent.mkdir()
        linked.symlink_to(launcher)
        doctor = subprocess.run([str(linked), "doctor"], env=self.env, capture_output=True, text=True)
        self.assertIn("ok       Pentad files", doctor.stdout, doctor.stderr)

        refused = self.install("--uninstall", check=False, PENTAD_FAKE_INSTANCES='[{"id":"a1"}]')
        self.assertNotEqual(refused.returncode, 0)
        self.assertIn("pentad stop", refused.stderr)
        self.assertTrue(launcher.exists())

        result = self.install("--uninstall")
        self.assertFalse(launcher.exists())
        self.assertFalse((prefix / "share/pentad").exists())
        self.assertIn("~/.config/pentad", result.stdout)

    def test_staged_install_replaces_the_runtime_and_drops_the_old_helper_path(self):
        destdir = self.temp / "root"
        legacy = destdir / "usr/lib/pentad/tools/recolor_wallpaper.py"
        legacy.parent.mkdir(parents=True)
        legacy.write_text("", encoding="utf-8")
        stale = destdir / "usr/share/pentad/quickshell/removed-upstream.qml"
        stale.parent.mkdir(parents=True)
        stale.write_text("", encoding="utf-8")

        result = self.install(DESTDIR=str(destdir), PREFIX="/usr")
        self.assertNotIn("Next steps", result.stdout)
        self.assertTrue((destdir / "usr/share/pentad/quickshell/shell.qml").is_file())
        self.assertFalse(stale.exists())
        self.assertFalse((destdir / "usr/lib/pentad").exists())
        self.assertTrue((destdir / "usr/lib").is_dir())

        again = self.temp / "again"
        self.install("--prefix", "/opt/pentad", "--runtime", str(destdir / "usr/share/pentad/quickshell"),
                     DESTDIR=str(again))
        self.assertTrue((again / "opt/pentad/share/pentad/quickshell/builtin-registry.json").is_file())

    def test_uninstall_leaves_a_foreign_launcher_alone(self):
        foreign = self.temp / "home/.local/bin/pentad"
        foreign.parent.mkdir(parents=True)
        foreign.write_text("#!/bin/sh\necho another program\n", encoding="utf-8")
        result = self.install("--uninstall", check=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertTrue(foreign.exists())

    def test_relative_prefix_is_rejected(self):
        result = self.install(check=False, PREFIX="usr")
        self.assertEqual(result.returncode, 2)

    @unittest.skipUnless(shutil.which("magick"), "ImageMagick is needed for installed command smoke test")
    def test_installed_recolor_command_finds_its_helper(self):
        destdir = self.temp / "root"
        self.install(DESTDIR=str(destdir), PREFIX="/usr")
        source = self.temp / "source image.png"
        subprocess.run(["magick", "-size", "2x2", "xc:#808080", str(source)], check=True)
        subprocess.run([str(destdir / "usr/bin/pentad"), "recolor-wallpaper", str(source)], check=True)
        self.assertTrue((self.temp / "source image-moldavite.png").is_file())

if __name__ == "__main__":
    unittest.main()
