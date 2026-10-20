#!/usr/bin/env node
import { cp, mkdir, mkdtemp, readFile, rm, writeFile } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { spawn, spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const repo = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const defaultQs = '/tmp/pentad-qs-bin/qs';
const fixture = path.join(repo, 'quickshell/tests/network-native.qml');
const marker = 'PENTAD_TEST ';

function parseArgs(argv) {
  const options = { qs: process.env.PENTAD_QS_BIN || defaultQs, report: '' };
  for (let i = 0; i < argv.length; i++) {
    if (argv[i] === '--qs' && argv[i + 1]) options.qs = argv[++i];
    else if (argv[i] === '--report' && argv[i + 1]) options.report = argv[++i];
    else throw new Error(`Unknown or incomplete argument: ${argv[i]}`);
  }
  if (!options.report) throw new Error('Usage: network-native.mjs --report <path> [--qs <pinned-qs>]');
  return options;
}

function eventFrom(output) {
  const line = output.split(/\r?\n/).find((item) => item.includes(marker));
  if (!line) return null;
  try { return JSON.parse(line.slice(line.indexOf(marker) + marker.length)); }
  catch { return null; }
}

async function main() {
  const options = parseArgs(process.argv.slice(2));
  const reportPath = path.resolve(options.report);
  const report = { status: 'fail', scenario: 'network-native', checks: [], artifacts: [] };
  let output = '';
  let scratch;
  try {
    const version = spawnSync(options.qs, ['--version'], { encoding: 'utf8', timeout: 5000 });
    const versionText = `${version.stdout || ''}\n${version.stderr || ''}`;
    report.quickshellVersion = versionText.trim();
    if (version.error || version.status !== 0 || !/Quickshell 0\.3\.2\b/.test(versionText))
      throw new Error(`Requires pinned Quickshell 0.3.2: ${version.error?.message || versionText}`);

    const wayland = process.env.WAYLAND_DISPLAY;
    if (!wayland || !process.env.XDG_RUNTIME_DIR) throw new Error('Native fixture requires an active Wayland session');
    scratch = await mkdtemp(path.join(os.tmpdir(), 'pentad-network-native-'));
    const config = path.join(scratch, 'config');
    const runtime = path.join(scratch, 'runtime');
    for (const dir of [config, runtime, path.join(scratch, 'xdg-config'), path.join(scratch, 'xdg-data'),
      path.join(scratch, 'xdg-state'), path.join(scratch, 'xdg-cache')])
      await mkdir(dir, { recursive: true, mode: 0o700 });
    await cp(path.join(repo, 'quickshell'), config, { recursive: true, dereference: false });
    const source = await readFile(path.join(config, 'tests/network-native.qml'), 'utf8');
    await writeFile(path.join(config, 'shell.qml'), source
      .replaceAll('import "../services"', 'import "services"')
      .replaceAll('import "../features/system"', 'import "features/system"'));

    const env = {
      PATH: process.env.PATH || '/usr/bin:/bin', HOME: scratch,
      XDG_CONFIG_HOME: path.join(scratch, 'xdg-config'), XDG_DATA_HOME: path.join(scratch, 'xdg-data'),
      XDG_STATE_HOME: path.join(scratch, 'xdg-state'), XDG_CACHE_HOME: path.join(scratch, 'xdg-cache'),
      XDG_RUNTIME_DIR: runtime,
      WAYLAND_DISPLAY: path.isAbsolute(wayland) ? wayland : path.join(process.env.XDG_RUNTIME_DIR, wayland),
      PENTAD_PREVIEW: '1', PENTAD_SAFE_MODE: '1', LANG: 'C.UTF-8',
    };
    const result = await runQuickshell(options.qs, config, env);
    output = result.output;
    const event = eventFrom(output);
    report.checks = (event?.checks || []).map((check) => ({ ...check, passed: check.passed === true }));
    report.nativeFixtureStatus = event?.status || 'missing-event';
    report.exitCode = result.code;
    report.checks.push({ name: 'native fixture exits successfully', passed: result.code === 0 && event?.status === 'pass', detail: `exit=${result.code}` });
    report.checks.push({ name: 'all expected native behavior checks ran', passed: report.checks.length >= 13, detail: `checks=${report.checks.length - 1}` });
    report.checks.push({ name: 'no QML runtime or unknown-signal warnings', passed: !/TypeError:|ReferenceError:|SyntaxError:|Unknown signal|Cannot assign to non-existent property|Detected function .* in Connections element .* no signal .* matches/i.test(output) });
    report.status = report.checks.length > 0 && report.checks.every((check) => check.passed) ? 'pass' : 'fail';
  } catch (error) {
    report.error = error.stack || String(error);
  } finally {
    await mkdir(path.dirname(reportPath), { recursive: true });
    const logPath = `${reportPath}.log`;
    await writeFile(logPath, output, { mode: 0o600 });
    report.artifacts = [logPath];
    await writeFile(reportPath, `${JSON.stringify(report, null, 2)}\n`, { mode: 0o600 });
    if (scratch) await rm(scratch, { recursive: true, force: true });
  }
  process.stdout.write(`${JSON.stringify(report, null, 2)}\n`);
  return report.status === 'pass' ? 0 : 1;
}

function runQuickshell(qs, config, env) {
  return new Promise((resolve, reject) => {
    const child = spawn(qs, ['--no-duplicate', '--path', config], { cwd: repo, env, stdio: ['ignore', 'pipe', 'pipe'] });
    let output = '';
    const collect = (chunk) => { output += chunk; };
    child.stdout.setEncoding('utf8').on('data', collect);
    child.stderr.setEncoding('utf8').on('data', collect);
    const timeout = setTimeout(() => { child.kill('SIGTERM'); setTimeout(() => child.kill('SIGKILL'), 1000).unref(); }, 20000);
    child.once('error', (error) => { clearTimeout(timeout); reject(error); });
    child.once('close', (code, signal) => { clearTimeout(timeout); resolve({ code: code ?? (signal ? 128 : 1), signal, output }); });
  });
}

main().then((code) => { process.exitCode = code; }).catch((error) => {
  console.error(JSON.stringify({ status: 'fail', scenario: 'network-native', error: error.stack || String(error) }, null, 2));
  process.exitCode = 1;
});
