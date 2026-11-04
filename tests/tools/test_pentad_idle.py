import importlib.util
import json
import os
import stat
import subprocess
import sys
import tempfile
import unittest
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from unittest.mock import patch

MODULE = Path(__file__).resolve().parents[2] / 'tools/pentad_idle.py'
SPEC = importlib.util.spec_from_file_location('pentad_idle', MODULE)
idle = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(idle)

CONFIG = '''$suspend_cmd = systemctl suspend
general {
    lock_cmd = pentad lock
    before_sleep_cmd = loginctl lock-session
}

listener {
    timeout = 300 # lock
    on-timeout = loginctl lock-session
}

listener {
    timeout = 900 # sleep
    on-timeout = $suspend_cmd
    condition_cmd = test -f /tmp/example-idle-allowed
    condition_retry = 30
}
'''
DISPLAY = '''listener {
    timeout = 600
    on-timeout = hyprctl dispatch dpms off
    on-resume = hyprctl dispatch dpms on && brightnessctl -r
    ignore_inhibit = false
}
'''


class IdleConfigTest(unittest.TestCase):
    def test_sleep_edit_preserves_variable_commands_conditions_lock_and_comments(self):
        self.assertEqual(idle.edit(CONFIG, 'suspend', 1800), CONFIG.replace('timeout = 900', 'timeout = 1800'))

    def test_direct_sleep_flags_survive_and_compound_commands_do_not_get_competing_timers(self):
        for command in ('systemctl --no-block suspend', 'systemctl suspend --no-block'):
            text = CONFIG.replace('$suspend_cmd\n', command + '\n')
            self.assertEqual(idle.edit(text, 'suspend', 1800), text.replace('timeout = 900', 'timeout = 1800'))
        for command in ('systemctl suspend && notify-send done', 'my-suspend-script', 'hyprctl dispatch dpms off && notify-send done'):
            text = CONFIG.replace('$suspend_cmd\n', command + '\n')
            with self.subTest(command=command), self.assertRaises(idle.IdleError):
                idle.edit(text, 'display', 360)

    def test_add_display_has_both_off_and_wake_and_does_not_change_existing_rules(self):
        result = idle.edit(CONFIG, 'display', 360)
        self.assertTrue(result.startswith(CONFIG))
        self.assertIn('    on-timeout = ' + idle.DPMS_OFF, result)
        self.assertIn('    on-resume = ' + idle.DPMS_ON, result)
        listeners = idle.parse(result)[1]
        self.assertEqual((listeners['display']['seconds'], listeners['suspend']['seconds']), (360, 900))
        self.assertEqual(idle.edit(result, 'display', 360), result)

    def test_disable_then_reenable_restores_custom_command_and_condition(self):
        disabled = idle.edit(CONFIG, 'suspend', 0)
        self.assertIn(idle.DISABLED + '    on-timeout = $suspend_cmd', disabled)
        self.assertTrue(idle.parse(disabled)[1]['suspend']['disabled'])
        self.assertEqual(idle.edit(disabled, 'suspend', 900), CONFIG)
        self.assertEqual(idle.edit(disabled, 'suspend', 0), disabled)
        self.assertEqual(idle.edit(CONFIG, 'display', 0), CONFIG)

    def test_display_edit_keeps_existing_wake_command_and_options(self):
        self.assertEqual(idle.edit(DISPLAY, 'display', 120), DISPLAY.replace('timeout = 600', 'timeout = 120'))

    def test_missing_or_empty_wake_is_added_for_legacy_and_lua_rules(self):
        for command, wake in [('hyprctl dispatch dpms off', 'hyprctl dispatch dpms on'), (idle.DPMS_OFF, idle.DPMS_ON)]:
            for resume in ['', '    on-resume =\n']:
                text = 'listener {\n    timeout = 600\n    on-timeout = ' + command + '\n' + resume + '}\n'
                result = idle.edit(text, 'display', 600)
                self.assertEqual(result.count('on-resume = ' + wake), 1)
                self.assertEqual(result.count('on-resume'), 1)
                idle.parse(result)

    def test_variable_timeout_and_command_are_read_without_changing_definitions(self):
        text = '$duration = 333\n$screen = hyprctl dispatch dpms off\nlistener {\n    timeout = $duration # custom\n    on-timeout = $screen\n}\n'
        self.assertEqual(idle.parse(text)[1]['display']['seconds'], 333)
        updated = idle.edit(text, 'display', 120)
        self.assertTrue(updated.startswith('$duration = 333\n$screen ='))
        self.assertIn('timeout = 120 # custom', updated)

    def test_crlf_and_unrelated_shell_braces_survive(self):
        original = (CONFIG + 'listener {\n    timeout = 42\n    on-timeout = sh -c "echo ${EXAMPLE}"\n}\n').replace('\n', '\r\n')
        result = idle.edit(original, 'suspend', 1800)
        self.assertEqual(result, original.replace('timeout = 900', 'timeout = 1800'))

    def test_ambiguous_included_and_malformed_configs_are_refused(self):
        texts = [CONFIG + CONFIG, CONFIG + 'source = other.conf\n', 'listener { timeout = 1 }\n',
                 'listener {\n timeout = 1\n', CONFIG + '}\n',
                 CONFIG.replace('timeout = 900', 'timeout = $missing'),
                 CONFIG.replace('timeout = 900', 'timeout = 900\n    timeout = 10')]
        for text in texts:
            with self.subTest(text=text), self.assertRaises(idle.IdleError):
                idle.edit(text, 'suspend', 600)

    def test_invalid_requests_never_generate_config(self):
        for action, seconds in [('display', -1), ('suspend', 86401), ('display', True), ('display', '900'), ('lock', 300)]:
            with self.subTest(action=action, seconds=seconds), self.assertRaises(idle.IdleError):
                idle.edit(CONFIG, action, seconds)


class IdleStorageTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.path = Path(self.temp.name) / 'hypridle.conf'
        self.path.write_text(CONFIG)
        self.path.chmod(0o640)

    def save(self, **changes):
        request = dict(action='display', seconds=360, revision=idle.idle_state(self.path)['revision'])
        request.update(changes)
        return idle.set_idle_timeout(request, self.path)

    def test_write_is_atomic_preserves_permissions_and_reports_restart_required(self):
        with patch.object(idle.shutil, 'which', return_value='/fixture/bin/hypridle'):
            self.assertEqual(idle.idle_state(self.path)['suspend'], 900)
            self.assertTrue(idle.idle_state(self.path)['available'])
            self.assertEqual(self.save(), dict(ok=True, restartRequired=True))
            self.assertEqual(idle.idle_state(self.path)['display'], 360)
        self.assertEqual(stat.S_IMODE(self.path.stat().st_mode), 0o640)
        self.assertEqual(list(self.path.parent.glob('.pentad-idle-*')), [])

    def test_conflict_and_invalid_values_leave_original_untouched(self):
        revision = idle.idle_state(self.path)['revision']
        self.path.write_text(CONFIG + '# edited elsewhere\n')
        self.assertEqual(self.save(revision=revision)['reason'], 'conflict')
        self.assertEqual(self.save(seconds=True)['reason'], 'invalid-request')
        self.assertEqual(self.path.read_text(), CONFIG + '# edited elsewhere\n')

    def test_write_failure_keeps_original_and_cleans_temporary_file(self):
        with patch.object(idle.os, 'replace', side_effect=PermissionError):
            self.assertEqual(self.save()['reason'], 'idle-config-read-only')
        self.assertEqual(self.path.read_text(), CONFIG)
        self.assertEqual(list(self.path.parent.glob('.pentad-idle-*')), [])

    def test_change_during_write_is_rejected(self):
        fsync = idle.os.fsync
        def change(fd):
            fsync(fd)
            self.path.write_text(CONFIG + '# concurrent edit\n')
        with patch.object(idle.os, 'fsync', side_effect=change):
            self.assertEqual(self.save()['reason'], 'conflict')
        self.assertTrue(self.path.read_text().endswith('# concurrent edit\n'))

    def test_concurrent_writers_with_the_same_revision_cannot_overwrite_each_other(self):
        revision = idle.idle_state(self.path)['revision']
        requests = [dict(action='display', seconds=seconds, revision=revision) for seconds in (120, 600)]
        with ThreadPoolExecutor(max_workers=2) as executor:
            results = list(executor.map(lambda request: idle.set_idle_timeout(request, self.path), requests))
        self.assertEqual(sum(result['ok'] for result in results), 1)
        self.assertEqual([result['reason'] for result in results if not result['ok']], ['conflict'])
        self.assertIn(idle.idle_state(self.path)['display'], (120, 600))

    def test_symlink_fifo_missing_oversize_and_invalid_utf8_are_read_only(self):
        target = self.path.with_name('link.conf')
        target.symlink_to(self.path)
        self.assertFalse(idle.idle_state(target)['ok'])
        self.assertFalse(idle.set_idle_timeout({}, target)['ok'])
        self.assertTrue(target.is_symlink())
        fifo = self.path.with_name('fifo.conf')
        os.mkfifo(fifo)
        self.assertFalse(idle.idle_state(fifo)['ok'])
        self.assertEqual(idle.idle_state(self.path.with_name('missing'))['reason'], 'idle-config-missing')
        self.path.write_bytes(b'\xff')
        self.assertFalse(idle.idle_state(self.path)['ok'])
        self.path.write_bytes(b'x' * (idle.MAX_BYTES + 1))
        self.assertFalse(idle.idle_state(self.path)['ok'])

    def test_empty_config_disabled_timer_missing_program_and_recovery(self):
        self.path.write_text('')
        with patch.object(idle.shutil, 'which', return_value=None):
            self.assertEqual(idle.idle_state(self.path)['display'], 0)
            self.assertFalse(idle.idle_state(self.path)['available'])
        self.assertTrue(self.save(action='suspend', seconds=600)['ok'])
        self.assertTrue(self.save(action='suspend', seconds=0)['ok'])
        self.assertEqual(idle.idle_state(self.path)['suspend'], 0)
        self.assertTrue(self.save(action='suspend', seconds=1200)['ok'])
        self.assertEqual(idle.idle_state(self.path)['suspend'], 1200)

    def test_xdg_config_path_is_used(self):
        with patch.dict(os.environ, {'XDG_CONFIG_HOME': self.temp.name}):
            self.assertEqual(idle.config_path(), Path(self.temp.name) / 'hypr/hypridle.conf')

    def test_system_entrypoint_runs_from_an_unrelated_directory_with_isolated_python(self):
        config = self.path.parent / 'config/hypr/hypridle.conf'
        config.parent.mkdir(parents=True)
        config.write_text(CONFIG)
        env = dict(HOME=self.temp.name, XDG_CONFIG_HOME=str(config.parent.parent), PATH='')
        def request(payload):
            reply = subprocess.run([sys.executable, '-I', str(MODULE.with_name('pentad_system.py'))],
                                   input=json.dumps(payload), text=True, capture_output=True, check=True,
                                   cwd=self.temp.name, env=env, timeout=5)
            return json.loads(reply.stdout)
        state = request(dict(operation='idle'))
        self.assertEqual((state['display'], state['suspend'], state['available']), (0, 900, False))
        reply = request(dict(operation='set-idle-timeout', action='display', seconds=600, revision=state['revision']))
        self.assertEqual(reply, dict(ok=True, restartRequired=True))
        self.assertEqual(request(dict(operation='idle'))['display'], 600)


if __name__ == '__main__':
    unittest.main()
