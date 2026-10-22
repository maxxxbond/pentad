#!/usr/bin/env python3
"""Run one explicitly requested local file operation for a sidebar tool.

The request arrives as JSON on stdin and the result leaves as one JSON line on stdout.
Every CLI runs with an argument list (never a shell), inside a private work directory that
links the inputs under neutral names, so file names never reach CLI option or pattern
parsers. Results are published next to the first input with a fresh name and never
replace an existing file. SIGTERM stops the running CLI and removes partial output.
"""
import hashlib
import json
import mimetypes
import os
import re
import shutil
import signal
import stat
import subprocess
import sys
import tempfile
from pathlib import Path
from urllib.parse import quote, urlsplit
from urllib.request import url2pathname

MAX_INPUTS = 100
MAX_REQUEST = 1024 * 1024
MAX_TEXT = 256 * 1024
TAR_SUFFIXES = ('.tar', '.tar.gz', '.tgz', '.tar.xz', '.txz', '.tar.zst', '.tzst', '.tar.bz2', '.tbz2', '.tbz')
STACKED_SUFFIXES = TAR_SUFFIXES + ('.tar.lz', '.tar.lzma')


class ToolError(Exception):
    def __init__(self, message, detail=''):
        super().__init__(message)
        self.detail = detail


class Cancelled(BaseException):
    pass


def _cancel(signum, frame):
    raise Cancelled()


def _kill(process):
    try:
        os.killpg(process.pid, signal.SIGKILL)
    except (ProcessLookupError, PermissionError):
        pass
    try:
        process.wait(timeout=5)
    except subprocess.TimeoutExpired:
        pass


def _first_line(data):
    text = data.decode('utf-8', 'replace') if isinstance(data, bytes) else str(data or '')
    lines = [line.strip() for line in text.splitlines() if line.strip()]
    errors = [line for line in lines if re.search(r'error|invalid|fail|cannot|can\'t|unable|not ', line, re.I)]
    return ((errors or lines or [''])[-1])[:200]


def _die_with_parent():
    # The CLI gets its own process group for clean cancellation; this keeps it from outliving
    # the helper if the shell kills the helper outright.
    try:
        import ctypes
        ctypes.CDLL(None, use_errno=True).prctl(1, signal.SIGKILL)  # PR_SET_PDEATHSIG
    except (OSError, AttributeError):
        pass


def run(argv, cwd, timeout, stdin=None, ok_codes=(0,)):
    """Run a CLI in its own process group; return (code, stdout, stderr)."""
    name = argv[0]
    try:
        process = subprocess.Popen(argv, cwd=cwd, start_new_session=True, preexec_fn=_die_with_parent,
            stdin=subprocess.PIPE if stdin is not None else subprocess.DEVNULL,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    except FileNotFoundError:
        raise ToolError(f'{name} is not installed') from None
    try:
        out, err = process.communicate(stdin, timeout=timeout)
    except subprocess.TimeoutExpired:
        _kill(process)
        raise ToolError(f'{name} took longer than {timeout} s and was stopped') from None
    except BaseException:
        _kill(process)
        raise
    if process.returncode not in ok_codes:
        raise ToolError(_first_line(err) or _first_line(out) or f'{name} failed with exit code {process.returncode}',
                        (err or b'').decode('utf-8', 'replace'))
    return process.returncode, out, err


def file_path(uri):
    parsed = urlsplit(uri)
    if parsed.scheme != 'file' or parsed.netloc not in ('', 'localhost') or not parsed.path.startswith('/') or parsed.query or parsed.fragment:
        raise ToolError('Only local files are supported')
    path = url2pathname(parsed.path)
    if '\0' in path:
        raise ToolError('Invalid file URI')
    return Path(path)


def file_uri(path):
    return 'file://' + quote(str(path), safe='/')


def split_name(name):
    """Return (stem, suffix) keeping stacked archive suffixes such as .tar.gz together."""
    lower = name.lower()
    for suffix in sorted(STACKED_SUFFIXES, key=len, reverse=True):
        if lower.endswith(suffix) and len(name) > len(suffix):
            return name[:-len(suffix)], name[-len(suffix):]
    stem, dot, extension = name.rpartition('.')
    return (stem, '.' + extension) if dot and stem else (name, '')


def describe(path):
    info = path.stat()
    folder = stat.S_ISDIR(info.st_mode)
    size = sum(child.stat().st_size for child in path.rglob('*') if child.is_file() and not child.is_symlink()) if folder else info.st_size
    mime = 'inode/directory' if folder else mimetypes.guess_type(path.name)[0] or 'application/octet-stream'
    return {'kind': 'folder' if folder else 'file', 'mimeType': mime, 'uri': file_uri(path), 'name': path.name, 'sizeBytes': size}


class Job:
    def __init__(self, inputs):
        self.inputs = inputs
        self.output_dir = self._output_dir(inputs[0].parent if inputs else None)
        self.work = Path(tempfile.mkdtemp(prefix='.pentad-tool-', dir=self.output_dir))
        self.outputs = []
        self._links = 0

    @staticmethod
    def _output_dir(preferred):
        if preferred and os.access(preferred, os.W_OK | os.X_OK):
            return preferred
        downloads = Path(os.environ.get('XDG_DOWNLOAD_DIR') or Path.home() / 'Downloads') / 'Pentad'
        downloads.mkdir(parents=True, exist_ok=True)
        return downloads

    def link(self, path, name=None):
        """Expose an input inside the work directory under a neutral (or chosen) name."""
        if name is None:
            self._links += 1
            name = f'input-{self._links}{split_name(path.name)[1].lower()}'
            name = re.sub(r'[^a-z0-9.-]', '', name) or f'input-{self._links}'
        os.symlink(path, self.work / name)
        return name

    def scratch(self, name):
        return self.work / name

    def publish(self, produced, stem, suffix=''):
        """Move a produced file or folder to a fresh name beside the inputs; never overwrite."""
        produced = Path(produced)
        if not produced.exists():
            raise ToolError('The tool finished without producing a file')
        folder = produced.is_dir()
        stem = (stem.strip() or 'Output')[:180]
        for index in range(1, 1000):
            candidate = self.output_dir / (f'{stem}{suffix}' if index == 1 else f'{stem} ({index}){suffix}')
            try:
                if folder:
                    candidate.mkdir()
                else:
                    os.close(os.open(candidate, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o644))
            except FileExistsError:
                continue
            try:
                os.replace(produced, candidate)
            except OSError:
                if folder:
                    candidate.rmdir()
                else:
                    candidate.unlink(missing_ok=True)
                raise
            self.outputs.append(candidate)
            return candidate
        raise ToolError('Could not find a free output name')

    def cleanup(self):
        shutil.rmtree(self.work, ignore_errors=True)

    def discard_outputs(self):
        for path in self.outputs:
            if path.is_dir():
                shutil.rmtree(path, ignore_errors=True)
            else:
                path.unlink(missing_ok=True)
        self.outputs = []


def choice(options, key, allowed, default):
    value = options.get(key, default)
    if isinstance(value, (int, float)) and not isinstance(value, bool):
        value = str(int(value))
    if value not in allowed:
        raise ToolError(f'Unsupported {key}: {value}')
    return value


def secret(options, key='password'):
    value = options.get(key)
    if not isinstance(value, str) or not value:
        raise ToolError('Enter a password')
    if '\n' in value or '\r' in value or '\0' in value or len(value) > 512:
        raise ToolError('The password cannot contain line breaks')
    return value


def parse_pages(spec, count):
    """Parse '1-3, 5, 8-', '-2' and 'z'/'end' into a page list (1-based, order kept, no repeats)."""
    if not isinstance(spec, str) or not spec.strip():
        raise ToolError('Enter pages, for example 1-3, 5')
    if len(spec) > 1000:
        raise ToolError('The page list is too long')
    def bound(token, fallback):
        if token in (None, ''):
            return fallback
        if token in ('z', 'end', 'last'):
            return count
        return int(token)
    pages = []
    for part in spec.lower().replace(' ', '').split(','):
        if not part:
            continue
        match = re.fullmatch(r'(\d+|z|end|last)?(-(\d+|z|end|last)?)?', part)
        if not match or not (match.group(1) or match.group(2)):
            raise ToolError(f'Cannot read page range “{part}”')
        start = bound(match.group(1), 1)
        end = bound(match.group(3), count) if match.group(2) else start
        for page in (start, end):
            if not 1 <= page <= count:
                raise ToolError(f'Page {page} is outside 1–{count}')
        step = 1 if end >= start else -1
        for page in range(start, end + step, step):
            if page not in pages:
                pages.append(page)
    if not pages:
        raise ToolError('Enter pages, for example 1-3, 5')
    return pages


def page_ranges(pages):
    """Compress [1,2,3,7] into '1-3,7' for qpdf."""
    ranges, start, previous = [], None, None
    for page in pages + [None]:
        if start is not None and page is not None and previous is not None and page == previous + 1:
            previous = page
            continue
        if start is not None:
            ranges.append(str(start) if start == previous else f'{start}-{previous}')
        start = previous = page
    return ','.join(ranges)


def parse_time(value, label):
    if value in (None, ''):
        return None
    text = str(value).strip()
    match = re.fullmatch(r'(?:(\d+):)?(?:(\d+):)?(\d+(?:\.\d+)?)', text)
    if not match:
        raise ToolError(f'{label} must look like 75, 1:15 or 0:01:15.5')
    parts = [part for part in match.groups() if part is not None]
    seconds = 0.0
    for part in parts:
        seconds = seconds * 60 + float(part)
    return seconds


def human_size(size):
    for unit in ('B', 'KB', 'MB', 'GB'):
        if size < 1024 or unit == 'GB':
            return f'{size:.0f} {unit}' if unit == 'B' else f'{size:.1f} {unit}'
        size /= 1024
    return f'{size} B'


# --- PDF -------------------------------------------------------------------

def _pdf(job, path):
    with open(path, 'rb') as handle:
        if not handle.read(1024).lstrip().startswith(b'%PDF-'):
            raise ToolError(f'{path.name} is not a PDF')
    return job.link(path)


def _encrypted(job, name):
    code, _, _ = run(['qpdf', '--requires-password', name], job.work, 30, ok_codes=(0, 2, 3))
    return code == 0


def _plain_pdf(job, path):
    name = _pdf(job, path)
    if _encrypted(job, name):
        raise ToolError(f'{path.name} is password-protected; unlock it first')
    return name


def _page_count(job, name):
    _, out, _ = run(['qpdf', '--show-npages', name], job.work, 60, ok_codes=(0, 3))
    return int(out.strip() or 0)


def pdf_extract(job, options):
    name = _plain_pdf(job, job.inputs[0])
    pages = parse_pages(options.get('pages'), _page_count(job, name))
    run(['qpdf', name, '--pages', name, page_ranges(pages), '--', 'out.pdf'], job.work, 300, ok_codes=(0, 3))
    job.publish(job.scratch('out.pdf'), split_name(job.inputs[0].name)[0] + '-pages', '.pdf')
    return {'summary': f'{len(pages)} page{"s" if len(pages) != 1 else ""} extracted'}


def pdf_delete(job, options):
    name = _plain_pdf(job, job.inputs[0])
    count = _page_count(job, name)
    removed = parse_pages(options.get('pages'), count)
    kept = [page for page in range(1, count + 1) if page not in removed]
    if not kept:
        raise ToolError('At least one page must remain')
    run(['qpdf', name, '--pages', name, page_ranges(kept), '--', 'out.pdf'], job.work, 300, ok_codes=(0, 3))
    job.publish(job.scratch('out.pdf'), split_name(job.inputs[0].name)[0] + '-edited', '.pdf')
    return {'summary': f'{len(removed)} removed, {len(kept)} kept'}


def pdf_split(job, options):
    every = int(choice(options, 'every', ('1', '2', '5', '10'), '1'))
    name = _plain_pdf(job, job.inputs[0])
    stem = split_name(job.inputs[0].name)[0]
    folder = job.scratch('out')
    folder.mkdir()
    run(['qpdf', f'--split-pages={every}', name, str(folder / 'part-%d.pdf')], job.work, 300, ok_codes=(0, 3))
    parts = sorted(folder.iterdir())
    for part in parts:
        part.rename(folder / f'{stem} {part.name[5:]}')
    job.publish(folder, stem + '-split')
    return {'summary': f'{len(parts)} files'}


def pdf_rotate(job, options):
    angle = choice(options, 'angle', ('90', '180', '270'), '90')
    for path in job.inputs:
        name = _plain_pdf(job, path)
        pages = options.get('pages') or ''
        selection = page_ranges(parse_pages(pages, _page_count(job, name))) if pages.strip() else '1-z'
        out = job.scratch(name + '.rotated.pdf')
        run(['qpdf', name, out.name, f'--rotate=+{angle}:{selection}'], job.work, 300, ok_codes=(0, 3))
        job.publish(out, split_name(path.name)[0] + '-rotated', '.pdf')
    return {}


GS_PRESETS = {'screen': '/screen', 'ebook': '/ebook', 'printer': '/printer'}


def pdf_compress(job, options):
    preset = choice(options, 'level', tuple(GS_PRESETS), 'ebook')
    before = after = 0
    skipped = 0
    for path in job.inputs:
        name = _plain_pdf(job, path)
        out = job.scratch(name + '.small.pdf')
        run(['gs', '-sDEVICE=pdfwrite', '-dCompatibilityLevel=1.6', f'-dPDFSETTINGS={GS_PRESETS[preset]}',
             '-dNOPAUSE', '-dBATCH', '-dQUIET', '-dSAFER', f'-sOutputFile={out.name}', name], job.work, 900)
        size_in, size_out = path.stat().st_size, out.stat().st_size if out.exists() else 0
        if not size_out:
            raise ToolError(f'Ghostscript produced no output for {path.name}')
        if size_out >= size_in:
            skipped += 1
            out.unlink()
            continue
        before += size_in
        after += size_out
        job.publish(out, split_name(path.name)[0] + '-compressed', '.pdf')
    return _savings(before, after, skipped)


def _savings(before, after, skipped):
    parts = []
    if before:
        parts.append(f'{human_size(before)} → {human_size(after)}, saved {round(100 - after * 100 / before)}%')
    if skipped:
        parts.append(f'{skipped} already optimal, left as is')
    return {'summary': '; '.join(parts) or 'Nothing to do'}


def pdf_merge(job, options):
    if len(job.inputs) < 2:
        raise ToolError('Add at least two PDFs to merge')
    names = [_plain_pdf(job, path) for path in job.inputs]
    run(['qpdf', '--empty', '--pages', *names, '--', 'out.pdf'], job.work, 600, ok_codes=(0, 3))
    job.publish(job.scratch('out.pdf'), split_name(job.inputs[0].name)[0] + '-merged', '.pdf')
    return {'summary': f'{len(names)} PDFs merged'}


def pdf_images(job, options):
    image_format = choice(options, 'format', ('png', 'jpeg'), 'png')
    dpi = choice(options, 'dpi', ('72', '150', '300'), '150')
    name = _plain_pdf(job, job.inputs[0])
    stem = split_name(job.inputs[0].name)[0]
    folder = job.scratch('out')
    folder.mkdir()
    run(['pdftoppm', f'-{image_format}', '-r', dpi, name, str(folder / 'page')], job.work, 900)
    pages = sorted(folder.iterdir())
    if not pages:
        raise ToolError('No pages were rendered')
    job.publish(folder, stem + '-images')
    return {'summary': f'{len(pages)} image{"s" if len(pages) != 1 else ""}'}


def pdf_text(job, options):
    name = _plain_pdf(job, job.inputs[0])
    run(['pdftotext', '-layout', '-enc', 'UTF-8', name, 'out.txt'], job.work, 300)
    text = job.scratch('out.txt').read_text('utf-8', 'replace')
    job.publish(job.scratch('out.txt'), split_name(job.inputs[0].name)[0], '.txt')
    if not text.strip():
        return {'summary': 'No text layer found; the PDF may be scanned', 'text': ''}
    return {'text': text[:MAX_TEXT], 'summary': f'{len(text.split())} words' + (' (preview truncated)' if len(text) > MAX_TEXT else '')}


def _argfile(job, lines):
    path = job.scratch('qpdf-args')
    descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(descriptor, 'w', encoding='utf-8') as handle:
        handle.write('\n'.join(lines) + '\n')
    return '@' + path.name


def pdf_unlock(job, options):
    password = secret(options)
    name = _pdf(job, job.inputs[0])
    if not _encrypted(job, name):
        raise ToolError('This PDF is not password-protected')
    try:
        run(['qpdf', _argfile(job, [f'--password={password}']), '--decrypt', name, 'out.pdf'], job.work, 300, ok_codes=(0, 3))
    except ToolError as error:
        raise ToolError('Wrong password' if 'password' in str(error).lower() else str(error)) from None
    job.publish(job.scratch('out.pdf'), split_name(job.inputs[0].name)[0] + '-unlocked', '.pdf')
    return {}


def pdf_lock(job, options):
    password = secret(options)
    name = _plain_pdf(job, job.inputs[0])
    args = _argfile(job, ['--encrypt', f'--user-password={password}', f'--owner-password={password}', '--bits=256', '--'])
    run(['qpdf', name, args, 'out.pdf'], job.work, 300, ok_codes=(0, 3))
    job.publish(job.scratch('out.pdf'), split_name(job.inputs[0].name)[0] + '-protected', '.pdf')
    return {}


# --- Images ----------------------------------------------------------------

IMAGE_FORMATS = {'jpg': ('.jpg', 90), 'png': ('.png', None), 'webp': ('.webp', 85), 'avif': ('.avif', 60), 'heic': ('.heic', 70)}
ANIMATED = ('.gif', '.webp', '.apng')


def _magick(job, argv, timeout=180):
    run(['magick', *argv], job.work, timeout)


def _image_suffix(path):
    suffix = split_name(path.name)[1].lower()
    return '.jpg' if suffix in ('.jpeg', '.jpe') else suffix or '.png'


def image_convert(job, options):
    target = choice(options, 'format', tuple(IMAGE_FORMATS), 'jpg')
    suffix, quality = IMAGE_FORMATS[target]
    for path in job.inputs:
        name = job.link(path)
        source = name if suffix in ANIMATED else name + '[0]'
        flatten = ['-background', 'white', '-alpha', 'remove', '-alpha', 'off'] if target == 'jpg' else []
        out = job.scratch(name + '.out' + suffix)
        _magick(job, [source, '-auto-orient', *flatten, *(['-quality', str(quality)] if quality else []), out.name])
        job.publish(out, split_name(path.name)[0], suffix)
    return {}


def image_resize(job, options):
    size = choice(options, 'size', ('3840', '2560', '1920', '1280', '640', '50%'), '1920')
    geometry = size if size.endswith('%') else f'{size}x{size}>'
    label = 'half' if size == '50%' else size
    for path in job.inputs:
        name = job.link(path)
        suffix = _image_suffix(path)
        out = job.scratch(name + '.out' + suffix)
        _magick(job, [name, '-auto-orient', '-resize', geometry, out.name])
        job.publish(out, f'{split_name(path.name)[0]}-{label}', suffix)
    return {}


def image_compress(job, options):
    quality = int(choice(options, 'quality', ('60', '75', '85'), '75'))
    before = after = skipped = 0
    for path in job.inputs:
        name = job.link(path)
        suffix = _image_suffix(path)
        out = job.scratch(name + '.out' + suffix)
        if suffix == '.png':
            settings = ['-define', 'png:compression-level=9', '-define', 'png:compression-filter=5']
        elif suffix in ('.jpg', '.webp', '.avif', '.heic', '.jxl'):
            settings = ['-quality', str(quality)] + (['-sampling-factor', '4:2:0', '-interlace', 'JPEG'] if suffix == '.jpg' else [])
        else:
            raise ToolError(f'{path.name}: compression supports JPEG, PNG, WebP, AVIF and HEIC')
        _magick(job, [name, '-auto-orient', '-strip', *settings, out.name])
        size_in, size_out = path.stat().st_size, out.stat().st_size
        if size_out >= size_in:
            skipped += 1
            out.unlink()
            continue
        before += size_in
        after += size_out
        job.publish(out, split_name(path.name)[0] + '-compressed', suffix)
    return _savings(before, after, skipped)


def image_strip(job, options):
    for path in job.inputs:
        name = job.link(path)
        suffix = _image_suffix(path)
        out = job.scratch(name + '.out' + suffix)
        _magick(job, [name, '-auto-orient', '-strip', out.name])
        job.publish(out, split_name(path.name)[0] + '-clean', suffix)
    return {'summary': 'EXIF, GPS and other metadata removed'}


def image_rotate(job, options):
    transform = choice(options, 'transform', ('90', '180', '270', 'flip-h', 'flip-v'), '90')
    operation = {'flip-h': ['-flop'], 'flip-v': ['-flip']}.get(transform, ['-rotate', transform])
    for path in job.inputs:
        name = job.link(path)
        suffix = _image_suffix(path)
        out = job.scratch(name + '.out' + suffix)
        _magick(job, [name, '-auto-orient', *operation, out.name])
        job.publish(out, split_name(path.name)[0] + '-rotated', suffix)
    return {}


def image_pdf(job, options):
    names = [job.link(path) + '[0]' for path in job.inputs]
    _magick(job, [*names, '-auto-orient', 'out.pdf'], timeout=600)
    job.publish(job.scratch('out.pdf'), split_name(job.inputs[0].name)[0], '.pdf')
    return {'summary': f'{len(names)} page{"s" if len(names) != 1 else ""}'}


def ocr_languages():
    try:
        _, out, err = run(['tesseract', '--list-langs'], None, 15)
    except ToolError:
        return []
    lines = (out or err).decode('utf-8', 'replace').splitlines()
    return [line.strip() for line in lines[1:] if re.fullmatch(r'[A-Za-z_]+', line.strip()) and line.strip() != 'osd']


def image_ocr(job, options):
    languages = ocr_languages()
    language = options.get('language') or ('eng' if 'eng' in languages else (languages or ['eng'])[0])
    parts = language.split('+')
    if not all(part in languages for part in parts):
        raise ToolError(f'OCR language {language} is not installed')
    texts = []
    for path in job.inputs:
        _, out, _ = run(['tesseract', job.link(path), 'stdout', '-l', language], job.work, 180)
        texts.append(out.decode('utf-8', 'replace').strip())
    text = '\n\n'.join(part for part in texts if part)
    return {'text': text[:MAX_TEXT], 'summary': f'{len(text.split())} words recognized' if text else 'No text recognized'}


def image_barcode(job, options):
    found = []
    for path in job.inputs:
        code, out, _ = run(['zbarimg', '--quiet', '--raw', job.link(path)], job.work, 60, ok_codes=(0, 4))
        if code == 0:
            found.append(out.decode('utf-8', 'replace').strip())
    text = '\n'.join(found)
    return {'text': text[:MAX_TEXT], 'summary': f'{len(text.splitlines())} code{"s" if len(text.splitlines()) != 1 else ""} found' if text else 'No QR code or barcode found'}


# --- Video and audio -------------------------------------------------------

FFMPEG = ['ffmpeg', '-nostdin', '-hide_banner', '-loglevel', 'error']
AUDIO_FORMATS = {
    'mp3': ('.mp3', ['-c:a', 'libmp3lame', '-q:a', '2']),
    'm4a': ('.m4a', ['-c:a', 'aac', '-b:a', '192k']),
    'opus': ('.opus', ['-c:a', 'libopus', '-b:a', '128k']),
    'flac': ('.flac', ['-c:a', 'flac']),
    'wav': ('.wav', ['-c:a', 'pcm_s16le']),
}
CRF = {'high': '20', 'balanced': '24', 'small': '29'}


def _ffmpeg(job, argv, timeout=3600):
    try:
        run([*FFMPEG, *argv], job.work, timeout)
    except ToolError as error:
        if 'matches no streams' in error.detail:
            raise ToolError('This file has no audio track' if '0:a' in ' '.join(argv) else 'No usable stream found') from None
        raise


def media_gif(job, options):
    width = choice(options, 'width', ('320', '480', '640', '800'), '480')
    fps = choice(options, 'fps', ('10', '15', '24'), '15')
    graph = (f"fps={fps},scale='min(iw\\,{width})':-1:flags=lanczos,split[a][b];"
             '[a]palettegen=stats_mode=diff[p];[b][p]paletteuse=dither=bayer:bayer_scale=4')
    for path in job.inputs:
        name = job.link(path)
        out = job.scratch(name + '.gif')
        _ffmpeg(job, ['-i', name, '-vf', graph, '-loop', '0', out.name])
        job.publish(out, split_name(path.name)[0], '.gif')
    return {}


def media_video(job, options):
    quality = choice(options, 'quality', tuple(CRF), 'balanced')
    height = choice(options, 'height', ('keep', '1080', '720', '480'), 'keep')
    scale = [] if height == 'keep' else ['-vf', f"scale=-2:'min(ih\\,{height})'"]
    before = after = skipped = 0
    for path in job.inputs:
        name = job.link(path)
        out = job.scratch(name + '.out.mp4')
        _ffmpeg(job, ['-i', name, '-map', '0:v:0', '-map', '0:a:0?', *scale, '-c:v', 'libx264', '-preset', 'medium',
                      '-crf', CRF[quality], '-pix_fmt', 'yuv420p', '-c:a', 'aac', '-b:a', '128k', '-movflags', '+faststart', out.name])
        size_in, size_out = path.stat().st_size, out.stat().st_size
        same_container = split_name(path.name)[1].lower() == '.mp4'
        if same_container and size_out >= size_in:
            skipped += 1
            out.unlink()
            continue
        before += size_in
        after += size_out
        job.publish(out, split_name(path.name)[0] + ('-compressed' if same_container else ''), '.mp4')
    return _savings(before, after, skipped) if before > after or skipped else {}


def media_audio(job, options):
    target = choice(options, 'format', tuple(AUDIO_FORMATS), 'mp3')
    suffix, codec = AUDIO_FORMATS[target]
    for path in job.inputs:
        name = job.link(path)
        out = job.scratch(name + '.out' + suffix)
        _ffmpeg(job, ['-i', name, '-map', '0:a:0', '-vn', *codec, out.name])
        job.publish(out, split_name(path.name)[0], suffix)
    return {}


def media_trim(job, options):
    start = parse_time(options.get('start'), 'Start') or 0.0
    end = parse_time(options.get('end'), 'End')
    if end is not None and end <= start:
        raise ToolError('End must be after start')
    path = job.inputs[0]
    name = job.link(path)
    suffix = split_name(path.name)[1].lower() or '.mp4'
    out = job.scratch(name + '.trim' + suffix)
    window = ['-ss', f'{start:.3f}'] + (['-to', f'{end:.3f}'] if end is not None else [])
    _ffmpeg(job, [*window, '-i', name, '-map', '0', '-c', 'copy', out.name])
    job.publish(out, split_name(path.name)[0] + '-trimmed', suffix)
    return {'summary': 'Cut at the nearest keyframes, without re-encoding'}


# --- Archives and checksums ------------------------------------------------

def archive_extract(job, options):
    password = options.get('password') or ''
    if password and ('\n' in password or '\r' in password):
        raise ToolError('The password cannot contain line breaks')
    for path in job.inputs:
        stem, suffix = split_name(path.name)
        target = job.scratch('out-' + str(len(job.outputs)))
        target.mkdir()
        if suffix.lower() in TAR_SUFFIXES:
            run(['tar', '-xf', job.link(path), '-C', target.name, '--no-same-owner', '--no-same-permissions'], job.work, 900)
        else:
            stdin = (password + '\n').encode('utf-8') if password else None
            try:
                run(['7z', 'x', '-y', '-bd', '-bso0', '-bsp0', f'-o{target.name}', job.link(path)], job.work, 900, stdin=stdin)
            except ToolError as error:
                message = str(error) + error.detail
                if 'password' in message.lower() or 'Break signaled' in message:
                    raise ToolError(f'{path.name} is encrypted; enter its password' if not password else 'Wrong password') from None
                raise
        entries = list(target.iterdir())
        if not entries:
            raise ToolError(f'{path.name} is empty')
        if len(entries) == 1 and entries[0].is_dir() and not entries[0].is_symlink():
            job.publish(entries[0], entries[0].name)
        else:
            job.publish(target, stem)
    return {}


def archive_create(job, options):
    archive_format = choice(options, 'format', ('zip', '7z', 'tar.zst'), 'zip')
    source = job.scratch('src')
    source.mkdir()
    names = []
    for path in job.inputs:
        stem, suffix = split_name(path.name)
        name = path.name
        for index in range(2, 1000):
            if name not in names:
                break
            name = f'{stem} ({index}){suffix}'
        job.link(path, f'src/{name}')
        names.append(name)
    out = job.scratch('out.' + archive_format)
    if archive_format == 'tar.zst':
        run(['tar', '--zstd', '-h', '-cf', str(out), '-C', str(source), '--', *names], job.work, 1800)
    else:
        run(['7z', 'a', f'-t{archive_format}', '-bd', '-bso0', '-bsp0', str(out), '--', *names], source, 1800)
    stem = split_name(job.inputs[0].name)[0] if len(job.inputs) == 1 else 'Archive'
    job.publish(out, stem, '.' + archive_format)
    return {'summary': f'{len(names)} file{"s" if len(names) != 1 else ""} packed'}


HASHES = ('sha256', 'sha1', 'md5', 'sha512', 'blake2b')


def checksum(job, options, text=None):
    algorithm = choice(options, 'algorithm', HASHES, 'sha256')
    expected = re.sub(r'\s+', '', str(options.get('expected') or '')).lower()
    lines = []
    digests = []
    for path in job.inputs:
        digest = hashlib.new(algorithm)
        with open(path, 'rb') as handle:
            for chunk in iter(lambda: handle.read(1024 * 1024), b''):
                digest.update(chunk)
        digests.append(digest.hexdigest())
        lines.append(f'{digests[-1]}  {path.name}')
    if text is not None:
        digests.append(hashlib.new(algorithm, text.encode('utf-8')).hexdigest())
        lines.append(digests[-1])
    result = {'text': '\n'.join(lines)}
    if expected:
        result['summary'] = 'Match' if expected in digests else 'No match'
        result['match'] = expected in digests
    return result


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
