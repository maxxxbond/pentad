import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { existsSync } from 'node:fs';
import { mkdir, mkdtemp, readFile, rm, symlink } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';

const repo = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const { version } = JSON.parse(await readFile(path.join(repo, 'package.json'), 'utf8'));
const name = `pentad-${version}`;

function run(command, args, options = {}) {
  const result = spawnSync(command, args, { encoding: 'utf8', ...options });
  assert.equal(result.status, 0, `${command} ${args.join(' ')}\n${result.stdout}${result.stderr}`);
  return result.stdout;
}

test('release tarball is reproducible and installs without Node.js', async t => {
  const work = await mkdtemp(path.join(tmpdir(), 'pentad-release-test-'));
  t.after(() => rm(work, { recursive: true, force: true }));
  const env = { ...process.env, SOURCE_DATE_EPOCH: '1700000000' };
  for (const output of ['first', 'second']) {
    run(process.execPath, [path.join(repo, 'scripts/package-release.mjs'), '--output', path.join(work, output)], { env });
  }
  const archive = await readFile(path.join(work, 'first', `${name}.tar.gz`));
  assert.deepEqual(archive, await readFile(path.join(work, 'second', `${name}.tar.gz`)));
  const checksum = await readFile(path.join(work, 'first', `${name}.tar.gz.sha256`), 'utf8');
  assert.equal(checksum, `${createHash('sha256').update(archive).digest('hex')}  ${name}.tar.gz\n`);

  const listing = run('tar', ['-tzf', path.join(work, 'first', `${name}.tar.gz`)]).split('\n');
  for (const file of ['runtime/shell.qml', 'runtime/builtin-registry.json', 'runtime/helpers/pentad_doctor.py',
    'packaging/install.sh', 'scripts/pentad', 'LICENSE']) {
    assert.ok(listing.includes(`${name}/${file}`), `${file} is packaged`);
  }
  assert.ok(!listing.some(entry => entry.includes('__pycache__') || entry.startsWith(`${name}/quickshell/`)));

  run('tar', ['-xzf', path.join(work, 'first', `${name}.tar.gz`), '-C', work]);
  // Only the programs install.sh uses, so a hidden build step would fail for lack of node.
  const bin = path.join(work, 'bin');
  await mkdir(bin);
  for (const tool of ['cat', 'chmod', 'cp', 'dirname', 'grep', 'id', 'install', 'mkdir', 'mktemp', 'mv', 'rm', 'rmdir']) {
    await symlink(run('sh', ['-c', 'command -v "$1"', 'sh', tool]).trim(), path.join(bin, tool));
  }
  const destdir = path.join(work, 'root');
  run(path.join(work, name, 'packaging/install.sh'), [],
    { env: { PATH: bin, HOME: work, TMPDIR: work, DESTDIR: destdir, PREFIX: '/usr' } });
  assert.ok(existsSync(path.join(destdir, 'usr/share/pentad/quickshell/shell.qml')));
  assert.ok(existsSync(path.join(destdir, 'usr/bin/pentad')));
});
