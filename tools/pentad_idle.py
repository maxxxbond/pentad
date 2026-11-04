"""Conservative, revision-checked edits of the user's hypridle listeners.

Commands are configuration text, never executed here. Unsupported layouts are read-only.
Disabled listeners stay in comments so their commands and options survive re-enabling.
"""
import fcntl
import hashlib
import os
import re
import shlex
import shutil
import stat
import tempfile
import time
from contextlib import contextmanager
from pathlib import Path

DISABLED = '# pentad-idle-disabled: '
MAX_BYTES = 1024 * 1024
MAX_SECONDS = 24 * 60 * 60
VARIABLE = re.compile(r'\$[A-Za-z_][A-Za-z_0-9]*')
DPMS_OFF = "hyprctl dispatch 'hl.dsp.dpms({ action = \"disable\" })'"
DPMS_ON = "hyprctl dispatch 'hl.dsp.dpms({ action = \"enable\" })'"


class IdleError(ValueError):
    def __init__(self, reason):
        super().__init__(reason)
        self.reason = reason


def config_path():
    base = os.environ.get('XDG_CONFIG_HOME') or str(Path.home() / '.config')
    return Path(base) / 'hypr/hypridle.conf'


def _code(line):
    # Hyprlang escapes a literal hash with ##, rather than shell quoting.
    return line.replace('##', '\x00').split('#', 1)[0].replace('\x00', '##').strip()


def _expand(value, variables):
    for _ in range(16):
        expanded = VARIABLE.sub(lambda match: variables.get(match.group(), match.group()), value)
        if expanded == value:
            return value
        value = expanded
    raise IdleError('idle-config-complex')


def _action(command, variables):
    value = _expand(command, variables).strip()
    try:
        argv = shlex.split(value)
    except ValueError:
        raise IdleError('idle-config-complex') from None
    arguments = [arg for arg in argv[1:] if not arg.startswith('-')]
    if command.strip() == '$suspend_cmd' or (argv and argv[0] in ('systemctl', 'loginctl')
            and len(arguments) == 1 and arguments[0] in ('suspend', 'suspend-then-hibernate', 'hybrid-sleep')):
        return 'suspend'
    if re.fullmatch(r'hyprctl\s+dispatch\s+dpms\s+off', value) or re.fullmatch(
            r'''hyprctl\s+dispatch\s+['"]?hl\.dsp\.dpms\(\{\s*action\s*=\s*["']disable["']\s*\}\)['"]?''', value):
        return 'display'
    if re.search(r'\b(?:suspend|dpms)\b', value):
        # A compound/custom sleep or DPMS command must not acquire a competing timer.
        raise IdleError('idle-config-complex')
    return None


def parse(text):
    """Return only unambiguous listeners; retain byte offsets via splitlines(True)."""
    lines = text.splitlines(keepends=True)
    variables = {}
    listeners = {}
    category = None
    start = 0
    fields = {}
    disabled = False
    decoded = []
    for index, original in enumerate(lines):
        marked = original.startswith(DISABLED)
        line = original[len(DISABLED):] if marked else original
        code = _code(line)
        if not code:
            if category == 'listener':
                decoded.append(line)
            continue
        if code == '}':
            if category is None:
                raise IdleError('idle-config-complex')
            if category == 'listener':
                if marked != disabled:
                    raise IdleError('idle-config-complex')
                decoded.append(line)
                command = fields.get('on-timeout', {}).get('value', '')
                action = _action(command, variables)
                if action:
                    if action in listeners or 'timeout' not in fields:
                        raise IdleError('idle-config-complex')
                    timeout = _expand(fields['timeout']['value'], variables)
                    if not re.fullmatch(r'[1-9][0-9]*', timeout) or int(timeout) > MAX_SECONDS:
                        raise IdleError('idle-config-complex')
                    listeners[action] = dict(start=start, end=index + 1, fields=fields,
                                             lines=decoded, disabled=disabled, seconds=int(timeout))
            category = None
            continue
        opening = re.fullmatch(r'(general|listener)\s*\{', code)
        if opening:
            if category is not None or (marked and opening[1] != 'listener'):
                raise IdleError('idle-config-complex')
            category = opening[1]
            start, fields, decoded, disabled = index, {}, [line], marked
            continue
        match = re.fullmatch(r'([^=\s]+)\s*=\s*(.*)', code)
        if not match:
            raise IdleError('idle-config-complex')
        key, value = match.groups()
        if key == 'source' or (category is None and not key.startswith('$')):
            raise IdleError('idle-config-complex')
        if category is None:
            if marked or key in variables:
                raise IdleError('idle-config-complex')
            variables[key] = _expand(value, variables)
        elif category == 'listener':
            if marked != disabled or key in fields:
                raise IdleError('idle-config-complex')
            fields[key] = dict(value=value, index=index - start)
            decoded.append(line)
    if category is not None:
        raise IdleError('idle-config-complex')
    return lines, listeners


def edit(text, action, seconds):
    if action not in ('display', 'suspend') or type(seconds) is not int or not 0 <= seconds <= MAX_SECONDS:
        raise IdleError('invalid-request')
    lines, listeners = parse(text)
    listener = listeners.get(action)
    newline = '\r\n' if '\r\n' in text else '\n'
    if listener:
        replacement = list(listener['lines'])
        if seconds:
            index = listener['fields']['timeout']['index']
            # Replace the value and retain its indentation, trailing comment and line ending.
            replacement[index] = re.sub(r'^(\s*timeout\s*=\s*)[^\s#]+',
                                        lambda match: match[1] + str(seconds), replacement[index])
            if action == 'display' and not listener['fields'].get('on-resume', {}).get('value'):
                wake = DPMS_ON if 'hl.dsp.' in listener['fields']['on-timeout']['value'] else 'hyprctl dispatch dpms on'
                replacement.insert(-1, '    on-resume = ' + wake + newline)
                if 'on-resume' in listener['fields']:
                    del replacement[listener['fields']['on-resume']['index']]
        else:
            replacement = [DISABLED + line for line in replacement]
        return ''.join(lines[:listener['start']] + replacement + lines[listener['end']:])
    if not seconds:
        return text
    command = DPMS_OFF if action == 'display' else 'systemctl suspend'
    block = ['# Pentad: ' + action, 'listener {', '    timeout = ' + str(seconds),
             '    on-timeout = ' + command]
    if action == 'display':
        block.append('    on-resume = ' + DPMS_ON)
    block.append('}')
    return text + (newline if text and not text.endswith('\n') else '') + newline + newline.join(block) + newline


def _read(path):
    try:
        fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    except FileNotFoundError:
        raise IdleError('idle-config-missing') from None
    except OSError:
        raise IdleError('idle-config-read-only') from None
    try:
        info = os.fstat(fd)
        if not stat.S_ISREG(info.st_mode) or info.st_size > MAX_BYTES:
            raise IdleError('idle-config-complex')
        with os.fdopen(fd, 'rb', closefd=False) as stream:
            data = stream.read(MAX_BYTES + 1)
        if len(data) > MAX_BYTES:
            raise IdleError('idle-config-complex')
        try:
            text = data.decode('utf-8')
        except UnicodeDecodeError:
            raise IdleError('idle-config-complex') from None
        return text, hashlib.sha256(data).hexdigest(), info
    finally:
        os.close(fd)


def idle_state(path=None):
    path = config_path() if path is None else Path(path)
    try:
        text, revision, _ = _read(path)
        _, listeners = parse(text)
        values = {action: entry['seconds'] if not entry['disabled'] else 0
                  for action, entry in listeners.items()}
        return dict(ok=True, revision=revision, display=values.get('display', 0),
                    suspend=values.get('suspend', 0), available=shutil.which('hypridle') is not None)
    except IdleError as error:
        return dict(ok=False, reason=error.reason)
    except OSError:
        return dict(ok=False, reason='idle-config-read-only')


@contextmanager
def _locked(path):
    fd = os.open(path.parent / '.pentad-idle.lock', os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW | os.O_NONBLOCK, 0o600)
    try:
        if not stat.S_ISREG(os.fstat(fd).st_mode):
            raise IdleError('idle-config-read-only')
        deadline = time.monotonic() + 5
        while True:
            try:
                fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
                break
            except BlockingIOError:
                if time.monotonic() >= deadline:
                    raise IdleError('timeout')
                time.sleep(0.05)
        yield
    finally:
        os.close(fd)


def set_idle_timeout(request, path=None):
    path = config_path() if path is None else Path(path)
    try:
        with _locked(path):
            return _set_locked(request, path)
    except IdleError as error:
        return dict(ok=False, reason=error.reason)
    except OSError:
        return dict(ok=False, reason='idle-config-read-only')


def _set_locked(request, path):
    stage = None
    try:
        text, revision, info = _read(path)
        if not isinstance(request.get('revision'), str) or request['revision'] != revision:
            raise IdleError('conflict')
        updated = edit(text, request.get('action'), request.get('seconds'))
        if updated == text:
            return dict(ok=True, restartRequired=False)
        data = updated.encode('utf-8')
        if len(data) > MAX_BYTES:
            raise IdleError('idle-config-complex')
        # A sibling temporary file keeps replace atomic. Never follow or replace a symlink.
        fd, stage = tempfile.mkstemp(prefix='.pentad-idle-', dir=path.parent)
        with os.fdopen(fd, 'wb') as stream:
            os.fchmod(stream.fileno(), stat.S_IMODE(info.st_mode))
            stream.write(data)
            stream.flush()
            os.fsync(stream.fileno())
        if _read(path)[1] != revision:
            raise IdleError('conflict')
        os.replace(stage, path)
        return dict(ok=True, restartRequired=True)
    except IdleError as error:
        return dict(ok=False, reason=error.reason)
    except OSError:
        return dict(ok=False, reason='idle-config-read-only')
    finally:
        if stage and os.path.exists(stage):
            os.unlink(stage)
