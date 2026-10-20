import test from 'node:test';
import assert from 'node:assert/strict';
import { trayAvailability, trayIconMode, trayTooltip } from '../../quickshell/logic/tray.mjs';

test('tray availability exposes native items in the shared value shape', () => {
  const items = [{ id: 'app/status' }];
  assert.deepEqual(trayAvailability(items), { kind: 'ready', value: { items } });
  assert.deepEqual(trayAvailability(null), { kind: 'unavailable', reason: 'binding-missing' });
});

test('tray icon modes retain the three supported choices', () => {
  for (const mode of ['soft', 'color', 'monochrome']) assert.equal(trayIconMode(mode), mode);
  assert.equal(trayIconMode('unknown'), 'soft');
});

test('tray tooltip joins only nonempty native title and description', () => {
  assert.equal(trayTooltip({ tooltipTitle: 'Network', tooltipDescription: 'Connected' }), 'Network\nConnected');
  assert.equal(trayTooltip({ tooltipTitle: '', tooltipDescription: '' }), '');
});
