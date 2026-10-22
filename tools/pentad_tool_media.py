"""Video and audio operations of the sidebar file tools.
"""
from pentad_tool_core import ToolError, _savings, choice, parse_time, run, split_name


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
