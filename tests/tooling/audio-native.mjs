#!/usr/bin/env node
import { chmod, cp, mkdir, mkdtemp, readFile, rm, writeFile } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { spawn, spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { qmlRuntimeErrors } from '../../scripts/test-quickshell.mjs';

const repo = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const fixture = path.join(repo, 'quickshell/tests/audio-native.qml');
const defaultQs = '/tmp/pentad-qs-bin/qs';
const fakeWpctl = String.raw`#!/usr/bin/python3
import json, os, sys, time
args = sys.argv[1:]
scenario = os.environ['PENTAD_AUDIO_SCENARIO']
log_path = os.environ['PENTAD_AUDIO_LOG']
counter_path = os.path.join(os.environ['PENTAD_AUDIO_COUNTS'], args[-1])
with open(log_path, 'a', encoding='utf-8') as stream:
    stream.write(json.dumps(args) + '\n')
try: count = int(open(counter_path, encoding='ascii').read()) + 1
except FileNotFoundError: count = 1
with open(counter_path, 'w', encoding='ascii') as stream: stream.write(str(count))
if scenario in ('device-removed', 'service-loss'):
    time.sleep(1)
if args[0] != 'get-volume' or len(args) != 2: sys.exit(3)
if scenario in ('success', 'stale-probe'):
    print('Volume: 0.70' if count >= 2 else 'Volume: 0.40')
elif scenario == 'mute':
    print('Volume: 0.40 [MUTED]' if count >= 2 else 'Volume: 0.40')
elif scenario == 'supersede':
    print('Volume: 0.80')
elif scenario == 'late-confirmation':
    print('Volume: 0.70')
elif scenario == 'stream-controls' and args[-1] == '31':
    print('Volume: 0.72')
elif scenario == 'stream-controls' and args[-1] == '32':
    print('Volume: 0.55 [MUTED]')
else:
    print('Volume: 0.40')
`;

function eventFrom(output) {
  const marker = 'PENTAD_TEST ';
  const line = output.split(/\r?\n/).find((entry) => entry.includes(marker));
  if (!line) return null;
  try { return JSON.parse(line.slice(line.indexOf(marker) + marker.length)); } catch { return null; }
}

async function runScenario(qs, scratch, scenario, waylandSocket) {
  const config = path.join(scratch, `config-${scenario}`);
  const bin = path.join(scratch, `bin-${scenario}`);
  const home = path.join(scratch, `home-${scenario}`);
  const runtime = path.join(scratch, `runtime-${scenario}`);
  const counts = path.join(scratch, `counts-${scenario}`);
  const logPath = path.join(scratch, `fake-${scenario}.jsonl`);
  for (const dir of [config, bin, home, runtime, counts,
    path.join(scratch, `xdg-config-${scenario}`), path.join(scratch, `xdg-data-${scenario}`),
    path.join(scratch, `xdg-state-${scenario}`), path.join(scratch, `xdg-cache-${scenario}`)])
    await mkdir(dir, { recursive: true, mode: 0o700 });
  await cp(path.join(repo, 'quickshell'), config, { recursive: true });
  const source = await readFile(fixture, 'utf8');
  await writeFile(path.join(config, 'shell.qml'), source
    .replaceAll('import "../services"', 'import "services"')
    .replaceAll('import "../features/system"', 'import "features/system"'));
  if (scenario !== 'missing-utility') {
    const target = path.join(bin, 'wpctl');
    await writeFile(target, fakeWpctl, { mode: 0o700 });
    await chmod(target, 0o700);
  }
  const env = {
    ...process.env,
    PATH: bin,
    HOME: home,
    XDG_CONFIG_HOME: path.join(scratch, `xdg-config-${scenario}`),
    XDG_DATA_HOME: path.join(scratch, `xdg-data-${scenario}`),
    XDG_STATE_HOME: path.join(scratch, `xdg-state-${scenario}`),
    XDG_CACHE_HOME: path.join(scratch, `xdg-cache-${scenario}`),
    XDG_RUNTIME_DIR: runtime,
    WAYLAND_DISPLAY: waylandSocket,
    PENTAD_AUDIO_SCENARIO: scenario,
    PENTAD_AUDIO_LOG: logPath,
    PENTAD_AUDIO_COUNTS: counts,
    LANG: 'C.UTF-8',
  };
  const child = spawn(qs, ['--no-duplicate', '--path', config], { cwd: repo, env, stdio: ['ignore', 'pipe', 'pipe'] });
  let output = '';
  child.stdout.setEncoding('utf8').on('data', (chunk) => { output += chunk; });
  child.stderr.setEncoding('utf8').on('data', (chunk) => { output += chunk; });
  let timedOut = false;
  const timeout = setTimeout(() => { timedOut = true; child.kill('SIGTERM'); }, 14000);
  const closed = await new Promise((resolve) => {
    child.once('error', (error) => resolve({ error }));
    child.once('close', (code, signal) => resolve({ code, signal }));
  });
  clearTimeout(timeout);
  const event = eventFrom(output);
  const calls = (await readFile(logPath, 'utf8').catch(() => '')).split(/\r?\n/)
    .filter(Boolean).map((line) => JSON.parse(line));
  const checks = (event?.checks || []).slice();
  const runtimeErrors = qmlRuntimeErrors(output);
  checks.push({ name: 'no-qml-runtime-errors', passed: runtimeErrors.length === 0, detail: runtimeErrors.join('\n') });
  checks.push({ name: 'only-private-fake-wpctl-ran', passed: calls.every((args) => args.length === 2 && args[0] === 'get-volume'), detail: JSON.stringify(calls) });
  if (scenario === 'missing-utility') checks.push({ name: 'missing-wpctl-did-not-fall-through-to-system-path', passed: calls.length === 0 });
  if (scenario === 'timeout') checks.push({ name: 'timeout-kept-polling-without-claiming-write', passed: calls.length > 1, detail: JSON.stringify(calls) });
  if (scenario === 'native-signals') checks.push({ name: 'idle-native-updates-spawn-no-wpctl', passed: calls.length === 0, detail: JSON.stringify(calls) });
  if (scenario === 'late-confirmation') checks.push({ name: 'unconfirmed-write-ran-a-readback', passed: calls.length >= 1, detail: JSON.stringify(calls) });
  if (scenario === 'success') checks.push({ name: 'readback-polled-after-native-set', passed: calls.length >= 2 && calls.every((args) => args[0] === 'get-volume') });
  return { scenario, status: !closed.error && !timedOut && closed.code === 0 && event?.status === 'pass'
    && checks.length > 0 && checks.every((item) => item.passed === true) ? 'pass' : 'fail',
    checks, error: closed.error?.message, timedOut, exitCode: closed.code,
    output: closed.code === 0 && event?.status === 'pass' && !runtimeErrors.length ? undefined : output };
}

async function main(argv) {
  let qs = process.env.PENTAD_QS_BIN || defaultQs;
  let reportPath;
  let selectedScenario = '';
  for (let i = 0; i < argv.length; i++) {
    if (argv[i] === '--qs' && argv[i + 1]) qs = argv[++i];
    else if (argv[i] === '--report' && argv[i + 1]) reportPath = argv[++i];
    else if (argv[i] === '--scenario' && argv[i + 1]) selectedScenario = argv[++i];
    else throw new Error(`Unknown or incomplete argument: ${argv[i]}`);
  }
  if (!reportPath) throw new Error('Usage: audio-native.mjs --report <path> [--qs <pinned-qs>]');
  const wayland = process.env.WAYLAND_DISPLAY;
  if (!wayland || !process.env.XDG_RUNTIME_DIR) throw new Error('Audio fixture requires an active Wayland session');
  const waylandSocket = path.isAbsolute(wayland) ? wayland : path.join(process.env.XDG_RUNTIME_DIR, wayland);
  const version = spawnSync(qs, ['--version'], { encoding: 'utf8', timeout: 5000 });
  if (version.error || version.status !== 0 || !/Quickshell 0\.3\.2\b/.test(`${version.stdout}\n${version.stderr}`))
    throw new Error(`Need pinned Quickshell 0.3.2 (${qs}): ${version.error?.message || version.stderr || version.stdout}`);
  const scratch = await mkdtemp(path.join(os.tmpdir(), 'pentad-audio-native-'));
  try {
    const scenarios = selectedScenario ? [selectedScenario]
      : ['success', 'mute', 'default', 'default-timeout', 'supersede', 'stale-probe', 'timeout', 'device-removed', 'service-loss', 'missing-utility', 'streams', 'stream-controls', 'stream-guards', 'stream-recycled', 'stream-ready', 'native-signals', 'late-confirmation', 'microphone'];
    const results = [];
    for (const scenario of scenarios) results.push(await runScenario(qs, scratch, scenario, waylandSocket));
    const report = { status: results.every((item) => item.status === 'pass') ? 'pass' : 'fail',
      scenario: 'audio-native', qs: version.stdout.trim(),
      safety: 'injected fake Pipewire backend; private fake-only PATH for wpctl readbacks; no real audio writes',
      scenarios: results, checks: results.flatMap((item) => item.checks.map((check) => ({ scenario: item.scenario, ...check }))) };
    await mkdir(path.dirname(path.resolve(reportPath)), { recursive: true });
    await writeFile(path.resolve(reportPath), `${JSON.stringify(report, null, 2)}\n`, { mode: 0o600 });
    process.stdout.write(`${JSON.stringify(report, null, 2)}\n`);
    return report.status === 'pass' ? 0 : 1;
  } finally { await rm(scratch, { recursive: true, force: true }); }
}

main(process.argv.slice(2)).then((code) => { process.exitCode = code; }).catch((error) => {
  console.error(JSON.stringify({ status: 'fail', scenario: 'audio-native', error: error.stack || String(error) }, null, 2));
  process.exitCode = 1;
});
