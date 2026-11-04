#!/usr/bin/env node
// Rebuilds the compiled shaders in quickshell/assets/shaders: each <name>.frag becomes the
// <name>.frag.qsb next to it. Run it after editing a .frag source and commit both files; the
// .qsb files ship as they are, so building or installing Pentad never needs the Qt Shader Tools.
//
//   node scripts/build-shaders.mjs [name.frag ...]   (no names: every .frag in the folder)
//
// The tool is /usr/lib/qt6/bin/qsb or the first qsb on PATH; QSB=/path/to/qsb overrides both.
import { spawnSync } from 'node:child_process';
import { existsSync, readdirSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const repo = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const directory = path.join(repo, 'quickshell/assets/shaders');
// OpenGL ES 2 and desktop OpenGL, Direct3D 11 and Metal; qsb always adds SPIR-V for Vulkan.
const targets = ['--glsl', '100 es,120,150', '--hlsl', '50', '--msl', '12'];

function qsbPath() {
  if (process.env.QSB) return process.env.QSB;
  for (const candidate of ['/usr/lib/qt6/bin/qsb', '/usr/lib64/qt6/bin/qsb', '/usr/lib/x86_64-linux-gnu/qt6/bin/qsb'])
    if (existsSync(candidate)) return candidate;
  return 'qsb';
}

const requested = process.argv.slice(2);
const names = requested.length ? requested : readdirSync(directory).filter(name => name.endsWith('.frag')).sort();
const qsb = qsbPath();
let failed = 0;
for (const name of names) {
  if (path.basename(name) !== name || !name.endsWith('.frag') || !existsSync(path.join(directory, name))) {
    console.error(`Not a shader source in quickshell/assets/shaders: ${name}`);
    failed++;
    continue;
  }
  const source = path.join(directory, name);
  const result = spawnSync(qsb, [...targets, '-o', `${source}.qsb`, source], { stdio: 'inherit', timeout: 60000 });
  if (result.error || result.status !== 0) {
    console.error(`qsb failed for ${name}: ${result.error ? result.error.message : `exit ${result.status}`}`);
    failed++;
  } else console.log(`Built quickshell/assets/shaders/${name}.qsb`);
}
process.exitCode = failed ? 1 : 0;
