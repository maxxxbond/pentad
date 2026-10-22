import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
INSTALL = ROOT / "packaging/install.sh"

class InstallPackagingTests(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory(prefix="pentad-install-test-")
        self.addCleanup(temp.cleanup)
        self.temp = Path(temp.name)
        # A stand-in qs: these tests must never reach a real Quickshell instance.
        fake_bin = self.temp / "fake-bin"
        fake_bin.mkdir()
        qs = fake_bin / "qs"
        qs.write_text('#!/bin/sh\ncase "$1" in\n  list) echo "${PENTAD_FAKE_INSTANCES:-[]}" ;;\n'
                      '  --version) echo "quickshell 0.3.2" ;;\n  *) exit 3 ;;\nesac\n', encoding="utf-8")
        qs.chmod(0o755)
        self.env = {key: value for key, value in os.environ.items() if key not in ("PREFIX", "DESTDIR")}
        self.env.update({"HOME": str(self.temp / "home"), "PATH": f"{fake_bin}:{os.environ['PATH']}",
                         "TMPDIR": str(self.temp), "LANG": "C"})

    def install(self, *args, check=True, **env):
        return subprocess.run([str(INSTALL), *args], cwd=self.temp, env={**self.env, **env},
                              capture_output=True, text=True, check=check)

    def test_user_install_without_prefix_goes_to_local_and_uninstalls(self):
        result = self.install()
        prefix = self.temp / "home/.local"
        launcher = prefix / "bin/pentad"
        runtime = prefix / "share/pentad/quickshell"
        self.assertTrue(os.access(launcher, os.X_OK))
        self.assertTrue((runtime / "shell.qml").is_file())
        self.assertTrue((runtime / "helpers/pentad_doctor.py").is_file())
        self.assertIn("pentad doctor", result.stdout)
        self.assertIn("is not in your PATH", result.stdout)
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
