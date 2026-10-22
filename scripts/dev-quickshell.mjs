#!/usr/bin/env node
import { watch } from 'node:fs';
import { access, mkdir, mkdtemp, open, readFile, rename, rm } from 'node:fs/promises';
import { constants } from 'node:fs';
import { spawn } from 'node:child_process';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { meetsFloor, parseVersion } from './check-quickshell.mjs';

const repo = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const output = path.join(repo, 'dist/quickshell');
const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
const log = (message) => console.log(`[pentad dev] ${message}`);
const alive = (pid) => {
  try { process.kill(pid, 0); return true; }
  catch (error) { if (error.code === 'ESRCH') return false; throw error; }
};
// A lock left by a crash or reboot can name a PID that now belongs to an unrelated process.
const watcher = async (pid) => {
  try {
    const args = (await readFile(`/proc/${pid}/cmdline`, 'utf8')).split('\0');
    return args.some((arg) => path.basename(arg) === 'dev-quickshell.mjs');
  } catch (error) { if (error.code === 'ENOENT' || error.code === 'ESRCH') return false; throw error; }
};

function run(command, args, capture = false) {
  return new Promise((resolve, reject) => {
    const child = spawn(command, args, { cwd: repo, stdio: capture ? ['ignore', 'pipe', 'pipe'] : 'inherit' });
    let stdout = '';
    let stderr = '';
    if (capture) {
      child.stdout.on('data', (chunk) => { stdout += chunk; });
      child.stderr.on('data', (chunk) => { stderr += chunk; });
    }
    child.once('error', reject);
    child.once('close', (code, signal) => code === 0 ? resolve(stdout.trim() ? stdout : stderr)
      : reject(new Error(`${command} ${args.join(' ')} failed (${signal || code}): ${(stdout + stderr).trim()}`)));
  });
}

async function main(args) {
  if (args.includes('--help')) {
    console.log('Usage: pnpm dev:qs [--safe-mode] [--qs BINARY] [--once]\nSave a source file to rebuild and restart Pentad. Enter/r: rebuild. Ctrl+C: stop development. --once: restart without watching.');
    return;
  }
  let safeMode = false;
  let once = false;
  let binary = path.join(repo, 'artifacts/quickshell-runtime/bin/qs');
  try { await access(binary, constants.X_OK); } catch { binary = 'qs'; }
  for (let index = 0; index < args.length; index++) {
    if (args[index] === '--safe-mode') safeMode = true;
    else if (args[index] === '--once') once = true;
    else if (args[index] === '--qs' && args[index + 1]) binary = path.resolve(args[++index]);
    else throw new Error(`Unknown argument: ${args[index]}`);
  }
  const version = await run(binary, ['--version'], true);
  if (!meetsFloor(parseVersion(version))) throw new Error(`Quickshell >= 0.3.2 is required: ${version.trim()}`);
  await mkdir(path.dirname(output), { recursive: true });
  const lockPath = path.join(repo, 'dist/.pentad-dev.lock');
  let lock;
  try { lock = await open(lockPath, 'wx'); }
  catch (error) {
    if (error.code !== 'EEXIST') throw error;
    const owner = Number(await readFile(lockPath, 'utf8'));
    if (!Number.isInteger(owner) || owner <= 0 || await watcher(owner)) throw new Error('Another Pentad development watcher is running. Stop it with Ctrl+C first.');
    await rm(lockPath);
    lock = await open(lockPath, 'wx');
  }
  await lock.writeFile(String(process.pid));
  await lock.close();
  let shell = null;
  let stopped = false;
  let busy = false;
  let pending = false;
  let timer;
  const watchers = [];
  const changed = new Set();

  async function stopPentad() {
    try { await access(path.join(output, 'shell.qml')); }
    catch (error) { if (error.code === 'ENOENT') return; throw error; }
    const response = (await run(binary, ['list', '--path', output, '--json'], true))
      .replace(/\u001b\[[0-9;]*m/g, '').trim();
    if (/^No running instances(?:\.| for\s)/.test(response)) return;
    const instances = JSON.parse(response);
    if (!Array.isArray(instances)) throw new Error(`Unexpected Quickshell instance list: ${response}`);
    for (const instance of instances) {
      if (path.resolve(instance.config_path) !== path.join(output, 'shell.qml'))
        throw new Error(`Refusing to stop another config: ${instance.config_path}`);
      await run(binary, ['kill', '--id', instance.id], true);
      const deadline = Date.now() + 5000;
      while (alive(instance.pid) && Date.now() < deadline) await sleep(50);
      if (alive(instance.pid)) throw new Error(`Pentad process ${instance.pid} did not stop within 5 seconds.`);
    }
  }

  async function rebuild() {
    if (stopped) return;
    if (busy) { pending = true; return; }
    busy = true;
    pending = false;
    log(`Building${changed.size ? `: ${[...changed].slice(0, 5).join(', ')}` : ''}…`);
    changed.clear();
    let staging;
    try {
      staging = await mkdtemp(path.join(repo, 'dist/.pentad-dev-'));
      const next = path.join(staging, 'quickshell');
      await run(process.execPath, [path.join(repo, 'scripts/build-quickshell.mjs'), '--output', next]);
      if (stopped) return;
      await stopPentad();
      if (stopped) return;
      await rm(output, { recursive: true, force: true });
      await rename(next, output);
      log(once ? 'Starting Pentad. Ctrl+C to stop.' : 'Starting Pentad. Save to rebuild; Enter/r to restart; Ctrl+C to stop.');
      const child = spawn(binary, ['--no-duplicate', '--path', output], {
        cwd: repo, stdio: ['ignore', 'inherit', 'inherit'],
        env: { ...process.env, PENTAD_SAFE_MODE: safeMode ? '1' : '0', PENTAD_PREVIEW: '0' },
      });
      shell = child;
      child.on('error', (error) => {
        console.error(`[pentad dev] ${error.message}`);
        if (once) { process.exitCode = 1; void shutdown(); }
      });
      child.on('exit', (code, signal) => {
        if (shell !== child) return;
        shell = null;
        if (once) {
          if (!stopped) process.exitCode = code || (signal ? 1 : 0);
          void shutdown();
          return;
        }
        if (!stopped && !busy) log(`Pentad exited (${signal || code}). Fix the source and save, or press Enter to retry.`);
      });
    } catch (error) {
      console.error(`[pentad dev] ${error.message}${once ? '' : '\n[pentad dev] Watching for your next save.'}`);
      if (once) { process.exitCode = 1; setTimeout(() => void shutdown(), 0); }
    } finally {
      if (staging) await rm(staging, { recursive: true, force: true });
      busy = false;
      if (pending && !stopped) { clearTimeout(timer); timer = setTimeout(() => void rebuild(), 250); }
    }
  }

  function schedule(file) {
    if (stopped || /(?:^|[/\\])(?:__pycache__|\.git)(?:[/\\]|$)|\.pyc$|[~]$|\.sw[op]$/.test(file)) return;
    changed.add(file);
    pending = true;
    clearTimeout(timer);
    timer = setTimeout(() => void rebuild(), 250);
  }

  async function shutdown() {
    if (stopped) return;
    stopped = true;
    clearTimeout(timer);
    for (const watcher of watchers) watcher.close();
    process.stdin.pause();
    if (shell) shell.kill('SIGTERM');
    while (busy) await sleep(50);
    await rm(lockPath, { force: true });
    log('Development stopped.');
  }
  process.once('SIGINT', () => void shutdown());
  process.once('SIGTERM', () => void shutdown());
  try {
    for (const directory of once ? [] : ['quickshell', 'tools', 'LICENSES']) {
      const watcher = watch(path.join(repo, directory), { recursive: true }, (_, file) => schedule(`${directory}/${file || ''}`));
      watcher.on('error', (error) => { console.error(`[pentad dev] Watcher failed: ${error.message}`); void shutdown(); });
      watchers.push(watcher);
    }
    for (const file of once ? [] : ['LICENSE', 'scripts/build-quickshell.mjs']) {
      watchers.push(watch(path.join(repo, file), () => schedule(file)));
    }
    if (!once && process.stdin.isTTY) {
      process.stdin.setEncoding('utf8');
      process.stdin.on('data', (text) => {
        if (text.trim() === '' || text.trim().toLowerCase() === 'r') schedule('manual restart');
      });
      process.stdin.resume();
    }
    log(`Watching ${repo}/quickshell using ${binary}`);
    await rebuild();
  } catch (error) {
    await shutdown();
    throw error;
  }
}

main(process.argv.slice(2)).catch((error) => { console.error(`[pentad dev] ${error.message}`); process.exitCode = 1; });
