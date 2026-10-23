import assert from 'node:assert/strict';
import test from 'node:test';
import { appOptions, categoryLabel, formatBytes, formatUptime, systemError, timezoneOptions } from '../../quickshell/logic/settings-system.mjs';

const en = (uk, value) => value;
const uk = value => value;

test('memory reads in binary units with the language decimal mark', () => {
  assert.equal(formatBytes(32768000 * 1024, en), '31.3 GB');
  assert.equal(formatBytes(32768000 * 1024, uk), '31,3 ГБ');
  assert.equal(formatBytes(16 * 1024 ** 3, en), '16 GB');
  assert.equal(formatBytes(512, en), '512 B');
  assert.equal(formatBytes(null, uk), 'Невідомо');
});

test('uptime keeps the two largest units', () => {
  assert.equal(formatUptime(3725, en), '1 h 2 min');
  assert.equal(formatUptime(2 * 86400 + 5 * 3600 + 60, uk), '2 д 5 год');
  assert.equal(formatUptime(86400, en), '1 d');
  assert.equal(formatUptime(59, en), '0 min');
  assert.equal(formatUptime(undefined, en), 'Unknown');
});

test('time zone options keep the current zone and read without underscores', () => {
  assert.deepEqual(timezoneOptions(['America/New_York', 'Europe/Kyiv'], 'Europe/Kyiv').map(option => option.label),
    ['America/New York', 'Europe/Kyiv']);
  assert.deepEqual(timezoneOptions([], 'Europe/Kyiv'), [{ value: 'Europe/Kyiv', label: 'Europe/Kyiv' }]);
  assert.deepEqual(timezoneOptions(undefined, ''), []);
});

test('default-app options list candidates and keep an unknown current choice', () => {
  assert.deepEqual(appOptions({ current: 'custom.desktop', candidates: [{ id: 'firefox.desktop', name: 'Firefox' }] }),
    [{ value: 'custom.desktop', label: 'custom' }, { value: 'firefox.desktop', label: 'Firefox' }]);
  assert.deepEqual(appOptions({ current: '', candidates: [] }), []);
  assert.deepEqual(appOptions(null), []);
  const qtList = { length: 1, 0: { id: 'loupe.desktop', name: 'Loupe' } };
  assert.deepEqual(appOptions({ current: 'loupe.desktop', candidates: qtList }), [{ value: 'loupe.desktop', label: 'Loupe' }]);
});

test('categories and failures read as words', () => {
  assert.equal(categoryLabel('web', en), 'Web browser');
  assert.equal(categoryLabel('video', uk), 'Відео');
  assert.equal(categoryLabel('fax', en), 'fax');
  assert.equal(systemError('denied', en), 'The system did not allow the change');
  assert.equal(systemError('weird', uk), 'Не вдалося (weird)');
});
