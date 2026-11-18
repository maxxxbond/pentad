"""Opt-in checks against a real local Ollama: `PENTAD_LIVE_OLLAMA=1 python3 -m unittest
tests/tools/test_pentad_worker_live.py`. Default suites skip this file.

Needs `ollama serve` on http://127.0.0.1:11434 with `qwen3.5:0.8b` and `embeddinggemma-2:270m`
pulled. Nothing is pulled, deleted or unloaded here; requests use keepAlive "30s", so the
models leave memory on Ollama's own schedule. Timings are printed to stderr.
"""
import json
import os
import queue
import subprocess
import sys
import tempfile
import threading
import time
import unittest
from pathlib import Path

from tools import pentad_worker as worker

LIVE = os.environ.get('PENTAD_LIVE_OLLAMA') == '1'
BASE_URL = 'http://127.0.0.1:11434'
CHAT_MODEL = 'qwen3.5:0.8b'
EMBED_MODEL = 'embeddinggemma-2:270m'
KEEP_ALIVE = '30s'
COLD_LOAD_S = 180
PROVIDER = {'kind': 'ollama', 'baseUrl': BASE_URL, 'credential': '', 'credentialEnv': ''}


def note(text):
    sys.stderr.write(f'\n[live] {text}\n')
    sys.stderr.flush()


@unittest.skipUnless(LIVE, 'set PENTAD_LIVE_OLLAMA=1 to run against the local Ollama')
class LiveOllamaTests(unittest.TestCase):
    """One real worker process for the whole class, spoken to over its protocol."""

    @classmethod
    def setUpClass(cls):
        cls.directory = tempfile.TemporaryDirectory()
        root = Path(cls.directory.name)
        env = dict(os.environ, HOME=str(root), XDG_CACHE_HOME=str(root / 'cache'), TMPDIR=str(root))
        started = time.monotonic()
        cls.process = subprocess.Popen([sys.executable, '-I', str(Path(worker.__file__).resolve()), '--serve',
                                        '--cache-root', str(root / 'cache')],
                                       stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, env=env)
        cls.lines = queue.Queue()
        threading.Thread(target=cls._read, daemon=True).start()
        hello = cls.lines.get(timeout=10)
        note(f'worker hello after {time.monotonic() - started:.3f} s')
        assert hello and hello['type'] == 'hello', hello
        cls.next_id = 0

    @classmethod
    def _read(cls):
        for line in cls.process.stdout:
            cls.lines.put(json.loads(line))
        cls.lines.put(None)

    @classmethod
    def tearDownClass(cls):
        try:
            cls.process.stdin.close()
            cls.process.wait(timeout=10)
        finally:
            if cls.process.poll() is None:
                cls.process.kill()
                cls.process.wait()
            cls.process.stdout.close()
            cls.directory.cleanup()

    def call(self, op, payload, timeout=COLD_LOAD_S):
        type(self).next_id += 1
        ident = self.next_id
        started = time.monotonic()
        self.process.stdin.write(json.dumps({'type': 'request', 'id': ident, 'op': op, 'payload': payload,
                                             'timeoutMs': timeout * 1000}).encode() + b'\n')
        self.process.stdin.flush()
        partials = []
        first = None
        while True:
            message = self.lines.get(timeout=timeout + 10)
            self.assertIsNotNone(message, 'the worker exited')
            if message.get('id') != ident:
                continue
            if message['type'] == 'partial':
                first = first or time.monotonic() - started
                partials.append(message['chunk'])
            elif message['type'] == 'result':
                return message['result'], partials, time.monotonic() - started, first

    def test_1_models_lists_the_chat_model_with_vision(self):
        result, _, elapsed, _ = self.call('llm.models', {'provider': PROVIDER}, 30)
        self.assertTrue(result['ok'], result)
        models = {entry['name']: entry for entry in result['value']['models']}
        note(f'llm.models: {len(models)} models in {elapsed:.3f} s')
        self.assertIn(CHAT_MODEL, models)
        self.assertIn('vision', models[CHAT_MODEL].get('capabilities', []))
        self.assertIn('completion', models[CHAT_MODEL]['capabilities'])
        self.assertIn(EMBED_MODEL, models)
        self.assertIn('embedding', models[EMBED_MODEL].get('capabilities', []))

    def test_2_warm_loads_the_chat_model(self):
        result, _, elapsed, _ = self.call('llm.warm', {'provider': PROVIDER, 'model': CHAT_MODEL, 'keepAlive': KEEP_ALIVE})
        self.assertTrue(result['ok'], result)
        self.assertTrue(result['value']['warmed'])
        note(f'llm.warm {CHAT_MODEL}: loadMs={result["value"]["loadMs"]} wallMs={result["value"]["wallMs"]} '
             f'(round trip {elapsed:.3f} s)')
        again, _, elapsed, _ = self.call('llm.warm', {'provider': PROVIDER, 'model': CHAT_MODEL, 'keepAlive': KEEP_ALIVE})
        self.assertTrue(again['ok'], again)
        note(f'llm.warm again (resident): loadMs={again["value"]["loadMs"]} (round trip {elapsed:.3f} s)')

    def test_3_chat_streams_a_one_line_answer(self):
        payload = {'provider': PROVIDER, 'model': CHAT_MODEL, 'keepAlive': KEEP_ALIVE, 'temperature': 0, 'maxTokens': 32,
                   'messages': [{'role': 'user', 'content': 'Reply with one short word: what colour is the sky on a clear day?'}]}
        result, partials, elapsed, first = self.call('llm.chat', payload)
        self.assertTrue(result['ok'], result)
        text = result['value']['text']
        self.assertTrue(text.strip(), result)
        self.assertEqual(''.join(chunk['text'] for chunk in partials), text)
        note(f'llm.chat {CHAT_MODEL}: {elapsed:.3f} s total, first partial {first if first is None else round(first, 3)} s, '
             f'{len(partials)} partials, usage={result["value"].get("usage")}, text={text.strip()[:60]!r}')

    def test_4_embed_returns_vectors(self):
        payload = {'provider': PROVIDER, 'model': EMBED_MODEL, 'keepAlive': KEEP_ALIVE, 'input': ['hello world', 'привіт світ']}
        result, _, elapsed, _ = self.call('llm.embed', payload)
        self.assertTrue(result['ok'], result)
        vectors = result['value']['vectors']
        self.assertEqual(len(vectors), 2)
        self.assertGreater(result['value']['dims'], 0)
        self.assertTrue(all(len(vector) == result['value']['dims'] for vector in vectors))
        note(f'llm.embed {EMBED_MODEL}: {elapsed:.3f} s, dims={result["value"]["dims"]}')


if __name__ == '__main__':
    unittest.main()
