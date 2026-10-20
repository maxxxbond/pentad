#!/usr/bin/env node
import { mkdir, mkdtemp, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { spawn, spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

export const parseVersion = (text) => text.match(/(?:Quickshell\s+)?(\d+)\.(\d+)\.(\d+)/i)?.slice(1).map(Number);
export const meetsFloor = (version, floor = [0, 3, 2]) => version !== undefined && (version[0] > floor[0] || (version[0] === floor[0] && (version[1] > floor[1] || (version[1] === floor[1] && version[2] >= floor[2]))));
export const parseQtQuery = (text) => Object.fromEntries(text.split(/\r?\n/).map((line) => {
  const separator = line.indexOf(':');
  return separator < 0 ? [] : [line.slice(0, separator), line.slice(separator + 1)];
}).filter((entry) => entry.length));
const run = (command, argv = [], options = {}) => spawnSync(command, argv, { encoding: 'utf8', timeout: 10000, ...options });

function probeImports(config, env) {
  return new Promise((resolve) => {
    const child = spawn('qs', ['--path', config], { env, stdio: ['ignore', 'pipe', 'pipe'] });
    let output = '';
    let loaded = false;
    let timedOut = false;
    let settled = false;
    const settle = (result) => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      resolve({ ...result, loaded, output });
    };
    const collect = (chunk) => {
      output += chunk;
      const plain = output.replace(/\u001b\[[0-9;]*m/g, '');
      if (plain.includes('Configuration Loaded')) {
        loaded = true;
        child.kill('SIGTERM');
      } else if (/Failed to load configuration|module .* not installed|is not a type/i.test(plain)) child.kill('SIGTERM');
    };
    child.stdout.setEncoding('utf8').on('data', collect);
    child.stderr.setEncoding('utf8').on('data', collect);
    const timer = setTimeout(() => {
      timedOut = true;
      child.kill('SIGTERM');
      setTimeout(() => child.kill('SIGKILL'), 1000).unref();
    }, 10000);
    child.once('error', (error) => settle({ error }));
    child.once('close', (code, signal) => settle({ code, signal, timedOut }));
  });
}

async function main(args) {
  const native = args.includes('--native');
  if (args.some((arg) => arg !== '--native')) {
    console.error('Usage: node scripts/check-quickshell.mjs [--native]');
    return 2;
  }
  const failures = [];
  const qsVersion = run('qs', ['--version']);
  const installed = qsVersion.error ? undefined : parseVersion(`${qsVersion.stdout}\n${qsVersion.stderr}`);
  const qmake = run('qmake6', ['-query', 'QT_VERSION', 'QT_INSTALL_QML', 'QT_INSTALL_BINS']);
  const qt = parseQtQuery(qmake.stdout || '');
  const { QT_VERSION: qtVersion, QT_INSTALL_QML: qmlPath, QT_INSTALL_BINS: qtBin } = qt;
  const packages = ['quickshell-git', 'quickshell', 'qt6-base', 'qt6-declarative', 'qt6-wayland'];
  const cohort = [...new Set(packages.map((name) => run('pacman', ['-Q', name])).filter((result) => result.status === 0).map((result) => result.stdout.trim()))];
  console.log(`Qt cohort: Qt ${qtVersion || 'unknown'}; QML modules ${qmlPath || 'unknown'}; ${cohort.length ? cohort.join(', ') : 'package metadata unavailable'}`);

  if (qsVersion.error || qsVersion.status !== 0 || !installed) failures.push(`Quickshell version unavailable: ${qsVersion.error?.message || qsVersion.stderr || qsVersion.stdout}`);
  else if (!meetsFloor(installed)) failures.push(`Quickshell ${installed.join('.')} is below required 0.3.2; QML/native probes skipped.`);
  else console.log(`Quickshell ${installed.join('.')} meets the 0.3.2 floor`);
  if (qmake.error || qmake.status !== 0 || !qtBin) failures.push(`qmake6 metadata probe failed: ${qmake.error?.message || qmake.stderr || qmake.stdout}`);
  if (!installed || !meetsFloor(installed) || qmake.error || qmake.status !== 0 || !qtBin) {
    for (const failure of failures) console.error(`FAIL: ${failure}`);
    return 1;
  }

  const qmllintPath = path.join(qtBin || '/usr/lib/qt6/bin', 'qmllint');
  const qmlToolPath = path.join(qtBin || '/usr/lib/qt6/bin', 'qml');
  const qmllint = run(qmllintPath, ['--version']);
  if (qmllint.error || qmllint.status !== 0) failures.push(`qmllint unavailable at ${qmllintPath}: ${qmllint.error?.message || qmllint.stderr || qmllint.stdout}`);
  else console.log(`qmllint: ${(qmllint.stdout || qmllint.stderr).trim()}`);
  const qmlTool = run(qmlToolPath, ['--version']);
  if (qmlTool.error || qmlTool.status !== 0) failures.push(`qml unavailable at ${qmlToolPath}: ${qmlTool.error?.message || qmlTool.stderr || qmlTool.stdout}`);
  else console.log(`qml: ${(qmlTool.stdout || qmlTool.stderr).trim()}`);

  const scratch = await mkdtemp(path.join(tmpdir(), 'pentad-qs-imports-'));
  const imports = [
    'Quickshell', 'Quickshell.Io', 'Quickshell.Hyprland', 'Quickshell.Networking',
    'Quickshell.Services.Mpris', 'Quickshell.Services.Pipewire', 'Quickshell.Services.UPower',
    'Quickshell.Services.SystemTray', 'Quickshell.Services.Notifications',
    'QtQuick.Controls.Basic', 'QtQuick.Shapes', 'QtQuick.Effects', 'Qt5Compat.GraphicalEffects',
  ];
  const probe = path.join(scratch, 'shell.qml');
  await writeFile(probe, `${imports.map((name) => `import ${name}`).join('\n')}\nimport QtQml\nShellRoot {}\n`);
  const runtime = path.join(scratch, 'runtime');
  await mkdir(runtime, { mode: 0o700 });
  const probeResult = await probeImports(probe, {
      PATH: process.env.PATH || '/usr/bin:/bin', HOME: scratch,
      XDG_CONFIG_HOME: path.join(scratch, 'config'), XDG_DATA_HOME: path.join(scratch, 'data'),
      XDG_STATE_HOME: path.join(scratch, 'state'), XDG_CACHE_HOME: path.join(scratch, 'cache'),
      XDG_RUNTIME_DIR: runtime, QT_QPA_PLATFORM: 'offscreen',
      PENTAD_SAFE_MODE: '1', PENTAD_PREVIEW: '1',
  });
  await rm(scratch, { recursive: true, force: true });
  const probeText = probeResult.output.replace(/\u001b\[[0-9;]*m/g, '');
  if (probeResult.error || !probeResult.loaded || /Failed to load configuration|module .* not installed|is not a type/i.test(probeText)) failures.push(`Quickshell QML import probe failed (imports do not instantiate a notification server): ${probeResult.error?.message || probeText || (probeResult.timedOut ? 'timed out before configuration loaded' : 'configuration did not load')}`);
  else console.log(`QML imports available: ${imports.join(', ')}`);

  if (native) {
    const ipc = run('qs', ['ipc', 'show'], { timeout: 5000 });
    if (ipc.error || ipc.status !== 0) failures.push(`explicit native IPC probe failed: ${ipc.error?.message || ipc.stderr || ipc.stdout}`);
    else console.log('Explicit native IPC probe completed.');
  }
  if (failures.length) {
    for (const failure of failures) console.error(`FAIL: ${failure}`);
    return 1;
  }
  console.log('Quickshell development environment check passed.');
  return 0;
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) process.exitCode = await main(process.argv.slice(2));
