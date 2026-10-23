import test from 'node:test';
import assert from 'node:assert/strict';
import {
    buildSections, dayTitle, entryType, entrySubtitle, formatSize, matchesQuery,
    newestFirst, rowTime, typeBadge, typeCounts,
} from '../../quickshell/logic/stash-view.mjs';

const NOW = new Date(2026, 9, 23, 15, 0);

function at(day, hour, minute, month = 9, year = 2026) {
    return new Date(year, month, day, hour, minute).toISOString();
}

function file(id, name, addedAt, extra = {}) {
    return Object.assign({ id, uri: 'file:///home/u/Documents/' + encodeURIComponent(name), label: name, addedAt, pinned: false }, extra);
}

const PHOTO_INFO = { available: true, mimeType: 'image/png', size: 1000 };

function fixture() {
    const entries = [
        file('pin', 'pinned.pdf', at(20, 9, 0), { pinned: true }),
        file('pdf', 'report.pdf', at(23, 9, 0)),
        file('p1', 'a.png', at(23, 10, 0)),
        file('p2', 'b.png', at(23, 12, 0)),
        { id: 'yd', kind: 'text', uri: '', text: 'groceries', label: 'groceries', addedAt: at(22, 18, 30), pinned: false },
        { id: 'mon', kind: 'link', uri: 'https://github.com/quickshell-mirror/quickshell', label: 'quickshell', addedAt: at(19, 8, 15), pinned: false },
        file('old', 'legacy.zip', ''),
    ];
    const metadata = {};
    for (const entry of entries)
        metadata[entry.uri] = entry.id === 'p1' || entry.id === 'p2'
            ? PHOTO_INFO : { available: true, mimeType: 'application/octet-stream', size: 10 };
    return { entries, metadata };
}

test('buildSections orders pinned, days newest first, then earlier', () => {
    const { entries, metadata } = fixture();
    const sections = buildSections(entries, metadata, { query: '', filter: 'all', now: NOW, language: 'uk' });
    assert.deepEqual(sections.map(section => section.id), ['pinned', 'today', 'yesterday', '2026-10-19', 'earlier']);
    assert.deepEqual(sections.map(section => section.title), ['Закріплене', 'Сьогодні', 'Вчора', 'Понеділок', 'Раніше']);
    const today = sections[1];
    assert.deepEqual(today.photos.map(entry => entry.id), ['p2', 'p1']);
    assert.deepEqual(today.rows.map(entry => entry.id), ['pdf']);
    assert.deepEqual(sections[0].rows.map(entry => entry.id), ['pin']);
    assert.deepEqual(sections[0].photos, []);
});

test('pinned photos are rows and pinned stays newest first', () => {
    const { entries, metadata } = fixture();
    entries[2].pinned = true;
    entries[3].pinned = true;
    const pinned = buildSections(entries, metadata, { query: '', filter: 'all', now: NOW, language: 'en' })[0];
    assert.equal(pinned.title, 'Pinned');
    assert.deepEqual(pinned.photos, []);
    assert.deepEqual(pinned.rows.map(entry => entry.id), ['p2', 'p1', 'pin']);
});

test('filter and query narrow the sections', () => {
    const { entries, metadata } = fixture();
    const photos = buildSections(entries, metadata, { query: '', filter: 'photo', now: NOW, language: 'en' });
    assert.deepEqual(photos.map(section => section.id), ['today']);
    assert.equal(photos[0].rows.length, 0);
    assert.equal(photos[0].photos.length, 2);
    const links = buildSections(entries, metadata, { query: 'quickshell', filter: 'link', now: NOW, language: 'en' });
    assert.equal(links.length, 1);
    assert.deepEqual(links[0].rows.map(entry => entry.id), ['mon']);
    assert.deepEqual(buildSections(entries, metadata, { query: 'nothing-here', filter: 'all', now: NOW, language: 'en' }), []);
});

test('sections use local calendar days, not 24 hour distance', () => {
    const late = new Date(2026, 9, 22, 23, 59).toISOString();
    const early = new Date(2026, 9, 23, 0, 1).toISOString();
    const entries = [file('a', 'a.txt', late), file('b', 'b.txt', early)];
    const sections = buildSections(entries, {}, { query: '', filter: 'all', now: new Date(2026, 9, 23, 0, 30), language: 'en' });
    assert.deepEqual(sections.map(section => section.id), ['today', 'yesterday']);
});

test('dayTitle names days in both languages', () => {
    assert.equal(dayTitle('pinned', NOW, 'uk'), 'Закріплене');
    assert.equal(dayTitle('pinned', NOW, 'en'), 'Pinned');
    assert.equal(dayTitle('today', NOW, 'uk'), 'Сьогодні');
    assert.equal(dayTitle('yesterday', NOW, 'en'), 'Yesterday');
    assert.equal(dayTitle('earlier', NOW, 'uk'), 'Раніше');
    assert.equal(dayTitle('earlier', NOW, 'en'), 'Earlier');
    assert.equal(dayTitle('2026-10-19', NOW, 'uk'), 'Понеділок');
    assert.equal(dayTitle('2026-10-19', NOW, 'en'), 'Monday');
    assert.equal(dayTitle('2026-10-17', NOW, 'en'), 'Saturday');
    assert.equal(dayTitle('2026-10-12', NOW, 'uk'), '12 жовтня');
    assert.equal(dayTitle('2026-10-12', NOW, 'en'), 'October 12');
    assert.equal(dayTitle('2025-10-12', NOW, 'uk'), '12 жовтня 2025');
    assert.equal(dayTitle('2025-12-31', NOW, 'en'), 'December 31, 2025');
});

test('rowTime shows clock times in days and dates in pinned', () => {
    assert.equal(rowTime({ addedAt: at(23, 9, 5) }, 'today', 'uk', NOW), '09:05');
    assert.equal(rowTime({ addedAt: at(19, 18, 40) }, '2026-10-19', 'en', NOW), '18:40');
    assert.equal(rowTime({ addedAt: at(23, 14, 2) }, 'pinned', 'uk', NOW), '14:02');
    assert.equal(rowTime({ addedAt: at(12, 9, 0) }, 'pinned', 'uk', NOW), '12 жовт');
    assert.equal(rowTime({ addedAt: at(12, 9, 0) }, 'pinned', 'en', NOW), 'Oct 12');
    assert.equal(rowTime({ addedAt: at(12, 9, 0, 9, 2025) }, 'pinned', 'en', NOW), 'Oct 12, 2025');
    assert.equal(rowTime({ addedAt: '' }, 'earlier', 'uk', NOW), '');
    assert.equal(rowTime({ addedAt: '' }, 'pinned', 'en', NOW), '');
});

test('formatSize uses base 1024 with localized units', () => {
    assert.equal(formatSize(2516582, 'uk'), '2,4 МБ');
    assert.equal(formatSize(2516582, 'en'), '2.4 MB');
    assert.equal(formatSize(188416, 'en'), '184 KB');
    assert.equal(formatSize(188416, 'uk'), '184 КБ');
    assert.equal(formatSize(812, 'uk'), '812 Б');
    assert.equal(formatSize(812, 'en'), '812 B');
    assert.equal(formatSize(0, 'en'), '0 B');
    assert.equal(formatSize(1048575, 'en'), '1.0 MB');
    assert.equal(formatSize(-1, 'en'), '');
    assert.equal(formatSize(undefined, 'en'), '');
});

test('entryType maps kinds, mime types and extensions', () => {
    assert.equal(entryType({ kind: 'image', uri: 'https://x.test/a' }), 'photo');
    assert.equal(entryType({ kind: 'link', uri: 'https://x.test/' }), 'link');
    assert.equal(entryType({ kind: 'spotify', uri: 'https://open.spotify.com/track/x' }), 'link');
    assert.equal(entryType({ kind: 'text', text: 'hi' }), 'text');
    assert.equal(entryType(file('a', 'a.JPG', ''), undefined), 'photo');
    assert.equal(entryType(file('a', 'a.heic', ''), undefined), 'photo');
    assert.equal(entryType(file('a', 'a.pdf', ''), undefined), 'file');
    assert.equal(entryType(file('a', 'noext', ''), { mimeType: 'image/webp' }), 'photo');
    assert.equal(entryType(file('a', 'x.png', ''), { mimeType: 'application/pdf' }), 'file');
    assert.equal(entryType(file('a', 'Folder', ''), { mimeType: 'inode/directory', folder: true }), 'file');
});

test('typeCounts totals match the entry count', () => {
    const { entries, metadata } = fixture();
    const counts = typeCounts(entries, metadata);
    assert.deepEqual(counts, { all: 7, file: 3, photo: 2, link: 1, text: 1 });
    assert.equal(counts.file + counts.photo + counts.link + counts.text, entries.length);
});

test('matchesQuery searches label, text, path and url', () => {
    const doc = file('a', 'Договір.pdf', '');
    assert.equal(matchesQuery(doc, undefined, ''), true);
    assert.equal(matchesQuery(doc, undefined, 'договір'), true);
    assert.equal(matchesQuery(doc, undefined, 'documents'), true);
    assert.equal(matchesQuery(doc, undefined, 'ДОГОВІР'), true);
    assert.equal(matchesQuery(doc, undefined, 'missing'), false);
    const note = { id: 'n', kind: 'text', uri: '', text: 'Buy Milk\nand eggs', label: 'Buy Milk', addedAt: '', pinned: false };
    assert.equal(matchesQuery(note, undefined, 'eggs'), true);
    const link = { id: 'l', kind: 'link', uri: 'https://www.example.org/guide/start?x=1', label: 'Guide', addedAt: '', pinned: false };
    assert.equal(matchesQuery(link, undefined, 'example.org'), true);
    assert.equal(matchesQuery(link, undefined, '/guide'), true);
    assert.equal(matchesQuery(link, undefined, 'https'), false);
    assert.equal(matchesQuery(link, undefined, 'x=1'), false);
});

test('entrySubtitle describes files, photos, links and notes', () => {
    const pdf = file('a', 'Договір.pdf', '');
    assert.equal(pdf.uri, 'file:///home/u/Documents/%D0%94%D0%BE%D0%B3%D0%BE%D0%B2%D1%96%D1%80.pdf');
    const info = { size: 2516582, mimeType: 'application/pdf', available: true };
    assert.equal(entrySubtitle(pdf, info, { language: 'uk', home: '/home/u' }), 'PDF · 2,4 МБ · ~/Documents');
    assert.equal(entrySubtitle(pdf, info, { language: 'en', home: '/home/u' }), 'PDF · 2.4 MB · ~/Documents');
    assert.equal(entrySubtitle(pdf, info, { language: 'en', home: '/home/other' }), 'PDF · 2.4 MB · /home/u/Documents');
    assert.equal(entrySubtitle(pdf, undefined, { language: 'en', home: '/home/u' }), 'PDF · ~/Documents');
    assert.equal(entrySubtitle(pdf, { available: false }, { language: 'uk', home: '/home/u' }), 'Оригінал не знайдено');
    assert.equal(entrySubtitle(pdf, { available: false }, { language: 'en', home: '/home/u' }), 'Original not found');
    const dir = { id: 'd', uri: 'file:///home/u/Projects/', label: 'Projects', addedAt: '', pinned: false };
    assert.equal(entrySubtitle(dir, { folder: true, available: true, mimeType: 'inode/directory' }, { language: 'uk', home: '/home/u' }), 'Тека · ~');
    assert.equal(entrySubtitle(dir, { folder: true, available: true }, { language: 'en', home: '/home/u' }), 'Folder · ~');
    const png = file('p', 'a.png', '');
    assert.equal(entrySubtitle(png, { mimeType: 'image/png', size: 188416, available: true }, { language: 'uk', home: '/home/u' }), 'Фото · 184 КБ');
    assert.equal(entrySubtitle(png, { mimeType: 'image/png', available: true }, { language: 'en', home: '/home/u' }), 'Photo');
    const web = { id: 'w', kind: 'image', uri: 'https://x.test/p', imageUrl: 'https://x.test/p.jpg', previewUrl: 'https://x.test/p.jpg', label: 'p', addedAt: '', pinned: false };
    assert.equal(entrySubtitle(web, undefined, { language: 'uk', home: '' }), 'Веб-фото · не завантажено');
    assert.equal(entrySubtitle(web, undefined, { language: 'en', home: '' }), 'Web photo · not downloaded');
    const saved = Object.assign({}, web, { localUri: 'file:///home/u/pic.jpg' });
    assert.equal(entrySubtitle(saved, { mimeType: 'image/jpeg', size: 812, available: true }, { language: 'en', home: '/home/u' }), 'Photo · 812 B');
    const link = { id: 'l', kind: 'link', uri: 'https://www.example.org:8080/guide', label: 'g', addedAt: '', pinned: false };
    assert.equal(entrySubtitle(link, undefined, { language: 'en', home: '' }), 'example.org');
});

test('note subtitles use Ukrainian plural rules', () => {
    const note = lines => ({ id: 'n', kind: 'text', uri: '', text: Array.from({ length: lines }, (_, index) => 'l' + index).join('\n'), label: 'l0', addedAt: '', pinned: false });
    const sub = (lines, language) => entrySubtitle(note(lines), undefined, { language, home: '' });
    assert.equal(sub(1, 'uk'), 'Нотатка');
    assert.equal(sub(3, 'uk'), 'Нотатка · 3 рядки');
    assert.equal(sub(5, 'uk'), 'Нотатка · 5 рядків');
    assert.equal(sub(11, 'uk'), 'Нотатка · 11 рядків');
    assert.equal(sub(12, 'uk'), 'Нотатка · 12 рядків');
    assert.equal(sub(14, 'uk'), 'Нотатка · 14 рядків');
    assert.equal(sub(21, 'uk'), 'Нотатка · 21 рядок');
    assert.equal(sub(22, 'uk'), 'Нотатка · 22 рядки');
    assert.equal(sub(1, 'en'), 'Note');
    assert.equal(sub(3, 'en'), 'Note · 3 lines');
});

test('typeBadge gives a short label and a tone', () => {
    assert.deepEqual(typeBadge(file('a', 'x.pdf', ''), undefined), { text: 'PDF', tone: 'document' });
    assert.deepEqual(typeBadge(file('a', 'x.zip', ''), undefined), { text: 'ZIP', tone: 'archive' });
    assert.deepEqual(typeBadge(file('a', 'x.doc', ''), undefined), { text: 'DOC', tone: 'office' });
    assert.deepEqual(typeBadge(file('a', 'x.mp3', ''), undefined), { text: 'MP3', tone: 'media' });
    assert.deepEqual(typeBadge(file('a', 'x.weirdext', ''), undefined), { text: 'WEIR', tone: 'neutral' });
    assert.deepEqual(typeBadge(file('a', 'LICENSE', ''), undefined), { text: '', tone: 'neutral' });
    assert.deepEqual(typeBadge({ kind: 'link', uri: 'https://x.test/' }, undefined), { text: '', tone: 'link' });
    assert.deepEqual(typeBadge({ kind: 'spotify', uri: 'https://open.spotify.com/track/x' }, undefined), { text: '', tone: 'link' });
    assert.deepEqual(typeBadge({ kind: 'text', text: 'x' }, undefined), { text: '', tone: 'note' });
});

test('newestFirst puts later entries first on equal times and undated ones last', () => {
    const same = at(23, 12, 0);
    const entries = [
        { id: 'old', addedAt: at(20, 9, 0) },
        { id: 'legacy', addedAt: '' },
        { id: 'a', addedAt: same },
        { id: 'b', addedAt: same },
        { id: 'newest', addedAt: at(23, 14, 0) },
    ];
    assert.deepEqual(newestFirst(entries).map(entry => entry.id), ['newest', 'b', 'a', 'old', 'legacy']);
    assert.deepEqual(entries.map(entry => entry.id), ['old', 'legacy', 'a', 'b', 'newest'], 'input is not reordered');
});
