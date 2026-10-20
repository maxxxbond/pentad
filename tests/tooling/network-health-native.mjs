#!/usr/bin/env node
import { chmod, cp, mkdir, mkdtemp, readFile, rm, writeFile } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { spawn, spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const repo = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const fixture = path.join(repo, 'quickshell/tests/network-health.qml');
const defaultQs = '/tmp/pentad-qs-bin/qs';
const runtimeWarning = /TypeError:|ReferenceError:|SyntaxError:|Unknown signal|Cannot assign to non-existent property|Detected function .* in Connections element .* no signal .* matches/i;
const fakeBusctl = String.raw`#!/usr/bin/python3
import json, os, sys, time
args = sys.argv[1:]
scenario = os.environ['PENTAD_NETWORK_HEALTH_SCENARIO']
with open(os.environ['PENTAD_NETWORK_HEALTH_LOG'], 'a', encoding='utf-8') as stream:
    stream.write(json.dumps(args) + '\n')
owner = ['--system', 'call', 'org.freedesktop.DBus', '/org/freedesktop/DBus',
    'org.freedesktop.DBus', 'NameHasOwner', 's', 'org.freedesktop.NetworkManager']
wifi = ['--system', 'get-property', 'org.freedesktop.NetworkManager',
    '/org/freedesktop/NetworkManager', 'org.freedesktop.NetworkManager', 'WirelessEnabled']
if args == owner: kind = 'owner'
elif args == wifi: kind = 'wifi'
else: sys.exit(3)
count_path = os.environ['PENTAD_NETWORK_HEALTH_COUNTS'] + '-' + kind
try: count = int(open(count_path, encoding='ascii').read()) + 1
except FileNotFoundError: count = 1
with open(count_path, 'w', encoding='ascii') as stream: stream.write(str(count))
if kind == 'owner':
    if scenario == 'timeout': time.sleep(4)
    if scenario == 'late-generation' and count == 1: time.sleep(2)
    if scenario == 'loss-recovery' or scenario == 'wifi-owner-loss':
        print('b true' if count == 1 or scenario == 'loss-recovery' and count >= 3 else 'b false')
    elif scenario == 'owner-missing': print('b false')
    else: print('b true')
else:
    if scenario == 'wifi-timeout' and count >= 2: time.sleep(4)
    if scenario == 'wifi-getfailure' and count >= 2: sys.exit(5)
    if scenario == 'wifi-delayed': print('b false' if count >= 4 else 'b true')
    else: print('b true')
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
  const xdg = {};
  for (const name of ['config', 'data', 'state', 'cache']) xdg[name] = path.join(scratch, `xdg-${name}-${scenario}`);
  const log = path.join(scratch, `busctl-${scenario}.jsonl`);
  const counts = path.join(scratch, `counts-${scenario}`);
  for (const dir of [config, bin, home, runtime, ...Object.values(xdg)])
    await mkdir(dir, { recursive: true, mode: 0o700 });
  await cp(path.join(repo, 'quickshell'), config, { recursive: true });
  const source = await readFile(fixture, 'utf8');
  await writeFile(path.join(config, 'shell.qml'), source.replaceAll('import "../services"', 'import "services"'));
  if (scenario !== 'missing-busctl') {
    const executable = path.join(bin, 'busctl');
    await writeFile(executable, fakeBusctl, { mode: 0o700 });
    await chmod(executable, 0o700);
  }
  const env = {
    ...process.env, PATH: bin, HOME: home, XDG_RUNTIME_DIR: runtime,
    XDG_CONFIG_HOME: xdg.config, XDG_DATA_HOME: xdg.data, XDG_STATE_HOME: xdg.state, XDG_CACHE_HOME: xdg.cache,
    WAYLAND_DISPLAY: waylandSocket, LANG: 'C.UTF-8',
    PENTAD_NETWORK_HEALTH_SCENARIO: scenario, PENTAD_NETWORK_HEALTH_LOG: log,
    PENTAD_NETWORK_HEALTH_COUNTS: counts,
  };
  const child = spawn(qs, ['--no-duplicate', '--path', config], { cwd: repo, env, stdio: ['ignore', 'pipe', 'pipe'] });
  let output = '';
  child.stdout.setEncoding('utf8').on('data', (chunk) => { output += chunk; });
  child.stderr.setEncoding('utf8').on('data', (chunk) => { output += chunk; });
  let timedOut = false;
  const timeout = setTimeout(() => { timedOut = true; child.kill('SIGTERM'); }, 10000);
  const closed = await new Promise((resolve) => {
    child.once('error', (error) => resolve({ error }));
    child.once('close', (code, signal) => resolve({ code, signal }));
  });
  clearTimeout(timeout);
  const event = eventFrom(output);
  const calls = (await readFile(log, 'utf8').catch(() => '')).split(/\r?\n/).filter(Boolean).map(JSON.parse);
  const checks = (event?.checks || []).slice();
  checks.push({ name: 'only-private-fake-busctl-ran', passed: calls.every((args) =>
    JSON.stringify(args) === JSON.stringify(['--system', 'call', 'org.freedesktop.DBus', '/org/freedesktop/DBus',
      'org.freedesktop.DBus', 'NameHasOwner', 's', 'org.freedesktop.NetworkManager'])
    || JSON.stringify(args) === JSON.stringify(['--system', 'get-property', 'org.freedesktop.NetworkManager',
      '/org/freedesktop/NetworkManager', 'org.freedesktop.NetworkManager', 'WirelessEnabled'])), detail: `probes=${calls.length}` });
  if (scenario === 'missing-busctl') checks.push({ name: 'missing-busctl-did-not-fall-through-to-system-path',
    passed: calls.length === 0 });
  if (scenario === 'loss-recovery') checks.push({ name: 'multiple-owner-snapshots-observed', passed: calls.length >= 3,
    detail: `probes=${calls.length}` });
  checks.push({ name: 'no QML runtime or unmatched-signal warnings', passed: !runtimeWarning.test(output) });
  return { scenario, status: !closed.error && !timedOut && closed.code === 0 && event?.status === 'pass'
    && checks.length > 0 && checks.every((item) => item.passed === true) ? 'pass' : 'fail', checks,
    error: closed.error?.message, timedOut, exitCode: closed.code,
    output: closed.code === 0 && event?.status === 'pass' && checks.every((item) => item.passed) ? undefined : output };
}

async function main(argv) {
  let qs = process.env.PENTAD_QS_BIN || defaultQs;
  let reportPath = '';
  let selectedScenario = '';
  for (let i = 0; i < argv.length; i++) {
    if (argv[i] === '--qs' && argv[i + 1]) qs = argv[++i];
    else if (argv[i] === '--report' && argv[i + 1]) reportPath = argv[++i];
    else if (argv[i] === '--scenario' && argv[i + 1]) selectedScenario = argv[++i];
    else throw new Error(`Unknown or incomplete argument: ${argv[i]}`);
  }
  if (!reportPath) throw new Error('Usage: network-health-native.mjs --report <path> [--qs <pinned-qs>]');
  const wayland = process.env.WAYLAND_DISPLAY;
  if (!wayland || !process.env.XDG_RUNTIME_DIR) throw new Error('Health fixture requires an active Wayland session');
  const version = spawnSync(qs, ['--version'], { encoding: 'utf8', timeout: 5000 });
  if (version.error || version.status !== 0 || !/Quickshell 0\.3\.2\b/.test(`${version.stdout}\n${version.stderr}`))
    throw new Error(`Need pinned Quickshell 0.3.2 (${qs}): ${version.error?.message || version.stderr || version.stdout}`);
  const socket = path.isAbsolute(wayland) ? wayland : path.join(process.env.XDG_RUNTIME_DIR, wayland);
  const scratch = await mkdtemp(path.join(os.tmpdir(), 'pentad-network-health-'));
  try {
    const results = [];
    const scenarios = selectedScenario ? [selectedScenario]
      : ['ready', 'loss-recovery', 'owner-missing', 'timeout', 'missing-busctl', 'late-generation',
        'wifi-delayed', 'wifi-mismatch', 'wifi-getfailure', 'wifi-timeout', 'wifi-owner-loss'];
    for (const scenario of scenarios)
      results.push(await runScenario(qs, scratch, scenario, socket));
    const report = { status: results.every((item) => item.status === 'pass') ? 'pass' : 'fail',
      scenario: 'network-health-native', qs: version.stdout.trim(),
      safety: 'injected fake Network backend; private fake-only PATH for busctl; no network writes or system bus probes',
      scenarios: results, checks: results.flatMap((item) => item.checks.map((check) => ({ scenario: item.scenario, ...check }))) };
    await mkdir(path.dirname(path.resolve(reportPath)), { recursive: true, mode: 0o700 });
    await writeFile(path.resolve(reportPath), `${JSON.stringify(report, null, 2)}\n`, { mode: 0o600 });
    process.stdout.write(`${JSON.stringify(report, null, 2)}\n`);
    return report.status === 'pass' ? 0 : 1;
  } finally { await rm(scratch, { recursive: true, force: true }); }
}

main(process.argv.slice(2)).then((code) => { process.exitCode = code; }).catch((error) => {
  console.error(JSON.stringify({ status: 'fail', scenario: 'network-health-native', error: error.stack || String(error) }, null, 2));
  process.exitCode = 1;
});
