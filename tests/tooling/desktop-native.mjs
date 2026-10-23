#!/usr/bin/env node
import { chmod, cp, mkdir, mkdtemp, readFile, readdir, rm, writeFile } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { spawn, spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const repo = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const fixture = path.join(repo, 'quickshell/tests/desktop-native.qml');
const defaultQs = '/tmp/pentad-qs-bin/qs';
const fakePrograms = {
  slurp: `#!/bin/sh\nprintf 'slurp\\n' >> "$PENTAD_FAKE_LOG"\n[ "$PENTAD_FAKE_FAIL" = slurp ] && exit 2\nprintf '120,80 640x360\\n'\n`,
  'xdg-user-dir': `#!/bin/sh\nprintf 'xdg-user-dir\\n' >> "$PENTAD_FAKE_LOG"\n[ "$PENTAD_FAKE_FAIL" = xdg-user-dir ] && exit 2\nprintf '%s/Pictures\\n' "$HOME"\n`,
  mkdir: `#!/bin/sh\nprintf 'mkdir\\n' >> "$PENTAD_FAKE_LOG"\n[ "$PENTAD_FAKE_FAIL" = mkdir ] && exit 2\nexec /usr/bin/mkdir "$@"\n`,
  grim: `#!/bin/sh\nprintf 'grim\\n' >> "$PENTAD_FAKE_LOG"\n[ "$PENTAD_FAKE_FAIL" = grim ] && exit 2\nprintf 'fake screenshot\\n' > "$3"\n`,
  'wf-recorder': `#!/bin/sh\nprintf 'wf-recorder\\nrecord-path:%s\\n' "$4" >> "$PENTAD_FAKE_LOG"\ntrap 'printf "recorder-stop\\n" >> "$PENTAD_FAKE_LOG"; exit 0' INT TERM\nwhile :; do /usr/bin/sleep 0.05; done\n`,
  hyprpicker: `#!/bin/sh\nprintf 'hyprpicker\\n' >> "$PENTAD_FAKE_LOG"\nexit 0\n`,
  'systemd-inhibit': `#!/bin/sh\nprintf 'systemd-inhibit\\n' >> "$PENTAD_FAKE_LOG"\ntrap 'printf "inhibit-stop\\n" >> "$PENTAD_FAKE_LOG"; exit 0' INT TERM\nwhile :; do /usr/bin/sleep 0.05; done\n`,
  ls: `#!/bin/sh\n[ "$1" = -1 ] && [ "$2" = "$PENTAD_DESKTOP_DRM_ROOT" ] || exit 2\n[ "$PENTAD_DESKTOP_SCENARIO" = gpu-cancel ] && /usr/bin/sleep 0.5\n[ "$PENTAD_DESKTOP_SCENARIO" = gpu-slow ] && /usr/bin/sleep 0.4\nexec /usr/bin/ls -1 "$2"\n`,
};
// Stands in for /sys/class/drm: two cards with sysfs values and a connector entry that is not a card.
const drmFiles = {
  'card0/device/gpu_busy_percent': '22\n', 'card0/device/mem_info_vram_used': '100\n', 'card0/device/mem_info_vram_total': '1000\n',
  'card1/device/gpu_busy_percent': '64\n', 'card1/device/mem_info_vram_used': '300\n', 'card1/device/mem_info_vram_total': '2000\n',
  'card0-DP-1/status': 'connected\n',
};

function parseEvents(output) {
  return output.split(/\r?\n/).filter((line) => line.includes('PENTAD_TEST ')).map((line) => {
    try { return JSON.parse(line.slice(line.indexOf('PENTAD_TEST ') + 'PENTAD_TEST '.length)); }
    catch { return null; }
  }).filter(Boolean);
}

async function runScenario(qs, scratch, name) {
  const config = path.join(scratch, `config-${name}`);
  const fakeBin = path.join(scratch, `bin-${name}`);
  const home = path.join(scratch, `home-${name}`);
  const log = path.join(scratch, `fake-${name}.log`);
  const drm = path.join(scratch, `drm-${name}`);
  for (const [file, value] of Object.entries(drmFiles)) {
    await mkdir(path.dirname(path.join(drm, file)), { recursive: true, mode: 0o700 });
    await writeFile(path.join(drm, file), value);
  }
  await Promise.all([mkdir(config, { recursive: true, mode: 0o700 }), mkdir(fakeBin, { recursive: true, mode: 0o700 }), mkdir(home, { recursive: true, mode: 0o700 })]);
  await cp(path.join(repo, 'quickshell'), config, { recursive: true });
  const source = await readFile(fixture, 'utf8');
  await writeFile(path.join(config, 'shell.qml'), source
    .replaceAll('import "../services"', 'import "services"')
    .replaceAll('import "../features/bar"', 'import "features/bar"'));
  const omitted = {
    'missing-slurp': ['slurp'],
    'missing-grim': ['grim'],
    'missing-recorder': ['wf-recorder'],
    'missing-picker': ['hyprpicker'],
    'missing-inhibit': ['systemd-inhibit'],
    'xdg-fallback': ['xdg-user-dir'],
  }[name] || [];
  for (const [program, body] of Object.entries(fakePrograms)) {
    if (omitted.includes(program)) continue;
    const target = path.join(fakeBin, program);
    await writeFile(target, body, { mode: 0o700 });
    await chmod(target, 0o700);
  }
  const env = {
    ...process.env,
    HOME: home,
    PATH: fakeBin,
    PENTAD_DESKTOP_SCENARIO: name,
    PENTAD_DESKTOP_DRM_ROOT: drm,
    PENTAD_FAKE_FAIL: name === 'mkdir-fail' ? 'mkdir' : '',
    PENTAD_FAKE_LOG: log,
    XDG_CONFIG_HOME: path.join(scratch, 'xdg-config'),
    XDG_DATA_HOME: path.join(scratch, 'xdg-data'),
    XDG_STATE_HOME: path.join(scratch, 'xdg-state'),
    XDG_CACHE_HOME: path.join(scratch, 'xdg-cache'),
    LANG: 'C.UTF-8',
  };
  for (const key of ['XDG_CONFIG_HOME', 'XDG_DATA_HOME', 'XDG_STATE_HOME', 'XDG_CACHE_HOME'])
    await mkdir(env[key], { recursive: true, mode: 0o700 });
  const child = spawn(qs, ['--no-duplicate', '--path', config], { cwd: repo, env, stdio: ['ignore', 'pipe', 'pipe'] });
  let output = '';
  child.stdout.setEncoding('utf8').on('data', (chunk) => { output += chunk; });
  child.stderr.setEncoding('utf8').on('data', (chunk) => { output += chunk; });
  let timedOut = false;
  let forceKill;
  const timer = setTimeout(() => {
    timedOut = true;
    child.kill('SIGTERM');
    forceKill = setTimeout(() => child.kill('SIGKILL'), 1000);
  }, 23000);
  const closed = await new Promise((resolve) => {
    child.once('error', (error) => resolve({ error }));
    child.once('close', (code, signal) => resolve({ code, signal }));
  });
  clearTimeout(timer);
  clearTimeout(forceKill);
  const events = parseEvents(output);
  const event = events.at(-1);
  const calls = await readFile(log, 'utf8').catch(() => '');
  const checks = event?.checks || [];
  if (name === 'capture-stop') {
    checks.push({ name: 'fake-capture-command-order', passed: calls.split(/\r?\n/).filter(Boolean).join(',') === 'slurp,xdg-user-dir,mkdir,grim,slurp,xdg-user-dir,mkdir,wf-recorder,record-path:' + (calls.match(/record-path:(.*)/)?.[1] || '') + ',recorder-stop', detail: calls });
    const pictureFiles = await readdir(path.join(home, 'Pictures', 'Pentad')).catch(() => []);
    checks.push({ name: 'fake-screenshot-file-created', passed: pictureFiles.some((file) => file.endsWith('.png')), detail: pictureFiles.join(',') });
  } else if (name === 'xdg-fallback') {
    checks.push({ name: 'fallback-utility-order', passed: calls.split(/\r?\n/).filter(Boolean).join(',') === 'slurp,mkdir,grim', detail: calls });
    const pictureFiles = await readdir(path.join(home, 'Pictures', 'Pentad')).catch(() => []);
    checks.push({ name: 'fallback-screenshot-file-created', passed: pictureFiles.some((file) => file.endsWith('.png')), detail: pictureFiles.join(',') });
  }
  if (name === 'inhibit') checks.push({ name: 'owned-inhibitor-stopped', passed: calls.includes('inhibit-stop'), detail: calls });
  return {
    scenario: name,
    status: !closed.error && !timedOut && closed.code === 0 && events.length === 1 && event.status === 'pass' && checks.length > 0 && checks.every((item) => item.passed === true) ? 'pass' : 'fail',
    checks,
    error: closed.error?.message,
    timedOut,
    exitCode: closed.code,
    output: closed.code === 0 ? undefined : output,
  };
}

async function main(argv) {
  let qs = process.env.PENTAD_QS_BIN || defaultQs;
  let reportPath;
  for (let i = 0; i < argv.length; i++) {
    const option = argv[i];
    if (option !== '--qs' && option !== '--report') throw new Error(`Unknown argument: ${option}`);
    const value = argv[i + 1];
    if (!value || value.startsWith('--')) throw new Error(`${option} requires a value`);
    if (option === '--qs') qs = value;
    else reportPath = value;
    i++;
  }
  const version = spawnSync(qs, ['--version'], { encoding: 'utf8', timeout: 5000 });
  if (version.error || version.status !== 0 || !/Quickshell 0\.3\.2\b/.test(`${version.stdout}\n${version.stderr}`))
    throw new Error(`Need the pinned Quickshell 0.3.2 binary (${qs}): ${version.error?.message || version.stdout || version.stderr}`);
  const scratch = await mkdtemp(path.join(os.tmpdir(), 'pentad-desktop-native-'));
  const result = { status: 'fail', scenario: 'desktop-native', qs: `${version.stdout.trim()}`, checks: [] };
  try {
    const availableScenarios = ['capture-stop', 'missing-slurp', 'missing-grim', 'missing-recorder', 'missing-picker', 'missing-inhibit', 'mkdir-fail', 'xdg-fallback', 'inhibit', 'guards', 'dnd', 'gpu', 'gpu-slow', 'gpu-cancel'];
    result.scenarios = [];
    for (const scenario of availableScenarios) result.scenarios.push(await runScenario(qs, scratch, scenario));
    result.status = result.scenarios.every((item) => item.status === 'pass') ? 'pass' : 'fail';
    result.checks = result.scenarios.flatMap((item) => item.checks.map((check) => ({ scenario: item.scenario, ...check })));
    const failures = result.scenarios.filter((item) => item.status !== 'pass');
    if (failures.length) result.failures = failures.map(({ scenario, error, timedOut, exitCode, output }) => ({ scenario, error, timedOut, exitCode, output }));
  } finally {
    await rm(scratch, { recursive: true, force: true });
  }
  if (reportPath) {
    await mkdir(path.dirname(path.resolve(reportPath)), { recursive: true });
    await writeFile(reportPath, `${JSON.stringify(result, null, 2)}\n`, { mode: 0o600 });
  }
  process.stdout.write(`${JSON.stringify(result, null, 2)}\n`);
  return result.status === 'pass' ? 0 : 1;
}

main(process.argv.slice(2)).then((code) => { process.exitCode = code; }).catch((error) => {
  console.error(error.stack || String(error));
  process.exitCode = 1;
});
