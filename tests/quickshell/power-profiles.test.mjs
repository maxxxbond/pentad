import test from 'node:test';
import assert from 'node:assert/strict';
import { parseActiveProfile, parseProfiles, validProfile } from '../../quickshell/logic/power-profiles.mjs';

test('power profile parser accepts listed profiles and actual profile only', () => {
  const profiles = parseProfiles('* balanced:\n  performance:\n  power-saver:');
  assert.deepEqual(profiles, ['balanced', 'performance', 'power-saver']);
  assert.equal(parseActiveProfile('performance\n', profiles), 'performance');
  assert.equal(validProfile('power-saver', profiles), true);
});

test('power profile parser rejects empty, malformed, and unlisted readback', () => {
  assert.throws(() => parseProfiles(''), /service-missing/);
  assert.throws(() => parseProfiles('malformed response'), /service-missing/);
  const profiles = ['balanced', 'performance'];
  assert.throws(() => parseActiveProfile('turbo', profiles), /invalid-response/);
  assert.equal(validProfile('turbo', profiles), false);
});
