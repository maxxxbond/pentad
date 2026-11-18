import os
import json
import subprocess
import sys
import tempfile
import unittest
import fcntl
from pathlib import Path
from unittest.mock import patch

from tools.pentad_files import (
    ARTWORK_CACHE_MAX_BYTES,
    ARTWORK_CACHE_MAX_COUNT,
    ARTWORK_MAX_BYTES,
    ARTWORK_PENDING_MAX_COUNT,
    Conflict,
    InvalidDocument,
    LockTimeout,
    artwork_commit,
    artwork_copy_local,
    artwork_prepare,
    artwork_remove,
    artwork_touch,
    checkpoint_document,
    read_document,
    restore_document,
    write_document,
)

class StoreTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)

    def tearDown(self):
        self.temp.cleanup()

    def test_stale_revision_preserves_newer_document(self):
        first = write_document(self.root, "theme", '{"schemaVersion":1}', None)
        second = write_document(
            self.root, "theme", '{"schemaVersion":1,"accent":"#123456"}', first["revision"]
        )
        with self.assertRaises(Conflict):
            write_document(self.root, "theme", '{"accent":"#654321"}', first["revision"])
        self.assertIn("#123456", read_document(self.root, "theme")["text"])
        self.assertNotEqual(first["revision"], second["revision"])

    def test_create_requires_absence_and_existing_write_requires_revision(self):
        write_document(self.root, "layout", "{}", None)
        with self.assertRaises(Conflict):
            write_document(self.root, "layout", "[]", None)

    def test_missing_read_does_not_create_root_and_write_root_is_private(self):
        missing = self.root / "not-created"
        self.assertEqual(read_document(missing, "theme"), {"ok": True, "revision": None})
        self.assertFalse(missing.exists())
        write_document(missing, "theme", "{}", None)
        self.assertEqual(missing.stat().st_mode & 0o777, 0o700)

    def test_organizer_state_round_trips_through_bounded_state_store(self):
        document = '{"schemaVersion":1,"tab":"tasks","collapsed":true,"tasks":[]}'
        saved = write_document(self.root, "organizer", document, None)
        loaded = read_document(self.root, "organizer")
        self.assertEqual(loaded["text"], document)
        self.assertEqual(loaded["revision"], saved["revision"])

    def test_models_document_round_trips_and_unknown_names_are_refused(self):
        document = '{"schemaVersion":1,"providers":[],"roles":{"chat":""}}'
        saved = write_document(self.root, "models", document, None)
        loaded = read_document(self.root, "models")
        self.assertEqual(loaded["text"], document)
        self.assertEqual(loaded["revision"], saved["revision"])
        self.assertEqual((self.root / "models.json").stat().st_mode & 0o777, 0o600)
        with self.assertRaises(InvalidDocument):
            write_document(self.root, "model", document, None)

    def test_lock_contention_times_out(self):
        write_document(self.root, "theme", "{}", None)
        lock_fd = os.open(self.root / ".lock", os.O_RDWR)
        try:
            fcntl.flock(lock_fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
            with patch("tools.pentad_files.LOCK_TIMEOUT_SECONDS", 0.05):
                with self.assertRaises(LockTimeout):
                    write_document(self.root, "theme", "[]", read_document(self.root, "theme")["revision"])
        finally:
            os.close(lock_fd)

    def test_cli_handles_one_request_and_exits(self):
        config_root = self.root / "config"
        state_root = self.root / "state"
        request = json.dumps({"operation": "read", "name": "theme"})
        process = subprocess.run(
            [sys.executable, "tools/pentad-files.py", "--config-root", str(config_root), "--state-root", str(state_root)],
            input=request,
            text=True,
            capture_output=True,
            check=True,
        )
        self.assertEqual(process.stderr, "")
        self.assertEqual(len(process.stdout.splitlines()), 1)
        self.assertEqual(json.loads(process.stdout), {"ok": True, "revision": None})
        self.assertFalse(config_root.exists())

    def test_rejects_symlink_and_oversized_targets(self):
        (self.root / "theme.json").symlink_to(self.root / "elsewhere")
        with self.assertRaises(InvalidDocument):
            read_document(self.root, "theme")
        (self.root / "theme.json").unlink()
        (self.root / "theme.json").write_bytes(b"x" * (1024 * 1024 + 1))
        with self.assertRaises(InvalidDocument):
            read_document(self.root, "theme")

    def test_failed_replace_preserves_document_and_removes_temp(self):
        initial = write_document(self.root, "session", "old", None)
        with patch("tools.pentad_files.os.replace", side_effect=OSError("replace failed")):
            with self.assertRaises(OSError):
                write_document(self.root, "session", "new", initial["revision"])
        self.assertEqual(read_document(self.root, "session")["text"], "old")
        self.assertEqual(list(self.root.glob("*.tmp")), [])
        self.assertEqual(list(self.root.glob(".*.tmp")), [])

    def test_private_checkpoint_restore_and_stale_restore_conflict(self):
        before = write_document(self.root, "theme", "before", None)
        checkpoint = checkpoint_document(self.root, "theme")
        self.assertEqual((self.root / ".checkpoints").stat().st_mode & 0o777, 0o700)
        saved = self.root / ".checkpoints" / checkpoint["checkpointId"]
        self.assertEqual(saved.stat().st_mode & 0o777, 0o600)
        current = write_document(self.root, "theme", "newer", before["revision"])
        with self.assertRaises(Conflict):
            restore_document(self.root, "theme", checkpoint["checkpointId"], before["revision"])
        self.assertEqual(read_document(self.root, "theme")["text"], "newer")
        restored = restore_document(self.root, "theme", checkpoint["checkpointId"], current["revision"])
        self.assertTrue(restored["ok"])
        self.assertEqual(read_document(self.root, "theme")["text"], "before")

    @unittest.skipUnless(hasattr(os, "symlink"), "symlinks unavailable")
    def test_refuses_symlink_lock(self):
        (self.root / ".lock").symlink_to(self.root / "target")
        with self.assertRaises(OSError):
            write_document(self.root, "theme", "x", None)

class ArtworkCacheTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name) / "cache" / "pentad" / "artwork"

    def tearDown(self):
        self.temp.cleanup()

    def staged(self, request_id, size):
        result = artwork_prepare(self.root, request_id)
        Path(result["path"]).write_bytes(b"x" * size)
        return result

    def test_artwork_commit_enforces_per_cover_limit_and_removes_rejected_stage(self):
        self.staged(1, ARTWORK_MAX_BYTES + 1)
        with self.assertRaises(InvalidDocument):
            artwork_commit(self.root, 1)
        self.assertFalse((self.root / ".pending-1.part").exists())

        self.staged(2, ARTWORK_MAX_BYTES)
        saved = artwork_commit(self.root, 2)
        self.assertEqual(saved["size"], ARTWORK_MAX_BYTES)
        self.assertEqual(Path(saved["path"]).stat().st_mode & 0o777, 0o600)

    def test_artwork_cache_evicts_oldest_entry_by_count_and_total_bytes(self):
        for request_id in range(1, ARTWORK_CACHE_MAX_COUNT + 1):
            self.staged(request_id, 1)
            artwork_commit(self.root, request_id)
        self.staged(ARTWORK_CACHE_MAX_COUNT + 1, 1)
        result = artwork_commit(self.root, ARTWORK_CACHE_MAX_COUNT + 1)
        self.assertEqual(result["evicted"], [1])
        self.assertFalse((self.root / "cover-1.img").exists())
        self.assertEqual(len(list(self.root.glob("cover-*.img"))), ARTWORK_CACHE_MAX_COUNT)

        for request_id in range(100, 108):
            self.staged(request_id, 2 * 1024 * 1024)
            artwork_commit(self.root, request_id)
        self.staged(108, 2 * 1024 * 1024)
        result = artwork_commit(self.root, 108)
        files = list(self.root.glob("cover-*.img"))
        self.assertEqual(sum(path.stat().st_size for path in files), ARTWORK_CACHE_MAX_BYTES)
        self.assertEqual(len(files), 8)
        self.assertEqual(result["evicted"], [100])

    def test_artwork_touch_and_remove_refuse_invalid_ids_and_cleanup_stage(self):
        self.staged(7, 5)
        artwork_commit(self.root, 7)
        self.assertTrue(artwork_touch(self.root, 7)["ok"])
        self.staged(8, 4)
        self.assertTrue(artwork_remove(self.root, 8)["ok"])
        self.assertFalse((self.root / ".pending-8.part").exists())
        with self.assertRaises(InvalidDocument):
            artwork_touch(self.root, "../7")

    def test_local_artwork_copy_is_bounded_and_rejects_remote_file_authority(self):
        source = Path(self.temp.name) / "cover image.jpg"
        source.write_bytes(b"cover-data")
        copied = artwork_copy_local(self.root, 20, source.as_uri())
        self.assertEqual(Path(copied["path"]).read_bytes(), b"cover-data")
        with self.assertRaises(InvalidDocument):
            artwork_copy_local(self.root, 21, "file://remote-host/tmp/cover.jpg")

        source.write_bytes(b"x" * (ARTWORK_MAX_BYTES + 1))
        with self.assertRaises(InvalidDocument):
            artwork_copy_local(self.root, 22, source.as_uri())

    def test_pending_artwork_downloads_have_a_concurrent_count_bound(self):
        for request_id in range(30, 30 + ARTWORK_PENDING_MAX_COUNT):
            artwork_prepare(self.root, request_id)
        with self.assertRaises(InvalidDocument):
            artwork_prepare(self.root, 40)

    def test_stale_artwork_stages_are_removed_before_new_transfer(self):
        first = artwork_prepare(self.root, 50)
        os.utime(first["path"], (0, 0))
        artwork_prepare(self.root, 51)
        self.assertFalse((self.root / ".pending-50.part").exists())

if __name__ == "__main__":
    unittest.main()
