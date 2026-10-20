import test from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { mkdtemp, readFile, writeFile, rm } from 'node:fs/promises';
import { gunzipSync } from 'node:zlib';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

test('real emoji bundle searches in Qt JS without a shell or GUI', async t => {
  const qt = spawnSync('pkg-config', ['--cflags', '--libs', 'Qt6Qml', 'Qt6Core'], { encoding: 'utf8', timeout: 5000 });
  const compiler = spawnSync('c++', ['--version'], { encoding: 'utf8', timeout: 5000 });
  if (qt.status !== 0 || compiler.status !== 0) return t.skip('Requires Qt6Qml/Qt6Core and a C++ compiler');
  const repo = fileURLToPath(new URL('../../', import.meta.url));
  const temporary = await mkdtemp(path.join(tmpdir(), 'pentad-spotlight-qt-'));
  try {
    const env = { ...process.env, HOME: temporary, XDG_CONFIG_HOME: temporary,
      XDG_CACHE_HOME: temporary, XDG_STATE_HOME: temporary, XDG_RUNTIME_DIR: temporary };
    for (const key of ['WAYLAND_DISPLAY', 'DISPLAY', 'DBUS_SESSION_BUS_ADDRESS', 'HYPRLAND_INSTANCE_SIGNATURE']) delete env[key];
    const bundle = JSON.parse(await readFile(path.join(repo, 'quickshell/assets/spotlight/emoji.json'), 'utf8'));
    const records = Object.fromEntries(['en', 'de', 'uk'].map(locale =>
      [locale, JSON.parse(gunzipSync(Buffer.from(bundle.locales[locale], 'base64')).toString('utf8'))]));
    const fixture = path.join(temporary, 'emoji.json');
    await writeFile(fixture, JSON.stringify(records));
    const binary = path.join(temporary, 'spotlight-js-qt');
    const build = spawnSync('c++', ['-std=c++17', '-fPIC', path.join(repo, 'tests/tools/spotlight-js-qt.cpp'),
      '-o', binary, ...qt.stdout.trim().split(/\s+/)], { encoding: 'utf8', timeout: 60000, env });
    assert.equal(build.status, 0, build.error?.message || build.stderr);
    const result = spawnSync(binary, [repo, fixture], { encoding: 'utf8', timeout: 15000, env });
    assert.equal(result.status, 0, result.error?.message || result.stderr || result.stdout);
    assert.match(result.stdout, /Qt Spotlight emoji: passed/);
  } finally {
    await rm(temporary, { recursive: true, force: true });
  }
});
