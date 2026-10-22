// Pure text helpers for the sidebar tools. No Node APIs: also imported by QML's JS engine.
const ok = value => ({ ok: true, value });
const fail = reason => ({ ok: false, reason });

// ---------- UTF-8 / base64 ----------
export function utf8Encode(text) {
  const bytes = [];
  for (const ch of String(text)) {
    let c = ch.codePointAt(0);
    if (c >= 0xD800 && c <= 0xDFFF) c = 0xFFFD;
    if (c < 0x80) bytes.push(c);
    else if (c < 0x800) bytes.push(0xC0 | (c >> 6), 0x80 | (c & 63));
    else if (c < 0x10000) bytes.push(0xE0 | (c >> 12), 0x80 | ((c >> 6) & 63), 0x80 | (c & 63));
    else bytes.push(0xF0 | (c >> 18), 0x80 | ((c >> 12) & 63), 0x80 | ((c >> 6) & 63), 0x80 | (c & 63));
  }
  return bytes;
}

export function utf8Decode(bytes) {
  let out = '';
  for (let i = 0; i < bytes.length;) {
    const b = bytes[i];
    let need = 0, c = 0, min = 0;
    if (b < 0x80) { out += String.fromCharCode(b); i++; continue; }
    else if (b >= 0xC2 && b <= 0xDF) { need = 1; c = b & 0x1F; min = 0x80; }
    else if (b >= 0xE0 && b <= 0xEF) { need = 2; c = b & 0x0F; min = 0x800; }
    else if (b >= 0xF0 && b <= 0xF4) { need = 3; c = b & 0x07; min = 0x10000; }
    else return fail('Not valid UTF-8 text');
    for (let k = 1; k <= need; k++) {
      const n = bytes[i + k];
      if (n === undefined || (n & 0xC0) !== 0x80) return fail('Not valid UTF-8 text');
      c = (c << 6) | (n & 63);
    }
    if (c < min || c > 0x10FFFF || (c >= 0xD800 && c <= 0xDFFF)) return fail('Not valid UTF-8 text');
    out += String.fromCodePoint(c);
    i += need + 1;
  }
  return ok(out);
}

const B64 = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';

export function base64Encode(text, urlSafe = false) {
  const b = utf8Encode(text);
  let out = '';
  for (let i = 0; i < b.length; i += 3) {
    const n = (b[i] << 16) | ((b[i + 1] || 0) << 8) | (b[i + 2] || 0);
    out += B64[(n >> 18) & 63] + B64[(n >> 12) & 63];
    out += i + 1 < b.length ? B64[(n >> 6) & 63] : '=';
    out += i + 2 < b.length ? B64[n & 63] : '=';
  }
  return ok(urlSafe ? out.replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '') : out);
}

function base64Bytes(input) {
  const s = String(input).replace(/\s+/g, '').replace(/-/g, '+').replace(/_/g, '/').replace(/=+$/, '');
  if (s === '') return fail('Nothing to decode');
  if (!/^[A-Za-z0-9+/]+$/.test(s) || s.length % 4 === 1) return fail('Not valid Base64');
  const bytes = [];
  let acc = 0, bits = 0;
  for (let i = 0; i < s.length; i++) {
    acc = (acc << 6) | B64.indexOf(s[i]);
    bits += 6;
    if (bits >= 8) { bits -= 8; bytes.push((acc >> bits) & 255); acc &= (1 << bits) - 1; }
  }
  return ok(bytes);
}

export function base64Decode(input) {
  const r = base64Bytes(input);
  return r.ok ? utf8Decode(r.value) : r;
}

// ---------- URL / HTML / hex ----------
export function urlEncode(text) {
  try { return ok(encodeURIComponent(String(text))); } catch (e) { return fail('Cannot encode lone surrogate characters'); }
}
export function urlDecode(input) {
  try { return ok(decodeURIComponent(String(input).trim())); } catch (e) { return fail('Not valid URL encoding'); }
}

const htmlNamed = { amp: '&', lt: '<', gt: '>', quot: '"', apos: "'", nbsp: ' ' };
export function htmlEncode(text) {
  return ok(String(text).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;').replace(/'/g, '&#39;'));
}
export function htmlDecode(input) {
  return ok(String(input).replace(/&(?:#(\d+)|#[xX]([0-9a-fA-F]+)|([A-Za-z]+));/g, (m, dec, hex, name) => {
    if (name) return Object.prototype.hasOwnProperty.call(htmlNamed, name) ? htmlNamed[name] : m;
    const c = dec ? parseInt(dec, 10) : parseInt(hex, 16);
    return c > 0 && c <= 0x10FFFF && !(c >= 0xD800 && c <= 0xDFFF) ? String.fromCodePoint(c) : m;
  }));
}

export function hexEncode(text) {
  return ok(utf8Encode(text).map(b => (b < 16 ? '0' : '') + b.toString(16)).join(''));
}
export function hexDecode(input) {
  const s = String(input).replace(/0x/gi, '').replace(/[\s:,-]+/g, '');
  if (s === '') return fail('Nothing to decode');
  if (!/^[0-9a-fA-F]+$/.test(s) || s.length % 2) return fail('Not valid hex');
  const bytes = [];
  for (let i = 0; i < s.length; i += 2) bytes.push(parseInt(s.substr(i, 2), 16));
  return utf8Decode(bytes);
}

// ---------- JWT ----------
function jwtJson(part, name) {
  const t = base64Decode(part);
  if (!t.ok) return fail('JWT ' + name + ' is not valid Base64URL');
  try { return ok(JSON.parse(t.value)); } catch (e) { return fail('JWT ' + name + ' is not valid JSON'); }
}
export function decodeJwt(input, now = Date.now()) {
  const parts = String(input).trim().split('.');
  if (parts.length !== 3 || !parts[0] || !parts[1]) return fail('Not a JWT: expected three dot-separated parts');
  const header = jwtJson(parts[0], 'header');
  if (!header.ok) return header;
  const payload = jwtJson(parts[1], 'payload');
  if (!payload.ok) return payload;
  let out = 'Header\n' + JSON.stringify(header.value, null, 2) + '\n\nPayload\n' + JSON.stringify(payload.value, null, 2);
  const times = [];
  for (const claim of ['exp', 'iat', 'nbf']) {
    const v = payload.value && payload.value[claim];
    if (typeof v === 'number' && isFinite(v) && Math.abs(v) < 8.64e12) {
      times.push(claim + ': ' + new Date(v * 1000).toISOString() + ' (' + relativeTime(v * 1000, now) + ')');
    }
  }
  if (times.length) out += '\n\n' + times.join('\n');
  out += '\n\nSignature not verified';
  return ok(out);
}

export const codecModes = ['base64', 'base64url', 'url', 'html', 'hex', 'jwt'];
export function encodeText(mode, input) {
  switch (mode) {
    case 'base64': return base64Encode(input, false);
    case 'base64url': return base64Encode(input, true);
    case 'url': return urlEncode(input);
    case 'html': return htmlEncode(input);
    case 'hex': return hexEncode(input);
    case 'jwt': return fail('JWT can only be decoded');
    default: return fail('Unknown mode');
  }
}
export function decodeText(mode, input, now = Date.now()) {
  switch (mode) {
    case 'base64': case 'base64url': return base64Decode(input);
    case 'url': return urlDecode(input);
    case 'html': return htmlDecode(input);
    case 'hex': return hexDecode(input);
    case 'jwt': return decodeJwt(input, now);
    default: return fail('Unknown mode');
  }
}

// Detect JWT / URL-encoded / hex / base64 / HTML entities and decode. Returns { ok, value, mode }.
export function autoDecode(input, now = Date.now()) {
  const s = String(input).trim();
  if (!s) return fail('Nothing to decode');
  const tries = [];
  if (/^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]*$/.test(s)) tries.push('jwt');
  if (/%[0-9a-fA-F]{2}/.test(s)) tries.push('url');
  if (/^(0x)?[0-9a-fA-F]{2}([\s:,-]*(0x)?[0-9a-fA-F]{2})*$/.test(s)) tries.push('hex');
  if (/^[A-Za-z0-9+/_-]+={0,2}$/.test(s.replace(/\s+/g, ''))) tries.push('base64');
  if (/&(#\d+|#x[0-9a-f]+|[a-z]+);/i.test(s)) tries.push('html');
  for (const mode of tries) {
    const r = decodeText(mode, s, now);
    if (r.ok) return { ok: true, value: r.value, mode };
  }
  return fail('Could not detect an encoding');
}

// ---------- Timestamps ----------
const MAX_MS = 8.64e15;
export function parseTimestamp(input) {
  const s = String(input).trim();
  if (!s) return fail('Enter a timestamp');
  if (/^[+-]?\d+(\.\d+)?$/.test(s)) {
    const n = Number(s);
    const isMs = Math.abs(n) >= 1e11;
    const ms = isMs ? n : n * 1000;
    if (!isFinite(ms) || Math.abs(ms) > MAX_MS) return fail('Timestamp is out of range');
    return { ok: true, value: Math.round(ms), unit: isMs ? 'milliseconds' : 'seconds' };
  }
  const ms = Date.parse(s);
  if (isNaN(ms)) return fail('Not a Unix time, ISO 8601 or RFC 2822 date');
  return { ok: true, value: ms, unit: 'date' };
}

export function relativeTime(ms, now) {
  const diff = Math.round((ms - now) / 1000);
  const abs = Math.abs(diff);
  if (abs < 5) return 'just now';
  const units = [['year', 31536000], ['month', 2592000], ['day', 86400], ['hour', 3600], ['minute', 60], ['second', 1]];
  for (const [name, size] of units) {
    if (abs >= size) {
      const n = Math.floor(abs / size);
      const label = n + ' ' + name + (n === 1 ? '' : 's');
      return diff < 0 ? label + ' ago' : 'in ' + label;
    }
  }
  return 'just now';
}

const p2 = n => (n < 10 ? '0' : '') + n;
export function formatTimestamp(ms, now) {
  if (!isFinite(ms) || Math.abs(ms) > MAX_MS) return fail('Timestamp is out of range');
  const d = new Date(ms);
  const off = -d.getTimezoneOffset();
  const sign = off < 0 ? '-' : '+';
  const local = d.getFullYear() + '-' + p2(d.getMonth() + 1) + '-' + p2(d.getDate()) + ' ' + p2(d.getHours()) + ':' + p2(d.getMinutes()) + ':' + p2(d.getSeconds())
    + ' (UTC' + sign + p2(Math.floor(Math.abs(off) / 60)) + ':' + p2(Math.abs(off) % 60) + ')';
  return ok([
    { id: 'seconds', label: 'Unix seconds', value: String(Math.floor(ms / 1000)) },
    { id: 'milliseconds', label: 'Unix ms', value: String(ms) },
    { id: 'iso', label: 'ISO 8601 UTC', value: d.toISOString() },
    { id: 'local', label: 'Local', value: local },
    { id: 'relative', label: 'Relative', value: relativeTime(ms, now) },
  ]);
}

export function convertTimestamp(input, now = Date.now()) {
  const p = parseTimestamp(input);
  return p.ok ? formatTimestamp(p.value, now) : p;
}

// ---------- Colors ----------
const clamp = (v, lo, hi) => Math.min(hi, Math.max(lo, v));
const toLinear = c => (c <= 0.04045 ? c / 12.92 : Math.pow((c + 0.055) / 1.055, 2.4));
const fromLinear = c => (c <= 0.0031308 ? 12.92 * c : 1.055 * Math.pow(Math.max(c, 0), 1 / 2.4) - 0.055);

export function rgbToOklch(r, g, b) {
  const lr = toLinear(r / 255), lg = toLinear(g / 255), lb = toLinear(b / 255);
  const l = Math.cbrt(0.4122214708 * lr + 0.5363325363 * lg + 0.0514459929 * lb);
  const m = Math.cbrt(0.2119034982 * lr + 0.6806995451 * lg + 0.1073969566 * lb);
  const s = Math.cbrt(0.0883024619 * lr + 0.2817188376 * lg + 0.6299787005 * lb);
  const L = 0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s;
  const A = 1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s;
  const B = 0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s;
  const C = Math.sqrt(A * A + B * B);
  let H = C < 1e-4 ? 0 : Math.atan2(B, A) * 180 / Math.PI;
  if (H < 0) H += 360;
  return { l: L, c: C < 1e-4 ? 0 : C, h: H };
}

export function oklchToRgb(L, C, H) {
  const a = C * Math.cos(H * Math.PI / 180), b = C * Math.sin(H * Math.PI / 180);
  const l = Math.pow(L + 0.3963377774 * a + 0.2158037573 * b, 3);
  const m = Math.pow(L - 0.1055613458 * a - 0.0638541728 * b, 3);
  const s = Math.pow(L - 0.0894841775 * a - 1.2914855480 * b, 3);
  const lr = 4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s;
  const lg = -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s;
  const lb = -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s;
  return { r: fromLinear(lr) * 255, g: fromLinear(lg) * 255, b: fromLinear(lb) * 255 };
}

function hslToRgb(h, s, l) {
  h = ((h % 360) + 360) % 360;
  const f = n => { const k = (n + h / 30) % 12; return l - s * Math.min(l, 1 - l) * Math.max(-1, Math.min(k - 3, 9 - k, 1)); };
  return { r: f(0) * 255, g: f(8) * 255, b: f(4) * 255 };
}
function rgbToHsl(r, g, b) {
  r /= 255; g /= 255; b /= 255;
  const max = Math.max(r, g, b), min = Math.min(r, g, b), d = max - min;
  const l = (max + min) / 2;
  let h = 0, s = 0;
  if (d > 0) {
    s = d / (1 - Math.abs(2 * l - 1));
    if (max === r) h = ((g - b) / d) % 6; else if (max === g) h = (b - r) / d + 2; else h = (r - g) / d + 4;
    h *= 60; if (h < 0) h += 360;
  }
  return { h, s, l };
}

function num(token, percentScale) {
  const t = token.trim();
  if (/^[+-]?(\d+\.?\d*|\.\d+)(e[+-]?\d+)?%$/i.test(t)) return parseFloat(t) / 100 * percentScale;
  if (/^[+-]?(\d+\.?\d*|\.\d+)(e[+-]?\d+)?$/i.test(t)) return parseFloat(t);
  return NaN;
}
function hue(token) {
  const m = /^([+-]?(?:\d+\.?\d*|\.\d+))(deg|grad|rad|turn)?$/i.exec(token.trim());
  if (!m) return NaN;
  const v = parseFloat(m[1]);
  switch ((m[2] || 'deg').toLowerCase()) {
    case 'grad': return v * 0.9;
    case 'rad': return v * 180 / Math.PI;
    case 'turn': return v * 360;
    default: return v;
  }
}

// Returns { ok, value: { r, g, b, a } } with r,g,b in 0..255 (unclamped for out-of-gamut oklch), a in 0..1.
export function parseColor(input) {
  const s = String(input).trim().toLowerCase();
  if (!s) return fail('Enter a color');
  let m = /^#?([0-9a-f]{3,4}|[0-9a-f]{6}|[0-9a-f]{8})$/.exec(s);
  if (m && (s[0] === '#' || /^[0-9a-f]{6}([0-9a-f]{2})?$/.test(s))) {
    let h = m[1];
    if (h.length <= 4) h = h.split('').map(c => c + c).join('');
    return ok({ r: parseInt(h.substr(0, 2), 16), g: parseInt(h.substr(2, 2), 16), b: parseInt(h.substr(4, 2), 16), a: h.length === 8 ? parseInt(h.substr(6, 2), 16) / 255 : 1 });
  }
  m = /^(rgba?|hsla?|oklch)\(\s*([^)]*)\)$/.exec(s);
  if (!m) return fail('Not a hex, rgb(), hsl() or oklch() color');
  const fn = m[1];
  let alpha = 1;
  const slash = m[2].trim().split('/');
  if (slash.length > 2) return fail('Invalid color syntax');
  let args = slash[0].trim().split(/[\s,]+/).filter(Boolean);
  if (slash.length === 2) {
    const a = num(slash[1], 1);
    if (isNaN(a)) return fail('Invalid alpha');
    alpha = clamp(a, 0, 1);
  } else if (args.length === 4) {
    const a = num(args.pop(), 1);
    if (isNaN(a)) return fail('Invalid alpha');
    alpha = clamp(a, 0, 1);
  }
  if (args.length !== 3) return fail('Expected three color components');
  if (fn === 'rgb' || fn === 'rgba') {
    const v = args.map(t => num(t, 255));
    if (v.some(isNaN)) return fail('Invalid rgb() value');
    return ok({ r: clamp(v[0], 0, 255), g: clamp(v[1], 0, 255), b: clamp(v[2], 0, 255), a: alpha });
  }
  if (fn === 'hsl' || fn === 'hsla') {
    const h = hue(args[0]), sat = num(args[1], 1), lig = num(args[2], 1);
    if (isNaN(h) || isNaN(sat) || isNaN(lig)) return fail('Invalid hsl() value');
    const sv = args[1].indexOf('%') < 0 && sat > 1 ? sat / 100 : sat;
    const lv = args[2].indexOf('%') < 0 && lig > 1 ? lig / 100 : lig;
    return ok(Object.assign(hslToRgb(h, clamp(sv, 0, 1), clamp(lv, 0, 1)), { a: alpha }));
  }
  const L = num(args[0], 1), C = num(args[1], 0.4), H = hue(args[2]);
  if (isNaN(L) || isNaN(C) || isNaN(H)) return fail('Invalid oklch() value');
  return ok(Object.assign(oklchToRgb(clamp(L, 0, 1), Math.max(0, C), H), { a: alpha }));
}

const trim = (n, d) => String(parseFloat(n.toFixed(d)));
const byte = v => clamp(Math.round(v), 0, 255);
// Output channels are clamped to the sRGB gamut.
export function formatColor(c) {
  const r = byte(c.r), g = byte(c.g), b = byte(c.b), a = clamp(c.a === undefined ? 1 : c.a, 0, 1);
  const hx = n => (n < 16 ? '0' : '') + n.toString(16);
  const hex = '#' + hx(r) + hx(g) + hx(b) + (a < 1 ? hx(Math.round(a * 255)) : '');
  const al = trim(a, 3);
  const hsl = rgbToHsl(r, g, b);
  const lch = rgbToOklch(r, g, b);
  const pct = v => trim(v * 100, 1) + '%';
  return {
    hex,
    rgb: a < 1 ? 'rgba(' + r + ', ' + g + ', ' + b + ', ' + al + ')' : 'rgb(' + r + ', ' + g + ', ' + b + ')',
    hsl: (a < 1 ? 'hsla(' : 'hsl(') + trim(hsl.h, 1) + ', ' + pct(hsl.s) + ', ' + pct(hsl.l) + (a < 1 ? ', ' + al : '') + ')',
    oklch: 'oklch(' + pct(lch.l) + ' ' + trim(lch.c, 4) + ' ' + trim(lch.h, 2) + (a < 1 ? ' / ' + al : '') + ')',
    css: a < 1 ? 'rgba(' + r + ', ' + g + ', ' + b + ', ' + al + ')' : hex,
  };
}

export function convertColor(input) {
  const p = parseColor(input);
  return p.ok ? ok(formatColor(p.value)) : p;
}

// ---------- Text case ----------
const isDigit = c => c >= '0' && c <= '9';
const isLower = c => c !== c.toUpperCase() && c === c.toLowerCase();
const isUpper = c => c !== c.toLowerCase() && c === c.toUpperCase();
function isWordChar(c) {
  if (isDigit(c)) return true;
  const code = c.charCodeAt(0);
  if (code < 128) return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z');
  if (code < 0xC0 || code === 0xD7 || code === 0xF7) return false;
  if (code >= 0xD800 && code <= 0xDFFF) return false;
  if ((code >= 0x2000 && code <= 0x2BFF) || (code >= 0x3000 && code <= 0x303F) || (code >= 0xFE00 && code <= 0xFE0F)) return false;
  return true;
}
const isApostrophe = c => c === "'" || c === '’';

// Split into words: handles camelCase, PascalCase, HTMLParser, snake_case, kebab-case, spaces and Unicode letters.
export function splitWords(text) {
  const chars = Array.from(String(text));
  const words = [];
  let cur = '';
  const flush = () => { if (cur) words.push(cur); cur = ''; };
  for (let i = 0; i < chars.length; i++) {
    const c = chars[i];
    if (isApostrophe(c) && cur && i + 1 < chars.length && isWordChar(chars[i + 1]) && !isDigit(chars[i - 1])) { cur += c; continue; }
    if (!isWordChar(c)) { flush(); continue; }
    if (cur) {
      const prev = cur[cur.length - 1];
      const next = chars[i + 1];
      if (isUpper(c) && (isLower(prev) || isDigit(prev))) flush();
      else if (isUpper(c) && isUpper(prev) && next !== undefined && isLower(next)) flush();
    }
    cur += c;
  }
  flush();
  return words;
}

const bare = w => w.replace(/['’]/g, '');
const cap = w => { const a = Array.from(w); return a.length ? a[0].toUpperCase() + a.slice(1).join('').toLowerCase() : w; };

const latinMap = {};
[['àáâãäåāăą', 'a'], ['çćĉċč', 'c'], ['ďđð', 'd'], ['èéêëēĕėęě', 'e'], ['ĝğġģ', 'g'], ['ĥħ', 'h'], ['ìíîïĩīĭįı', 'i'], ['ĵ', 'j'], ['ķ', 'k'],
  ['ĺļľŀł', 'l'], ['ñńņňŉ', 'n'], ['òóôõöøōŏő', 'o'], ['ŕŗř', 'r'], ['śŝşš', 's'], ['ţťŧ', 't'], ['ùúûüũūŭůűų', 'u'], ['ŵ', 'w'], ['ýÿŷ', 'y'], ['źżž', 'z'],
  ['ß', 'ss'], ['æ', 'ae'], ['œ', 'oe'], ['þ', 'th']].forEach(pair => { for (const ch of pair[0]) latinMap[ch] = pair[1]; });

const cyr = { 'а': 'a', 'б': 'b', 'в': 'v', 'г': 'h', 'ґ': 'g', 'д': 'd', 'е': 'e', 'ж': 'zh', 'з': 'z', 'и': 'y', 'і': 'i', 'к': 'k', 'л': 'l', 'м': 'm', 'н': 'n', 'о': 'o', 'п': 'p', 'р': 'r', 'с': 's', 'т': 't', 'у': 'u', 'ф': 'f', 'х': 'kh', 'ц': 'ts', 'ч': 'ch', 'ш': 'sh', 'щ': 'shch', 'ь': '',
  'ы': 'y', 'э': 'e', 'ё': 'e', 'ъ': '' };
const cyrInitial = { 'є': 'ye', 'ї': 'yi', 'й': 'y', 'ю': 'yu', 'я': 'ya' };
const cyrMedial = { 'є': 'ie', 'ї': 'i', 'й': 'i', 'ю': 'iu', 'я': 'ia' };
const has = (o, k) => Object.prototype.hasOwnProperty.call(o, k);

// Lowercases and transliterates Latin diacritics and Ukrainian Cyrillic (2010 national system) to ASCII.
export function transliterate(text) {
  const chars = Array.from(String(text).toLowerCase());
  let out = '';
  for (let i = 0; i < chars.length; i++) {
    const c = chars[i];
    const prev = chars[i - 1];
    const initial = prev === undefined || !(isWordChar(prev) || isApostrophe(prev));
    if (c === 'г' && prev === 'з') out += 'gh';
    else if (has(cyrInitial, c)) out += initial ? cyrInitial[c] : cyrMedial[c];
    else if (has(cyr, c)) out += cyr[c];
    else if (c === 'ʼ') out += '';
    else if (has(latinMap, c)) out += latinMap[c];
    else out += c;
  }
  return out;
}

export const caseModes = ['lower', 'upper', 'title', 'sentence', 'camel', 'pascal', 'snake', 'kebab', 'constant', 'slug'];

function perLine(text, fn) { return text.split('\n').map(fn).join('\n'); }

export function convertCase(mode, input) {
  const text = String(input);
  switch (mode) {
    case 'lower': return ok(text.toLowerCase());
    case 'upper': return ok(text.toUpperCase());
    case 'title': {
      let out = '', start = true;
      for (const c of text.toLowerCase()) {
        if (isWordChar(c)) { out += start ? c.toUpperCase() : c; start = false; }
        else { out += c; if (!isApostrophe(c)) start = true; }
      }
      return ok(out);
    }
    case 'sentence': {
      let out = '', start = true;
      for (const c of text.toLowerCase()) {
        if (start && isWordChar(c)) { out += c.toUpperCase(); start = false; continue; }
        out += c;
        if (c === '.' || c === '!' || c === '?' || c === '\n') start = true;
        else if (isWordChar(c)) start = false;
      }
      return ok(out);
    }
    case 'camel': return ok(perLine(text, l => splitWords(l).map((w, i) => (i ? cap(bare(w)) : bare(w).toLowerCase())).join('')));
    case 'pascal': return ok(perLine(text, l => splitWords(l).map(w => cap(bare(w))).join('')));
    case 'snake': return ok(perLine(text, l => splitWords(l).map(w => bare(w).toLowerCase()).join('_')));
    case 'kebab': return ok(perLine(text, l => splitWords(l).map(w => bare(w).toLowerCase()).join('-')));
    case 'constant': return ok(perLine(text, l => splitWords(l).map(w => bare(w).toUpperCase()).join('_')));
    case 'slug': return ok(splitWords(text).map(w => transliterate(w).replace(/[^a-z0-9]+/g, '')).filter(Boolean).join('-'));
    default: return fail('Unknown case');
  }
}

export function utf8Size(text) { return utf8Encode(text).length; }

export function textStats(input) {
  const text = String(input);
  let characters = 0;
  for (const c of text) characters++;
  const trimmed = text.trim();
  return {
    characters,
    words: trimmed ? trimmed.split(/\s+/).length : 0,
    lines: text === '' ? 0 : text.split('\n').length,
    bytes: utf8Size(text),
  };
}
