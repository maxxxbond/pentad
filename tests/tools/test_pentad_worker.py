import io
import json
import os
import queue
import signal
import stat
import subprocess
import sys
import tempfile
import threading
import time
import unittest
from pathlib import Path
from unittest import mock
from urllib.parse import quote

from tools import pentad_worker as worker

WORKER = Path(worker.__file__).resolve()
core = worker.core
image = worker.image

FAKE_TESSERACT = r'''#!/bin/sh
case "$1" in
  --version) echo "tesseract 9.9-fake"; exit 0 ;;
  --list-langs)
    echo list >> "$FAKE_DIR/log"
    echo 'List of available languages in "/fake/" (2):'
    printf '%b\n' "${FAKE_TESS_LANGS:-eng\nosd}"
    exit 0 ;;
esac
echo "ocr $*" >> "$FAKE_DIR/log"
if [ -n "$FAKE_TESS_PIDS" ]; then echo $$ > "$FAKE_TESS_PIDS/$$"; fi
if [ -n "$FAKE_TESS_WAIT" ]; then
  i=0; while [ ! -e "$FAKE_TESS_WAIT" ] && [ $i -lt 600 ]; do sleep 0.05; i=$((i+1)); done
fi
if [ -n "$FAKE_TESS_GATHER" ]; then
  touch "$FAKE_DIR/started-$$"
  i=0; while [ "$(ls "$FAKE_DIR" | grep -c '^started-')" -lt "$FAKE_TESS_GATHER" ] && [ $i -lt 200 ]; do sleep 0.05; i=$((i+1)); done
  [ $i -lt 200 ] && echo together
fi
printf 'read: %s\n\n   \nargs: %s\n' "$(cat "$1")" "$*"
'''

FAKE_ZBARIMG = r'''#!/bin/sh
case "$1" in --version) echo "0.0-fake"; exit 0 ;; esac
echo "zbar $*" >> "$FAKE_DIR/log"
[ -n "$FAKE_ZBAR_EXIT" ] && exit "$FAKE_ZBAR_EXIT"
cat "$FAKE_DIR/zbar.xml"
'''

FAKE_QPDF = r'''#!/bin/sh
if [ -n "$FAKE_QPDF_MARKER" ]; then echo $$ > "$FAKE_QPDF_MARKER"; exec sleep 30; fi
case "$1" in --requires-password) exit 2 ;; esac
exit 0
'''

FAKE_PDFTOTEXT = r'''#!/bin/sh
case "$1" in -v) echo "pdftotext version 0-fake" >&2; exit 0 ;; esac
echo "pdftotext" >> "$FAKE_DIR/log"
printf 'page text of %s\n' "$(head -c 20 "$4")" > "$5"
'''

ZBAR_XML = '''<barcodes xmlns='http://zbar.sourceforge.net/2008/barcode'>
<source href='input-1.png'>
<index num='0'>
<symbol type='QR-Code' quality='1' orientation='UP'><polygon points='+12,+12'/><data><![CDATA[https://example.com/a?b=1]]></data></symbol>
<symbol type='EAN-13' quality='1'><data format='base64' length='11'><![CDATA[
aGVsbG8Kd29ybGQ=
]]></data></symbol>
</index>
</source>
</barcodes>
'''


def uri(path):
    return 'file://' + quote(str(path), safe='/')


class WorkerProcess:
    """One worker over real pipes; collects every line it writes."""

    def __init__(self, env, cache_root, extra=()):
        self.process = subprocess.Popen([sys.executable, '-I', str(WORKER), '--serve', '--cache-root', str(cache_root), *extra],
                                        stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=env)
        self.messages = queue.Queue()
        self.seen = []
        self.stderr = b''
        self._reader = threading.Thread(target=self._read, daemon=True)
        self._reader.start()
        self._errors = threading.Thread(target=self._read_errors, daemon=True)
        self._errors.start()

    def _read(self):
        for line in self.process.stdout:
            self.messages.put(json.loads(line))
        self.messages.put(None)

    def _read_errors(self):
        self.stderr = self.process.stderr.read()

    def send(self, message):
        self.send_raw(json.dumps(message).encode() + b'\n')

    def send_raw(self, data):
        self.process.stdin.write(data)
        self.process.stdin.flush()

    def request(self, ident, op, payload=None, **extra):
        self.send(dict({'type': 'request', 'id': ident, 'op': op, 'payload': payload or {}}, **extra))

    def next(self, timeout=10):
        try:
            message = self.messages.get(timeout=timeout)
        except queue.Empty:
            raise AssertionError('the worker sent nothing in time') from None
        if message is not None:
            self.seen.append(message)
        return message

    def result(self, ident, timeout=10):
        deadline = time.monotonic() + timeout
        for message in self.seen:
            if message.get('type') == 'result' and message.get('id') == ident:
                return message['result']
        while True:
            message = self.next(max(0.01, deadline - time.monotonic()))
            if message is None:
                raise AssertionError(f'the worker exited before answering {ident}')
            if message.get('type') == 'result' and message.get('id') == ident:
                return message['result']

    def call(self, ident, op, payload=None, **extra):
        self.request(ident, op, payload, **extra)
        return self.result(ident)

    def close(self, timeout=10):
        try:
            self.process.stdin.close()
        except OSError:
            pass
        try:
            return self.process.wait(timeout=timeout)
        finally:
            self.drain()

    def drain(self):
        if self.process.poll() is None:
            self.process.kill()
            self.process.wait()
        self._reader.join(timeout=5)
        self._errors.join(timeout=5)
        for stream in (self.process.stdin, self.process.stdout, self.process.stderr):
            try:
                stream.close()
            except OSError:
                pass
        while True:
            try:
                message = self.messages.get_nowait()
            except queue.Empty:
                break
            if message is not None:
                self.seen.append(message)

    def results_by_id(self):
        counts = {}
        for message in self.seen:
            if message.get('type') == 'result':
                counts[message['id']] = counts.get(message['id'], 0) + 1
        return counts


class WorkerTestCase(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.root = Path(self.directory.name)
        self.bin = self.root / 'bin'
        self.bin.mkdir()
        self.fake = self.root / 'fake'
        self.fake.mkdir()
        self.tmp = self.root / 'tmp'
        self.tmp.mkdir()
        self.cache = self.root / 'cache' / 'pentad' / 'worker'
        for name, script in (('tesseract', FAKE_TESSERACT), ('zbarimg', FAKE_ZBARIMG), ('qpdf', FAKE_QPDF),
                             ('pdftotext', FAKE_PDFTOTEXT)):
            path = self.bin / name
            path.write_text(script)
            path.chmod(0o755)
        (self.fake / 'zbar.xml').write_text(ZBAR_XML)
        self.workers = []

    def tearDown(self):
        for process in self.workers:
            process.drain()
        self.directory.cleanup()

    def start(self, extra=(), **env):
        environment = dict(os.environ, PATH=f'{self.bin}:{os.environ.get("PATH", "")}', TMPDIR=str(self.tmp),
                           FAKE_DIR=str(self.fake), HOME=str(self.root), XDG_CACHE_HOME=str(self.root / 'cache'))
        environment.update(env)
        process = WorkerProcess(environment, self.cache, extra)
        self.workers.append(process)
        hello = process.next()
        self.assertEqual(hello['type'], 'hello')
        return process

    def image(self, name, content):
        path = self.root / name
        path.write_text(content)
        return path

    def log(self, prefix):
        path = self.fake / 'log'
        lines = path.read_text().splitlines() if path.exists() else []
        return [line for line in lines if line.startswith(prefix)]

    def scratch_dirs(self, *folders):
        return [path for folder in (self.tmp, self.root, *folders) for path in folder.iterdir()
                if path.name.startswith('.pentad-tool-')]

    def wait_for(self, predicate, timeout=10):
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            if predicate():
                return True
            time.sleep(0.02)
        return False

    def assert_dead(self, pid):
        # A killed child is reaped by the worker; give that a moment.
        def gone():
            try:
                os.kill(pid, 0)
            except ProcessLookupError:
                return True
            return False
        self.assertTrue(self.wait_for(gone, 5), f'child {pid} is still running')


class ProtocolTests(WorkerTestCase):
    def test_hello_lists_the_builtin_ops(self):
        process = self.start()
        hello = process.seen[0]
        self.assertEqual(hello['protocol'], 1)
        self.assertEqual(hello['worker'], '1')
        self.assertTrue({'file.run', 'image.ocr', 'image.barcode', 'pdf.text', 'ocr.languages', 'worker.stats'} <= set(hello['ops']))
        self.assertEqual(hello['ops'], sorted(hello['ops']))
        stats = process.call(1, 'worker.stats')
        self.assertEqual(stats['ok'], True)
        self.assertEqual(stats['cached'], False)
        self.assertEqual(stats['value']['protocol'], 1)
        self.assertEqual(process.close(), 0)

    def test_unknown_op_is_unsupported(self):
        process = self.start()
        result = process.call(2, 'no.such-op')
        self.assertEqual(result['ok'], False)
        self.assertEqual(result['reason'], 'unsupported')

    def test_malformed_and_oversized_lines(self):
        process = self.start()
        process.send_raw(b'garbage\n')
        process.send_raw(b'\n')
        process.send_raw(b'{"type":"request","id":11,"op":\n')
        self.assertEqual(process.result(11)['reason'], 'invalid-response')
        process.send({'type': 'request', 'id': 13, 'op': 5, 'payload': {}})
        self.assertEqual(process.result(13)['reason'], 'invalid-response')
        process.send({'type': 'request', 'id': 14, 'op': 'worker.stats', 'payload': [], 'timeoutMs': 1000})
        self.assertEqual(process.result(14)['reason'], 'invalid-response')
        big = b'"' + b'a' * (1024 * 1024) + b'"'
        process.send_raw(b'{"type":"request","id":12,"op":"worker.stats","payload":{"x":' + big + b'}}\n')
        self.assertEqual(process.result(12)['reason'], 'invalid-response')
        process.send_raw(b'{"payload":{"x":' + big + b'},"id":15}\n')
        # Ignored: no id, id 0, a string id, an unknown type and a cancel for an unknown id.
        process.send({'type': 'request', 'id': 0, 'op': 'worker.stats'})
        process.send({'type': 'request', 'id': 'x', 'op': 'worker.stats'})
        process.send({'type': 'future-thing', 'id': 16})
        process.send({'type': 'cancel', 'id': 999})
        self.assertTrue(process.call(17, 'worker.stats')['ok'])
        self.assertEqual(process.close(), 0)
        self.assertEqual(process.results_by_id(), {11: 1, 12: 1, 13: 1, 14: 1, 17: 1})
        self.assertIn(b'ignored', process.stderr)

    def test_eof_and_shutdown_exit_cleanly(self):
        process = self.start()
        self.assertEqual(process.close(), 0)
        process = self.start()
        process.send({'type': 'shutdown'})
        self.assertEqual(process.process.wait(timeout=10), 0)


class OcrTests(WorkerTestCase):
    def test_bar_compatible_options_and_cache_hit(self):
        process = self.start()
        picture = self.image('shot.png', 'first image')
        payload = {'uri': uri(picture), 'language': 'eng+ukr', 'psm': 6, 'filterInstalled': True}
        first = process.call(1, 'image.ocr', payload)
        self.assertEqual(first['ok'], True, first)
        self.assertEqual(first['cached'], False)
        # Missing packs dropped, --psm passed, blank lines removed.
        self.assertEqual(first['value']['text'], 'read: first image\nargs: input-1.png stdout -l eng --psm 6')
        second = process.call(2, 'image.ocr', payload)
        self.assertEqual(second, {'ok': True, 'value': first['value'], 'cached': True})
        self.assertEqual(len(self.log('ocr ')), 1)
        # Another option or another image is a miss.
        self.assertFalse(process.call(3, 'image.ocr', dict(payload, psm=3))['cached'])
        picture.write_text('second image')
        self.assertIn('second image', process.call(4, 'image.ocr', payload)['value']['text'])
        self.assertEqual(len(self.log('ocr ')), 3)
        # The language list is memoised for the whole run.
        self.assertEqual(len(self.log('list')), 1)
        self.assertEqual(stat.S_IMODE(self.cache.stat().st_mode), 0o700)
        for entry in self.cache.iterdir():
            self.assertEqual(stat.S_IMODE(entry.stat().st_mode), 0o600)
        self.assertEqual(process.close(), 0)
        self.assertEqual(self.scratch_dirs(), [])
        # A restarted worker reads the same cache.
        process = self.start()
        picture.write_text('first image')
        self.assertTrue(process.call(5, 'image.ocr', payload)['cached'])

    def test_missing_language_without_filter_and_bad_options(self):
        process = self.start()
        picture = self.image('shot.png', 'x')
        result = process.call(1, 'image.ocr', {'uri': uri(picture), 'language': 'ukr'})
        self.assertEqual((result['ok'], result['reason']), (False, 'unavailable'))
        result = process.call(2, 'image.ocr', {'uri': uri(picture), 'language': 'ukr', 'filterInstalled': True})
        self.assertIn('-l eng', result['value']['text'])
        self.assertNotIn('--psm', result['value']['text'])
        self.assertEqual(process.call(3, 'image.ocr', {'uri': uri(picture), 'psm': 99})['reason'], 'unsupported')
        self.assertEqual(process.call(4, 'image.ocr', {'uri': 'https://example.com/a.png'})['reason'], 'unsupported')
        self.assertEqual(process.call(5, 'image.ocr', {'uri': uri(self.root)})['reason'], 'unsupported')
        self.assertEqual(process.call(6, 'image.ocr', {'uri': uri(self.root / 'gone.png')})['reason'], 'io')
        self.assertEqual(process.call(7, 'image.ocr', {})['reason'], 'unsupported')
        self.assertEqual(self.scratch_dirs(), [])

    def test_missing_tesseract_is_unavailable(self):
        (self.bin / 'tesseract').unlink()
        process = self.start(PATH=str(self.bin))
        result = process.call(1, 'image.ocr', {'uri': uri(self.image('shot.png', 'x'))})
        self.assertEqual(result['reason'], 'unavailable')

    def test_language_list_is_memoised_until_refresh(self):
        process = self.start(FAKE_TESS_LANGS='eng\\nukr\\nosd')
        self.assertEqual(process.call(1, 'ocr.languages')['value'], {'languages': ['eng', 'ukr']})
        process.call(2, 'ocr.languages')
        self.assertEqual(len(self.log('list')), 1)
        process.call(3, 'ocr.languages', {'refresh': True})
        self.assertEqual(len(self.log('list')), 2)


class OtherOpTests(WorkerTestCase):
    def test_barcode_codes_with_types_and_none_found(self):
        process = self.start()
        result = process.call(1, 'image.barcode', {'uri': uri(self.image('qr.png', 'qr'))})
        self.assertEqual(result['value'], {'codes': [{'type': 'QR-Code', 'text': 'https://example.com/a?b=1'},
                                                     {'type': 'EAN-13', 'text': 'hello\nworld'}]})
        self.assertTrue(process.call(2, 'image.barcode', {'uri': uri(self.image('qr.png', 'qr'))})['cached'])
        process.close()
        process = self.start(FAKE_ZBAR_EXIT='4')
        self.assertEqual(process.call(3, 'image.barcode', {'uri': uri(self.image('blank.png', 'blank'))})['value'], {'codes': []})

    def test_pdf_text_is_returned_without_writing_files(self):
        process = self.start()
        document = self.root / 'doc.pdf'
        document.write_bytes(b'%PDF-1.4 hello')
        result = process.call(1, 'pdf.text', {'uri': uri(document)})
        self.assertEqual(result['value'], {'text': 'page text of %PDF-1.4 hello\n', 'truncated': False})
        self.assertTrue(process.call(2, 'pdf.text', {'uri': uri(document)})['cached'])
        self.assertEqual(sorted(path.name for path in self.root.iterdir()), ['bin', 'cache', 'doc.pdf', 'fake', 'tmp'])
        not_pdf = self.image('note.pdf', 'plain text')
        self.assertEqual(process.call(3, 'pdf.text', {'uri': uri(not_pdf)})['reason'], 'io')

    def test_file_run_returns_the_one_shot_result(self):
        process = self.start()
        job = {'operation': 'checksum', 'inputs': [], 'text': 'abc', 'options': {}}
        result = process.call(1, 'file.run', job)
        self.assertEqual(result['value'], worker.file_tool.execute(job))
        self.assertEqual(result['cached'], False)
        failed = process.call(2, 'file.run', {'operation': 'nope'})
        self.assertEqual((failed['ok'], failed['reason'], failed['message']), (False, 'io', 'Unknown operation nope'))


class ConcurrencyTests(WorkerTestCase):
    def test_three_jobs_run_at_the_same_time(self):
        process = self.start(FAKE_TESS_GATHER='3')
        for ident in (1, 2, 3):
            process.request(ident, 'image.ocr', {'uri': uri(self.image(f'{ident}.png', f'image {ident}'))})
        for ident in (1, 2, 3):
            result = process.result(ident, timeout=20)
            self.assertTrue(result['ok'], result)
            self.assertTrue(result['value']['text'].startswith('together'), result)

    def test_a_full_queue_answers_busy_and_drains(self):
        release = self.root / 'release'
        process = self.start(FAKE_TESS_WAIT=str(release))
        picture = uri(self.image('shot.png', 'x'))
        for ident in range(1, 36):
            process.request(ident, 'image.ocr', {'uri': picture})
        result = process.call(36, 'image.ocr', {'uri': picture})
        self.assertEqual((result['ok'], result['reason']), (False, 'busy'))
        # A queued request is cancelled at once, without waiting for the running ones.
        process.send({'type': 'cancel', 'id': 30})
        self.assertEqual(process.result(30, timeout=5)['reason'], 'cancelled')
        release.touch()
        for ident in range(1, 36):
            if ident != 30:
                self.assertTrue(process.result(ident, timeout=30)['ok'])
        self.assertEqual(process.close(), 0)
        self.assertEqual(set(process.results_by_id().values()), {1})
        self.assertEqual(len(process.results_by_id()), 36)
        self.assertEqual(self.scratch_dirs(), [])

    def test_cancel_kills_the_cli_and_removes_the_work_directory(self):
        pids = self.root / 'pids'
        pids.mkdir()
        process = self.start(FAKE_TESS_PIDS=str(pids), FAKE_TESS_WAIT=str(self.root / 'never'))
        process.request(1, 'image.ocr', {'uri': uri(self.image('shot.png', 'x'))})
        self.assertTrue(self.wait_for(lambda: any(pids.iterdir())), 'fake tesseract never started')
        child = int(next(pids.iterdir()).name)
        self.assertEqual(len(self.scratch_dirs()), 1)
        started = time.monotonic()
        process.send({'type': 'cancel', 'id': 1})
        result = process.result(1, timeout=5)
        self.assertEqual((result['ok'], result['reason']), (False, 'cancelled'))
        # Answered by the job itself after cleanup, not by the 2 s grace fallback.
        self.assertLess(time.monotonic() - started, 1.5)
        self.assert_dead(child)
        self.assertEqual(self.scratch_dirs(), [])
        process.send({'type': 'cancel', 'id': 1})
        self.assertTrue(process.call(2, 'worker.stats')['ok'])
        self.assertEqual(process.close(), 0)
        self.assertEqual(process.results_by_id(), {1: 1, 2: 1})

    def test_cancel_stops_a_file_run_job_and_removes_partial_work(self):
        marker = self.root / 'started'
        process = self.start(FAKE_QPDF_MARKER=str(marker))
        pdf = self.root / 'doc.pdf'
        pdf.write_bytes(b'%PDF-1.4\n')
        process.request(1, 'file.run', {'operation': 'pdf.extract', 'inputs': [uri(pdf)], 'options': {'pages': '1'}})
        self.assertTrue(self.wait_for(marker.exists), 'fake CLI never started')
        self.assertTrue(self.wait_for(lambda: marker.read_text().strip() != ''))
        child = int(marker.read_text())
        process.send({'type': 'cancel', 'id': 1})
        self.assertEqual(process.result(1)['reason'], 'cancelled')
        self.assert_dead(child)
        self.assertEqual(self.scratch_dirs(), [])
        self.assertEqual(sorted(path.name for path in self.root.iterdir()), ['bin', 'cache', 'doc.pdf', 'fake', 'started', 'tmp'])

    def test_timeout_kills_the_cli(self):
        pids = self.root / 'pids'
        pids.mkdir()
        process = self.start(FAKE_TESS_PIDS=str(pids), FAKE_TESS_WAIT=str(self.root / 'never'))
        process.request(1, 'image.ocr', {'uri': uri(self.image('shot.png', 'x'))}, timeoutMs=700)
        result = process.result(1, timeout=10)
        self.assertEqual((result['ok'], result['reason']), (False, 'timeout'))
        self.assertIn('0.7 s', result['message'])
        self.assert_dead(int(next(pids.iterdir()).name))
        self.assertEqual(self.scratch_dirs(), [])

    def test_exactly_one_result_when_cancels_race_the_jobs(self):
        process = self.start()
        picture = uri(self.image('shot.png', 'x'))
        for ident in range(1, 61):
            if ident % 2:
                process.request(ident, 'image.ocr', {'uri': picture})
            else:
                process.request(ident, 'file.run', {'operation': 'checksum', 'inputs': [], 'text': str(ident), 'options': {}})
            process.send({'type': 'cancel', 'id': ident})
            if ident % 3 == 0:
                process.send({'type': 'cancel', 'id': ident})
        self.assertTrue(process.call(100, 'worker.stats')['ok'])
        for ident in range(1, 61):
            result = process.result(ident)
            self.assertTrue(result['ok'] or result['reason'] == 'cancelled', result)
        self.assertEqual(process.close(), 0)
        self.assertEqual(process.results_by_id(), {ident: 1 for ident in list(range(1, 61)) + [100]})
        answered = set()
        for message in process.seen:
            if message.get('type') == 'result':
                answered.add(message['id'])
            elif 'id' in message:
                self.assertNotIn(message['id'], answered, 'a line arrived after its result')
        self.assertEqual(self.scratch_dirs(), [])


class LifetimeTests(WorkerTestCase):
    def run_slow_job(self):
        pids = self.root / 'pids'
        pids.mkdir()
        process = self.start(FAKE_TESS_PIDS=str(pids), FAKE_TESS_WAIT=str(self.root / 'never'))
        process.request(1, 'image.ocr', {'uri': uri(self.image('shot.png', 'x'))})
        process.request(2, 'image.ocr', {'uri': uri(self.image('other.png', 'y'))})
        process.request(3, 'image.ocr', {'uri': uri(self.image('third.png', 'z'))})
        process.request(4, 'image.ocr', {'uri': uri(self.image('queued.png', 'q'))})
        self.assertTrue(self.wait_for(lambda: len(list(pids.iterdir())) == 3), 'fake tesseract never started')
        return process, [int(path.name) for path in pids.iterdir()]

    def assert_stopped(self, process, children):
        self.assertEqual(process.results_by_id(), {1: 1, 2: 1, 3: 1, 4: 1})
        for ident in (1, 2, 3, 4):
            self.assertEqual(process.result(ident)['reason'], 'service-stopped')
        for child in children:
            self.assert_dead(child)
        self.assertEqual(self.scratch_dirs(), [])

    def test_stdin_eof_cancels_running_jobs_and_exits(self):
        process, children = self.run_slow_job()
        started = time.monotonic()
        self.assertEqual(process.close(), 0)
        self.assertLess(time.monotonic() - started, 3)
        self.assert_stopped(process, children)

    def test_sigterm_cancels_running_jobs_and_exits(self):
        process, children = self.run_slow_job()
        process.process.send_signal(signal.SIGTERM)
        self.assertEqual(process.process.wait(timeout=10), 0)
        process.drain()
        self.assert_stopped(process, children)


class InProcessTests(unittest.TestCase):
    def tearDown(self):
        core.set_threaded(False)

    def test_run_skips_preexec_fn_only_in_threaded_mode(self):
        calls = []
        real = core.subprocess.Popen

        def recording(*args, **kwargs):
            calls.append('preexec_fn' in kwargs)
            return real(*args, **kwargs)
        with mock.patch.object(core.subprocess, 'Popen', recording):
            core.run(['true'], None, 10)
            core.set_threaded(True)
            core.run(['true'], None, 10)
        self.assertEqual(calls, [True, False])

    def test_a_cancelled_scope_starts_nothing_and_cancel_kills_a_running_cli(self):
        core.set_threaded(True)
        scope = core.CancelScope()
        scope.cancel('cancelled')
        with mock.patch.object(core.subprocess, 'Popen') as popen, core.bind_scope(scope):
            with self.assertRaises(core.Cancelled):
                core.run(['true'], None, 10)
        popen.assert_not_called()

        scope = core.CancelScope()
        outcome = {}
        called = threading.Event()
        scope.on_cancel(called.set)

        def job():
            with core.bind_scope(scope):
                try:
                    core.run(['sleep', '30'], None, 60)
                    outcome['value'] = 'finished'
                except core.Cancelled:
                    outcome['value'] = 'cancelled'
        thread = threading.Thread(target=job)
        started = time.monotonic()
        thread.start()
        deadline = time.monotonic() + 5
        while not scope._processes and time.monotonic() < deadline:
            time.sleep(0.01)
        self.assertTrue(scope.cancel('timeout'))
        self.assertFalse(scope.cancel('cancelled'))
        thread.join(timeout=5)
        self.assertEqual(outcome, {'value': 'cancelled'})
        self.assertLess(time.monotonic() - started, 5)
        self.assertEqual(scope.reason, 'timeout')
        self.assertTrue(called.is_set())
        self.assertIsNone(core.current_scope())

    def server(self, ops):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        output = io.BytesIO()
        server = worker.Server(ops, worker.WorkerCache(Path(directory.name) / 'cache'), output)
        server.start()
        self.addCleanup(server.shutdown)
        return server, output

    @staticmethod
    def lines(output):
        return [json.loads(line) for line in output.getvalue().splitlines()]

    def wait(self, predicate):
        deadline = time.monotonic() + 5
        while not predicate() and time.monotonic() < deadline:
            time.sleep(0.01)
        self.assertTrue(predicate())

    def test_a_job_that_ignores_cancel_is_answered_once_after_the_grace(self):
        release = threading.Event()
        cancelled = threading.Event()

        def stubborn(payload, ctx):
            ctx.on_cancel(cancelled.set)
            release.wait(10)
            return worker.ok({'late': True})
        server, output = self.server({'test.stubborn': stubborn})
        with mock.patch.object(worker, 'CANCEL_GRACE_S', 0.2):
            server.handle(b'{"type":"request","id":1,"op":"test.stubborn","payload":{}}\n')
            self.wait(lambda: server.pending.get(1) is not None and server.pending[1].state == 'running')
            server.handle(b'{"type":"cancel","id":1}\n')
            self.wait(lambda: any(line['type'] == 'result' for line in self.lines(output)))
        self.assertTrue(cancelled.is_set())
        self.assertEqual(self.lines(output), [{'type': 'result', 'id': 1, 'result': {'ok': False, 'reason': 'cancelled', 'message': 'Cancelled'}}])
        self.assertEqual(server.stats()['background'], 1)
        release.set()
        self.wait(lambda: not server.live)
        self.assertEqual(len(self.lines(output)), 1)

    def test_partials_come_before_the_result_and_stop_after_it(self):
        contexts = []

        def streaming(payload, ctx):
            contexts.append(ctx)
            self.assertTrue(ctx.progress({'stage': 'loading'}))
            self.assertTrue(ctx.partial({'text': 'He'}))
            self.assertFalse(ctx.partial({'bad': object()}))
            self.assertFalse(ctx.partial({'big': 'x' * (3 * 1024 * 1024)}))
            self.assertGreater(ctx.remaining(), 0)
            self.assertFalse(ctx.cancelled())
            return worker.ok({'text': 'Hello'})
        server, output = self.server({'test.stream': streaming})
        server.handle(b'{"type":"request","id":4,"op":"test.stream","payload":{},"timeoutMs":5000}\n')
        self.wait(lambda: any(line['type'] == 'result' for line in self.lines(output)))
        self.assertEqual(self.lines(output), [
            {'type': 'progress', 'id': 4, 'data': {'stage': 'loading'}},
            {'type': 'partial', 'id': 4, 'chunk': {'text': 'He'}},
            {'type': 'result', 'id': 4, 'result': {'ok': True, 'value': {'text': 'Hello'}, 'cached': False}}])
        self.assertEqual(contexts[0].timeout_s, 5)
        self.assertEqual(contexts[0].request_id, 4)
        self.assertFalse(contexts[0].partial({'text': 'late'}))
        self.assertEqual(len(self.lines(output)), 3)

    def test_op_errors_map_to_result_reasons(self):
        def raising(payload, ctx):
            kind = payload['kind']
            if kind == 'op':
                raise worker.OpError('denied', 'No')
            if kind == 'tool':
                raise core.ToolError('slow', reason='timeout')
            if kind == 'bug':
                raise KeyError('x')
            return {'ok': True, 'value': {'blob': b'bytes'}}
        server, output = self.server({'test.raise': raising})
        self.enterContext(mock.patch.object(worker, 'log'))
        for ident, kind in enumerate(('op', 'tool', 'bug', 'bytes'), start=1):
            server.handle(json.dumps({'type': 'request', 'id': ident, 'op': 'test.raise', 'payload': {'kind': kind}}).encode())
        self.wait(lambda: len(self.lines(output)) == 4)
        reasons = {line['id']: (line['result']['reason'], line['result']['message']) for line in self.lines(output)}
        self.assertEqual(reasons, {1: ('denied', 'No'), 2: ('timeout', 'slow'), 3: ('io', 'KeyError'),
                                   4: ('io', 'The operation returned data that is not JSON')})

    def test_result_normalisation(self):
        self.assertEqual(worker.normalize({'ok': True, 'value': {'a': 1}}), {'ok': True, 'value': {'a': 1}, 'cached': False})
        self.assertEqual(worker.normalize({'ok': False, 'reason': 'missing', 'message': 'No key'}),
                         {'ok': False, 'reason': 'io', 'message': 'No key', 'detail': 'missing'})
        self.assertEqual(worker.normalize({'ok': False, 'reason': 'busy'})['reason'], 'busy')
        self.assertEqual(worker.normalize('nope')['reason'], 'io')
        self.assertEqual(worker.normalize({'ok': True, 'value': [1]})['reason'], 'io')

    def test_zbar_xml_parsing(self):
        self.assertEqual(worker.parse_zbar_xml(ZBAR_XML), [{'type': 'QR-Code', 'text': 'https://example.com/a?b=1'},
                                                          {'type': 'EAN-13', 'text': 'hello\nworld'}])
        self.assertEqual(worker.parse_zbar_xml('<barcodes></barcodes>'), [])

    def test_ocr_option_resolution(self):
        self.assertEqual(image.ocr_language('', ['ukr', 'eng']), 'eng')
        self.assertEqual(image.ocr_language(None, ['ukr']), 'ukr')
        self.assertEqual(image.ocr_language('ukr+eng+deu', ['ukr', 'eng'], True), 'ukr+eng')
        self.assertEqual(image.ocr_language('deu', ['ukr', 'eng'], True), 'eng')
        with self.assertRaises(core.ToolError) as raised:
            image.ocr_language('deu', ['eng'])
        self.assertEqual(raised.exception.reason, 'unavailable')
        self.assertEqual(image.ocr_psm(6), 6)
        self.assertEqual(image.ocr_psm('6'), 6)
        self.assertIsNone(image.ocr_psm(None))
        for bad in (14, -1, True, 'six', 2.5):
            with self.subTest(bad=bad), self.assertRaises(core.ToolError):
                image.ocr_psm(bad)

    def test_extensions_register_ops_and_invalid_ones_are_dropped(self):
        with tempfile.TemporaryDirectory() as directory:
            Path(directory, 'pentad_worker_test_ext.py').write_text(
                'def register_ops(ops):\n'
                '    ops["test.echo"] = lambda payload, ctx: {"ok": True, "value": payload}\n'
                '    ops["Bad Name"] = lambda payload, ctx: None\n'
                '    ops["test.not-callable"] = 5\n')
            Path(directory, 'pentad_worker_broken_ext.py').write_text('raise RuntimeError("boom")\n')
            sys.path.insert(0, directory)
            try:
                ops = {'worker.stats': lambda payload, ctx: None}
                with mock.patch.object(worker, 'log') as log:
                    loaded = worker.load_extensions(ops, ('pentad_worker_test_ext', 'pentad_worker_missing_ext',
                                                          'pentad_worker_broken_ext'))
            finally:
                sys.path.remove(directory)
                sys.modules.pop('pentad_worker_test_ext', None)
                sys.modules.pop('pentad_worker_broken_ext', None)
        self.assertEqual(loaded, ['pentad_worker_test_ext'])
        self.assertEqual(sorted(ops), ['test.echo', 'worker.stats'])
        self.assertTrue(any('broken' in str(call) for call in log.call_args_list))

    def test_check_cancelled_is_a_no_op_without_a_scope(self):
        core.check_cancelled()
        scope = core.CancelScope()
        with core.bind_scope(scope):
            core.check_cancelled()
            scope.cancel('timeout')
            with self.assertRaises(core.Cancelled):
                core.check_cancelled()
        core.check_cancelled()


class _SlowDigest:
    """Wraps a hashlib object so every update() takes 50 ms: a stand-in for hashing a huge file."""
    updates = []

    def __init__(self, real):
        self.real = real
        self.count = 0
        _SlowDigest.updates.append(self)

    def update(self, data):
        self.count += 1
        time.sleep(0.05)
        self.real.update(data)

    def hexdigest(self):
        return self.real.hexdigest()


class CancellableLoopTests(unittest.TestCase):
    """A cancelled job stuck in a pure-Python copy or hash loop gives its thread back promptly,
    so three such jobs do not block a fourth request."""
    server = InProcessTests.server
    lines = staticmethod(InProcessTests.lines)
    wait = InProcessTests.wait

    def setUp(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.root = Path(directory.name)
        self.tmp = self.root / 'tmp'
        self.tmp.mkdir()
        self.enterContext(mock.patch.object(tempfile, 'tempdir', str(self.tmp)))
        # Forced answers after the grace would hide a stuck thread; only an unwound job answers.
        self.enterContext(mock.patch.object(worker, 'CANCEL_GRACE_S', 30.0))
        _SlowDigest.updates = []

    def big(self, name, mib):
        path = self.root / name
        with open(path, 'wb') as handle:
            handle.truncate(mib * 1024 * 1024)
        return path

    def results(self, output):
        return {line['id']: line['result'] for line in self.lines(output) if line['type'] == 'result'}

    def assert_slots_free_after_stop(self, server, output, stop, chunks):
        self.wait(lambda: sum(1 for digest in _SlowDigest.updates if digest.count) >= 3)
        started = time.monotonic()
        stop()
        server.handle(b'{"type":"request","id":4,"op":"file.run","payload":'
                      b'{"operation":"checksum","inputs":[],"text":"abc","options":{}}}\n')
        self.wait(lambda: 4 in self.results(output))
        self.assertLess(time.monotonic() - started, 1.5)
        self.wait(lambda: {1, 2, 3} <= set(self.results(output)))
        self.assertLess(time.monotonic() - started, 1.5)
        self.wait(lambda: not server.live)
        self.assertEqual(server.stats()['background'], 0)
        # Each stopped loop quit long before it had read the whole input.
        self.assertTrue(all(digest.count < chunks for digest in _SlowDigest.updates))
        return self.results(output)

    def test_a_cancelled_large_copy_stops_and_frees_its_slot(self):
        source = uri(self.big('huge.pdf', 64))
        real = worker.hashlib
        slow = mock.Mock(sha256=lambda: _SlowDigest(real.sha256()))
        self.enterContext(mock.patch.object(worker, 'hashlib', slow))

        def copy(payload, ctx):
            return worker._cached(ctx, 'test.copy', {}, payload, 'engine', lambda job: {'done': True})
        ops = worker.builtin_ops(None)
        ops['test.copy'] = copy
        server, output = self.server(ops)
        for ident in (1, 2, 3):
            server.handle(json.dumps({'type': 'request', 'id': ident, 'op': 'test.copy', 'payload': {'uri': source},
                                      'timeoutMs': 400 if ident == 3 else 60000}).encode())

        def stop():
            server.handle(b'{"type":"cancel","id":1}\n')
            server.handle(b'{"type":"cancel","id":2}\n')
        results = self.assert_slots_free_after_stop(server, output, stop, 64)
        self.assertEqual({ident: results[ident].get('reason') for ident in (1, 2, 3)},
                         {1: 'cancelled', 2: 'cancelled', 3: 'timeout'})
        self.assertTrue(results[4]['ok'], results[4])
        self.assertEqual([path for path in self.tmp.iterdir() if path.name.startswith('.pentad-tool-')], [])
        self.assertEqual(server.cache.stats()['entries'], 0)

    def test_a_cancelled_checksum_stops_and_frees_its_slot(self):
        archive = sys.modules[worker.file_tool.checksum.__module__]
        real = archive.hashlib
        slow = mock.Mock(new=lambda name, data=b'': _SlowDigest(real.new(name, data)))
        self.enterContext(mock.patch.object(archive, 'hashlib', slow))
        files = [uri(self.big(f'disk-{index}.img', 32)) for index in range(3)]
        server, output = self.server(worker.builtin_ops(None))
        for ident in (1, 2, 3):
            server.handle(json.dumps({'type': 'request', 'id': ident, 'op': 'file.run',
                                      'payload': {'operation': 'checksum', 'inputs': files, 'options': {}},
                                      'timeoutMs': 400 if ident == 3 else 60000}).encode())

        def stop():
            server.handle(b'{"type":"cancel","id":1}\n')
            server.handle(b'{"type":"cancel","id":2}\n')
        results = self.assert_slots_free_after_stop(server, output, stop, 32)
        self.assertEqual({ident: results[ident].get('reason') for ident in (1, 2, 3)},
                         {1: 'cancelled', 2: 'cancelled', 3: 'timeout'})
        self.assertEqual(results[4]['value']['text'], real.sha256(b'abc').hexdigest())


class InputStatKeyTests(unittest.TestCase):
    """A repeated cached op on an unchanged file skips the copy; any change to the file misses."""

    def setUp(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.root = Path(directory.name)
        self.tmp = self.root / 'tmp'
        self.tmp.mkdir()
        self.enterContext(mock.patch.object(tempfile, 'tempdir', str(self.tmp)))
        # The tests write their files just now; trust stat keys at once unless a test says so.
        self.enterContext(mock.patch.object(worker, 'INPUT_SETTLE_NS', 0))
        self.copy = self.enterContext(mock.patch.object(worker._Scratch, '_copy', autospec=True,
                                                        side_effect=worker._Scratch._copy))
        self.cache = worker.WorkerCache(self.root / 'cache')
        self.ctx = mock.Mock(cache=self.cache, check=lambda: None)
        self.computed = []

    def call(self, path, cache=None):
        def compute(job):
            data = job.inputs[0].read_bytes()
            self.computed.append(data[:8])
            return {'size': len(data), 'head': data[:8].hex()}
        ctx = self.ctx if cache is None else mock.Mock(cache=cache, check=lambda: None)
        result = worker._cached(ctx, 'test.op', {'o': 1}, {'uri': uri(path)}, 'engine-1', compute)
        self.assertEqual(list(self.tmp.iterdir()), [])
        return result

    def big(self, name, head=b'A'):
        path = self.root / name
        path.write_bytes(head * 8 + os.urandom(8 * 1024 * 1024))
        return path

    def test_an_unchanged_file_is_answered_without_copying(self):
        path = self.big('doc.pdf')
        first = self.call(path)
        self.assertEqual((first['cached'], self.copy.call_count), (False, 1))
        for _ in range(3):
            again = self.call(path)
            self.assertEqual(again, dict(first, cached=True))
        self.assertEqual((self.copy.call_count, len(self.computed)), (1, 1))
        stats = self.cache.stats()
        self.assertEqual((stats['entries'], stats['hits'], stats['misses'], stats['stores']), (2, 3, 1, 1))
        for entry in (self.root / 'cache').iterdir():
            self.assertEqual(stat.S_IMODE(entry.stat().st_mode), 0o600)

    def test_a_size_or_mtime_change_misses(self):
        path = self.big('doc.pdf')
        self.call(path)
        with open(path, 'ab') as handle:
            handle.write(b'more')
        grown = self.call(path)
        self.assertEqual((grown['cached'], self.copy.call_count, len(self.computed)), (False, 2, 2))
        self.assertEqual(grown['value']['size'], 8 + 8 * 1024 * 1024 + 4)
        # Only the time moved: the stat key misses, the content hash still hits.
        info = path.stat()
        os.utime(path, ns=(info.st_atime_ns, info.st_mtime_ns - 5 * 10 ** 9))
        touched = self.call(path)
        self.assertEqual((touched['cached'], self.copy.call_count, len(self.computed)), (True, 3, 2))
        self.assertEqual(self.call(path)['cached'], True)
        self.assertEqual(self.copy.call_count, 3)

    def test_new_bytes_of_the_same_size_with_the_mtime_put_back_miss(self):
        path = self.big('doc.pdf')
        info = path.stat()
        self.call(path)
        time.sleep(0.05)  # past the file system's timestamp tick
        with open(path, 'r+b') as handle:
            handle.write(b'B' * 8)
        os.utime(path, ns=(info.st_atime_ns, info.st_mtime_ns))
        self.assertEqual((path.stat().st_size, path.stat().st_mtime_ns), (info.st_size, info.st_mtime_ns))
        changed = self.call(path)
        self.assertEqual((changed['cached'], changed['value']['head']), (False, (b'B' * 8).hex()))
        self.assertEqual(self.copy.call_count, 2)

    def test_a_replaced_file_misses(self):
        path = self.big('doc.pdf')
        self.call(path)
        twin = self.root / 'twin.pdf'
        twin.write_bytes(path.read_bytes())
        info = path.stat()
        os.utime(twin, ns=(info.st_atime_ns, info.st_mtime_ns))
        os.replace(twin, path)
        self.assertNotEqual(path.stat().st_ino, info.st_ino)
        replaced = self.call(path)
        # A new inode is a stat-key miss; the same bytes are still a result hit.
        self.assertEqual((replaced['cached'], self.copy.call_count, len(self.computed)), (True, 2, 1))

    def test_a_symlink_is_followed_and_retargeting_it_misses(self):
        first, second = self.big('a.pdf', b'A'), self.big('b.pdf', b'B')
        link = self.root / 'link.pdf'
        link.symlink_to(first)
        self.assertEqual(self.call(link)['value']['head'], (b'A' * 8).hex())
        self.call(link)
        self.assertEqual(self.copy.call_count, 1)
        link.unlink()
        link.symlink_to(second)
        self.assertEqual(self.call(link)['value']['head'], (b'B' * 8).hex())
        self.assertEqual(self.copy.call_count, 2)

    def test_a_file_that_has_not_settled_is_not_indexed(self):
        path = self.big('fresh.pdf')
        with mock.patch.object(worker, 'INPUT_SETTLE_NS', 3 * 10 ** 9):
            self.call(path)
            self.assertEqual(self.call(path)['cached'], True)
        self.assertEqual((self.copy.call_count, self.cache.stats()['entries']), (2, 1))
        # A file changed while it was copied is not indexed either.
        with mock.patch.object(worker._Input, 'unchanged', return_value=False):
            self.call(path)
        self.assertEqual((self.copy.call_count, self.cache.stats()['entries']), (3, 1))

    def test_an_index_entry_that_disagrees_with_the_bytes_is_dropped(self):
        path = self.big('doc.pdf')
        source = worker._Input({'uri': uri(path)})
        key = source.stat_key()
        source.close()
        self.assertTrue(self.cache.remember_input(key, worker.hashlib.sha256(b'other').hexdigest()))
        self.assertEqual(self.call(path)['value']['head'], (b'A' * 8).hex())
        self.assertIsNone(self.cache.input_hash(key))
        self.call(path)
        self.call(path)
        self.assertEqual(self.copy.call_count, 2)

    def test_no_cache_and_bad_inputs_behave_as_before(self):
        path = self.big('doc.pdf')
        disabled = worker.WorkerCache(self.root / 'off', max_bytes=0)
        for _ in range(2):
            self.assertEqual(self.call(path, cache=disabled)['cached'], False)
        self.assertEqual(self.copy.call_count, 2)
        folder = self.root / 'folder'
        folder.mkdir()
        for target, reason, message in ((folder, 'unsupported', 'folder is not a regular file'),
                                        (self.root / 'gone.pdf', 'io', 'gone.pdf no longer exists')):
            with self.subTest(target=target.name), self.assertRaises(worker.OpError) as raised:
                self.call(target)
            self.assertEqual((raised.exception.reason, raised.exception.message), (reason, message))


if __name__ == '__main__':
    unittest.main()
