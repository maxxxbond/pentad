import os
import stat
import tempfile
import time
import unittest
from pathlib import Path

from tools.pentad_worker_cache import WorkerCache, cache_key, content_hash, default_root


class CacheKeyTests(unittest.TestCase):
    def test_key_covers_op_options_content_and_engine(self):
        base = cache_key('image.ocr', {'language': 'eng', 'psm': 6}, content_hash(b'png'), 'tesseract 5')
        self.assertEqual(base, cache_key('image.ocr', {'psm': 6, 'language': 'eng'}, content_hash(b'png'), 'tesseract 5'))
        for other in (cache_key('image.barcode', {'language': 'eng', 'psm': 6}, content_hash(b'png'), 'tesseract 5'),
                      cache_key('image.ocr', {'language': 'ukr', 'psm': 6}, content_hash(b'png'), 'tesseract 5'),
                      cache_key('image.ocr', {'language': 'eng', 'psm': 6}, content_hash(b'png2'), 'tesseract 5'),
                      cache_key('image.ocr', {'language': 'eng', 'psm': 6}, content_hash(b'png'), 'tesseract 6')):
            self.assertNotEqual(base, other)
        self.assertRegex(base, r'^[0-9a-f]{64}$')

    def test_default_root_follows_xdg_cache_home(self):
        old = os.environ.get('XDG_CACHE_HOME')
        try:
            os.environ['XDG_CACHE_HOME'] = '/tmp/pentad-cache-test'
            self.assertEqual(default_root(), Path('/tmp/pentad-cache-test/pentad/worker'))
            os.environ['XDG_CACHE_HOME'] = 'relative'
            self.assertEqual(default_root(), Path.home() / '.cache' / 'pentad' / 'worker')
        finally:
            if old is None:
                os.environ.pop('XDG_CACHE_HOME', None)
            else:
                os.environ['XDG_CACHE_HOME'] = old


class WorkerCacheTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.root = Path(self.directory.name) / 'pentad' / 'worker'

    def tearDown(self):
        self.directory.cleanup()

    def key(self, index):
        return cache_key('image.ocr', {}, content_hash(str(index).encode()), 'engine')

    def test_round_trip_with_private_permissions_and_counters(self):
        cache = WorkerCache(self.root)
        self.assertTrue(cache.enabled)
        self.assertIsNone(cache.get(self.key(1)))
        self.assertTrue(cache.put(self.key(1), {'text': 'привіт'}))
        self.assertEqual(cache.get(self.key(1)), {'text': 'привіт'})
        self.assertEqual(stat.S_IMODE(self.root.stat().st_mode), 0o700)
        files = list(self.root.iterdir())
        self.assertEqual([path.name for path in files], [self.key(1) + '.json'])
        self.assertEqual(stat.S_IMODE(files[0].stat().st_mode), 0o600)
        stats = cache.stats()
        self.assertEqual((stats['hits'], stats['misses'], stats['stores'], stats['entries']), (1, 1, 1, 1))
        # A new instance (a restarted worker) finds the entry on disk.
        self.assertEqual(WorkerCache(self.root).get(self.key(1)), {'text': 'привіт'})

    def test_tightens_an_existing_directory_and_refuses_a_symlink(self):
        self.root.mkdir(parents=True, mode=0o755)
        os.chmod(self.root, 0o755)
        self.assertTrue(WorkerCache(self.root).enabled)
        self.assertEqual(stat.S_IMODE(self.root.stat().st_mode), 0o700)
        target = Path(self.directory.name) / 'elsewhere'
        target.mkdir()
        link = Path(self.directory.name) / 'link'
        link.symlink_to(target)
        cache = WorkerCache(link)
        self.assertFalse(cache.enabled)
        self.assertFalse(cache.put(self.key(1), {'text': 'x'}))
        self.assertIsNone(cache.get(self.key(1)))
        self.assertEqual(list(target.iterdir()), [])

    def test_zero_size_disables_the_cache(self):
        cache = WorkerCache(self.root, max_bytes=0)
        self.assertFalse(cache.enabled)
        self.assertFalse(cache.put(self.key(1), {'text': 'x'}))

    def test_evicts_oldest_mtime_first_and_a_hit_refreshes_an_entry(self):
        cache = WorkerCache(self.root)
        past = time.time() - 1000
        for index in range(5):
            cache.put(self.key(index), {'text': str(index)})
            os.utime(self.root / f'{self.key(index)}.json', (past + index, past + index))
        # Entry 0 is the oldest; reading it makes it the newest.
        self.assertIsNotNone(cache.get(self.key(0)))
        smaller = WorkerCache(self.root, max_entries=3)
        self.assertEqual(sorted(path.name for path in self.root.iterdir()),
                         sorted(f'{self.key(index)}.json' for index in (0, 3, 4)))
        self.assertEqual(smaller.stats()['entries'], 3)
        self.assertEqual(smaller.stats()['evictions'], 2)

    def test_stays_under_the_byte_cap(self):
        cache = WorkerCache(self.root, max_bytes=4096)
        for index in range(20):
            self.assertTrue(cache.put(self.key(index), {'text': 'x' * 500}))
        total = sum(path.stat().st_size for path in self.root.iterdir())
        self.assertLessEqual(total, 4096)
        self.assertEqual(cache.stats()['bytes'], total)
        self.assertIsNotNone(cache.get(self.key(19)))
        self.assertIsNone(cache.get(self.key(0)))

    def test_skips_an_entry_larger_than_a_quarter_of_the_cap(self):
        cache = WorkerCache(self.root, max_bytes=4096)
        self.assertFalse(cache.put(self.key(1), {'text': 'x' * 2000}))
        self.assertEqual(list(self.root.iterdir()), [])

    def test_a_damaged_or_foreign_entry_is_a_miss_and_is_removed(self):
        cache = WorkerCache(self.root)
        cache.put(self.key(1), {'text': 'x'})
        path = self.root / f'{self.key(1)}.json'
        path.write_text('{not json')
        self.assertIsNone(cache.get(self.key(1)))
        self.assertFalse(path.exists())
        # An entry copied under another key does not count.
        cache.put(self.key(2), {'text': 'two'})
        (self.root / f'{self.key(2)}.json').rename(self.root / f'{self.key(3)}.json')
        self.assertIsNone(cache.get(self.key(3)))

    def test_removes_stale_temporary_files(self):
        self.root.mkdir(parents=True)
        stale = self.root / '.tmp-old'
        stale.write_text('partial')
        os.utime(stale, (time.time() - 7200, time.time() - 7200))
        fresh = self.root / '.tmp-new'
        fresh.write_text('partial')
        WorkerCache(self.root)
        self.assertFalse(stale.exists())
        self.assertTrue(fresh.exists())


if __name__ == '__main__':
    unittest.main()
