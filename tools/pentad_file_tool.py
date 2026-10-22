#!/usr/bin/env python3
"""Run one explicitly requested local file operation for a sidebar tool.

The request arrives as JSON on stdin and the result leaves as one JSON line on stdout.
Every CLI runs with an argument list (never a shell), inside a private work directory that
links the inputs under neutral names, so file names never reach CLI option or pattern
parsers. Results are published next to the first input with a fresh name and never
replace an existing file. SIGTERM stops the running CLI and removes partial output.
"""
import json
import os
import re
import signal
import stat
import sys

# Sibling modules live next to this file. `python3 -I` leaves the script
# directory off sys.path; append it (never prepend) so the standard
# library still wins over anything in this directory.
_HERE = os.path.dirname(os.path.abspath(__file__))
if _HERE not in sys.path:
    sys.path.append(_HERE)

from pentad_tool_archive import archive_create, archive_extract, checksum
# page_ranges, parse_pages, parse_time and split_name are re-exported for the unit tests.
from pentad_tool_core import (MAX_INPUTS, MAX_REQUEST, MAX_TEXT, Cancelled, Job, ToolError, _cancel, describe,
                              file_path, page_ranges, parse_pages, parse_time, run, split_name)
from pentad_tool_image import (image_barcode, image_compress, image_convert, image_ocr, image_pdf, image_resize,
                               image_rotate, image_strip, ocr_languages)
from pentad_tool_media import media_audio, media_gif, media_trim, media_video
from pentad_tool_pdf import (pdf_compress, pdf_delete, pdf_extract, pdf_images, pdf_lock, pdf_merge, pdf_rotate,
                             pdf_split, pdf_text, pdf_unlock)


# --- Text ------------------------------------------------------------------

def translate(text, options):
    target = options.get('target') or 'en'
    source = options.get('source') or ''
    for code in (target, source):
        if code and not re.fullmatch(r'[a-z]{2,3}(-[A-Za-z]{2,4})?', code):
            raise ToolError(f'Unsupported language code {code}')
    if not text.strip():
        raise ToolError('Enter text to translate')
    _, out, _ = run(['trans', '-brief', '-no-ansi', '-no-autocorrect', f'{source}:{target}'], None, 45, stdin=text.encode('utf-8'))
    value = out.decode('utf-8', 'replace').strip()
    if not value:
        raise ToolError('The translation service returned nothing; check the network')
    return {'text': value[:MAX_TEXT]}


OPERATIONS = {
    'pdf.extract': (pdf_extract, 1, 1), 'pdf.delete': (pdf_delete, 1, 1), 'pdf.split': (pdf_split, 1, 1),
    'pdf.rotate': (pdf_rotate, 1, MAX_INPUTS), 'pdf.compress': (pdf_compress, 1, MAX_INPUTS), 'pdf.merge': (pdf_merge, 2, MAX_INPUTS),
    'pdf.images': (pdf_images, 1, 1), 'pdf.text': (pdf_text, 1, 1), 'pdf.unlock': (pdf_unlock, 1, 1), 'pdf.lock': (pdf_lock, 1, 1),
    'image.convert': (image_convert, 1, MAX_INPUTS), 'image.resize': (image_resize, 1, MAX_INPUTS),
    'image.compress': (image_compress, 1, MAX_INPUTS), 'image.strip': (image_strip, 1, MAX_INPUTS),
    'image.rotate': (image_rotate, 1, MAX_INPUTS), 'image.pdf': (image_pdf, 1, MAX_INPUTS),
    'image.ocr': (image_ocr, 1, 20), 'image.barcode': (image_barcode, 1, 20),
    'media.gif': (media_gif, 1, 10), 'media.video': (media_video, 1, 20), 'media.audio': (media_audio, 1, MAX_INPUTS),
    'media.trim': (media_trim, 1, 1),
    'archive.extract': (archive_extract, 1, 20), 'archive.create': (archive_create, 1, MAX_INPUTS),
    'checksum': (checksum, 0, MAX_INPUTS),
}


def execute(request):
    if not isinstance(request, dict):
        raise ToolError('Expected a request object')
    operation = request.get('operation')
    options = request.get('options') or {}
    if not isinstance(options, dict):
        raise ToolError('Options must be an object')
    text = request.get('text')
    if text is not None and (not isinstance(text, str) or len(text.encode('utf-8')) > MAX_TEXT):
        raise ToolError('Text input is limited to 256 KiB')
    if operation == 'ocr.languages':
        return {'ok': True, 'languages': ocr_languages()}
    if operation == 'text.translate':
        return {'ok': True, **translate(text or '', options)}
    if operation not in OPERATIONS:
        raise ToolError(f'Unknown operation {operation}')
    handler, minimum, maximum = OPERATIONS[operation]
    uris = request.get('inputs') or []
    if not isinstance(uris, list) or any(not isinstance(uri, str) or len(uri) > 4096 for uri in uris):
        raise ToolError('Invalid input list')
    if not minimum <= len(uris) <= maximum or (not uris and text is None):
        raise ToolError(f'This action takes {minimum}–{maximum} files' if maximum > 1 else 'This action takes one file')
    inputs = []
    for uri in uris:
        path = file_path(uri)
        try:
            mode = path.stat().st_mode
        except FileNotFoundError:
            raise ToolError(f'{path.name} no longer exists') from None
        if not stat.S_ISREG(mode):
            raise ToolError(f'{path.name} is not a regular file')
        inputs.append(path.resolve())
    if handler is checksum:
        return {'ok': True, **checksum(_InputsOnly(inputs), options, text)}
    job = Job(inputs)
    try:
        result = handler(job, options)
        outputs = [describe(path) for path in job.outputs]
    except BaseException:
        job.discard_outputs()
        raise
    finally:
        job.cleanup()
    input_bytes = sum(path.stat().st_size for path in inputs)
    return {'ok': True, 'outputs': outputs, 'inputBytes': input_bytes,
            'outputBytes': sum(item['sizeBytes'] for item in outputs), **result}


class _InputsOnly:
    """Checksums read inputs in place and publish nothing, so they skip the work directory."""
    def __init__(self, inputs):
        self.inputs = inputs


def main():
    signal.signal(signal.SIGTERM, _cancel)
    signal.signal(signal.SIGINT, _cancel)
    try:
        raw = sys.stdin.buffer.read(MAX_REQUEST + 1)
        if len(raw) > MAX_REQUEST:
            raise ToolError('Request is too large')
        result = execute(json.loads(raw.decode('utf-8')))
    except Cancelled:
        result = {'ok': False, 'cancelled': True, 'reason': 'Cancelled'}
    except ToolError as error:
        result = {'ok': False, 'reason': str(error)[:300]}
    except (OSError, UnicodeError, ValueError, TypeError) as error:
        result = {'ok': False, 'reason': str(error)[:300] or error.__class__.__name__}
    sys.stdout.write(json.dumps(result, ensure_ascii=False, separators=(',', ':')) + '\n')
    sys.stdout.flush()
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
