#!/usr/bin/env node
// Clicks the bar tools in a real bar inside the private headless compositor (scripts/test-quickshell-headless.mjs).
// slurp, grim, the clipboard, notifications and the browser are stand-ins first in PATH, so nothing reaches the session.
import { chmod, copyFile, mkdir, mkdtemp, readFile, readdir, rm, writeFile } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { spawn, spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const repo = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const qsBin = process.env.PENTAD_QS_BIN ? path.dirname(process.env.PENTAD_QS_BIN) : '';
const realBusctl = spawnSync('sh', ['-c', 'command -v busctl'], { encoding: 'utf8', timeout: 5000 }).stdout?.trim() || '';
const logOf = name => `printf '${name} %s\\n' "$*" >> "$PENTAD_BT_LOG"`;
const fakes = {
  // The screenshot helper freezes the screen with `grim -o <output> <file>`; the stand-in writes the synthetic page.
  grim: `#!/bin/sh\n${logOf('grim')}\nfor last; do :; done\ncat "$PENTAD_BT_IMAGE" > "$last"\n`,
  'wl-copy': `#!/bin/sh\n${logOf('wl-copy')}\nprintf 'clipboard:' >> "$PENTAD_BT_LOG"; cat >> "$PENTAD_BT_LOG"; printf '\\n' >> "$PENTAD_BT_LOG"\n`,
  'notify-send': `#!/bin/sh\n${logOf('notify')}\n`,
  'xdg-open': `#!/bin/sh\n${logOf('open')}\n`,
  hyprpicker: `#!/bin/sh\n${logOf('hyprpicker')}\n`,
  // Anything that could change the real audio, radios, display or power settings is a recording stand-in.
  pactl: `#!/bin/sh\ncase "$1 $2" in\n  "get-default-sink ") echo sink-a;;\n  "list short") if [ "$3" = sinks ]; then printf '1\\tsink-a\\tx\\n2\\tsink-b\\tx\\n'; else printf '7\\tx\\n'; fi;;\n  "list sinks") printf 'Sink #2\\n\\tName: sink-b\\n\\tDescription: Headphones\\n';;\n  *) ${logOf('pactl')};;\nesac\n`,
  // These keep a little state in a file so the read-back after a toggle sees the change.
  nmcli: `#!/bin/sh\nS="$PENTAD_BT_STATE/radio"; [ -f "$S" ] || echo enabled:enabled > "$S"\ncase "$*" in\n  '-t -f WIFI,WWAN radio') cat "$S";;\n  'radio all off') ${logOf('nmcli')}; echo disabled:disabled > "$S";;\n  'radio all on') ${logOf('nmcli')}; echo enabled:enabled > "$S";;\n  radio*) ${logOf('nmcli')};;\nesac\nexit 0\n`,
  hyprctl: `#!/bin/sh\nS="$PENTAD_BT_STATE/temperature"; [ -f "$S" ] || echo 6000 > "$S"\ncase "$*" in\n  'hyprsunset temperature') cat "$S";;\n  'hyprsunset identity get') echo false;;\n  'hyprsunset temperature '*) ${logOf('hyprctl')}; echo "$3" > "$S";;\n  'hyprsunset identity') ${logOf('hyprctl')}; echo 6000 > "$S";;\nesac\nexit 0\n`,
  bluetoothctl: `#!/bin/sh\n${logOf('bluetoothctl')}\nexit 1\n`,
  // Power profiles go through busctl; every other busctl call reaches the real one, as before.
  busctl: `#!/bin/sh\ncase "$*" in\n  *org.freedesktop.UPower.PowerProfiles*) ;;\n  *) ${realBusctl ? `exec '${realBusctl}' "$@"` : 'exit 1'};;\nesac\nS="$PENTAD_BT_STATE/profile"; [ -f "$S" ] || echo balanced > "$S"\nP='{"type":"aa{sv}","data":[{"Profile":{"type":"s","data":"performance"}},{"Profile":{"type":"s","data":"balanced"}},{"Profile":{"type":"s","data":"power-saver"}}]}'\ncase "$*" in\n  *set-property*) ${logOf('busctl')}; for last; do :; done; echo "$last" > "$S";;\n  *'ActiveProfile Profiles') printf '{"type":"s","data":"%s"}\\n%s\\n' "$(cat "$S")" "$P";;\n  *get-property*) printf '{"type":"s","data":"%s"}\\n' "$(cat "$S")";;\nesac\nexit 0\n`,
  wpctl: `#!/bin/sh\n${logOf('wpctl')}\nexit 1\n`,
};

// Read-only: whether the real Bluetooth adapter is powered ('yes'/'no'), or null when there is none.
function bluetoothPower() {
  const shown = spawnSync('bluetoothctl', ['show'], { encoding: 'utf8', timeout: 5000 });
  return /Powered: (yes|no)/.exec(shown.stdout || '')?.[1] ?? null;
}
const btBefore = bluetoothPower();
const scratch = await mkdtemp(path.join(os.tmpdir(), 'pentad-bar-tools-ui-'));
let code = 1;
try {
  const bin = path.join(scratch, 'bin');
  await mkdir(bin, { mode: 0o700 });
  const image = path.join(scratch, 'page.png');
  const log = path.join(scratch, 'log.txt');
  for (const [name, body] of Object.entries(fakes)) {
    // The harness does not pass extra variables on to qs, so the paths are written into the stand-ins.
    await writeFile(path.join(bin, name), body.replaceAll('$PENTAD_BT_STATE', scratch).replaceAll('$PENTAD_BT_LOG', log).replaceAll('$PENTAD_BT_IMAGE', image), { mode: 0o700 });
    await chmod(path.join(bin, name), 0o700);
  }
  // A page with a noisy "photo", two lines of large text and a flat card, so the picker has something to suggest.
  spawnSync('magick', ['-size', '1280x720', 'xc:white', '(', '-size', '400x250', 'xc:gray50', '+noise', 'Random', ')',
    '-geometry', '+100+100', '-composite', '-fill', 'black', '-pointsize', '56', '-annotate', '+640+160', 'Hello Pentad',
    '-annotate', '+640+240', 'Region picker', '-fill', '#e8e8ec', '-draw', 'rectangle 100,450 619,649',
    '-fill', '#3c5aa0', '-draw', 'rectangle 100,450 619,457', image]);
  await writeFile(log, '');
  const report = path.join(scratch, 'report.json');
  const env = { ...process.env, PATH: [bin, qsBin, process.env.PATH].filter(Boolean).join(':'), PENTAD_BT_LOG: log, PENTAD_BT_IMAGE: image };
  const child = spawn(process.execPath, [path.join(repo, 'scripts/test-quickshell-headless.mjs'), '--scenario', 'bar-tools-ui', '--report', report],
    { cwd: repo, env, stdio: ['ignore', 'pipe', 'pipe'] });
  let output = '';
  child.stdout.setEncoding('utf8').on('data', chunk => { output += chunk; });
  child.stderr.setEncoding('utf8').on('data', chunk => { output += chunk; });
  const timer = setTimeout(() => child.kill('SIGTERM'), 200000);
  const status = await new Promise(resolve => child.once('close', exit => resolve(exit)));
  clearTimeout(timer);
  if (process.env.PENTAD_BT_PNG) await copyFile(`${report}.png`, process.env.PENTAD_BT_PNG).catch(() => {});
  if (process.env.PENTAD_BT_SHOTS) {
    for (const name of await readdir(scratch).catch(() => [])) if (name.startsWith('report.json.png.'))
      await copyFile(path.join(scratch, name), path.join(process.env.PENTAD_BT_SHOTS, name.slice('report.json.png.'.length))).catch(() => {});
  }
  if (process.env.PENTAD_BT_SHELL_LOG) await copyFile(`${report}.log`, process.env.PENTAD_BT_SHELL_LOG).catch(() => {});
  const result = JSON.parse(await readFile(report, 'utf8').catch(() => '{"status":"blocked","checks":[]}'));
  const btAfter = bluetoothPower();
  if (btBefore && btAfter && btBefore !== btAfter) spawnSync('bluetoothctl', ['power', btBefore === 'yes' ? 'on' : 'off'], { timeout: 10000 });
  const logText = (await readFile(log, 'latin1')).replace(/[^\x09\x0a\x20-\x7e]+/g, '·');
  const extra = [
    ['ocr-text-copied', /clipboard:Hello Pentad/.test(logText)],
    ['picker-ran-with-format', /hyprpicker -a -f hex/.test(logText)],
    ['yandex-opened', /open https:\/\/yandex\.com\/images\//.test(logText)],
    ['image-search-copied-png', /wl-copy --type image\/png/.test(logText)],
    ['ruler-size-copied', /clipboard:\d+x\d+/.test(logText) && /notify -a Pentad Size copied \d+x\d+ px/.test(logText)],
    ['night-light-set', /hyprctl hyprsunset temperature 4000/.test(logText)],
    ['airplane-radios-off', /nmcli radio all off/.test(logText)],
    ['power-saver-set', /busctl .*set-property .*ActiveProfile s power-saver/.test(logText)],
    ['next-sink-selected', /pactl set-default-sink sink-b/.test(logText)],
    ['no-code-notification', /No code found/.test(logText)],
    // The harness shares the system bus, so the real adapter must be unchanged by the run (restored if it was not).
    ['real-bluetooth-power-unchanged', btBefore === btAfter],
  ].map(([name, passed]) => ({ name, status: passed ? 'pass' : 'fail' }));
  const checks = [...result.checks, ...extra];
  const failed = checks.filter(check => check.status !== 'pass');
  console.log(JSON.stringify({ status: status === 0 && result.status === 'pass' && !failed.length ? 'pass' : 'fail', checks: checks.length, failed, log: logText, tail: failed.length ? output.slice(-2500) : undefined }, null, 2));
  code = status === 0 && result.status === 'pass' && !failed.length ? 0 : 1;
} finally { await rm(scratch, { recursive: true, force: true }); }
process.exitCode = code;
