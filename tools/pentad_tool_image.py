"""Image operations (conversion, OCR, barcodes) of the sidebar file tools.
"""
import re
import threading
import time

from pentad_tool_core import MAX_TEXT, ToolError, _savings, choice, run, split_name


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


# `tesseract --list-langs` costs a process start; the resident worker asks for it on every OCR
# request, so a successful listing is kept for a short while. Failures are not kept.
LANGUAGES_TTL = 60.0
_languages = {'at': None, 'value': []}
_languages_lock = threading.Lock()


def _list_ocr_languages():
    try:
        _, out, err = run(['tesseract', '--list-langs'], None, 15)
    except ToolError:
        return None
    lines = (out or err).decode('utf-8', 'replace').splitlines()
    return [line.strip() for line in lines[1:] if re.fullmatch(r'[A-Za-z_]+', line.strip()) and line.strip() != 'osd']


def ocr_languages(max_age=LANGUAGES_TTL):
    """Installed tesseract languages (without osd); [] when tesseract is missing or fails."""
    with _languages_lock:
        at = _languages['at']
        if at is not None and time.monotonic() - at < max_age:
            return list(_languages['value'])
    value = _list_ocr_languages()
    if value is None:
        return []
    with _languages_lock:
        _languages['at'] = time.monotonic()
        _languages['value'] = value
    return list(value)


def ocr_language(requested, languages, filter_installed=False):
    """Resolve the `-l` value. With `filter_installed` (the bar's behaviour) missing packs are
    dropped and nothing left falls back to the default; otherwise a missing pack is an error."""
    default = 'eng' if 'eng' in languages else (languages or ['eng'])[0]
    if requested in (None, ''):
        return default
    if not isinstance(requested, str) or len(requested) > 200:
        raise ToolError('Unsupported OCR language', reason='unsupported')
    parts = requested.split('+')
    if filter_installed:
        kept = list(dict.fromkeys(part for part in parts if part in languages))
        return '+'.join(kept) if kept else default
    if not all(part in languages for part in parts):
        raise ToolError(f'OCR language {requested} is not installed', reason='unavailable')
    return requested


def ocr_psm(value):
    """Tesseract page segmentation mode 0–13, or None for tesseract's default."""
    if value in (None, ''):
        return None
    if isinstance(value, str) and value.isdigit():
        value = int(value)
    if not isinstance(value, int) or isinstance(value, bool) or not 0 <= value <= 13:
        raise ToolError('Unsupported page segmentation mode', reason='unsupported')
    return value


def image_ocr(job, options):
    """Options: `language` ('eng', 'eng+ukr'), `filterInstalled` (drop missing packs), `psm`
    (the bar uses 6) and `dropBlankLines` (the bar strips whitespace-only lines)."""
    language = ocr_language(options.get('language'), ocr_languages(), options.get('filterInstalled') is True)
    psm = ocr_psm(options.get('psm'))
    texts = []
    for path in job.inputs:
        argv = ['tesseract', job.link(path), 'stdout', '-l', language] + (['--psm', str(psm)] if psm is not None else [])
        _, out, _ = run(argv, job.work, 180)
        texts.append(out.decode('utf-8', 'replace').strip())
    text = '\n\n'.join(part for part in texts if part)
    if options.get('dropBlankLines') is True:
        text = '\n'.join(line for line in text.splitlines() if line.strip())
    return {'text': text[:MAX_TEXT], 'summary': f'{len(text.split())} words recognized' if text else 'No text recognized'}


def image_barcode(job, options):
    found = []
    for path in job.inputs:
        code, out, _ = run(['zbarimg', '--quiet', '--raw', job.link(path)], job.work, 60, ok_codes=(0, 4))
        if code == 0:
            found.append(out.decode('utf-8', 'replace').strip())
    text = '\n'.join(found)
    return {'text': text[:MAX_TEXT], 'summary': f'{len(text.splitlines())} code{"s" if len(text.splitlines()) != 1 else ""} found' if text else 'No QR code or barcode found'}
