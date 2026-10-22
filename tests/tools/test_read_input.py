import tempfile
import unittest
from pathlib import Path
from urllib.parse import quote

from tools.pentad_read_input import read_inputs

class ReadInputTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.root = Path(self.directory.name)

    def tearDown(self):
        self.directory.cleanup()

    def uri(self, name):
        return 'file://' + quote(str(self.root / name), safe='/')

    def test_reads_bounded_utf8_text_and_json(self):
        (self.root / 'words.txt').write_text('Grüße', encoding='utf-8')
        (self.root / 'data.json').write_text('{"ok":true}', encoding='utf-8')
        result = read_inputs({'uris': [self.uri('words.txt'), self.uri('data.json')], 'maxBytes': 64})
        self.assertEqual([item['value'] for item in result['items']], ['Grüße', '{"ok":true}'])
        self.assertIn('text/plain', result['items'][0]['compatibleTypes'])
        self.assertIn('application/json', result['items'][1]['compatibleTypes'])

    def test_reports_image_and_pdf_types_without_reading_as_text(self):
        (self.root / 'picture.png').write_bytes(b'\x89PNG\r\n')
        (self.root / 'document.pdf').write_bytes(b'%PDF-')
        items = read_inputs({'uris': [self.uri('picture.png'), self.uri('document.pdf')], 'maxBytes': 64})['items']
        self.assertEqual([item['mimeType'] for item in items], ['image/png', 'application/pdf'])
        self.assertTrue(all('value' not in item for item in items))

    def test_sniffs_renamed_binary_and_decodes_percent_once(self):
        (self.root / 'literal%20name.txt').write_text('hello', encoding='utf-8')
        (self.root / 'renamed.txt').write_bytes(b'\x89PNG\r\n\x1a\ncontent')
        items = read_inputs({'uris': [self.uri('literal%20name.txt'), self.uri('renamed.txt')], 'maxBytes': 64})['items']
        self.assertEqual(items[0]['value'], 'hello')
        self.assertEqual(items[1]['mimeType'], 'image/png')

    def test_describes_large_binary_files_by_reference_and_keeps_text_uris(self):
        (self.root / 'movie.mkv').write_bytes(b'\x1a\x45\xdf\xa3' + b'\0' * 200)
        (self.root / 'bundle.bin').write_bytes(b'PK\x03\x04' + b'\0' * 200)
        (self.root / 'clip.dat').write_bytes(b'\0\0\0\x18ftypmp42' + b'\0' * 200)
        (self.root / 'backup.gz').write_bytes(b'\x00' * 200)
        (self.root / 'note.txt').write_text('hi', encoding='utf-8')
        items = read_inputs({'uris': [self.uri(name) for name in ['movie.mkv', 'bundle.bin', 'clip.dat', 'backup.gz', 'note.txt']], 'maxBytes': 64})['items']
        self.assertEqual([item['mimeType'] for item in items], ['video/x-matroska', 'application/zip', 'video/mp4', 'application/gzip', 'text/plain'])
        self.assertTrue(all('value' not in item and item['sizeBytes'] > 64 for item in items[:4]))
        self.assertEqual(items[4]['uri'], self.uri('note.txt'))
        self.assertTrue(all(item['compatibleTypes'][-1] == 'application/x-pentad-local-file' for item in items))
        self.assertEqual(items[0]['compatibleTypes'][0], 'video/x-matroska')

    def test_rejects_oversize_binary_invalid_utf8_and_non_file_uri(self):
        (self.root / 'large.txt').write_text('x' * 10, encoding='utf-8')
        (self.root / 'binary.txt').write_bytes(b'\x00x')
        (self.root / 'invalid.txt').write_bytes(b'\xff')
        for uri in [self.uri('large.txt'), self.uri('binary.txt'), self.uri('invalid.txt'), 'https://example.test/file.txt']:
            with self.subTest(uri=uri), self.assertRaises((ValueError, UnicodeError)):
                read_inputs({'uris': [uri], 'maxBytes': 4})

    def test_rejects_directory_and_file_uri_query_or_fragment(self):
        with self.assertRaises(ValueError):
            read_inputs({'uris': [self.uri('.')], 'maxBytes': 64})
        for suffix in ['?download=1', '#fragment']:
            with self.subTest(suffix=suffix), self.assertRaises(ValueError):
                read_inputs({'uris': [self.uri('words.txt') + suffix], 'maxBytes': 64})

if __name__ == '__main__':
    unittest.main()
