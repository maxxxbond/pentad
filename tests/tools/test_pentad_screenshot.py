import importlib.util
import io
import os
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

import cairo

MODULE_PATH = Path(__file__).resolve().parents[2] / "tools" / "pentad_screenshot.py"
SPEC = importlib.util.spec_from_file_location("pentad_screenshot", MODULE_PATH)
shot = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(shot)

def image(path: Path, width=20, height=12):
    surface = cairo.ImageSurface(cairo.FORMAT_ARGB32, width, height)
    ctx = cairo.Context(surface)
    ctx.set_source_rgb(1, 1, 1)
    ctx.paint()
    ctx.set_source_rgb(0, 0, 1)
    ctx.rectangle(2, 2, 4, 4)
    ctx.fill()
    surface.write_to_png(str(path))

def rgba_at(surface, x, y):
    data = surface.get_data()
    offset = y * surface.get_stride() + x * 4
    blue, green, red, alpha = data[offset:offset + 4]
    return red, green, blue, alpha

class ScreenshotTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.runtime = Path(self.temp.name)
        old_runtime = os.environ.get("XDG_RUNTIME_DIR")
        os.environ["XDG_RUNTIME_DIR"] = str(self.runtime)
        self.addCleanup(lambda: os.environ.pop("XDG_RUNTIME_DIR", None) if old_runtime is None
                        else os.environ.__setitem__("XDG_RUNTIME_DIR", old_runtime))
        self.session = "a" * 32
        self.work = self.runtime / f"pentad-screenshot-{self.session}"
        self.work.mkdir(mode=0o700)
        image(self.work / "source.png")
        self.doc = {"width": 20, "height": 12, "crop": {"x": 1, "y": 1, "width": 8, "height": 7},
                    "annotations": [{"id": "x", "type": "redact", "x": 3, "y": 3, "width": 2, "height": 2,
                                     "points": [], "text": "", "color": "#ff0000", "strokeWidth": 4, "fontSize": 24}]}

    def test_capture_uses_explicit_output_and_private_session(self):
        def run(argv, **_kwargs):
            self.assertEqual(argv[:3], ["grim", "-o", "DP-1"])
            image(Path(argv[3]))
            return type("Result", (), {"returncode": 0, "stderr": b""})()

        with patch.object(shot, "_run_command", side_effect=run):
            result = shot.capture("DP-1", "b" * 32)
        self.assertEqual((result["width"], result["height"]), (20, 12))
        self.assertEqual(Path(result["path"]).parent.name, f"pentad-screenshot-{'b' * 32}")
        self.assertEqual(Path(result["path"]).stat().st_mode & 0o777, 0o600)

    def test_capture_failure_removes_partial_session(self):
        def run(argv, **_kwargs):
            image(Path(argv[3]))
            return type("Result", (), {"returncode": 1, "stderr": b"fake grim failure"})()

        with patch.object(shot, "_run_command", side_effect=run):
            with self.assertRaises(shot.RequestError):
                shot.capture("DP-1", "c" * 32)
        self.assertFalse((self.runtime / f"pentad-screenshot-{'c' * 32}").exists())

    def test_capture_all_uses_explicit_outputs_and_returns_every_frame(self):
        outputs = ["DP-1", "HDMI-A-1"]
        sessions = ["1" * 32, "2" * 32]
        calls = []

        def run(argv, **kwargs):
            calls.append((argv, kwargs))
            image(Path(argv[3]), 40 if argv[2] == "DP-1" else 30, 20)
            return type("Result", (), {"returncode": 0, "stderr": b""})()

        with patch.object(shot, "_run_command", side_effect=run):
            result = shot.handle({"operation": "capture-all", "outputs": outputs, "sessions": sessions})
        self.assertTrue(result["ok"])
        self.assertEqual([frame["output"] for frame in result["frames"]], outputs)
        self.assertEqual([(frame["width"], frame["height"]) for frame in result["frames"]], [(40, 20), (30, 20)])
        self.assertEqual([frame["session"] for frame in result["frames"]], sessions)
        self.assertEqual([call[0][2] for call in calls], outputs)
        self.assertTrue(all(call[1]["timeout"] == 5 for call in calls))
        self.assertTrue(all(Path(frame["path"]).is_file() for frame in result["frames"]))

    def test_capture_all_failure_cleans_every_requested_session(self):
        outputs = ["DP-1", "HDMI-A-1", "DP-2"]
        sessions = ["3" * 32, "4" * 32, "5" * 32]
        calls = []

        def run(argv, **_kwargs):
            calls.append(argv[2])
            image(Path(argv[3]))
            code = 1 if argv[2] == "HDMI-A-1" else 0
            return type("Result", (), {"returncode": code, "stderr": b"fake grim failure"})()

        with patch.object(shot, "_run_command", side_effect=run):
            with self.assertRaisesRegex(shot.RequestError, "fake grim failure"):
                shot.handle({"operation": "capture-all", "outputs": outputs, "sessions": sessions})
        self.assertEqual(calls, outputs[:2])
        self.assertTrue(all(not (self.runtime / f"pentad-screenshot-{token}").exists() for token in sessions))

    def test_capture_all_rejects_more_than_eight_outputs_before_capture(self):
        with patch.object(shot, "_run_command") as run:
            with self.assertRaisesRegex(shot.RequestError, "1 to 8"):
                shot.handle({"operation": "capture-all", "outputs": [f"DP-{i}" for i in range(9)],
                             "sessions": [f"{i:032x}" for i in range(9)]})
        run.assert_not_called()

    def test_capture_all_collision_preserves_unowned_and_unused_sessions(self):
        outputs = ["DP-1", "HDMI-A-1", "DP-2"]
        sessions = ["6" * 32, "7" * 32, "8" * 32]
        protected = []
        for token in sessions[1:]:
            directory = self.runtime / f"pentad-screenshot-{token}"
            directory.mkdir(mode=0o700)
            marker = directory / "owned-by-other-session"
            marker.write_text("keep")
            protected.append(marker)
        calls = []

        def run(argv, **_kwargs):
            calls.append(argv[2])
            image(Path(argv[3]))
            return type("Result", (), {"returncode": 0, "stderr": b""})()

        with patch.object(shot, "_run_command", side_effect=run):
            with self.assertRaises(FileExistsError):
                shot.handle({"operation": "capture-all", "outputs": outputs, "sessions": sessions})
        self.assertEqual(calls, outputs[:1])
        self.assertFalse((self.runtime / f"pentad-screenshot-{sessions[0]}").exists())
        self.assertTrue(all(marker.read_text() == "keep" for marker in protected))

    def test_export_crops_and_attempts_copy_independently_from_save(self):
        calls = []

        def run(argv, **kwargs):
            calls.append((argv, kwargs))
            if argv[0] == "wl-copy":
                self.assertEqual(argv[2], "image/png")
                self.assertTrue(kwargs["input"].startswith(b"\x89PNG"))
                return None
            self.fail(f"unexpected subprocess {argv}")

        with patch.object(shot, "_run_command", side_effect=run), patch.object(shot, "_save", side_effect=OSError("disk full")):
            result = shot.export(self.session, self.doc, "copy", "", True)
        self.assertTrue(result["copied"])
        self.assertFalse(result["saved"])
        self.assertTrue(result["ok"])
        self.assertEqual(result["saveError"], "disk full")
        self.assertEqual(len(calls), 1)

    def test_saved_png_has_crop_dimensions_and_annotation(self):
        output = self.runtime / "saved.png"
        captured = {}

        def run(argv, **kwargs):
            captured["png"] = kwargs["input"]
            return None

        with patch.object(shot, "_run_command", side_effect=run), patch.object(
            shot, "_save", side_effect=lambda _directory, png: (output.write_bytes(png), str(output))[1]
        ):
            result = shot.export(self.session, self.doc, "copy", "", True)
        self.assertTrue(result["copied"])
        surface, width, height = shot._png(output)
        self.assertEqual((width, height), (8, 7))
        self.assertNotEqual(output.read_bytes(), (self.work / "source.png").read_bytes())
        self.assertEqual(rgba_at(surface, 2, 2), (255, 0, 0, 255))
        self.assertEqual(rgba_at(surface, 1, 4), (0, 0, 255, 255))
        surface.finish()

    def test_save_succeeds_when_clipboard_fails(self):
        directory = self.runtime / "fallback-save"
        with patch.object(shot, "_run_command", side_effect=OSError("no clipboard")):
            result = shot.export(self.session, self.doc, "copy", str(directory), True)
        self.assertFalse(result["copied"])
        self.assertTrue(result["saved"])
        self.assertTrue(result["ok"])
        self.assertIn("no clipboard", result["copyError"])
        self.assertTrue(Path(result["path"]).is_file())

    def test_rejects_out_of_bounds_crop_before_side_effect(self):
        self.doc["crop"]["x"] = 19
        with patch.object(shot, "_run_command") as run:
            with self.assertRaises(shot.RequestError):
                shot.export(self.session, self.doc, "copy", "", False)
        run.assert_not_called()

    def test_fractional_crop_rounds_outward_to_cover_selected_pixels(self):
        self.doc["crop"] = {"x": 1.5, "y": 1.2, "width": 7.1, "height": 6.2}
        self.assertEqual(shot._validate_document(self.doc, 20, 12)[1], (1, 1, 8, 7))

    def test_cleanup_only_removes_owned_session(self):
        self.assertEqual(shot.handle({"operation": "cleanup", "session": self.session}), {"ok": True})
        self.assertFalse(self.work.exists())
        with self.assertRaises(shot.RequestError):
            shot.handle({"operation": "cleanup", "session": "../bad"})

    def test_save_writes_private_png_and_bindings_export_is_bounded(self):
        directory = self.runtime / "Pictures"
        result = shot.export(self.session, self.doc, "save", str(directory), False)
        saved = Path(result["path"])
        self.assertTrue(result["saved"])
        self.assertEqual(saved.stat().st_mode & 0o777, 0o600)
        self.assertEqual(shot._png(saved)[1:], (8, 7))

        config = self.runtime / "config"
        old_config = os.environ.get("XDG_CONFIG_HOME")
        os.environ["XDG_CONFIG_HOME"] = str(config)
        self.addCleanup(lambda: os.environ.pop("XDG_CONFIG_HOME", None) if old_config is None
                        else os.environ.__setitem__("XDG_CONFIG_HOME", old_config))
        fragment = "bind = SUPER, PRINT, exec, grim\n"
        written = shot.handle({"operation": "bindings", "content": fragment})
        binding_path = Path(written["path"])
        self.assertEqual(binding_path.read_text(), fragment)
        self.assertEqual(binding_path.stat().st_mode & 0o777, 0o600)
        with self.assertRaises(shot.RequestError):
            shot.handle({"operation": "bindings", "content": "x" * (16 * 1024 + 1)})

    def test_missing_xdg_user_dir_falls_back_to_pictures(self):
        with patch.object(shot, "_run_command", side_effect=FileNotFoundError("xdg-user-dir")):
            self.assertEqual(shot._pictures_directory(), Path.home() / "Pictures")

    def test_request_reader_stops_at_size_limit(self):
        with self.assertRaisesRegex(shot.RequestError, "12 MiB"):
            shot.read_request(io.BytesIO(b" " * (shot.MAX_REQUEST_BYTES + 1)))
        self.assertEqual(shot.read_request(io.BytesIO(b'{"operation":"nope"}')), {"operation": "nope"})

    def test_cairo_renders_theme_font_with_cyrillic_multiline_text(self):
        image(self.work / "source.png", 100, 60)
        self.doc = {"width": 100, "height": 60, "crop": {"x": 0, "y": 0, "width": 100, "height": 60},
            "annotations": []}
        self.doc["annotations"] = [{"id": "text", "type": "text", "x": 2, "y": 1,
            "width": 80, "height": 32, "points": [], "text": "Привіт\nWorld", "color": "#ff0000",
            "strokeWidth": 4, "fontSize": 12}]
        result = shot.export(self.session, self.doc, "save", str(self.runtime / "text"), False, "Geist")
        self.assertTrue(result["saved"])
        rendered, _, _ = shot._png(Path(result["path"]))
        first_line = sum(rgba_at(rendered, x, y)[0] > 200 and rgba_at(rendered, x, y)[1] < 80
                         for y in range(1, 14) for x in range(2, 80))
        second_line = sum(rgba_at(rendered, x, y)[0] > 200 and rgba_at(rendered, x, y)[1] < 80
                          for y in range(14, 29) for x in range(2, 80))
        self.assertGreater(first_line, 0)
        self.assertGreater(second_line, 0)
        rendered.finish()

    def test_single_point_brush_is_a_visible_dot(self):
        self.doc["annotations"] = [{"id": "dot", "type": "brush", "x": 7, "y": 4, "width": 0, "height": 0,
            "points": [{"x": 7, "y": 4}], "text": "", "color": "#ff0000", "strokeWidth": 4, "fontSize": 24}]
        output = self.runtime / "dot.png"
        with patch.object(shot, "_save", side_effect=lambda _directory, png: (output.write_bytes(png), str(output))[1]):
            shot.export(self.session, self.doc, "save", "", False)
        rendered, _, _ = shot._png(output)
        self.assertEqual(rgba_at(rendered, 6, 3), (255, 0, 0, 255))
        rendered.finish()

    def test_signed_arrow_has_arrowhead_beyond_end_of_shaft(self):
        self.doc["crop"] = {"x": 0, "y": 0, "width": 20, "height": 12}
        self.doc["annotations"] = [{"id": "arrow", "type": "arrow", "x": 14, "y": 6, "width": -8, "height": 0,
            "points": [], "text": "", "color": "#ff0000", "strokeWidth": 2, "fontSize": 24}]
        output = self.runtime / "arrow.png"
        with patch.object(shot, "_save", side_effect=lambda _directory, png: (output.write_bytes(png), str(output))[1]):
            shot.export(self.session, self.doc, "save", "", False)
        rendered, _, _ = shot._png(output)
        upper_head = any(rgba_at(rendered, x, y)[0] > 128 for x in range(14, 18) for y in range(0, 3))
        lower_head = any(rgba_at(rendered, x, y)[0] > 128 for x in range(14, 18) for y in range(9, 12))
        self.assertTrue(upper_head and lower_head)
        rendered.finish()

if __name__ == "__main__":
    unittest.main()
