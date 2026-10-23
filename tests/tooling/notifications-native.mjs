#!/usr/bin/env node
import { cp, mkdir, mkdtemp, readFile, rm, writeFile } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { spawn, spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const repo = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const marker = 'PENTAD_NOTIFICATION_STATE ';

function parseArgs(argv) {
  const options = { inside: false, qs: process.env.PENTAD_QS_BIN || path.join(repo, 'artifacts/quickshell-runtime/bin/qs'), report: undefined, scratch: undefined };
  for (let i = 0; i < argv.length; ++i) {
    const arg = argv[i];
    if (arg === '--inside') { options.inside = true; continue; }
    if (arg === '--qs' && argv[i + 1]) { options.qs = argv[++i]; continue; }
    if (arg === '--report' && argv[i + 1]) { options.report = argv[++i]; continue; }
    if (arg === '--scratch' && options.inside && argv[i + 1]) { options.scratch = argv[++i]; continue; }
    throw new Error(`Unknown or incomplete argument: ${arg}`);
  }
  return options;
}

function call(command, args, env, timeout = 5000) {
  const result = spawnSync(command, args, { env, encoding: 'utf8', timeout });
  if (result.error || result.status !== 0) throw new Error(`${command} failed: ${result.error?.message || result.stderr || result.stdout}`);
  return result.stdout;
}

function waitFor(predicate, timeoutMs, description) {
  const started = Date.now();
  return new Promise((resolve, reject) => {
    const timer = setInterval(() => {
      if (predicate()) { clearInterval(timer); resolve(); }
      else if (Date.now() - started > timeoutMs) { clearInterval(timer); reject(new Error(`Timed out waiting for ${description}`)); }
    }, 25);
  });
}

async function main() {
  const options = parseArgs(process.argv.slice(2));
  if (!options.inside) {
    const scratch = await mkdtemp(path.join(os.tmpdir(), 'pentad-notifications-native-'));
    const env = { ...process.env, HOME: scratch, QT_QPA_PLATFORM: 'offscreen', LANG: 'C.UTF-8' };
    env.PENTAD_NOTIFICATION_PARENT_DBUS_ADDRESS = process.env.DBUS_SESSION_BUS_ADDRESS || '';
    for (const [key, folder] of Object.entries({ XDG_RUNTIME_DIR: 'runtime', XDG_CONFIG_HOME: 'config', XDG_DATA_HOME: 'data', XDG_CACHE_HOME: 'cache', XDG_STATE_HOME: 'state' })) {
      env[key] = path.join(scratch, folder); await mkdir(env[key], { recursive: true, mode: 0o700 });
    }
    delete env.WAYLAND_DISPLAY; delete env.DISPLAY; delete env.HYPRLAND_INSTANCE_SIGNATURE;
    const args = ['--inside', '--scratch', scratch, '--qs', options.qs];
    if (options.report) args.push('--report', options.report);
    try {
      const result = spawnSync('dbus-run-session', ['--', process.execPath, fileURLToPath(import.meta.url), ...args], { env, stdio: 'inherit', timeout: 45000 });
      return result.error || result.status !== 0 ? 1 : 0;
    } finally { await rm(scratch, { recursive: true, force: true }); }
  }
  if (!process.env.DBUS_SESSION_BUS_ADDRESS || process.env.PENTAD_NOTIFICATION_PARENT_DBUS_ADDRESS === process.env.DBUS_SESSION_BUS_ADDRESS)
    throw new Error('--inside requires a fresh private dbus-run-session');
  const version = call(options.qs, ['--version'], process.env);
  if (!/Quickshell 0\.3\.2\b/.test(version)) throw new Error(`Pinned Quickshell 0.3.2 required; received ${version.trim()}`);
  const scratch = options.scratch;
  const staged = path.join(process.env.XDG_CONFIG_HOME, 'quickshell-fixture');
  await cp(path.join(repo, 'quickshell'), staged, { recursive: true, dereference: false });
  const helpers = path.join(staged, 'helpers'); await mkdir(helpers, { recursive: true, mode: 0o700 });
  await Promise.all(['pentad-files.py', 'pentad_files.py'].map((name) => cp(path.join(repo, 'tools', name), path.join(helpers, name))));
  const source = await readFile(path.join(repo, 'quickshell/tests/notifications-native.qml'), 'utf8');
  await writeFile(path.join(staged, 'shell.qml'), source.replaceAll('import "../services"', 'import "services"'));
  const child = spawn(options.qs, ['--no-duplicate', '--path', staged], { env: process.env, stdio: ['ignore', 'pipe', 'pipe'] });
  let output = '';
  child.stdout.setEncoding('utf8').on('data', (chunk) => { output += chunk; });
  child.stderr.setEncoding('utf8').on('data', (chunk) => { output += chunk; });
  let monitor;
  let competitor;
  let monitorOutput = '';
  const checks = [];
  const dbus = (...args) => call('gdbus', ['call', '--session', '--dest', 'org.freedesktop.Notifications', '--object-path', '/org/freedesktop/Notifications', '--method', ...args], process.env);
  const stateRecords = () => output.split(/\r?\n/).filter((line) => line.includes(marker)).map((line) => {
    const text = line.slice(line.indexOf(marker) + marker.length).trim();
    try { return JSON.parse(text); } catch { return null; }
  }).filter(Boolean);
  try {
    await waitFor(() => {
      const owner = spawnSync('busctl', ['--user', 'call', 'org.freedesktop.DBus', '/org/freedesktop/DBus', 'org.freedesktop.DBus', 'GetConnectionUnixProcessID', 's', 'org.freedesktop.Notifications'], { env: process.env, encoding: 'utf8' });
      const pid = /^u\s+(\d+)/.exec(owner.stdout || '')?.[1];
      return owner.status === 0 && Number(pid) === child.pid;
    }, 10000, 'native notification server ownership').catch((error) => { throw new Error(`${error.message}\n${output.slice(-5000)}`); });
    checks.push({ name: 'private-bus-owner-probe-confirms-this-shell', passed: true });
    const competingPath = staged + '-competitor';
    await cp(staged, competingPath, { recursive: true });
    const competingState = path.join(scratch, 'competing-state');
    await mkdir(competingState, { mode: 0o700 });
    let competingOutput = '';
    competitor = spawn(options.qs, ['--no-duplicate', '--path', competingPath], {
      env: { ...process.env, XDG_STATE_HOME: competingState }, stdio: ['ignore', 'pipe', 'pipe'],
    });
    competitor.stdout.setEncoding('utf8').on('data', (chunk) => { competingOutput += chunk; });
    competitor.stderr.setEncoding('utf8').on('data', (chunk) => { competingOutput += chunk; });
    await waitFor(() => competingOutput.includes('"status":"another-server"'), 8000,
      'second shell to report the existing private notification owner');
    const retainedOwner = call('busctl', ['--user', 'call', 'org.freedesktop.DBus',
      '/org/freedesktop/DBus', 'org.freedesktop.DBus', 'GetConnectionUnixProcessID',
      's', 'org.freedesktop.Notifications'], process.env);
    checks.push({ name: 'existing-notification-owner-is-not-replaced',
      passed: Number(/^u\s+(\d+)/.exec(retainedOwner)?.[1]) === child.pid });
    // The service stops probing once it owns the name, which relies on the owner refusing replacement.
    const replaceAttempt = call('busctl', ['--user', 'call', 'org.freedesktop.DBus', '/org/freedesktop/DBus',
      'org.freedesktop.DBus', 'RequestName', 'su', 'org.freedesktop.Notifications', '6'], process.env);
    checks.push({ name: 'notification-owner-refuses-replacement', passed: /^u\s+3\b/.test(replaceAttempt.trim()),
      detail: replaceAttempt.trim() });
    const competitorStopped = new Promise((resolve) => competitor.once('close', resolve));
    competitor.kill('SIGTERM');
    await competitorStopped;
    competitor = undefined;
    monitor = spawn('gdbus', ['monitor', '--session', '--dest', 'org.freedesktop.Notifications'], { env: process.env, stdio: ['ignore', 'pipe', 'pipe'] });
    monitor.stdout.setEncoding('utf8').on('data', (chunk) => { monitorOutput += chunk; });
    monitor.stderr.setEncoding('utf8').on('data', (chunk) => { monitorOutput += chunk; });
    const first = dbus('org.freedesktop.Notifications.Notify', '"Pentad fixture"', 'uint32 0', '""', '"Original title"', '"body"', "['open', 'Open']", "{'urgency': <byte 1>, 'desktop-entry': <'pentad-fixture'>}", 'int32 60000');
    const firstId = /uint32 (\d+)/.exec(first)?.[1];
    if (!firstId) throw new Error(`Could not parse first notification id: ${first}`);
    const replacement = dbus('org.freedesktop.Notifications.Notify', '"Pentad fixture"', `uint32 ${firstId}`, '""', '"Replacement title"', '"updated"', "['open', 'Open']", "{'urgency': <byte 1>, 'desktop-entry': <'pentad-fixture'>}", 'int32 60000');
    if (!replacement.includes(`uint32 ${firstId}`)) throw new Error(`Replacement did not retain native id: ${replacement}`);
    await waitFor(() => output.includes('PENTAD_NOTIFICATION_ACTION_RESULT true')
      && monitorOutput.includes(`ActionInvoked (uint32 ${firstId}, 'open')`)
      && monitorOutput.includes(`NotificationClosed (uint32 ${firstId}, uint32 2)`), 8000, 'native action invocation and auto-dismiss')
      .catch((error) => { throw new Error(`${error.message}\nQS ${output.slice(-6000)}\nDBUS ${monitorOutput.slice(-3000)}`); });
    checks.push({ name: 'notify-replacement-and-native-action-auto-dismiss', passed: true });
    await new Promise((resolve) => setTimeout(resolve, 700));
    const afterAction = stateRecords().at(-1);
    const snapshot = afterAction?.history?.find((record) => record.title === 'Replacement title');
    checks.push({ name: 'own-config-save-keeps-live-archive-snapshot', passed: !!snapshot && snapshot.wireId === null });
    const third = dbus('org.freedesktop.Notifications.Notify', '"Pentad fixture"', 'uint32 0', '""', '"Close me"', '"close test"', '[]', "{'urgency': <byte 1>}", 'int32 60000');
    const thirdId = /uint32 (\d+)/.exec(third)?.[1];
    if (!thirdId) throw new Error(`Could not parse close test notification id: ${third}`);
    await waitFor(() => stateRecords().some((state) => state.history.some((item) => item.title === 'Close me')), 5000, 'third notification delivery');
    dbus('org.freedesktop.Notifications.CloseNotification', `uint32 ${thirdId}`);
    await waitFor(() => stateRecords().at(-1)?.history.every((item) => item.title !== 'Close me'), 5000, 'CloseNotification archival removal');
    checks.push({ name: 'close-notification-removes-snapshot', passed: true });
    const notify = (title, timeout) => {
      const reply = dbus('org.freedesktop.Notifications.Notify', '"Pentad fixture"', 'uint32 0', '""', JSON.stringify(title), '"fixture"', '[]', "{'urgency': <byte 1>}", `int32 ${timeout}`);
      const id = /uint32 (\d+)/.exec(reply)?.[1];
      if (!id) throw new Error(`Could not parse notification id: ${reply}`);
      return id;
    };
    const closed = (id, reason) => monitorOutput.includes(`NotificationClosed (uint32 ${id}, uint32 ${reason})`);
    notify('Enable DND', 60000);
    await waitFor(() => output.includes('PENTAD_NOTIFICATION_DND_READY'), 5000, 'DND enablement');
    const quietId = notify('Quiet notification', 60000);
    await waitFor(() => output.includes('PENTAD_NOTIFICATION_DND_DONE') && closed(quietId, 2), 5000, 'native dismissal while DND is enabled');
    checks.push({ name: 'dnd-delivery-is-archived-without-leaking-native-object', passed:
      stateRecords().at(-1)?.history.some((item) => item.title === 'Quiet notification' && item.wireId === null) });
    const expiryId = notify('Expiry notification', 1000);
    await waitFor(() => closed(expiryId, 1), 4000, 'native expiry after presentation');
    checks.push({ name: 'presented-popup-expires-with-native-reason', passed: true });
    const hoverId = notify('Hover notification', 3000);
    await waitFor(() => output.includes('PENTAD_NOTIFICATION_HOVER_PAUSED'), 4000, 'hover pause');
    if (closed(hoverId, 1)) throw new Error('Hover popup expired before pause');
    await waitFor(() => output.includes('PENTAD_NOTIFICATION_HOVER_RESUMED'), 2000, 'hover resume');
    if (closed(hoverId, 1)) throw new Error('Hover popup expired while paused');
    await waitFor(() => closed(hoverId, 1), 2000, 'remaining timeout after hover resume');
    checks.push({ name: 'hover-pauses-and-resumes-remaining-monotonic-time', passed: true });
    // One probe on load (plus one after the fixture's unreadable archive resets the status), then none.
    const probeMarker = 'PENTAD_NOTIFICATION_OWNER_PROBES ';
    const probes = output.split(/\r?\n/).filter((line) => line.includes(probeMarker)).map((line) => {
      try { return JSON.parse(line.slice(line.indexOf(probeMarker) + probeMarker.length)); } catch { return null; }
    });
    const lastProbe = probes.at(-1);
    checks.push({ name: 'owner-probe-stops-while-this-shell-owns-the-name',
      passed: probes.length >= 5 && !!lastProbe && lastProbe.generation <= 2 && lastProbe.polling === false
        && probes.slice(2).every((item) => item?.generation === lastProbe.generation),
      detail: JSON.stringify({ samples: probes.length, last: lastProbe }) });
  } catch (error) {
    if (options.report) await writeFile(options.report, JSON.stringify({
      status: 'fail', scenario: 'notifications-native', checks,
      error: error.message, output: output.slice(-6000), monitor: monitorOutput.slice(-3000),
    }, null, 2));
    throw new Error(`${error.message}\nQS ${output.slice(-6000)}\nDBUS ${monitorOutput.slice(-3000)}`);
  } finally {
    const children = [child, monitor, competitor].filter(Boolean);
    const closes = children.map((process) => process.exitCode !== null || process.signalCode !== null
      ? Promise.resolve() : new Promise((resolve) => process.once('close', resolve)));
    for (const process of children) process.kill('SIGTERM');
    await Promise.all(closes);
  }
  const failures = checks.filter((check) => !check.passed);
  const report = { status: failures.length ? 'fail' : 'pass', scenario: 'notifications-native', quickshell: version.trim(), bus: 'private dbus-run-session', checks, output: output.slice(-6000), monitor: monitorOutput.slice(-3000), scratch: scratch };
  if (options.report) await writeFile(options.report, JSON.stringify(report, null, 2));
  console.log(`${report.status}: notifications-native (${checks.length} checks)`);
  if (failures.length) console.error(failures);
  return failures.length ? 1 : 0;
}

main().then((code) => { process.exitCode = code; }).catch((error) => { console.error(error.stack || error); process.exitCode = 1; });
