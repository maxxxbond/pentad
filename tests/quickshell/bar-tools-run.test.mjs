import test from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { chmodSync, mkdtempSync, readFileSync, rmSync, writeFileSync, existsSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { audioOutputScript, clipUtf8, fileUri, imageCaptureScript, ocrCopyScript, ocrScript, ocrTextBytes, qrScript, rulerScript, translateScript } from '../../quickshell/logic/bar-tools.mjs';

// Runs the real scripts in a private directory against the picked image, the way the Desktop service does.
// The clipboard, notifications, browser and curl are stand-ins that record what they receive, so nothing
// touches a display, the clipboard or the session bus.
const have = name => spawnSync('sh', ['-c', `command -v ${name}`]).status === 0;
const ready = ['magick', 'tesseract', 'zbarimg', 'qrencode', 'jq'].every(have);

function sandbox({ image } = {}) {
  const dir = mkdtempSync(path.join(tmpdir(), 'pentad-bar-tools-run-'));
  const bin = path.join(dir, 'bin');
  spawnSync('mkdir', ['-p', bin]);
  const stub = (name, body) => { writeFileSync(path.join(bin, name), `#!/bin/sh\n${body}\n`); chmodSync(path.join(bin, name), 0o755); };
  const picked = path.join(dir, 'picked.png');
  writeFileSync(picked, image);
  stub('wl-copy', `echo "$*" > '${dir}/clipboard.args'; cat > '${dir}/clipboard'`);
  stub('notify-send', `printf '%s\\n' "$*" >> '${dir}/notify'`);
  stub('xdg-open', `echo "$*" >> '${dir}/opened'`);
  stub('curl', `cat > '${dir}/curl.stdin'; echo "$*" > '${dir}/curl.args'; echo '{"translations":[{"text":"Привіт світ"}]}'`);
  const run = (script, args = [picked]) => spawnSync('sh', ['-c', script, 'pentad', ...args],
    { env: { ...process.env, PATH: `${bin}:${process.env.PATH}` }, encoding: 'utf8', timeout: 30000 });
  const read = name => existsSync(path.join(dir, name)) ? readFileSync(path.join(dir, name), 'utf8') : null;
  return { dir, bin, stub, run, read, picked, cleanup: () => rmSync(dir, { recursive: true, force: true }) };
}

const textImage = text => spawnSync('magick', ['-size', '600x120', 'xc:white', '-fill', 'black', '-pointsize', '56',
  '-annotate', '+20+80', text, 'png:-'], { encoding: 'buffer' }).stdout;
const qrImage = text => spawnSync('qrencode', ['-o', '-', '-s', '8', text], { encoding: 'buffer' }).stdout;

test('OCR copies the text of the picked image and tells the user', { skip: !ready }, () => {
  const box = sandbox({ image: textImage('Hello World') });
  try {
    const result = box.run(ocrScript('eng+ukr'));
    assert.equal(result.status, 0, result.stderr);
    assert.match(box.read('clipboard'), /Hello World/);
    assert.match(box.read('notify'), /Text copied/);
  } finally { box.cleanup(); }
});

test('an image without text reports it instead of copying nothing', { skip: !ready }, () => {
  const box = sandbox({ image: spawnSync('magick', ['-size', '200x80', 'xc:white', 'png:-'], { encoding: 'buffer' }).stdout });
  try {
    const result = box.run(ocrScript('eng'));
    assert.equal(result.status, 4);
    assert.equal(box.read('clipboard'), null);
    assert.match(box.read('notify'), /No text found/);
  } finally { box.cleanup(); }
});

test('the image capture puts the picked PNG on the clipboard', { skip: !ready }, () => {
  const image = textImage('Snippet');
  const box = sandbox({ image });
  try {
    const result = box.run(imageCaptureScript);
    assert.equal(result.status, 0, result.stderr);
    assert.match(box.read('clipboard.args'), /--type image\/png/);
    assert.deepEqual(readFileSync(path.join(box.dir, 'clipboard')), image);
  } finally { box.cleanup(); }
});

test('the QR scan copies the decoded text', { skip: !ready }, () => {
  const box = sandbox({ image: qrImage('https://example.test/pentad') });
  try {
    const result = box.run(qrScript);
    assert.equal(result.status, 0, result.stderr);
    assert.equal(box.read('clipboard'), 'https://example.test/pentad');
  } finally { box.cleanup(); }
});

test('an image without a code reports it', { skip: !ready }, () => {
  const box = sandbox({ image: textImage('no code here') });
  try {
    assert.equal(box.run(qrScript).status, 4);
    assert.match(box.read('notify'), /No code found/);
    assert.equal(box.read('clipboard'), null);
  } finally { box.cleanup(); }
});

test('translation sends the recognized text to DeepL with the key on stdin only', { skip: !ready }, () => {
  const box = sandbox({ image: textImage('Hello World') });
  try {
    const keyFile = path.join(box.dir, 'deepl.key');
    writeFileSync(keyFile, 'secret-key-123:fx\n');
    const result = box.run(translateScript({ target: 'UK', languages: 'eng', provider: 'deepl' }), [box.picked, keyFile]);
    assert.equal(result.status, 0, result.stderr);
    assert.equal(box.read('clipboard'), 'Привіт світ');
    assert.match(box.read('curl.stdin'), /DeepL-Auth-Key secret-key-123:fx/);
    const args = box.read('curl.args');
    assert.ok(!args.includes('secret-key-123'));
    assert.match(args, /api-free\.deepl\.com/);
    assert.match(args, /text=Hello World/);
    assert.match(args, /target_lang=UK/);
  } finally { box.cleanup(); }
});

test('translation without a key file asks for one', { skip: !ready }, () => {
  const box = sandbox({ image: textImage('Hello') });
  try {
    const result = box.run(translateScript({ target: 'UK', languages: 'eng', provider: 'deepl' }), [box.picked, '']);
    assert.equal(result.status, 3);
    assert.match(box.read('notify'), /API key/);
    assert.equal(box.read('curl.args'), null);
  } finally { box.cleanup(); }
});

test('the ruler copies the size it is given', { skip: !ready }, () => {
  const box = sandbox({ image: textImage('x') });
  try {
    const result = box.run(rulerScript, ['320x200']);
    assert.equal(result.status, 0, result.stderr);
    assert.equal(box.read('clipboard'), '320x200');
    assert.match(box.read('notify'), /Size copied 320x200 px/);
  } finally { box.cleanup(); }
});

test('the next audio output script switches the default sink and moves streams', { skip: !ready }, () => {
  const box = sandbox({ image: textImage('x') });
  try {
    box.stub('pactl', `case "$1 $2" in
  "get-default-sink ") echo sink-a;;
  "list short") if [ "$3" = sinks ]; then printf '1\\tsink-a\\tx\\n2\\tsink-b\\tx\\n'; else printf '7\\tx\\n8\\ty\\n'; fi;;
  "list sinks") printf 'Sink #1\\n\\tName: sink-a\\n\\tDescription: Speakers\\nSink #2\\n\\tName: sink-b\\n\\tDescription: Headphones\\n';;
  *) echo "$*" >> '${box.dir}/pactl.log';;
esac`);
    const result = box.run(audioOutputScript, []);
    assert.equal(result.status, 0, result.stderr);
    const log = box.read('pactl.log');
    assert.match(log, /set-default-sink sink-b/);
    assert.match(log, /move-sink-input 7 sink-b/);
    assert.match(log, /move-sink-input 8 sink-b/);
    assert.match(box.read('notify'), /Headphones/);
  } finally { box.cleanup(); }
});

test('a missing program is named in a notification instead of failing silently', { skip: !ready }, () => {
  const box = sandbox({ image: textImage('Hello') });
  try {
    // Only the stand-ins are on PATH, so tesseract is "not installed".
    const result = spawnSync('/bin/sh', ['-c', ocrScript('eng'), 'pentad', box.picked], { env: { PATH: box.bin }, encoding: 'utf8', timeout: 30000 });
    assert.equal(result.status, 7, result.stderr);
    assert.match(box.read('notify'), /Missing tool tesseract/);
    assert.equal(box.read('clipboard'), null);
  } finally { box.cleanup(); }
});

test('worker OCR copies the recognised text it gets as an argument, never as shell code', () => {
  const box = sandbox({ image: Buffer.from('') });
  try {
    const text = "Привіт $(touch pwned) `id` 'quote' \"double\"\nline two";
    const result = box.run(ocrCopyScript, [text]);
    assert.equal(result.status, 0, result.stderr);
    assert.equal(box.read('clipboard'), text);
    assert.match(box.read('notify'), /Text copied/);
    assert.equal(existsSync(path.join(box.dir, 'pwned')), false);
    assert.equal(existsSync('pwned'), false);
  } finally { box.cleanup(); }
});

test('recognised text is clipped to whole UTF-8 characters within one argv entry', () => {
  assert.ok(ocrTextBytes < 131072);
  assert.equal(clipUtf8('abc', 3), 'abc');
  assert.equal(clipUtf8('abcd', 3), 'abc');
  assert.equal(clipUtf8('їжак', 5), 'їж');
  assert.equal(clipUtf8('a😀b', 4), 'a');
  assert.equal(clipUtf8('a😀b', 5), 'a😀');
  const long = 'ї'.repeat(80000);
  assert.equal(Buffer.byteLength(clipUtf8(long, ocrTextBytes)), ocrTextBytes);
  assert.equal(fileUri('/tmp/pentad pick/a#b.png'), 'file:///tmp/pentad%20pick/a%23b.png');
});

test('no script selects an area or captures the screen itself any more', () => {
  for (const script of [ocrScript('eng'), ocrCopyScript, imageCaptureScript, qrScript, rulerScript, translateScript({ target: 'UK', languages: 'eng', provider: 'deepl' })]) {
    assert.doesNotMatch(script, /slurp|grim/);
  }
});
