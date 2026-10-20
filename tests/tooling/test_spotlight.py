import base64
import gzip
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'tools'))
import pentad_spotlight as spotlight

class SpotlightPortsTest(unittest.TestCase):
    def test_preserves_ags_history_and_updates_counts_and_pins_atomically(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory) / 'pentad'
            self.assertEqual(spotlight.handle({'operation': 'history'}, root, '')['history']['recent'], [])
            root.mkdir()
            original = {'version': 1, 'pinned': ['app-firefox.desktop'],
                        'recent': [{'id': 'app-firefox.desktop', 'count': 7, 'used': 10}]}
            (root / 'spotlight.json').write_text(json.dumps(original))
            reply = spotlight.handle({'operation': 'record', 'id': 'app-firefox.desktop'}, root, '')
            self.assertEqual(reply['history']['recent'][0]['count'], 8)
            self.assertEqual(reply['history']['pinned'], original['pinned'])
            reply = spotlight.handle({'operation': 'pin', 'id': 'app-terminal.desktop'}, root, '')
            self.assertIn('app-terminal.desktop', reply['history']['pinned'])
            self.assertEqual(json.loads((root / 'spotlight.json').read_text()), reply['history'])
            self.assertEqual(list(root.glob('*.tmp')), [])

    def test_binary_clipboard_copy_and_delete_use_only_validated_argv(self):
        binary = b'\x89PNG\r\n\x1a\n\x00\xff\x00'
        with patch.object(spotlight, 'command', side_effect=[binary, b'']) as command:
            self.assertTrue(spotlight.handle({'operation': 'copy-clip', 'id': '42'}, '', '')['ok'])
            self.assertEqual(command.call_args_list[0].args, (['cliphist', 'decode', '42'],))
            self.assertEqual(command.call_args_list[1].args, (['wl-copy'], binary))
        with patch.object(spotlight, 'command') as command:
            with self.assertRaises(ValueError):
                spotlight.handle({'operation': 'delete-clip', 'id': '42;echo bad'}, '', '')
            command.assert_not_called()

    def test_emoji_bundle_decodes_requested_locales_without_extra_dependencies(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'emoji.json'
            rows = [['🔥', 'fire', ['hot'], 'fire']]
            path.write_text(json.dumps({'locales': {'en': base64.b64encode(gzip.compress(json.dumps(rows).encode())).decode()}}))
            self.assertEqual(spotlight.handle({'operation': 'emoji', 'languages': ['en', 'missing']}, '', path)['records'], {'en': rows})

    def test_emoji_auto_language_uses_keyboard_layouts_without_input_events(self):
        with patch.object(spotlight, 'command', return_value=b'{"keyboards":[{"layout":"de,ua"},{"layout":"de,ua"}]}') as command:
            self.assertEqual(spotlight.handle({'operation': 'keyboard-layouts'}, '', '')['layouts'], ['de,ua'])
            command.assert_called_once_with(['hyprctl', '-j', 'devices'])

    def test_emoji_auto_language_falls_back_to_hyprland_global_layout(self):
        with patch.object(spotlight, 'command', side_effect=[
                b'{"keyboards":[]}', b'{"str":"de,ua"}']) as command:
            self.assertEqual(spotlight.handle({'operation': 'keyboard-layouts'}, '', '')['layouts'], ['de,ua'])
            self.assertEqual(command.call_args_list[1].args[0], ['hyprctl', '-j', 'getoption', 'input:kb_layout'])
        with patch.object(spotlight, 'command', side_effect=[OSError(), b'{"str":"uk"}']):
            self.assertEqual(spotlight.handle({'operation': 'keyboard-layouts'}, '', '')['layouts'], ['uk'])
        with patch.object(spotlight, 'command', side_effect=[b'{"keyboards":[{}]}', OSError()]):
            self.assertEqual(spotlight.handle({'operation': 'keyboard-layouts'}, '', '')['layouts'], [])

    def test_clipboard_image_preview_sniffs_common_image_formats(self):
        fixtures = [
            (b'\x89PNG\r\n\x1a\nbytes', 'image/png'),
            (b'\xff\xd8\xffbytes', 'image/jpeg'),
            (b'GIF89abytes', 'image/gif'),
            (b'RIFF0000WEBPbytes', 'image/webp'),
            (b'BMbytes', 'image/bmp'),
        ]
        for payload, mime in fixtures:
            with self.subTest(mime=mime), patch.object(spotlight, 'command', return_value=payload):
                reply = spotlight.handle({'operation': 'preview-clip', 'id': '42'}, '', '')
                self.assertTrue(reply['ok'])
                self.assertTrue(reply['image'].startswith(f'data:{mime};base64,'))

if __name__ == '__main__':
    unittest.main()
