"""Image operations (conversion, OCR, barcodes) of the sidebar file tools.
"""
import re

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
