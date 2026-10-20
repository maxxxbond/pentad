#!/usr/bin/env node
import { chmod, cp, mkdir, mkdtemp, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { spawn, spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const repo = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const sampleMarker = 'PENTAD_HARDWARE_READONLY ';
const sampleMs = 5400;
const killAfterMs = 15000;
const maxOutput = 256 * 1024;

function usage() {
  return 'Usage: node tests/tooling/hardware-readonly.mjs --qs <Quickshell-0.3.2-binary> --report <path.json>';
}

function parseArgs(args) {
  const parsed = {};
  for (let i = 0; i < args.length; i++) {
    if (args[i] === '--qs') parsed.qs = args[++i];
    else if (args[i] === '--report') parsed.report = args[++i];
    else throw new Error(`Unknown argument: ${args[i]}`);
  }
  if (!parsed.qs || !parsed.report) throw new Error(usage());
  return parsed;
}

export function classifyRuntimeErrors(output) {
  const errors = [];
  const patterns = [
    [/\b(?:TypeError|ReferenceError|SyntaxError)\b/i, 'qml-runtime-exception'],
    [/Binding loop detected/i, 'qml-binding-loop'],
    [/Detected function .* in Connections element[^\n]*no signal .* matches/i, 'qml-connections-signal-mismatch'],
    [/Connections[^\n]*(?:(?:signal|function)[^\n]*(?:not|no signal|no matching|doesn't|cannot|missing)|(?:not|no signal|no matching|doesn't|cannot|missing)[^\n]*(?:signal|function))/i, 'qml-connections-signal-mismatch'],
    [/(?:Cannot assign to non-existent property|Cannot connect .* to .* signal)/i, 'qml-binding-or-signal-error'],
    [/Failed to load configuration|Failed to load QML|QML.*(?:failed|error)/i, 'qml-load-error'],
  ];
  for (const [pattern, code] of patterns) if (pattern.test(output)) errors.push(code);
  return [...new Set(errors)];
}

function sanitizedLog(report, runtimeErrors, launch) {
  return [
    'Pentad read-only native hardware probe',
    `status=${report.status}`,
    `quickshellVersion=${report.quickshellVersionText || 'unavailable'}`,
    `launch=${launch}`,
    `runtimeErrors=${runtimeErrors.length ? runtimeErrors.join(',') : 'none'}`,
    `sample=${report.sampleCaptured ? 'captured' : 'not-captured'}`,
    `optionalServices=${report.services ? Object.entries(report.services).map(([name, value]) => {
      const available = value.available === true || value.profileAvailable === true || value.batteryAvailable === true;
      return `${name}:${available ? 'available' : 'unavailable'}`;
    }).join(',') : 'not-sampled'}`,
    '',
  ].join('\n');
}

function qmlConfig() {
  return `import QtQuick\nimport Quickshell\nimport "services"\n\nShellRoot {\n    id: root\n    property Network network: Network { preview: false; safeMode: true }\n    property Power power: Power { preview: false; safeMode: true }\n    property Audio audio: Audio { preview: false; safeMode: true }\n    property Desktop desktop: Desktop { preview: false; safeMode: true; telemetryEnabled: true }\n\n    function sample() {\n        const networkState = network.state;\n        const networkReady = networkState && networkState.kind === "ready";\n        const networkValue = networkReady ? networkState.value : null;\n        const audioState = audio.state;\n        const audioReady = audioState && audioState.kind === "ready";\n        const audioValue = audioReady ? audioState.value : null;\n        const powerState = power.profileState;\n        const powerReady = powerState && powerState.kind === "ready";\n        const batteryState = power.batteryState;\n        const batteryReady = batteryState && batteryState.kind === "ready"\n            && batteryState.value && batteryState.value.battery !== null;\n        const desktopState = desktop.state;\n        const desktopValue = desktopState && desktopState.value ? desktopState.value : null;\n        const telemetry = desktopValue ? desktopValue.telemetry : null;\n        const gpus = telemetry && Array.isArray(telemetry.gpus) ? telemetry.gpus : [];\n        const memory = telemetry && telemetry.memory ? telemetry.memory : null;\n        const gpuMemory = gpus.map(function(gpu) { return gpu.memory; }).filter(function(value) { return !!value; });\n        let vramUsed = 0, vramTotal = 0;\n        for (let i = 0; i < gpuMemory.length; ++i) { vramUsed += gpuMemory[i].used; vramTotal += gpuMemory[i].total; }\n        const result = {\n            services: {\n                network: { available: networkReady, connectivity: networkReady ? networkValue.connectivity : null,\n                    connected: networkReady ? networkValue.connected === true : null,\n                    deviceCount: networkReady ? networkValue.devices.length : null,\n                    connectedDeviceCount: networkReady ? networkValue.devices.filter(function(item) { return item.connected; }).length : null,\n                    wifiEnabled: networkReady ? networkValue.wifiEnabled === true : null },\n                audio: { available: audioReady, inputCount: audioReady ? audioValue.inputs.length : null,\n                    outputCount: audioReady ? audioValue.outputs.length : null,\n                    defaultInputAvailable: audioReady ? audioValue.input !== null : null,\n                    defaultOutputAvailable: audioReady ? audioValue.output !== null : null },\n                power: { profileAvailable: powerReady, actualProfile: powerReady ? powerState.value.actual : null,\n                    batteryAvailable: batteryReady },\n                desktop: { available: !!(desktopValue && desktopValue.telemetryStatus.kind === "ready"),\n                    telemetryStatus: desktopValue ? desktopValue.telemetryStatus.kind : "unavailable",\n                    cpuPercent: telemetry && Number.isFinite(telemetry.cpuPercent) ? telemetry.cpuPercent * 100 : null,\n                    memoryUsedBytes: memory ? memory.used : null, memoryTotalBytes: memory ? memory.total : null,\n                    rxBytesPerSecond: telemetry && Number.isFinite(telemetry.rxBytesPerSecond) ? telemetry.rxBytesPerSecond : null,\n                    txBytesPerSecond: telemetry && Number.isFinite(telemetry.txBytesPerSecond) ? telemetry.txBytesPerSecond : null,\n                    gpuPercent: telemetry && Number.isFinite(telemetry.gpuPercent) ? telemetry.gpuPercent * 100 : null,\n                    gpuCount: telemetry ? gpus.length : null, vramUsedBytes: gpuMemory.length ? vramUsed : null,\n                    vramTotalBytes: gpuMemory.length ? vramTotal : null,\n                    gpuCards: gpus.map(function(gpu) {\n                        const id = String(gpu.id || "");\n                        if (!/^card\\d+$/.test(id)) return null;\n                        return { id: id, loadPercent: Number.isFinite(gpu.load) ? gpu.load * 100 : null,\n                            vramUsedBytes: gpu.memory ? gpu.memory.used : null,\n                            vramTotalBytes: gpu.memory ? gpu.memory.total : null };\n                    }).filter(function(gpu) { return gpu !== null; }) }\n            }\n        };\n        console.info(${JSON.stringify(sampleMarker)} + JSON.stringify(result));\n        Qt.quit();\n    }\n\n    Timer { interval: ${sampleMs}; running: true; repeat: false; onTriggered: root.sample() }\n}\n`;
}

function makeReport() {
  return {
    status: 'blocked',
    mode: 'read-only',
    durationMs: sampleMs,
    checks: [],
    services: null,
    runtimeErrors: [],
    sampleCaptured: false,
    quickshellVersionText: 'unavailable',
  };
}

export async function main(args = process.argv.slice(2)) {
  let options;
  try { options = parseArgs(args); }
  catch (error) { console.error(error.message); return 2; }

  const qs = path.resolve(options.qs);
  const reportPath = path.resolve(options.report);
  const logPath = `${reportPath}.log`;
  const report = makeReport();
  let scratch;
  let output = '';
  let launch = 'not-started';
  let timedOut = false;
  let childResult = null;
  let sample = null;
  let runtimeErrors = [];

  try {
    await mkdir(path.dirname(reportPath), { recursive: true, mode: 0o700 });
    await chmod(path.dirname(reportPath), 0o700);
    const version = spawnSync(qs, ['--version'], { encoding: 'utf8', timeout: 5000, env: process.env });
    const versionText = `${version.stdout || ''}\n${version.stderr || ''}`;
    const match = /(?:Quickshell|qs)\s+(\d+)\.(\d+)\.(\d+)/i.exec(versionText);
    report.quickshellVersionText = match ? match[0] : 'unavailable';
    if (version.error || version.status !== 0 || !match || Number(match[1]) !== 0 || Number(match[2]) !== 3 || Number(match[3]) < 2) {
      report.checks.push({ name: 'quickshell-version', status: 'blocked' });
      launch = 'version-unavailable-or-below-0.3.2';
    } else if (!process.env.XDG_RUNTIME_DIR || !process.env.WAYLAND_DISPLAY) {
      report.checks.push({ name: 'wayland-session', status: 'blocked' });
      launch = 'wayland-session-unavailable';
    } else {
      scratch = await mkdtemp(path.join(tmpdir(), 'pentad-hardware-readonly-'));
      await chmod(scratch, 0o700);
      const xdg = {};
      for (const key of ['config', 'data', 'state', 'cache']) {
        xdg[key] = path.join(scratch, key);
        await mkdir(xdg[key], { recursive: true, mode: 0o700 });
      }
      const staged = path.join(xdg.config, 'quickshell-hardware-readonly');
      await cp(path.join(repo, 'quickshell'), staged, { recursive: true, dereference: false });
      await chmod(staged, 0o700);
      await writeFile(path.join(staged, 'shell.qml'), qmlConfig(), { mode: 0o600 });
      const env = {
        PATH: process.env.PATH || '/usr/bin:/bin',
        HOME: scratch,
        XDG_CONFIG_HOME: xdg.config,
        XDG_DATA_HOME: xdg.data,
        XDG_STATE_HOME: xdg.state,
        XDG_CACHE_HOME: xdg.cache,
        XDG_RUNTIME_DIR: process.env.XDG_RUNTIME_DIR,
        WAYLAND_DISPLAY: process.env.WAYLAND_DISPLAY,
        LANG: process.env.LANG || 'C.UTF-8',
        PENTAD_PREVIEW: '0',
        PENTAD_SAFE_MODE: '1',
      };
      for (const name of ['DBUS_SESSION_BUS_ADDRESS', 'DISPLAY', 'PIPEWIRE_REMOTE', 'PULSE_SERVER', 'HYPRLAND_INSTANCE_SIGNATURE']) {
        if (process.env[name]) env[name] = process.env[name];
      }
      const child = spawn(qs, ['--no-duplicate', '--path', staged], { cwd: repo, env, stdio: ['ignore', 'pipe', 'pipe'] });
      child.stdout.setEncoding('utf8').on('data', chunk => { output = (output + chunk).slice(-maxOutput); });
      child.stderr.setEncoding('utf8').on('data', chunk => { output = (output + chunk).slice(-maxOutput); });
      const timer = setTimeout(() => {
        timedOut = true;
        child.kill('SIGTERM');
        setTimeout(() => child.kill('SIGKILL'), 1000).unref();
      }, killAfterMs);
      childResult = await new Promise(resolve => {
        child.once('error', error => resolve({ error }));
        child.once('close', (code, signal) => resolve({ code, signal }));
      });
      clearTimeout(timer);
      launch = childResult.error ? 'spawn-error' : `exited-${childResult.code ?? childResult.signal}`;
      const markerLines = output.split(/\r?\n/).filter(line => line.includes(sampleMarker));
      if (markerLines.length) {
        try { sample = JSON.parse(markerLines.at(-1).slice(markerLines.at(-1).indexOf(sampleMarker) + sampleMarker.length)); }
        catch { report.checks.push({ name: 'sample-format', status: 'fail' }); }
      }
      runtimeErrors = classifyRuntimeErrors(output);
      report.runtimeErrors = runtimeErrors;
      if (runtimeErrors.length) report.checks.push({ name: 'qml-runtime-errors', status: 'fail', codes: runtimeErrors });
      if (sample && sample.services) {
        report.services = sample.services;
        report.sampleCaptured = true;
        report.checks.push({ name: 'native-services-sampled', status: 'pass' });
      }
      if (timedOut) report.checks.push({ name: 'bounded-shutdown', status: 'fail' });
      else if (childResult.error) report.checks.push({ name: 'quickshell-launch', status: 'blocked' });
      else if (!sample && !runtimeErrors.length) report.checks.push({ name: 'native-sample', status: 'blocked' });
      else if (childResult.code !== 0 && !runtimeErrors.length) report.checks.push({ name: 'quickshell-exit', status: 'blocked' });
      report.status = runtimeErrors.length || timedOut || report.checks.some(check => check.status === 'fail') ? 'fail'
        : sample && childResult.code === 0 ? 'pass' : 'blocked';
    }
  } catch (error) {
    report.status = 'blocked';
    report.checks.push({ name: 'probe-setup', status: 'blocked' });
    launch = 'setup-error';
  } finally {
    report.launch = launch;
    try {
      if (scratch) await rm(scratch, { recursive: true, force: true });
    } catch {  }
    await mkdir(path.dirname(reportPath), { recursive: true, mode: 0o700 });
    await chmod(path.dirname(reportPath), 0o700);
    await writeFile(reportPath, `${JSON.stringify(report, null, 2)}\n`, { mode: 0o600 });
    await chmod(reportPath, 0o600);
    await writeFile(logPath, sanitizedLog(report, runtimeErrors, launch), { mode: 0o600 });
    await chmod(logPath, 0o600);
  }
  console.log(`${report.status}: read-only hardware probe; report ${reportPath}`);
  return report.status === 'pass' ? 0 : 1;
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  process.exitCode = await main();
}
