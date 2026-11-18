import os
import stat
import tempfile
import time
import unittest
from pathlib import Path
from unittest import mock

from tools.pentad_worker_cache import WorkerCache, cache_key, content_hash, default_root, stat_key


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

    def test_clear_removes_only_cache_files_inside_the_root(self):
        cache = WorkerCache(self.root)
        for index in range(3):
            cache.put(self.key(index), {'text': str(index)})
        (self.root / '.tmp-left').write_text('partial')
        (self.root / 'notes.txt').write_text('not ours')
        (self.root / 'nested').mkdir()
        outside = Path(self.directory.name) / 'outside.json'
        outside.write_text('{}')
        (self.root / f'{self.key(9)}.json').symlink_to(outside)
        self.assertEqual(cache.clear(), 3)
        self.assertEqual(sorted(path.name for path in self.root.iterdir()), sorted(['notes.txt', 'nested', f'{self.key(9)}.json']))
        self.assertTrue(outside.exists())
        self.assertEqual(cache.stats()['entries'], 0)
        self.assertIsNone(cache.get(self.key(1)))
        self.assertTrue(cache.put(self.key(1), {'text': 'again'}))

    def test_clear_refuses_a_root_that_became_a_symlink(self):
        cache = WorkerCache(self.root)
        cache.put(self.key(1), {'text': 'one'})
        target = Path(self.directory.name) / 'elsewhere'
        self.root.rename(target)
        self.root.symlink_to(target)
        self.assertEqual(cache.clear(), 0)
        self.assertEqual([path.name for path in target.iterdir()], [f'{self.key(1)}.json'])

    def test_clear_on_a_disabled_cache_does_nothing(self):
        self.assertEqual(WorkerCache(self.root, max_bytes=0).clear(), 0)

    def test_input_index_entries_share_the_cache_but_not_its_counters(self):
        cache = WorkerCache(self.root)
        source = Path(self.directory.name) / 'input.bin'
        source.write_bytes(b'abc')
        info = os.stat(source)
        key = stat_key(str(source), info)
        self.assertNotIn(key, {self.key(index) for index in range(3)})
        self.assertIsNone(cache.input_hash(key))
        digest = content_hash(b'abc')
        self.assertTrue(cache.remember_input(key, digest))
        self.assertEqual(cache.input_hash(key), digest)
        self.assertFalse(cache.remember_input(key, 'not a hash'))
        path = self.root / f'{key}.json'
        self.assertEqual(stat.S_IMODE(path.stat().st_mode), 0o600)
        stats = cache.stats()
        self.assertEqual((stats['hits'], stats['misses'], stats['stores'], stats['entries']), (0, 0, 0, 1))
        # Every stat field is part of the key.
        for field in ('st_dev', 'st_ino', 'st_size', 'st_mtime_ns', 'st_ctime_ns'):
            changed = mock.Mock(**{name: getattr(info, name) for name in
                                   ('st_dev', 'st_ino', 'st_size', 'st_mtime_ns', 'st_ctime_ns')})
            setattr(changed, field, getattr(info, field) + 1)
            with self.subTest(field=field):
                self.assertNotEqual(stat_key(str(source), changed), key)
        self.assertNotEqual(stat_key(str(source) + 'x', info), key)
        # A damaged entry is no hash; forget removes an entry.
        path.write_text('{"format":1,"key":"%s","value":{"inputHash":"zz"}}' % key)
        self.assertIsNone(cache.input_hash(key))
        cache.remember_input(key, digest)
        cache.forget(key)
        self.assertFalse(path.exists())
        self.assertIsNone(cache.input_hash(key))

    def test_input_index_entries_are_evicted_with_the_cache(self):
        cache = WorkerCache(self.root, max_entries=2)
        keys = [stat_key(f'/input/{index}', os.stat(self.directory.name)) for index in range(3)]
        past = time.time() - 1000
        for index, key in enumerate(keys):
            cache.remember_input(key, content_hash(str(index).encode()))
            os.utime(self.root / f'{key}.json', (past + index, past + index))
            cache._index[f'{key}.json'] = (past + index, cache._index[f'{key}.json'][1])
        self.assertEqual(cache.stats()['entries'], 2)
        self.assertIsNone(cache.input_hash(keys[0]))
        self.assertIsNotNone(cache.input_hash(keys[2]))
        self.assertFalse(WorkerCache(self.root, max_bytes=0).remember_input(keys[0], content_hash(b'0')))


if __name__ == '__main__':
    unittest.main()
