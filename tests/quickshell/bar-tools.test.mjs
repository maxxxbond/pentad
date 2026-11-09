import test from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import {
  audioOutputScript, pickLabel, qrScript, regionActions, scriptActions, barTools, barToolsDefaults, colorFormats, enabledEngines, focusPath, imageCaptureScript, inhibitCommand,
  ocrScript, parseBarTools, pickerCommand, searchEngines, searchPlan, translateScript, visibleTools,
} from '../../quickshell/logic/bar-tools.mjs';

const syntaxOk = script => spawnSync('sh', ['-n', '-c', script]).status === 0;

test('a fresh config keeps the original four tools and adds the new actions', () => {
  const { toggles, actions } = visibleTools(undefined);
  assert.deepEqual(toggles.map(tool => tool.id), ['dnd', 'inhibit']);
  assert.deepEqual(actions.map(tool => tool.id), ['screenshot', 'record', 'ocr', 'picker', 'translate', 'imageSearch']);
});

test('tool ids are unique and every tool is a toggle or an action', () => {
  assert.equal(new Set(barTools.map(tool => tool.id)).size, barTools.length);
  assert.ok(barTools.every(tool => ['toggle', 'action'].includes(tool.kind)));
  assert.ok(['night', 'bluetooth', 'airplane', 'saver', 'overnight', 'focus'].every(id => barTools.some(tool => tool.id === id && tool.kind === 'toggle')));
});

test('visibility follows the saved flags and hides everything when all are off', () => {
  const show = Object.fromEntries(barTools.map(tool => [tool.id, false]));
  assert.deepEqual(visibleTools({ show }), { toggles: [], actions: [] });
  assert.deepEqual(visibleTools({ show: { ...show, night: true, ocr: true } }).toggles.map(tool => tool.id), ['night']);
});

test('parsing fills defaults, keeps valid values and rejects unknown ones', () => {
  assert.deepEqual(parseBarTools(undefined), barToolsDefaults);
  const parsed = parseBarTools({ show: { night: true }, search: { mode: 'direct', engine: 'yandex' }, picker: { format: 'rgb' } });
  assert.equal(parsed.show.night, true);
  assert.equal(parsed.show.dnd, true);
  assert.equal(parsed.search.mode, 'direct');
  assert.equal(parsed.picker.format, 'rgb');
  for (const bad of [
    { show: { nope: true } }, { show: { night: 'yes' } }, { search: { mode: 'sometimes' } },
    { search: { engine: 'altavista' } }, { search: { engines: { google: 1 } } }, { ocr: { languages: 'eng; rm' } },
    { picker: { format: 'lab' } }, { translate: { target: 'XX' } }, { translate: { keyFile: 'relative/key' } }, [], 'text',
  ]) assert.throws(() => parseBarTools(bad), undefined, JSON.stringify(bad));
});

test('the API key file must be an absolute or home path', () => {
  assert.equal(parseBarTools({ translate: { keyFile: '~/.config/deepl.key' } }).translate.keyFile, '~/.config/deepl.key');
  assert.equal(parseBarTools({ translate: { keyFile: '/run/secrets/deepl' } }).translate.keyFile, '/run/secrets/deepl');
  assert.equal(parseBarTools({ translate: { keyFile: '' } }).translate.keyFile, '');
});

test('image search asks by default and goes straight to the preferred engine in direct mode', () => {
  assert.equal(searchPlan(undefined).kind, 'ask');
  assert.equal(searchPlan(undefined).engines.length, searchEngines.length);
  const direct = searchPlan({ search: { mode: 'direct', engine: 'bing' } });
  assert.equal(direct.kind, 'direct');
  assert.equal(direct.engine.id, 'bing');
});

test('direct mode falls back to asking when the preferred engine is disabled, and reports no engines', () => {
  const engines = Object.fromEntries(searchEngines.map(engine => [engine.id, engine.id === 'tineye']));
  assert.equal(searchPlan({ search: { mode: 'direct', engine: 'google', engines } }).kind, 'ask');
  assert.deepEqual(enabledEngines({ search: { engines } }).map(engine => engine.id), ['tineye']);
  const none = Object.fromEntries(searchEngines.map(engine => [engine.id, false]));
  assert.equal(searchPlan({ search: { mode: 'direct', engines: none } }).kind, 'none');
});

test('every search engine opens an https page', () => {
  for (const engine of searchEngines) assert.match(engine.url, /^https:\/\/[a-z0-9.-]+\//, engine.id);
  assert.equal(new Set(searchEngines.map(engine => engine.id)).size, searchEngines.length);
});

test('keep-awake commands are bounded and fall back to indefinite', () => {
  assert.equal(inhibitCommand(0).at(-1), 'infinity');
  assert.equal(inhibitCommand(1800).at(-1), '1800');
  assert.equal(inhibitCommand(-5).at(-1), 'infinity');
  assert.equal(inhibitCommand(10 ** 7).at(-1), 'infinity');
  assert.equal(inhibitCommand('60; rm').at(-1), 'infinity');
});

test('the color picker passes only known formats to hyprpicker', () => {
  for (const format of colorFormats) assert.deepEqual(pickerCommand(format), ['hyprpicker', '-a', '-f', format]);
  assert.deepEqual(pickerCommand('x; reboot'), ['hyprpicker', '-a', '-f', 'hex']);
});

test('the focus marker lives in the cache directory the agent rules refer to', () => {
  assert.equal(focusPath('/home/user'), '/home/user/.cache/pentad-focus');
  assert.equal(focusPath('/home/user/'), '/home/user/.cache/pentad-focus');
});

test('generated shell scripts parse', () => {
  assert.ok(syntaxOk(ocrScript('eng+ukr')));
  assert.ok(syntaxOk(imageCaptureScript));
  assert.ok(syntaxOk(translateScript({ target: 'UK', languages: 'eng', provider: 'deepl' })));
  assert.ok(syntaxOk(translateScript({ target: 'DE', languages: 'eng', provider: 'google' })));
  assert.ok(syntaxOk(qrScript));
  assert.ok(syntaxOk(audioOutputScript));
});

test('the audio output script picks the next sink and wraps around', () => {
  const pick = cur => spawnSync('sh', ['-c', `printf 'a\\nb\\nc\\n' | awk -v cur="${cur}" '{a[NR]=$0; if ($0==cur) i=NR} END {print a[i%NR+1]}'`]).stdout.toString().trim();
  assert.equal(pick('a'), 'b');
  assert.equal(pick('c'), 'a');
  assert.match(audioOutputScript, /awk -v cur=/);
});

test('privacy, QR and audio tools exist but start hidden, and script actions are known', () => {
  assert.deepEqual(['ruler', 'magnifier'].map(id => barTools.find(tool => tool.id === id).kind), ['action', 'action']);
  assert.deepEqual(['privacy', 'qrScan', 'audioOutput'].map(id => barTools.find(tool => tool.id === id).visible), [false, false, false]);
  assert.deepEqual([...scriptActions].sort(), ['audio-output', 'image-search', 'magnifier', 'ocr', 'qr-scan', 'ruler', 'translate']);
  assert.deepEqual([...regionActions].sort(), ['image-search', 'magnifier', 'ocr', 'qr-scan', 'record', 'ruler', 'translate']);
});

test('scripts never interpolate unvalidated language or target text', () => {
  assert.ok(!ocrScript("eng'; reboot; '").includes('reboot'));
  assert.ok(!translateScript({ target: 'UK; reboot', languages: 'eng', provider: 'deepl' }).includes('reboot'));
  assert.ok(!translateScript({ target: 'UK', languages: '$(reboot)', provider: 'deepl' }).includes('reboot'));
});

test('every area tool has a label for the picker overlay', () => {
  const text = (uk, en) => en;
  for (const kind of regionActions) assert.notEqual(pickLabel(kind, text), '', kind);
  assert.equal(pickLabel('nope', text), '');
});

test('the DeepL key reaches curl through stdin, not its arguments', () => {
  const script = translateScript({ target: 'UK', languages: 'eng', provider: 'deepl' });
  assert.match(script, /-K - /);
  assert.ok(!/-H [^|]*\$key/.test(script));
  assert.match(script, /api-free\.deepl\.com/);
  assert.match(script, /api\.deepl\.com/);
});

test('OCR falls back to English when a language pack is missing', () => {
  const run = spawnSync('sh', ['-c', ocrScript('eng+ukr').split('text=')[0]
    + 'printf %s "$langs"'], { env: { ...process.env, PATH: process.env.PATH } });
  assert.match(run.stdout.toString(), /^eng(\+ukr)?$/);
});

test('engines with an upload form name an https endpoint and a field the script can quote', () => {
  const uploading = searchEngines.filter(engine => engine.upload);
  assert.deepEqual(uploading.map(engine => engine.id), ['google', 'tineye', 'saucenao', 'iqdb', 'ascii2d']);
  for (const engine of uploading) {
    assert.match(engine.upload.url, /^https:\/\/[a-z0-9.-]+\/[^"|\s]*$/, engine.id);
    assert.match(engine.upload.field, /^[a-z_]+$/, engine.id);
  }
});

test('overnight settings default, parse and reject bad values', () => {
  assert.deepEqual(barToolsDefaults.overnight, { end: '08:00', openrgb: { start: 'Night', end: 'Day' }, commands: { start: '', end: '' } });
  assert.equal(barToolsDefaults.show.overnight, false);
  const parsed = parseBarTools({ overnight: { end: 'none', openrgb: { start: 'Dark Room' }, commands: { end: 'fanctl auto' } } });
  assert.deepEqual(parsed.overnight, { end: 'none', openrgb: { start: 'Dark Room', end: 'Day' }, commands: { start: '', end: 'fanctl auto' } });
  for (const bad of [
    { overnight: [] }, { overnight: { end: '06:00' } }, { overnight: { openrgb: { start: 'a;b' } } }, { overnight: { openrgb: { end: '' } } },
    { overnight: { openrgb: 'Night' } }, { overnight: { commands: { start: 'x'.repeat(1001) } } }, { overnight: { commands: { end: 1 } } },
  ]) assert.throws(() => parseBarTools(bad), undefined, JSON.stringify(bad));
});
