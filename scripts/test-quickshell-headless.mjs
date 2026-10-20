#!/usr/bin/env node
import { spawn, spawnSync } from 'node:child_process';
import { access, cp, mkdir, mkdtemp, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const self = fileURLToPath(import.meta.url);
const repo = path.resolve(path.dirname(self), '..');
const args = process.argv.slice(2);
const inside = args[0] === '--inside';

async function main() {
  if (!inside) {
    const scratch = await mkdtemp(path.join(tmpdir(), 'pentad-headless-'));
    const env = { ...process.env, PENTAD_PARENT_DBUS: process.env.DBUS_SESSION_BUS_ADDRESS || '' };
    for (const [key, folder] of Object.entries({ HOME: 'home', XDG_RUNTIME_DIR: 'runtime',
      XDG_CONFIG_HOME: 'config', XDG_DATA_HOME: 'data', XDG_CACHE_HOME: 'cache', XDG_STATE_HOME: 'state' })) {
      env[key] = path.join(scratch, folder);
      await mkdir(env[key], { recursive: true, mode: 0o700 });
    }
    const fonts = path.join(env.XDG_DATA_HOME, 'fonts');
    await mkdir(fonts);
    for (const family of ['Geist', 'Material Symbols Rounded']) {
      const result = spawnSync('fc-match', ['-f', '%{file}', family], { encoding: 'utf8', timeout: 5000 });
      const font = result.stdout?.trim();
      if (result.status === 0 && font) await cp(font, path.join(fonts, path.basename(font)));
    }
    for (const key of ['WAYLAND_DISPLAY', 'DISPLAY', 'HYPRLAND_INSTANCE_SIGNATURE', 'DBUS_SESSION_BUS_ADDRESS']) delete env[key];
    env.LIBGL_ALWAYS_SOFTWARE = '1';
    env.QT_QPA_PLATFORM = 'offscreen';
    const busConfig = path.join(scratch, 'dbus.conf');
    const busSocket = path.join(scratch, 'dbus.sock');
    await writeFile(busConfig, `<busconfig><type>session</type><listen>unix:path=${busSocket}</listen><auth>EXTERNAL</auth><policy context="default"><allow send_destination="*" eavesdrop="true"/><allow receive_sender="*" eavesdrop="true"/><allow own="*"/></policy></busconfig>`);
    env.PENTAD_PRIVATE_DBUS_SOCKET = busSocket;
    try {
      return await new Promise((resolve, reject) => {
        const child = spawn('dbus-run-session', ['--config-file', busConfig, '--', process.execPath, self, '--inside', ...args], { env, stdio: 'inherit' });
        child.once('error', reject);
        child.once('close', (code) => resolve(code ?? 1));
      });
    } finally { await rm(scratch, { recursive: true, force: true }); }
  }
  if (!process.env.DBUS_SESSION_BUS_ADDRESS || process.env.DBUS_SESSION_BUS_ADDRESS === process.env.PENTAD_PARENT_DBUS)
    throw new Error('A private D-Bus session is required.');
  if (!process.env.PENTAD_PRIVATE_DBUS_SOCKET || !process.env.DBUS_SESSION_BUS_ADDRESS.startsWith('unix:path=' + process.env.PENTAD_PRIVATE_DBUS_SOCKET + ','))
    throw new Error('D-Bus must use the socket created inside the disposable test directory.');
  const socketName = 'pentad-test-virtual';
  const socket = path.join(process.env.XDG_RUNTIME_DIR, socketName);
  const scaleIndex = args.indexOf('--scale');
  const scale = scaleIndex >= 0 ? Number(args[scaleIndex + 1]) : 1;
  if (![1, 1.25, 1.5, 2].includes(scale)) throw new Error('Unsupported display scale.');
  let compositorLog = '';
  const compositor = spawn('kwin_wayland', ['--virtual', '--no-global-shortcuts', '--no-kactivities',
    '--no-lockscreen', '--width', String(Math.round(1280 * scale)), '--height', String(Math.round(1080 * scale)),
    '--scale', '1', '--output-count', '2', '--socket', socketName],
  { env: process.env, stdio: ['ignore', 'pipe', 'pipe'] });
  compositor.stdout.on('data', (chunk) => { compositorLog = (compositorLog + chunk).slice(-4000); });
  compositor.stderr.on('data', (chunk) => { compositorLog = (compositorLog + chunk).slice(-4000); });
  let compositorError;
  compositor.on('error', (error) => { compositorError = error; });
  const stopped = new Promise((resolve) => compositor.once('close', resolve));
  try {
    const deadline = Date.now() + 10000;
    while (true) {
      if (compositorError || compositor.exitCode !== null) throw new Error(`Virtual compositor failed: ${compositorError || compositorLog}`);
      try { await access(socket); break; } catch {  }
      if (Date.now() > deadline) throw new Error(`Virtual compositor did not become ready: ${compositorLog}`);
      await new Promise((resolve) => setTimeout(resolve, 50));
    }
    const env = { ...process.env, WAYLAND_DISPLAY: socket, QT_QPA_PLATFORM: 'wayland',
      PENTAD_HEADLESS: '1', QT_SCALE_FACTOR: String(scale),
      PATH: path.join(repo, 'artifacts/quickshell-runtime/bin') + ':' + process.env.PATH };
    return await new Promise((resolve, reject) => {
      const child = spawn(process.execPath, [path.join(repo, 'scripts/test-quickshell.mjs'), ...args.slice(1)],
        { cwd: repo, env, stdio: 'inherit' });
      child.once('error', reject);
      child.once('close', (code) => resolve(code ?? 1));
    });
  } finally {
    compositor.kill('SIGTERM');
    const force = setTimeout(() => compositor.kill('SIGKILL'), 2000);
    await stopped;
    clearTimeout(force);
  }
}

main().then((code) => { process.exitCode = code; }).catch((error) => { console.error(error.message); process.exitCode = 1; });
