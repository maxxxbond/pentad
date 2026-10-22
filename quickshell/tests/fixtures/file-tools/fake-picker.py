#!/usr/bin/env python3
"""Stands in for tools/pentad_pick_files.py in fixtures: answers with a file next to itself."""
import json
import sys
from pathlib import Path
from urllib.parse import quote

request = json.loads(sys.stdin.read() or '{}')
chosen = Path(__file__).resolve().parent / 'pages-pages.pdf'
print(json.dumps({'ok': True, 'uris': ['file://' + quote(str(chosen), safe='/')], 'title': request.get('title')}))
