import assert from 'node:assert/strict';
import test from 'node:test';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';
import { detectIntent } from '../../quickshell/logic/spotlight-intent.mjs';
import { createSearchDispatcher, LauncherSession, moveGridSelection, parseHistory, rankResults, recordLaunch, togglePinned } from '../../quickshell/logic/spotlight-dispatch.mjs';
import {
  createAppsProvider, createClipboardProvider, createDefaultProviders, createMathProvider, createWebSearchProvider,
  evaluateExpression, fuzzyScore, keyboardEmojiLayouts, parseCliphistLine, parseEmojiPreferences,
  resolveEmojiLanguages, searchClipboardEntries, searchEmojiRecords,
  searchIndexedApps,
} from '../../quickshell/logic/spotlight-providers.mjs';

const app = (name, score = 100) => ({ id: `app-${name}`, category: 'app', title: name, score, actions: [] });

test('emoji grid navigation handles empty data, boundaries and a partial final row', () => {
  assert.equal(moveGridSelection(0, 0, 5, 'down'), 0);
  assert.equal(moveGridSelection(0, 12, 5, 'down'), 5);
  assert.equal(moveGridSelection(8, 12, 5, 'down'), 11);
  assert.equal(moveGridSelection(11, 12, 5, 'down'), 11);
  assert.equal(moveGridSelection(11, 12, 5, 'up'), 6);
  assert.equal(moveGridSelection(3, 12, 5, 'up'), 3);
  assert.equal(moveGridSelection(0, 12, 5, 'left'), 0);
  assert.equal(moveGridSelection(11, 12, 5, 'right'), 11);
  assert.equal(moveGridSelection(4, 12, 5, 'right'), 5);
  assert.equal(moveGridSelection(5, 12, 5, 'left'), 4);
});

test('Spotlight keys route emoji navigation while preserving text editing and other pages', () => {
  const source = readFileSync(new URL('../../quickshell/shell/SpotlightHost.qml', import.meta.url), 'utf8');
  const handler = source.match(/    function handleKey\(event\) \{(.*?)\n    \}/s)[1];
  const Qt = { ControlModifier: 1, ShiftModifier: 2, AltModifier: 4 };
  for (const [, key] of handler.matchAll(/Qt\.(Key_\w+)/g)) if (!(key in Qt)) Qt[key] = 100 + Object.keys(Qt).length;
  const moves = [];
  const context = vm.createContext({ Qt, emojiMode: true,
    search: { cursorPosition: 3, length: 3, selectedText: '' },
    spotlight: { pending: false, page: 'results', move(delta) { moves.push(delta); } },
    emojiGrid: { move(direction) { moves.push(direction); } },
  });
  function key(name, modifiers = 0) {
    context.event = { key: Qt[name], modifiers, accepted: false };
    vm.runInContext(`(function(event) { ${handler} })(event)`, context, { timeout: 1000 });
    return context.event.accepted;
  }
  assert.equal(key('Key_Down'), true);
  assert.equal(key('Key_Right'), true);
  assert.deepEqual(moves, ['down', 'right']);
  assert.equal(key('Key_Left', Qt.ControlModifier), false, 'Ctrl+Left edits the query');
  assert.equal(key('Key_Left', Qt.ShiftModifier), false, 'Shift+Left selects query text');
  context.search.cursorPosition = 1;
  assert.equal(key('Key_Left'), false, 'arrows inside the query retain caret movement');
  context.search.cursorPosition = 3;
  context.search.selectedText = 'по';
  assert.equal(key('Key_Left'), false, 'selected query text retains caret movement');
  context.emojiMode = false;
  context.spotlight.page = 'actions';
  key('Key_Down');
  assert.deepEqual(moves, ['down', 'right', 1], 'action-list navigation stays linear');
});

test('intent precedence, clean queries and input length are bounded', () => {
  assert.deepEqual(detectIntent(' :fire '), { mode: 'emoji', cleanQuery: 'fire', isMathExpression: false });
  assert.equal(detectIntent('cb token').mode, 'clipboard');
  assert.equal(detectIntent('? arch').cleanQuery, 'arch');
  assert.equal(detectIntent('= 24 * 7').mode, 'calc');
  assert.equal(detectIntent('120 / 4 + 5').isMathExpression, true);
  assert.equal(detectIntent('firefox').mode, 'all');
  assert.equal(detectIntent('x'.repeat(400)).cleanQuery.length, 256);
});

test('app fuzzy matching preserves acronym, prefix and bounded browse behavior', () => {
  assert.ok(fuzzyScore('fire', 'Firefox Web Browser') > 60);
  assert.ok(fuzzyScore('vsc', 'Visual Studio Code') > 30);
  assert.equal(fuzzyScore('kitty', 'GIMP Image Editor'), 0);
  const results = searchIndexedApps('web', [
    { id: 'firefox.desktop', name: 'Firefox', exec: 'firefox', comment: 'Web Browser', keywords: ['internet'] },
    { id: 'editor.desktop', name: 'Editor', exec: 'editor', keywords: [] },
  ]);
  assert.deepEqual(results.map(item => item.title), ['Firefox']);
  assert.equal(results[0].actions[0].data.desktopId, 'firefox.desktop');
  assert.equal(searchIndexedApps('', Array.from({ length: 501 }, (_, index) => ({ id: `${index}`, name: `App ${index}`, keywords: [] }))).length, 500);
  assert.equal(createAppsProvider([]).matches('  '), false);
});

test('math parser is bounded and never evaluates arbitrary JavaScript', async () => {
  assert.equal(evaluateExpression('2 + 3 * 4').result, 14);
  assert.equal(evaluateExpression('(2 + 3) * 4').result, 20);
  assert.equal(evaluateExpression('2 ^ 10').result, 1024);
  assert.equal(evaluateExpression('sqrt(144) + pi').success, true);
  assert.equal(evaluateExpression('1 / 0').success, false);
  assert.equal(evaluateExpression('1.2.3 + 4').success, false);
  assert.equal(evaluateExpression('globalThis.process.exit()').success, false);
  assert.equal(evaluateExpression('1'.repeat(300)).success, false);
  const provider = createMathProvider();
  assert.equal(provider.matches('= 25 * 4'), true);
  assert.equal((await provider.search('25 * 4'))[0].title, '100');
});

test('cliphist parsing rejects unsafe IDs and clipboard results stay bounded', async () => {
  assert.deepEqual(parseCliphistLine('42\thello world'), { id: '42', isBinary: false, preview: 'hello world' });
  assert.deepEqual(parseCliphistLine('99\t[[ binary data 1920x1080 png 245 KB ]]'), {
    id: '99', isBinary: true, preview: 'PNG image (1920x1080, 245 KB)',
  });
  assert.equal(parseCliphistLine('1;touch /tmp/x\tbad'), null);
  const entries = Array.from({ length: 35 }, (_, index) => ({ id: String(index), isBinary: false, preview: `token ${index}` }));
  assert.equal(searchClipboardEntries('token', entries).length, 30);
  const provider = createClipboardProvider(entries);
  assert.equal(provider.matches('cb'), true);
  assert.equal((await provider.search('cb token')).length, 30);
});

test('web provider creates an encoded bounded action preview', async () => {
  const results = await createWebSearchProvider().search('? arch & linux');
  assert.equal(results[0].preview.metadata.Engine, 'DuckDuckGo');
  assert.match(results[0].preview.content, /arch%20%26%20linux/);
  assert.equal(results[0].actions[0].data.url, results[0].preview.content);
  assert.equal((await createWebSearchProvider().search('   ')).length, 0);
});

test('emoji search uses selected languages, deduplicates glyphs and honors cancellation', () => {
  const data = {
    uk: [['🔥', 'вогонь', ['палає'], 'fire'], ['🐈️', 'кіт', ['тварина'], 'cat']],
    en: [['🔥', 'fire', ['hot'], 'fire'], ['🎉', 'party popper', ['tada'], 'tada']],
    de: [['🔥', 'Feuer', ['brand'], 'fire']],
  };
  const results = searchEmojiRecords(':fire', data, { languages: ['uk', 'en', 'de'], displayLocale: 'uk_UA.UTF-8' });
  assert.equal(results.filter(item => item.preview.content === '🔥').length, 1);
  assert.equal(results[0].subtitle, 'вогонь');
  assert.equal(searchEmojiRecords(':fire', data, { languages: ['uk', 'en'], displayLocale: 'de' })[0].subtitle, 'вогонь');
  assert.equal(searchEmojiRecords(':feur', data, { languages: ['de'] })[0].preview.content, '🔥');
  assert.equal(searchEmojiRecords(':вогонь', data, { languages: ['en'] }).length, 0);
  assert.deepEqual(searchEmojiRecords(':fire', data, {}, { aborted: true }), []);
  assert.ok(searchEmojiRecords(':', data).length <= 60);
});

test('emoji language preferences remain bounded and derive language from configured layouts', () => {
  assert.deepEqual(parseEmojiPreferences('{}'), { languages: 'auto' });
  assert.deepEqual(parseEmojiPreferences('{"emoji":{"languages":["uk_UA","zh-HK","uk"]}}'), { languages: ['uk', 'zh-hant'] });
  assert.throws(() => parseEmojiPreferences('{"emoji":{"languages":["unsupported"]}}'));
  assert.deepEqual(keyboardEmojiLayouts({ keyboards: [{ layout: 'us,ua' }, { xkb_layout: 'de' }, null] }), ['us,ua', 'de']);
  assert.deepEqual(resolveEmojiLanguages({ locales: ['uk_UA.UTF-8'], layouts: ['de,us'] }), ['uk', 'de', 'en']);
});

test('dispatcher routes by intent, isolates provider errors, browses only on request and drops stale work', async () => {
  let release;
  const pending = new Promise(resolve => { release = resolve; });
  const dispatcher = createSearchDispatcher([
    { category: 'app', matches: () => true, search: async () => [app('Firefox', 40)], browse: async () => [app('Firefox')] },
    { category: 'calc', matches: query => query.startsWith('=') || /^\d.*[+*/-]/.test(query), search: async () => [{ id: 'math', category: 'calc', title: '9', score: 100 }] },
    { category: 'web', matches: () => true, search: async () => { throw new Error('offline'); } },
    { category: 'app', matches: () => { throw new Error('bad provider'); }, search: async () => [] },
    { category: 'app', matches: query => query === 'slow query', search: async () => { await pending; return [app('stale')]; } },
  ]);
  assert.deepEqual(await dispatcher.query(''), []);
  assert.equal((await dispatcher.query('', true)).length, 1);
  const routed = await dispatcher.query('=2 + 7');
  assert.deepEqual(routed.map(item => item.id), ['math']);
  const stale = dispatcher.query('slow query');
  dispatcher.cancel();
  release();
  assert.deepEqual(await stale, []);
});

test('history is bounded and ranked without promoting an unrelated app above exact match', () => {
  let history = parseHistory('{"version":1,"pinned":["app-secret","clipboard-x"],"recent":[]}');
  assert.deepEqual(history.pinned, ['app-secret']);
  history = recordLaunch(history, 'app-Z', 2);
  history = recordLaunch(history, 'app-Z', 3);
  history = togglePinned(history, 'app-B');
  assert.equal(history.recent[0].count, 2);
  const results = [app('weak', 80), { ...app('web', 500), category: 'web' }, app('exact', 150)];
  const ranked = rankResults(results, history);
  assert.deepEqual(ranked.map(item => item.id), ['app-exact', 'app-weak', 'app-web']);
  assert.equal(parseHistory('x'.repeat(70000)).recent.length, 0);
});

test('launcher session rejects stale updates and preserves selected identity', () => {
  const session = new LauncherSession();
  session.open();
  const old = session.beginQuery(), current = session.beginQuery();
  assert.equal(session.accept(current, [app('A'), app('B')]), true);
  session.move(1);
  assert.equal(session.accept(old, [app('old')]), false);
  assert.equal(session.accept(session.beginQuery(), [app('B'), app('A')]), true);
  assert.equal(session.selectedResult.id, 'app-B');
  session.move(-5);
  assert.equal(session.selectedResult.id, 'app-A');
  session.move(5);
  assert.equal(session.selectedResult.id, 'app-B');
  const action = session.beginAction();
  assert.ok(action);
  assert.equal(session.actionPending, true);
  assert.equal(session.beginAction(), null);
  const newerQuery = session.beginQuery();
  assert.equal(session.endAction(action), false);
  assert.equal(session.actionPending, false);
  assert.equal(session.accept(newerQuery, session.results), true);
  const closedAction = session.beginAction();
  assert.ok(closedAction);
  session.close();
  session.open();
  assert.equal(session.endAction(closedAction), false);
});

test('default provider factory yields all pure provider categories', () => {
  assert.deepEqual(createDefaultProviders().map(provider => provider.category), ['calc', 'app', 'clipboard', 'emoji', 'web']);
});
