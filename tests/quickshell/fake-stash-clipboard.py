#!/usr/bin/env python3
"""Offline stand-in for tools/pentad_stash_clipboard.py in the shelf QML fixture.

Every request is appended as one JSON line to $XDG_STATE_HOME/stash-clipboard-requests.jsonl, so the
fixture can read back what the service sent. No clipboard is touched: the first paste answers with text,
the second and fourth with a stash-owned image, the others are empty; copy and delete always succeed.
"""
import json
import os
from pathlib import Path
import sys


def main():
    request = json.loads(sys.stdin.read())
    state = os.environ.get('XDG_STATE_HOME') or os.path.join(os.path.expanduser('~'), '.local', 'state')
    log = os.path.join(state, 'stash-clipboard-requests.jsonl')
    os.makedirs(state, exist_ok=True)
    previous = []
    if os.path.exists(log):
        with open(log, encoding='utf-8') as handle:
            previous = [json.loads(line) for line in handle if line.strip()]
    with open(log, 'a', encoding='utf-8') as handle:
        handle.write(json.dumps(request, ensure_ascii=False) + '\n')
    operation = request.get('operation')
    if operation == 'paste':
        pastes = sum(1 for item in previous if item.get('operation') == 'paste')
        if pastes == 0:
            result = {'ok': True, 'text': 'Вставлено з буфера'}
        elif pastes == 1:
            path = Path(state) / 'pentad' / 'stash' / 'clip-fixture.png'
            result = {'ok': True, 'items': [{'uri': path.as_uri(), 'label': path.name, 'owned': True}]}
        elif pastes == 3:
            path = Path(state) / 'pentad' / 'stash' / 'clip-second.png'
            result = {'ok': True, 'items': [{'uri': path.as_uri(), 'label': path.name, 'owned': True}]}
        else:
            result = {'ok': False, 'reason': 'empty', 'message': 'The clipboard has nothing to paste'}
    elif operation in ('copy', 'delete'):
        result = {'ok': True}
    else:
        result = {'ok': False, 'reason': 'invalid', 'message': 'Unknown operation'}
    print(json.dumps(result, ensure_ascii=False), flush=True)


if __name__ == '__main__':
    main()
