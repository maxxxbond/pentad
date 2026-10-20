import assert from 'node:assert/strict';
import test from 'node:test';
import { occupiedSlots, placementsForSlot } from '../../quickshell/logic/placement.mjs';

const clock = { id: 'pentad.clock', allowedSlots: ['system', 'tools', 'center'], pentads: ['left', 'center', 'right'] };
const weather = { id: 'pentad.weather', allowedSlots: ['sidebar-left', 'sidebar-right'], pentads: ['left-menu', 'right-menu'] };
const catalog = { 'pentad.clock': { manifest: clock }, 'pentad.weather': { manifest: weather } };
const widget = (instanceId, moduleId, slot, settings = {}, enabled = true) => ({ instanceId, moduleId, slot, enabled, settings });

test('without stored zones a widget keeps its legacy slot and a neutral frame', () => {
  const widgets = [widget('a', 'pentad.clock', 'system'), widget('b', 'pentad.clock', 'center')];
  const result = placementsForSlot(widgets, catalog, 'system');
  assert.deepEqual(result.map(entry => entry.instanceId), ['a']);
  assert.deepEqual(result[0].frame, { margin: 0, padding: 0, background: 'none' });
  assert.equal(result[0].slot, 'system');
  assert.deepEqual(placementsForSlot(widgets, catalog, 'tools'), []);
});

test('disabled widgets and unknown manifests are handled', () => {
  const widgets = [widget('a', 'pentad.clock', 'system', {}, false), widget('x', 'pentad.unknown', 'system')];
  assert.deepEqual(placementsForSlot(widgets, catalog, 'system').map(entry => entry.instanceId), ['x']);
  assert.deepEqual(placementsForSlot(null, catalog, 'system'), []);
});

test('stored zones place the widget in the first allowed slot of every active section', () => {
  const placement = widget('c', 'pentad.clock', 'system', { _zones: ['center', 'right'] });
  assert.deepEqual(occupiedSlots(clock, placement), [{ zone: 'center', slot: 'center' }, { zone: 'right', slot: 'tools' }]);
  const widgets = [placement];
  assert.deepEqual(placementsForSlot(widgets, catalog, 'center').map(entry => entry.zone), ['center']);
  assert.deepEqual(placementsForSlot(widgets, catalog, 'tools').map(entry => entry.zone), ['right']);
  assert.deepEqual(placementsForSlot(widgets, catalog, 'system'), [], 'the legacy slot is left once zones are stored');
});

test('position orders widgets inside a section and ties keep config order', () => {
  const widgets = [
    widget('a', 'pentad.clock', 'system', { _zones: ['right'], _order_right: 3 }),
    widget('b', 'pentad.clock', 'system', { _zones: ['right'], _order_right: 1 }),
    widget('c', 'pentad.clock', 'system', { _zones: ['right'] }),
  ];
  assert.deepEqual(placementsForSlot(widgets, catalog, 'tools').map(entry => entry.instanceId), ['b', 'c', 'a']);
});

test('frame and size come from the stored values', () => {
  const widgets = [widget('a', 'pentad.weather', 'sidebar-left', { _zones: ['left-menu'], _margin: 8, _padding: 4, _bg: 'solid', _size_left_menu: 'tile', '_size_left-menu': 'tile' })];
  const [entry] = placementsForSlot(widgets, catalog, 'sidebar-left');
  assert.deepEqual(entry.frame, { margin: 8, padding: 4, background: 'solid' });
  assert.equal(entry.size, 'tile');
  assert.equal(entry.zone, 'left-menu');
});

test('invalid stored values fall back to defaults instead of breaking the slot', () => {
  const widgets = [widget('a', 'pentad.weather', 'sidebar-left', { _margin: 7, _bg: 'neon' })];
  const [entry] = placementsForSlot(widgets, catalog, 'sidebar-left');
  assert.deepEqual(entry.frame, { margin: 0, padding: 0, background: 'none' });
});
