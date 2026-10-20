#!/usr/bin/env node
import { cp, chmod, mkdir, mkdtemp, readFile, rm, writeFile } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { spawn, spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const repo = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const marker = 'PENTAD_NETWORK_READONLY ';
const runtimeWarning = /TypeError:|ReferenceError:|SyntaxError:|Unknown signal|Cannot assign to non-existent property|Detected function .* in Connections element .* no signal .* matches/i;

function parseArgs(argv) {
  const options = { qs: process.env.PENTAD_QS_BIN || '/tmp/pentad-qs-bin/qs', report: '' };
  for (let i = 0; i < argv.length; i++) {
    if (argv[i] === '--qs' && argv[i + 1]) options.qs = argv[++i];
    else if (argv[i] === '--report' && argv[i + 1]) options.report = argv[++i];
    else throw new Error(`Unknown or incomplete argument: ${argv[i]}`);
  }
  if (!options.report) throw new Error('Usage: network-readonly.mjs --report <path> [--qs <pinned-qs>]');
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
  const version = spawnSync(options.qs, ['--version'], { encoding: 'utf8', timeout: 5000 });
  const versionText = `${version.stdout || ''}\n${version.stderr || ''}`;
  if (version.error || version.status !== 0 || !/Quickshell 0\.3\.2\b/.test(versionText))
    throw new Error(`Requires pinned Quickshell 0.3.2: ${version.error?.message || versionText}`);
  const wayland = process.env.WAYLAND_DISPLAY;
  if (!wayland || !process.env.XDG_RUNTIME_DIR) throw new Error('Read-only native probe requires an active Wayland session');

  const scratch = await mkdtemp(path.join(os.tmpdir(), 'pentad-network-readonly-'));
  let output = '';
  try {
    const config = path.join(scratch, 'config');
    await mkdir(config, { mode: 0o700 });
    await cp(path.join(repo, 'quickshell'), config, { recursive: true });
    const source = await readFile(path.join(config, 'tests/network-readonly.qml'), 'utf8');
    await writeFile(path.join(config, 'shell.qml'), source.replaceAll('import "../services"', 'import "services"'));
    const xdg = {};
    for (const name of ['config', 'data', 'state', 'cache']) {
      xdg[name] = path.join(scratch, `xdg-${name}`);
      await mkdir(xdg[name], { mode: 0o700 });
    }
    const runtime = path.join(scratch, 'runtime');
    await mkdir(runtime, { mode: 0o700 });
    const env = {
      PATH: process.env.PATH || '/usr/bin:/bin', HOME: scratch, LANG: 'C.UTF-8',
      XDG_CONFIG_HOME: xdg.config, XDG_DATA_HOME: xdg.data,
      XDG_STATE_HOME: xdg.state, XDG_CACHE_HOME: xdg.cache, XDG_RUNTIME_DIR: runtime,
      WAYLAND_DISPLAY: path.isAbsolute(wayland) ? wayland : path.join(process.env.XDG_RUNTIME_DIR, wayland),
      PENTAD_SAFE_MODE: '1', PENTAD_PREVIEW: '0',
    };
    const child = spawn(options.qs, ['--no-duplicate', '--path', config], { cwd: repo, env, stdio: ['ignore', 'pipe', 'pipe'] });
    child.stdout.setEncoding('utf8').on('data', (chunk) => { output += chunk; });
    child.stderr.setEncoding('utf8').on('data', (chunk) => { output += chunk; });
    let timedOut = false;
    const timeout = setTimeout(() => { timedOut = true; child.kill('SIGTERM'); }, 12000);
    const closed = await new Promise((resolve) => {
      child.once('error', (error) => resolve({ error }));
      child.once('close', (code, signal) => resolve({ code, signal }));
    });
    clearTimeout(timeout);
    const sample = eventFrom(output);
    const checks = [
      { name: 'read-only native sample emitted', passed: !!sample, detail: sample ? sample.kind : 'missing marker' },
      { name: 'safe mode enabled and no writes requested', passed: sample?.safeMode === true },
      { name: 'no QML runtime or unknown-signal warnings', passed: !runtimeWarning.test(output) },
      { name: 'Quickshell exited cleanly', passed: !closed.error && !timedOut && closed.code === 0,
        detail: closed.error?.message || (timedOut ? 'timed out' : `exit=${closed.code}`) },
    ];
    const report = {
      status: checks.every((check) => check.passed) ? 'pass' : 'fail',
      scenario: 'network-readonly', quickshellVersion: versionText.trim(),
      scope: 'real native network state only; safe mode; disposable HOME/XDG/runtime; no setters or daemon restarts',
      limitations: ['Quickshell 0.3.2 selects Networking.backend once at singleton startup. If it is None then, a later owner probe cannot create the backend; restarting Quickshell is required.'],
      checks, sample: sample || null, log: path.basename(`${reportPath}.log`),
    };
    await mkdir(path.dirname(reportPath), { recursive: true, mode: 0o700 });
    await chmod(path.dirname(reportPath), 0o700);
    await writeFile(`${reportPath}.log`, output, { mode: 0o600 });
    await writeFile(reportPath, `${JSON.stringify(report, null, 2)}\n`, { mode: 0o600 });
    process.stdout.write(`${JSON.stringify(report, null, 2)}\n`);
    return report.status === 'pass' ? 0 : 1;
  } finally {
    await rm(scratch, { recursive: true, force: true });
  }
}

main().then((code) => { process.exitCode = code; }).catch((error) => {
  console.error(JSON.stringify({ status: 'fail', scenario: 'network-readonly', error: error.stack || String(error) }, null, 2));
  process.exitCode = 1;
});
