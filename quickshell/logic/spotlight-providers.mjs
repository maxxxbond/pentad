export const spotlightCategories = Object.freeze(['app', 'calc', 'clipboard', 'emoji', 'file', 'web', 'action']);
const MAX_QUERY = 256;
const MAX_APPS = 2000;
const MAX_CLIPS = 1000;
const MAX_RESULTS = 60;
const MAX_EMOJI_RECORDS = 30000;
export const supportedEmojiLanguages = Object.freeze(['bn', 'da', 'de', 'en', 'en-gb', 'es', 'es-mx', 'et', 'fi', 'fr', 'hi', 'hu', 'it', 'ja', 'ko', 'lt', 'ms', 'nb', 'nl', 'pl', 'pt', 'ru', 'sv', 'th', 'uk', 'vi', 'zh', 'zh-hant']);
let emojiCacheRecords = null;
let emojiIndexCache = new Map();
const action = (id, label, shortcut = 'Enter', data = undefined) => {
  const result = { id, label, shortcut };
  if (data !== undefined) result.data = data;
  return result;
};

export function fuzzyScore(query, target) {
  const q = String(query).toLowerCase().trim().slice(0, MAX_QUERY);
  const t = String(target).toLowerCase().trim().slice(0, 512);
  if (!q || !t) return 0;
  if (q === t) return 100;
  if (t.startsWith(q)) return 80 + q.length / t.length * 15;
  if (t.includes(q)) return 50 + q.length / t.length * 15;
  const words = t.split(/[\s\-_]+/);
  const initials = words.map(word => word[0] || '').join('');
  if (initials.includes(q)) return 40 + q.length / initials.length * 20;
  let qi = 0, ti = 0, score = 0, last = -1;
  while (qi < q.length && ti < t.length) {
    if (q[qi] === t[ti]) {
      const previous = t[ti - 1];
      score += ti === 0 || (previous !== undefined && /[\s\-_]/.test(previous)) ? 15 : last === ti - 1 ? 8 : 4;
      last = ti++;
      qi++;
    } else ti++;
  }
  return qi === q.length ? score : 0;
}

export function searchIndexedApps(query, apps) {
  const clean = typeof query === 'string' ? query.trim().slice(0, MAX_QUERY) : '';
  if (!Array.isArray(apps)) return [];
  const scored = [];
  for (const app of apps.slice(0, MAX_APPS)) {
    if (!app || typeof app.id !== 'string' || typeof app.name !== 'string') continue;
    const nameScore = fuzzyScore(clean, app.name) * 1.5;
    const commentScore = app.comment ? fuzzyScore(clean, app.comment) * 0.8 : 0;
    const keywordScore = Array.isArray(app.keywords) ? app.keywords.reduce((best, keyword) => Math.max(best, fuzzyScore(clean, keyword)), 0) : 0;
    const score = Math.round(Math.max(nameScore, commentScore, keywordScore));
    if (score > 15 || !clean) scored.push({ app, score });
  }
  scored.sort((a, b) => b.score - a.score);
  return scored.slice(0, clean ? 40 : 500).map(({ app, score }) => ({
    id: `app-${app.id}`, category: 'app', title: app.name, subtitle: app.comment || app.exec || '',
    icon: app.iconName || 'application-x-executable', score,
    actions: [action('launch-app', `Launch ${app.name}`, 'Enter', { desktopId: app.id })],
    preview: { type: 'app-info', content: app.comment || app.name,
      metadata: { Name: app.name, Executable: app.exec || '', Keywords: Array.isArray(app.keywords) ? app.keywords.join(', ') || 'None' : 'None' } },
  }));
}

export function createAppsProvider(initialApps = []) {
  let apps = Array.isArray(initialApps) ? initialApps.slice(0, MAX_APPS) : [];
  return {
    id: 'apps', category: 'app', matches: query => typeof query === 'string' && query.trim().length > 0,
    setApps(value) { apps = Array.isArray(value) ? value.slice(0, MAX_APPS) : []; },
    browse(signal) { return this.search('', signal); },
    search(query, signal) { return Promise.resolve(signal?.aborted ? [] : searchIndexedApps(query, apps)); },
  };
}

function tokenizeExpression(input) {
  const source = input.trim();
  if (!source || source.length > MAX_QUERY) throw new Error('Expression is empty or too long');
  const tokens = [];
  let i = 0;
  while (i < source.length) {
    const ch = source[i];
    if (/\s/.test(ch)) { i++; continue; }
    if (/[\d.]/.test(ch)) {
      let value = '';
      while (i < source.length && /[\d.]/.test(source[i])) value += source[i++];
      tokens.push({ type: 'number', value });
    } else if (/[a-z]/i.test(ch)) {
      let value = '';
      while (i < source.length && /[a-z0-9]/i.test(source[i])) value += source[i++];
      tokens.push({ type: 'ident', value: value.toLowerCase() });
    } else if ('+-*/^%'.includes(ch)) { tokens.push({ type: 'op', value: ch }); i++; }
    else if (ch === '(' || ch === ')') { tokens.push({ type: ch, value: ch }); i++; }
    else throw new Error(`Unexpected character: ${ch}`);
    if (tokens.length > 256) throw new Error('Expression is too complex');
  }
  tokens.push({ type: 'eof', value: '' });
  return tokens;
}

class ExpressionParser {
  constructor(tokens) { this.tokens = tokens; this.pos = 0; this.depth = 0; }
  current() { return this.tokens[this.pos] || { type: 'eof', value: '' }; }
  eat(type, value) {
    const token = this.current();
    if (token.type !== type || (value !== undefined && token.value !== value)) throw new Error(`Unexpected token: ${token.value}`);
    this.pos++;
    return token;
  }
  parse() { const result = this.expr(); if (this.current().type !== 'eof') throw new Error('Extra tokens'); return result; }
  expr() { let left = this.term(); while (this.current().type === 'op' && ['+', '-'].includes(this.current().value)) { const op = this.eat('op').value, right = this.term(); left = op === '+' ? left + right : left - right; } return left; }
  term() { let left = this.factor(); while (this.current().type === 'op' && '*/%'.includes(this.current().value)) { const op = this.eat('op').value, right = this.factor(); if ((op === '/' || op === '%') && right === 0) throw new Error('Division by zero'); left = op === '*' ? left * right : op === '/' ? left / right : left % right; } return left; }
  factor() { let left = this.unary(); while (this.current().type === 'op' && this.current().value === '^') { this.eat('op'); left = Math.pow(left, this.unary()); } return left; }
  unary() { if (++this.depth > 64) throw new Error('Expression nesting limit exceeded'); try { if (this.current().type === 'op' && ['-', '+'].includes(this.current().value)) { const op = this.eat('op').value; const value = this.unary(); return op === '-' ? -value : value; } return this.primary(); } finally { this.depth--; } }
  primary() {
    const token = this.current();
    if (token.type === 'number') {
      this.eat('number');
      if (!/^([0-9]+(\.[0-9]*)?|\.[0-9]+)$/.test(token.value)) throw new Error('Invalid number');
      const value = Number(token.value);
      if (!Number.isFinite(value)) throw new Error('Invalid number');
      return value;
    }
    if (token.type === 'ident') {
      const name = this.eat('ident').value;
      if (name === 'pi') return Math.PI;
      if (name === 'e') return Math.E;
      if (this.current().type !== '(') throw new Error(`Unknown identifier: ${name}`);
      this.eat('('); const arg = this.expr(); this.eat(')');
      const functions = { sqrt: value => value < 0 ? NaN : Math.sqrt(value), abs: Math.abs, round: Math.round, floor: Math.floor, ceil: Math.ceil, sin: Math.sin, cos: Math.cos, tan: Math.tan, log: value => value <= 0 ? NaN : Math.log(value), ln: value => value <= 0 ? NaN : Math.log(value), log10: value => value <= 0 ? NaN : Math.log10(value) };
      if (!Object.prototype.hasOwnProperty.call(functions, name)) throw new Error(`Unknown function: ${name}`);
      const result = functions[name](arg);
      if (!Number.isFinite(result)) throw new Error(name === 'sqrt' ? 'Square root requires a non-negative value' : 'Invalid function input');
      return result;
    }
    if (token.type === '(') { this.eat('('); const value = this.expr(); this.eat(')'); return value; }
    throw new Error(`Expected a number, got: ${token.value}`);
  }
}

export function evaluateExpression(expression) {
  try {
    const result = new ExpressionParser(tokenizeExpression(String(expression || ''))).parse();
    if (!Number.isFinite(result)) return { success: false, error: 'Result is not finite' };
    const formatted = Number.isInteger(result) ? String(result) : String(Number(result.toFixed(6)));
    return { success: true, result, formatted };
  } catch (error) { return { success: false, error: error?.message || 'Invalid expression' }; }
}

export function createMathProvider() {
  return {
    id: 'math', category: 'calc',
    matches(query) { const clean = query.startsWith('=') ? query.slice(1).trim() : query.trim(); return !!clean && /\d/.test(clean) && evaluateExpression(clean).success; },
    search(query, signal) {
      if (signal?.aborted) return Promise.resolve([]);
      const clean = query.startsWith('=') ? query.slice(1).trim() : query.trim();
      const result = evaluateExpression(clean);
      if (!result.success || result.formatted === undefined) return Promise.resolve([]);
      return Promise.resolve([{ id: `math-${clean}`, category: 'calc', title: result.formatted, subtitle: `${clean} = ${result.formatted}`,
        icon: 'calculator', score: 100, actions: [action('copy-result', 'Copy result', 'Enter', { text: result.formatted })],
        preview: { type: 'math', content: `${clean} = ${result.formatted}`, metadata: { Result: result.formatted, Expression: clean } } }]);
    },
  };
}

export function parseCliphistLine(line) {
  if (typeof line !== 'string' || line.length > 8192) return null;
  const tab = line.indexOf('\t');
  if (tab < 1) return null;
  const id = line.slice(0, tab).trim(), rest = line.slice(tab + 1);
  if (!/^\d{1,20}$/.test(id)) return null;
  if (!rest.includes('[[ binary data')) return { id, isBinary: false, preview: rest.trim().slice(0, 2048) };
  const info = rest.match(/\[\[ binary data\s*(.*?)\s*\]\]/)?.[1]?.trim() || '';
  const parts = info.match(/^(\d+x\d+)\s+([a-z]+)\s+(.+)$/i);
  if (parts) return { id, isBinary: true, preview: `${parts[2].toUpperCase()} image (${parts[1]}, ${parts[3]})` };
  if (/^\d+x\d+$/.test(info)) return { id, isBinary: true, preview: `PNG image (${info})` };
  return { id, isBinary: true, preview: info ? `PNG image (${info})` : 'PNG image' };
}

export function searchClipboardEntries(query, entries) {
  const clean = typeof query === 'string' ? query.toLowerCase().trim().slice(0, MAX_QUERY) : '';
  if (!Array.isArray(entries)) return [];
  return entries.slice(0, MAX_CLIPS).filter(entry => entry && typeof entry.id === 'string'
      && typeof entry.preview === 'string' && (!clean || entry.preview.toLowerCase().includes(clean)))
    .slice(0, 30).map((entry, index) => ({
      id: `clip-${entry.id}`, category: 'clipboard', title: entry.preview.slice(0, 2048),
      subtitle: entry.isBinary ? 'Image' : `Clipboard item ${entry.id}`, icon: entry.isBinary ? 'photo' : 'clipboard-text', score: 100 - index,
      actions: [action('copy-to-clipboard', 'Paste', 'Enter', { clipboardId: entry.id })],
      preview: { type: entry.isBinary ? 'image' : 'text', content: entry.preview.slice(0, 2048), metadata: { ID: entry.id, Type: entry.isBinary ? 'Image' : 'Text' } },
    }));
}

export function createClipboardProvider(initialEntries = []) {
  let entries = Array.isArray(initialEntries) ? initialEntries.slice(0, MAX_CLIPS) : [];
  return {
    id: 'clipboard', category: 'clipboard',
    matches(query) { const clean = query.trim(); return clean === 'cb' || clean.startsWith('cb '); },
    setEntries(value) { entries = Array.isArray(value) ? value.slice(0, MAX_CLIPS) : []; },
    search(query, signal) { if (signal?.aborted) return Promise.resolve([]); const clean = query.trim().replace(/^cb(?:\s|$)/, '').trim(); return Promise.resolve(searchClipboardEntries(clean, entries)); },
  };
}

const MAX_FILES = 60;
const FILE_KINDS = [
  ['image', ['png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp', 'svg', 'avif', 'tif', 'tiff', 'ico']],
  ['video', ['mp4', 'mkv', 'webm', 'mov', 'avi', 'm4v']],
  ['audio', ['mp3', 'flac', 'ogg', 'opus', 'wav', 'm4a', 'aac']],
  ['pdf', ['pdf']],
  ['archive', ['zip', 'tar', 'gz', 'xz', 'zst', '7z', 'rar', 'bz2']],
  ['text', ['txt', 'md', 'json', 'csv', 'log', 'conf', 'ini', 'toml', 'yaml', 'yml', 'xml', 'html', 'css',
    'js', 'mjs', 'ts', 'py', 'sh', 'qml', 'c', 'h', 'cpp', 'rs', 'go', 'java', 'lua']],
  ['document', ['odt', 'doc', 'docx', 'rtf', 'ods', 'xls', 'xlsx', 'odp', 'ppt', 'pptx', 'epub']],
];
// Freedesktop icon names, resolved through the user's icon theme.
export const fileKindIcons = Object.freeze({ folder: 'folder', image: 'image-x-generic', video: 'video-x-generic',
  audio: 'audio-x-generic', pdf: 'application-pdf', archive: 'package-x-generic', text: 'text-x-generic',
  document: 'x-office-document', other: 'text-x-generic' });

export function fileKind(name, directory = false) {
  if (directory) return 'folder';
  const dot = typeof name === 'string' ? name.lastIndexOf('.') : -1;
  const extension = dot > 0 ? name.slice(dot + 1).toLowerCase() : '';
  return FILE_KINDS.find(([, extensions]) => extensions.includes(extension))?.[0] || 'other';
}

export function formatFileSize(bytes, units = ['B', 'KB', 'MB', 'GB', 'TB']) {
  if (!Number.isFinite(bytes) || bytes < 0) return '';
  let value = bytes, unit = 0;
  while (value >= 1000 && unit < units.length - 1) { value /= 1000; unit++; }
  return `${unit === 0 || value >= 10 ? Math.round(value) : value.toFixed(1)} ${units[unit]}`;
}

// Files rank below applications (whose matches score above 15) and above web search.
export function searchFileEntries(query, entries) {
  const terms = typeof query === 'string' ? query.toLowerCase().trim().slice(0, MAX_QUERY).split(/\s+/).filter(Boolean) : [];
  if (!terms.length || !Array.isArray(entries)) return [];
  const results = [];
  for (const entry of entries.slice(0, MAX_FILES)) {
    if (!entry || typeof entry.path !== 'string' || typeof entry.name !== 'string' || !entry.path.startsWith('/')) continue;
    const name = entry.name.toLowerCase();
    if (!terms.every(term => name.includes(term))) continue;
    const start = name.startsWith(terms[0]) ? 3 : name.includes(` ${terms[0]}`) || name.includes(`_${terms[0]}`)
      || name.includes(`-${terms[0]}`) ? 2 : 0;
    const depth = Math.min(9, (entry.folder || '').split('/').length);
    const kind = fileKind(entry.name, entry.directory === true);
    results.push({
      id: `file-${entry.path}`, category: 'file', title: entry.name.slice(0, 512), subtitle: (entry.folder || '').slice(0, 1024),
      icon: fileKindIcons[kind], score: 10 + start - depth * 0.1 - results.length * 0.001,
      actions: [action('open-file', 'Open', 'Enter', { path: entry.path }), action('copy-path', 'Copy path', 'Ctrl+C', { text: entry.path })],
      preview: { type: 'file', kind, path: entry.path, content: entry.path,
        size: entry.directory === true ? -1 : Number(entry.size), modified: Number(entry.modified) },
    });
  }
  return results;
}

export function createFilesProvider(initialEntries = []) {
  let entries = Array.isArray(initialEntries) ? initialEntries.slice(0, MAX_FILES) : [];
  return {
    id: 'files', category: 'file',
    matches(query) { return query.trim().length >= 2; },
    setEntries(value) { entries = Array.isArray(value) ? value.slice(0, MAX_FILES) : []; },
    search(query, signal) { return Promise.resolve(signal?.aborted ? [] : searchFileEntries(query, entries)); },
  };
}

export function buildWebSearchUrl(query, template = 'https://duckduckgo.com/?q=%s') {
  const clean = typeof query === 'string' ? query.trim().slice(0, MAX_QUERY) : '';
  if (!clean || typeof template !== 'string' || template.length > 512 || !template.includes('%s')) return '';
  return template.replace('%s', encodeURIComponent(clean));
}

export function createWebSearchProvider(template) {
  return {
    id: 'web', category: 'web', matches: query => query.trim().length > 0,
    search(query, signal) {
      if (signal?.aborted) return Promise.resolve([]);
      const clean = query.trim().startsWith('?') ? query.trim().slice(1).trim() : query.trim();
      const url = buildWebSearchUrl(clean, template || 'https://duckduckgo.com/?q=%s');
      if (!url) return Promise.resolve([]);
      return Promise.resolve([{ id: `web-${clean}`, category: 'web', title: `Search the web for ${clean}`,
        subtitle: url, icon: 'world-search', score: 20,
        actions: [action('open-web', 'Search in browser', 'Enter', { url })],
        preview: { type: 'text', content: url, metadata: { Query: clean, Engine: 'DuckDuckGo' } } }]);
    },
  };
}

export function normalizeEmojiLocale(value) {
  if (typeof value !== 'string') return undefined;
  const locale = value.trim().split(/[.@]/)[0].replace(/_/g, '-').toLowerCase();
  if (!locale || locale === 'c' || locale === 'posix') return undefined;
  if (/^zh-(hant|tw|hk|mo)(-|$)/.test(locale)) return 'zh-hant';
  if (supportedEmojiLanguages.includes(locale)) return locale;
  const language = locale.split('-')[0];
  return supportedEmojiLanguages.includes(language) ? language : undefined;
}

const keyboardLayoutLanguages = {
  us: 'en', gb: 'en', au: 'en', ca: 'en', ua: 'uk', de: 'de', at: 'de', ch: 'de', fr: 'fr', be: 'fr',
  es: 'es', latam: 'es', mx: 'es-mx', pt: 'pt', br: 'pt', it: 'it', ru: 'ru', pl: 'pl', nl: 'nl', dk: 'da',
  fi: 'fi', ee: 'et', se: 'sv', no: 'nb', lt: 'lt', hu: 'hu', jp: 'ja', kr: 'ko', cn: 'zh', tw: 'zh-hant',
  hk: 'zh-hant', vn: 'vi', th: 'th', in: 'hi', bd: 'bn', my: 'ms',
};

export function resolveEmojiLanguages(options = {}) {
  const result = [];
  const add = value => {
    const language = normalizeEmojiLocale(value);
    if (language && !result.includes(language)) result.push(language);
  };
  if (Array.isArray(options.languages) && options.languages.length) {
    for (const value of options.languages.slice(0, 64)) add(value);
  } else {
    const locales = Array.isArray(options.locales) ? options.locales.slice(0, 64) : [];
    for (const locale of locales) for (const part of String(locale).split(':')) add(part);
    const layouts = Array.isArray(options.layouts) ? options.layouts.slice(0, 64) : [];
    for (const layout of layouts) for (const code of String(layout).toLowerCase().split(',')) {
      const language = keyboardLayoutLanguages[code.trim().replace(/\([^)]*\)/g, '')];
      if (language) add(language);
    }
  }
  if (!result.includes('en')) result.push('en');
  return result;
}

export function parseEmojiPreferences(text) {
  if (typeof text !== 'string') throw new Error('Spotlight configuration exceeds 64 KiB');
  let byteLength = 0;
  for (let i = 0; i < text.length; i++) {
    const code = text.charCodeAt(i);
    if (code < 0x80) byteLength++;
    else if (code < 0x800) byteLength += 2;
    else if (code >= 0xd800 && code <= 0xdbff && i + 1 < text.length
        && text.charCodeAt(i + 1) >= 0xdc00 && text.charCodeAt(i + 1) <= 0xdfff) { byteLength += 4; i++; }
    else byteLength += 3;
    if (byteLength > 65536) throw new Error('Spotlight configuration exceeds 64 KiB');
  }
  const input = JSON.parse(text);
  if (!input || typeof input !== 'object' || Array.isArray(input)) throw new Error('Spotlight configuration must be an object');
  const emoji = input.emoji;
  if (emoji === undefined) return { languages: 'auto' };
  if (!emoji || typeof emoji !== 'object' || Array.isArray(emoji)) throw new Error('emoji must be an object');
  const languages = emoji.languages;
  if (languages === undefined || languages === 'auto') return { languages: 'auto' };
  if (!Array.isArray(languages) || !languages.length || languages.length > 64
      || !languages.every(value => typeof value === 'string' && normalizeEmojiLocale(value)))
    throw new Error('emoji.languages must be auto or a nonempty array of supported language codes');
  const normalized = [];
  for (const value of languages) {
    const locale = normalizeEmojiLocale(value);
    if (!normalized.includes(locale)) normalized.push(locale);
  }
  return { languages: normalized };
}

export function keyboardEmojiLayouts(devices) {
  if (!devices || typeof devices !== 'object' || !Array.isArray(devices.keyboards)) return [];
  const layouts = [];
  for (const keyboard of devices.keyboards) {
    if (!keyboard || typeof keyboard !== 'object') continue;
    const layout = keyboard.layout !== undefined && keyboard.layout !== null ? keyboard.layout : keyboard.xkb_layout;
    if (typeof layout === 'string' && layout.trim()) layouts.push(layout);
  }
  return layouts;
}

const normalizeEmojiText = value => String(value).normalize('NFKD').toLowerCase().replace(/[\u0300-\u036f]/g, '')
  .replace(/[^\p{L}\p{N}+]+/gu, ' ').trim().replace(/\s+/g, ' ');
function oneEmojiTypo(left, right) {
  if (left.length < 4 || Math.abs(left.length - right.length) > 1) return false;
  let a = 0, b = 0, edits = 0;
  while (a < left.length && b < right.length) {
    if (left[a] === right[b]) { a++; b++; continue; }
    if (++edits > 1) return false;
    if (left.length === right.length && left[a] === right[b + 1] && left[a + 1] === right[b]) { a += 2; b += 2; }
    else if (left.length > right.length) a++;
    else if (left.length < right.length) b++;
    else { a++; b++; }
  }
  return edits + Number(a < left.length || b < right.length) <= 1;
}
const emojiTermScore = (query, term) => query === term ? 100 : term.startsWith(query) ? 80 : term.includes(query) ? 60
  : !term.includes(' ') && oneEmojiTypo(query, term) ? 35 : 0;

export function searchEmojiRecords(query, recordsByLocale, options = {}, signal = undefined) {
  if (signal?.aborted || typeof query !== 'string' || query.length > MAX_QUERY || !recordsByLocale || typeof recordsByLocale !== 'object') return [];
  const languages = resolveEmojiLanguages(options);
  const requested = normalizeEmojiLocale(options.displayLocale);
  const preferred = requested && languages.includes(requested) ? requested : languages[0] || 'en';
  const order = [preferred];
  for (const language of languages) if (language !== preferred) order.push(language);
  const key = JSON.stringify(order);
  if (emojiCacheRecords !== recordsByLocale) { emojiCacheRecords = recordsByLocale; emojiIndexCache = new Map(); }
  const cache = emojiIndexCache;
  let items = cache.get(key);
  if (!items) {
    const index = new Map();
    let processed = 0;
    for (const locale of order) {
      if (processed >= MAX_EMOJI_RECORDS) break;
      const rows = Array.isArray(recordsByLocale[locale]) ? recordsByLocale[locale].slice(0, 10000) : [];
      for (const row of rows) {
        if (processed++ >= MAX_EMOJI_RECORDS) break;
        if (!Array.isArray(row) || typeof row[0] !== 'string' || typeof row[1] !== 'string') continue;
        const glyph = row[0], name = row[1], tags = row[2], shortcode = row[3];
        let item = index.get(glyph);
        if (!item) { item = { glyph, name, shortcode: typeof shortcode === 'string' ? shortcode : '', labels: new Set(), terms: new Set() }; index.set(glyph, item); }
        item.labels.add(normalizeEmojiText(name));
        const terms = [name, item.shortcode];
        if (Array.isArray(tags)) for (const tag of tags.slice(0, 32)) if (typeof tag === 'string') terms.push(tag.slice(0, 256));
        for (const term of terms) {
          const normalized = normalizeEmojiText(term);
          if (normalized) { item.terms.add(normalized); for (const word of normalized.split(' ')) item.terms.add(word); }
        }
      }
    }
    items = [];
    index.forEach(item => items.push(item));
    cache.set(key, items);
    if (cache.size > 8) cache.delete(cache.keys().next().value);
  }
  const clean = query.trim().replace(/^:/, '').replace(/:$/, '').trim();
  const normalized = normalizeEmojiText(clean), tokens = normalized.split(' ').filter(Boolean);
  if (tokens.length > 16) return [];
  if (!clean) return items.slice(0, MAX_RESULTS).map(item => mapEmoji(item, 95));
  if (!tokens.length) return items.filter(item => item.glyph === clean).slice(0, MAX_RESULTS).map(item => mapEmoji(item, 150));
  const ranked = [];
  for (const item of items) {
    let total = 0, all = true;
    for (const token of tokens) {
      let best = 0;
      for (const term of item.terms) best = Math.max(best, emojiTermScore(token, term));
      if (!best) { all = false; break; }
      total += best;
      if (signal?.aborted) return [];
    }
    if (all) {
      let exactName = item.labels.has(normalized), typoName = false;
      if (!exactName) item.labels.forEach(label => { if (oneEmojiTypo(normalized, label)) typoName = true; });
      ranked.push({ item, score: total / tokens.length + (exactName ? 40 : typoName ? 20 : 0) });
    }
  }
  ranked.sort((a, b) => b.score - a.score);
  return ranked.slice(0, MAX_RESULTS).map(({ item, score }) => mapEmoji(item, score));
}

function mapEmoji(item, score) {
  const codepoints = [];
  for (let i = 0; i < item.glyph.length; i++) {
    const point = item.glyph.codePointAt(i);
    codepoints.push(point.toString(16).toUpperCase());
    if (point > 0xffff) i++;
  }
  return { id: `emoji-${codepoints.join('-')}`, category: 'emoji', title: `${item.glyph} :${item.shortcode}:`, subtitle: item.name,
    score, actions: [action('copy-emoji', `Copy ${item.glyph}`, 'Enter', { text: item.glyph })],
    preview: { type: 'emoji', content: item.glyph, metadata: { Name: item.name, Shortcode: `:${item.shortcode}:`, CodePoint: codepoints.map(point => `U+${point}`).join(' ') } } };
}

export function createEmojiProvider(recordsByLocale, options = {}) {
  return { id: 'emoji', category: 'emoji', matches: query => /^\s*:/.test(query),
    search(query, signal) { return Promise.resolve(searchEmojiRecords(query, recordsByLocale, options, signal)); } };
}

export function createDefaultProviders({ apps = [], clipboard = [], emojiRecords = {}, emoji = {}, files = [], webTemplate } = {}) {
  return [createMathProvider(), createAppsProvider(apps), createClipboardProvider(clipboard), createEmojiProvider(emojiRecords, emoji),
    createFilesProvider(files), createWebSearchProvider(webTemplate)];
}
