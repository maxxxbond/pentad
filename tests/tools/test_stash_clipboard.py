import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
CLIPBOARD = REPO / 'tools' / 'pentad_stash_clipboard.py'
PREVIEW = REPO / 'tools' / 'pentad_shelf_preview.py'

FAKE_PASTE = r'''#!/bin/sh
# Fake wl-paste: types come from $FAKE/types, content from $FAKE/data/<type with / ; = replaced by _>.
if [ "$1" = "--list-types" ]; then
  cat "$FAKE/types" 2>/dev/null
  exit "$(cat "$FAKE/list-status" 2>/dev/null || echo 0)"
fi
type=""
while [ $# -gt 0 ]; do
  if [ "$1" = "--type" ]; then type="$2"; shift; fi
  shift
done
name=$(printf '%s' "$type" | tr '/;=' '___')
cat "$FAKE/data/$name"
'''

FAKE_COPY = r'''#!/bin/sh
printf '%s\n' "$@" > "$FAKE/copy-args"
cat > "$FAKE/copy-stdin"
'''


class ClipboardCase(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        root = Path(self.tmp.name)
        self.bin = root / 'bin'
        self.fake = root / 'fake'
        self.state = root / 'state'
        self.stash = root / 'stash'
        for directory in (self.bin, self.fake / 'data', self.state):
            directory.mkdir(parents=True)
        for name, body in (('wl-paste', FAKE_PASTE), ('wl-copy', FAKE_COPY)):
            script = self.bin / name
            script.write_text(body)
            script.chmod(0o755)

    def env(self, path=None):
        env = {key: value for key, value in os.environ.items() if key not in ('WAYLAND_DISPLAY', 'XDG_STATE_HOME')}
        env['PATH'] = path if path is not None else f'{self.bin}:/usr/bin:/bin'
        env['XDG_STATE_HOME'] = str(self.state)
        env['FAKE'] = str(self.fake)
        return env

    def offer(self, types):
        (self.fake / 'types').write_text(''.join(t + '\n' for t in types))

    def put(self, mime, content):
        name = mime.replace('/', '_').replace(';', '_').replace('=', '_')
        (self.fake / 'data' / name).write_bytes(content)

    def empty_path(self):
        empty = Path(self.tmp.name) / 'empty'
        empty.mkdir(exist_ok=True)
        return str(empty)

    def run_helper(self, request, helper=CLIPBOARD, env=None):
        result = subprocess.run([sys.executable, '-I', str(helper)], input=json.dumps(request).encode(),
                                capture_output=True, env=env or self.env(), timeout=20)
        self.assertEqual(result.returncode, 0, result.stderr)
        lines = result.stdout.decode().strip().splitlines()
        self.assertEqual(len(lines), 1)
        return json.loads(lines[0])


class PasteTests(ClipboardCase):
    def test_paste_prefers_image(self):
        png = b'\x89PNG\r\n\x1a\n' + bytes(range(256))
        self.offer(['text/plain', 'image/png'])
        self.put('image/png', png)
        self.put('text/plain', b'hello')
        result = self.run_helper({'operation': 'paste', 'stashDir': str(self.stash)})
        self.assertTrue(result['ok'])
        self.assertEqual(len(result['items']), 1)
        item = result['items'][0]
        self.assertTrue(item['owned'])
        saved = self.stash / item['label']
        self.assertRegex(item['label'], r'^clip-\d{8}-\d{6}-[0-9a-f]{4}\.png$')
        self.assertEqual(item['uri'], saved.as_uri())
        self.assertEqual(saved.read_bytes(), png)
        self.assertEqual(saved.stat().st_mode & 0o777, 0o600)
        self.assertEqual(self.stash.stat().st_mode & 0o777, 0o700)

    def test_paste_other_image_keeps_its_extension(self):
        self.offer(['image/jpeg'])
        self.put('image/jpeg', b'\xff\xd8jpeg')
        item = self.run_helper({'operation': 'paste', 'stashDir': str(self.stash)})['items'][0]
        self.assertTrue(item['label'].endswith('.jpg'))

    def test_paste_defaults_to_the_state_dir(self):
        self.offer(['image/png'])
        self.put('image/png', b'png')
        item = self.run_helper({'operation': 'paste'})['items'][0]
        self.assertEqual(Path(item['uri'][len('file://'):]).parent, self.state / 'pentad' / 'stash')

    def test_paste_rejects_oversized_image(self):
        self.offer(['image/png'])
        self.put('image/png', b'x' * (32 * 1024 * 1024 + 1))
        result = self.run_helper({'operation': 'paste', 'stashDir': str(self.stash)})
        self.assertEqual((result['ok'], result['reason']), (False, 'too-large'))
        self.assertEqual(list(self.stash.glob('*')) if self.stash.exists() else [], [])

    def test_paste_file_uri_list(self):
        self.offer(['text/uri-list', 'text/plain'])
        self.put('text/uri-list', b'# comment\r\nfile:///tmp/a%20b.png\r\nfile:///tmp/c.txt\r\n')
        result = self.run_helper({'operation': 'paste', 'stashDir': str(self.stash)})
        self.assertEqual(result, {'ok': True, 'items': [
            {'uri': 'file:///tmp/a%20b.png', 'label': 'a b.png'},
            {'uri': 'file:///tmp/c.txt', 'label': 'c.txt'}]})

    def test_paste_uri_list_with_web_links_falls_back_to_text(self):
        self.offer(['text/uri-list', 'text/plain'])
        self.put('text/uri-list', b'https://example.com/\r\n')
        self.put('text/plain', b'https://example.com/')
        result = self.run_helper({'operation': 'paste', 'stashDir': str(self.stash)})
        self.assertEqual(result, {'ok': True, 'text': 'https://example.com/'})

    def test_paste_text(self):
        self.offer(['text/plain;charset=utf-8', 'text/plain', 'UTF8_STRING'])
        self.put('text/plain;charset=utf-8', 'привіт\nworld'.encode())
        self.put('text/plain', b'ignored')
        result = self.run_helper({'operation': 'paste', 'stashDir': str(self.stash)})
        self.assertEqual(result, {'ok': True, 'text': 'привіт\nworld'})

    def test_paste_text_falls_back_to_legacy_targets(self):
        self.offer(['TEXT', 'UTF8_STRING'])
        self.put('UTF8_STRING', b'legacy')
        self.assertEqual(self.run_helper({'operation': 'paste', 'stashDir': str(self.stash)}), {'ok': True, 'text': 'legacy'})

    def test_paste_empty(self):
        self.offer(['application/x-weird'])
        result = self.run_helper({'operation': 'paste', 'stashDir': str(self.stash)})
        self.assertEqual((result['ok'], result['reason']), (False, 'empty'))

    def test_paste_blank_text_is_empty(self):
        self.offer(['text/plain'])
        self.put('text/plain', b'')
        self.assertEqual(self.run_helper({'operation': 'paste', 'stashDir': str(self.stash)})['reason'], 'empty')

    def test_paste_rejects_oversized_text(self):
        self.offer(['text/plain'])
        self.put('text/plain', b'a' * (70 * 1024))
        result = self.run_helper({'operation': 'paste', 'stashDir': str(self.stash)})
        self.assertEqual((result['ok'], result['reason']), (False, 'too-large'))

    def test_paste_reports_unavailable_clipboard(self):
        self.offer(['text/plain'])
        (self.fake / 'list-status').write_text('1')
        self.assertEqual(self.run_helper({'operation': 'paste'})['reason'], 'clipboard-unavailable')

    def test_paste_reports_missing_wl_paste(self):
        result = self.run_helper({'operation': 'paste'}, env=self.env(path=self.empty_path()))
        self.assertEqual((result['ok'], result['reason']), (False, 'clipboard-unavailable'))


class CopyTests(ClipboardCase):
    def copy(self, request):
        result = self.run_helper(dict(request, operation='copy'))
        self.assertEqual(result, {'ok': True})
        return (self.fake / 'copy-args').read_text().split(), (self.fake / 'copy-stdin').read_bytes()

    def test_copy_modes(self):
        args, stdin = self.copy({'mode': 'text', 'value': 'привіт'})
        self.assertEqual(args, ['--type', 'text/plain;charset=utf-8'])
        self.assertEqual(stdin, 'привіт'.encode())
        args, stdin = self.copy({'mode': 'uris', 'value': 'file:///tmp/a%20b.png\nfile:///tmp/c'})
        self.assertEqual(args, ['--type', 'text/uri-list'])
        self.assertEqual(stdin, b'file:///tmp/a%20b.png\r\nfile:///tmp/c\r\n')
        image = Path(self.tmp.name) / 'p.png'
        image.write_bytes(b'\x89PNGdata')
        args, stdin = self.copy({'mode': 'image', 'path': str(image)})
        self.assertEqual(args, ['--type', 'image/png'])
        self.assertEqual(stdin, b'\x89PNGdata')

    def test_copy_refuses_bad_requests(self):
        for request in ({'mode': 'uris', 'value': 'https://example.com/'},
                        {'mode': 'uris', 'value': 'file://host/etc/passwd'},
                        {'mode': 'image', 'path': self.tmp.name},
                        {'mode': 'image', 'path': str(Path(self.tmp.name) / 'missing.png')},
                        {'mode': 'text', 'value': 5},
                        {'mode': 'nope'}):
            result = self.run_helper(dict(request, operation='copy'))
            self.assertFalse(result['ok'], request)
            self.assertIn('reason', result)
        self.assertFalse((self.fake / 'copy-args').exists())

    def test_copy_refuses_image_symlink(self):
        real = Path(self.tmp.name) / 'real.png'
        real.write_bytes(b'png')
        link = Path(self.tmp.name) / 'link.png'
        link.symlink_to(real)
        self.assertFalse(self.run_helper({'operation': 'copy', 'mode': 'image', 'path': str(link)})['ok'])

    def test_copy_reports_unavailable_clipboard(self):
        result = self.run_helper({'operation': 'copy', 'mode': 'text', 'value': 'x'}, env=self.env(path=self.empty_path()))
        self.assertEqual((result['ok'], result['reason']), (False, 'clipboard-unavailable'))


class DeleteTests(ClipboardCase):
    def setUp(self):
        super().setUp()
        self.stash.mkdir(mode=0o700)

    def delete(self, path):
        return self.run_helper({'operation': 'delete', 'stashDir': str(self.stash), 'path': str(path)})

    def test_delete_inside_stash(self):
        target = self.stash / 'clip-1.png'
        target.write_bytes(b'png')
        self.assertEqual(self.delete(target), {'ok': True})
        self.assertFalse(target.exists())

    def test_delete_missing_file_is_ok(self):
        self.assertEqual(self.delete(self.stash / 'gone.png'), {'ok': True})

    def test_delete_refuses_paths_outside_stash_dir(self):
        outside = Path(self.tmp.name) / 'precious.txt'
        outside.write_text('keep')
        nested = self.stash / 'sub'
        nested.mkdir()
        (nested / 'deep.png').write_bytes(b'x')
        sibling = Path(self.tmp.name) / 'stash-evil'
        sibling.mkdir()
        (sibling / 'a.png').write_bytes(b'x')
        for path in (outside, nested / 'deep.png', sibling / 'a.png', self.stash / '..' / 'precious.txt',
                     self.stash, '/etc/passwd', 'relative.png'):
            result = self.delete(path)
            self.assertEqual((result['ok'], result['reason']), (False, 'outside-stash'), path)
        self.assertEqual(outside.read_text(), 'keep')
        self.assertTrue((nested / 'deep.png').exists() and (sibling / 'a.png').exists() and self.stash.exists())

    def test_delete_refuses_directory_inside_stash(self):
        folder = self.stash / 'folder'
        folder.mkdir()
        self.assertEqual(self.delete(folder)['reason'], 'outside-stash')
        self.assertTrue(folder.exists())

    def test_delete_refuses_symlink_escape(self):
        outside = Path(self.tmp.name) / 'precious.txt'
        outside.write_text('keep')
        link = self.stash / 'clip-link.png'
        link.symlink_to(outside)
        result = self.delete(link)
        self.assertEqual((result['ok'], result['reason']), (False, 'outside-stash'))
        self.assertEqual(outside.read_text(), 'keep')
        self.assertTrue(link.is_symlink())

    def test_delete_refuses_symlink_to_another_stash_file(self):
        real = self.stash / 'real.png'
        real.write_bytes(b'x')
        link = self.stash / 'link.png'
        link.symlink_to(real)
        self.assertEqual(self.delete(link)['reason'], 'outside-stash')
        self.assertTrue(real.exists() and link.is_symlink())

    def test_delete_refuses_escape_through_a_symlinked_directory(self):
        outside = Path(self.tmp.name) / 'elsewhere'
        outside.mkdir()
        (outside / 'a.png').write_bytes(b'x')
        (self.stash / 'dir').symlink_to(outside)
        self.assertEqual(self.delete(self.stash / 'dir' / 'a.png')['reason'], 'outside-stash')
        self.assertTrue((outside / 'a.png').exists())


class PreviewTests(ClipboardCase):
    """The preview helper may segfault on exit when Gtk has no display (existing behaviour), so these
    tests read the emitted JSON lines instead of the exit status."""

    def preview(self, uris):
        result = subprocess.run([sys.executable, '-I', str(PREVIEW)], input=json.dumps({'uris': uris}).encode(),
                                capture_output=True, env=self.env(), timeout=60)
        if not result.stdout and b'gi' in result.stderr:
            self.skipTest('PyGObject is not available')
        return result, [json.loads(line) for line in result.stdout.decode().splitlines()]

    def test_preview_size(self):
        target = Path(self.tmp.name) / 'data.bin'
        target.write_bytes(b'x' * 1234)
        folder = Path(self.tmp.name) / 'folder'
        folder.mkdir()
        _, lines = self.preview([target.as_uri(), folder.as_uri()])
        items = {item['uri']: item for item in lines}
        self.assertEqual(items[target.as_uri()]['size'], 1234)
        self.assertNotIn('size', items[folder.as_uri()])

    def test_preview_accepts_350_uris_but_not_351(self):
        uris = [(Path(self.tmp.name) / f'missing-{i}').as_uri() for i in range(350)]
        _, lines = self.preview(uris)
        self.assertEqual(len(lines), 350)
        rejected, lines = self.preview(uris + ['file:///x'])
        self.assertEqual((rejected.returncode, lines), (1, []))
        self.assertIn(b'Invalid file list', rejected.stderr)


if __name__ == '__main__':
    unittest.main()
