import json
import os
import shutil
import signal
import subprocess
import sys
import tempfile
import time
import unittest
import zipfile
from pathlib import Path
from urllib.parse import quote

from tools import pentad_file_tool as tool
from tools.pentad_file_tool import ToolError, execute, page_ranges, parse_pages, parse_time, split_name

HELPER = Path(tool.__file__).resolve()
have = shutil.which


def uri(path):
    return 'file://' + quote(str(path), safe='/')


class PureLogicTests(unittest.TestCase):
    def test_parses_page_lists_ranges_open_ends_and_last_page(self):
        self.assertEqual(parse_pages('1-3, 5, 8-', 9), [1, 2, 3, 5, 8, 9])
        self.assertEqual(parse_pages('-2,z', 4), [1, 2, 4])
        self.assertEqual(parse_pages('3-1', 3), [3, 2, 1])
        self.assertEqual(parse_pages('2,2,1-2', 3), [2, 1])
        for spec in ['', '0', '5', '1-x', 'a', '1--2']:
            with self.subTest(spec=spec), self.assertRaises(ToolError):
                parse_pages(spec, 4)

    def test_compresses_page_lists_for_qpdf(self):
        self.assertEqual(page_ranges([1, 2, 3, 7, 9, 10]), '1-3,7,9-10')
        self.assertEqual(page_ranges([3, 2]), '3,2')

    def test_reads_times_and_stacked_archive_suffixes(self):
        self.assertEqual(parse_time('75', 'Start'), 75)
        self.assertEqual(parse_time('1:15', 'Start'), 75)
        self.assertEqual(parse_time('1:00:01.5', 'Start'), 3601.5)
        self.assertIsNone(parse_time('', 'End'))
        with self.assertRaises(ToolError):
            parse_time('1m', 'Start')
        self.assertEqual(split_name('backup.tar.gz'), ('backup', '.tar.gz'))
        self.assertEqual(split_name('photo.JPG'), ('photo', '.JPG'))
        self.assertEqual(split_name('.bashrc'), ('.bashrc', ''))


class FileOperationTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.root = Path(self.directory.name)

    def tearDown(self):
        self.directory.cleanup()

    def run_op(self, operation, paths, **options):
        return execute({'operation': operation, 'inputs': [uri(path) for path in paths], 'options': options})

    def assert_no_work_dirs(self):
        self.assertEqual([path.name for path in self.root.iterdir() if path.name.startswith('.pentad-tool-')], [])

    def make_pdf(self, name='doc.pdf', pages=3):
        path = self.root / name
        frames = [arg for index in range(pages) for arg in ('-size', '120x160', f'xc:gray{20 + index * 20}')]
        subprocess.run(['magick', *frames, str(path)], check=True)
        return path

    def make_image(self, name='photo.png', size='64x48'):
        path = self.root / name
        subprocess.run(['magick', '-size', size, 'gradient:red-blue', str(path)], check=True)
        return path

    def test_rejects_unknown_operations_missing_files_and_wrong_counts(self):
        with self.assertRaises(ToolError):
            execute({'operation': 'shell', 'inputs': []})
        with self.assertRaises(ToolError):
            self.run_op('pdf.merge', [self.root / 'missing.pdf'])
        with self.assertRaises(ToolError):
            execute({'operation': 'pdf.extract', 'inputs': ['https://example.test/a.pdf'], 'options': {}})

    @unittest.skipUnless(have('qpdf') and have('magick'), 'qpdf and ImageMagick are required')
    def test_pdf_page_operations_write_new_files_and_never_overwrite(self):
        pdf = self.make_pdf()
        (self.root / 'doc-pages.pdf').write_bytes(b'keep me')
        first = self.run_op('pdf.extract', [pdf], pages='3,1')
        self.assertEqual(first['outputs'][0]['name'], 'doc-pages (2).pdf')
        self.assertEqual((self.root / 'doc-pages.pdf').read_bytes(), b'keep me')
        count = lambda name: int(subprocess.run(['qpdf', '--show-npages', str(self.root / name)], capture_output=True, text=True).stdout)
        self.assertEqual(count('doc-pages (2).pdf'), 2)
        self.assertEqual(count(self.run_op('pdf.delete', [pdf], pages='2')['outputs'][0]['name']), 2)
        with self.assertRaises(ToolError):
            self.run_op('pdf.delete', [pdf], pages='1-z')
        merged = self.run_op('pdf.merge', [pdf, pdf])
        self.assertEqual(count(merged['outputs'][0]['name']), 6)
        split = self.run_op('pdf.split', [pdf], every='2')
        self.assertEqual(split['outputs'][0]['kind'], 'folder')
        self.assertEqual(sorted(path.name for path in (self.root / 'doc-split').iterdir()), ['doc 1-2.pdf', 'doc 3-3.pdf'])
        self.assertEqual(self.run_op('pdf.rotate', [pdf], angle='90')['outputs'][0]['name'], 'doc-rotated.pdf')
        self.assertTrue(pdf.exists())
        self.assert_no_work_dirs()

    @unittest.skipUnless(have('qpdf') and have('magick'), 'qpdf and ImageMagick are required')
    def test_pdf_lock_and_unlock_round_trip_without_password_in_arguments(self):
        pdf = self.make_pdf(pages=1)
        locked = self.root / self.run_op('pdf.lock', [pdf], password='two words')['outputs'][0]['name']
        self.assertEqual(subprocess.run(['qpdf', '--requires-password', str(locked)]).returncode, 0)
        with self.assertRaises(ToolError) as wrong:
            self.run_op('pdf.unlock', [locked], password='nope')
        self.assertIn('Wrong password', str(wrong.exception))
        with self.assertRaises(ToolError) as protected:
            self.run_op('pdf.compress', [locked])
        self.assertIn('password-protected', str(protected.exception))
        unlocked = self.root / self.run_op('pdf.unlock', [locked], password='two words')['outputs'][0]['name']
        self.assertEqual(subprocess.run(['qpdf', '--requires-password', str(unlocked)]).returncode, 2)
        with self.assertRaises(ToolError):
            self.run_op('pdf.lock', [pdf], password='line\nbreak')

    @unittest.skipUnless(have('pdftoppm') and have('pdftotext') and have('gs') and have('magick') and have('qpdf'), 'poppler and Ghostscript are required')
    def test_pdf_render_text_and_compress(self):
        pdf = self.make_pdf(pages=2)
        rendered = self.run_op('pdf.images', [pdf], format='png', dpi='72')
        self.assertEqual(len(list((self.root / rendered['outputs'][0]['name']).iterdir())), 2)
        text = self.run_op('pdf.text', [pdf])
        self.assertEqual(text['outputs'][0]['name'], 'doc.txt')
        compressed = self.run_op('pdf.compress', [pdf], level='screen')
        self.assertIn('summary', compressed)
        fake = self.root / 'fake.pdf'
        fake.write_bytes(self.make_image().read_bytes())
        with self.assertRaises(ToolError):
            self.run_op('pdf.text', [fake])

    @unittest.skipUnless(have('magick'), 'ImageMagick is required')
    def test_image_operations_batch_and_keep_originals(self):
        first, second = self.make_image('a.png'), self.make_image('b.png', '200x100')
        converted = self.run_op('image.convert', [first, second], format='webp')
        self.assertEqual([item['name'] for item in converted['outputs']], ['a.webp', 'b.webp'])
        self.assertEqual(self.run_op('image.convert', [first], format='webp')['outputs'][0]['name'], 'a (2).webp')
        resized = self.run_op('image.resize', [second], size='50%')['outputs'][0]
        geometry = subprocess.run(['magick', 'identify', '-format', '%wx%h', str(self.root / resized['name'])], capture_output=True, text=True).stdout
        self.assertEqual(geometry, '100x50')
        self.assertEqual(self.run_op('image.rotate', [first], transform='flip-h')['outputs'][0]['name'], 'a-rotated.png')
        self.assertEqual(self.run_op('image.strip', [first])['outputs'][0]['name'], 'a-clean.png')
        self.assertEqual(self.run_op('image.pdf', [first, second])['outputs'][0]['name'], 'a.pdf')
        with self.assertRaises(ToolError):
            self.run_op('image.convert', [first], format='exe')
        self.assertTrue(first.exists() and second.exists())
        self.assert_no_work_dirs()

    @unittest.skipUnless(have('qrencode') and have('zbarimg'), 'qrencode and zbar are required')
    def test_reads_qr_codes_and_reports_absent_codes(self):
        code = self.root / 'code.png'
        subprocess.run(['qrencode', '-o', str(code), 'hello pentad'], check=True)
        self.assertEqual(self.run_op('image.barcode', [code])['text'], 'hello pentad')
        if have('magick'):
            self.assertEqual(self.run_op('image.barcode', [self.make_image()])['summary'], 'No QR code or barcode found')

    @unittest.skipUnless(have('ffmpeg'), 'ffmpeg is required')
    def test_media_operations(self):
        video = self.root / 'clip.mkv'
        subprocess.run(['ffmpeg', '-nostdin', '-loglevel', 'error', '-f', 'lavfi', '-i', 'testsrc=duration=2:size=160x120:rate=10',
                        '-f', 'lavfi', '-i', 'sine=duration=2', '-shortest', '-c:v', 'libx264', '-c:a', 'aac', str(video)], check=True)
        self.assertEqual(self.run_op('media.gif', [video], width='320', fps='10')['outputs'][0]['name'], 'clip.gif')
        self.assertEqual(self.run_op('media.audio', [video], format='opus')['outputs'][0]['name'], 'clip.opus')
        self.assertEqual(self.run_op('media.video', [video], quality='small', height='480')['outputs'][0]['name'], 'clip.mp4')
        self.assertEqual(self.run_op('media.trim', [video], start='0.5', end='1:01')['outputs'][0]['name'], 'clip-trimmed.mkv')
        with self.assertRaises(ToolError):
            self.run_op('media.trim', [video], start='2', end='1')
        silent = self.root / 'silent.mp4'
        subprocess.run(['ffmpeg', '-nostdin', '-loglevel', 'error', '-f', 'lavfi', '-i', 'testsrc=duration=1', '-c:v', 'libx264', str(silent)], check=True)
        with self.assertRaises(ToolError) as error:
            self.run_op('media.audio', [silent])
        self.assertIn('no audio', str(error.exception))

    @unittest.skipUnless(have('7z') and have('tar'), '7-Zip and tar are required')
    def test_archive_round_trips_and_encrypted_archives(self):
        (self.root / 'one').mkdir()
        (self.root / 'two').mkdir()
        first, second = self.root / 'one' / 'note.txt', self.root / 'two' / 'note.txt'
        first.write_text('first')
        second.write_text('second')
        packed = self.run_op('archive.create', [first, second], format='zip')['outputs'][0]
        archive = self.root / 'one' / packed['name']
        self.assertEqual(sorted(zipfile.ZipFile(archive).namelist()), ['note (2).txt', 'note.txt'])
        extracted = self.run_op('archive.extract', [archive])['outputs'][0]
        self.assertEqual((self.root / 'one' / extracted['name'] / 'note (2).txt').read_text(), 'second')
        tarball = self.run_op('archive.create', [first], format='tar.zst')['outputs'][0]
        self.assertEqual(tarball['name'], 'note.tar.zst')
        unpacked = self.run_op('archive.extract', [self.root / 'one' / tarball['name']])['outputs'][0]
        self.assertEqual(unpacked['name'], 'note')
        secret = self.root / 'secret.7z'
        subprocess.run(['7z', 'a', '-pSecret', '-mhe=on', str(secret), str(first)], check=True, capture_output=True)
        with self.assertRaises(ToolError) as locked:
            self.run_op('archive.extract', [secret])
        self.assertIn('encrypted', str(locked.exception))
        opened = self.run_op('archive.extract', [secret], password='Secret')['outputs'][0]
        self.assertEqual((self.root / opened['name'] / 'note.txt').read_text(), 'first')
        self.assert_no_work_dirs()

    def test_checksums_files_and_text_and_compares(self):
        path = self.root / 'data.bin'
        path.write_bytes(b'abc')
        sha = 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad'
        result = self.run_op('checksum', [path], expected=sha.upper())
        self.assertEqual(result['text'], f'{sha}  data.bin')
        self.assertTrue(result['match'])
        self.assertFalse(self.run_op('checksum', [path], algorithm='md5', expected='00')['match'])
        self.assertEqual(execute({'operation': 'checksum', 'inputs': [], 'text': 'abc', 'options': {}})['text'], sha)
        with self.assertRaises(ToolError):
            self.run_op('checksum', [path], algorithm='crc')


class ProcessTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.root = Path(self.directory.name)

    def tearDown(self):
        self.directory.cleanup()

    def test_sigterm_stops_the_cli_and_removes_partial_work(self):
        fake = self.root / 'bin'
        fake.mkdir()
        marker = self.root / 'started'
        script = fake / 'qpdf'
        script.write_text(f'#!/bin/sh\necho $$ > {marker}\nexec sleep 30\n')
        script.chmod(0o755)
        pdf = self.root / 'doc.pdf'
        pdf.write_bytes(b'%PDF-1.4\n')
        request = json.dumps({'operation': 'pdf.extract', 'inputs': [uri(pdf)], 'options': {'pages': '1'}}).encode()
        env = dict(os.environ, PATH=f'{fake}:{os.environ.get("PATH", "")}')
        process = subprocess.Popen([sys.executable, '-I', str(HELPER)], stdin=subprocess.PIPE, stdout=subprocess.PIPE, env=env)
        try:
            process.stdin.write(request)
            process.stdin.close()
            deadline = time.monotonic() + 10
            while not marker.exists() and time.monotonic() < deadline:
                time.sleep(0.05)
            self.assertTrue(marker.exists(), 'fake CLI never started')
            child = int(marker.read_text())
            process.send_signal(signal.SIGTERM)
            result = json.loads(process.stdout.read())
            self.assertEqual(process.wait(timeout=10), 0)
        finally:
            if process.poll() is None:
                process.kill()
                process.wait()
        self.assertTrue(result['cancelled'])
        with self.assertRaises(ProcessLookupError):
            os.kill(child, 0)
        self.assertEqual([path.name for path in self.root.iterdir() if path.name.startswith('.pentad-tool-')], [])

    def test_reports_invalid_requests_as_json(self):
        result = subprocess.run([sys.executable, '-I', str(HELPER)], input=b'not json', capture_output=True, timeout=10)
        self.assertEqual(result.returncode, 0)
        self.assertFalse(json.loads(result.stdout)['ok'])


if __name__ == '__main__':
    unittest.main()
