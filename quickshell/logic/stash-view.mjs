import { shelfLocalUri } from './shelf.mjs';

// View model for the Stash window and the quick tab. Qt-free, and without Intl or
// toLocaleDateString: the QML JavaScript engine has no reliable locale support, so the
// month and weekday names live in the tables below.

const IMAGE_EXTENSIONS = ['png', 'jpg', 'jpeg', 'gif', 'webp', 'avif', 'heic', 'bmp', 'svg', 'tif', 'tiff'];
const TONE_EXTENSIONS = {
    document: ['pdf', 'txt', 'md', 'rtf', 'epub', 'djvu', 'odt', 'tex'],
    office: ['doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx', 'ods', 'odp', 'csv'],
    archive: ['zip', 'rar', '7z', 'tar', 'gz', 'xz', 'bz2', 'zst', 'tgz', 'iso'],
    media: IMAGE_EXTENSIONS.concat(['mp3', 'flac', 'wav', 'ogg', 'opus', 'm4a', 'aac', 'mp4', 'mkv', 'webm', 'mov', 'avi']),
};

const MONTHS = {
    uk: ['січня', 'лютого', 'березня', 'квітня', 'травня', 'червня', 'липня', 'серпня', 'вересня', 'жовтня', 'листопада', 'грудня'],
    en: ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'],
};
const MONTHS_SHORT = {
    uk: ['січ', 'лют', 'бер', 'квіт', 'трав', 'черв', 'лип', 'серп', 'вер', 'жовт', 'лист', 'груд'],
    en: ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'],
};
// Indexed by Date.getDay(): Sunday first.
const WEEKDAYS = {
    uk: ['Неділя', 'Понеділок', 'Вівторок', 'Середа', 'Четвер', 'П’ятниця', 'Субота'],
    en: ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'],
};
const SIZE_UNITS = {
    uk: ['Б', 'КБ', 'МБ', 'ГБ', 'ТБ'],
    en: ['B', 'KB', 'MB', 'GB', 'TB'],
};
const SECTION_ID = /^(\d{4})-(\d{2})-(\d{2})$/;
const MS_PER_DAY = 24 * 60 * 60 * 1000;

function lang(language) { return language === 'uk' ? 'uk' : 'en'; }

function pad2(value) { return (value < 10 ? '0' : '') + value; }

function infoFor(entry, metadata) {
    const key = shelfLocalUri(entry);
    return key && metadata ? metadata[key] : undefined;
}

// The file path of a file: URI, percent-decoded; '' for anything else.
function localPath(uri) {
    if (typeof uri !== 'string' || !/^file:\/\//i.test(uri)) return '';
    const raw = uri.slice(uri.indexOf('/', 'file://'.length)).split(/[?#]/, 1)[0] || '';
    try { return decodeURIComponent(raw); }
    catch (error) { return raw; }
}

function pathExtension(path) {
    const name = path.replace(/\/+$/, '');
    const base = name.slice(name.lastIndexOf('/') + 1);
    const dot = base.lastIndexOf('.');
    if (dot <= 0 || dot === base.length - 1) return '';
    const extension = base.slice(dot + 1).toLowerCase();
    return /^[a-z0-9]{1,8}$/.test(extension) ? extension : '';
}

function parentDirectory(path) {
    const trimmed = path.replace(/\/+$/, '');
    const cut = trimmed.lastIndexOf('/');
    return cut <= 0 ? '/' : trimmed.slice(0, cut);
}

function withHome(path, home) {
    const root = typeof home === 'string' ? home.replace(/\/+$/, '') : '';
    if (!root) return path;
    if (path === root) return '~';
    return path.startsWith(root + '/') ? '~' + path.slice(root.length) : path;
}

// Host and path of an http(s) URL, without scheme, query or fragment.
function urlHostPath(uri) {
    return typeof uri === 'string' ? uri.replace(/^https?:\/\//i, '').split(/[?#]/, 1)[0] : '';
}

function urlHost(uri) {
    const authority = urlHostPath(uri).split('/', 1)[0];
    return authority.slice(authority.lastIndexOf('@') + 1).replace(/:\d*$/, '').replace(/^www\./i, '');
}

export function entryType(entry, info) {
    if (entry.kind === 'image') return 'photo';
    if (entry.kind === 'link' || entry.kind === 'spotify') return 'link';
    if (entry.kind === 'text') return 'text';
    const mimeType = info && typeof info.mimeType === 'string' ? info.mimeType : '';
    if (mimeType) return mimeType.startsWith('image/') ? 'photo' : 'file';
    return IMAGE_EXTENSIONS.includes(pathExtension(localPath(shelfLocalUri(entry)))) ? 'photo' : 'file';
}

export function typeCounts(entries, metadata) {
    const counts = { all: 0, file: 0, photo: 0, link: 0, text: 0 };
    for (const entry of entries) {
        counts.all += 1;
        counts[entryType(entry, infoFor(entry, metadata))] += 1;
    }
    return counts;
}

export function matchesQuery(entry, info, query) {
    const needle = typeof query === 'string' ? query.trim().toLocaleLowerCase() : '';
    if (!needle) return true;
    const fields = [entry.label, entry.text, localPath(shelfLocalUri(entry))];
    if (entry.kind && entry.kind !== 'text') fields.push(urlHostPath(entry.uri));
    return fields.some(field => typeof field === 'string' && field.toLocaleLowerCase().includes(needle));
}

function dayNumber(date) { return Date.UTC(date.getFullYear(), date.getMonth(), date.getDate()) / MS_PER_DAY; }

function sectionIdFor(date, now) {
    const days = dayNumber(now) - dayNumber(date);
    if (days === 0) return 'today';
    if (days === 1) return 'yesterday';
    return date.getFullYear() + '-' + pad2(date.getMonth() + 1) + '-' + pad2(date.getDate());
}

function entryDate(entry) {
    if (!entry.addedAt) return null;
    const date = new Date(entry.addedAt);
    return isNaN(date.getTime()) ? null : date;
}

export function newestFirst(items) {
    // Entries are appended, so a later position is newer: it breaks ties and orders undated entries.
    return items.map((entry, index) => {
        const date = entryDate(entry);
        return { entry, index, time: date ? date.getTime() : -Infinity };
    }).sort((a, b) => (b.time === a.time ? b.index - a.index : b.time > a.time ? 1 : -1))
        .map(item => item.entry);
}

export function buildSections(entries, metadata, options) {
    const settings = options || {};
    const now = settings.now || new Date();
    const filter = settings.filter || 'all';
    const language = lang(settings.language);
    const pinned = [];
    const days = {};
    const dayOrder = [];
    const earlier = [];
    for (const entry of entries) {
        const info = infoFor(entry, metadata);
        if (filter !== 'all' && entryType(entry, info) !== filter) continue;
        if (!matchesQuery(entry, info, settings.query)) continue;
        if (entry.pinned) { pinned.push(entry); continue; }
        const date = entryDate(entry);
        if (!date) { earlier.push(entry); continue; }
        const id = sectionIdFor(date, now);
        if (!days[id]) { days[id] = []; dayOrder.push(id); }
        days[id].push(entry);
    }
    const sections = [];
    if (pinned.length)
        sections.push({ id: 'pinned', title: dayTitle('pinned', now, language), photos: [], rows: newestFirst(pinned) });
    // Ids are today, yesterday and zero-padded dates, so the dates sort as strings; newest first.
    const rank = id => id === 'today' ? 'z2' : id === 'yesterday' ? 'z1' : id;
    for (const id of dayOrder.sort((a, b) => (rank(a) < rank(b) ? 1 : -1))) {
        const sorted = newestFirst(days[id]);
        sections.push({
            id,
            title: dayTitle(id, now, language),
            photos: sorted.filter(entry => entryType(entry, infoFor(entry, metadata)) === 'photo'),
            rows: sorted.filter(entry => entryType(entry, infoFor(entry, metadata)) !== 'photo'),
        });
    }
    if (earlier.length)
        sections.push({ id: 'earlier', title: dayTitle('earlier', now, language), photos: [], rows: newestFirst(earlier) });
    return sections;
}

export function dayTitle(sectionId, now, language) {
    const code = lang(language);
    const uk = code === 'uk';
    if (sectionId === 'pinned') return uk ? 'Закріплене' : 'Pinned';
    if (sectionId === 'today') return uk ? 'Сьогодні' : 'Today';
    if (sectionId === 'yesterday') return uk ? 'Вчора' : 'Yesterday';
    if (sectionId === 'earlier') return uk ? 'Раніше' : 'Earlier';
    const match = SECTION_ID.exec(sectionId || '');
    if (!match) return '';
    const today = now || new Date();
    const date = new Date(Number(match[1]), Number(match[2]) - 1, Number(match[3]));
    const days = dayNumber(today) - dayNumber(date);
    if (days === 0) return dayTitle('today', today, code);
    if (days === 1) return dayTitle('yesterday', today, code);
    if (days >= 2 && days <= 6) return WEEKDAYS[code][date.getDay()];
    const month = MONTHS[code][date.getMonth()];
    const sameYear = date.getFullYear() === today.getFullYear();
    if (uk) return date.getDate() + ' ' + month + (sameYear ? '' : ' ' + date.getFullYear());
    return month + ' ' + date.getDate() + (sameYear ? '' : ', ' + date.getFullYear());
}

// A day section shows the clock. 'pinned' and 'recent' (the quick tab's flat list) mix days,
// so they show the clock only for today and the date otherwise.
export function rowTime(entry, sectionId, language, now) {
    const date = entryDate(entry);
    if (!date) return '';
    const clock = pad2(date.getHours()) + ':' + pad2(date.getMinutes());
    if (sectionId !== 'pinned' && sectionId !== 'recent') return clock;
    const today = now || new Date();
    if (dayNumber(date) === dayNumber(today)) return clock;
    const code = lang(language);
    const month = MONTHS_SHORT[code][date.getMonth()];
    const year = date.getFullYear() === today.getFullYear() ? '' : date.getFullYear();
    if (code === 'uk') return date.getDate() + ' ' + month + (year ? ' ' + year : '');
    return month + ' ' + date.getDate() + (year ? ', ' + year : '');
}

export function formatSize(bytes, language) {
    if (typeof bytes !== 'number' || !isFinite(bytes) || bytes < 0) return '';
    const code = lang(language);
    const units = SIZE_UNITS[code];
    let value = bytes;
    let unit = 0;
    while (unit < units.length - 1 && Math.round(value) >= 1024) { value /= 1024; unit += 1; }
    // Rounding can carry into the next unit (1023.96 KB), so settle the unit on the rounded value.
    let text;
    if (unit > 0 && value < 10) {
        text = (Math.round(value * 10) / 10).toFixed(1);
        if (Number(text) >= 10) text = '10';
    } else text = String(Math.round(value));
    return (code === 'uk' ? text.replace('.', ',') : text) + ' ' + units[unit];
}

function noteLines(text) {
    return typeof text === 'string' ? text.replace(/\s+$/, '').split(/\r?\n/).length : 1;
}

function linesWord(count, language) {
    if (language !== 'uk') return count + (count === 1 ? ' line' : ' lines');
    const hundreds = count % 100;
    const last = count % 10;
    const word = hundreds >= 11 && hundreds <= 14 ? 'рядків' : last === 1 ? 'рядок' : last >= 2 && last <= 4 ? 'рядки' : 'рядків';
    return count + ' ' + word;
}

export function entrySubtitle(entry, info, options) {
    const settings = options || {};
    const code = lang(settings.language);
    const uk = code === 'uk';
    const type = entryType(entry, info);
    if (type === 'text') {
        const lines = noteLines(entry.text);
        const note = uk ? 'Нотатка' : 'Note';
        return lines > 1 ? note + ' · ' + linesWord(lines, code) : note;
    }
    if (type === 'link') return urlHost(entry.uri);
    if (entry.kind === 'image' && !entry.localUri) return uk ? 'Веб-фото · не завантажено' : 'Web photo · not downloaded';
    if (info && info.available === false) return uk ? 'Оригінал не знайдено' : 'Original not found';
    const size = formatSize(info ? info.size : undefined, code);
    const segments = [];
    if (type === 'photo') {
        segments.push(uk ? 'Фото' : 'Photo');
        if (size) segments.push(size);
    } else {
        const path = localPath(shelfLocalUri(entry));
        const kind = info && info.folder ? (uk ? 'Тека' : 'Folder') : pathExtension(path).toUpperCase();
        if (kind) segments.push(kind);
        if (size && !(info && info.folder)) segments.push(size);
        if (path) segments.push(withHome(parentDirectory(path), settings.home));
    }
    return segments.join(' · ');
}

export function typeBadge(entry, info) {
    const type = entryType(entry, info);
    if (type === 'text') return { text: '', tone: 'note' };
    if (type === 'link') return { text: '', tone: 'link' };
    if (entry.kind === 'image') return { text: '', tone: 'media' };
    if (info && info.folder) return { text: '', tone: 'neutral' };
    const extension = pathExtension(localPath(shelfLocalUri(entry)));
    const mimeType = info && typeof info.mimeType === 'string' ? info.mimeType : '';
    let tone = 'neutral';
    for (const name of Object.keys(TONE_EXTENSIONS))
        if (TONE_EXTENSIONS[name].includes(extension)) tone = name;
    if (tone === 'neutral' && /^(?:image|audio|video)\//.test(mimeType)) tone = 'media';
    return { text: extension.slice(0, 4).toUpperCase(), tone };
}

const FAILURE_TEXT = {
    'too-large': { uk: 'Сховок переповнений. Приберіть щось, щоб додати нове.', en: 'Stash is full. Remove something to add more.' },
    'item-too-large': { uk: 'Це завелике для Сховку.', en: 'This is too large for the Stash.' },
    limit: { uk: 'Досягнуто 300 записів. Закріпіть важливе або приберіть зайве.', en: '300 items reached. Pin what matters or remove some.' },
    'pin-limit': { uk: 'Можна закріпити до 50 записів.', en: 'You can pin up to 50 items.' },
};
const CLIPBOARD_FAILURE_TEXT = {
    empty: { uk: 'Буфер обміну порожній.', en: 'The clipboard is empty.' },
    'clipboard-unavailable': { uk: 'Немає доступу до буфера обміну. Встановіть wl-clipboard.', en: "Can't reach the clipboard. Install wl-clipboard." },
    'helper-failed': { uk: 'Не вдалося виконати дію з буфером обміну.', en: 'The clipboard action failed.' },
};
// Refusals that are not failures to show: the Stash is read-only, or the command never ran.
const SILENT_REASONS = ['', 'preview', 'read-only'];

// The message for a Stash command refused by a store or item limit; '' for any other reason.
export function stashFailureText(reason, language) {
    const text = Object.prototype.hasOwnProperty.call(FAILURE_TEXT, reason) ? FAILURE_TEXT[reason] : null;
    return text ? text[lang(language)] : '';
}

// The message for a failed paste or copy: the limits keep their own text, an empty or unreachable
// clipboard says so, and every other failure of the clipboard helper reads the same.
export function clipboardFailureText(reason, language) {
    if (SILENT_REASONS.includes(typeof reason === 'string' ? reason : '')) return '';
    const limit = stashFailureText(reason, language);
    if (limit) return limit;
    const text = Object.prototype.hasOwnProperty.call(CLIPBOARD_FAILURE_TEXT, reason) ? CLIPBOARD_FAILURE_TEXT[reason] : CLIPBOARD_FAILURE_TEXT['helper-failed'];
    return text[lang(language)];
}
