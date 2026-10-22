import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

from tools import pentad_pick_files as picker
from tools.pentad_pick_files import PickError, local_uris, parse_filter, path_uris, validate

HELPER = Path(picker.__file__).resolve()


class PureLogicTests(unittest.TestCase):
    def test_parses_dialog_filters_and_drops_unsafe_patterns(self):
        self.assertEqual(parse_filter('PDF documents (*.pdf *.PDF)'), ('PDF documents', ['*.pdf', '*.PDF']))
        self.assertEqual(parse_filter('All files (*)'), ('All files', ['*']))
        self.assertIsNone(parse_filter('no patterns'))
        self.assertIsNone(parse_filter('Bad ($(rm) `x`)'))

    def test_validates_requests(self):
        spec = validate({'filters': ['Images (*.png)', 'junk'], 'multiple': False})
        self.assertEqual(spec, {'title': 'Choose files', 'multiple': False, 'filters': [('Images', ['*.png'])]})
        with self.assertRaises(PickError):
            validate([])
        with self.assertRaises(PickError):
            validate({'title': 'x' * 300})

    def test_keeps_local_file_uris_only(self):
        self.assertEqual(local_uris(['file:///tmp/a%20b.pdf', 'https://x.test/a', 'file://host/a', 'file://localhost/tmp/c']),
                         ['file:///tmp/a%20b.pdf', 'file:///tmp/c'])
        self.assertEqual(path_uris(['/tmp/a b.pdf', 'relative']), ['file:///tmp/a%20b.pdf'])


class FallbackTests(unittest.TestCase):
    """Runs the helper against a fake zenity without a session bus, so no dialog opens."""

    def run_helper(self, script, request):
        with tempfile.TemporaryDirectory() as directory:
            fake = Path(directory) / 'zenity'
            fake.write_text('#!/bin/sh\n' + script)
            fake.chmod(0o755)
            env = {key: value for key, value in os.environ.items() if key not in ('DBUS_SESSION_BUS_ADDRESS', 'DISPLAY', 'WAYLAND_DISPLAY')}
            env['PATH'] = f'{directory}:/usr/bin:/bin'
            result = subprocess.run([sys.executable, '-I', str(HELPER)], input=json.dumps(request).encode(),
                                    capture_output=True, env=env, timeout=10)
            return json.loads(result.stdout)

    def test_returns_chosen_paths_as_uris(self):
        result = self.run_helper("printf '/tmp/one.pdf\\n/tmp/two words.pdf\\n'\n", {'filters': ['PDF (*.pdf)']})
        self.assertEqual(result, {'ok': True, 'uris': ['file:///tmp/one.pdf', 'file:///tmp/two%20words.pdf']})

    def test_reports_cancel_and_failure(self):
        self.assertEqual(self.run_helper('exit 1\n', {}), {'ok': False, 'cancelled': True})
        self.assertFalse(self.run_helper('exit 5\n', {})['ok'])


if __name__ == '__main__':
    unittest.main()
