"""Keep model-provider credentials in the desktop keyring through libsecret's `secret-tool`.

A reference looks like `secret://pentad/providers/openai`. The value travels to `secret-tool`
on stdin only and is never part of an argument list, a result dictionary, an error message or
a log line. There is no plaintext fallback: a missing program or a missing Secret Service is
reported as `unavailable`.

`secret-tool` exits 1 with no output both for an absent item and for a collection that is
locked and cannot be prompted for, so "locked" cannot be told apart reliably from "missing"
and is never guessed: a locked keyring appears as `missing` (or as `unavailable` when the
service itself fails). Only a non-zero exit with a message on stderr (no D-Bus, no Secret
Service) counts as `unavailable`.
"""
import os
import re
import shutil
import subprocess

PROGRAM = 'secret-tool'
TIMEOUT = 20
SCHEME = 'secret://pentad/'
ATTRIBUTE = 'pentad-ref'
_SEGMENT = re.compile(r'^[a-z0-9._-]+$')
REASONS = ('missing', 'locked', 'unavailable', 'invalid')


class SecretError(Exception):
    """`reason` is one of missing, locked, unavailable, invalid. The message never holds a secret."""

    def __init__(self, reason, message=''):
        super().__init__(message or reason)
        self.reason = reason


def parse_ref(ref):
    """Return the path after `secret://pentad/`, or raise SecretError('invalid')."""
    if not isinstance(ref, str) or not ref.startswith(SCHEME):
        raise SecretError('invalid', 'A secret reference looks like secret://pentad/<path>')
    path = ref[len(SCHEME):]
    segments = path.split('/')
    if not all(_SEGMENT.match(s) and s not in ('.', '..') for s in segments):
        raise SecretError('invalid', 'Secret reference segments use only a-z, 0-9, dot, underscore and hyphen')
    return path


def _run(args, stdin=None):
    """Return (code, stdout bytes, stderr bytes); a missing or hanging program is `unavailable`."""
    if shutil.which(PROGRAM) is None:
        raise SecretError('unavailable', f'{PROGRAM} is not installed')
    try:
        done = subprocess.run([PROGRAM, *args], input=stdin, capture_output=True, timeout=TIMEOUT, check=False,
                              **({} if stdin is not None else {'stdin': subprocess.DEVNULL}))
    except subprocess.TimeoutExpired:
        raise SecretError('unavailable', f'{PROGRAM} took longer than {TIMEOUT} s and was stopped') from None
    except OSError:
        raise SecretError('unavailable', f'{PROGRAM} could not be started') from None
    return done.returncode, done.stdout, done.stderr


def lookup(ref):
    """Return the stored value or raise SecretError (missing, unavailable, invalid)."""
    path = parse_ref(ref)
    code, out, err = _run(['lookup', ATTRIBUTE, path])
    if code == 0 and out:
        return out.decode('utf-8', 'replace')
    if code != 0 and err.strip():
        raise SecretError('unavailable', 'The keyring (Secret Service) did not answer')
    raise SecretError('missing', 'No secret is stored for this reference')


def status(ref):
    """Return stored, missing, locked or unavailable; raise SecretError('invalid') for a bad reference."""
    try:
        lookup(ref)
    except SecretError as error:
        if error.reason == 'invalid':
            raise
        return error.reason
    return 'stored'


def store(ref, value):
    """Save `value` (on stdin) under the reference, replacing any earlier one."""
    path = parse_ref(ref)
    if not isinstance(value, str) or not value or '\0' in value:
        raise SecretError('invalid', 'The secret value is empty or malformed')
    code, _, _ = _run(['store', '--label', f'Pentad {path}', ATTRIBUTE, path], stdin=value.encode('utf-8'))
    if code != 0:
        raise SecretError('unavailable', 'The keyring (Secret Service) refused to store the secret')


def clear(ref):
    """Delete the stored value and verify it is gone."""
    path = parse_ref(ref)
    code, _, err = _run(['clear', ATTRIBUTE, path])
    if code != 0 and err.strip():
        raise SecretError('unavailable', 'The keyring (Secret Service) did not answer')
    if status(ref) == 'stored':
        raise SecretError('unavailable', 'The secret is still stored after clearing')


def resolve(provider):
    """Return the credential for a provider dict, or None when it needs none.

    `credential` (a secret:// reference) wins; otherwise `credentialEnv` names an environment
    variable. A configured source that yields nothing raises SecretError.
    """
    reference = (provider.get('credential') or '').strip()
    if reference:
        return lookup(reference)
    name = (provider.get('credentialEnv') or '').strip()
    if name:
        value = os.environ.get(name, '')
        if not value:
            raise SecretError('missing', 'The credential environment variable is not set')
        return value
    return None


def _op(handler):
    def run(payload, ctx=None):
        try:
            return {'ok': True, 'value': handler(payload if isinstance(payload, dict) else {})}
        except SecretError as error:
            # The worker contract only carries Result reasons; keep the secret-specific one as detail.
            reason = RESULT_REASON.get(error.reason, 'io')
            return {'ok': False, 'reason': reason, 'message': str(error), 'detail': error.reason}
    return run


RESULT_REASON = {'missing': 'unavailable', 'locked': 'unavailable', 'unavailable': 'unavailable',
                 'invalid': 'invalid-input'}


def _status(payload):
    return {'status': status(payload.get('ref'))}


def _store(payload):
    store(payload.get('ref'), payload.get('value'))
    return {'status': 'stored'}


def _clear(payload):
    clear(payload.get('ref'))
    return {'status': 'missing'}


def register_ops(table):
    """Add secret.status, secret.store and secret.clear to the worker's op table."""
    table['secret.status'] = _op(_status)
    table['secret.store'] = _op(_store)
    table['secret.clear'] = _op(_clear)
