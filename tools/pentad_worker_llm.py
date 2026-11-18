"""Model and translation ops for the resident worker (pentad_worker.py loads this module and
calls `register_ops(ops)`).

Ops (payloads come from quickshell/logic/capabilities.mjs `routeCall`; spec §5 and §7):

- `llm.chat` `{provider, model, messages: [{role, content, images?: [file URI]}], temperature?,
  maxTokens?, keepAlive?, think?}` -> `{text, usage?: {inputTokens?, outputTokens?},
  finishReason?: "stop" | "length" | "content-filter" | ...}`. The text also streams as
  `partial({text: delta})`.
- `llm.embed` `{provider, model, input: [string]}` -> `{vectors: [[number]], dims}`.
- `llm.models` `{provider}` -> `{models: [{name, sizeBytes?, parameterSize?, capabilities?}]}`.
  Ollama: /api/tags plus /api/show per model (capabilities are an open set of strings, as
  Ollama reports them). OpenAI-compatible: GET /models. Anthropic: GET /v1/models. Gemini:
  GET /models, with `supportedGenerationMethods` mapped to "completion" / "embedding".
- `llm.warm` `{provider, model, keepAlive?}` -> Ollama loads the model with an empty chat
  (`messages: []`) and answers `{warmed: true, loadMs}`; other kinds answer `{warmed: false}`
  without any request.
- `text.translate` `{text, target, source?}` -> `{text}` through translate-shell (`trans`), the
  same path as the sidebar helper (`pentad_file_tool.translate`).

`provider` is `{kind, baseUrl, credential, credentialEnv}` with kind `ollama`,
`openai-compatible`, `anthropic` or `gemini`. The worker never receives a key value: it resolves
`credential` (secret://) or `credentialEnv` itself through pentad_secrets. The key is sent only
as the provider's auth header (`Authorization: Bearer`, `x-api-key`, `x-goog-api-key`; never in a
URL) and is scrubbed from every message this module returns.

Rules: the endpoint is re-checked exactly like `validateEndpoint` in quickshell/logic/models.mjs
(https anywhere, http only to loopback; an insecure one is `denied`). Request bodies hold at most
1 MiB besides the encoded images; images are `file://` URIs of regular files of at most 8 MiB,
PNG, JPEG, WebP or GIF by signature. Model text is capped at 1 MiB (`io`). Connect timeout 8 s;
the whole call ends at the request's deadline, at most 600 s. Cancel shuts the socket. HTTP
401/403 -> `denied`, 404 -> `unavailable`, 429 -> `busy` (with Retry-After), 5xx and unreachable
hosts -> `unavailable`, 400/413/422 -> `invalid-input`, a malformed stream -> `invalid-response`.
Connections go straight to the endpoint (no proxy, no redirects). Model output is data: it is
returned, never executed or interpreted.
"""
import base64
import http.client
import json
import os
import re
import socket
import ssl
import stat
import sys
import threading
import time
from urllib.parse import quote

_HERE = os.path.dirname(os.path.abspath(__file__))
if _HERE not in sys.path:
    sys.path.append(_HERE)

import pentad_file_tool as file_tool  # noqa: E402
import pentad_secrets as secrets  # noqa: E402
from pentad_tool_core import MAX_TEXT, Cancelled, ToolError, file_path  # noqa: E402

KINDS = ('ollama', 'openai-compatible', 'anthropic', 'gemini')
CONNECT_TIMEOUT_S = 8.0
MAX_CALL_S = 600.0
MAX_BODY = 1024 * 1024               # request body, images excluded
MAX_RESPONSE_TEXT = 1024 * 1024      # model text, UTF-8 bytes
MAX_STREAM_BYTES = 16 * 1024 * 1024  # raw stream bytes (JSON framing, thinking)
MAX_LINE = 1024 * 1024               # one NDJSON line or SSE event
MAX_ERROR_BODY = 64 * 1024
MAX_JSON_BODY = 32 * 1024 * 1024     # non-streamed answers (embeddings, model lists)
MAX_IMAGE_BYTES = 8 * 1024 * 1024
MAX_IMAGES = 16
MAX_IMAGE_TOTAL = 32 * 1024 * 1024
MAX_MESSAGES = 100
MAX_EMBED_ITEMS = 64
MAX_MODELS = 200
MAX_MODEL_NAME = 200
ANTHROPIC_VERSION = '2023-06-01'
ANTHROPIC_MAX_TOKENS = 1024
USER_AGENT = 'Pentad-worker/1'

_ENDPOINT = re.compile(r'([Hh][Tt][Tt][Pp][Ss]?)://(\[[0-9A-Fa-f:.]+\]|[A-Za-z0-9.-]+)(?::([0-9]{1,5}))?(/[^?#\s]*)?')
_LOOPBACK_V4 = re.compile(r'127\.([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})')
_ENV_NAME = re.compile(r'[A-Za-z_][A-Za-z0-9_]{0,127}')
_KEY = re.compile(r'[\x21-\x7e]{1,4096}')
_KEEP_ALIVE = re.compile(r'-?[0-9]+|-?(?:[0-9]+(?:\.[0-9]+)?(?:ns|us|ms|s|m|h))+')
_LANGUAGE = re.compile(r'[a-z]{2,3}(-[A-Za-z]{2,4})?')
_CONTROL = re.compile(r'[\x00-\x1f\x7f]')
_ROLES = ('system', 'user', 'assistant')
_FINISH = {'stop': 'stop', 'end_turn': 'stop', 'stop_sequence': 'stop', 'STOP': 'stop',
           'length': 'length', 'max_tokens': 'length', 'MAX_TOKENS': 'length',
           'content_filter': 'content-filter', 'refusal': 'content-filter', 'SAFETY': 'content-filter',
           'RECITATION': 'content-filter', 'BLOCKLIST': 'content-filter', 'PROHIBITED_CONTENT': 'content-filter',
           'SPII': 'content-filter', 'tool_calls': 'tool-calls', 'tool_use': 'tool-calls'}


class LlmError(Exception):
    """A failure with a Result reason. The message is built here, never from a key."""

    def __init__(self, reason, message, detail=''):
        super().__init__(message)
        self.reason = reason
        self.message = message
        self.detail = detail


# --- Endpoint rule (mirrors validateEndpoint in quickshell/logic/models.mjs) ----

def _loopback_quad(host):
    """127.0.0.0/8 as a real dotted quad: "127.300.0.1" is a DNS name and may resolve anywhere."""
    match = _LOOPBACK_V4.fullmatch(host)
    return bool(match) and all(int(octet) <= 255 for octet in match.groups())


def endpoint_parts(url):
    """`{protocol, host, port, path, loopback, url}` or None when `url` is not a plain http(s) URL.
    Credentials, a query or a fragment in the URL are refused: keys travel in headers only."""
    if not isinstance(url, str):
        return None
    text = url.strip()
    if not text or len(text) > 2048:
        return None
    match = _ENDPOINT.fullmatch(text)
    if not match:
        return None
    port = int(match.group(3)) if match.group(3) else 0
    if match.group(3) and (port == 0 or port > 65535):
        return None
    host = match.group(2).lower()
    if host.startswith('['):
        host = host[1:]
    if host.endswith(']'):
        host = host[:-1]
    # A full dotted quad only: "127.example.com" is a public name, not loopback.
    loopback = host in ('localhost', '::1') or _loopback_quad(host)
    path = (match.group(4) or '').rstrip('/')
    protocol = match.group(1).lower()
    return {'protocol': protocol, 'host': host, 'port': port or (443 if protocol == 'https' else 80),
            'path': path, 'loopback': loopback,
            'url': f'{protocol}://{match.group(2).lower()}{f":{port}" if match.group(3) else ""}{path}'}


def validate_endpoint(url):
    parts = endpoint_parts(url)
    if parts is None:
        return {'ok': False, 'reason': 'invalid-url'}
    if parts['protocol'] != 'https' and not parts['loopback']:
        return {'ok': False, 'reason': 'insecure-endpoint'}
    return {'ok': True, 'url': parts['url']}


# --- Payload checks -----------------------------------------------------------

class _Call:
    """State of one op call: the resolved key, so every outgoing message can be scrubbed."""

    def __init__(self):
        self.key = None

    def redact(self, text):
        text = str(text or '')
        if self.key:
            text = text.replace(self.key, '[redacted]')
        return text


class _Provider:
    def __init__(self, kind, endpoint, key):
        self.kind = kind
        self.endpoint = endpoint
        self.key = key


def _clean(text, limit=200):
    """Provider-supplied text for a message: one line, no control characters, bounded."""
    return _CONTROL.sub(' ', str(text)).strip()[:limit]


def _provider(payload, call, resolve_key=True):
    source = payload.get('provider')
    if not isinstance(source, dict):
        raise LlmError('invalid-input', 'provider must be an object')
    kind = source.get('kind')
    if kind not in KINDS:
        raise LlmError('unsupported', f'Unknown provider kind {_clean(kind, 40)!r}')
    checked = validate_endpoint(source.get('baseUrl'))
    if not checked['ok']:
        if checked['reason'] == 'insecure-endpoint':
            raise LlmError('denied', 'The provider endpoint must use https (plain http is allowed only to this machine)')
        raise LlmError('invalid-input', 'The provider endpoint is not a valid http(s) URL')
    endpoint = endpoint_parts(checked['url'])
    for name in ('credential', 'credentialEnv'):
        if source.get(name) is not None and not isinstance(source.get(name), str):
            raise LlmError('invalid-input', f'provider.{name} must be a string')
    env = (source.get('credentialEnv') or '').strip()
    if env and not _ENV_NAME.fullmatch(env):
        raise LlmError('invalid-input', 'provider.credentialEnv must be an environment variable name')
    key = None
    if resolve_key:
        try:
            key = secrets.resolve({'credential': source.get('credential') or '', 'credentialEnv': env})
        except secrets.SecretError as error:
            reason = secrets.RESULT_REASON.get(error.reason, 'io')
            raise LlmError(reason, f'The provider key is not usable: {error}', error.reason) from None
        if key is not None:
            key = key.strip()
            call.key = key
            # A key that cannot be a header value would make http.client echo it in an error.
            if not _KEY.fullmatch(key):
                raise LlmError('invalid-input', 'The stored provider key contains characters that cannot be sent', 'invalid')
    return _Provider(kind, endpoint, key)


def _model(payload):
    model = payload.get('model')
    if not isinstance(model, str) or not model.strip() or len(model.strip()) > MAX_MODEL_NAME or _CONTROL.search(model):
        raise LlmError('invalid-input', 'model must be a non-empty model name')
    return model.strip()


def _keep_alive(payload):
    value = payload.get('keepAlive')
    if value is None or value == '':
        return None
    if not isinstance(value, str) or len(value) > 32 or not _KEEP_ALIVE.fullmatch(value):
        raise LlmError('invalid-input', 'keepAlive must be a duration such as "5m", "30s" or "-1"')
    return value


_SIGNATURES = ((b'\x89PNG\r\n\x1a\n', 'image/png'), (b'\xff\xd8\xff', 'image/jpeg'),
               (b'GIF87a', 'image/gif'), (b'GIF89a', 'image/gif'))


def sniff_image(head):
    for signature, mime in _SIGNATURES:
        if head.startswith(signature):
            return mime
    if len(head) >= 12 and head[:4] == b'RIFF' and head[8:12] == b'WEBP':
        return 'image/webp'
    return None


def load_image(uri):
    """(mime, base64 text, raw size) of a local image file."""
    if not isinstance(uri, str) or not uri.startswith('file://') or len(uri) > 4096:
        raise LlmError('invalid-input', 'Images must be local file:// URIs')
    try:
        path = file_path(uri)
    except ToolError:
        raise LlmError('invalid-input', 'Images must be local file:// URIs') from None
    try:
        handle = os.open(path, os.O_RDONLY | os.O_NONBLOCK | os.O_CLOEXEC)
    except FileNotFoundError:
        raise LlmError('io', f'{path.name} no longer exists') from None
    except OSError as error:
        raise LlmError('io', f'{path.name}: {error.strerror or "cannot be read"}') from None
    try:
        info = os.fstat(handle)
        if not stat.S_ISREG(info.st_mode):
            raise LlmError('invalid-input', f'{path.name} is not a regular file')
        if info.st_size > MAX_IMAGE_BYTES:
            raise LlmError('invalid-input', f'{path.name} is larger than {MAX_IMAGE_BYTES // (1024 * 1024)} MiB')
        chunks = []
        total = 0
        while True:
            chunk = os.read(handle, 1024 * 1024)
            if not chunk:
                break
            total += len(chunk)
            if total > MAX_IMAGE_BYTES:
                raise LlmError('invalid-input', f'{path.name} is larger than {MAX_IMAGE_BYTES // (1024 * 1024)} MiB')
            chunks.append(chunk)
    finally:
        os.close(handle)
    data = b''.join(chunks)
    mime = sniff_image(data[:16])
    if mime is None:
        raise LlmError('invalid-input', f'{path.name} is not a PNG, JPEG, WebP or GIF image')
    return mime, base64.b64encode(data).decode('ascii'), len(data)


def _messages(payload, ctx):
    """[{role, content, images: [(mime, base64)]}] with the images read from disk."""
    items = payload.get('messages')
    if not isinstance(items, list) or not items or len(items) > MAX_MESSAGES:
        raise LlmError('invalid-input', f'messages must contain 1 to {MAX_MESSAGES} entries')
    result = []
    count = 0
    total = 0
    for index, item in enumerate(items):
        if not isinstance(item, dict) or item.get('role') not in _ROLES or not isinstance(item.get('content'), str):
            raise LlmError('invalid-input', f'messages[{index}] needs a role (system, user, assistant) and string content')
        images = item.get('images') or []
        if not isinstance(images, list):
            raise LlmError('invalid-input', f'messages[{index}].images must be a list of file URIs')
        if images and item['role'] != 'user':
            raise LlmError('invalid-input', 'Images are only allowed on user messages')
        loaded = []
        for uri in images:
            count += 1
            if count > MAX_IMAGES:
                raise LlmError('invalid-input', f'At most {MAX_IMAGES} images per request')
            ctx.check()
            mime, data, size = load_image(uri)
            total += size
            if total > MAX_IMAGE_TOTAL:
                raise LlmError('invalid-input', f'The images exceed {MAX_IMAGE_TOTAL // (1024 * 1024)} MiB in total')
            loaded.append((mime, data))
        result.append({'role': item['role'], 'content': item['content'], 'images': loaded})
    return result


def _sampling(payload):
    temperature = payload.get('temperature')
    if temperature is not None and (isinstance(temperature, bool) or not isinstance(temperature, (int, float))
                                    or not 0 <= temperature <= 2):
        raise LlmError('invalid-input', 'temperature must be between 0 and 2')
    max_tokens = payload.get('maxTokens')
    if max_tokens is not None and (isinstance(max_tokens, bool) or not isinstance(max_tokens, int)
                                   or not 1 <= max_tokens <= 1_000_000):
        raise LlmError('invalid-input', 'maxTokens must be a positive integer')
    return temperature, max_tokens


def _body(document, image_bytes=0):
    data = json.dumps(document, ensure_ascii=False, separators=(',', ':')).encode('utf-8')
    if len(data) - image_bytes > MAX_BODY:
        raise LlmError('invalid-input', 'The request is larger than 1 MiB')
    return data


# --- HTTP -----------------------------------------------------------------------

_tls_context = None
_tls_lock = threading.Lock()


def _tls():
    global _tls_context
    with _tls_lock:
        if _tls_context is None:
            _tls_context = ssl.create_default_context()
        return _tls_context


class _Http:
    """The HTTP connections of one op call. Cancel shuts the current socket down, so a read
    blocked in another thread returns at once; every read is bounded by the call's deadline."""

    def __init__(self, ctx, call):
        self.ctx = ctx
        self.call = call
        self.deadline = time.monotonic() + min(MAX_CALL_S, ctx.remaining())
        self._lock = threading.Lock()
        self._sock = None
        ctx.on_cancel(self.abort)

    def abort(self):
        with self._lock:
            sock = self._sock
        if sock is not None:
            try:
                # The plain-socket shutdown: SSLSocket.shutdown would drop its SSL object under a
                # reader in another thread.
                socket.socket.shutdown(sock, socket.SHUT_RDWR)
            except (OSError, ValueError):
                pass

    def remaining(self):
        return self.deadline - time.monotonic()

    def arm(self):
        """Bound the next socket operation by the deadline; raise once it has passed."""
        self.ctx.check()
        left = self.remaining()
        if left <= 0:
            raise LlmError('timeout', f'The provider did not finish within {min(MAX_CALL_S, self.ctx.timeout_s):g} s')
        with self._lock:
            sock = self._sock
        if sock is not None:
            try:
                sock.settimeout(left)
            except OSError:
                pass

    def broken(self, error, during):
        """Turn a socket error into a Result failure (Cancelled when the call was cancelled)."""
        self.ctx.check()
        if isinstance(error, LlmError):
            return error
        if isinstance(error, (socket.timeout, TimeoutError)) and self.remaining() <= 0.05:
            return LlmError('timeout', f'The provider did not finish within {min(MAX_CALL_S, self.ctx.timeout_s):g} s')
        return LlmError('io', f'The connection to the provider broke while {during}')

    def open(self, endpoint, method, path, body=None, headers=None):
        self.ctx.check()
        if self.remaining() <= 0:
            raise LlmError('timeout', 'No time is left for the request')
        label = endpoint['host']
        timeout = max(0.05, min(CONNECT_TIMEOUT_S, self.remaining()))
        if endpoint['protocol'] == 'https':
            connection = http.client.HTTPSConnection(endpoint['host'], endpoint['port'], timeout=timeout, context=_tls())
        else:
            connection = http.client.HTTPConnection(endpoint['host'], endpoint['port'], timeout=timeout)
        try:
            connection.connect()
        except (socket.timeout, TimeoutError):
            self.ctx.check()
            raise LlmError('unavailable', f'{label} did not answer within {CONNECT_TIMEOUT_S:g} s') from None
        except ConnectionRefusedError:
            self.ctx.check()
            raise LlmError('unavailable', f'{label} refused the connection; is the service running?') from None
        except ssl.SSLCertVerificationError:
            self.ctx.check()
            raise LlmError('unavailable', f'The TLS certificate of {label} could not be verified') from None
        except ssl.SSLError:
            self.ctx.check()
            raise LlmError('unavailable', f'The TLS handshake with {label} failed') from None
        except socket.gaierror:
            self.ctx.check()
            raise LlmError('unavailable', f'{label} could not be resolved') from None
        except OSError:
            self.ctx.check()
            raise LlmError('unavailable', f'{label} could not be reached') from None
        with self._lock:
            self._sock = connection.sock
        if self.ctx.cancelled():
            connection.close()
            self.ctx.check()
        all_headers = {'User-Agent': USER_AGENT, 'Accept-Encoding': 'identity'}
        if body is not None:
            all_headers['Content-Type'] = 'application/json'
        all_headers.update(headers or {})
        try:
            self.arm()
            connection.request(method, path, body=body, headers=all_headers)
            self.arm()
            response = connection.getresponse()
        except (OSError, http.client.HTTPException) as error:
            connection.close()
            raise self.broken(error, 'sending the request') from None
        except BaseException:
            connection.close()
            raise
        return _Response(self, connection, response)


class _Response:
    def __init__(self, owner, connection, response):
        self.owner = owner
        self.connection = connection
        self.response = response
        self.status = response.status
        self.received = 0

    def header(self, name):
        return self.response.getheader(name) or ''

    def close(self):
        try:
            self.response.close()
        except Exception:
            pass
        self.connection.close()

    def _count(self, size):
        self.received += size
        if self.received > MAX_STREAM_BYTES:
            raise LlmError('io', f'The provider sent more than {MAX_STREAM_BYTES // (1024 * 1024)} MiB')

    def lines(self):
        """Yield each line without its line break."""
        while True:
            try:
                self.owner.arm()
                line = self.response.readline(MAX_LINE + 1)
            except (OSError, http.client.HTTPException, ValueError, AttributeError) as error:
                raise self.owner.broken(error, 'reading the answer') from None
            if not line:
                self.owner.ctx.check()
                return
            self._count(len(line))
            if len(line) > MAX_LINE and not line.endswith(b'\n'):
                raise LlmError('invalid-response', 'The provider sent a line larger than 1 MiB')
            yield line.rstrip(b'\r\n')

    def read(self, limit, what='answer'):
        chunks = []
        total = 0
        while True:
            try:
                self.owner.arm()
                chunk = self.response.read1(min(65536, limit + 1 - total)) if total <= limit else b''
            except (OSError, http.client.HTTPException, ValueError, AttributeError) as error:
                raise self.owner.broken(error, 'reading the answer') from None
            if not chunk:
                self.owner.ctx.check()
                break
            total += len(chunk)
            if total > limit:
                raise LlmError('io', f'The provider {what} is larger than {limit // (1024 * 1024) or 1} MiB')
            chunks.append(chunk)
        return b''.join(chunks)

    def json(self, limit=MAX_JSON_BODY):
        try:
            return json.loads(self.read(limit))
        except (ValueError, RecursionError):
            raise LlmError('invalid-response', 'The provider answer is not valid JSON') from None

    def error_message(self):
        try:
            body = self.read(MAX_ERROR_BODY, 'error')
        except LlmError:
            return ''
        try:
            document = json.loads(body)
        except (ValueError, RecursionError):
            return _clean(body.decode('utf-8', 'replace'))
        error = document.get('error') if isinstance(document, dict) else None
        if isinstance(error, dict):
            error = error.get('message') or error.get('type')
        if not isinstance(error, str) and isinstance(document, dict):
            error = document.get('message') or document.get('detail')
        return _clean(error) if isinstance(error, str) else ''

    def check(self):
        """Raise the Result failure for a non-2xx status."""
        status = self.status
        if 200 <= status < 300:
            return
        detail = self.error_message()
        suffix = f': {detail}' if detail else ''
        if status in (401, 403):
            raise LlmError('denied', f'The provider refused the request (HTTP {status}); check the key{suffix}')
        if status == 404:
            raise LlmError('unavailable', f'The model or endpoint was not found (HTTP 404){suffix}')
        if status == 429:
            retry = _clean(self.header('Retry-After'), 40)
            after = f'; retry after {retry} s' if retry.isdigit() else f'; retry after {retry}' if retry else ''
            raise LlmError('busy', f'The provider is rate limiting requests (HTTP 429){after}{suffix}')
        if status >= 500:
            raise LlmError('unavailable', f'The provider failed (HTTP {status}){suffix}')
        if status in (400, 413, 422):
            raise LlmError('invalid-input', f'The provider rejected the request (HTTP {status}){suffix}')
        raise LlmError('io', f'The provider answered HTTP {status}{suffix}')


def _json_line(data):
    try:
        value = json.loads(data)
    except (ValueError, RecursionError):
        raise LlmError('invalid-response', 'The provider stream is malformed') from None
    if not isinstance(value, dict):
        raise LlmError('invalid-response', 'The provider stream is malformed')
    return value


def _sse(response):
    """Yield (event name, data bytes) per server-sent event."""
    event = ''
    data = []
    size = 0
    for line in response.lines():
        if not line:
            if data:
                yield event, b'\n'.join(data)
            event, data, size = '', [], 0
            continue
        if line.startswith(b':'):
            continue
        field, _, value = line.partition(b':')
        if value.startswith(b' '):
            value = value[1:]
        if field == b'data':
            size += len(value) + 1
            if size > MAX_LINE:
                raise LlmError('invalid-response', 'The provider sent an event larger than 1 MiB')
            data.append(value)
        elif field == b'event':
            event = value.decode('utf-8', 'replace')
    if data:
        yield event, b'\n'.join(data)


def _stream_error(error):
    if isinstance(error, dict):
        kind = error.get('type') or error.get('status') or ''
        message = error.get('message') or kind
    else:
        kind, message = '', error
    reason = 'busy' if kind in ('overloaded_error', 'rate_limit_error', 'RESOURCE_EXHAUSTED') else 'io'
    text = _clean(message) if isinstance(message, str) else ''
    return LlmError(reason, f'The provider reported an error{": " + text if text else ""}')


# --- Chat -----------------------------------------------------------------------

class _Output:
    """Model text: streamed as partials, capped at MAX_RESPONSE_TEXT."""

    def __init__(self, ctx):
        self.ctx = ctx
        self.parts = []
        self.size = 0
        self.finish_reason = ''
        self.usage = {}

    def add(self, text):
        if not isinstance(text, str) or not text:
            return
        self.size += len(text.encode('utf-8'))
        if self.size > MAX_RESPONSE_TEXT:
            raise LlmError('io', 'The model response is larger than 1 MiB')
        self.parts.append(text)
        self.ctx.partial({'text': text})

    def finish(self, reason):
        if isinstance(reason, str) and reason:
            self.finish_reason = _FINISH.get(reason, _clean(reason, 32).lower())

    def count(self, name, value):
        if isinstance(value, int) and not isinstance(value, bool) and value >= 0:
            self.usage[name] = value

    def value(self):
        result = {'text': ''.join(self.parts)}
        if self.usage:
            result['usage'] = dict(self.usage)
        if self.finish_reason:
            result['finishReason'] = self.finish_reason
        return result


def _ollama_chat(provider, model, messages, payload, think):
    temperature, max_tokens = _sampling(payload)
    keep_alive = _keep_alive(payload)
    image_bytes = 0
    items = []
    for message in messages:
        item = {'role': message['role'], 'content': message['content']}
        if message['images']:
            item['images'] = [data for _, data in message['images']]
            image_bytes += sum(len(data) for data in item['images'])
        items.append(item)
    document = {'model': model, 'messages': items, 'stream': True}
    if think is not None:
        document['think'] = think
    options = {}
    if temperature is not None:
        options['temperature'] = temperature
    if max_tokens is not None:
        options['num_predict'] = max_tokens
    if options:
        document['options'] = options
    if keep_alive is not None:
        document['keep_alive'] = keep_alive
    headers = {'Accept': 'application/x-ndjson'}
    if provider.key:
        headers['Authorization'] = f'Bearer {provider.key}'
    return provider.endpoint['path'] + '/api/chat', _body(document, image_bytes), headers


def _read_ollama(response, output):
    for line in response.lines():
        if not line.strip():
            continue
        event = _json_line(line)
        if event.get('error'):
            raise _stream_error(event['error'])
        message = event.get('message')
        if isinstance(message, dict):
            output.add(message.get('content'))
        if event.get('done') is True:
            output.finish(event.get('done_reason') or 'stop')
            output.count('inputTokens', event.get('prompt_eval_count'))
            output.count('outputTokens', event.get('eval_count'))
            return
    raise LlmError('invalid-response', 'The provider stream ended without a completion marker')


def _openai_chat(provider, model, messages, payload):
    temperature, max_tokens = _sampling(payload)
    image_bytes = 0
    items = []
    for message in messages:
        if message['images']:
            content = [{'type': 'text', 'text': message['content']}] if message['content'] else []
            for mime, data in message['images']:
                content.append({'type': 'image_url', 'image_url': {'url': f'data:{mime};base64,{data}'}})
                image_bytes += len(data)
        else:
            content = message['content']
        items.append({'role': message['role'], 'content': content})
    document = {'model': model, 'messages': items, 'stream': True}
    if temperature is not None:
        document['temperature'] = temperature
    if max_tokens is not None:
        document['max_tokens'] = max_tokens
    headers = {'Accept': 'text/event-stream'}
    if provider.key:
        headers['Authorization'] = f'Bearer {provider.key}'
    return provider.endpoint['path'] + '/chat/completions', _body(document, image_bytes), headers


def _read_openai(response, output):
    for _, data in _sse(response):
        if data.strip() == b'[DONE]':
            output.finish(output.finish_reason or 'stop')
            return
        event = _json_line(data)
        if event.get('error'):
            raise _stream_error(event['error'])
        choices = event.get('choices')
        choice = choices[0] if isinstance(choices, list) and choices and isinstance(choices[0], dict) else {}
        delta = choice.get('delta')
        if isinstance(delta, dict):
            output.add(delta.get('content'))
        if choice.get('finish_reason'):
            output.finish(choice['finish_reason'])
        usage = event.get('usage')
        if isinstance(usage, dict):
            output.count('inputTokens', usage.get('prompt_tokens'))
            output.count('outputTokens', usage.get('completion_tokens'))
    if not output.finish_reason:
        raise LlmError('invalid-response', 'The provider stream ended without a completion marker')


def _anthropic_chat(provider, model, messages, payload):
    temperature, max_tokens = _sampling(payload)
    image_bytes = 0
    system = []
    items = []
    for message in messages:
        if message['role'] == 'system':
            if message['content']:
                system.append(message['content'])
            continue
        if message['images']:
            content = []
            for mime, data in message['images']:
                content.append({'type': 'image', 'source': {'type': 'base64', 'media_type': mime, 'data': data}})
                image_bytes += len(data)
            if message['content']:
                content.append({'type': 'text', 'text': message['content']})
        else:
            content = message['content']
        items.append({'role': message['role'], 'content': content})
    if not items:
        raise LlmError('invalid-input', 'Anthropic needs at least one user message')
    document = {'model': model, 'max_tokens': max_tokens or ANTHROPIC_MAX_TOKENS, 'messages': items, 'stream': True}
    if system:
        document['system'] = '\n\n'.join(system)
    if temperature is not None:
        document['temperature'] = min(1, temperature)
    headers = {'Accept': 'text/event-stream', 'anthropic-version': ANTHROPIC_VERSION}
    if provider.key:
        headers['x-api-key'] = provider.key
    return provider.endpoint['path'] + '/v1/messages', _body(document, image_bytes), headers


def _read_anthropic(response, output):
    for _, data in _sse(response):
        event = _json_line(data)
        kind = event.get('type')
        if kind == 'error':
            raise _stream_error(event.get('error'))
        if kind == 'message_start':
            message = event.get('message')
            usage = message.get('usage') if isinstance(message, dict) else None
            if isinstance(usage, dict):
                output.count('inputTokens', usage.get('input_tokens'))
        elif kind == 'content_block_delta':
            delta = event.get('delta')
            if isinstance(delta, dict) and delta.get('type') == 'text_delta':
                output.add(delta.get('text'))
        elif kind == 'message_delta':
            delta = event.get('delta')
            if isinstance(delta, dict) and delta.get('stop_reason'):
                output.finish(delta['stop_reason'])
            usage = event.get('usage')
            if isinstance(usage, dict):
                output.count('outputTokens', usage.get('output_tokens'))
        elif kind == 'message_stop':
            output.finish(output.finish_reason or 'stop')
            return
    raise LlmError('invalid-response', 'The provider stream ended without a completion marker')


def _gemini_model(model):
    name = model[len('models/'):] if model.startswith('models/') else model
    return quote(name, safe='-._~')


def _gemini_chat(provider, model, messages, payload):
    temperature, max_tokens = _sampling(payload)
    image_bytes = 0
    system = []
    contents = []
    for message in messages:
        if message['role'] == 'system':
            if message['content']:
                system.append(message['content'])
            continue
        parts = []
        if message['content'] or not message['images']:
            parts.append({'text': message['content']})
        for mime, data in message['images']:
            parts.append({'inline_data': {'mime_type': mime, 'data': data}})
            image_bytes += len(data)
        contents.append({'role': 'model' if message['role'] == 'assistant' else 'user', 'parts': parts})
    if not contents:
        raise LlmError('invalid-input', 'Gemini needs at least one user message')
    document = {'contents': contents}
    if system:
        document['systemInstruction'] = {'parts': [{'text': '\n\n'.join(system)}]}
    config = {}
    if temperature is not None:
        config['temperature'] = temperature
    if max_tokens is not None:
        config['maxOutputTokens'] = max_tokens
    if config:
        document['generationConfig'] = config
    headers = {'Accept': 'text/event-stream'}
    if provider.key:
        headers['x-goog-api-key'] = provider.key
    path = f"{provider.endpoint['path']}/models/{_gemini_model(model)}:streamGenerateContent?alt=sse"
    return path, _body(document, image_bytes), headers


def _read_gemini(response, output):
    for _, data in _sse(response):
        event = _json_line(data)
        if event.get('error'):
            raise _stream_error(event['error'])
        feedback = event.get('promptFeedback')
        if isinstance(feedback, dict) and feedback.get('blockReason'):
            raise LlmError('io', f"The provider blocked the prompt ({_clean(feedback['blockReason'], 40)})")
        candidates = event.get('candidates')
        candidate = candidates[0] if isinstance(candidates, list) and candidates and isinstance(candidates[0], dict) else {}
        content = candidate.get('content')
        parts = content.get('parts') if isinstance(content, dict) else None
        for part in parts if isinstance(parts, list) else []:
            if isinstance(part, dict) and not part.get('thought'):
                output.add(part.get('text'))
        if candidate.get('finishReason'):
            output.finish(candidate['finishReason'])
        usage = event.get('usageMetadata')
        if isinstance(usage, dict):
            output.count('inputTokens', usage.get('promptTokenCount'))
            output.count('outputTokens', usage.get('candidatesTokenCount'))
    if not output.finish_reason:
        raise LlmError('invalid-response', 'The provider stream ended without a completion marker')


_READERS = {'ollama': _read_ollama, 'openai-compatible': _read_openai, 'anthropic': _read_anthropic,
            'gemini': _read_gemini}


def op_chat(payload, ctx, call):
    provider = _provider(payload, call)
    model = _model(payload)
    messages = _messages(payload, ctx)
    if payload.get('think') is not None and not isinstance(payload.get('think'), bool):
        raise LlmError('invalid-input', 'think must be a boolean')
    think = payload.get('think') is True
    http_ = _Http(ctx, call)
    output = _Output(ctx)
    if provider.kind == 'ollama':
        path, body, headers = _ollama_chat(provider, model, messages, payload, think)
    elif provider.kind == 'openai-compatible':
        path, body, headers = _openai_chat(provider, model, messages, payload)
    elif provider.kind == 'anthropic':
        path, body, headers = _anthropic_chat(provider, model, messages, payload)
    else:
        path, body, headers = _gemini_chat(provider, model, messages, payload)
    response = http_.open(provider.endpoint, 'POST', path, body, headers)
    try:
        if provider.kind == 'ollama' and not think and response.status == 400:
            # Older Ollama builds reject `think` for models without a thinking mode; retry once without it.
            message = response.error_message()
            response.close()
            if 'think' not in message.lower():
                raise LlmError('invalid-input', f'The provider rejected the request (HTTP 400){": " + message if message else ""}')
            path, body, headers = _ollama_chat(provider, model, messages, payload, None)
            response = http_.open(provider.endpoint, 'POST', path, body, headers)
        response.check()
        _READERS[provider.kind](response, output)
    finally:
        response.close()
    return output.value()


# --- Embeddings, model lists, warm-up -------------------------------------------------

def _round(value):
    return float(f'{value:.7g}')


def _vectors(raw, count):
    if not isinstance(raw, list) or len(raw) != count:
        raise LlmError('invalid-response', 'The provider returned the wrong number of vectors')
    vectors = []
    dims = None
    for vector in raw:
        if not isinstance(vector, list) or not vector or any(
                isinstance(x, bool) or not isinstance(x, (int, float)) for x in vector):
            raise LlmError('invalid-response', 'The provider returned an invalid vector')
        if dims is not None and len(vector) != dims:
            raise LlmError('invalid-response', 'The provider returned vectors of different sizes')
        dims = len(vector)
        vectors.append([_round(x) for x in vector])
    return {'vectors': vectors, 'dims': dims}


def op_embed(payload, ctx, call):
    provider = _provider(payload, call, resolve_key=False)
    if provider.kind == 'anthropic':
        raise LlmError('unsupported', 'Anthropic does not offer embeddings')
    model = _model(payload)
    items = payload.get('input')
    if not isinstance(items, list) or not items or len(items) > MAX_EMBED_ITEMS or any(
            not isinstance(item, str) or not item for item in items):
        raise LlmError('invalid-input', f'input must contain 1 to {MAX_EMBED_ITEMS} non-empty strings')
    provider = _provider(payload, call)
    path = provider.endpoint['path']
    headers = {'Accept': 'application/json'}
    if provider.kind == 'ollama':
        document = {'model': model, 'input': items}
        keep_alive = _keep_alive(payload)
        if keep_alive is not None:
            document['keep_alive'] = keep_alive
        path += '/api/embed'
        if provider.key:
            headers['Authorization'] = f'Bearer {provider.key}'
    elif provider.kind == 'openai-compatible':
        document = {'model': model, 'input': items}
        path += '/embeddings'
        if provider.key:
            headers['Authorization'] = f'Bearer {provider.key}'
    else:
        name = _gemini_model(model)
        document = {'requests': [{'model': f'models/{name}', 'content': {'parts': [{'text': item}]}} for item in items]}
        path += f'/models/{name}:batchEmbedContents'
        if provider.key:
            headers['x-goog-api-key'] = provider.key
    response = _Http(ctx, call).open(provider.endpoint, 'POST', path, _body(document), headers)
    try:
        response.check()
        answer = response.json()
    finally:
        response.close()
    if not isinstance(answer, dict):
        raise LlmError('invalid-response', 'The provider answer is not an object')
    if provider.kind == 'ollama':
        raw = answer.get('embeddings')
    elif provider.kind == 'openai-compatible':
        data = answer.get('data')
        if not isinstance(data, list) or not all(isinstance(item, dict) for item in data):
            raise LlmError('invalid-response', 'The provider answer has no embeddings')
        raw = [item.get('embedding') for item in sorted(data, key=lambda item: item.get('index') if isinstance(item.get('index'), int) else 0)]
    else:
        data = answer.get('embeddings')
        raw = [item.get('values') if isinstance(item, dict) else None for item in data] if isinstance(data, list) else None
    return _vectors(raw, len(items))


def _get_json(http_, provider, path, headers, method='GET', body=None):
    response = http_.open(provider.endpoint, method, path, body, headers)
    try:
        response.check()
        answer = response.json()
    finally:
        response.close()
    if not isinstance(answer, dict):
        raise LlmError('invalid-response', 'The provider answer is not an object')
    return answer


def _name(value):
    return isinstance(value, str) and 0 < len(value) <= MAX_MODEL_NAME and not _CONTROL.search(value)


def _ollama_models(http_, provider, ctx):
    headers = {'Accept': 'application/json'}
    if provider.key:
        headers['Authorization'] = f'Bearer {provider.key}'
    base = provider.endpoint['path']
    answer = _get_json(http_, provider, base + '/api/tags', headers)
    listed = answer.get('models')
    if not isinstance(listed, list):
        raise LlmError('invalid-response', 'The provider answer has no model list')
    models = []
    for item in listed[:MAX_MODELS]:
        if not isinstance(item, dict) or not _name(item.get('name') or item.get('model')):
            continue
        entry = {'name': item.get('name') or item.get('model')}
        if isinstance(item.get('size'), int) and not isinstance(item.get('size'), bool):
            entry['sizeBytes'] = item['size']
        details = item.get('details')
        if isinstance(details, dict) and isinstance(details.get('parameter_size'), str):
            entry['parameterSize'] = _clean(details['parameter_size'], 32)
        models.append(entry)
    for entry in models:
        ctx.check()
        try:
            shown = _get_json(http_, provider, base + '/api/show', headers, 'POST', _body({'model': entry['name']}))
        except LlmError as error:
            if error.reason in ('timeout', 'denied'):
                raise
            continue  # an unreadable entry keeps its name and size
        capabilities = shown.get('capabilities')
        if isinstance(capabilities, list):
            entry['capabilities'] = [_clean(value, 32) for value in capabilities[:32] if isinstance(value, str) and value]
    return models


def op_models(payload, ctx, call):
    provider = _provider(payload, call)
    http_ = _Http(ctx, call)
    if provider.kind == 'ollama':
        return {'models': _ollama_models(http_, provider, ctx)}
    base = provider.endpoint['path']
    if provider.kind == 'openai-compatible':
        headers = {'Accept': 'application/json'}
        if provider.key:
            headers['Authorization'] = f'Bearer {provider.key}'
        answer = _get_json(http_, provider, base + '/models', headers)
        listed = answer.get('data')
        names = [item.get('id') for item in listed if isinstance(item, dict)] if isinstance(listed, list) else None
    elif provider.kind == 'anthropic':
        headers = {'Accept': 'application/json', 'anthropic-version': ANTHROPIC_VERSION}
        if provider.key:
            headers['x-api-key'] = provider.key
        answer = _get_json(http_, provider, base + '/v1/models?limit=1000', headers)
        listed = answer.get('data')
        names = [item.get('id') for item in listed if isinstance(item, dict)] if isinstance(listed, list) else None
    else:
        headers = {'Accept': 'application/json'}
        if provider.key:
            headers['x-goog-api-key'] = provider.key
        answer = _get_json(http_, provider, base + '/models?pageSize=1000', headers)
        listed = answer.get('models')
        if not isinstance(listed, list):
            raise LlmError('invalid-response', 'The provider answer has no model list')
        models = []
        for item in listed[:MAX_MODELS]:
            name = item.get('name') if isinstance(item, dict) else None
            if not _name(name):
                continue
            entry = {'name': name[len('models/'):] if name.startswith('models/') else name}
            methods = item.get('supportedGenerationMethods')
            if isinstance(methods, list):
                capabilities = [label for method, label in (('generateContent', 'completion'), ('embedContent', 'embedding'))
                                if method in methods]
                entry['capabilities'] = capabilities
            models.append(entry)
        return {'models': models}
    if names is None:
        raise LlmError('invalid-response', 'The provider answer has no model list')
    return {'models': [{'name': name} for name in names[:MAX_MODELS] if _name(name)]}


def op_warm(payload, ctx, call):
    provider = _provider(payload, call, resolve_key=False)
    model = _model(payload)
    keep_alive = _keep_alive(payload)
    if provider.kind != 'ollama':
        return {'warmed': False}
    provider = _provider(payload, call)
    document = {'model': model, 'messages': [], 'stream': False}
    if keep_alive is not None:
        document['keep_alive'] = keep_alive
    headers = {'Accept': 'application/json'}
    if provider.key:
        headers['Authorization'] = f'Bearer {provider.key}'
    started = time.monotonic()
    answer = _get_json(_Http(ctx, call), provider, provider.endpoint['path'] + '/api/chat', headers, 'POST', _body(document))
    wall_ms = round((time.monotonic() - started) * 1000)
    load = answer.get('load_duration')
    load_ms = round(load / 1e6) if isinstance(load, (int, float)) and not isinstance(load, bool) and load >= 0 else wall_ms
    return {'warmed': True, 'loadMs': load_ms, 'wallMs': wall_ms}


# --- Translation ----------------------------------------------------------------

def op_translate(payload, ctx, call):
    text = payload.get('text')
    target = payload.get('target')
    source = payload.get('source') or ''
    if not isinstance(text, str) or not text.strip() or len(text.encode('utf-8')) > MAX_TEXT:
        raise LlmError('invalid-input', 'text must be a non-empty string of at most 256 KiB')
    for code in (target, source) if source else (target,):
        if not isinstance(code, str) or not _LANGUAGE.fullmatch(code):
            raise LlmError('invalid-input', 'target and source must be language codes such as "uk" or "zh-CN"')
    return file_tool.translate(text, {'target': target, 'source': source})


# --- Registration ---------------------------------------------------------------

def _failure(reason, message, detail=''):
    result = {'ok': False, 'reason': reason, 'message': message[:500]}
    if detail:
        result['detail'] = detail[:64]
    return result


def _guarded(name, handler):
    def run(payload, ctx):
        call = _Call()
        try:
            return {'ok': True, 'value': handler(payload if isinstance(payload, dict) else {}, ctx, call)}
        except Cancelled:
            raise
        except LlmError as error:
            ctx.check()
            return _failure(error.reason, call.redact(error.message), error.detail)
        except ToolError as error:
            ctx.check()
            return _failure(getattr(error, 'reason', 'io') or 'io', call.redact(str(error))[:300])
        except Exception as error:  # never let an exception text (which might quote a header) escape
            ctx.check()
            return _failure('io', f'{name} failed ({type(error).__name__})')
    return run


def register_ops(ops):
    """Add llm.chat, llm.embed, llm.models, llm.warm and text.translate to the worker's op table."""
    for name, handler in (('llm.chat', op_chat), ('llm.embed', op_embed), ('llm.models', op_models),
                          ('llm.warm', op_warm), ('text.translate', op_translate)):
        ops[name] = _guarded(name, handler)
