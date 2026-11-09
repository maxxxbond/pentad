import test from 'node:test';
import assert from 'node:assert/strict';
import { planWings, rowWidth, showMargin } from '../../quickshell/logic/bar-density.mjs';

// Widths measured on the bar: a 36 px idle island slot, 248 with a track, 368 with karaoke; the
// telemetry wing is 247 px, a tools wing with four toggles and nine actions 374.
const bar = (overrides) => ({ width: 2560, inset: 24, gap: 4, spacing: 8, island: 36, left: 36, right: 268,
  telemetry: 247, tools: 374, ...overrides });
const portrait = (overrides) => bar({ width: 1080, inset: 14, ...overrides });

test('a wide bar shows both wings', () => {
  assert.deepEqual(planWings(bar()), { telemetry: true, tools: true });
});

test('a portrait 1080 px bar keeps telemetry and leaves out tools that do not fit their half', () => {
  assert.deepEqual(planWings(portrait()), { telemetry: true, tools: false });
  assert.deepEqual(planWings(portrait({ island: 248 })), { telemetry: true, tools: false }, 'a track plays');
  assert.deepEqual(planWings(portrait({ island: 368 })), { telemetry: true, tools: false }, 'karaoke');
});

test('the halves are independent: a narrow tools wing fits even when telemetry does not', () => {
  assert.deepEqual(planWings(portrait({ left: 300, tools: 120 })), { telemetry: false, tools: true });
});

test('the window title is not part of the left content, so it never pushes telemetry out', () => {
  // 540 half - 18 island - 14 inset - 36 workspaces - 8 spacing leaves 464 px for telemetry and the title.
  assert.equal(planWings(portrait({ telemetry: 464 - 4 - showMargin })).telemetry, true);
  assert.equal(planWings(portrait({ telemetry: 464 - 4 - showMargin + 1 })).telemetry, false);
});

test('a hidden wing needs spare room to return, a shown one stays until it really overflows', () => {
  const exact = portrait({ telemetry: 464 - 4 });
  assert.equal(planWings(exact).telemetry, false, 'no spare room yet');
  assert.equal(planWings(exact, { telemetry: true }).telemetry, true, 'still fits exactly');
  assert.equal(planWings(portrait({ telemetry: 464 - 3 }), { telemetry: true }).telemetry, false, 'one pixel over');
});

test('empty slots and missing numbers show nothing', () => {
  assert.deepEqual(planWings(bar({ telemetry: 0, tools: 0 })), { telemetry: false, tools: false });
  assert.deepEqual(planWings({}), { telemetry: false, tools: false });
  assert.deepEqual(planWings(bar({ width: Number.NaN })), { telemetry: false, tools: false });
  assert.deepEqual(planWings(bar({ inset: undefined })), { telemetry: true, tools: true });
});

test('a row width counts the items a Row lays out and the spacing between them', () => {
  assert.equal(rowWidth([18, 18, 268], 8), 18 + 8 + 18 + 8 + 268);
  assert.equal(rowWidth([18, 0, 268], 8), 18 + 8 + 268, 'a zero-width item takes no spacing');
  assert.equal(rowWidth([18, 18, 0], 8), 18 + 8 + 18, 'an empty steady row');
  assert.equal(rowWidth([], 8), 0);
  assert.equal(rowWidth([Number.NaN, undefined, -4, 30], Number.NaN), 30);
});
