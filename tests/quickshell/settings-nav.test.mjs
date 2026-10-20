import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  initialNav,
  selectPage,
  selectTab,
  moveSelection,
  flatPages,
} from '../../quickshell/logic/settings-nav.mjs';

const page = (id, group, tabs) => ({
  id,
  group,
  icon: 'x',
  labelUk: id,
  labelEn: id,
  keywords: [],
  ...(tabs ? { tabs } : {}),
  sections: [],
});
const tabs = (...ids) => ids.map((id) => ({ id, labelUk: id, labelEn: id }));

const pages = [
  page('wallpaper', 'personalization', tabs('look', 'colors')),
  page('bar', 'shell'),
  page('notifications', 'shell', tabs('general')),
  page('keys', 'behavior'),
  page('session', 'system'),
];

test('flatPages orders pages by group, keeping input order within a group', () => {
  assert.deepEqual(
    flatPages(pages).map((p) => p.id),
    ['wallpaper', 'bar', 'notifications', 'keys', 'session'],
  );
});

test('flatPages orders by group even when input is unsorted', () => {
  const shuffled = [pages[4], pages[3], pages[1], pages[0]];
  assert.deepEqual(
    flatPages(shuffled).map((p) => p.id),
    ['wallpaper', 'bar', 'keys', 'session'],
  );
});

test('flatPages of an empty list is empty', () => {
  assert.deepEqual(flatPages([]), []);
});

test('initialNav selects the first page and its first tab', () => {
  assert.deepEqual(initialNav(pages), { pageId: 'wallpaper', tabId: 'look', query: '' });
});

test('initialNav uses an empty tab id for a page without tabs', () => {
  assert.deepEqual(initialNav([page('bar', 'shell')]), { pageId: 'bar', tabId: '', query: '' });
});

test('initialNav on no pages yields an empty selection', () => {
  assert.deepEqual(initialNav([]), { pageId: '', tabId: '', query: '' });
});

test('selectPage switches page, resets tab to first tab and clears query', () => {
  const nav = { pageId: 'wallpaper', tabId: 'colors', query: 'font' };
  assert.deepEqual(selectPage(nav, pages, 'notifications'), {
    pageId: 'notifications',
    tabId: 'general',
    query: '',
  });
  assert.deepEqual(selectPage(nav, pages, 'bar'), { pageId: 'bar', tabId: '', query: '' });
});

test('selectPage with an unknown id leaves the navigation unchanged', () => {
  const nav = { pageId: 'wallpaper', tabId: 'colors', query: 'font' };
  assert.deepEqual(selectPage(nav, pages, 'nope'), nav);
});

test('selectPage does not mutate the input navigation', () => {
  const nav = { pageId: 'wallpaper', tabId: 'look', query: '' };
  const out = selectPage(nav, pages, 'bar');
  assert.notEqual(out, nav);
  assert.deepEqual(nav, { pageId: 'wallpaper', tabId: 'look', query: '' });
});

test('selectTab sets a tab that belongs to the current page', () => {
  const nav = { pageId: 'wallpaper', tabId: 'look', query: '' };
  assert.deepEqual(selectTab(nav, pages, 'colors'), { pageId: 'wallpaper', tabId: 'colors', query: '' });
  assert.deepEqual(nav, { pageId: 'wallpaper', tabId: 'look', query: '' });
});

test('selectTab ignores tab ids that do not belong to the current page', () => {
  const nav = { pageId: 'wallpaper', tabId: 'look', query: '' };
  assert.deepEqual(selectTab(nav, pages, 'general'), nav);
  assert.deepEqual(selectTab({ pageId: 'bar', tabId: '', query: '' }, pages, 'look'), {
    pageId: 'bar',
    tabId: '',
    query: '',
  });
});

test('selectTab keeps the query', () => {
  const nav = { pageId: 'wallpaper', tabId: 'look', query: 'x' };
  assert.equal(selectTab(nav, pages, 'colors').query, 'x');
});

test('moveSelection steps forward and backward through flat page order', () => {
  const start = { pageId: 'bar', tabId: '', query: '' };
  assert.equal(moveSelection(start, pages, 1).pageId, 'notifications');
  assert.equal(moveSelection(start, pages, -1).pageId, 'wallpaper');
});

test('moveSelection resets the tab to the new page first tab', () => {
  const nav = { pageId: 'bar', tabId: '', query: 'q' };
  assert.deepEqual(moveSelection(nav, pages, 1), { pageId: 'notifications', tabId: 'general', query: '' });
});

test('moveSelection clamps at both ends without wrapping', () => {
  const first = { pageId: 'wallpaper', tabId: 'look', query: '' };
  const last = { pageId: 'session', tabId: '', query: '' };
  assert.equal(moveSelection(first, pages, -1).pageId, 'wallpaper');
  assert.equal(moveSelection(last, pages, 1).pageId, 'session');
});

test('moveSelection supports first and last', () => {
  const mid = { pageId: 'keys', tabId: '', query: '' };
  assert.equal(moveSelection(mid, pages, 'first').pageId, 'wallpaper');
  assert.equal(moveSelection(mid, pages, 'last').pageId, 'session');
});

test('moveSelection with an unknown current page moves to the first page on a forward step', () => {
  const nav = { pageId: 'nope', tabId: '', query: '' };
  assert.equal(moveSelection(nav, pages, 1).pageId, 'wallpaper');
});

test('moveSelection on no pages returns the navigation unchanged', () => {
  const nav = { pageId: '', tabId: '', query: '' };
  assert.deepEqual(moveSelection(nav, [], 1), nav);
});

test('moveSelection does not mutate the input navigation', () => {
  const nav = { pageId: 'bar', tabId: '', query: '' };
  const out = moveSelection(nav, pages, 1);
  assert.notEqual(out, nav);
  assert.deepEqual(nav, { pageId: 'bar', tabId: '', query: '' });
});
