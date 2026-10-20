#!/usr/bin/env node
import { mkdtemp, mkdir, cp, rm, writeFile } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { spawn, spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const repo = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const fixture = path.join(repo, 'tests/tooling/mpris-fixture.js');
const marker = 'PENTAD_MEDIA_PHASE ';
const eventMarker = 'PENTAD_MPRIS_EVENT ';
const defaultQs = '/tmp/pentad-qs-bin/qs';

function parseLine(line, prefix) {
  try { return JSON.parse(line.slice(prefix.length)); } catch { return null; }
}
function run(command, args, env, timeout = 5000) {
  const result = spawnSync(command, args, { encoding: 'utf8', env, timeout });
  if (result.error || result.status !== 0) throw new Error(`${command} failed: ${result.error?.message || result.stderr || result.stdout}`);
  return result.stdout;
}
function parseArgs(argv) {
  const options = { inside: false, qs: undefined, report: undefined, scratch: undefined };
  const seen = new Set();
  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i];
    if (arg === '--inside') {
      if (seen.has(arg)) throw new Error('Duplicate argument: --inside');
      seen.add(arg);
      options.inside = true;
      continue;
    }
    if (!['--qs', '--report', '--scratch'].includes(arg)) throw new Error(`Unknown argument: ${arg}`);
    if (seen.has(arg)) throw new Error(`Duplicate argument: ${arg}`);
    seen.add(arg);
    const value = argv[++i];
    if (!value || value.startsWith('--')) throw new Error(`${arg} requires a value`);
    options[arg.slice(2)] = value;
  }
  if (options.scratch && !options.inside) throw new Error('--scratch is internal to the isolated runner');
  return options;
}
async function privateEnv(scratch, inherited = process.env) {
  const env = { ...inherited, HOME: scratch, QT_QPA_PLATFORM: 'offscreen', GIO_USE_VFS: 'local', LANG: 'C.UTF-8' };
  for (const [key, folder] of Object.entries({
    XDG_RUNTIME_DIR: 'runtime', XDG_CONFIG_HOME: 'config', XDG_DATA_HOME: 'data',
    XDG_CACHE_HOME: 'cache', XDG_STATE_HOME: 'state',
  })) {
    env[key] = path.join(scratch, folder);
    await mkdir(env[key], { recursive: true, mode: 0o700 });
  }
  delete env.DISPLAY;
  delete env.WAYLAND_DISPLAY;
  delete env.HYPRLAND_INSTANCE_SIGNATURE;
  delete env.DBUS_STARTER_ADDRESS;
  delete env.DBUS_STARTER_BUS_TYPE;
  return env;
}
async function main() {
  const options = parseArgs(process.argv.slice(2));
  if (!options.inside) {
    const scratch = await mkdtemp(path.join(os.tmpdir(), 'pentad-mpris-native-'));
    try {
      const env = await privateEnv(scratch);
      env.PENTAD_MPRIS_PARENT_DBUS_ADDRESS = process.env.DBUS_SESSION_BUS_ADDRESS || '';
      const childArgs = ['--inside', '--scratch', scratch];
      if (options.qs) childArgs.push('--qs', options.qs);
      if (options.report) childArgs.push('--report', options.report);
      const bus = spawnSync('dbus-run-session', ['--', process.execPath, fileURLToPath(import.meta.url), ...childArgs], { stdio: 'inherit', env });
      return bus.status ?? 1;
    } finally {
      await rm(scratch, { recursive: true, force: true });
    }
  }
  if (!process.env.DBUS_SESSION_BUS_ADDRESS
      || process.env.PENTAD_MPRIS_PARENT_DBUS_ADDRESS === undefined
      || process.env.DBUS_SESSION_BUS_ADDRESS === process.env.PENTAD_MPRIS_PARENT_DBUS_ADDRESS)
    throw new Error('--inside requires a fresh dbus-run-session private bus');
  const qs = options.qs || process.env.PENTAD_QS_BIN || defaultQs;
  const version = spawnSync(qs, ['--version'], { encoding: 'utf8', timeout: 5000 });
  if (version.error || version.status !== 0 || !/Quickshell 0\.3\.2\b/.test(`${version.stdout}\n${version.stderr}`)) {
    throw new Error(`Need the pinned Quickshell 0.3.2 binary (${qs}); got ${version.stdout || version.stderr || version.error?.message || 'no version'}`);
  }
  const scratch = options.scratch || await mkdtemp(path.join(os.tmpdir(), 'pentad-mpris-native-'));
  const ownsScratch = !options.scratch;
  const env = await privateEnv(scratch);
  delete env.PENTAD_MPRIS_PARENT_DBUS_ADDRESS;
  const server = spawn('gjs', ['-m', fixture], { env, stdio: ['ignore', 'pipe', 'pipe'] });
  let serverOutput = '';
  let serverReady = false;
  const serverEvents = [];
  server.stdout.setEncoding('utf8').on('data', (chunk) => {
    serverOutput += chunk;
    for (const line of serverOutput.split(/\r?\n/)) {
      if (line === 'PENTAD_MPRIS_READY') serverReady = true;
      if (line.startsWith(eventMarker)) {
        const event = parseLine(line, eventMarker);
        if (event) serverEvents.push(event);
      }
    }
    serverOutput = serverOutput.slice(serverOutput.lastIndexOf('\n') + 1);
  });
  server.stderr.setEncoding('utf8').on('data', (chunk) => { serverOutput += chunk; });
  let qsProcess;
  let output = '';
  const checks = [];
  const artifacts = [];
  let ready = false;
  try {
    await new Promise((resolve, reject) => {
      const timeout = setTimeout(() => reject(new Error('MPRIS fixture did not acquire its private bus names')), 5000);
      const poll = setInterval(() => {
        if (serverReady) { clearInterval(poll); clearTimeout(timeout); ready = true; resolve(); }
        else if (server.exitCode !== null) { clearInterval(poll); clearTimeout(timeout); reject(new Error(`Fixture server exited: ${serverOutput}`)); }
      }, 20);
    });
    const config = path.join(scratch, 'config');
    await mkdir(path.join(config, 'services'), { recursive: true });
    await mkdir(path.join(config, 'logic'), { recursive: true });
    await mkdir(path.join(config, 'tests'), { recursive: true });
    await cp(path.join(repo, 'quickshell/services/Media.qml'), path.join(config, 'services/Media.qml'));
    await cp(path.join(repo, 'quickshell/logic/media.mjs'), path.join(config, 'logic/media.mjs'));
    await cp(path.join(repo, 'quickshell/tests/media-native.qml'), path.join(config, 'shell.qml'));
    qsProcess = spawn(qs, ['--no-duplicate', '--path', config], { env, stdio: ['ignore', 'pipe', 'pipe'] });
    qsProcess.stdout.setEncoding('utf8').on('data', (chunk) => { output += chunk; });
    qsProcess.stderr.setEncoding('utf8').on('data', (chunk) => { output += chunk; });
    const command = async (method, ...values) => run('gdbus', ['call', '--session', '--dest', 'org.pentad.MediaFixture', '--object-path', '/org/pentad/MediaFixture', '--method', `org.pentad.MediaFixture.${method}`, ...values.map(String)], env);
    let phaseSearchFrom = 0;
    let phaseBusy = false;
    const reportEvent = async (phase) => new Promise((resolve, reject) => {
      const deadline = Date.now() + 20000;
      const timer = setInterval(async () => {
        if (phaseBusy) return;
        const markerIndex = output.indexOf(marker, phaseSearchFrom);
        const lineEnd = output.indexOf('\n', markerIndex);
        if (markerIndex >= 0 && lineEnd >= 0) {
          const event = parseLine(output.slice(markerIndex, lineEnd).trimEnd(), marker);
          phaseSearchFrom = lineEnd + 1;
          if (event?.phase !== phase) { clearInterval(timer); reject(new Error(`Expected ${phase}, saw ${event?.phase}`)); return; }
          phaseBusy = true;
          try {
            if (phase === 'change-track') await command('ChangeTrack', 'B', '/track/B2');
            if (phase === 'deny-control') await command('SetCanControl', 'B', 'false');
            if (phase === 'restore-control') await command('SetCanControl', 'B', 'true');
            if (phase === 'drop-player') await command('DropPlayer', 'B');
            if (phase === 'restore-player') await command('RestorePlayer', 'B');
            clearInterval(timer);
            resolve();
          } catch (error) { clearInterval(timer); reject(error); }
          finally { phaseBusy = false; }
          return;
        }
        if (qsProcess.exitCode !== null) { clearInterval(timer); reject(new Error(`Quickshell exited before ${phase}: ${output}`)); }
        if (Date.now() >= deadline) { clearInterval(timer); reject(new Error(`Timed out waiting for ${phase}: ${output}`)); }
      }, 25);
    });
    for (const phase of ['deny-control', 'restore-control', 'change-track', 'drop-player', 'restore-player']) await reportEvent(phase);
    const closed = await new Promise((resolve) => {
      const timer = setTimeout(() => { qsProcess.kill('SIGTERM'); }, 1000);
      qsProcess.once('close', (code, signal) => { clearTimeout(timer); resolve({ code, signal }); });
    });
    const events = output.split(/\r?\n/).filter((line) => line.includes('PENTAD_TEST ')).map((line) => parseLine(line, line.slice(0, line.indexOf('PENTAD_TEST ') + 'PENTAD_TEST '.length)));
    checks.push(...events.flatMap((event) => event?.checks || []));
    const nativeCalls = serverEvents.filter((event) => event.method || event.event === 'track-changed');
    checks.push({ name: 'private bus received play-pause and absolute seeks', passed:
      nativeCalls.some((event) => ['PlayPause', 'Play', 'Pause'].includes(event.method))
      && nativeCalls.some((event) => event.method === 'SetPosition' && event.track === '/track/B' && event.position === 15_000_000)
      && nativeCalls.some((event) => event.method === 'SetPosition' && event.track === '/track/B2' && event.position === 20_000_000),
      detail: JSON.stringify(nativeCalls) });
    const passed = closed.code === 0 && checks.length > 0 && checks.every((check) => check.passed === true);
    const report = { status: passed ? 'pass' : 'fail', scenario: 'media-native', qs: version.stdout.trim(), bus: 'dbus-run-session', checks, artifacts };
    if (options.report) {
      await mkdir(path.dirname(path.resolve(options.report)), { recursive: true });
      await writeFile(options.report, `${JSON.stringify(report, null, 2)}\n`);
    }
    process.stdout.write(`${JSON.stringify(report, null, 2)}\n`);
    if (!passed) process.stderr.write(output);
    return passed ? 0 : 1;
  } finally {
    if (qsProcess && qsProcess.exitCode === null) qsProcess.kill('SIGKILL');
    if (ready && server.exitCode === null) server.kill('SIGTERM');
    if (server.exitCode === null) await new Promise((resolve) => server.once('close', resolve));
    if (ownsScratch) await rm(scratch, { recursive: true, force: true });
  }
}

main().then((code) => { process.exitCode = code; }).catch(async (error) => {
  let reportPath;
  try { reportPath = parseArgs(process.argv.slice(2)).report; } catch {  }
  const report = { status: 'fail', scenario: 'media-native', error: error.stack || String(error), bus: 'dbus-run-session' };
  if (reportPath) {
    await mkdir(path.dirname(path.resolve(reportPath)), { recursive: true }).catch(() => {});
    await writeFile(reportPath, `${JSON.stringify(report, null, 2)}\n`).catch(() => {});
  }
  console.error(JSON.stringify(report, null, 2));
  process.exitCode = 1;
});
