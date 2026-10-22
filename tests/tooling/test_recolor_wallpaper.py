import importlib.util
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
MODULE_PATH = ROOT / "tools/pentad_recolor_wallpaper.py"
SPEC = importlib.util.spec_from_file_location("recolor_wallpaper", MODULE_PATH)
recolor_wallpaper = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(recolor_wallpaper)

class RecolorWallpaperTests(unittest.TestCase):
    def test_lut_has_256_rgb_samples_and_expected_endpoints(self):
        lut = recolor_wallpaper.make_lut()
        self.assertEqual(len(lut), 256 * 3)
        self.assertEqual(tuple(lut[:3]), (17, 19, 17))
        self.assertEqual(tuple(lut[-3:]), (235, 240, 230))
        self.assertEqual(tuple(lut[51 * 3:52 * 3]), (25, 29, 24))
        self.assertLess(lut[51 * 3], lut[53 * 3])

    def test_theme_stops_replace_the_moldavite_map(self):
        stops = recolor_wallpaper.parse_stops("0:#000000, 0.5:#5B8DEF,1:#FFFFFF")
        self.assertEqual(stops, ((0.0, (0, 0, 0)), (0.5, (91, 141, 239)), (1.0, (255, 255, 255))))
        lut = recolor_wallpaper.make_lut(stops)
        self.assertEqual(tuple(lut[:3]), (0, 0, 0))
        self.assertEqual(tuple(lut[-3:]), (255, 255, 255))
        self.assertEqual(tuple(lut[128 * 3:129 * 3]), (92, 141, 239))
        for text in ("0:#000000", "0.2:#000000,1:#FFFFFF", "0:#000000,0.5:#111111,0.4:#222222,1:#FFFFFF",
                     "0:000000,1:#FFFFFF", "0:#GG0000,1:#FFFFFF", "x:#000000,1:#FFFFFF"):
            with self.assertRaises(ValueError, msg=text):
                recolor_wallpaper.parse_stops(text)

    def test_invalid_stops_exit_before_touching_files(self):
        with patch.object(recolor_wallpaper, "recolor") as recolor:
            self.assertEqual(recolor_wallpaper.main(["in.png", "out.png", "--stops", "0:#000000"]), 2)
        recolor.assert_not_called()

    def test_missing_magick_is_reported_before_processing(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            source = Path(temp_dir) / "wallpaper.png"
            source.write_bytes(b"fixture")
            with patch.object(recolor_wallpaper.shutil, "which", return_value=None):
                with self.assertRaisesRegex(RuntimeError, "ImageMagick 'magick' was not found"):
                    recolor_wallpaper.recolor(source, source.with_name("out.png"))

    def test_magick_receives_grayscale_autolevel_clut_pipeline(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            temp = Path(temp_dir)
            source = temp / "wallpaper.png"
            output = temp / "result.png"
            source.write_bytes(b"fixture")
            with patch.object(recolor_wallpaper.shutil, "which", return_value="/usr/bin/magick"):
                with patch.object(recolor_wallpaper.subprocess, "run") as run:
                    recolor_wallpaper.recolor(source, output)
            command = run.call_args.args[0]
            self.assertEqual(command[:2], ["/usr/bin/magick", str(source)])
            self.assertIn("-colorspace", command)
            self.assertIn("-auto-level", command)
            self.assertIn("-clut", command)
            self.assertEqual(command[-1], str(output))
            clut = Path(command[command.index("-type") + 2])
            self.assertFalse(clut.exists())
            run.assert_called_once_with(command, check=True)

if __name__ == "__main__":
    unittest.main()
