#!/usr/bin/env node
// Runs the real Desktop service in a bare Quickshell process (no windows, no compositor, offscreen Qt,
// private HOME and runtime dirs) against a stand-in area picker and stand-in clipboard/notification programs.
import { chmod, copyFile, cp, mkdir, mkdtemp, readFile, readdir, rm, stat, writeFile } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { spawn, spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const repo = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const fixture = path.join(repo, 'quickshell/tests/bar-tools-native.qml');
const logOf = name => `printf '${name} %s\\n' "$*" >> "$PENTAD_BT_LOG"`;
const PICKS = 12;
const fakes = {
  'wl-copy': `#!/bin/sh\n${logOf('wl-copy')}\nprintf 'clipboard:' >> "$PENTAD_BT_LOG"; cat >> "$PENTAD_BT_LOG"; printf '\\n' >> "$PENTAD_BT_LOG"\n# The real wl-copy keeps serving the clipboard from a background process that holds stdout and stderr open.\n/usr/bin/sleep 8 &\n`,
  'notify-send': `#!/bin/sh\n${logOf('notify')}\n`,
  'xdg-open': `#!/bin/sh\n${logOf('open')}\n`,
  curl: `#!/bin/sh\n${logOf('curl')}\nprintf 'curl-stdin:' >> "$PENTAD_BT_LOG"; cat >> "$PENTAD_BT_LOG"\nprintf '{"translations":[{"text":"Привіт світ"}]}'\n`,
  hyprpicker: `#!/bin/sh\n${logOf('hyprpicker')}\n`,
  'systemd-inhibit': `#!/bin/sh\n${logOf('inhibit')}\ntrap 'exit 0' INT TERM\nwhile :; do /usr/bin/sleep 0.05; done\n`,
  'wf-recorder': `#!/bin/sh\ntrap 'printf "recorder-stopped\\n" >> "$PENTAD_BT_LOG"; exit 0' INT TERM\n${logOf('recorder')}\nwhile :; do /usr/bin/sleep 0.05; done\n`,
  'xdg-user-dir': `#!/bin/sh\nprintf '%s/Pictures\\n' "$HOME"\n`,
  pactl: `#!/bin/sh\ncase "$1 $2" in\n  "get-default-sink ") echo sink-a;;\n  "list short") if [ "$3" = sinks ]; then printf '1\\tsink-a\\tx\\n2\\tsink-b\\tx\\n'; else printf '7\\tx\\n'; fi;;\n  "list sinks") printf 'Sink #1\\n\\tName: sink-a\\n\\tDescription: Speakers\\nSink #2\\n\\tName: sink-b\\n\\tDescription: Headphones\\n';;\n  *) ${logOf('pactl')};;\nesac\n`,
};

const scenarios = {
  text: { image: 'text', used: 5, verify: log => [
    ['ocr-text-copied', /clipboard:Hello World/.test(log)],
    ['ocr-notified', /notify -a Pentad Text copied/.test(log)],
    ['image-copied-as-png', /wl-copy --type image\/png/.test(log)],
    ['deepl-key-on-stdin', /curl-stdin:header = "Authorization: DeepL-Auth-Key test-key:fx"/.test(log)],
    ['deepl-key-not-in-args', !/curl [^\n]*test-key/.test(log)],
    ['deepl-free-endpoint-and-target', /curl [^\n]*api-free\.deepl\.com[^\n]*target_lang=UK/.test(log)],
    ['translation-copied', /clipboard:Привіт світ/.test(log)],
    ['yandex-opened', /open https:\/\/yandex\.com\/images\//.test(log)],
    ['saucenao-opened', /open https:\/\/saucenao\.com\//.test(log)],
    ['ask-mode-opens-nothing-by-itself', (log.match(/^open /gm) || []).length === 2],
  ] },
  direct: { image: 'text', used: 1, verify: log => [['preferred-engine-opened', /open https:\/\/www\.bing\.com\/visualsearch/.test(log)], ['image-on-clipboard', /wl-copy --type image\/png/.test(log)]] },
  qr: { image: 'qr', used: 1, verify: log => [['qr-text-copied', /clipboard:https:\/\/example\.test\/pentad/.test(log)]] },
  cancel: { image: 'text', used: 0, verify: log => [['nothing-copied', !/wl-copy/.test(log)], ['nothing-notified', !/notify/.test(log)], ['nothing-opened', !/open /.test(log)]] },
  nokey: { image: 'text', key: false, used: 1, verify: log => [['asks-for-key', /notify -a Pentad DeepL Set an API key file/.test(log)], ['no-request-sent', !/curl/.test(log)]] },
  nologic: { image: 'text', used: 1, verify: log => [['nothing-recorded-without-a-monitor-layout', !/recorder/.test(log)]] },
  record: { image: 'text', used: 1, verify: log => [
    ['recorder-started-on-the-chosen-area', /recorder -g 100,50 320x200 -f \S+\.mp4/.test(log)],
    ['recorder-stopped-cleanly', /recorder-stopped/.test(log)],
  ] },
  misc: { image: 'text', used: 2, verify: log => [
    ['ruler-size-copied', /clipboard:320x200/.test(log) && /notify -a Pentad Size copied 320x200 px/.test(log)],
    ['next-sink-selected', /pactl set-default-sink sink-b/.test(log)],
    ['stream-moved', /pactl move-sink-input 7 sink-b/.test(log)],
    ['sink-named-in-notification', /Headphones/.test(log)],
    ['picker-format', /hyprpicker -a -f rgb/.test(log)],
    ['timed-inhibit', /inhibit [^\n]*sleep 900/.test(log)],
  ] },
};

function events(output) {
  return output.split(/\r?\n/).filter(line => line.includes('PENTAD_TEST ')).map(line => {
    try { return JSON.parse(line.slice(line.indexOf('PENTAD_TEST ') + 'PENTAD_TEST '.length)); } catch { return null; }
  }).filter(Boolean);
}

async function runScenario(qs, scratch, name) {
  const spec = scenarios[name];
  const dir = path.join(scratch, name);
  const [config, bin, home, runtime] = ['config', 'bin', 'home', 'runtime'].map(part => path.join(dir, part));
  for (const folder of [config, bin, home, runtime]) await mkdir(folder, { recursive: true, mode: 0o700 });
  await cp(path.join(repo, 'quickshell'), config, { recursive: true });
  const source = await readFile(fixture, 'utf8');
  await writeFile(path.join(config, 'shell.qml'), source.replaceAll('import "../services"', 'import "services"'));
  for (const [program, body] of Object.entries(fakes)) {
    await writeFile(path.join(bin, program), body, { mode: 0o700 });
    await chmod(path.join(bin, program), 0o700);
  }
  const images = { text: path.join(dir, 'text.png'), qr: path.join(dir, 'qr.png') };
  spawnSync('magick', ['-size', '600x120', 'xc:white', '-fill', 'black', '-pointsize', '56', '-annotate', '+20+80', 'Hello World', images.text]);
  spawnSync('qrencode', ['-o', images.qr, '-s', '8', 'https://example.test/pentad']);
  // One file per area the stand-in picker may hand out, named the way the helper names them.
  const picks = path.join(dir, 'picks');
  await mkdir(picks, { mode: 0o700 });
  for (let index = 1; index <= PICKS; index++)
    await copyFile(images[spec.image], path.join(picks, `pentad-pick-${index.toString(16).padStart(32, '0')}.png`));
  const key = path.join(dir, 'deepl.key');
  await writeFile(key, 'test-key:fx\n', { mode: 0o600 });
  const log = path.join(dir, 'log.txt');
  await writeFile(log, '');
  const env = {
    PATH: `${bin}:/usr/bin`, HOME: home, XDG_RUNTIME_DIR: runtime, XDG_CONFIG_HOME: path.join(dir, 'xdg-config'),
    XDG_DATA_HOME: path.join(dir, 'xdg-data'), XDG_STATE_HOME: path.join(dir, 'xdg-state'), XDG_CACHE_HOME: path.join(dir, 'xdg-cache'),
    LANG: 'C.UTF-8', QT_QPA_PLATFORM: 'offscreen', PENTAD_BT_SCENARIO: name, PENTAD_BT_LOG: log,
    PENTAD_BT_PICKS: picks, PENTAD_BT_KEY: spec.key === false ? '' : key,
  };
  const child = spawn(qs, ['--no-duplicate', '--path', config], { cwd: dir, env, stdio: ['ignore', 'pipe', 'pipe'] });
  let output = '';
  child.stdout.setEncoding('utf8').on('data', chunk => { output += chunk; });
  child.stderr.setEncoding('utf8').on('data', chunk => { output += chunk; });
  let timedOut = false;
  const timer = setTimeout(() => { timedOut = true; child.kill('SIGTERM'); setTimeout(() => child.kill('SIGKILL'), 1000).unref(); }, 30000);
  const closed = await new Promise(resolve => { child.once('error', error => resolve({ error })); child.once('close', (code, signal) => resolve({ code, signal })); });
  clearTimeout(timer);
  const logText = await readFile(log, 'utf8');
  const event = events(output).at(-1);
  const checks = [...(event?.checks || []), ...spec.verify(logText).map(([checkName, passed]) => ({ name: checkName, passed, detail: '' }))];
  if (typeof spec.used === 'number') {
    const left = (await readdir(picks)).length;
    checks.push({ name: 'picked-images-are-removed-after-use', passed: left === PICKS - spec.used, detail: `${left} of ${PICKS} left, ${spec.used} expected used` });
  }
  if (name === 'misc') {
    const marker = await stat(path.join(home, '.cache/pentad-focus')).then(() => true, () => false);
    checks.push({ name: 'focus-marker-file-created', passed: marker, detail: '' });
  }
  const passed = !closed.error && !timedOut && event?.status === 'pass' && checks.every(item => item.passed);
  return { scenario: name, status: passed ? 'pass' : 'fail', checks, timedOut, exitCode: closed.code, log: passed ? undefined : logText, output: passed ? undefined : output.slice(-3000) };
}

async function main(argv) {
  const qs = process.env.PENTAD_QS_BIN || path.join(repo, 'artifacts/quickshell-runtime/bin/qs');
  const only = argv.find(arg => scenarios[arg]);
  const version = spawnSync(qs, ['--version'], { encoding: 'utf8', timeout: 5000 });
  if (version.error || version.status !== 0) throw new Error(`Need Quickshell (${qs}): ${version.error?.message || version.stderr}`);
  const scratch = await mkdtemp(path.join(os.tmpdir(), 'pentad-bar-tools-native-'));
  const result = { status: 'fail', qs: version.stdout.trim(), scenarios: [] };
  try {
    for (const name of only ? [only] : Object.keys(scenarios)) result.scenarios.push(await runScenario(qs, scratch, name));
    result.status = result.scenarios.every(item => item.status === 'pass') ? 'pass' : 'fail';
  } finally { if (process.env.PENTAD_BT_KEEP) console.error("kept", scratch); else await rm(scratch, { recursive: true, force: true }); }
  process.stdout.write(`${JSON.stringify(result, null, 2)}\n`);
  return result.status === 'pass' ? 0 : 1;
}

main(process.argv.slice(2)).then(code => { process.exitCode = code; }).catch(error => { console.error(error.stack || String(error)); process.exitCode = 1; });
