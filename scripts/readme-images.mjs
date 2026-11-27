#!/usr/bin/env node
// Renders the README images from the `showcase` fixture in the isolated headless session and writes
// optimised copies to docs/assets/readme. Needs ImageMagick; never touches the running shell.
import { spawnSync } from 'node:child_process';
import { mkdir, mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const repo = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const output = path.join(repo, 'docs/assets/readme');

function run(command, args) {
  const result = spawnSync(command, args, { cwd: repo, stdio: 'inherit' });
  if (result.error) throw result.error;
  if (result.status !== 0) throw new Error(`${command} exited with ${result.status}`);
}

const work = await mkdtemp(path.join(tmpdir(), 'pentad-readme-images-'));
try {
  const report = path.join(work, 'showcase.json');
  // Scale 2 renders 2560x1600; downscaling keeps text crisp at the published size.
  run(process.execPath, [path.join(repo, 'scripts/test-quickshell-headless.mjs'), '--scenario', 'showcase',
    '--scale', '2', '--report', report]);
  await mkdir(output, { recursive: true });
  const strip = ['-strip', '-define', 'png:exclude-chunks=date,time'];
  // One image per scene, all at the published size. The media scene shows the real track with its cover and
  // no lyrics; the karaoke scene stays a fixture check only.
  const scenes = [['.rest.png', 'rest.png'], ['', 'control-center.png'], ['.tools.png', 'tools.png'],
    ['.screen-tools.png', 'screenshot-editor.png'], ['.spotlight.png', 'spotlight.png'], ['.media.png', 'media.png']];
  for (const [suffix, name] of scenes) {
    run('magick', [`${report}.png${suffix}`, '-resize', '1600x1000', ...strip, path.join(output, name)]);
  }
  console.log(`Wrote ${scenes.map(([, name]) => name).join(', ')} to ${path.relative(repo, output)}`);
} finally {
  await rm(work, { recursive: true, force: true });
}
