import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import {
  orderProfiles, parseProbe, parseReadback, probeCommand, readbackCommand, setCommand, validProfile,
} from '../../quickshell/logic/power-profiles.mjs';

const entry = (name) => ({ Profile: { type: 's', data: name }, Driver: { type: 's', data: 'placeholder' } });
const probeOutput = (active, names) => `${JSON.stringify({ type: 's', data: active })}\n`
  + `${JSON.stringify({ type: 'aa{sv}', data: names.map(entry) })}\n`;

test('probe reads the active profile and lists profiles fastest first', () => {
  const result = parseProbe(probeOutput('balanced', ['power-saver', 'balanced', 'performance']));
  assert.deepEqual(result, { profiles: ['performance', 'balanced', 'power-saver'], actual: 'balanced' });
  assert.deepEqual(parseProbe(probeOutput('power-saver', ['power-saver', 'balanced'])).profiles, ['balanced', 'power-saver']);
  assert.equal(validProfile('power-saver', result.profiles), true);
});

test('probe rejects empty, malformed and unlisted answers', () => {
  assert.throws(() => parseProbe(''), /invalid-response/);
  assert.throws(() => parseProbe('Failed to get property: not found'), /invalid-response/);
  assert.throws(() => parseProbe(probeOutput('balanced', [])), /service-missing/);
  assert.throws(() => parseProbe(probeOutput('turbo', ['balanced', 'power-saver'])), /invalid-response/);
  assert.throws(() => parseProbe('x'.repeat(16385)), /invalid-response/);
  assert.throws(() => parseProbe(JSON.stringify({ type: 's', data: 'balanced' })), /invalid-response/);
});

test('readback accepts only a listed profile', () => {
  const profiles = ['performance', 'balanced', 'power-saver'];
  assert.equal(parseReadback('{"type":"s","data":"performance"}\n', profiles), 'performance');
  assert.throws(() => parseReadback('{"type":"s","data":"turbo"}', profiles), /invalid-response/);
  assert.throws(() => parseReadback('{"type":"b","data":true}', profiles), /invalid-response/);
  assert.throws(() => parseReadback('', profiles), /invalid-response/);
  assert.equal(validProfile('turbo', ['balanced', 'performance']), false);
});

test('commands are bounded busctl argument arrays and writes take only listed profiles', () => {
  for (const argv of [probeCommand, readbackCommand]) {
    assert.deepEqual(argv.slice(0, 3), ['busctl', '--system', '--timeout=2']);
    assert.ok(argv.includes('get-property'));
  }
  assert.deepEqual(setCommand('power-saver', ['balanced', 'power-saver']).slice(-3), ['ActiveProfile', 's', 'power-saver']);
  assert.throws(() => setCommand('performance', ['balanced', 'power-saver']), /unavailable/);
  assert.throws(() => setCommand('balanced; rm -rf /', ['balanced; rm -rf /']), /unavailable/);
  assert.deepEqual(orderProfiles(['custom', 'power-saver', 'performance']), ['performance', 'power-saver', 'custom']);
});

test('the power service never polls the daemon', () => {
  const source = readFileSync(new URL('../../quickshell/services/Power.qml', import.meta.url), 'utf8');
  assert.doesNotMatch(source, /powerprofilesctl/);
  assert.doesNotMatch(source, /repeat:\s*true/);
  assert.match(source, /target: root\.active \? PowerProfiles : null/);
});
