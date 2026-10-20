import test from 'node:test';
import assert from 'node:assert/strict';
import { activeWindowCrop, capturedWindowRegions } from '../../quickshell/logic/screenshot-windows.mjs';

const output = {
  id: 'output-1', name: 'DP-1', x: -1920, y: -200, width: 600, height: 1000,
  scale: 1.5, transform: '90', activeWorkspaceId: '2', specialWorkspaceId: 'special:term',
};
const client = (address, changes = {}) => ({
  address, title: address, monitorId: 'DP-1', workspaceId: '2',
  x: -1900, y: 0, width: 100, height: 100, mapped: true, hidden: false,
  pinned: false, floating: false, ...changes,
});

test('projects clipped global window geometry into image pixels at independent scales', () => {
  const snapshot = { desktop: { outputs: [output] }, clients: [
    client('0x1', { x: -2000, y: -150, width: 200, height: 100 }),
  ] };
  assert.deepEqual(capturedWindowRegions(snapshot, 'DP-1', 900, 2000), [{
    x: 0, y: 100, width: 180, height: 200, title: '0x1', address: '0x1', outputId: 'DP-1',
  }]);
});

test('filters hidden, unmapped and inactive windows while retaining pinned and special-workspace windows', () => {
  const snapshot = { desktop: { outputs: [output] }, clients: [
    client('active'),
    client('hidden', { hidden: true }),
    client('unmapped', { mapped: false }),
    client('inactive', { workspaceId: '9' }),
    client('pinned', { workspaceId: '9', pinned: true }),
    client('special', { workspaceId: 'special:term' }),
  ] };
  assert.deepEqual(capturedWindowRegions(snapshot, 'output-1', 600, 1000).map(item => item.address), ['active', 'pinned', 'special']);
});

test('puts floating windows last so reverse hit testing sees them first', () => {
  const snapshot = { desktop: { outputs: [output] }, clients: [
    client('float-a', { floating: true }),
    client('tiled'),
    client('float-b', { floating: true }),
  ] };
  assert.deepEqual(capturedWindowRegions(snapshot, 'DP-1', 600, 1000).map(item => item.address), ['tiled', 'float-a', 'float-b']);
});

test('clips windows crossing the output edge and does not filter by monitorId', () => {
  const snapshot = { desktop: { outputs: [output] }, clients: [
    client('span', { monitorId: 'another-output', x: -1350, y: 700, width: 100, height: 200 }),
    client('outside', { x: -1300, y: 700, width: 100, height: 200 }),
  ] };
  assert.deepEqual(capturedWindowRegions(snapshot, 'DP-1', 1200, 1000), [{
    x: 1140, y: 900, width: 60, height: 100, title: 'span', address: 'span', outputId: 'DP-1',
  }]);
});

test('activeWindowCrop returns the active visible region or null', () => {
  const snapshot = { activeAddress: 'active', desktop: { outputs: [output] }, clients: [
    client('active', { x: -1800, y: 50, width: 150, height: 80 }),
    client('hidden-active', { hidden: true }),
  ] };
  assert.deepEqual(activeWindowCrop(snapshot, 'DP-1', 1200, 2000), { x: 240, y: 500, width: 300, height: 160 });
  assert.equal(activeWindowCrop({ ...snapshot, activeAddress: 'missing' }, 'DP-1', 1200, 2000), null);
  assert.equal(activeWindowCrop({ ...snapshot, activeAddress: 'hidden-active' }, 'DP-1', 1200, 2000), null);
  assert.equal(activeWindowCrop(snapshot, 'absent', 1200, 2000), null);
});
