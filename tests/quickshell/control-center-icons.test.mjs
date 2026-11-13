import test from 'node:test';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { readFile, readdir } from 'node:fs/promises';

const root = new URL('../../quickshell/', import.meta.url);
const read = (path) => readFile(new URL(path, root), 'utf8');

test('bundled Material packs match their recorded upstream hashes', async () => {
  for (const pack of ['assets/icons/material/controls/', 'assets/icons/material/screenshot/', 'assets/icons/material/tools/', 'assets/icons/material/notifications/', 'assets/icons/material/stash/', 'assets/icons/material/status/', 'assets/icons/material/devices/']) {
    const sources = JSON.parse(await read(pack + 'sources.json'));
    const files = (await readdir(new URL(pack, root))).filter((name) => name.endsWith('.svg')).sort();
    assert.deepEqual(sources.icons.map((icon) => icon.file).sort(), files, pack);
    for (const icon of sources.icons) {
      const body = await readFile(new URL(pack + icon.file, root));
      assert.equal(createHash('sha256').update(body).digest('hex'), icon.sha256, pack + icon.file);
      assert.match(icon.url, new RegExp(`/${sources.revision}/symbols/web/[a-z0-9_]+/materialsymbolsrounded/[a-z0-9_]+_fill1_20px\\.svg$`));
    }
  }
});

// R6: one icon family per surface. The control center draws filled Material Symbols only;
// stroked outline drawings and Fluent glyphs belong to other surfaces.
test('control center icons come from one filled family', async () => {
  const files = ['features/system/QuickSettingsGrid.qml', 'features/system/QuickSettingsEditBar.qml',
    'features/system/QuickSettingsEditTray.qml', 'features/system/SessionHeader.qml',
    'features/system/BrightnessControls.qml', 'components/PentadControl.qml'];
  const used = new Set();
  for (const file of files) {
    const code = await read(file);
    assert.doesNotMatch(code, /icons\/fluent\//, file);
    for (const match of code.matchAll(/"((?:controls\/)?[a-z0-9-]+-symbolic(?:\.svg)?)"/g)) {
      if (match[1].startsWith('controls/')) used.add(match[1]);
    }
    for (const match of code.matchAll(/material\/(controls\/[a-z0-9-]+-symbolic\.svg)/g)) used.add(match[1]);
  }
  const header = await read('features/system/SessionHeader.qml');
  for (const match of header.matchAll(/(?:icon: |iconUrl\()"([a-z0-9-]+-symbolic\.svg)"/g)) used.add('controls/' + match[1]);
  assert.ok(used.size >= 15, [...used].join(', '));
  for (const icon of used) {
    const svg = await read('assets/icons/material/' + (icon.endsWith('.svg') ? icon : icon + '.svg'));
    assert.doesNotMatch(svg, /stroke-width/, icon);
    assert.match(svg, /viewBox="0 -960 960 960"/, icon);
  }
  const widgetRoot = new URL('widgets/', root);
  for (const entry of await readdir(widgetRoot, { recursive: true })) {
    if (!entry.endsWith('.qml')) continue;
    const code = await read('widgets/' + entry);
    assert.doesNotMatch(code, /icons\/fluent\//, 'widgets/' + entry);
    for (const match of code.matchAll(/assets\/icons\/(material\/[a-z0-9/-]+-symbolic\.svg)/g)) {
      const svg = await read('assets/icons/' + match[1]);
      assert.doesNotMatch(svg, /stroke-width/, `widgets/${entry} uses the stroked ${match[1]}`);
    }
  }
  const grid = await read('features/system/QuickSettingsGrid.qml');
  const names = grid.split('\n').filter((line) => /\{ key: "(\w+)"/.test(line) && !line.includes('key: "tailscale"'))
    .flatMap((line) => [...line.matchAll(/"(controls\/[a-z0-9-]+\.svg)"/g)].map((match) => match[1]));
  assert.ok(names.length >= 10, names.join(', '));
  assert.equal(new Set(names).size, names.length, 'two tiles share an icon: ' + names.join(', '));
});

// The bar status cluster used to pull the microphone from the system icon theme, so the
// muted state depended on the user's theme and mixed outline and filled glyphs.
test('bar status icons are bundled filled Material glyphs, never theme icons', async () => {
  const { audioIndicator } = await import('../../quickshell/logic/audio.mjs');
  const { networkIndicator } = await import('../../quickshell/logic/network.mjs');
  const cluster = await read('features/bar/StatusCluster.qml');
  assert.doesNotMatch(cluster, /iconPath|Material Symbols Rounded/);
  const icons = new Set();
  for (const kind of ['output', 'input'])
    for (const device of [null, { muted: false }, { muted: true }]) icons.add(audioIndicator(kind, device).icon);
  for (const connectivity of ['full', 'limited', 'portal'])
    for (const [primary, type] of [['wifi', 'wifi'], ['wired', 'wired']])
      icons.add(networkIndicator({ kind: 'ready', value: { primary, connected: true, connectivity,
        devices: [{ type, connected: true }] } }).icon);
  icons.add(networkIndicator({ kind: 'ready', value: { connected: false, devices: [{ type: 'wifi' }] } }).icon);
  icons.add(networkIndicator({ kind: 'unavailable' }).icon);
  assert.ok(icons.size >= 8, [...icons].join(', '));
  for (const icon of icons) {
    const svg = await read('assets/icons/' + icon);
    assert.doesNotMatch(svg, /stroke-width/, icon);
    assert.match(svg, /viewBox="0 -960 960 960"/, icon);
  }
});
