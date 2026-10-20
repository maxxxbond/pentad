import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { copyFile, mkdir, mkdtemp, readFile, readdir, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import test from 'node:test';

const repo = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const delay = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
async function until(predicate) {
  const deadline = Date.now() + 8000;
  while (Date.now() < deadline) { if (await predicate()) return; await delay(25); }
  assert.fail('Timed out waiting for development workflow');
}
function launch(command, args, cwd) {
  const child = spawn(command, args, { cwd, stdio: ['ignore', 'pipe', 'pipe'] });
  child.output = '';
  child.stdout.on('data', (chunk) => { child.output += chunk; });
  child.stderr.on('data', (chunk) => { child.output += chunk; });
  child.finished = new Promise((resolve, reject) => {
    child.once('error', reject);
    child.once('close', (code, signal) => resolve({ code, signal }));
  });
  return child;
}

async function fixture() {
  const root = await mkdtemp(path.join(tmpdir(), 'pentad-dev-test-'));
  for (const directory of ['scripts', 'quickshell', 'tools', 'LICENSES', 'instances']) await mkdir(path.join(root, directory));
  await writeFile(path.join(root, 'LICENSE'), 'fixture');
  for (const file of ['dev-quickshell.mjs', 'check-quickshell.mjs']) await copyFile(path.join(repo, 'scripts', file), path.join(root, 'scripts', file));
  await writeFile(path.join(root, 'quickshell/shell.qml'), 'first');
  await writeFile(path.join(root, 'scripts/build-quickshell.mjs'), `
import { mkdir, readFile, writeFile } from 'node:fs/promises';
import path from 'node:path';
const text = await readFile('quickshell/shell.qml', 'utf8');
if (text === 'broken') { console.error('fixture build failed'); process.exit(1); }
const output = process.argv[process.argv.indexOf('--output') + 1];
await mkdir(output, { recursive: true });
await writeFile(path.join(output, 'shell.qml'), text);
`);
  const binary = path.join(root, 'fake-qs');
  await writeFile(binary, `#!/usr/bin/env node
const fs = require('node:fs');
const path = require('node:path');
const args = process.argv.slice(2);
const registry = path.join(__dirname, 'instances');
if (args.includes('--version')) { console.log('Quickshell 0.3.2'); process.exit(0); }
const config = args.includes('--path') ? path.join(args[args.indexOf('--path') + 1], 'shell.qml') : null;
if (args[0] === 'list') {
  const entries = fs.readdirSync(registry).map(name => JSON.parse(fs.readFileSync(path.join(registry, name), 'utf8'))).filter(entry => entry.config_path === config);
  if (!entries.length) { console.error('No running instances for ' + config); console.error('Use --all to list all instances.'); process.exit(0); }
  console.log(JSON.stringify(entries)); process.exit(0);
}
if (args[0] === 'kill') {
  const id = args[args.indexOf('--id') + 1];
  const entry = JSON.parse(fs.readFileSync(path.join(registry, id), 'utf8'));
  process.kill(entry.pid, 'SIGTERM'); process.exit(0);
}
const id = String(process.pid);
fs.writeFileSync(path.join(registry, id), JSON.stringify({ id, pid: process.pid, config_path: config }));
console.log('Configuration Loaded');
process.on('SIGTERM', () => { fs.rmSync(path.join(registry, id), { force: true }); process.exit(0); });
setInterval(() => {}, 1000);
`, { mode: 0o700 });
  return { root, binary };
}

test('live development replaces only Pentad, watches saves, preserves failed builds, and cleans up', { timeout: 30000 }, async () => {
  const { root, binary } = await fixture();
  const output = path.join(root, 'dist/quickshell');
  await mkdir(output, { recursive: true });
  await writeFile(path.join(output, 'shell.qml'), 'old');
  const other = launch(binary, ['--path', path.join(root, 'another-shell')], root);
  const prior = launch(binary, ['--path', output], root);
  let dev;
  try {
    await until(() => other.output.includes('Configuration Loaded') && prior.output.includes('Configuration Loaded'));
    dev = launch(process.execPath, ['scripts/dev-quickshell.mjs', '--qs', binary], root);
    await until(() => dev.output.includes('Configuration Loaded'));
    assert.equal((await prior.finished).code, 0);
    assert.equal(other.exitCode, null);
    assert.equal(await readFile(path.join(output, 'shell.qml'), 'utf8'), 'first');
    const duplicate = launch(process.execPath, ['scripts/dev-quickshell.mjs', '--qs', binary], root);
    assert.equal((await duplicate.finished).code, 1);
    assert.match(duplicate.output, /Another Pentad development watcher/);

    await writeFile(path.join(root, 'quickshell/shell.qml'), 'second');
    await until(async () => (await readFile(path.join(output, 'shell.qml'), 'utf8').catch(() => '')) === 'second');
    await until(() => dev.output.split('Configuration Loaded').length === 3);
    const beforeFailure = (await readdir(path.join(root, 'instances'))).sort();
    await writeFile(path.join(root, 'quickshell/shell.qml'), 'broken');
    await until(() => dev.output.includes('fixture build failed'));
    assert.equal(await readFile(path.join(output, 'shell.qml'), 'utf8'), 'second');
    assert.deepEqual((await readdir(path.join(root, 'instances'))).sort(), beforeFailure);

    await writeFile(path.join(root, 'quickshell/shell.qml'), 'recovered');
    await until(() => dev.output.split('Configuration Loaded').length === 4);
    assert.equal(await readFile(path.join(output, 'shell.qml'), 'utf8'), 'recovered');
    dev.kill('SIGINT');
    assert.equal((await dev.finished).code, 0, dev.output);
    await until(async () => (await readdir(path.join(root, 'instances'))).length === 1);
    assert.equal(other.exitCode, null);
    assert.deepEqual(await readdir(path.join(root, 'instances')), [String(other.pid)]);
    assert.equal((await readdir(path.join(root, 'dist'))).includes('.pentad-dev.lock'), false);
  } finally {
    if (dev && dev.exitCode === null) { dev.kill('SIGINT'); await dev.finished; }
    for (const child of [prior, other]) if (child.exitCode === null) { child.kill('SIGTERM'); await child.finished; }
    await rm(root, { recursive: true, force: true });
  }
});

test('one-time development restart reports build failure and releases its lock', { timeout: 10000 }, async () => {
  const { root, binary } = await fixture();
  try {
    await writeFile(path.join(root, 'quickshell/shell.qml'), 'broken');
    const dev = launch(process.execPath, ['scripts/dev-quickshell.mjs', '--qs', binary, '--once'], root);
    assert.equal((await dev.finished).code, 1);
    assert.match(dev.output, /fixture build failed/);
    assert.equal((await readdir(path.join(root, 'dist'))).includes('.pentad-dev.lock'), false);
  } finally { await rm(root, { recursive: true, force: true }); }
});

test('development starts when Quickshell returns text instead of an empty JSON list', { timeout: 10000 }, async () => {
  const { root, binary } = await fixture();
  let dev;
  try {
    const output = path.join(root, 'dist/quickshell');
    await mkdir(output, { recursive: true });
    await writeFile(path.join(output, 'shell.qml'), 'old');
    dev = launch(process.execPath, ['scripts/dev-quickshell.mjs', '--qs', binary], root);
    await until(() => dev.output.includes('Configuration Loaded'));
    assert.equal(await readFile(path.join(output, 'shell.qml'), 'utf8'), 'first');
    dev.kill('SIGINT');
    assert.equal((await dev.finished).code, 0, dev.output);
    assert.deepEqual(await readdir(path.join(root, 'instances')), []);
  } finally {
    if (dev && dev.exitCode === null) { dev.kill('SIGINT'); await dev.finished; }
    await rm(root, { recursive: true, force: true });
  }
});
