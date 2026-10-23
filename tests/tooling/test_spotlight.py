import base64
import gzip
import io
import json
import os
from pathlib import Path
import subprocess
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

    def test_file_search_keeps_visible_home_matches_and_uses_argv(self):
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory) / 'home'
            config = home / '.config'
            pictures = home / 'Bilder'
            (pictures / 'Trip').mkdir(parents=True)
            config.mkdir()
            (config / 'user-dirs.dirs').write_text('XDG_PICTURES_DIR="$HOME/Bilder"\nXDG_DOWNLOAD_DIR="$HOME"\n')
            photo = pictures / 'Trip' / 'Sea Sunset.png'
            photo.write_bytes(b'x' * 10)
            hidden = home / '.cache' / 'sea sunset.png'
            hidden.parent.mkdir()
            hidden.write_bytes(b'')
            outside = Path(directory) / 'sea sunset.png'
            outside.write_bytes(b'')
            found = [str(photo), str(hidden), str(outside), str(pictures / 'Trip' / 'sea.txt'), str(photo)]
            with patch.object(spotlight, 'search_paths', side_effect=[found, []]) as search:
                files = spotlight.find_files('sea SUNSET', home, config)
            self.assertEqual([item['path'] for item in files], [str(photo)])
            self.assertEqual(files[0]['folder'], '~/Bilder/Trip')
            self.assertEqual((files[0]['size'], files[0]['directory']), (10, False))
            fd = search.call_args_list[0].args[0]
            self.assertEqual(fd[0], 'fd')
            self.assertEqual(fd[fd.index('--') + 1:], ['sea', str(pictures)], 'the home directory itself is never walked')
            self.assertEqual(search.call_args_list[1].args[0][-2:], ['sea', 'sunset'])
        for query in ('', ' ', 'a', 'x' * 300):
            with self.assertRaises(ValueError):
                spotlight.find_files(query, Path('/nonexistent'), Path('/nonexistent'))

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

def write_bundle(path, rows_by_locale):
    path.write_text(json.dumps({'locales': {
        locale: base64.b64encode(gzip.compress(json.dumps(rows).encode())).decode()
        for locale, rows in rows_by_locale.items()}}))

def serve_lines(lines, state_root='', emoji_path=''):
    stdout = io.BytesIO()
    spotlight.serve(state_root, emoji_path, io.BytesIO(b''.join(lines)), stdout)
    return [json.loads(line) for line in stdout.getvalue().splitlines()]

class SpotlightServeTest(unittest.TestCase):
    def test_serve_answers_each_line_in_order_and_echoes_ids(self):
        with tempfile.TemporaryDirectory() as directory:
            emoji = Path(directory) / 'emoji.json'
            rows = [['🔥', 'fire', ['hot'], 'fire']]
            write_bundle(emoji, {'en': rows})
            replies = serve_lines([
                b'{"id":1,"request":{"operation":"history"}}\n',
                b'not json\n',
                b'\n',
                b'{"id":3,"request":{"operation":"unknown"}}\n',
                b'{"id":4,"request":["history"]}\n',
                b'{"request":{"operation":"history"}}\n',
                b'{"id":6,"request":{"operation":"emoji","languages":["en","missing"]}}\n',
                b'{"id":7,"request":{"operation":"emoji","languages":"en"}}',
            ], Path(directory) / 'pentad', emoji)
        self.assertEqual([reply['id'] for reply in replies], [1, None, 3, 4, None, 6, 7])
        self.assertEqual(replies[0]['result'], {'ok': True, 'history': {'version': 1, 'pinned': [], 'recent': []}})
        for index in (1, 2, 3, 4, 6):
            self.assertEqual(replies[index]['result']['ok'], False)
            self.assertEqual(replies[index]['result']['reason'], 'io')
        self.assertEqual(replies[5]['result'], {'ok': True, 'records': {'en': rows}})

    def test_serve_keeps_running_after_unexpected_errors(self):
        with patch.object(spotlight, 'handle', side_effect=[KeyError('locales'), {'ok': True}]):
            replies = serve_lines([b'{"id":1,"request":{}}\n', b'{"id":2,"request":{}}\n'])
        self.assertEqual(replies, [{'id': 1, 'result': {'ok': False, 'reason': 'io', 'message': 'KeyError'}},
                                   {'id': 2, 'result': {'ok': True}}])

    def test_serve_rejects_an_oversized_line_by_its_id_and_reads_on(self):
        huge = b'{"id":9,"request":{"operation":"copy-text","text":"' + b'x' * (spotlight.REQUEST_LIMIT * 2) + b'"}}\n'
        with patch.object(spotlight, 'command') as command:
            replies = serve_lines([huge, b'{"id":10,"request":{"operation":"history"}}\n'])
            command.assert_not_called()
        self.assertEqual(replies[0], {'id': 9, 'result': {'ok': False, 'reason': 'io', 'message': 'ValueError'}})
        self.assertEqual(replies[1]['id'], 10)
        self.assertTrue(replies[1]['result']['ok'])

    def test_serve_bounds_reply_size(self):
        with patch.object(spotlight, 'REPLY_LIMIT', 64), patch.object(spotlight, 'handle', return_value={'ok': True, 'text': 'x' * 100}):
            replies = serve_lines([b'{"id":1,"request":{}}\n'])
        self.assertEqual(replies, [{'id': 1, 'result': {'ok': False, 'reason': 'io', 'message': 'TooLarge'}}])

    def test_serve_parses_the_emoji_bundle_once_until_the_file_changes(self):
        with tempfile.TemporaryDirectory() as directory:
            emoji = Path(directory) / 'emoji.json'
            write_bundle(emoji, {'en': [['🔥', 'fire', [], 'fire']], 'uk': [['🔥', 'вогонь', [], 'fire']]})
            request = b'{"id":%d,"request":{"operation":"emoji","languages":["en","uk"]}}\n'
            reads = []
            original = Path.read_bytes
            def counted(path):
                reads.append(path)
                return original(path)
            with patch.object(spotlight.Path, 'read_bytes', counted):
                first = serve_lines([request % 1, request % 2], '', emoji)
                self.assertEqual(len(reads), 1)
                self.assertEqual(first[0]['result'], first[1]['result'])
                self.assertEqual(first[0]['result']['records']['uk'], [['🔥', 'вогонь', [], 'fire']])
                cache = {}
                spotlight.emoji_records(emoji, ['en'], cache)
                write_bundle(emoji, {'en': [['💧', 'droplet', [], 'droplet']]})
                os.utime(emoji, ns=(1, 1))
                self.assertEqual(spotlight.emoji_records(emoji, ['en', 'uk'], cache), {'en': [['💧', 'droplet', [], 'droplet']]})
                self.assertEqual(len(reads), 3)

    def test_serve_process_answers_several_requests_and_exits_when_stdin_closes(self):
        with tempfile.TemporaryDirectory() as directory:
            emoji = Path(directory) / 'emoji.json'
            write_bundle(emoji, {'en': [['🔥', 'fire', [], 'fire']]})
            helper = Path(__file__).resolve().parents[2] / 'tools' / 'pentad_spotlight.py'
            process = subprocess.Popen([sys.executable, str(helper), '--state-root', str(Path(directory) / 'state'),
                                        '--emoji-data', str(emoji), '--serve'],
                                       stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            try:
                for identity in (1, 2, 3):
                    process.stdin.write(b'{"id":%d,"request":{"operation":"emoji","languages":["en"]}}\n' % identity)
                    process.stdin.flush()
                    reply = json.loads(process.stdout.readline())
                    self.assertEqual(reply['id'], identity)
                    self.assertEqual(reply['result']['records']['en'][0][0], '🔥')
                process.stdin.close()
                self.assertEqual(process.wait(timeout=10), 0)
            finally:
                if process.poll() is None:
                    process.kill()
                    process.wait(timeout=10)
                process.stdout.close()
                process.stderr.close()

class SteamIconsTest(unittest.TestCase):
    def test_finds_each_games_cached_client_icon_and_ignores_artwork(self):
        with tempfile.TemporaryDirectory() as home:
            cache = Path(home) / '.local/share/Steam/appcache/librarycache'
            icon = 'a' * 40 + '.jpg'
            (cache / '730').mkdir(parents=True)
            for name in (icon, 'logo.png', 'library_hero.jpg', 'header.jpg'):
                (cache / '730' / name).write_bytes(b'x')
            (cache / '999').mkdir()
            (cache / '999' / 'header.jpg').write_bytes(b'x')
            (cache / 'not-a-game').mkdir()
            with patch.object(Path, 'home', return_value=Path(home)):
                reply = spotlight.handle({'operation': 'steam-icons'}, '', '')
            self.assertEqual(reply, dict(ok=True, icons={'730': str(cache / '730' / icon)}))

    def test_missing_steam_is_an_empty_result(self):
        with tempfile.TemporaryDirectory() as home, patch.object(Path, 'home', return_value=Path(home)):
            self.assertEqual(spotlight.handle({'operation': 'steam-icons'}, '', ''), dict(ok=True, icons={}))

if __name__ == '__main__':
    unittest.main()
