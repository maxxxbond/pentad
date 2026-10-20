import importlib.util
import os
import re
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

import cairo
import numpy as np

MODULE_PATH = Path(__file__).resolve().parents[2] / "tools" / "pentad_screenshot.py"
SPEC = importlib.util.spec_from_file_location("pentad_screenshot_pick", MODULE_PATH)
shot = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(shot)


def write_png(path: Path, pixels: np.ndarray):
    """pixels is height x width x 3 in RGB."""
    height, width, _ = pixels.shape
    bgra = np.zeros((height, width, 4), dtype=np.uint8)
    bgra[:, :, 0] = pixels[:, :, 2]
    bgra[:, :, 1] = pixels[:, :, 1]
    bgra[:, :, 2] = pixels[:, :, 0]
    bgra[:, :, 3] = 255
    surface = cairo.ImageSurface.create_for_data(bytearray(bgra.tobytes()), cairo.FORMAT_ARGB32, width, height)
    surface.write_to_png(str(path))


def synthetic_page(width=1280, height=720):
    """A page with a photo, a block of text lines and a flat card, on white."""
    rng = np.random.default_rng(7)
    page = np.full((height, width, 3), 255, dtype=np.uint8)
    # photo: noisy colours
    page[100:350, 100:500] = rng.integers(0, 255, size=(250, 400, 3), dtype=np.uint8)
    # text: rows of short black "words" of glyph height 9
    for line in range(8):
        y = 110 + line * 22
        x = 640
        while x < 1160:
            word = int(rng.integers(20, 70))
            for glyph in range(0, word, 7):
                page[y:y + 9, x + glyph:x + glyph + 4] = 20
            x += word + 12
    # card: flat light grey with a thin darker top bar
    page[450:650, 100:620] = (232, 232, 236)
    page[450:458, 100:620] = (60, 90, 160)
    return page


def near(rect, expected, tolerance=14):
    return (abs(rect["x"] - expected[0]) <= tolerance and abs(rect["y"] - expected[1]) <= tolerance
            and abs(rect["width"] - expected[2]) <= tolerance * 2 and abs(rect["height"] - expected[3]) <= tolerance * 2)


class PickTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.runtime = Path(self.temp.name)
        previous = os.environ.get("XDG_RUNTIME_DIR")
        os.environ["XDG_RUNTIME_DIR"] = str(self.runtime)
        self.addCleanup(lambda: os.environ.pop("XDG_RUNTIME_DIR", None) if previous is None
                        else os.environ.__setitem__("XDG_RUNTIME_DIR", previous))
        self.session = "d" * 32
        self.work = self.runtime / f"pentad-screenshot-{self.session}"
        self.work.mkdir(mode=0o700)
        self.page = synthetic_page()
        write_png(self.work / "source.png", self.page)

    # crop -------------------------------------------------------------------------------------

    def test_crop_writes_a_private_png_of_exactly_the_selection(self):
        result = shot.crop(self.session, {"x": 100, "y": 100, "width": 40, "height": 30}, 1)
        path = Path(result["path"])
        self.assertTrue(result["ok"])
        self.assertEqual(path.parent, self.runtime)
        self.assertRegex(path.name, r"^pentad-pick-[0-9a-f]{32}\.png$")
        self.assertEqual(path.stat().st_mode & 0o777, 0o600)
        self.assertEqual((result["width"], result["height"]), (40, 30))
        surface = cairo.ImageSurface.create_from_png(str(path))
        self.assertEqual((surface.get_width(), surface.get_height()), (40, 30))

    def test_crop_pixels_come_from_the_selected_area(self):
        result = shot.crop(self.session, {"x": 100, "y": 450, "width": 10, "height": 4}, 1)
        surface = cairo.ImageSurface.create_from_png(result["path"])
        data = surface.get_data()
        blue, green, red, _alpha = data[0:4]
        self.assertEqual((red, green, blue), (60, 90, 160))

    def test_crop_scales_with_hard_pixel_edges_for_the_magnifier(self):
        result = shot.crop(self.session, {"x": 100, "y": 450, "width": 5, "height": 16}, 4)
        self.assertEqual((result["width"], result["height"]), (20, 64))
        surface = cairo.ImageSurface.create_from_png(result["path"])
        data = surface.get_data()
        stride = surface.get_stride()

        def rgb(x, y):
            offset = y * stride + x * 4
            return tuple(data[offset:offset + 3][::-1])

        # source rows 0..7 are the blue bar, row 8 onwards the grey card; scaled rows 31 and 32 straddle that edge
        self.assertEqual(rgb(3, 31), (60, 90, 160))
        self.assertEqual(rgb(3, 32), (232, 232, 236))

    def test_crop_rounds_fractional_selections_outward_and_stays_inside_the_image(self):
        result = shot.crop(self.session, {"x": 10.4, "y": 20.2, "width": 5.2, "height": 3.1}, 1)
        self.assertEqual((result["x"], result["y"], result["cropWidth"], result["cropHeight"]), (10, 20, 6, 4))

    def test_crop_rejects_bad_input_before_creating_anything(self):
        before = set(self.runtime.iterdir())
        for rect in ({"x": -1, "y": 0, "width": 5, "height": 5}, {"x": 0, "y": 0, "width": 0, "height": 5},
                     {"x": 1270, "y": 0, "width": 20, "height": 5}, {"x": 0, "y": 0, "width": float("nan"), "height": 5},
                     {"x": 0, "y": 0, "width": 5}, "nope", None):
            with self.assertRaises(shot.RequestError, msg=repr(rect)):
                shot.crop(self.session, rect, 1)
        for scale in (0, 9, 2.5, True, "3", -1):
            with self.assertRaises(shot.RequestError, msg=repr(scale)):
                shot.crop(self.session, {"x": 0, "y": 0, "width": 5, "height": 5}, scale)
        with self.assertRaises(shot.RequestError):
            shot.crop("../bad", {"x": 0, "y": 0, "width": 5, "height": 5}, 1)
        self.assertEqual(set(self.runtime.iterdir()), before)

    def test_crop_refuses_results_beyond_the_pixel_limit(self):
        with patch.object(shot, "MAX_PIXELS", 1000):
            with self.assertRaises(shot.RequestError):
                shot.crop(self.session, {"x": 0, "y": 0, "width": 100, "height": 100}, 2)

    def test_discard_removes_only_pick_files_from_the_runtime_directory(self):
        result = shot.crop(self.session, {"x": 0, "y": 0, "width": 4, "height": 4}, 1)
        keep = self.runtime / "pentad-other.png"
        keep.write_bytes(b"x")
        self.assertEqual(shot.handle({"operation": "discard", "path": result["path"]}), {"ok": True})
        self.assertFalse(Path(result["path"]).exists())
        for bad in (str(keep), "/etc/passwd", str(self.runtime / "pentad-pick-short.png"), "../x", 5, None,
                    str(self.runtime / "sub" / ("pentad-pick-" + "a" * 32 + ".png"))):
            with self.assertRaises(shot.RequestError, msg=repr(bad)):
                shot.handle({"operation": "discard", "path": bad})
        self.assertTrue(keep.exists())
        # a file that is already gone is not an error
        self.assertEqual(shot.handle({"operation": "discard", "path": result["path"]}), {"ok": True})

    def test_handle_routes_crop_and_proposals(self):
        result = shot.handle({"operation": "crop", "session": self.session,
                              "rect": {"x": 0, "y": 0, "width": 8, "height": 8}, "scale": 2})
        self.assertEqual(result["width"], 16)
        self.assertTrue(shot.handle({"operation": "proposals", "session": self.session})["ok"])

    # proposals --------------------------------------------------------------------------------

    def regions(self):
        result = shot.proposals(self.session)
        self.assertTrue(result["ok"])
        return result["regions"]

    def test_finds_the_photo_the_text_block_and_the_card(self):
        regions = self.regions()
        photo = [r for r in regions if r["kind"] == "image" and near(r, (100, 100, 400, 250))]
        dark = np.argwhere((self.page[:, :, 0] < 60) & (np.arange(self.page.shape[1])[None, :] >= 600))
        top, left = dark.min(axis=0)
        bottom, right = dark.max(axis=0)
        text_box = (int(left), int(top), int(right - left + 1), int(bottom - top + 1))
        text = [r for r in regions if r["kind"] == "text" and near(r, text_box, 10)]
        card = [r for r in regions if r["kind"] == "panel" and near(r, (100, 450, 520, 200))]
        self.assertTrue(photo, regions)
        self.assertTrue(text, regions)
        self.assertTrue(card, regions)

    def test_regions_are_inside_the_image_and_never_the_whole_screen(self):
        for region in self.regions():
            self.assertGreaterEqual(region["x"], 0)
            self.assertGreaterEqual(region["y"], 0)
            self.assertLessEqual(region["x"] + region["width"], 1280)
            self.assertLessEqual(region["y"] + region["height"], 720)
            self.assertLess(region["width"] * region["height"], 0.6 * 1280 * 720)
            self.assertIn(region["kind"], ("image", "text", "panel"))

    def test_regions_do_not_duplicate_each_other(self):
        regions = self.regions()

        def iou(a, b):
            x1, y1 = max(a["x"], b["x"]), max(a["y"], b["y"])
            x2 = min(a["x"] + a["width"], b["x"] + b["width"])
            y2 = min(a["y"] + a["height"], b["y"] + b["height"])
            inter = max(0, x2 - x1) * max(0, y2 - y1)
            union = a["width"] * a["height"] + b["width"] * b["height"] - inter
            return inter / union if union else 0

        for i, a in enumerate(regions):
            for b in regions[i + 1:]:
                self.assertLess(iou(a, b), 0.85, (a, b))

    def test_results_are_capped_and_deterministic(self):
        first = self.regions()
        self.assertLessEqual(len(first), 600)
        self.assertEqual(first, self.regions())

    def test_a_blank_screen_has_no_proposals(self):
        write_png(self.work / "source.png", np.full((720, 1280, 3), 255, dtype=np.uint8))
        self.assertEqual(self.regions(), [])

    def test_tiny_images_are_handled(self):
        write_png(self.work / "source.png", np.full((10, 10, 3), 255, dtype=np.uint8))
        self.assertEqual(self.regions(), [])

    def test_runs_in_reasonable_time_on_a_4k_frame(self):
        import time
        big = np.full((2160, 3840, 3), 255, dtype=np.uint8)
        big[200:900, 200:1300] = np.random.default_rng(3).integers(0, 255, size=(700, 1100, 3), dtype=np.uint8)
        write_png(self.work / "source.png", big)
        started = time.monotonic()
        regions = self.regions()
        self.assertLess(time.monotonic() - started, 6.0)
        self.assertTrue(any(r["kind"] == "image" and near(r, (200, 200, 1100, 700), 20) for r in regions))

    def test_sixteen_bit_pngs_give_the_same_suggestions(self):
        # cairo loads these as 10-bit RGB30, whose bytes are not BGRA; the helper must not read them as such.
        height, width, _ = self.page.shape
        surface = cairo.ImageSurface(cairo.FORMAT_RGB30, width, height)
        flat = cairo.ImageSurface.create_for_data(
            bytearray(np.dstack([self.page[:, :, 2], self.page[:, :, 1], self.page[:, :, 0],
                                 np.full((height, width), 255, dtype=np.uint8)]).tobytes()), cairo.FORMAT_ARGB32, width, height)
        ctx = cairo.Context(surface)
        ctx.set_source_surface(flat, 0, 0)
        ctx.paint()
        surface.write_to_png(str(self.work / "source.png"))
        regions = self.regions()
        self.assertTrue([r for r in regions if r["kind"] == "image" and near(r, (100, 100, 400, 250))], regions)
        self.assertTrue([r for r in regions if r["kind"] == "panel" and near(r, (100, 450, 520, 200))], regions)

    def test_without_numpy_it_reports_nothing_instead_of_failing(self):
        with patch.object(shot, "_numpy", return_value=None):
            result = shot.proposals(self.session)
        self.assertEqual(result["regions"], [])
        self.assertTrue(result["ok"])
        self.assertIn("numpy", result["reason"])

    def test_session_must_exist(self):
        with self.assertRaises(Exception):
            shot.proposals("e" * 32)


if __name__ == "__main__":
    unittest.main()
