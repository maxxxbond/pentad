import json
import os
import queue
import socket
import subprocess
import sys
import tempfile
import threading
import time
import unittest
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from unittest import mock
from urllib.parse import quote

from tools import pentad_worker as worker
from tools import pentad_worker_llm as llm

core = worker.core
WORKER = Path(worker.__file__).resolve()
KEY = 'sk-pentad-TEST-0123456789abcdef'
PNG = b'\x89PNG\r\n\x1a\n' + b'\x00' * 32
JPEG = b'\xff\xd8\xff\xe0' + b'\x00' * 32
WEBP = b'RIFF\x24\x00\x00\x00WEBPVP8 ' + b'\x00' * 32


def uri(path):
    return 'file://' + quote(str(path), safe='/')


class Ctx:
    """The worker's per-request context, in process."""

    def __init__(self, timeout=30):
        self.scope = core.CancelScope()
        self.request_id = 1
        self.op = 'test'
        self.timeout_s = timeout
        self.deadline = time.monotonic() + timeout
        self.partials = []
        self.progresses = []
        self.cache_root = ''

    def cancelled(self):
        return self.scope.cancelled

    def check(self):
        self.scope.check()

    def on_cancel(self, callback):
        self.scope.on_cancel(callback)

    def remaining(self):
        return max(0.0, self.deadline - time.monotonic())

    def partial(self, chunk):
        self.partials.append(chunk)
        return True

    def progress(self, data):
        self.progresses.append(data)
        return True


# --- A loopback provider ----------------------------------------------------------

class Handler(BaseHTTPRequestHandler):
    protocol_version = 'HTTP/1.1'

    def log_message(self, *args):
        pass

    def _handle(self):
        length = int(self.headers.get('Content-Length') or 0)
        raw = self.rfile.read(length) if length else b''
        try:
            body = json.loads(raw) if raw else None
        except ValueError:
            body = raw
        owner = self.server.owner
        record = {'method': self.command, 'path': self.path, 'headers': {k.lower(): v for k, v in self.headers.items()},
                  'body': body, 'raw': raw}
        owner.requests.append(record)
        self.close_connection = True
        route = owner.routes.get((self.command, self.path.split('?')[0]))
        if route is None:
            self.send_json(404, {'error': 'no such route'})
            return
        try:
            route(self, record)
        except (BrokenPipeError, ConnectionResetError):
            owner.disconnected.set()

    do_GET = _handle
    do_POST = _handle

    def send_json(self, status, document, headers=()):
        data = document if isinstance(document, bytes) else json.dumps(document).encode()
        self.send_response(status)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(data)))
        for name, value in headers:
            self.send_header(name, value)
        self.end_headers()
        self.wfile.write(data)

    def chunk(self, data):
        data = data.encode() if isinstance(data, str) else data
        self.wfile.write(b'%x\r\n%s\r\n' % (len(data), data))
        self.wfile.flush()

    def send_stream(self, chunks, content_type='application/x-ndjson', hold=False, keepalive='\n'):
        self.send_response(200)
        self.send_header('Content-Type', content_type)
        self.send_header('Transfer-Encoding', 'chunked')
        self.end_headers()
        for item in chunks:
            self.chunk(item)
        if hold:
            # Trickle keep-alives until the client goes away (or 30 s pass).
            owner = self.server.owner
            for _ in range(600):
                time.sleep(0.05)
                try:
                    self.chunk(keepalive)
                except (BrokenPipeError, ConnectionResetError, OSError):
                    owner.disconnected.set()
                    return
            return
        self.wfile.write(b'0\r\n\r\n')
        self.wfile.flush()


class FakeProvider:
    def __init__(self):
        self.routes = {}
        self.requests = []
        self.disconnected = threading.Event()
        self.server = ThreadingHTTPServer(('127.0.0.1', 0), Handler)
        self.server.daemon_threads = True
        self.server.owner = self
        self.thread = threading.Thread(target=self.server.serve_forever, kwargs={'poll_interval': 0.05}, daemon=True)
        self.thread.start()
        self.url = f'http://127.0.0.1:{self.server.server_address[1]}'

    def route(self, method, path, handler):
        self.routes[(method, path)] = handler

    def json(self, method, path, document, status=200, headers=()):
        self.route(method, path, lambda h, r: h.send_json(status, document, headers))

    def stream(self, path, chunks, content_type='application/x-ndjson', **extra):
        self.route('POST', path, lambda h, r: h.send_stream(chunks, content_type, **extra))

    def close(self):
        self.server.shutdown()
        self.server.server_close()


def ndjson(*events):
    return [json.dumps(event) + '\n' for event in events]


def sse(*events, crlf=False):
    end = '\r\n' if crlf else '\n'
    out = []
    for event in events:
        name, data = event if isinstance(event, tuple) else ('', event)
        text = data if isinstance(data, str) else json.dumps(data)
        out.append((f'event: {name}{end}' if name else '') + f'data: {text}{end}{end}')
    return out


OLLAMA_HELLO = ndjson({'message': {'role': 'assistant', 'content': 'Hel'}, 'done': False},
                      {'message': {'role': 'assistant', 'content': 'lo'}, 'done': False},
                      {'message': {'role': 'assistant', 'content': ''}, 'done': True, 'done_reason': 'stop',
                       'prompt_eval_count': 5, 'eval_count': 2})
OPENAI_HELLO = sse({'choices': [{'delta': {'role': 'assistant'}}]}, {'choices': [{'delta': {'content': 'Hel'}}]},
                   {'choices': [{'delta': {'content': 'lo'}, 'finish_reason': 'stop'}]}, '[DONE]')
ANTHROPIC_HELLO = sse(('message_start', {'type': 'message_start', 'message': {'usage': {'input_tokens': 7}}}),
                      ('content_block_start', {'type': 'content_block_start', 'index': 0, 'content_block': {'type': 'text', 'text': ''}}),
                      ('ping', {'type': 'ping'}),
                      ('content_block_delta', {'type': 'content_block_delta', 'index': 0, 'delta': {'type': 'text_delta', 'text': 'Hel'}}),
                      ('content_block_delta', {'type': 'content_block_delta', 'index': 0, 'delta': {'type': 'text_delta', 'text': 'lo'}}),
                      ('message_delta', {'type': 'message_delta', 'delta': {'stop_reason': 'end_turn'}, 'usage': {'output_tokens': 2}}),
                      ('message_stop', {'type': 'message_stop'}))
GEMINI_HELLO = sse({'candidates': [{'content': {'role': 'model', 'parts': [{'text': 'Hel'}]}}]},
                   {'candidates': [{'content': {'parts': [{'text': 'pondering', 'thought': True}, {'text': 'lo'}]},
                                    'finishReason': 'STOP'}],
                    'usageMetadata': {'promptTokenCount': 3, 'candidatesTokenCount': 2}}, crlf=True)


class ProviderTestCase(unittest.TestCase):
    def setUp(self):
        self.fake = FakeProvider()
        self.addCleanup(self.fake.close)
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.ops = {}
        llm.register_ops(self.ops)
        patcher = mock.patch.dict(os.environ, {'PENTAD_TEST_KEY': KEY})
        patcher.start()
        self.addCleanup(patcher.stop)

    def provider(self, kind='ollama', key=False, url=None):
        return {'kind': kind, 'baseUrl': url or self.fake.url, 'credential': '', 'credentialEnv': 'PENTAD_TEST_KEY' if key else ''}

    def call(self, op, payload, ctx=None):
        ctx = ctx or Ctx()
        result = self.ops[op](payload, ctx)
        normalized = worker.normalize(result)
        self.assertNotIn(KEY, json.dumps(normalized))
        self.assertNotIn(KEY, json.dumps(ctx.partials + ctx.progresses))
        return normalized, ctx

    def chat(self, kind='ollama', key=False, **fields):
        payload = dict({'provider': self.provider(kind, key), 'model': 'm', 'messages': [{'role': 'user', 'content': 'Hi'}]}, **fields)
        return self.call('llm.chat', payload)

    def failure(self, result, reason):
        self.assertFalse(result['ok'], result)
        self.assertEqual(result['reason'], reason, result)
        return result['message']

    def file(self, name, data):
        path = self.root / name
        path.write_bytes(data)
        return path


class EndpointTests(unittest.TestCase):
    def test_same_rule_as_models_mjs(self):
        accepted = {
            'https://api.openai.com/v1': 'https://api.openai.com/v1',
            'https://openrouter.ai/api/v1/': 'https://openrouter.ai/api/v1',
            'https://example.com:8443': 'https://example.com:8443',
            'http://localhost:11434': 'http://localhost:11434',
            'http://127.0.0.1:11434': 'http://127.0.0.1:11434',
            'http://127.8.9.10/v1': 'http://127.8.9.10/v1',
            'http://[::1]:11434/': 'http://[::1]:11434',
            'https://[::1]': 'https://[::1]',
            'https://192.168.1.20/v1': 'https://192.168.1.20/v1',
            '  HTTPS://API.Example.COM/V1  ': 'https://api.example.com/V1',
            'https://example.com/v1\n': 'https://example.com/v1',
            'https://EXAMPLE.com:0080/a//': 'https://example.com:80/a',
        }
        for url, normalised in accepted.items():
            self.assertEqual(llm.validate_endpoint(url), {'ok': True, 'url': normalised}, url)
        for url in ['http://api.openai.com/v1', 'http://192.168.1.20:11434', 'http://10.0.0.5', 'http://0.0.0.0:11434',
                    'http://127.example.com', 'http://127.0.0.1.example.com', 'http://localhost.example.com',
                    'http://[::2]:11434', 'http://[fe80::1]']:
            self.assertEqual(llm.validate_endpoint(url), {'ok': False, 'reason': 'insecure-endpoint'}, url)
        for url in ['', '   ', 'localhost:11434', 'ftp://example.com', 'file:///etc/passwd', 'https://',
                    'https://user:pass@example.com', 'https://example.com/v1?key=1', 'https://example.com/v1#frag',
                    'https://example.com:0', 'https://example.com:70000', 'https://exa mple.com',
                    'https://example.com/a b', 'javascript:alert(1)', f'https://example.com/{"a" * 2048}',
                    'https://example.com/ x', 'http://[::1]x', None, 42, {}]:
            self.assertEqual(llm.validate_endpoint(url), {'ok': False, 'reason': 'invalid-url'}, repr(url))

    def test_parts_carry_the_connect_target(self):
        self.assertEqual({k: v for k, v in llm.endpoint_parts('http://[::1]:11434/x/').items() if k != 'url'},
                         {'protocol': 'http', 'host': '::1', 'port': 11434, 'path': '/x', 'loopback': True})
        self.assertEqual(llm.endpoint_parts('https://api.example.com')['port'], 443)

    def test_insecure_and_invalid_endpoints_never_connect(self):
        ops = {}
        llm.register_ops(ops)
        payload = {'provider': {'kind': 'ollama', 'baseUrl': 'http://example.com'}, 'model': 'm',
                   'messages': [{'role': 'user', 'content': 'x'}]}
        self.assertEqual(ops['llm.chat'](payload, Ctx())['reason'], 'denied')
        payload['provider']['baseUrl'] = 'https://user:pw@example.com'
        self.assertEqual(ops['llm.chat'](payload, Ctx())['reason'], 'invalid-input')
        payload['provider'] = {'kind': 'mystery', 'baseUrl': 'https://example.com'}
        self.assertEqual(ops['llm.chat'](payload, Ctx())['reason'], 'unsupported')


class ChatTests(ProviderTestCase):
    def test_ollama_streams_ndjson_with_think_off_and_no_keep_alive(self):
        self.fake.stream('/api/chat', OLLAMA_HELLO)
        result, ctx = self.chat(temperature=0, maxTokens=64)
        self.assertEqual(result, {'ok': True, 'cached': False, 'value': {
            'text': 'Hello', 'usage': {'inputTokens': 5, 'outputTokens': 2}, 'finishReason': 'stop'}})
        self.assertEqual(ctx.partials, [{'text': 'Hel'}, {'text': 'lo'}])
        body = self.fake.requests[0]['body']
        self.assertEqual(body['think'], False)
        self.assertTrue(body['stream'])
        self.assertNotIn('keep_alive', body)
        self.assertEqual(body['options'], {'temperature': 0, 'num_predict': 64})
        self.assertEqual(body['messages'], [{'role': 'user', 'content': 'Hi'}])
        self.assertNotIn('authorization', self.fake.requests[0]['headers'])

    def test_ollama_think_keep_alive_and_images(self):
        self.fake.stream('/api/chat', OLLAMA_HELLO)
        image = self.file('a.png', PNG)
        result, _ = self.chat(think=True, keepAlive='30s',
                              messages=[{'role': 'system', 'content': 'S'}, {'role': 'user', 'content': 'Look', 'images': [uri(image)]}])
        self.assertTrue(result['ok'], result)
        body = self.fake.requests[0]['body']
        self.assertEqual((body['think'], body['keep_alive']), (True, '30s'))
        import base64
        self.assertEqual(body['messages'][1]['images'], [base64.b64encode(PNG).decode()])
        self.assertEqual(self.chat(keepAlive='')[0]['ok'], True)
        self.assertNotIn('keep_alive', self.fake.requests[1]['body'])
        self.failure(self.chat(keepAlive='forever; rm')[0], 'invalid-input')
        self.failure(self.chat(think='yes')[0], 'invalid-input')

    def test_ollama_retries_without_think_when_the_model_has_no_thinking_mode(self):
        calls = []

        def route(handler, record):
            calls.append(record['body'])
            if len(calls) == 1:
                handler.send_json(400, {'error': '"m" does not support thinking'})
            else:
                handler.send_stream(OLLAMA_HELLO)
        self.fake.route('POST', '/api/chat', route)
        result, _ = self.chat()
        self.assertEqual(result['value']['text'], 'Hello')
        self.assertEqual(calls[0]['think'], False)
        self.assertNotIn('think', calls[1])

    def test_openai_compatible_sse_with_bearer_key_and_data_url_images(self):
        self.fake.stream('/v1/chat/completions', OPENAI_HELLO, 'text/event-stream')
        image = self.file('a.jpg', JPEG)
        payload = {'provider': self.provider('openai-compatible', key=True, url=self.fake.url + '/v1/'), 'model': 'gpt',
                   'messages': [{'role': 'user', 'content': 'Look', 'images': [uri(image)]}], 'maxTokens': 10}
        result, ctx = self.call('llm.chat', payload)
        self.assertEqual(result['value'], {'text': 'Hello', 'finishReason': 'stop'})
        self.assertEqual(ctx.partials, [{'text': 'Hel'}, {'text': 'lo'}])
        request = self.fake.requests[0]
        self.assertEqual(request['path'], '/v1/chat/completions')
        self.assertEqual(request['headers']['authorization'], f'Bearer {KEY}')
        self.assertEqual(request['body']['stream'], True)
        self.assertEqual(request['body']['max_tokens'], 10)
        content = request['body']['messages'][0]['content']
        self.assertEqual(content[0], {'type': 'text', 'text': 'Look'})
        self.assertTrue(content[1]['image_url']['url'].startswith('data:image/jpeg;base64,/9j/'))

    def test_anthropic_folds_system_and_sends_its_headers(self):
        self.fake.stream('/v1/messages', ANTHROPIC_HELLO, 'text/event-stream')
        image = self.file('a.webp', WEBP)
        payload = {'provider': self.provider('anthropic', key=True), 'model': 'claude',
                   'messages': [{'role': 'system', 'content': 'Be brief.'}, {'role': 'system', 'content': 'Data only.'},
                                {'role': 'user', 'content': 'Look', 'images': [uri(image)]}], 'temperature': 1.5}
        result, _ = self.call('llm.chat', payload)
        self.assertEqual(result['value'], {'text': 'Hello', 'usage': {'inputTokens': 7, 'outputTokens': 2}, 'finishReason': 'stop'})
        request = self.fake.requests[0]
        self.assertEqual(request['headers']['x-api-key'], KEY)
        self.assertEqual(request['headers']['anthropic-version'], '2023-06-01')
        self.assertNotIn('authorization', request['headers'])
        body = request['body']
        self.assertEqual(body['system'], 'Be brief.\n\nData only.')
        self.assertEqual(body['max_tokens'], 1024)
        self.assertEqual(body['temperature'], 1)
        self.assertEqual([m['role'] for m in body['messages']], ['user'])
        self.assertEqual(body['messages'][0]['content'][0]['source']['media_type'], 'image/webp')
        self.assertEqual(body['messages'][0]['content'][1], {'type': 'text', 'text': 'Look'})

    def test_gemini_uses_a_header_key_and_model_roles(self):
        path = '/v1beta/models/gemini-x:streamGenerateContent'
        self.fake.stream(path, GEMINI_HELLO, 'text/event-stream')
        gif = self.file('a.gif', b'GIF89a' + b'\x00' * 20)
        payload = {'provider': self.provider('gemini', key=True, url=self.fake.url + '/v1beta'), 'model': 'models/gemini-x',
                   'messages': [{'role': 'system', 'content': 'S'}, {'role': 'user', 'content': 'A', 'images': [uri(gif)]},
                                {'role': 'assistant', 'content': 'B'}, {'role': 'user', 'content': 'C'}]}
        result, ctx = self.call('llm.chat', payload)
        self.assertEqual(result['value'], {'text': 'Hello', 'usage': {'inputTokens': 3, 'outputTokens': 2}, 'finishReason': 'stop'})
        self.assertEqual(ctx.partials, [{'text': 'Hel'}, {'text': 'lo'}])
        request = self.fake.requests[0]
        self.assertEqual(request['path'], path + '?alt=sse')
        self.assertNotIn(KEY, request['path'])
        self.assertEqual(request['headers']['x-goog-api-key'], KEY)
        body = request['body']
        self.assertEqual(body['systemInstruction'], {'parts': [{'text': 'S'}]})
        self.assertEqual([c['role'] for c in body['contents']], ['user', 'model', 'user'])
        self.assertEqual(body['contents'][0]['parts'][1]['inline_data']['mime_type'], 'image/gif')

    def test_secret_reference_resolves_through_secret_tool(self):
        bin_dir = self.root / 'bin'
        bin_dir.mkdir()
        tool = bin_dir / 'secret-tool'
        tool.write_text('#!/bin/sh\n[ "$1" = lookup ] && [ "$3" = providers/ok ] && { printf %s "$FAKE_SECRET"; exit 0; }\nexit 1\n')
        tool.chmod(0o755)
        self.fake.stream('/api/chat', OLLAMA_HELLO)
        with mock.patch.dict(os.environ, {'PATH': f'{bin_dir}:/usr/bin:/bin', 'FAKE_SECRET': KEY}):
            provider = dict(self.provider(), credential='secret://pentad/providers/ok')
            result, _ = self.call('llm.chat', {'provider': provider, 'model': 'm', 'messages': [{'role': 'user', 'content': 'x'}]})
            self.assertTrue(result['ok'], result)
            self.assertEqual(self.fake.requests[0]['headers']['authorization'], f'Bearer {KEY}')
            provider['credential'] = 'secret://pentad/providers/absent'
            result, _ = self.call('llm.chat', {'provider': provider, 'model': 'm', 'messages': [{'role': 'user', 'content': 'x'}]})
            self.assertEqual((result['reason'], result['detail']), ('unavailable', 'missing'))
            self.assertEqual(len(self.fake.requests), 1)
        with mock.patch.dict(os.environ, {'PATH': str(self.root / 'nothing')}):
            result, _ = self.call('llm.chat', {'provider': provider, 'model': 'm', 'messages': [{'role': 'user', 'content': 'x'}]})
            self.assertEqual((result['reason'], result['detail']), ('unavailable', 'unavailable'))
        provider['credential'] = 'secret://elsewhere/x'
        result, _ = self.call('llm.chat', {'provider': provider, 'model': 'm', 'messages': [{'role': 'user', 'content': 'x'}]})
        self.assertEqual((result['reason'], result['detail']), ('invalid-input', 'invalid'))
        with mock.patch.dict(os.environ, {'PENTAD_TEST_KEY': ''}):
            result, _ = self.chat(key=True)
            self.assertEqual((result['reason'], result['detail']), ('unavailable', 'missing'))


class ImageTests(ProviderTestCase):
    def image_failure(self, image, reason):
        result, _ = self.chat(messages=[{'role': 'user', 'content': 'x', 'images': [image]}])
        self.failure(result, reason)
        self.assertEqual(self.fake.requests, [])

    def test_rejects_what_is_not_a_small_local_image(self):
        self.image_failure('https://example.com/a.png', 'invalid-input')
        self.image_failure('file://host/a.png', 'invalid-input')
        self.image_failure(uri(self.root), 'invalid-input')
        self.image_failure(uri(self.file('a.txt', b'plain text, not an image')), 'invalid-input')
        big = self.root / 'big.png'
        with open(big, 'wb') as handle:
            handle.write(PNG)
            handle.truncate(8 * 1024 * 1024 + 1)
        self.image_failure(uri(big), 'invalid-input')
        self.image_failure(uri(self.root / 'gone.png'), 'io')
        result, _ = self.chat(messages=[{'role': 'assistant', 'content': 'x', 'images': [uri(self.file('b.png', PNG))]}])
        self.failure(result, 'invalid-input')

    def test_signature_sniffing(self):
        self.assertEqual(llm.sniff_image(PNG[:16]), 'image/png')
        self.assertEqual(llm.sniff_image(JPEG[:16]), 'image/jpeg')
        self.assertEqual(llm.sniff_image(WEBP[:16]), 'image/webp')
        self.assertEqual(llm.sniff_image(b'GIF87a1234'), 'image/gif')
        self.assertIsNone(llm.sniff_image(b'RIFF\x00\x00\x00\x00WAVE'))
        self.assertIsNone(llm.sniff_image(b'<svg'))


class FailureTests(ProviderTestCase):
    def status(self, status, headers=(), body=None, kind='ollama'):
        path = {'ollama': '/api/chat', 'openai-compatible': '/chat/completions'}[kind]
        self.fake.json('POST', path, body if body is not None else {'error': 'nope'}, status, headers)
        result, _ = self.chat(kind)
        self.fake.requests.clear()
        return result

    def test_http_status_codes_map_to_result_reasons(self):
        self.assertIn('HTTP 401', self.failure(self.status(401), 'denied'))
        self.failure(self.status(403, kind='openai-compatible'), 'denied')
        message = self.failure(self.status(404, body={'error': "model 'm' not found"}), 'unavailable')
        self.assertIn("model 'm' not found", message)
        self.assertIn('retry after 7 s', self.failure(self.status(429, [('Retry-After', '7')]), 'busy'))
        self.failure(self.status(500), 'unavailable')
        self.failure(self.status(503, kind='openai-compatible'), 'unavailable')
        self.failure(self.status(400, body={'error': 'bad request'}), 'invalid-input')
        self.failure(self.status(302), 'io')

    def test_connection_refused_is_unavailable(self):
        holder = socket.socket()
        holder.bind(('127.0.0.1', 0))
        port = holder.getsockname()[1]
        holder.close()
        payload = {'provider': self.provider(url=f'http://127.0.0.1:{port}'), 'model': 'm', 'messages': [{'role': 'user', 'content': 'x'}]}
        self.assertIn('refused', self.failure(self.call('llm.chat', payload)[0], 'unavailable'))

    def test_malformed_or_unfinished_streams_are_invalid_responses(self):
        self.fake.stream('/api/chat', ['{"message": {"content": "a"}}\n', 'not json\n'])
        self.failure(self.chat()[0], 'invalid-response')
        self.fake.stream('/api/chat', ndjson({'message': {'content': 'a'}, 'done': False}))
        self.assertIn('completion marker', self.failure(self.chat()[0], 'invalid-response'))
        self.fake.stream('/chat/completions', sse({'choices': [{'delta': {'content': 'a'}}]}), 'text/event-stream')
        self.failure(self.chat('openai-compatible')[0], 'invalid-response')
        self.fake.stream('/v1/messages', sse(('message_start', {'type': 'message_start'}), ('x', '[1, 2]')), 'text/event-stream')
        self.failure(self.chat('anthropic')[0], 'invalid-response')
        self.fake.stream('/v1/messages', sse(('error', {'type': 'error', 'error': {'type': 'overloaded_error', 'message': 'Overloaded'}})),
                         'text/event-stream')
        self.assertIn('Overloaded', self.failure(self.chat('anthropic')[0], 'busy'))
        self.fake.stream('/api/chat', ndjson({'error': 'model runner crashed'}))
        self.assertIn('model runner crashed', self.failure(self.chat()[0], 'io'))

    def test_response_text_is_capped_at_one_mebibyte(self):
        line = json.dumps({'message': {'content': 'x' * 8192}, 'done': False}) + '\n'
        self.fake.stream('/api/chat', [line] * 140)
        self.assertIn('1 MiB', self.failure(self.chat()[0], 'io'))

    def test_request_body_is_capped_at_one_mebibyte(self):
        result, _ = self.chat(messages=[{'role': 'user', 'content': 'x' * (1024 * 1024 + 1)}])
        self.failure(result, 'invalid-input')
        self.assertEqual(self.fake.requests, [])

    def test_bad_payloads_are_invalid_input(self):
        for fields in ({'messages': []}, {'messages': [{'role': 'tool', 'content': 'x'}]}, {'messages': 'hi'},
                       {'model': ''}, {'model': 'a\nb'}, {'temperature': 3}, {'temperature': True}, {'maxTokens': 0}):
            self.failure(self.chat(**fields)[0], 'invalid-input')
        self.failure(self.call('llm.chat', {'model': 'm', 'messages': []})[0], 'invalid-input')
        self.assertEqual(self.fake.requests, [])


class SecrecyTests(ProviderTestCase):
    def echo_key(self, status):
        def route(handler, record):
            handler.send_json(status, {'error': {'message': f"Incorrect API key provided: {record['headers'].get('authorization', '')}"}})
        return route

    def test_the_key_never_leaves_in_results_or_messages(self):
        for status in (401, 404, 429, 500, 400):
            self.fake.requests.clear()
            self.fake.route('POST', '/chat/completions', self.echo_key(status))
            result, _ = self.chat('openai-compatible', key=True)  # call() asserts the key is absent
            self.assertFalse(result['ok'])
            self.assertIn('[redacted]', result['message'])
            self.assertEqual(self.fake.requests[0]['headers']['authorization'], f'Bearer {KEY}')
        self.fake.stream('/chat/completions', sse({'error': {'message': f'bad key {KEY}'}}), 'text/event-stream')
        result, _ = self.chat('openai-compatible', key=True)
        self.assertIn('[redacted]', result['message'])

    def test_a_key_that_is_not_a_header_value_is_refused_without_echo(self):
        for bad in (KEY + '\nX-Injected: 1', 'sk-ü-nonascii', '   '):
            with mock.patch.dict(os.environ, {'PENTAD_TEST_KEY': bad}):
                result, _ = self.chat('openai-compatible', key=True)
                self.assertIn(result['reason'], ('invalid-input', 'unavailable'))
                self.assertNotIn(bad.strip() or 'never', json.dumps(result))
        self.assertEqual(self.fake.requests, [])


class CancelTests(ProviderTestCase):
    def test_cancel_closes_a_slow_stream(self):
        self.fake.stream('/api/chat', ndjson({'message': {'content': 'first'}, 'done': False}), hold=True)
        ctx = Ctx(timeout=60)
        outcome = queue.Queue()

        def run():
            try:
                outcome.put(('result', self.ops['llm.chat']({'provider': self.provider(), 'model': 'm',
                                                             'messages': [{'role': 'user', 'content': 'x'}]}, ctx)))
            except core.Cancelled:
                outcome.put(('cancelled', None))
        thread = threading.Thread(target=run, daemon=True)
        thread.start()
        deadline = time.monotonic() + 5
        while not ctx.partials and time.monotonic() < deadline:
            time.sleep(0.01)
        self.assertEqual(ctx.partials, [{'text': 'first'}])
        started = time.monotonic()
        ctx.scope.cancel('cancelled')
        kind, _ = outcome.get(timeout=5)
        self.assertEqual(kind, 'cancelled')
        self.assertLess(time.monotonic() - started, 2)
        self.assertTrue(self.fake.disconnected.wait(5), 'the provider connection stayed open')

    def test_a_stream_past_the_deadline_times_out(self):
        self.fake.stream('/api/chat', [], hold=True)
        payload = {'provider': self.provider(), 'model': 'm', 'messages': [{'role': 'user', 'content': 'x'}]}
        started = time.monotonic()
        result, _ = self.call('llm.chat', payload, Ctx(timeout=0.6))
        self.failure(result, 'timeout')
        self.assertLess(time.monotonic() - started, 3)

    def test_already_cancelled_does_not_connect(self):
        ctx = Ctx()
        ctx.scope.cancel('cancelled')
        with self.assertRaises(core.Cancelled):
            self.ops['llm.chat']({'provider': self.provider(), 'model': 'm', 'messages': [{'role': 'user', 'content': 'x'}]}, ctx)
        self.assertEqual(self.fake.requests, [])


class EmbedModelsWarmTests(ProviderTestCase):
    def test_embed_per_provider(self):
        self.fake.json('POST', '/api/embed', {'embeddings': [[0.1, 0.2], [0.3, 0.123456789123]]})
        result, _ = self.call('llm.embed', {'provider': self.provider(), 'model': 'e', 'input': ['a', 'b'], 'keepAlive': '30s'})
        self.assertEqual(result['value'], {'vectors': [[0.1, 0.2], [0.3, 0.1234568]], 'dims': 2})
        self.assertEqual(self.fake.requests[-1]['body'], {'model': 'e', 'input': ['a', 'b'], 'keep_alive': '30s'})
        self.fake.json('POST', '/embeddings', {'data': [{'index': 1, 'embedding': [2.0]}, {'index': 0, 'embedding': [1.0]}]})
        result, _ = self.call('llm.embed', {'provider': self.provider('openai-compatible', key=True), 'model': 'e', 'input': ['a', 'b']})
        self.assertEqual(result['value'], {'vectors': [[1.0], [2.0]], 'dims': 1})
        self.fake.json('POST', '/models/emb:batchEmbedContents', {'embeddings': [{'values': [0.5, 0.25]}]})
        result, _ = self.call('llm.embed', {'provider': self.provider('gemini', key=True), 'model': 'emb', 'input': ['a']})
        self.assertEqual(result['value'], {'vectors': [[0.5, 0.25]], 'dims': 2})
        request = self.fake.requests[-1]
        self.assertEqual(request['headers']['x-goog-api-key'], KEY)
        self.assertEqual(request['body'], {'requests': [{'model': 'models/emb', 'content': {'parts': [{'text': 'a'}]}}]})
        count = len(self.fake.requests)
        self.failure(self.call('llm.embed', {'provider': self.provider('anthropic'), 'model': 'e', 'input': ['a']})[0], 'unsupported')
        self.failure(self.call('llm.embed', {'provider': self.provider(), 'model': 'e', 'input': []})[0], 'invalid-input')
        self.failure(self.call('llm.embed', {'provider': self.provider(), 'model': 'e', 'input': ['a'] * 65})[0], 'invalid-input')
        self.assertEqual(len(self.fake.requests), count)
        self.fake.json('POST', '/api/embed', {'embeddings': [[0.1]]})
        self.failure(self.call('llm.embed', {'provider': self.provider(), 'model': 'e', 'input': ['a', 'b']})[0], 'invalid-response')
        self.fake.json('POST', '/api/embed', {'embeddings': [[0.1], ['x']]})
        self.failure(self.call('llm.embed', {'provider': self.provider(), 'model': 'e', 'input': ['a', 'b']})[0], 'invalid-response')

    def test_ollama_models_with_capabilities_as_an_open_set(self):
        self.fake.json('GET', '/api/tags', {'models': [
            {'name': 'qwen:1b', 'size': 123, 'details': {'parameter_size': '1.0B'}},
            {'name': 'emb:1m', 'size': 9},
            {'name': 'broken:1'},
            {'name': 'bad\nname'}]})

        def show(handler, record):
            name = record['body']['model']
            if name == 'broken:1':
                handler.send_json(500, {'error': 'x'})
            else:
                handler.send_json(200, {'capabilities': ['completion', 'vision', 'future-thing'] if name == 'qwen:1b' else ['embedding']})
        self.fake.route('POST', '/api/show', show)
        result, _ = self.call('llm.models', {'provider': self.provider()})
        self.assertEqual(result['value'], {'models': [
            {'name': 'qwen:1b', 'sizeBytes': 123, 'parameterSize': '1.0B', 'capabilities': ['completion', 'vision', 'future-thing']},
            {'name': 'emb:1m', 'sizeBytes': 9, 'capabilities': ['embedding']},
            {'name': 'broken:1'}]})

    def test_models_of_other_providers(self):
        self.fake.json('GET', '/models', {'data': [{'id': 'gpt-a'}, {'id': 'gpt-b'}, 'junk']})
        result, _ = self.call('llm.models', {'provider': self.provider('openai-compatible', key=True)})
        self.assertEqual(result['value'], {'models': [{'name': 'gpt-a'}, {'name': 'gpt-b'}]})
        self.assertEqual(self.fake.requests[-1]['headers']['authorization'], f'Bearer {KEY}')
        self.fake.json('GET', '/v1/models', {'data': [{'id': 'claude-x'}]})
        result, _ = self.call('llm.models', {'provider': self.provider('anthropic', key=True)})
        self.assertEqual(result['value'], {'models': [{'name': 'claude-x'}]})
        self.assertEqual(self.fake.requests[-1]['headers']['x-api-key'], KEY)
        self.fake.json('GET', '/models', {'models': [
            {'name': 'models/gemini-x', 'supportedGenerationMethods': ['generateContent', 'countTokens']},
            {'name': 'models/emb', 'supportedGenerationMethods': ['embedContent']}]})
        result, _ = self.call('llm.models', {'provider': self.provider('gemini', key=True)})
        self.assertEqual(result['value'], {'models': [{'name': 'gemini-x', 'capabilities': ['completion']},
                                                      {'name': 'emb', 'capabilities': ['embedding']}]})
        self.assertNotIn(KEY, self.fake.requests[-1]['path'])

    def test_warm_loads_an_ollama_model_and_skips_the_others(self):
        self.fake.json('POST', '/api/chat', {'done': True, 'done_reason': 'load', 'load_duration': 1234000000})
        result, _ = self.call('llm.warm', {'provider': self.provider(), 'model': 'm', 'keepAlive': '30s'})
        self.assertEqual(result['value']['warmed'], True)
        self.assertEqual(result['value']['loadMs'], 1234)
        self.assertEqual(self.fake.requests[0]['body'], {'model': 'm', 'messages': [], 'stream': False, 'keep_alive': '30s'})
        for kind in ('openai-compatible', 'anthropic', 'gemini'):
            result, _ = self.call('llm.warm', {'provider': self.provider(kind, key=True), 'model': 'm'})
            self.assertEqual(result['value'], {'warmed': False})
        self.assertEqual(len(self.fake.requests), 1)
        self.fake.json('POST', '/api/chat', {'error': "model 'm' not found"}, 404)
        self.failure(self.call('llm.warm', {'provider': self.provider(), 'model': 'm'})[0], 'unavailable')


FAKE_TRANS = '''#!/bin/sh
printf '%s\\n' "$@" > "$FAKE_DIR/trans-args"
printf 'translated: '
cat
'''


class TranslateTests(ProviderTestCase):
    def setUp(self):
        super().setUp()
        self.bin = self.root / 'bin'
        self.bin.mkdir()
        trans = self.bin / 'trans'
        trans.write_text(FAKE_TRANS)
        trans.chmod(0o755)
        patcher = mock.patch.dict(os.environ, {'PATH': f'{self.bin}:/usr/bin:/bin', 'FAKE_DIR': str(self.root)})
        patcher.start()
        self.addCleanup(patcher.stop)

    def test_translates_through_trans(self):
        result, _ = self.call('text.translate', {'text': 'привіт', 'target': 'en', 'source': 'uk'})
        self.assertEqual(result['value'], {'text': 'translated: привіт'})
        self.assertEqual((self.root / 'trans-args').read_text().splitlines(), ['-brief', '-no-ansi', '-no-autocorrect', 'uk:en'])
        result, _ = self.call('text.translate', {'text': 'hi', 'target': 'zh-CN'})
        self.assertTrue(result['ok'])
        self.assertEqual((self.root / 'trans-args').read_text().splitlines()[-1], ':zh-CN')

    def test_bad_input_and_missing_program(self):
        for payload in ({'text': '', 'target': 'en'}, {'text': 'x', 'target': '-e'}, {'text': 'x'},
                        {'text': 'x', 'target': 'en', 'source': 'en; rm'}):
            self.failure(self.call('text.translate', payload)[0], 'invalid-input')
        with mock.patch.dict(os.environ, {'PATH': str(self.root / 'nothing')}):
            self.failure(self.call('text.translate', {'text': 'x', 'target': 'en'})[0], 'unavailable')


# --- Through the real worker loop ---------------------------------------------------

class WorkerLoopTests(ProviderTestCase):
    def start(self):
        env = dict(os.environ, HOME=str(self.root), XDG_CACHE_HOME=str(self.root / 'cache'), TMPDIR=str(self.root))
        process = subprocess.Popen([sys.executable, '-I', str(WORKER), '--serve', '--cache-root', str(self.root / 'cache')],
                                   stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=env)
        lines = queue.Queue()

        def read():
            for line in process.stdout:
                lines.put(json.loads(line))
            lines.put(None)
        threading.Thread(target=read, daemon=True).start()

        def stop():
            if process.poll() is None:
                process.kill()
            process.wait()
            for stream in (process.stdin, process.stdout, process.stderr):
                stream.close()
        self.addCleanup(stop)
        self.process, self.lines = process, lines
        hello = self.next()
        self.assertEqual(hello['type'], 'hello')
        return hello

    def send(self, message):
        self.process.stdin.write(json.dumps(message).encode() + b'\n')
        self.process.stdin.flush()

    def next(self, timeout=10):
        message = self.lines.get(timeout=timeout)
        self.assertIsNotNone(message, 'the worker exited')
        return message

    def until_result(self, ident, timeout=10):
        seen = []
        while True:
            message = self.next(timeout)
            seen.append(message)
            if message['type'] == 'result' and message['id'] == ident:
                return seen

    def finish(self):
        self.process.stdin.close()
        self.assertEqual(self.process.wait(timeout=10), 0)
        return self.process.stderr.read().decode('utf-8', 'replace')

    def test_chat_streams_partials_through_the_worker(self):
        hello = self.start()
        for op in ('llm.chat', 'llm.embed', 'llm.models', 'llm.warm', 'text.translate', 'secret.status'):
            self.assertIn(op, hello['ops'])
        self.fake.stream('/api/chat', OLLAMA_HELLO)
        self.send({'type': 'request', 'id': 3, 'op': 'llm.chat', 'payload': {
            'provider': self.provider(), 'model': 'm', 'messages': [{'role': 'user', 'content': 'Hi'}]}})
        seen = self.until_result(3)
        self.assertEqual([m['chunk'] for m in seen if m['type'] == 'partial'], [{'text': 'Hel'}, {'text': 'lo'}])
        self.assertEqual(seen[-1]['result'], {'ok': True, 'cached': False, 'value': {
            'text': 'Hello', 'usage': {'inputTokens': 5, 'outputTokens': 2}, 'finishReason': 'stop'}})
        self.finish()

    def test_cancel_and_secret_failures_through_the_worker(self):
        self.start()
        self.fake.stream('/api/chat', ndjson({'message': {'content': 'first'}, 'done': False}), hold=True)
        self.send({'type': 'request', 'id': 5, 'op': 'llm.chat', 'payload': {
            'provider': self.provider(), 'model': 'm', 'messages': [{'role': 'user', 'content': 'Hi'}]}})
        self.assertEqual(self.next()['type'], 'partial')
        self.send({'type': 'cancel', 'id': 5})
        seen = self.until_result(5, timeout=5)
        self.assertEqual(seen[-1]['result']['reason'], 'cancelled')
        self.assertTrue(self.fake.disconnected.wait(5))
        # A missing key keeps its specific cause in `detail`; the echoed key never appears.
        self.send({'type': 'request', 'id': 6, 'op': 'llm.chat', 'payload': {
            'provider': dict(self.provider(), credentialEnv='PENTAD_ABSENT_KEY'), 'model': 'm',
            'messages': [{'role': 'user', 'content': 'Hi'}]}})
        result = self.until_result(6)[-1]['result']
        self.assertEqual((result['reason'], result['detail']), ('unavailable', 'missing'))
        self.fake.route('POST', '/chat/completions', SecrecyTests.echo_key(None, 401))
        self.send({'type': 'request', 'id': 7, 'op': 'llm.chat', 'payload': {
            'provider': self.provider('openai-compatible', key=True), 'model': 'm', 'messages': [{'role': 'user', 'content': 'Hi'}]}})
        seen = self.until_result(7)
        self.assertEqual(seen[-1]['result']['reason'], 'denied')
        self.assertNotIn(KEY, json.dumps(seen))
        stderr = self.finish()
        self.assertNotIn(KEY, stderr)


if __name__ == '__main__':
    unittest.main()
