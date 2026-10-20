#!/usr/bin/env node
import { chmod, cp, mkdir, readFile, readdir, symlink, unlink, writeFile } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { spawn, spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { meetsFloor, parseVersion } from './check-quickshell.mjs';

const repo = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const graphicalScenarios = [
  'shell-entrypoint', 'runtime', 'output-lifecycle', 'design-system', 'bar', 'media', 'artwork',
  'popups', 'control-center', 'control-templates', 'tool-context', 'application-mixer', 'notification-popup', 'system-controls', 'plugin-host', 'config-store',
  'sidebar', 'clock-timer', 'shelf', 'window-navigation', 'navigation-adapter', 'window-navigation-visual', 'spotlight',
];
const nativeScenarios = [
  ['network', 'tests/tooling/network-native.mjs'],
  ['network-health', 'tests/tooling/network-health-native.mjs'],
  ['power', 'tests/tooling/power-native.mjs'],
  ['audio', 'tests/tooling/audio-native.mjs'],
  ['desktop', 'tests/tooling/desktop-native.mjs'],
  ['brightness', 'tests/tooling/brightness-native.mjs'],
  ['lyrics', 'tests/tooling/lyrics-native.mjs'],
  ['visualizer', 'tests/tooling/visualizer-native.mjs'],
  ['media-mpris', 'tests/tooling/media-native.mjs'],
];
const runtimeFailure = /TypeError:|ReferenceError:|SyntaxError:|Binding loop detected|Failed to load configuration|Cannot load controller|Unknown signal|Cannot assign to non-existent property|Detected function .* in Connections element[^\n]*no signal .* matches/i;
const missingModule = /(?:module|plugin).*(?:not installed|not found|could not be loaded|failed to load|unavailable)|could not load.*(?:module|plugin)|could not find (?:the )?(?:qt )?(?:platform )?(?:module|plugin)|no module named/i;
const hostBlocked = /operation not permitted|permission denied|spawn(?:Sync)? .*EPERM/i;

export function infrastructureBlockReason(log) {
  if (missingModule.test(log)) return 'required module or plugin is unavailable';
  if (hostBlocked.test(log)) return 'host denied a fixture subprocess';
  return '';
}

export function parseArgs(argv) {
  if (argv[0] === '--') argv = argv.slice(1);
  const options = { qs: '', reportDir: '', actual: false };
  const seen = new Set();
  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i];
    if (arg === '--actual') {
      if (seen.has(arg)) throw new Error('Duplicate argument: --actual');
      seen.add(arg);
      options.actual = true;
      continue;
    }
    if (arg !== '--qs' && arg !== '--report-dir') throw new Error(`Unknown or incomplete argument: ${arg}`);
    if (seen.has(arg)) throw new Error(`Duplicate argument: ${arg}`);
    seen.add(arg);
    const value = argv[++i];
    if (!value || value.startsWith('--')) throw new Error(`${arg} requires a value`);
    options[arg === '--qs' ? 'qs' : 'reportDir'] = value;
  }
  if (!options.qs) throw new Error('Usage: verify-quickshell.mjs --qs <binary> [--report-dir <path>] [--actual]');
  if (!options.reportDir) {
    const stamp = new Date().toISOString().replaceAll(':', '-').replaceAll('.', '-');
    options.reportDir = path.join(repo, 'artifacts', 'migration', 'integration-final', stamp);
  }
  return options;
}

function scanChecks(value, problems = []) {
  if (Array.isArray(value)) {
    for (const item of value) scanChecks(item, problems);
  } else if (value && typeof value === 'object') {
    if (value.passed === false || value.status === 'fail' || value.status === 'failed' || value.status === 'blocked')
      problems.push({ name: value.name || value.scenario || 'failed assertion', status: value.status === 'blocked' ? 'blocked' : 'fail' });
    for (const [key, child] of Object.entries(value)) if (key !== 'checks') scanChecks(child, problems);
    if (Array.isArray(value.checks)) for (const child of value.checks) scanChecks(child, problems);
  }
  return problems;
}

export function assessScenarioReport(report, log = '') {
  if (!report || typeof report !== 'object') return { status: 'fail', reason: 'missing or invalid report' };
  if (report.status === 'blocked') return { status: 'blocked', reason: 'scenario reported blocked' };
  if (report.status !== 'pass') return { status: 'fail', reason: `scenario status is ${String(report.status)}` };
  if (!Array.isArray(report.checks) || report.checks.length === 0) return { status: 'fail', reason: 'scenario has no checks' };
  const invalid = findInvalidChecks(report.checks);
  if (invalid.length) return { status: 'fail', reason: `checks missing a passing result: ${invalid.join(', ')}` };
  const failed = scanChecks(report.checks);
  if (failed.some((item) => item.status === 'blocked'))
    return { status: 'blocked', reason: `blocked checks: ${[...new Set(failed.filter((item) => item.status === 'blocked').map((item) => item.name))].join(', ')}` };
  if (failed.length) return { status: 'fail', reason: `failed checks: ${[...new Set(failed.map((item) => item.name))].join(', ')}` };
  if (runtimeFailure.test(log)) return { status: 'fail', reason: 'runtime warning/error found in scenario output' };
  return { status: 'pass', reason: '' };
}

function findInvalidChecks(value, names = [], invalid = []) {
  if (Array.isArray(value)) {
    for (const item of value) findInvalidChecks(item, names, invalid);
  } else if (value && typeof value === 'object') {
    if ('name' in value || 'passed' in value || 'status' in value) {
      const name = value.name || value.scenario || 'unnamed check';
      const valid = value.passed === true || ['pass', 'passed', 'fail', 'failed', 'blocked'].includes(value.status);
      if (!valid && (('passed' in value) || ('status' in value) || 'name' in value)) invalid.push(name);
    }
    for (const [key, child] of Object.entries(value)) if (key !== 'checks') findInvalidChecks(child, names, invalid);
    if (Array.isArray(value.checks)) findInvalidChecks(value.checks, names, invalid);
  }
  return invalid;
}

export function rootChecks(records) {
  return records.map((record) => ({
    name: `${record.name} completed`,
    passed: record.status === 'pass',
    status: record.status,
    detail: record.reason || record.error || '',
  }));
}

function safeEnv({ binDir, scratch, wayland = true }) {
  const pathValue = [binDir, process.env.PATH || '/usr/bin:/bin'].join(path.delimiter);
  const env = {
    PATH: pathValue,
    HOME: scratch,
    XDG_CONFIG_HOME: path.join(scratch, '.config'),
    XDG_DATA_HOME: path.join(scratch, '.local', 'share'),
    XDG_CACHE_HOME: path.join(scratch, '.cache'),
    XDG_STATE_HOME: path.join(scratch, '.local', 'state'),
    LANG: process.env.LANG || 'C.UTF-8',
    PENTAD_PREVIEW: '1',
    PENTAD_SAFE_MODE: '1',
  };
  if (wayland && process.env.WAYLAND_DISPLAY && process.env.XDG_RUNTIME_DIR) {
    env.XDG_RUNTIME_DIR = process.env.XDG_RUNTIME_DIR;
    env.WAYLAND_DISPLAY = path.isAbsolute(process.env.WAYLAND_DISPLAY)
      ? process.env.WAYLAND_DISPLAY
      : path.join(process.env.XDG_RUNTIME_DIR, process.env.WAYLAND_DISPLAY);
  }
  if (process.env.DISPLAY) env.DISPLAY = process.env.DISPLAY;
  return env;
}

function resolveHostGeist() {
  const result = spawnSync('fc-match', ['-f', '%{family}\n%{file}', 'Geist'], {
    encoding: 'utf8', timeout: 5000, env: process.env,
  });
  const [resolved = '', source = ''] = (result.stdout || '').trim().split('\n');
  const exactFamily = resolved.split(',').some((family) => family.trim() === 'Geist');
  const validSource = path.isAbsolute(source) && /\.(?:ttf|otf)$/i.test(source);
  return {
    requested: 'Geist',
    resolved: result.status === 0 && exactFamily ? resolved : 'unavailable',
    source: result.status === 0 && exactFamily && validSource ? source : '',
    reason: result.error?.message || (!exactFamily ? `fc-match resolved ${resolved || 'no family'}` : !validSource ? 'resolved font file is not TTF/OTF' : ''),
  };
}

async function stageHostGeist(font, scratch) {
  if (!font.source) return { staged: false, reason: font.reason || 'host Geist font unavailable' };
  const dataHome = path.join(scratch, '.local', 'share');
  const fontDir = path.join(dataHome, 'fonts');
  const configHome = path.join(scratch, '.config');
  const cacheHome = path.join(scratch, '.cache');
  const stateHome = path.join(scratch, '.local', 'state');
  await Promise.all([fontDir, configHome, cacheHome, stateHome].map((directory) =>
    mkdir(directory, { recursive: true, mode: 0o700 })));
  const target = path.join(fontDir, path.basename(font.source));
  await cp(font.source, target);
  await chmod(target, 0o600);
  const env = {
    ...process.env,
    HOME: scratch,
    XDG_CONFIG_HOME: configHome,
    XDG_DATA_HOME: dataHome,
    XDG_CACHE_HOME: cacheHome,
    XDG_STATE_HOME: stateHome,
  };
  const cache = spawnSync('fc-cache', ['-f', fontDir], { encoding: 'utf8', timeout: 10000, env });
  const match = spawnSync('fc-match', ['-f', '%{family}', 'Geist'], { encoding: 'utf8', timeout: 5000, env });
  const names = (match.stdout || '').trim().split(',').map((family) => family.trim());
  const staged = cache.status === 0 && match.status === 0 && names.includes('Geist');
  return { staged, reason: staged ? '' : cache.error?.message || match.error?.message || 'private fontconfig could not resolve staged Geist' };
}

async function writePrivate(filePath, text) {
  await mkdir(path.dirname(filePath), { recursive: true, mode: 0o700 });
  await writeFile(filePath, text, { mode: 0o600 });
  await chmod(filePath, 0o600);
}

async function runProcess(command, args, { cwd = repo, env, timeoutMs = 120000 } = {}) {
  return new Promise((resolve) => {
    let output = '';
    let timedOut = false;
    let settled = false;
    let killTimer;
    let child;
    try {
      child = spawn(command, args, { cwd, env, stdio: ['ignore', 'pipe', 'pipe'] });
    } catch (error) {
      resolve({ error: error.message, output, timedOut: false });
      return;
    }
    const collect = (chunk) => { output += chunk; };
    child.stdout.setEncoding('utf8').on('data', collect);
    child.stderr.setEncoding('utf8').on('data', collect);
    const timer = setTimeout(() => {
      timedOut = true;
      child.kill('SIGTERM');
      killTimer = setTimeout(() => child.kill('SIGKILL'), 1000);
      killTimer.unref();
    }, timeoutMs);
    const finish = (result) => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      clearTimeout(killTimer);
      resolve({ ...result, output, timedOut });
    };
    child.once('error', (error) => finish({ error: error.message }));
    child.once('close', (code, signal) => finish({ code, signal }));
  });
}

async function commandStep(name, command, args, env, reportDir, timeoutMs) {
  const startedAt = new Date().toISOString();
  const result = await runProcess(command, args, { env, timeoutMs });
  const log = path.join(reportDir, `${name}.log`);
  await writePrivate(log, result.output || result.error || '(no output)\n');
  const passed = !result.error && !result.timedOut && result.code === 0 && !runtimeFailure.test(result.output);
  const status = passed ? 'pass' : result.timedOut || result.error || missingModule.test(result.output) || hostBlocked.test(result.output) ? 'blocked' : 'fail';
  const record = {
    name, status, startedAt, command: [command, ...args], exitCode: result.code ?? null,
    signal: result.signal || null, timedOut: result.timedOut, timeoutMs, error: result.error || null,
    checks: [{ name: `${name} command completed without runtime errors`, passed,
      detail: result.error || (result.timedOut ? `timeout after ${timeoutMs}ms` : `exit=${result.code}`) }],
    log: path.basename(log),
  };
  await writePrivate(path.join(reportDir, `${name}.json`), `${JSON.stringify(record, null, 2)}\n`);
  return record;
}

async function fixtureStep(name, command, args, env, reportDir, timeoutMs = 120000) {
  const reportPath = path.join(reportDir, `${name}.json`);
  for (const file of [reportPath, `${reportPath}.log`]) {
    try { await unlink(file); } catch (error) { if (error.code !== 'ENOENT') throw error; }
  }
  const result = await runProcess(command, args(reportPath), { env, timeoutMs });
  const runnerLogPath = path.join(reportDir, `${name}.runner.log`);
  await writePrivate(runnerLogPath, result.output || result.error || '(no output)\n');
  let childReport;
  try {
    await chmod(reportPath, 0o600);
    childReport = JSON.parse(await readFile(reportPath, 'utf8'));
  } catch { childReport = null; }
  try { await chmod(`${reportPath}.log`, 0o600); } catch {}
  const logs = [result.output || '', result.error || ''];
  try { logs.push(await readFile(`${reportPath}.log`, 'utf8')); } catch {}
  if (childReport && Array.isArray(childReport.artifacts)) {
    for (const item of childReport.artifacts) {
      const candidate = typeof item === 'string' ? item : item && item.path;
      if (!candidate || !/\.log$/.test(candidate)) continue;
      try { logs.push(await readFile(candidate, 'utf8')); } catch {}
    }
  }
  const fullLog = logs.join('\n');
  let assessment;
  if (result.error || result.timedOut) assessment = { status: 'blocked', reason: result.error || `timeout after ${timeoutMs}ms` };
  else if (infrastructureBlockReason(fullLog)) assessment = { status: 'blocked', reason: infrastructureBlockReason(fullLog) };
  else if (!childReport) assessment = { status: 'fail', reason: 'scenario report missing or invalid' };
  else if (childReport.status === 'blocked') assessment = { status: 'blocked', reason: 'scenario reported blocked' };
  else assessment = assessScenarioReport(childReport, fullLog);
  if (result.code !== 0 && assessment.status === 'pass') assessment = infrastructureBlockReason(fullLog)
    ? { status: 'blocked', reason: infrastructureBlockReason(fullLog) }
    : { status: 'fail', reason: `runner exit=${result.code}` };
  const record = {
    name, status: assessment.status, reason: assessment.reason,
    command: [command, ...args(reportPath)], exitCode: result.code ?? null,
    signal: result.signal || null, timedOut: result.timedOut, timeoutMs,
    checks: childReport?.checks || [], report: path.basename(reportPath),
    runnerLog: path.basename(runnerLogPath),
  };
  await writePrivate(path.join(reportDir, `${name}.integration.json`), `${JSON.stringify(record, null, 2)}\n`);
  return record;
}

function overallStatus(records) {
  if (records.some((item) => item.status === 'fail')) return 'fail';
  if (records.some((item) => item.status === 'blocked')) return 'blocked';
  return records.length > 0 && records.every((item) => item.status === 'pass') ? 'pass' : 'fail';
}

export async function main(argv = process.argv.slice(2)) {
  let options;
  try { options = parseArgs(argv); }
  catch (error) { process.stderr.write(`${error.message}\n`); return 2; }

  const reportDir = path.resolve(options.reportDir);
  await mkdir(reportDir, { recursive: true, mode: 0o700 });
  await chmod(reportDir, 0o700);
  const { mkdtemp, rm } = await import('node:fs/promises');
  const hostFont = resolveHostGeist();
  const scratch = await mkdtemp(path.join(os.tmpdir(), 'pentad-qs-integration-'));
  await chmod(scratch, 0o700);
  const records = [];
  const rootReport = {
    status: 'blocked', startedAt: new Date().toISOString(), qs: path.resolve(options.qs),
    requestedActualCava: options.actual, reportDir, quickshell: {}, records,
  };
  const binDir = path.join(scratch, 'bin');
  await mkdir(binDir, { mode: 0o700 });
  const alias = path.join(binDir, 'qs');
  let env;
  try {
    const stagedFont = await stageHostGeist(hostFont, scratch);
    await symlink(rootReport.qs, alias);
    env = safeEnv({ binDir, scratch });
    const version = await runProcess(rootReport.qs, ['--version'], { env, timeoutMs: 10000 });
    const versionText = version.output.trim();
    rootReport.quickshell.versionText = versionText;
    rootReport.quickshell.version = parseVersion(versionText);
    rootReport.quickshell.binaryRevision = versionText;
    const versionPassed = !version.error && version.code === 0 && meetsFloor(rootReport.quickshell.version);
    const versionRecord = {
      name: 'quickshell-version-floor', status: versionPassed ? 'pass' : 'blocked',
      checks: [{ name: 'explicit binary is Quickshell >= 0.3.2', passed: versionPassed,
        detail: version.error || versionText || 'version unavailable' }],
      exitCode: version.code ?? null,
    };
    records.push(versionRecord);
    await writePrivate(path.join(reportDir, 'quickshell-version.json'), `${JSON.stringify(versionRecord, null, 2)}\n`);

    const displayAvailable = Boolean(env.WAYLAND_DISPLAY && env.XDG_RUNTIME_DIR);
    rootReport.environment = {
      wayland: displayAvailable,
      displaySocket: displayAvailable ? env.WAYLAND_DISPLAY : null,
      font: { requested: hostFont.requested, resolved: hostFont.resolved, staged: stagedFont.staged, reason: stagedFont.reason },
    };
    records.push(await commandStep('build-quickshell', process.execPath,
      ['scripts/build-quickshell.mjs'], env, reportDir));
    const unitFiles = [];
    for (const folder of ['tests/tooling', 'tests/quickshell']) {
      for (const item of (await readdir(path.join(repo, folder))).sort())
        if (item.endsWith('.test.mjs')) unitFiles.push(path.join(folder, item));
    }
    records.push(await commandStep('node-tests', process.execPath,
      ['--test', ...unitFiles], env, reportDir));
    records.push(await commandStep('python-file-tests', 'python3',
      ['-m', 'unittest', 'discover', '-s', 'tests/files'], env, reportDir));

    if (versionPassed) {
      if (!displayAvailable) {
        for (const name of graphicalScenarios) {
          const record = { name, status: 'blocked', reason: 'active Wayland socket and XDG_RUNTIME_DIR are required',
            checks: [{ name: 'graphical fixture prerequisites', passed: false, detail: 'display unavailable' }] };
          records.push(record);
          await writePrivate(path.join(reportDir, `${name}.integration.json`), `${JSON.stringify(record, null, 2)}\n`);
        }
      } else {
        for (const name of graphicalScenarios) {
          records.push(await fixtureStep(name, process.execPath, (reportPath) => [
            'scripts/test-quickshell.mjs', '--scenario', name, '--report', reportPath,
          ], env, reportDir, 60000));
        }
      }

      if (!displayAvailable) {
        for (const [name] of nativeScenarios) {
          const record = { name: `${name}-native`, status: 'blocked', reason: 'active Wayland socket and XDG_RUNTIME_DIR are required',
            checks: [{ name: 'native fixture prerequisites', passed: false, detail: 'display unavailable' }] };
          records.push(record);
          await writePrivate(path.join(reportDir, `${name}-native.integration.json`), `${JSON.stringify(record, null, 2)}\n`);
        }
        const record = { name: 'ipc-reload-native', status: 'blocked', reason: 'active Wayland socket and XDG_RUNTIME_DIR are required',
          checks: [{ name: 'IPC fixture prerequisites', passed: false, detail: 'display unavailable' }] };
        records.push(record);
        await writePrivate(path.join(reportDir, 'ipc-reload-native.integration.json'), `${JSON.stringify(record, null, 2)}\n`);
      } else {
        for (const [name, script] of nativeScenarios) {
          const args = [script, '--qs', rootReport.qs, '--report', path.join(reportDir, `${name}-native.json`)];
          if (name === 'visualizer' && options.actual) args.push('--actual');
          records.push(await fixtureStep(`${name}-native`, process.execPath, () => args, env, reportDir, 120000));
        }
        records.push(await fixtureStep('ipc-reload-native', 'python3', () => [
          'tests/tooling/ipc-native.py', '--report', path.join(reportDir, 'ipc-reload-native.json'),
        ], env, reportDir, 60000));
      }
    } else {
      for (const name of [...graphicalScenarios, ...nativeScenarios.map(([key]) => `${key}-native`), 'ipc-reload-native']) {
        const record = { name, status: 'blocked', reason: 'Quickshell version floor failed; fixture not launched',
          checks: [{ name: 'version prerequisite', passed: false, detail: versionText || version.error || 'version unavailable' }] };
        records.push(record);
        await writePrivate(path.join(reportDir, `${name}.integration.json`), `${JSON.stringify(record, null, 2)}\n`);
      }
    }
  } catch (error) {
    records.push({ name: 'integration-runner', status: 'fail', reason: error.stack || String(error),
      checks: [{ name: 'runner completed', passed: false, detail: String(error) }] });
  } finally {
    const expected = [
      'quickshell-version-floor', 'build-quickshell', 'node-tests', 'python-file-tests',
      ...graphicalScenarios, ...nativeScenarios.map(([name]) => `${name}-native`), 'ipc-reload-native',
    ];
    for (const name of expected) {
      if (records.some((item) => item.name === name)) continue;
      const record = { name, status: 'blocked', reason: 'runner stopped before this check was launched',
        checks: [{ name: 'scenario report is present', passed: false, detail: 'not launched' }] };
      records.push(record);
      const file = name === 'quickshell-version-floor' ? 'quickshell-version.json'
        : ['build-quickshell', 'node-tests', 'python-file-tests'].includes(name)
          ? `${name}.json` : `${name}.integration.json`;
      await writePrivate(path.join(reportDir, file), `${JSON.stringify(record, null, 2)}\n`);
    }
    rootReport.status = overallStatus(records);
    rootReport.finishedAt = new Date().toISOString();
    rootReport.checks = rootChecks(records);
    rootReport.summary = Object.fromEntries(['pass', 'fail', 'blocked'].map((status) =>
      [status, records.filter((item) => item.status === status).length]));
    await writePrivate(path.join(reportDir, 'integration.json'), `${JSON.stringify(rootReport, null, 2)}\n`);
    await rm(scratch, { recursive: true, force: true });
  }
  process.stdout.write(`${rootReport.status}: ${rootReport.summary.pass} passed, ${rootReport.summary.fail} failed, ${rootReport.summary.blocked} blocked; ${reportDir}\n`);
  return rootReport.status === 'pass' ? 0 : rootReport.status === 'blocked' ? 3 : 1;
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url))
  process.exitCode = await main(process.argv.slice(2));
