import test from 'node:test';
import assert from 'node:assert/strict';
import { sidebarPlacements } from '../../quickshell/logic/sidebar.mjs';
import { validateManifest } from '../../quickshell/logic/plugin-manifest.mjs';
import { readFile } from 'node:fs/promises';

test('sidebar placement selection keeps enabled sidebar entries in saved order', () => {
  const widgets = [
    { instanceId: 'workspaces-main', slot: 'sidebar-left', enabled: true },
    { instanceId: 'clock-main', slot: 'system', enabled: true },
    { instanceId: 'weather-main', slot: 'sidebar-left', enabled: false },
    { instanceId: 'chat-main', slot: 'sidebar-left', enabled: true },
  ];

  assert.deepEqual(sidebarPlacements(widgets).map(item => item.instanceId), [
    'workspaces-main', 'chat-main',
  ]);
  assert.deepEqual(sidebarPlacements(undefined), []);
});

test('built-in workspaces manifest is a valid sidebar widget', async () => {
  const manifest = JSON.parse(await readFile(
    new URL('../../quickshell/widgets/workspaces/manifest.json', import.meta.url), 'utf8',
  ));
  assert.equal(validateManifest(manifest, { slot: 'sidebar-left' }).ok, true);
});
