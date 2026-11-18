#!/usr/bin/env python3
"""Measure the resident worker against spec N1: start-up to hello, the round trip of an empty
op, OCR cold, warm-uncached and cached next to bare tesseract and the one-shot helper, and
`pdf.text` cold and cached on generated multi-MB PDFs.

Prints numbers and asserts nothing. Everything runs in a private temporary directory with its
own cache root; the user's cache and desktop are not touched. OCR is skipped when tesseract
is missing; ImageMagick (`magick`) is used to draw test text when present. The PDF part is
skipped without pdftotext or qpdf; its PDFs are written by hand (a line of text plus an
incompressible image), so it needs no PDF library.
"""
import json
import os
import shutil
import statistics
import struct
import subprocess
import sys
import tempfile
import time
import zlib
from pathlib import Path
from urllib.parse import quote

REPO = Path(__file__).resolve().parents[1]
WORKER = REPO / 'tools' / 'pentad_worker.py'
ONE_SHOT = REPO / 'tools' / 'pentad_file_tool.py'


def uri(path):
    return 'file://' + quote(str(path), safe='/')


class Worker:
    def __init__(self, cache_root):
        started = time.perf_counter()
        self.process = subprocess.Popen([sys.executable, '-I', str(WORKER), '--serve', '--cache-root', str(cache_root)],
                                        stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
        hello = json.loads(self.process.stdout.readline())
        self.start_ms = (time.perf_counter() - started) * 1000
        if hello.get('type') != 'hello' or hello.get('protocol') != 1:
            raise SystemExit(f'unexpected hello: {hello}')
        self.serial = 0

    def call(self, op, payload=None):
        self.serial += 1
        line = json.dumps({'type': 'request', 'id': self.serial, 'op': op, 'payload': payload or {}, 'timeoutMs': 120000})
        started = time.perf_counter()
        self.process.stdin.write(line.encode() + b'\n')
        self.process.stdin.flush()
        while True:
            message = json.loads(self.process.stdout.readline())
            if message.get('type') == 'result' and message.get('id') == self.serial:
                return (time.perf_counter() - started) * 1000, message['result']

    def close(self):
        self.process.stdin.close()
        self.process.wait(timeout=10)


def plain_png(path, width, height, seed):
    """A white PNG with a few dark bars, so it needs no image library."""
    rows = []
    for y in range(height):
        row = bytearray(b'\x00')
        for x in range(width):
            dark = (y // 12) % 3 == 1 and ((x + seed * 7) // 9) % 4 != 0
            row += b'\x20' if dark else b'\xff'
        rows.append(bytes(row))
    def chunk(kind, data):
        return struct.pack('>I', len(data)) + kind + data + struct.pack('>I', zlib.crc32(kind + data) & 0xffffffff)
    data = b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', width, height, 8, 0, 0, 0, 0))
    data += chunk(b'IDAT', zlib.compress(b''.join(rows))) + chunk(b'IEND', b'')
    path.write_bytes(data)


def text_png(path, text, seed):
    if shutil.which('magick'):
        result = subprocess.run(['magick', '-size', '1200x240', 'xc:white', '-fill', 'black', '-pointsize', '42',
                                 '-annotate', '+30+90', text, '-annotate', '+30+170', f'line two {seed}', str(path)],
                                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=30)
        if result.returncode == 0 and path.exists():
            return 'magick'
    plain_png(path, 600, 160, seed)
    return 'plain'


def big_pdf(path, image_bytes):
    """A one-page PDF with a line of text and an uncompressed random grey image of about
    `image_bytes`, so the file is large and its text is known."""
    side = int(image_bytes ** 0.5)
    pixels = os.urandom(side * side)
    content = b'BT /F1 24 Tf 72 720 Td (Pentad worker bench pdf text) Tj ET q 400 0 0 400 100 200 cm /Im1 Do Q'
    objects = [
        b'<< /Type /Catalog /Pages 2 0 R >>',
        b'<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
        b'<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 4 0 R '
        b'/Resources << /Font << /F1 5 0 R >> /XObject << /Im1 6 0 R >> >> >>',
        b'<< /Length %d >>\nstream\n' % len(content) + content + b'\nendstream',
        b'<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>',
        b'<< /Type /XObject /Subtype /Image /Width %d /Height %d /ColorSpace /DeviceGray '
        b'/BitsPerComponent 8 /Length %d >>\nstream\n' % (side, side, len(pixels)) + pixels + b'\nendstream',
    ]
    data = bytearray(b'%PDF-1.4\n%\xe2\xe3\xcf\xd3\n')
    offsets = []
    for number, body in enumerate(objects, start=1):
        offsets.append(len(data))
        data += b'%d 0 obj\n' % number + body + b'\nendobj\n'
    xref = len(data)
    data += b'xref\n0 %d\n0000000000 65535 f \n' % (len(objects) + 1)
    data += b''.join(b'%010d 00000 n \n' % offset for offset in offsets)
    data += b'trailer\n<< /Size %d /Root 1 0 R >>\nstartxref\n%d\n%%%%EOF\n' % (len(objects) + 1, xref)
    path.write_bytes(bytes(data))


def bench_pdf(root, cache_root):
    if not (shutil.which('pdftotext') and shutil.which('qpdf')):
        print('PDF text                  skipped: pdftotext or qpdf is not installed')
        return
    paths = []
    for megabytes in (8, 64):
        path = root / f'bench-{megabytes}.pdf'
        big_pdf(path, megabytes * 1024 * 1024)
        paths.append(path)
    # The worker trusts a file's stat key only once its change time is a few seconds old.
    time.sleep(3.5)
    worker = Worker(cache_root)
    for path in paths:
        size = path.stat().st_size / (1024 * 1024)
        cold_ms, cold = worker.call('pdf.text', {'uri': uri(path)})
        if not cold.get('ok'):
            print(f'PDF text failed: {cold}')
            break
        print(f'PDF text {size:4.0f} MiB cold     {cold_ms:7.2f} ms   cached={cold["cached"]}   '
              f'text={cold["value"]["text"].strip()[:32]!r}')
        cached = []
        for _ in range(30):
            elapsed, result = worker.call('pdf.text', {'uri': uri(path)})
            if not result.get('cached'):
                print(f'expected a cache hit, got {result}')
                break
            cached.append(elapsed)
        if cached:
            print(f'PDF text {size:4.0f} MiB cached   {summary(cached)}')
    worker.close()


def summary(samples):
    ordered = sorted(samples)
    p95 = ordered[min(len(ordered) - 1, int(round(0.95 * (len(ordered) - 1))))]
    return f'median {statistics.median(ordered):7.2f} ms   p95 {p95:7.2f} ms   min {ordered[0]:7.2f} ms   (n={len(ordered)})'


def main():
    print(f'python {sys.version.split()[0]}, worker {WORKER.relative_to(REPO)}')
    with tempfile.TemporaryDirectory(prefix='pentad-bench-') as directory:
        root = Path(directory)
        cache_root = root / 'cache'

        starts = []
        for _ in range(5):
            worker = Worker(cache_root)
            starts.append(worker.start_ms)
            worker.close()
        print(f'start to hello            {summary(starts)}')

        worker = Worker(cache_root)
        for _ in range(20):
            worker.call('worker.stats')
        trips = [worker.call('worker.stats')[0] for _ in range(300)]
        print(f'empty op round trip       {summary(trips)}')
        bench_pdf(root, cache_root)

        if not shutil.which('tesseract'):
            print('OCR                       skipped: tesseract is not installed')
            worker.close()
            return 0

        images = []
        for index in range(8):
            path = root / f'bench-{index}.png'
            kind = text_png(path, f'Pentad worker bench {index} capture transform route', index)
            images.append(path)
        print(f'test images               {kind}, {images[0].stat().st_size} bytes')
        payload = {'language': 'eng', 'psm': 6, 'filterInstalled': True}

        cold_ms, cold = worker.call('image.ocr', dict(payload, uri=uri(images[0])))
        if not cold.get('ok'):
            print(f'OCR failed: {cold}')
            worker.close()
            return 0
        print(f'OCR cold (first request)  {cold_ms:7.2f} ms   cached={cold["cached"]}   text={cold["value"]["text"][:40]!r}')

        # Interleaved, so CPU frequency drift affects both series alike.
        warm, bare = [], []
        for path in images[1:]:
            started = time.perf_counter()
            subprocess.run(['tesseract', str(path), 'stdout', '-l', 'eng', '--psm', '6'], stdout=subprocess.PIPE,
                           stderr=subprocess.DEVNULL, check=False, timeout=120)
            bare.append((time.perf_counter() - started) * 1000)
            warm.append(worker.call('image.ocr', dict(payload, uri=uri(path)))[0])
        print(f'OCR warm, not cached      {summary(warm)}')
        print(f'bare tesseract            {summary(bare)}')
        print(f'worker overhead           {statistics.median(warm) - statistics.median(bare):7.2f} ms (median warm - median bare)')

        cached = []
        for _ in range(100):
            elapsed, result = worker.call('image.ocr', dict(payload, uri=uri(images[0])))
            if not result.get('cached'):
                print(f'expected a cache hit, got {result}')
                break
            cached.append(elapsed)
        if cached:
            print(f'OCR cached                {summary(cached)}')
        stats = worker.call('worker.stats')[1]['value']['cache']
        print(f'cache                     {stats["entries"]} entries, {stats["bytes"]} bytes, {stats["hits"]} hits, {stats["misses"]} misses')
        worker.close()

        one_shot = []
        request = json.dumps({'operation': 'image.ocr', 'inputs': [uri(images[1])], 'options': {'language': 'eng'}}).encode()
        for _ in range(5):
            started = time.perf_counter()
            subprocess.run([sys.executable, '-I', str(ONE_SHOT)], input=request, stdout=subprocess.DEVNULL,
                           stderr=subprocess.DEVNULL, check=False, timeout=120)
            one_shot.append((time.perf_counter() - started) * 1000)
        print(f'one-shot helper OCR       {summary(one_shot)}')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
