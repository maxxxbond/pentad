const own = (value, key) => Object.prototype.hasOwnProperty.call(value, key);
export function utf8Length(input) {
  const value = String(input);
  let bytes = 0;
  for (let index = 0; index < value.length; index++) {
    const code = value.charCodeAt(index);
    if (code < 0x80) bytes++;
    else if (code < 0x800) bytes += 2;
    else if (code >= 0xd800 && code <= 0xdbff && index + 1 < value.length
        && value.charCodeAt(index + 1) >= 0xdc00 && value.charCodeAt(index + 1) <= 0xdfff) { bytes += 4; index++; }
    else bytes += 3;
  }
  return bytes;
}

export function searchTools(entries, query, { favorites = [], recent = [], view = 'all', category = '' } = {}) {
  const needle = String(query || '').trim().toLocaleLowerCase();
  const words = needle.split(/\s+/).filter(Boolean);
  const favoriteSet = new Set(favorites);
  const recentOrder = new Map(recent.map((id, index) => [id, index]));
  const rank = entry => {
    const name = entry.manifest.name.toLocaleLowerCase();
    return !needle || name === needle ? 0 : name.startsWith(needle) ? 1 : name.includes(needle) ? 2 : 3;
  };
  return (entries || []).filter(entry => {
    const manifest = entry?.manifest;
    if (!manifest?.tool || category && manifest.tool.category !== category) return false;
    if (view === 'favorites' && !favoriteSet.has(manifest.id)) return false;
    if (view === 'recent' && !recentOrder.has(manifest.id)) return false;
    const fields = [manifest.name, manifest.tool.category, ...(manifest.tool.keywords || [])]
      .map(value => String(value).toLocaleLowerCase());
    return words.every(word => fields.some(field => field.includes(word)));
  }).sort((a, b) => {
    const relevance = rank(a) - rank(b);
    if (relevance) return relevance;
    if (view !== 'recent') {
      const favoritesFirst = Number(favoriteSet.has(b.manifest.id)) - Number(favoriteSet.has(a.manifest.id));
      if (favoritesFirst) return favoritesFirst;
    }
    const ar = recentOrder.has(a.manifest.id) ? recentOrder.get(a.manifest.id) : Infinity;
    const br = recentOrder.has(b.manifest.id) ? recentOrder.get(b.manifest.id) : Infinity;
    return ar - br || a.manifest.name.localeCompare(b.manifest.name);
  });
}

export function toolEntries(catalog) {
  return Object.values(catalog || {}).filter(entry => entry?.manifest?.tool
      && Array.isArray(entry.manifest.allowedSlots) && entry.manifest.allowedSlots.includes('sidebar-left'))
    .sort((a, b) => a.manifest.name.localeCompare(b.manifest.name));
}

// Browsing order of catalog sections; unknown third-party categories follow alphabetically.
const SECTION_ORDER = ['Documents', 'Convert', 'Files', 'Text', 'Data', 'Create', 'AI'];
const DEFAULT_PINS = ['pentad.pdf', 'pentad.images', 'pentad.media', 'pentad.translate'];

// The resting catalog (no query, filter or pending input) reads as sections; any filtering stays flat.
export function catalogRows(entries, { sectioned = false } = {}) {
  const rank = category => {
    const index = SECTION_ORDER.indexOf(category);
    return index < 0 ? SECTION_ORDER.length : index;
  };
  const rows = (entries || []).map(entry => ({ entry, manifest: entry.manifest, section: sectioned ? entry.manifest.tool.category : '' }));
  if (!sectioned) return rows;
  return rows.sort((a, b) => rank(a.section) - rank(b.section) || a.section.localeCompare(b.section)
    || a.manifest.name.localeCompare(b.manifest.name));
}

// Pinned tiles: favorites first, then recent tools, then built-in suggestions, without repeats.
export function pinnedTools(entries, favorites = [], recent = [], limit = 4) {
  const byId = new Map((entries || []).map(entry => [entry.manifest.id, entry]));
  const picked = [];
  for (const id of [...favorites, ...recent, ...DEFAULT_PINS]) {
    if (byId.has(id) && !picked.includes(byId.get(id))) picked.push(byId.get(id));
    if (picked.length >= limit) break;
  }
  return picked;
}

// Bytes a tool must hold in memory. File references (a URI without inline value) are read by
// the tool from disk, so only their URI counts.
export function inputBytes(items) {
  return (items || []).reduce((sum, item) => sum + (item.kind === 'file' && item.value === undefined ? utf8Length(item.uri ?? '')
    : Number.isFinite(item.sizeBytes) ? item.sizeBytes : utf8Length(item.value ?? item.uri ?? '')), 0);
}

export function classifyText(input) {
  const value = String(input ?? '');
  const trimmed = value.trim();
  let kind = 'text';
  let mimeType = 'text/plain';
  if (trimmed) {
    try { JSON.parse(trimmed); kind = 'json'; mimeType = 'application/json'; }
    catch (error) {
      if (/^https?:\/\/(?:\[[0-9a-f:]+\]|[a-z0-9.-]+)(?::\d{1,5})?(?:[/?#][^\s]*)?$/i.test(trimmed)) { kind = 'url'; mimeType = 'text/uri-list'; }
      if (kind === 'text' && /^#(?:[\da-f]{3,4}|[\da-f]{6}|[\da-f]{8})$/i.test(trimmed)) {
        kind = 'color'; mimeType = 'text/x-color';
      }
    }
  }
  return { kind, mimeType, value, compatibleTypes: [...new Set([mimeType, 'text/plain'])] };
}

export function parseUriList(input) {
  const lines = String(input ?? '').split(/\r?\n/).map(line => line.trim()).filter(line => line && !line.startsWith('#'));
  if (!lines.length) return { ok: false, reason: 'empty', items: [] };
  const items = [];
  for (const value of lines) {
    const localFile = /^file:\/\/([^/]*)(\/[^\s]*)$/i.exec(value);
    const remoteUrl = /^(https?):\/\/(?:\[[0-9a-f:]+\]|[a-z0-9.-]+)(?::\d{1,5})?(?:[/?#][^\s]*)?$/i.test(value);
    if (localFile) {
      if (localFile[1] && localFile[1].toLowerCase() !== 'localhost') return { ok: false, reason: 'remote-file-uri', items: [] };
      items.push({ kind: 'file', mimeType: 'application/octet-stream', uri: value });
    } else if (remoteUrl) {
      items.push({ kind: 'url', mimeType: 'text/uri-list', value });
    } else return { ok: false, reason: 'unsupported-uri', items: [] };
  }
  return { ok: true, items };
}

export function mimeMatches(accepted, actual) {
  return (accepted || []).some(pattern => {
    if (pattern === actual) return true;
    if (!pattern.endsWith('/*')) return false;
    return actual.startsWith(pattern.slice(0, -1));
  });
}

export function compatibleTools(entries, input) {
  const items = Array.isArray(input) ? input : [input];
  if (!items.length) return [];
  return (entries || []).filter(entry => {
    const tool = entry?.manifest?.tool;
    if (!tool || items.length > tool.maxItems || items.length > 1 && !tool.multiple) return false;
    const size = inputBytes(items);
    return size <= tool.maxBytes && items.every(item =>
      (item.compatibleTypes || [item.mimeType]).some(type => mimeMatches(tool.accepts, type)));
  });
}

export function mergeDraft(current, incoming, choice = '') {
  if (!current) return { ok: true, value: incoming };
  if (choice === 'replace') return { ok: true, value: incoming };
  if (choice === 'append') return { ok: true, value: current + incoming };
  return { ok: false, reason: 'choose-replace-or-append' };
}

// Internal text-tool ingress. Validate before callers replace their persisted draft.
export function mergeTextInput(current, items, choice, maxBytes, appendSeparator = '') {
  if (typeof current !== 'string' || !Array.isArray(items) || !items.length
      || items.some(item => !item || typeof item.value !== 'string')
      || !['', 'replace', 'append'].includes(choice)
      || !Number.isSafeInteger(maxBytes) || maxBytes < 1)
    return { ok: false, reason: 'invalid-input' };
  const incoming = items.map(item => item.value).join('\n');
  const merged = mergeDraft(current, choice === 'append' && current ? appendSeparator + incoming : incoming, choice);
  if (!merged.ok) return merged;
  return utf8Length(merged.value) > maxBytes ? { ok: false, reason: 'too-large' } : merged;
}

export function cleanText(input) {
  return String(input ?? '').replace(/\r\n?/g, '\n').split('\n')
    .map(line => line.replace(/[\t ]+$/g, '')).join('\n').replace(/^\n+|\n+$/g, '');
}

export function formatJson(input) {
  try { return { ok: true, value: JSON.stringify(JSON.parse(String(input)), null, 2), mimeType: 'application/json' }; }
  catch (error) { return { ok: false, reason: error.message || 'Invalid JSON' }; }
}

const unitFactors = Object.freeze({
  length: { m: 1, km: 1000, cm: 0.01, mm: 0.001, mi: 1609.344, ft: 0.3048 },
  mass: { kg: 1, g: 0.001, mg: 0.000001, lb: 0.45359237, oz: 0.028349523125 },
  time: { s: 1, min: 60, h: 3600, day: 86400 },
});
export function convertUnit(input, from, to, category = 'length') {
  if (String(input).trim() === '') return { ok: false, reason: 'Enter a finite number' };
  const number = Number(input);
  if (!Number.isFinite(number)) return { ok: false, reason: 'Enter a finite number' };
  if (category === 'temperature') {
    const valid = ['C', 'F', 'K'];
    if (!valid.includes(from) || !valid.includes(to)) return { ok: false, reason: 'Unsupported temperature unit' };
    const kelvin = from === 'C' ? number + 273.15 : from === 'F' ? (number - 32) * 5 / 9 + 273.15 : number;
    const result = to === 'C' ? kelvin - 273.15 : to === 'F' ? (kelvin - 273.15) * 9 / 5 + 32 : kelvin;
    if (!Number.isFinite(result)) return { ok: false, reason: 'Conversion is outside the supported range' };
    return { ok: true, value: Number(result.toPrecision(12)), mimeType: 'text/plain' };
  }
  const factors = unitFactors[category];
  if (!factors || !own(factors, from) || !own(factors, to)) return { ok: false, reason: 'Unsupported unit pair' };
  const result = number * factors[from] / factors[to];
  if (!Number.isFinite(result)) return { ok: false, reason: 'Conversion is outside the supported range' };
  return { ok: true, value: Number(result.toPrecision(12)), mimeType: 'text/plain' };
}
