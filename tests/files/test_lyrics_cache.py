import json
import tempfile
import unittest
from pathlib import Path

from tools.pentad_lyrics_cache import MAX_BYTES, MAX_ENTRIES, read_lyrics_cache, write_lyrics_cache

class LyricsCacheTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)

    def tearDown(self):
        self.temp.cleanup()

    def test_round_trip_is_private_and_bounded(self):
        entries = {f"song-{index}": {"savedAt": index, "value": {"plain": "lyric"}}
                   for index in range(MAX_ENTRIES + 5)}
        self.assertTrue(write_lyrics_cache(str(self.root), entries)["ok"])
        result = read_lyrics_cache(str(self.root))
        self.assertEqual(len(result["entries"]), MAX_ENTRIES)
        self.assertNotIn("song-0", result["entries"])
        cache = self.root / "pentad" / "lyrics" / "cache.json"
        self.assertEqual(cache.stat().st_mode & 0o777, 0o600)
        self.assertEqual(cache.parent.stat().st_mode & 0o777, 0o700)

    def test_oversized_entry_is_evicted_until_file_fits(self):
        entries = {
            "small": {"savedAt": 1, "value": {"plain": "ok"}},
            "large": {"savedAt": 2, "value": {"plain": "x" * MAX_BYTES}},
        }
        write_lyrics_cache(str(self.root), entries)
        result = read_lyrics_cache(str(self.root))["entries"]
        self.assertLessEqual((self.root / "pentad" / "lyrics" / "cache.json").stat().st_size, MAX_BYTES)
        self.assertEqual(result, {"small": entries["small"]})

    def test_corrupt_and_symlink_cache_files_fail_closed(self):
        directory = self.root / "pentad" / "lyrics"
        directory.mkdir(parents=True)
        path = directory / "cache.json"
        path.write_text("not-json", encoding="utf-8")
        self.assertEqual(read_lyrics_cache(str(self.root))["entries"], {})
        path.unlink()
        target = self.root / "outside"
        target.write_text(json.dumps({"version": 1, "entries": {"leak": {}}}), encoding="utf-8")
        path.symlink_to(target)
        self.assertEqual(read_lyrics_cache(str(self.root))["entries"], {})

if __name__ == "__main__":
    unittest.main()
