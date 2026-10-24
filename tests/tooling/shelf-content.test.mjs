import test from 'node:test';
import assert from 'node:assert/strict';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { mkdtemp, mkdir, readdir, readFile, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import http from 'node:http';

const exec = promisify(execFile);
const helper = path.resolve('tools/pentad_shelf_content.py');
async function run(request, env) {
    return await new Promise((resolve, reject) => {
        const worker = execFile('python3', [helper], { env: env || process.env, timeout: 10000 }, (error, stdout) => {
            if (error) reject(error); else { try { resolve(JSON.parse(stdout)); } catch (error) { reject(error); } }
        });
        worker.stdin.end(JSON.stringify(request));
    });
}

test('Pinterest HTML yields the offered original, preview and source without fetching', async () => {
    const pin = 'https://www.pinterest.com/pin/790592909625181445/';
    const result = await run({ operation: 'extract', offer: { uris: pin,
        html: `<a href="${pin}"><img alt="Arabic logo design" src="https://i.pinimg.com/236x/a.jpg" srcset="https://i.pinimg.com/236x/a.jpg 1x, https://i.pinimg.com/474x/a.jpg 2x, https://i.pinimg.com/originals/a.png 4x"></a>` } });
    assert.deepEqual(result.items[0], { kind: 'image', uri: pin, label: 'Arabic logo design',
        previewUrl: 'https://i.pinimg.com/236x/a.jpg', imageUrl: 'https://i.pinimg.com/originals/a.png' });
});

test('Spotify empty URI, UTF-16LE track fallback, bookmark labels and plain text', async () => {
    const url = 'https://open.spotify.com/track/7h2ABjmIKKbT7VBWFM2nZD';
    const plain = await run({ operation: 'extract', offer: { uris: '', text: url } });
    assert.equal(plain.items[0].kind, 'spotify');
    const custom = await run({ operation: 'extract', offer: { uris: '',
        spotifyHex: Buffer.from('spotify:track:7h2ABjmIKKbT7VBWFM2nZD', 'utf16le').toString('hex') } });
    assert.equal(custom.items[0].uri, url);
    const bookmark = await run({ operation: 'extract', offer: { uris: 'https://weather.com/forecast',
        html: '<a href="https://weather.com/forecast">Hourly Weather Forecast</a>' } });
    assert.equal(bookmark.items[0].label, 'Hourly Weather Forecast');
    const text = await run({ operation: 'extract', offer: { text: '<script>as plain text</script>' } });
    assert.equal(text.items[0].text, '<script>as plain text</script>');
    const invalid = await run({ operation: 'extract', offer: { html: '<img src="javascript:alert(1)">' } });
    assert.equal(invalid.ok, false);
});

test('explicit downloads validate images, use XDG downloads, avoid collisions and clean failed files', async t => {
    const scratch = await mkdtemp(path.join(tmpdir(), 'pentad-download-test-'));
    t.after(() => rm(scratch, { recursive: true, force: true }));
    const config = path.join(scratch, 'config');
    await mkdir(config);
    const directory = path.join(scratch, 'downloads');
    await writeFile(path.join(config, 'user-dirs.dirs'), `XDG_DOWNLOAD_DIR="${directory}"\n`);
    const env = { ...process.env, XDG_CONFIG_HOME: config };
    const image = Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1PeAAAADElEQVR4nGNom1YOAAM5AZS5D+zuAAAAAElFTkSuQmCC', 'base64');
    const server = http.createServer((req, res) => {
        if (req.url === '/large') { res.writeHead(200, { 'Content-Length': 60 * 1024 * 1024 }); res.end(); }
        else if (req.url === '/bad') { res.writeHead(200, { 'Content-Type': 'text/html' }); res.end('<html>login</html>'); }
        else if (req.url === '/truncated') { res.writeHead(200, { 'Content-Type': 'image/png' }); res.end(image.subarray(0, 40)); }
        else if (req.url === '/redirect') { res.writeHead(302, { Location: '/image' }); res.end(); }
        else { res.writeHead(200, { 'Content-Type': 'image/png' }); res.end(image); }
    });
    await new Promise((resolve, reject) => { server.once('error', reject); server.listen(0, '127.0.0.1', resolve); });
    t.after(() => new Promise(resolve => { server.closeAllConnections(); server.close(resolve); }));
    const base = `http://127.0.0.1:${server.address().port}`;
    const first = await run({ operation: 'download', url: base + '/redirect', label: 'Фото / test' }, env);
    assert.equal(first.ok, true, first.message);
    const second = await run({ operation: 'download', url: base + '/image', label: 'Фото / test' }, env);
    assert.equal(second.ok, true, second.message);
    assert.notEqual(first.uri, second.uri);
    assert.deepEqual(await readFile(new URL(first.uri)), image);
    assert.equal((await run({ operation: 'download', url: base + '/bad' }, env)).ok, false);
    assert.equal((await run({ operation: 'download', url: base + '/truncated' }, env)).ok, false);
    assert.match((await run({ operation: 'download', url: base + '/large' }, env)).message, /50 MiB/);
    assert.equal((await readdir(path.join(directory, 'Pentad'))).length, 2);
    // The Stash's own copy goes to its state directory, never to downloads, and is marked owned.
    const state = path.join(scratch, 'state');
    const cached = await run({ operation: 'cache', url: base + '/image', label: 'Фото' }, { ...env, XDG_STATE_HOME: state });
    assert.equal(cached.ok, true, cached.message);
    assert.equal(cached.owned, true);
    assert.equal(path.dirname(new URL(cached.uri).pathname), path.join(state, 'pentad', 'stash'));
    assert.deepEqual(await readFile(new URL(cached.uri)), image);
    assert.equal((await run({ operation: 'cache', url: base + '/bad' }, { ...env, XDG_STATE_HOME: state })).ok, false);
    assert.equal((await readdir(path.join(state, 'pentad', 'stash'))).length, 1);
    assert.equal((await readdir(path.join(directory, 'Pentad'))).length, 2);
});
