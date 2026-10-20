import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]

class InstallPackagingTests(unittest.TestCase):
    @unittest.skipUnless(shutil.which("magick"), "ImageMagick is needed for installed command smoke test")
    def test_staged_install_contains_and_runs_recolor_command(self):
        with tempfile.TemporaryDirectory(prefix="pentad-install-test-") as temp_dir:
            temp = Path(temp_dir)
            destdir = temp / "root"
            env = os.environ.copy()
            env.update({"DESTDIR": str(destdir), "PREFIX": "/usr"})
            subprocess.run([str(ROOT / "packaging/install.sh")], cwd=ROOT, env=env, check=True)

            installed_cli = destdir / "usr/bin/pentad"
            installed_helper = destdir / "usr/lib/pentad/tools/recolor_wallpaper.py"
            self.assertTrue(installed_cli.is_file())
            self.assertTrue(os.access(installed_cli, os.X_OK))
            self.assertTrue(installed_helper.is_file())
            self.assertTrue((destdir / "usr/share/pentad/quickshell/shell.qml").is_file())

            source = temp / "source image.png"
            subprocess.run(
                ["magick", "-size", "2x2", "xc:#808080", str(source)], check=True
            )
            subprocess.run([str(installed_cli), "recolor-wallpaper", str(source)], check=True)
            self.assertTrue((temp / "source image-moldavite.png").is_file())

if __name__ == "__main__":
    unittest.main()
