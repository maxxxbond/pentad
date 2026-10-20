import test from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

test('screenshot modules import and execute in Qt JS without a GUI or shell', async t => {
  const compiler = spawnSync('c++', ['--version'], { encoding: 'utf8', timeout: 5000 });
  const qt = spawnSync('pkg-config', ['--cflags', '--libs', 'Qt6Qml', 'Qt6Core'], { encoding: 'utf8', timeout: 5000 });
  if (compiler.status !== 0 || qt.status !== 0) {
    t.skip('Requires a C++ compiler and Qt6Qml/Qt6Core development packages');
    return;
  }
  const repo = fileURLToPath(new URL('../../', import.meta.url));
  const temporary = await mkdtemp(path.join(tmpdir(), 'pentad-screenshot-qt-'));
  try {
    const binary = path.join(temporary, 'screenshot-js-qt');
    const env = Object.assign({}, process.env);
    for (const key of ['WAYLAND_DISPLAY', 'DISPLAY', 'DBUS_SESSION_BUS_ADDRESS', 'HYPRLAND_INSTANCE_SIGNATURE']) delete env[key];
    Object.assign(env, { HOME: temporary, XDG_CONFIG_HOME: temporary, XDG_CACHE_HOME: temporary, XDG_STATE_HOME: temporary });
    const build = spawnSync('c++', ['-std=c++17', '-fPIC', path.join(repo, 'tests/tools/screenshot-js-qt.cpp'),
      '-o', binary, ...qt.stdout.trim().split(/\s+/)], { encoding: 'utf8', timeout: 60000, env });
    assert.equal(build.status, 0, build.error?.message || build.stderr);
    const result = spawnSync(binary, [repo], { encoding: 'utf8', timeout: 15000, env });
    assert.equal(result.status, 0, result.error?.message || result.stderr);
    assert.match(result.stdout, /Qt screenshot modules: passed/);
  } finally {
    await rm(temporary, { recursive: true, force: true });
  }
});
