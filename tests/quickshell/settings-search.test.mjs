import { test } from 'node:test';
import assert from 'node:assert/strict';
import { matches, search } from '../../quickshell/logic/settings-search.mjs';

const pages = [
    {
        id: 'appearance', group: 'personalization', icon: 'palette',
        labelUk: 'Вигляд', labelEn: 'Appearance', keywords: ['theme', 'colors'],
        sections: [
            {
                id: 'theme', labelUk: 'Тема', labelEn: 'Theme',
                items: [
                    { key: 'theme.mode', kind: 'select', control: 'segmented', document: 'theme', path: 'mode',
                        labelUk: 'Темний режим', labelEn: 'Dark mode', keywords: ['light', 'night'] },
                    { key: 'theme.softness', kind: 'text', control: 'text', document: 'theme', path: 'softness',
                        labelUk: 'М’який акцент', labelEn: 'Soft accent' }
                ]
            }
        ]
    },
    {
        id: 'bar', group: 'shell', icon: 'bar', labelUk: 'Панель', labelEn: 'Bar', keywords: [],
        sections: [
            {
                id: 'tray', labelUk: 'Трей', labelEn: 'Tray',
                items: [
                    { key: 'trayIcons', kind: 'select', control: 'segmented', document: 'layout', path: 'trayIcons',
                        labelUk: 'Іконки трею', labelEn: 'Tray icons', keywords: ['systray', 'status'] },
                    { key: 'showSeconds', kind: 'boolean', control: 'toggle', document: 'layout', path: 'showSeconds',
                        labelUk: 'Секунди', labelEn: 'Seconds' }
                ]
            }
        ]
    }
];

test('matches is case-insensitive and requires every word', () => {
    assert.equal(matches('dark mod', 'Dark mode'), true);
    assert.equal(matches('DARK', 'dark mode'), true);
    assert.equal(matches('tray zzz', 'Tray icons'), false);
    assert.equal(matches('tray icons', 'Icons of the tray'), true);
});

test('matches ignores Ukrainian apostrophes ’ ʼ and ASCII quote', () => {
    assert.equal(matches('м’який', 'М’який акцент'), true);
    assert.equal(matches('мякий', 'Мʼякий акцент'), true);
    assert.equal(matches("м'який", 'Мякий акцент'), true);
    assert.equal(matches('м’який', 'Мякий акцент'), true);
});

test('matches with no words in query is true and no match fails', () => {
    assert.equal(matches('', 'anything'), true);
    assert.equal(matches('xyzzy', 'Dark mode'), false);
});

test('search returns [] for empty or whitespace query', () => {
    assert.deepEqual(search(pages, '', 'en'), []);
    assert.deepEqual(search(pages, '   ', 'uk'), []);
});

test('search finds item keywords', () => {
    assert.deepEqual(search(pages, 'tray', 'en'), [
        { pageId: 'bar', sectionId: 'tray', key: 'trayIcons', label: 'Tray icons' }
    ]);
});

test('search matches Ukrainian labels while returning the requested language label', () => {
    assert.deepEqual(search(pages, 'трею', 'en'), [
        { pageId: 'bar', sectionId: 'tray', key: 'trayIcons', label: 'Tray icons' }
    ]);
    assert.deepEqual(search(pages, 'трею', 'uk'), [
        { pageId: 'bar', sectionId: 'tray', key: 'trayIcons', label: 'Іконки трею' }
    ]);
});

test('search matches page label and keywords and keeps page then item order', () => {
    const results = search(pages, 'colors', 'en');
    assert.deepEqual(results.map((r) => r.key), ['theme.mode', 'theme.softness']);
    assert.deepEqual(search(pages, 'mode', 'en').map((r) => r.key), ['theme.mode']);
});

test('search handles apostrophes in query and no-match without throwing', () => {
    assert.deepEqual(search(pages, 'М’який', 'uk').map((r) => r.key), ['theme.softness']);
    assert.deepEqual(search(pages, 'nothing-like-this', 'en'), []);
});

test('search with multiple words requires all words across the item haystack', () => {
    assert.deepEqual(search(pages, 'dark night', 'en').map((r) => r.key), ['theme.mode']);
    assert.deepEqual(search(pages, 'dark tray', 'en'), []);
});

test('search reports the tab of items that live in a tab', () => {
  const pages = [{ id: 'bar', labelEn: 'Bar', labelUk: 'Панель', tabs: [{ id: 'layout' }, { id: 'tools' }], sections: [
    { id: 'toggles', tab: 'tools', items: [{ key: 'ocr', labelEn: 'OCR', labelUk: 'OCR' }] },
    { id: 'size', tab: 'layout', items: [{ key: 'height', labelEn: 'Height', labelUk: 'Висота' }] }] }];
  assert.deepEqual(search(pages, 'ocr', 'en'), [{ pageId: 'bar', sectionId: 'toggles', key: 'ocr', label: 'OCR', tabId: 'tools' }]);
});
