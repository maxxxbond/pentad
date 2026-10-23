import assert from 'node:assert/strict';
import test from 'node:test';
import { iconCandidates, indexApplications } from '../../quickshell/logic/spotlight-apps.mjs';
import { searchIndexedApps } from '../../quickshell/logic/spotlight-providers.mjs';
import { parseHistory, rankResults } from '../../quickshell/logic/spotlight-dispatch.mjs';

test('native app index supports sequences, filters hidden entries and keeps launch identities', () => {
  const entries = { length: 6,
    0: { id: 'firefox', name: 'Firefox', icon: 'firefox', genericName: 'Web Browser', keywords: { length: 1, 0: 'internet' } },
    1: { id: 'hidden', name: 'Hidden', noDisplay: true },
    2: { id: 'terminal', name: 'Terminal', comment: 'Command line' },
    3: { id: 'firefox', name: 'Duplicate' },
    4: { id: '', name: 'Invalid' }, 5: null };
  const index = indexApplications(entries);
  assert.deepEqual(index.map(app => app.id), ['firefox.desktop', 'terminal.desktop']);
  assert.equal(searchIndexedApps('browser', index)[0].actions[0].data.desktopId, 'firefox.desktop');
  assert.equal(searchIndexedApps('internet', index)[0].icon, 'firefox');
  assert.deepEqual(searchIndexedApps('unmatchable', index), []);
  assert.equal(searchIndexedApps('', index).length, 2);
  assert.deepEqual(indexApplications(null), []);
});

test('desktop IDs retain pins and usage ranking with the native Quickshell catalog', () => {
  const apps = indexApplications([{ id: 'firefox', name: 'Firefox' }, { id: 'terminal', name: 'Terminal' }]);
  const history = parseHistory(JSON.stringify({ version: 1, pinned: ['app-terminal.desktop'],
    recent: [{ id: 'app-firefox.desktop', count: 30, used: 100 }] }));
  assert.equal(rankResults(searchIndexedApps('', apps), history, true)[0].id, 'app-terminal.desktop');
  const results = searchIndexedApps('', apps).map(result => ({ ...result, score: 100 }));
  assert.equal(rankResults(results, { ...history, pinned: [] })[0].id, 'app-firefox.desktop');
});

test('icon candidates fall back from a Steam game icon to the Steam icon, then to a generic one', () => {
  assert.deepEqual(iconCandidates('steam_icon_730'), ['steam_icon_730', 'steam', 'application-x-executable']);
  assert.deepEqual(iconCandidates('firefox'), ['firefox', 'application-x-executable']);
  assert.deepEqual(iconCandidates(''), ['application-x-executable']);
  assert.deepEqual(iconCandidates(null), ['application-x-executable']);
});

test('a Steam game uses its cached icon between the theme icon and the Steam icon', () => {
  const steamIcons = { 730: '/steam/730/icon.jpg', 440: 'relative.jpg', 570: 42 };
  assert.deepEqual(iconCandidates('steam_icon_730', steamIcons),
    ['steam_icon_730', '/steam/730/icon.jpg', 'steam', 'application-x-executable']);
  assert.deepEqual(iconCandidates('steam_icon_440', steamIcons), ['steam_icon_440', 'steam', 'application-x-executable']);
  assert.deepEqual(iconCandidates('steam_icon_570', steamIcons), ['steam_icon_570', 'steam', 'application-x-executable']);
  assert.deepEqual(iconCandidates('steam_icon_1', null), ['steam_icon_1', 'steam', 'application-x-executable']);
  assert.deepEqual(iconCandidates('steam_icon_constructor', steamIcons), ['steam_icon_constructor', 'application-x-executable']);
  assert.deepEqual(iconCandidates('firefox', steamIcons), ['firefox', 'application-x-executable']);
});
