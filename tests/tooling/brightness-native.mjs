#!/usr/bin/env node
import { chmod, cp, mkdir, mkdtemp, readFile, rm, writeFile } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { spawn, spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const repo = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const fixture = path.join(repo, 'quickshell/tests/brightness-native.qml');
const defaultQs = '/tmp/pentad-qs-bin/qs';
const fakeUtility = String.raw`#!/usr/bin/python3
import json, os, sys, time

tool = os.path.basename(sys.argv[0])
args = sys.argv[1:]
scenario = os.environ['PENTAD_BRIGHTNESS_SCENARIO']
log_path = os.environ['PENTAD_BRIGHTNESS_LOG']
state_path = os.environ['PENTAD_BRIGHTNESS_STATE']

def log():
    with open(log_path, 'a', encoding='utf-8') as stream:
        stream.write(json.dumps({'tool': tool, 'args': args}) + '\n')

def level():
    return int(open(state_path, encoding='ascii').read())

def set_level(value):
    with open(state_path, 'w', encoding='ascii') as stream:
        stream.write(str(value))

log()
if scenario == 'timeout' and tool == 'brightnessctl':
    time.sleep(12)
if scenario == 'output-changed' and tool == 'brightnessctl':
    time.sleep(2)

value = level()
if tool == 'brightnessctl':
    if args == ['--list', '--machine-readable']:
        if scenario == 'invalid-device':
            print('capslock,leds,1,100%,1')
        else:
            print(f'amdgpu_bl0,backlight,{value},{value}%,100')
    elif args[-1:] == ['info']:
        print(f'amdgpu_bl0,backlight,{value},{value}%,100')
    elif len(args) >= 5 and args[-2] == 'set':
        set_level(int(args[-1].rstrip('%')))
        value = level()
        print(f'amdgpu_bl0,backlight,{value},{value}%,100')
    else:
        sys.exit(3)
elif tool == 'ddcutil':
    if args == ['detect', '--brief']:
        print('Display 1')
        print(' I2C bus: /dev/i2c-7')
        print(' DRM connector: card1-HDMI-A-1')
    elif len(args) == 5 and args[0] == '--bus' and args[2:] == ['getvcp', '10', '--terse']:
        print(f'VCP 10 C {value} 100')
    elif len(args) == 5 and args[0] == '--bus' and args[2:4] == ['setvcp', '10']:
        set_level(int(args[4]))
    else:
        sys.exit(3)
else:
    sys.exit(4)
`;

function eventFrom(output) {
  const marker = 'PENTAD_TEST ';
  const line = output.split(/\r?\n/).find((entry) => entry.includes(marker));
  if (!line) return null;
  try { return JSON.parse(line.slice(line.indexOf(marker) + marker.length)); }
  catch { return null; }
}

async function runScenario(qs, scratch, scenario) {
  const config = path.join(scratch, `config-${scenario}`);
  const bin = path.join(scratch, `bin-${scenario}`);
  const home = path.join(scratch, `home-${scenario}`);
  const logPath = path.join(scratch, `fake-${scenario}.jsonl`);
  const statePath = path.join(scratch, `state-${scenario}`);
  for (const dir of [config, bin, home]) await mkdir(dir, { recursive: true, mode: 0o700 });
  await cp(path.join(repo, 'quickshell'), config, { recursive: true });
  const source = await readFile(fixture, 'utf8');
  await writeFile(path.join(config, 'shell.qml'), source.replaceAll('import "../services"', 'import "services"'));
  await writeFile(statePath, '40');

  for (const program of ['brightnessctl', 'ddcutil']) {
    if (scenario === 'missing-utility' || (scenario === 'start-fail' && program === 'brightnessctl')) continue;
    const target = path.join(bin, program);
    await writeFile(target, fakeUtility, { mode: 0o700 });
    await chmod(target, scenario === 'start-fail' && program === 'brightnessctl' ? 0o600 : 0o700);
  }
  if (scenario === 'start-fail') {
    const target = path.join(bin, 'brightnessctl');
    await writeFile(target, fakeUtility, { mode: 0o600 });
    await chmod(target, 0o600);
  }

  const env = {
    ...process.env,
    PATH: bin,
    HOME: home,
    XDG_CONFIG_HOME: path.join(scratch, `xdg-config-${scenario}`),
    XDG_DATA_HOME: path.join(scratch, `xdg-data-${scenario}`),
    XDG_STATE_HOME: path.join(scratch, `xdg-state-${scenario}`),
    XDG_CACHE_HOME: path.join(scratch, `xdg-cache-${scenario}`),
    PENTAD_BRIGHTNESS_SCENARIO: scenario,
    PENTAD_BRIGHTNESS_LOG: logPath,
    PENTAD_BRIGHTNESS_STATE: statePath,
    LANG: 'C.UTF-8',
  };
  for (const key of ['XDG_CONFIG_HOME', 'XDG_DATA_HOME', 'XDG_STATE_HOME', 'XDG_CACHE_HOME'])
    await mkdir(env[key], { recursive: true, mode: 0o700 });

  const child = spawn(qs, ['--no-duplicate', '--path', config], { cwd: repo, env, stdio: ['ignore', 'pipe', 'pipe'] });
  let output = '';
  child.stdout.setEncoding('utf8').on('data', (chunk) => { output += chunk; });
  child.stderr.setEncoding('utf8').on('data', (chunk) => { output += chunk; });
  let timedOut = false;
  const timeout = setTimeout(() => { timedOut = true; child.kill('SIGTERM'); }, 23000);
  const closed = await new Promise((resolve) => {
    child.once('error', (error) => resolve({ error }));
    child.once('close', (code, signal) => resolve({ code, signal }));
  });
  clearTimeout(timeout);

  const event = eventFrom(output);
  const records = (await readFile(logPath, 'utf8').catch(() => '')).split(/\r?\n/)
    .filter(Boolean).map((line) => JSON.parse(line));
  const checks = (event?.checks || []).slice();
  const calls = records.map((item) => `${item.tool} ${item.args.join(' ')}`);
  checks.push({ name: 'only-private-fake-utilities-ran', passed: records.every((item) => ['brightnessctl', 'ddcutil'].includes(item.tool)), detail: calls.join('\n') });
  if (scenario === 'internal-success') {
    checks.push({ name: 'internal-read-set-confirmed-readback-order', passed: calls.join('|') === [
      'brightnessctl --list --machine-readable', 'brightnessctl --device amdgpu_bl0 --machine-readable info',
      'brightnessctl --device amdgpu_bl0 --machine-readable info',
      'brightnessctl --device amdgpu_bl0 --machine-readable set 45%', 'brightnessctl --device amdgpu_bl0 --machine-readable info',
    ].join('|'), detail: calls.join('|') });
  } else if (scenario === 'internal-coalesce') {
    checks.push({ name: 'wheel-burst-skips-detection-and-coalesces-into-one-follow-up', passed: calls.join('|') === [
      'brightnessctl --list --machine-readable', 'brightnessctl --device amdgpu_bl0 --machine-readable info',
      'brightnessctl --device amdgpu_bl0 --machine-readable set 45%', 'brightnessctl --device amdgpu_bl0 --machine-readable info',
      'brightnessctl --device amdgpu_bl0 --machine-readable set 55%', 'brightnessctl --device amdgpu_bl0 --machine-readable info',
    ].join('|'), detail: calls.join('|') });
  } else if (scenario === 'external-coalesce') {
    checks.push({ name: 'ddc-burst-reuses-bus-and-max-without-detect', passed: calls.join('|') === [
      'ddcutil detect --brief', 'ddcutil --bus 7 getvcp 10 --terse',
      'ddcutil --bus 7 setvcp 10 45', 'ddcutil --bus 7 getvcp 10 --terse',
      'ddcutil --bus 7 setvcp 10 55', 'ddcutil --bus 7 getvcp 10 --terse',
    ].join('|'), detail: calls.join('|') });
  } else if (scenario === 'external-success') {
    checks.push({ name: 'external-ddc-detect-read-set-verify-order', passed: calls.join('|') === [
      'ddcutil detect --brief', 'ddcutil --bus 7 getvcp 10 --terse',
      'ddcutil --bus 7 getvcp 10 --terse',
      'ddcutil --bus 7 setvcp 10 45', 'ddcutil --bus 7 getvcp 10 --terse',
    ].join('|'), detail: calls.join('|') });
  } else if (scenario === 'safe-mode') {
    checks.push({ name: 'safe-mode-never-launched-write-utility-stage', passed: !records.some((item) => item.args.includes('set')), detail: calls.join('|') });
  } else if (scenario === 'missing-utility') {
    checks.push({ name: 'missing-tools-produced-no-external-execution', passed: records.length === 0, detail: calls.join('|') });
  } else if (scenario === 'invalid-device') {
    checks.push({ name: 'invalid-backlight-device-never-read-or-wrote', passed: records.length === 1 && calls[0] === 'brightnessctl --list --machine-readable', detail: calls.join('|') });
  } else if (scenario === 'start-fail') {
    checks.push({ name: 'non-executable-fake-reported-start-failure', passed: records.length === 0, detail: calls.join('|') });
  } else if (scenario === 'timeout') {
    checks.push({ name: 'timeout-killed-fake-with-no-followup-command', passed: records.length === 1, detail: calls.join('|') });
  } else if (scenario === 'output-changed') {
    checks.push({ name: 'output-change-routed-new-output-to-ddc', passed: records.some((item) => item.tool === 'ddcutil' && item.args[0] === 'detect'), detail: calls.join('|') });
  }
  return {
    scenario,
    status: !closed.error && !timedOut && closed.code === 0 && event?.status === 'pass'
      && checks.length > 0 && checks.every((item) => item.passed === true) ? 'pass' : 'fail',
    checks, error: closed.error?.message, timedOut, exitCode: closed.code,
    output: closed.code === 0 ? undefined : output,
  };
}

async function main(argv) {
  let qs = process.env.PENTAD_QS_BIN || defaultQs;
  let reportPath;
  for (let i = 0; i < argv.length; i++) {
    if (argv[i] === '--qs' && argv[i + 1]) qs = argv[++i];
    else if (argv[i] === '--report' && argv[i + 1]) reportPath = argv[++i];
    else throw new Error(`Unknown or incomplete argument: ${argv[i]}`);
  }
  const version = spawnSync(qs, ['--version'], { encoding: 'utf8', timeout: 5000 });
  if (version.error || version.status !== 0 || !/Quickshell 0\.3\.2\b/.test(`${version.stdout}\n${version.stderr}`))
    throw new Error(`Need pinned Quickshell 0.3.2 (${qs}): ${version.error?.message || version.stderr || version.stdout}`);

  const scratch = await mkdtemp(path.join(os.tmpdir(), 'pentad-brightness-native-'));
  try {
    const scenarios = ['internal-success', 'external-success', 'internal-coalesce', 'external-coalesce', 'missing-utility', 'invalid-device', 'start-fail', 'timeout', 'output-changed', 'safe-mode'];
    const results = [];
    for (const scenario of scenarios) results.push(await runScenario(qs, scratch, scenario));
    const report = {
      status: results.every((item) => item.status === 'pass') ? 'pass' : 'fail',
      scenario: 'brightness-native', qs: version.stdout.trim(),
      safety: 'private fake-only PATH; no real brightness utility reachable',
      scenarios: results,
      checks: results.flatMap((item) => item.checks.map((check) => ({ scenario: item.scenario, ...check }))),
    };
    if (reportPath) {
      await mkdir(path.dirname(path.resolve(reportPath)), { recursive: true });
      await writeFile(path.resolve(reportPath), `${JSON.stringify(report, null, 2)}\n`, { mode: 0o600 });
    }
    process.stdout.write(`${JSON.stringify(report, null, 2)}\n`);
    return report.status === 'pass' ? 0 : 1;
  } finally {
    await rm(scratch, { recursive: true, force: true });
  }
}

main(process.argv.slice(2)).then((code) => { process.exitCode = code; }).catch((error) => {
  console.error(JSON.stringify({ status: 'fail', scenario: 'brightness-native', error: error.stack || String(error) }, null, 2));
  process.exitCode = 1;
});
