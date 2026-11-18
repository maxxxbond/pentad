import json
import os
import stat
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from tools import pentad_secrets as secrets

REF = 'secret://pentad/providers/openai'
VALUE = 'sk-test-VALUE-1234'

FAKE = r'''#!/usr/bin/env python3
import json, os, sys, time
root = os.environ['FAKE_ROOT']
mode = os.environ.get('FAKE_MODE', '')
with open(os.path.join(root, 'argv.log'), 'a') as log:
    log.write(json.dumps(sys.argv[1:]) + '\n')
if mode == 'hang':
    time.sleep(60)
if mode == 'broken':
    sys.stderr.write('secret-tool: Cannot autolaunch D-Bus without X11 $DISPLAY\n')
    sys.exit(1)
db = os.path.join(root, 'db.json')
data = json.load(open(db)) if os.path.exists(db) else {}
cmd, args = sys.argv[1], sys.argv[2:]
if cmd == 'store':
    path = args[args.index('pentad-ref') + 1]
    data[path] = sys.stdin.read()
    json.dump(data, open(db, 'w'))
elif cmd == 'lookup':
    path = args[args.index('pentad-ref') + 1]
    if path not in data:
        sys.exit(1)
    sys.stdout.write(data[path])
elif cmd == 'clear':
    path = args[args.index('pentad-ref') + 1]
    data.pop(path, None)
    json.dump(data, open(db, 'w'))
'''


class FakeKeyring(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.root = Path(self.directory.name)
        self.bin = self.root / 'bin'
        self.bin.mkdir()
        program = self.bin / 'secret-tool'
        program.write_text(FAKE)
        program.chmod(program.stat().st_mode | stat.S_IXUSR)
        patcher = mock.patch.dict(os.environ, {'PATH': str(self.bin) + os.pathsep + '/usr/bin:/bin',
                                               'FAKE_ROOT': str(self.root), 'FAKE_MODE': ''})
        patcher.start()
        self.addCleanup(patcher.stop)
        self.addCleanup(self.directory.cleanup)

    def argv_log(self):
        path = self.root / 'argv.log'
        return path.read_text() if path.exists() else ''


class RefTests(unittest.TestCase):
    def test_accepts_paths_and_rejects_everything_else(self):
        self.assertEqual(secrets.parse_ref(REF), 'providers/openai')
        self.assertEqual(secrets.parse_ref('secret://pentad/a.b_c-1'), 'a.b_c-1')
        for bad in ['', None, 5, 'secret://other/x', 'secret://pentad/', 'secret://pentad/A', 'secret://pentad/a//b',
                    'secret://pentad/../x', 'secret://pentad/a b', 'secret://pentad/a?x', 'pentad/x']:
            with self.subTest(ref=bad), self.assertRaises(secrets.SecretError) as caught:
                secrets.parse_ref(bad)
            self.assertEqual(caught.exception.reason, 'invalid')


class StoreTests(FakeKeyring):
    def test_stored_then_cleared(self):
        self.assertEqual(secrets.status(REF), 'missing')
        secrets.store(REF, VALUE)
        self.assertEqual(secrets.status(REF), 'stored')
        self.assertEqual(secrets.lookup(REF), VALUE)
        secrets.clear(REF)
        self.assertEqual(secrets.status(REF), 'missing')
        with self.assertRaises(secrets.SecretError) as caught:
            secrets.lookup(REF)
        self.assertEqual(caught.exception.reason, 'missing')

    def test_value_never_in_argv_and_label_attribute_are_set(self):
        secrets.store(REF, VALUE)
        secrets.lookup(REF)
        log = self.argv_log()
        self.assertNotIn(VALUE, log)
        calls = [json.loads(line) for line in log.splitlines()]
        self.assertEqual(calls[0], ['store', '--label', 'Pentad providers/openai', 'pentad-ref', 'providers/openai'])
        self.assertEqual(calls[1], ['lookup', 'pentad-ref', 'providers/openai'])

    def test_rejects_bad_values_without_calling_the_program(self):
        for bad in ['', None, 'a\0b']:
            with self.subTest(value=bad), self.assertRaises(secrets.SecretError) as caught:
                secrets.store(REF, bad)
            self.assertEqual(caught.exception.reason, 'invalid')
        self.assertEqual(self.argv_log(), '')

    def test_not_installed_is_unavailable(self):
        with mock.patch.dict(os.environ, {'PATH': str(self.root / 'nothing')}):
            self.assertEqual(secrets.status(REF), 'unavailable')
            with self.assertRaises(secrets.SecretError) as caught:
                secrets.store(REF, VALUE)
            self.assertEqual(caught.exception.reason, 'unavailable')

    def test_service_error_is_unavailable_and_message_is_clean(self):
        os.environ['FAKE_MODE'] = 'broken'
        self.assertEqual(secrets.status(REF), 'unavailable')
        with self.assertRaises(secrets.SecretError) as caught:
            secrets.store(REF, VALUE)
        self.assertEqual(caught.exception.reason, 'unavailable')
        self.assertNotIn(VALUE, str(caught.exception))
        with self.assertRaises(secrets.SecretError):
            secrets.clear(REF)

    def test_timeout_is_unavailable(self):
        os.environ['FAKE_MODE'] = 'hang'
        with mock.patch.object(secrets, 'TIMEOUT', 0.5):
            self.assertEqual(secrets.status(REF), 'unavailable')

    def test_invalid_ref_raises_from_status(self):
        with self.assertRaises(secrets.SecretError) as caught:
            secrets.status('nope')
        self.assertEqual(caught.exception.reason, 'invalid')


class ResolveTests(FakeKeyring):
    def test_credential_wins_then_env_then_none(self):
        secrets.store(REF, VALUE)
        with mock.patch.dict(os.environ, {'MY_KEY': 'from-env'}):
            self.assertEqual(secrets.resolve({'credential': REF, 'credentialEnv': 'MY_KEY'}), VALUE)
            self.assertEqual(secrets.resolve({'credential': '', 'credentialEnv': 'MY_KEY'}), 'from-env')
            with self.assertRaises(secrets.SecretError) as caught:
                secrets.resolve({'credentialEnv': 'UNSET_KEY_XYZ'})
            self.assertEqual(caught.exception.reason, 'missing')
        self.assertIsNone(secrets.resolve({'credential': '', 'credentialEnv': ''}))
        secrets.clear(REF)
        with self.assertRaises(secrets.SecretError) as caught:
            secrets.resolve({'credential': REF})
        self.assertEqual(caught.exception.reason, 'missing')


class OpTests(FakeKeyring):
    def setUp(self):
        super().setUp()
        self.table = {}
        secrets.register_ops(self.table)

    def test_registers_three_ops_and_round_trips_without_leaking(self):
        self.assertEqual(sorted(self.table), ['secret.clear', 'secret.status', 'secret.store'])
        results = [
            self.table['secret.status']({'ref': REF}, None),
            self.table['secret.store']({'ref': REF, 'value': VALUE}, None),
            self.table['secret.status']({'ref': REF}, None),
            self.table['secret.clear']({'ref': REF}, None),
            self.table['secret.status']({'ref': REF}, None),
        ]
        self.assertEqual([r['value']['status'] for r in results], ['missing', 'stored', 'stored', 'missing', 'missing'])
        self.assertTrue(all(r['ok'] for r in results))
        self.assertNotIn(VALUE, json.dumps(results))

    def test_failures_become_reasons(self):
        bad = self.table['secret.store']({'ref': 'x', 'value': VALUE}, None)
        self.assertEqual((bad['ok'], bad['reason']), (False, 'invalid-input'))
        self.assertNotIn(VALUE, json.dumps(bad))
        os.environ['FAKE_MODE'] = 'broken'
        down = self.table['secret.store']({'ref': REF, 'value': VALUE}, None)
        self.assertEqual((down['ok'], down['reason']), (False, 'unavailable'))
        self.assertNotIn(VALUE, json.dumps(down))
        self.assertEqual(self.table['secret.status']('garbage', None)['reason'], 'invalid-input')


if __name__ == '__main__':
    unittest.main()
