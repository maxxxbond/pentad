#!/usr/bin/env node
import { spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { cp, mkdir, mkdtemp, readFile, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { gzipSync } from 'node:zlib';

const repo = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const args = process.argv.slice(2);
if (args.length && (args.length !== 2 || args[0] !== '--output')) {
  console.error('Usage: node scripts/package-release.mjs [--output DIRECTORY]');
  process.exit(2);
}
const output = path.resolve(args.length ? args[1] : path.join(repo, 'dist/release'));
const { version } = JSON.parse(await readFile(path.join(repo, 'package.json'), 'utf8'));
const name = `pentad-${version}`;
// The tarball reproduces from the commit time; SOURCE_DATE_EPOCH overrides it.
const git = spawnSync('git', ['-C', repo, 'log', '-1', '--format=%ct'], { encoding: 'utf8' });
const epoch = process.env.SOURCE_DATE_EPOCH || (git.status === 0 && git.stdout.trim()) || String(Math.floor(Date.now() / 1000));

function run(command, commandArgs) {
  const result = spawnSync(command, commandArgs, { stdio: ['ignore', 'inherit', 'inherit'] });
  if (result.error) throw result.error;
  if (result.status !== 0) throw new Error(`${command} exited with ${result.status}`);
}

const work = await mkdtemp(path.join(tmpdir(), 'pentad-release-'));
try {
  const root = path.join(work, name);
  // The same paths as in the repository, so packaging/install.sh works unchanged; runtime/ replaces the build.
  run(process.execPath, [path.join(repo, 'scripts/build-quickshell.mjs'), '--output', path.join(root, 'runtime')]);
  for (const file of ['README.md', 'LICENSE', 'TRADEMARK.md', 'LICENSES', 'packaging/install.sh', 'packaging/README.md', 'scripts/pentad']) {
    await cp(path.join(repo, file), path.join(root, file), { recursive: true });
  }
  const tarball = path.join(work, `${name}.tar`);
  run('tar', ['--create', '--file', tarball, '--directory', work, '--sort=name', '--owner=0', '--group=0',
    '--numeric-owner', `--mtime=@${epoch}`, '--mode=u+rwX,go+rX,go-w', '--format=posix',
    '--pax-option=exthdr.name=%d/PaxHeaders/%f,delete=atime,delete=ctime', name]);
  const archive = gzipSync(await readFile(tarball), { level: 9 });
  await mkdir(output, { recursive: true });
  const target = path.join(output, `${name}.tar.gz`);
  await writeFile(target, archive);
  await writeFile(`${target}.sha256`, `${createHash('sha256').update(archive).digest('hex')}  ${name}.tar.gz\n`);
  console.log(`Packaged ${target}`);
} finally {
  await rm(work, { recursive: true, force: true });
}
