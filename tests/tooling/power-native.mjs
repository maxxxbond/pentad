#!/usr/bin/env node
import { chmod, cp, mkdir, mkdtemp, readFile, rm, writeFile } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { spawn, spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const repo = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const fixture = path.join(repo, 'quickshell/tests/power-native.qml');
const defaultQs = '/tmp/pentad-qs-bin/qs';
// Stands in for busctl: answers only the power-profiles-daemon properties, from a state file.
const fakeUtility = String.raw`#!/usr/bin/python3
import json, os, sys

args = sys.argv[1:]
scenario = os.environ['PENTAD_POWER_SCENARIO']
log_path = os.environ['PENTAD_POWER_LOG']
state_path = os.environ['PENTAD_POWER_STATE']
count_path = os.environ['PENTAD_POWER_GET_COUNT']
with open(log_path, 'a', encoding='utf-8') as stream:
    stream.write(json.dumps(args) + '\n')
service = ['org.freedesktop.UPower.PowerProfiles', '/org/freedesktop/UPower/PowerProfiles', 'org.freedesktop.UPower.PowerProfiles']
profiles = ['power-saver', 'balanced', 'performance']

def get_count():
    try: return int(open(count_path, encoding='ascii').read())
    except FileNotFoundError: return 0
def set_count(value):
    with open(count_path, 'w', encoding='ascii') as stream: stream.write(str(value))
def read_profile():
    try: return open(state_path, encoding='ascii').read().strip()
    except FileNotFoundError: return 'balanced'
def write_profile(value):
    with open(state_path, 'w', encoding='ascii') as stream: stream.write(value)
def set_attempted():
    return os.path.exists(state_path + '.desired')

if args[:3] != ['--system', '--timeout=2', '--json=short'] and args[:2] != ['--system', '--timeout=2']:
    sys.exit(3)
if 'get-property' in args and args[args.index('get-property') + 1:][:3] == service:
    if scenario == 'service-missing' or scenario == 'service-lost' and set_attempted():
        print('Failed to get property: The name is not activatable', file=sys.stderr)
        sys.exit(1)
    names = args[args.index('get-property') + 4:]
    if names == ['ActiveProfile']:
        count = get_count() + 1
        set_count(count)
        if scenario == 'success' and count >= 2:
            write_profile(open(state_path + '.desired', encoding='ascii').read().strip())
    elif names != ['ActiveProfile', 'Profiles']:
        sys.exit(3)
    print(json.dumps({'type': 's', 'data': read_profile()}))
    if 'Profiles' in names:
        print(json.dumps({'type': 'aa{sv}', 'data': [{'Profile': {'type': 's', 'data': name}} for name in profiles]}))
elif 'set-property' in args and args[args.index('set-property') + 1:][:4] == service + ['ActiveProfile']:
    value = args[-1]
    with open(state_path + '.desired', 'w', encoding='ascii') as stream: stream.write(value)
    if scenario in ['set-fail', 'service-lost']: sys.exit(1)
    if args[-2] != 's' or value not in profiles: sys.exit(2)
    if scenario not in ['success', 'readback-timeout']: write_profile(value)
else:
    sys.exit(3)
`;

function eventFrom(output) {
  const marker = 'PENTAD_TEST ';
  const line = output.split(/\r?\n/).find((entry) => entry.includes(marker));
  if (!line) return null;
  try { return JSON.parse(line.slice(line.indexOf(marker) + marker.length)); } catch { return null; }
}

async function runScenario(qs, scratch, scenario) {
  const config = path.join(scratch, `config-${scenario}`);
  const bin = path.join(scratch, `bin-${scenario}`);
  const home = path.join(scratch, `home-${scenario}`);
  const logPath = path.join(scratch, `fake-${scenario}.jsonl`);
  const statePath = path.join(scratch, `state-${scenario}`);
  const getCountPath = path.join(scratch, `get-count-${scenario}`);
  for (const dir of [config, bin, home]) await mkdir(dir, { recursive: true, mode: 0o700 });
  await cp(path.join(repo, 'quickshell'), config, { recursive: true });
  const source = await readFile(fixture, 'utf8');
  await writeFile(path.join(config, 'shell.qml'), source
    .replaceAll('import "../services"', 'import "services"')
    .replaceAll('import "../features/system"', 'import "features/system"'));
  await writeFile(statePath, 'balanced');
  if (scenario !== 'missing-utility') {
    const target = path.join(bin, 'busctl');
    await writeFile(target, fakeUtility, { mode: 0o700 });
    await chmod(target, 0o700);
  }
  const env = {
    ...process.env,
    PATH: bin,
    // No display, no session bus, and a system bus address that leads nowhere: the native
    // PowerProfiles and UPower clients cannot reach real daemons, so every answer is the fake's.
    QT_QPA_PLATFORM: 'offscreen',
    DBUS_SYSTEM_BUS_ADDRESS: `unix:path=${path.join(scratch, 'no-system-bus')}`,
    HOME: home,
    XDG_CONFIG_HOME: path.join(scratch, `xdg-config-${scenario}`),
    XDG_DATA_HOME: path.join(scratch, `xdg-data-${scenario}`),
    XDG_STATE_HOME: path.join(scratch, `xdg-state-${scenario}`),
    XDG_CACHE_HOME: path.join(scratch, `xdg-cache-${scenario}`),
    XDG_RUNTIME_DIR: path.join(scratch, `xdg-runtime-${scenario}`),
    PENTAD_POWER_SCENARIO: scenario,
    PENTAD_POWER_LOG: logPath,
    PENTAD_POWER_STATE: statePath,
    PENTAD_POWER_GET_COUNT: getCountPath,
    LANG: 'C.UTF-8',
  };
  for (const key of ['WAYLAND_DISPLAY', 'DISPLAY', 'HYPRLAND_INSTANCE_SIGNATURE', 'DBUS_SESSION_BUS_ADDRESS']) delete env[key];
  for (const key of ['XDG_CONFIG_HOME', 'XDG_DATA_HOME', 'XDG_STATE_HOME', 'XDG_CACHE_HOME', 'XDG_RUNTIME_DIR'])
    await mkdir(env[key], { recursive: true, mode: 0o700 });

  const child = spawn(qs, ['--no-duplicate', '--path', config], { cwd: repo, env, stdio: ['ignore', 'pipe', 'pipe'] });
  let output = '';
  child.stdout.setEncoding('utf8').on('data', (chunk) => { output += chunk; });
  child.stderr.setEncoding('utf8').on('data', (chunk) => { output += chunk; });
  let timedOut = false;
  const timeout = setTimeout(() => { timedOut = true; child.kill('SIGTERM'); }, 22000);
  const closed = await new Promise((resolve) => {
    child.once('error', (error) => resolve({ error }));
    child.once('close', (code, signal) => resolve({ code, signal }));
  });
  clearTimeout(timeout);
  const event = eventFrom(output);
  const calls = (await readFile(logPath, 'utf8').catch(() => '')).split(/\r?\n/)
    .filter(Boolean).map((line) => JSON.parse(line));
  const checks = (event?.checks || []).slice();
  const verb = (args) => args.includes('set-property') ? `set ${args[args.length - 1]}`
    : args.includes('Profiles') ? 'probe' : args.includes('get-property') ? 'get' : 'other';
  const verbs = calls.map(verb);
  const detail = JSON.stringify(verbs);
  checks.push({ name: 'only-private-fake-utility-ran', passed: !verbs.includes('other'), detail });
  if (scenario === 'success') {
    checks.push({ name: 'set-is-followed-by-observed-readback', passed: verbs.some((item, i) => item === 'set performance'
      && verbs.slice(i + 1).includes('get')), detail });
    checks.push({ name: 'only-allowlisted-profile-argv-used', passed: calls.every((args) => verb(args) !== 'other'
      && (!args.includes('set-property') || ['balanced', 'performance', 'power-saver'].includes(args[args.length - 1]))), detail });
  } else if (scenario === 'safe-mode') {
    checks.push({ name: 'safe-mode-never-ran-set', passed: !verbs.some((item) => item.startsWith('set')), detail });
  } else if (scenario === 'missing-utility') {
    checks.push({ name: 'missing-tool-produced-no-process-log', passed: calls.length === 0, detail });
  } else if (scenario === 'set-fail') {
    checks.push({ name: 'failed-set-had-no-readback-claim', passed: verbs.includes('set performance')
      && !verbs.includes('get'), detail });
  } else if (scenario === 'idle') {
    checks.push({ name: 'idle-service-spawns-nothing-after-probe', passed: detail === '["probe"]', detail });
  }
  return { scenario, status: !closed.error && !timedOut && closed.code === 0 && event?.status === 'pass'
    && checks.length && checks.every((check) => check.passed === true) ? 'pass' : 'fail', checks,
    error: closed.error?.message, timedOut, exitCode: closed.code, output: closed.code === 0 ? undefined : output };
}

async function main(argv) {
  let qs = process.env.PENTAD_QS_BIN || defaultQs;
  let reportPath;
  for (let i = 0; i < argv.length; i++) {
    if (argv[i] === '--qs' && argv[i + 1]) qs = argv[++i];
    else if (argv[i] === '--report' && argv[i + 1]) reportPath = argv[++i];
    else throw new Error(`Unknown or incomplete argument: ${argv[i]}`);
  }
  if (!reportPath) throw new Error('Usage: power-native.mjs --report <path> [--qs <pinned-qs>]');
  const version = spawnSync(qs, ['--version'], { encoding: 'utf8', timeout: 5000 });
  if (version.error || version.status !== 0 || !/Quickshell 0\.3\.2\b/.test(`${version.stdout}\n${version.stderr}`))
    throw new Error(`Need pinned Quickshell 0.3.2 (${qs}): ${version.error?.message || version.stderr || version.stdout}`);
  const scratch = await mkdtemp(path.join(os.tmpdir(), 'pentad-power-native-'));
  try {
    const results = [];
    for (const scenario of ['success', 'safe-mode', 'missing-utility', 'service-missing', 'set-fail', 'readback-timeout',
      'service-lost', 'idle'])
      results.push(await runScenario(qs, scratch, scenario));
    const report = { status: results.every((item) => item.status === 'pass') ? 'pass' : 'fail',
      scenario: 'power-native', qs: version.stdout.trim(), safety: 'private fake-only PATH; no display, session bus or system bus reachable',
      scenarios: results, checks: results.flatMap((item) => item.checks.map((check) => ({ scenario: item.scenario, ...check }))) };
    await mkdir(path.dirname(path.resolve(reportPath)), { recursive: true });
    await writeFile(path.resolve(reportPath), `${JSON.stringify(report, null, 2)}\n`, { mode: 0o600 });
    process.stdout.write(`${JSON.stringify(report, null, 2)}\n`);
    return report.status === 'pass' ? 0 : 1;
  } finally { await rm(scratch, { recursive: true, force: true }); }
}

main(process.argv.slice(2)).then((code) => { process.exitCode = code; }).catch((error) => {
  console.error(JSON.stringify({ status: 'fail', scenario: 'power-native', error: error.stack || String(error) }, null, 2));
  process.exitCode = 1;
});
