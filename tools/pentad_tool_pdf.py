"""PDF operations of the sidebar file tools.
"""
import os

from pentad_tool_core import MAX_TEXT, ToolError, _savings, choice, page_ranges, parse_pages, run, secret, split_name


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
