#!/usr/bin/env node
import { cp, mkdir, mkdtemp, readFile, rm, writeFile } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { spawn, spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const repo = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const defaultQs = '/tmp/pentad-qs-bin/qs';
const marker = 'PENTAD_VISUALIZER_TEST ';
const fakeCava = String.raw`#!/usr/bin/node
const fs = require('node:fs');
const log = process.env.PENTAD_CAVA_LOG;
const record = (event, extra = {}) => fs.appendFileSync(log, JSON.stringify({ event, pid: process.pid, ...extra }) + '\n');
let config = '';
let emitted = false;
process.stdin.setEncoding('utf8');
process.stdin.on('data', chunk => {
  config += chunk;
  if (emitted || !config.includes('noise_reduction = 20')) return;
  emitted = true;
  record('configured', { config });
  if (!config.includes('bars = 50') || !config.includes('raw_target = /dev/stdout')) process.exit(3);
  const frame = Array(50).fill('500').join(';') + ';\n';
  record('frame', { bytes: frame.length, ending: frame.slice(-2) });
  process.stdout.write(frame);
  const timer = setInterval(() => process.stdout.write(frame), 40);
  process.on('SIGTERM', () => { clearInterval(timer); record('stopped'); process.exit(0); });
});
record('started', { argv: process.argv.slice(2) });
process.on('exit', code => record('exit', { code }));
`;

function parseArgs(argv) {
  const options = { qs: process.env.PENTAD_QS_BIN || defaultQs, report: undefined, actual: false };
  for (let i = 0; i < argv.length; i++) {
    if (argv[i] === '--qs' && argv[i + 1]) options.qs = argv[++i];
    else if (argv[i] === '--report' && argv[i + 1]) options.report = argv[++i];
    else if (argv[i] === '--actual') options.actual = true;
    else throw new Error(`Unknown or incomplete argument: ${argv[i]}`);
  }
  if (!options.report) throw new Error('Usage: visualizer-native.mjs --report <path> [--qs <pinned-qs>] [--actual]');
  return options;
}

function eventFrom(output) {
  const line = output.split(/\r?\n/).find((item) => item.includes(marker));
  return line ? JSON.parse(line.slice(line.indexOf(marker) + marker.length)) : null;
}

async function runNative({ qs, config, env, mode, timeoutMs = 8000 }) {
  const runEnv = { ...env, PENTAD_VISUALIZER_MODE: mode };
  const child = spawn('/usr/bin/dbus-run-session', ['--', qs, '--no-duplicate', '--path', config], {
    cwd: repo, env: runEnv, stdio: ['ignore', 'pipe', 'pipe'],
  });
  let output = '';
  child.stdout.setEncoding('utf8').on('data', chunk => { output += chunk; });
  child.stderr.setEncoding('utf8').on('data', chunk => { output += chunk; });
  const result = await new Promise((resolve, reject) => {
    const timer = setTimeout(() => { child.kill('SIGKILL'); reject(new Error(`${mode} timed out:\n${output}`)); }, timeoutMs);
    child.once('error', error => { clearTimeout(timer); reject(error); });
    child.once('close', (code, signal) => { clearTimeout(timer); resolve({ code, signal }); });
  });
  return { ...result, output, event: eventFrom(output) };
}

async function main() {
  const options = parseArgs(process.argv.slice(2));
  const reportPath = path.resolve(options.report);
  const scratch = await mkdtemp(path.join(os.tmpdir(), 'pentad-visualizer-native-'));
  const report = { status: 'fail', scenario: 'visualizer-native', qs: options.qs,
    actualCavaRequested: options.actual, checks: [], artifacts: [] };
  let outputs = [];
  try {
    const version = spawnSync(options.qs, ['--version'], { encoding: 'utf8', timeout: 5000 });
    const versionText = `${version.stdout || ''}\n${version.stderr || ''}`;
    report.quickshellVersion = versionText.trim();
    if (version.error || version.status !== 0 || !/Quickshell 0\.3\.2\b/.test(versionText))
      throw new Error(`Requires pinned Quickshell 0.3.2: ${version.error?.message || versionText}`);

    const [bin, config] = ['bin', 'config'].map(name => path.join(scratch, name));
    for (const dir of [bin, config, path.join(config, 'services'), path.join(config, 'logic'),
      path.join(config, 'theme'), path.join(scratch, 'runtime'), path.join(scratch, 'data'),
      path.join(scratch, 'cache'), path.join(scratch, 'state')])
      await mkdir(dir, { recursive: true, mode: 0o700 });
    const fakePath = path.join(bin, 'cava');
    await writeFile(fakePath, fakeCava, { mode: 0o700 });
    await Promise.all([
      cp(path.join(repo, 'quickshell/services/Visualizer.qml'), path.join(config, 'services/Visualizer.qml')),
      cp(path.join(repo, 'quickshell/logic/visualizer.mjs'), path.join(config, 'logic/visualizer.mjs')),
      cp(path.join(repo, 'quickshell/logic/theme.mjs'), path.join(config, 'logic/theme.mjs')),
      cp(path.join(repo, 'quickshell/theme'), path.join(config, 'theme'), { recursive: true }),
      cp(path.join(repo, 'quickshell/tests/visualizer-native.qml'), path.join(config, 'shell.qml')),
    ]);
    const fakeLog = path.join(scratch, 'fake-cava.jsonl');
    const commonEnv = {
      PATH: `${bin}:/usr/bin:/bin`, HOME: scratch,
      XDG_CONFIG_HOME: path.join(scratch, 'xdg-config'), XDG_DATA_HOME: path.join(scratch, 'data'),
      XDG_CACHE_HOME: path.join(scratch, 'cache'), XDG_STATE_HOME: path.join(scratch, 'state'),
      XDG_RUNTIME_DIR: path.join(scratch, 'runtime'), LANG: 'C.UTF-8', QT_QPA_PLATFORM: 'offscreen',
      GIO_USE_VFS: 'local', PENTAD_CAVA_LOG: fakeLog,
    };
    for (const key of ['XDG_CONFIG_HOME']) await mkdir(commonEnv[key], { recursive: true, mode: 0o700 });

    const checks = [];
    for (const mode of ['fake', 'reduced-motion', 'preview', 'safe-mode']) {
      const env = { ...commonEnv };
      const result = await runNative({ qs: options.qs, config, env, mode });
      outputs.push(`[${mode}]\n${result.output}`);
      checks.push(...(result.event?.checks || []).map(item => ({ ...item, passed: item.passed === true })));
      checks.push({ name: `${mode} native fixture exits successfully`, passed: result.code === 0 && result.event?.status === 'pass', detail: `code=${result.code}; ${result.signal || ''}` });
    }

    const missingEnv = { ...commonEnv, PATH: path.join(scratch, 'empty-path') };
    await mkdir(missingEnv.PATH, { mode: 0o700 });
    await cp('/usr/bin/dbus-daemon', path.join(missingEnv.PATH, 'dbus-daemon'));
    const missing = await runNative({ qs: options.qs, config, env: missingEnv, mode: 'missing' });
    outputs.push(`[missing]\n${missing.output}`);
    checks.push(...(missing.event?.checks || []).map(item => ({ ...item, passed: item.passed === true })));
    checks.push({ name: 'missing-utility fixture exits successfully', passed: missing.code === 0 && missing.event?.status === 'pass', detail: `code=${missing.code}` });

    const records = (await readFile(fakeLog, 'utf8').catch(() => '')).split(/\r?\n/).filter(Boolean).map(line => JSON.parse(line));
    report.fakeCavaRecords = records;
    const starts = records.filter(item => item.event === 'started');
    const configs = records.filter(item => item.event === 'configured');
    checks.push({ name: 'fake CAVA receives one stdin config on each start',
      passed: starts.length === 2 && configs.length === 2 && configs.every(item => item.config.includes('bars = 50')
        && item.config.includes('frame_delimiter = 10') && item.config.includes('raw_target = /dev/stdout')),
      detail: `starts=${starts.length}; configs=${configs.length}` });

    if (options.actual) {
      const actualEnv = { ...commonEnv, PATH: '/usr/local/bin:/usr/bin:/bin',
        PULSE_SERVER: process.env.PULSE_SERVER || (process.env.XDG_RUNTIME_DIR
          ? `unix:${path.join(process.env.XDG_RUNTIME_DIR, 'pulse/native')}` : '') };
      delete actualEnv.PENTAD_CAVA_LOG;
      const actual = await runNative({ qs: options.qs, config, env: actualEnv, mode: 'actual', timeoutMs: 9000 });
      outputs.push(`[actual-cava]\n${actual.output}`);
      checks.push(...(actual.event?.checks || []).map(item => ({ ...item, passed: item.passed === true })));
      checks.push({ name: 'installed CAVA native probe exits successfully', passed: actual.code === 0 && actual.event?.status === 'pass', detail: `code=${actual.code}` });
    }

    report.checks = checks;
    report.status = checks.length && checks.every(item => item.passed) ? 'pass' : 'fail';
  } catch (error) {
    report.error = error.stack || String(error);
  } finally {
    await mkdir(path.dirname(reportPath), { recursive: true });
    const logPath = `${reportPath}.log`;
    await writeFile(logPath, outputs.join('\n'), { mode: 0o600 });
    report.artifacts = [logPath];
    await writeFile(reportPath, `${JSON.stringify(report, null, 2)}\n`, { mode: 0o600 });
    await rm(scratch, { recursive: true, force: true });
  }
  process.stdout.write(`${JSON.stringify(report, null, 2)}\n`);
  return report.status === 'pass' ? 0 : 1;
}

main().then(code => { process.exitCode = code; }).catch(error => {
  console.error(error.stack || String(error));
  process.exitCode = 1;
});
