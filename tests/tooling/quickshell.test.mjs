import assert from 'node:assert/strict';
import { mkdtemp, mkdir, readdir, readFile, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import test from 'node:test';
import { fileURLToPath } from 'node:url';
import { meetsFloor, parseQtQuery, parseVersion } from '../../scripts/check-quickshell.mjs';
import { parseTestOutput, qmlRuntimeErrors } from '../../scripts/test-quickshell.mjs';

const repo = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const temporary = await mkdtemp(path.join(tmpdir(), 'pentad-tooling-test-'));
const run = (script, args = [], env = process.env) => spawnSync(process.execPath, [path.join(repo, script), ...args], { cwd: repo, encoding: 'utf8', env: { ...env }, timeout: 10000 });
const executable = async (file, contents) => {
  await writeFile(file, `#!/bin/sh\n${contents}\n`, { mode: 0o700 });
};

test.after(async () => rm(temporary, { recursive: true, force: true }));

test('version parser enforces the 0.3.2 floor', () => {
  assert.deepEqual(parseVersion('Quickshell 0.2.1 (revision old)'), [0, 2, 1]);
  assert.equal(meetsFloor(parseVersion('Quickshell 0.2.1')), false);
  assert.equal(meetsFloor(parseVersion('Quickshell 0.3.2')), true);
  assert.equal(meetsFloor(parseVersion('Quickshell 1.0.0')), true);
  assert.deepEqual(parseQtQuery('QT_VERSION:6.11.2\nQT_INSTALL_QML:/usr/lib/qt6/qml\nQT_INSTALL_BINS:/usr/lib/qt6/bin\n'), {
    QT_VERSION: '6.11.2', QT_INSTALL_QML: '/usr/lib/qt6/qml', QT_INSTALL_BINS: '/usr/lib/qt6/bin',
  });
});

test('CLI passes the selected root literally and rejects unsupported commands', async () => {
  const bin = path.join(temporary, 'cli-bin');
  const root = path.join(temporary, 'root with spaces');
  await mkdir(bin);
  await mkdir(root);
  const capture = path.join(temporary, 'qs-args');
  await executable(path.join(bin, 'qs'), 'if [ "$1" = "--version" ]; then echo "Quickshell 0.3.2"; exit 0; fi; printf "%s\\n" "${PENTAD_SAFE_MODE-}" "$@" > "$CAPTURE"');
  const env = { PATH: `${bin}:/usr/bin:/bin`, HOME: temporary, CAPTURE: capture };
  const started = spawnSync(path.join(repo, 'scripts/pentad'), ['start', '--path', root, '--safe-mode'], { encoding: 'utf8', env });
  assert.equal(started.status, 0, started.stderr);
  assert.equal(await readFile(capture, 'utf8'), `1\n--no-duplicate\n--path\n${root}\n`);
  const unsupported = spawnSync(path.join(repo, 'scripts/pentad'), ['settings'], { encoding: 'utf8', env });
  assert.equal(unsupported.status, 2);
  const ping = spawnSync(path.join(repo, 'scripts/pentad'), ['ping', '--path', root], { encoding: 'utf8', env });
  assert.equal(ping.status, 0, ping.stderr);
  assert.equal(await readFile(capture, 'utf8'), `\nipc\n--path\n${root}\ncall\npentad\nrequest\nping\n{}\n`);
});

test('CLI refuses to start an unsupported Quickshell before launch', async () => {
  const bin = path.join(temporary, 'old-cli-bin');
  const root = path.join(temporary, 'old-root');
  await mkdir(bin);
  await mkdir(root);
  const capture = path.join(temporary, 'old-qs-args');
  await executable(path.join(bin, 'qs'), 'if [ "$1" = "--version" ]; then echo "Quickshell 0.2.1"; exit 0; fi; echo launched > "$CAPTURE"');
  const result = spawnSync(path.join(repo, 'scripts/pentad'), ['start', '--path', root], { encoding: 'utf8', env: { PATH: `${bin}:/usr/bin:/bin`, HOME: temporary, CAPTURE: capture } });
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /below required 0\.3\.2/);
  await assert.rejects(readFile(capture));
});

test('lifecycle commands target the selected config and restart from a stopped state', async () => {
  const bin = path.join(temporary, 'lifecycle-bin');
  const root = path.join(temporary, 'lifecycle root');
  const capture = path.join(temporary, 'lifecycle-args');
  await mkdir(bin);
  await mkdir(root);
  await executable(path.join(bin, 'qs'), `
printf '%s\\n' CALL "$@" >> "$CAPTURE"
case "$1" in
  --version) echo 'Quickshell 0.3.2' ;;
  list) if [ -f "$CAPTURE.running" ]; then echo '[{"id":"pentad"}]'; else echo '[]'; fi ;;
  kill) rm -f "$CAPTURE.running" ;;
esac`);
  const env = { PATH: `${bin}:/usr/bin:/bin`, HOME: temporary, CAPTURE: capture };
  await writeFile(`${capture}.running`, 'running');
  let result = spawnSync(path.join(repo, 'scripts/pentad'), ['stop', '--path', root], { encoding: 'utf8', env });
  assert.equal(result.status, 0, result.stderr);
  assert.match(await readFile(capture, 'utf8'), new RegExp(`CALL\\nkill\\n--path\\n${root}\\n`));
  await writeFile(capture, '');
  result = spawnSync(path.join(repo, 'scripts/pentad'), ['restart', '--path', root], { encoding: 'utf8', env });
  assert.equal(result.status, 0, result.stderr);
  assert.equal(await readFile(capture, 'utf8'), `CALL\nlist\n--path\n${root}\n--json\nCALL\n--version\nCALL\n--no-duplicate\n--path\n${root}\n`);
  for (const [command, argv] of [['status', ['list', '--path', root]], ['logs', ['log', '--follow', '--path', root]]]) {
    await writeFile(capture, '');
    result = spawnSync(path.join(repo, 'scripts/pentad'), [command, '--path', root], { encoding: 'utf8', env });
    assert.equal(result.status, 0, result.stderr);
    assert.equal(await readFile(capture, 'utf8'), `CALL\n${argv.join('\n')}\n`);
  }
});

test('navigation CLI validates typed actions and preserves the chosen root', async () => {
  const bin = path.join(temporary, 'navigation-cli-bin');
  const root = path.join(temporary, 'navigation root');
  await mkdir(bin);
  await mkdir(root);
  const capture = path.join(temporary, 'navigation-args');
  await executable(path.join(bin, 'qs'), 'printf "%s\\n" "$@" > "$CAPTURE"; printf \'%s\\n\' \'{"ok":true}\'');
  const env = { PATH: `${bin}:/usr/bin:/bin`, CAPTURE: capture };
  for (const [args, payload] of [
    [['overview', 'open'], '{"action":"open"}'],
    [['overview', 'close'], '{"action":"close"}'],
    [['cheatsheet', 'toggle'], '{"action":"toggle"}'],
    [['cheatsheet', 'open'], '{"action":"open"}'],
    [['window-switcher', 'application', 'previous'], '{"mode":"application","action":"previous"}'],
    [['window-switcher', 'all', 'commit'], '{"mode":"all","action":"commit"}'],
  ]) {
    const result = spawnSync(path.join(repo, 'scripts/pentad'), [...args, '--path', root], { env, encoding: 'utf8' });
    assert.equal(result.status, 0, result.stderr);
    assert.equal(await readFile(capture, 'utf8'), `ipc\n--path\n${root}\ncall\npentad\nrequest\n${args[0]}\n${payload}\n`);
  }
  for (const args of [['overview', 'destroy'], ['overview'], ['cheatsheet'], ['cheatsheet', 'show'], ['window-switcher', 'desktop', 'next'], ['window-switcher', 'all', 'launch']]) {
    const result = spawnSync(path.join(repo, 'scripts/pentad'), [...args, '--path', root], { env, encoding: 'utf8' });
    assert.equal(result.status, 2);
  }
});

test('development CLI uses the persistent local runtime for start and IPC', async () => {
  const checkout = path.join(temporary, 'development checkout');
  const localBin = path.join(checkout, 'artifacts/quickshell-runtime/bin');
  const scripts = path.join(checkout, 'scripts');
  const root = path.join(checkout, 'dist/quickshell');
  await Promise.all([localBin, scripts, root].map(dir => mkdir(dir, { recursive: true })));
  await writeFile(path.join(scripts, 'pentad'), await readFile(path.join(repo, 'scripts/pentad')), { mode: 0o700 });
  const capture = path.join(checkout, 'args');
  await executable(path.join(localBin, 'qs'), 'if [ "$1" = "--version" ]; then echo "Quickshell 0.3.2"; exit 0; fi; printf "%s\\n" "${PENTAD_SAFE_MODE-}" "$@" > "$CAPTURE"');
  const env = { PATH: '/usr/bin:/bin', CAPTURE: capture };
  const start = spawnSync(path.join(scripts, 'pentad'), ['start', '--development', '--safe-mode'], { encoding: 'utf8', env });
  assert.equal(start.status, 0, start.stderr);
  assert.equal(await readFile(capture, 'utf8'), `1\n--no-duplicate\n--path\n${root}\n`);
  const ping = spawnSync(path.join(scripts, 'pentad'), ['ping', '--development'], { encoding: 'utf8', env });
  assert.equal(ping.status, 0, ping.stderr);
  assert.equal(await readFile(capture, 'utf8'), `\nipc\n--path\n${root}\ncall\npentad\nrequest\nping\n{}\n`);
});

test('CLI validates workspace arguments and propagates a rejected IPC result', async () => {
  const bin = path.join(temporary, 'typed-cli-bin');
  const root = path.join(temporary, 'typed-root');
  await mkdir(bin);
  await mkdir(root);
  await executable(path.join(bin, 'qs'), 'printf \'%s\\n\' \'{"ok":false,"reason":"denied"}\'');
  const env = { PATH: `${bin}:/usr/bin:/bin`, HOME: temporary };
  for (const args of [['workspace-super', 'Alt_L', 'press'], ['workspace-super', 'Super_L', 'toggle'], ['workspace-slot', '10'], ['panel', 'right', 'destroy']]) {
    const rejected = spawnSync(path.join(repo, 'scripts/pentad'), [...args, '--path', root], { encoding: 'utf8', env });
    assert.equal(rejected.status, 2);
  }
  const denied = spawnSync(path.join(repo, 'scripts/pentad'), ['workspace-slot', '1', '--path', root], { encoding: 'utf8', env });
  assert.equal(denied.status, 1);
  assert.equal(JSON.parse(denied.stdout).reason, 'denied');
});

test('fixture runner marks unavailable scenarios blocked and exits nonzero', async () => {
  const report = path.join(temporary, 'blocked.json');
  const result = run('scripts/test-quickshell.mjs', ['--', '--scenario', 'runtime', '--report', report], { ...process.env, WAYLAND_DISPLAY: '', XDG_RUNTIME_DIR: '' });
  assert.notEqual(result.status, 0);
  const body = JSON.parse(await readFile(report, 'utf8'));
  assert.equal(body.status, 'blocked');
  assert.equal(body.scenario, 'runtime');
});

test('fixture parser recognizes prefixed records and requires passed booleans', () => {
  const { events, checks } = parseTestOutput('INFO: qml: PENTAD_TEST {"status":"pass","checks":[{"name":"root","passed":true},{"name":"ipc","passed":false}]}');
  assert.equal(events[0].status, 'pass');
  assert.deepEqual(checks.map((check) => [check.name, check.status]), [['root', 'pass'], ['ipc', 'fail']]);
  assert.deepEqual(parseTestOutput('no marker').checks, []);
});

test('fixture runner rejects silent widget and controller loading failures', () => {
  const errors = [
    'WARN: Cannot load controller for pentad.activity: Property value set multiple times',
    'WARN: PluginHost.qml:29: Error: Cannot assign to non-existent property "controller"',
    'QML Connections: Detected function "onCommandFinished" in Connections element. This is probably intended to be a signal handler but no signal of the target matches the name.',
  ];
  assert.deepEqual(qmlRuntimeErrors(['Configuration Loaded', ...errors].join('\n')), errors);
});

test('fixture runner rejects arbitrary scenario names', () => {
  const result = run('scripts/test-quickshell.mjs', ['--scenario', '../../tmp/anything', '--report', path.join(temporary, 'bad.json')]);
  assert.equal(result.status, 2);
});

test('build creates a self-contained runtime tree from the migrated sources', async () => {
  // A scratch output: the default dist/quickshell may be the tree a running shell uses.
  const output = path.join(temporary, 'build/quickshell');
  const result = run('scripts/build-quickshell.mjs', ['--output', output]);
  assert.equal(result.status, 0, `${result.stderr}${result.stdout}${result.error?.message || ''}`);
  for (const file of ['shell.qml', 'shell/IpcBridge.qml', 'defaults/theme.json', 'LICENSE', 'LICENSES/material-symbols-Apache-2.0.txt', 'catalogs/en.json', 'catalogs/uk.json', 'helpers/pentad_read_input.py']) {
    await readFile(path.join(output, file));
  }
  await assert.rejects(readFile(path.join(output, 'catalogs/locale.ts')));
  const registry = JSON.parse(await readFile(path.join(output, 'builtin-registry.json'), 'utf8'));
  const widgets = await readdir(path.join(repo, 'quickshell/widgets'), { withFileTypes: true });
  const expected = [];
  for (const entry of widgets.filter(item => item.isDirectory())) {
    const manifest = JSON.parse(await readFile(path.join(repo, 'quickshell/widgets', entry.name, 'manifest.json'), 'utf8'));
    expected.push({ id: manifest.id, path: `widgets/${entry.name}/manifest.json` });
  }
  expected.sort((a, b) => (a.id < b.id ? -1 : a.id > b.id ? 1 : a.path < b.path ? -1 : a.path > b.path ? 1 : 0));
  assert.ok(expected.length > 0);
  assert.deepEqual(registry, expected);
});
