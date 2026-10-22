"""Archive and checksum operations of the sidebar file tools.
"""
import hashlib
import re

from pentad_tool_core import TAR_SUFFIXES, ToolError, choice, run, split_name


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
