const offsetsMap = new Map();
const defaultLyricOffsetMs = 500;

function timestampSeconds(minutes, seconds, fraction) {
  return Math.round((Number(minutes) * 60 + Number(seconds) + Number(`0.${fraction || '0'}`)) * 1000) / 1000;
}

function normalizeTimestamp(seconds) {
  return Math.max(0, Math.round(seconds * 1000) / 1000);
}

function lrcOffsetSeconds(text) {
  const match = /\[offset:([+-]?\d+)\]/i.exec(text);
  if (!match) return 0;
  const milliseconds = Number(match[1]);
  return Number.isFinite(milliseconds) ? milliseconds / 1000 : 0;
}

function parseWordMarks(text, lineAt, offset) {
  const source = text.replace(/\[[^\]]*\]/g, '');
  const marks = [];
  const pattern = /<(\d{1,3}):([0-5]\d)(?:[.:](\d{1,3}))?>/g;
  let match;
  while ((match = pattern.exec(source)) !== null) {
    marks.push({ index: match.index, end: pattern.lastIndex, at: timestampSeconds(match[1], match[2], match[3]) + offset });
  }
  if (marks.length === 0) return { text: source.trim(), words: undefined };

  let lineText = '';
  const words = [];
  let cursor = 0;
  for (let index = 0; index < marks.length; index++) {
    const mark = marks[index];
    const next = marks[index + 1];
    const before = index === 0 ? source.slice(cursor, mark.index) : '';
    const value = source.slice(mark.end, next ? next.index : source.length);
    if (before) {
      lineText += before;
      const leading = before.trim();
      if (leading) words.push({ at: lineAt, text: leading });
    }
    lineText += value;
    const word = value.trim();
    if (word) words.push({ at: mark.at, text: word });
    cursor = next ? next.index : source.length;
  }
  lineText = lineText.trim();
  return { text: lineText, words: words.length ? words : undefined };
}

export function parseLrc(text) {
  if (typeof text !== 'string' || text.length === 0) return [];
  const offset = lrcOffsetSeconds(text);
  const parsed = [];
  let order = 0;
  for (const raw of text.split(/\r?\n/)) {
    const stamps = [];
    const pattern = /\[(\d{1,3}):([0-5]\d)(?:[.:](\d{1,3}))?\]/g;
    let match;
    while ((match = pattern.exec(raw)) !== null) {
      stamps.push({ rawAt: timestampSeconds(match[1], match[2], match[3]) + offset });
    }
    if (!stamps.length) continue;

    const content = raw.replace(/\[(\d{1,3}):([0-5]\d)(?:[.:](\d{1,3}))?\]/g, '');
    const firstAt = stamps[0].rawAt;
    const lyric = parseWordMarks(content, firstAt, offset);
    for (const stamp of stamps) {
      const words = lyric.words ? lyric.words.map(function(word) {
        const shifted = stamp.rawAt === firstAt ? word.at : word.at + stamp.rawAt - firstAt;
        return { at: normalizeTimestamp(shifted), text: word.text };
      }) : undefined;
      const line = { at: normalizeTimestamp(stamp.rawAt), text: lyric.text };
      if (words) line.words = words;
      parsed.push({ line, order: order++ });
    }
  }

  parsed.sort(function(a, b) { return a.line.at - b.line.at || a.order - b.order; });
  const merged = [];
  for (const entry of parsed) {
    const line = entry.line;
    const previous = merged.length ? merged[merged.length - 1] : null;
    if (previous && Math.abs(previous.at - line.at) < 0.001) {
      if (line.text) previous.text = previous.text ? `${previous.text}\n${line.text}` : line.text;
      if (line.words) {
        if (!previous.words) previous.words = [];
        for (const word of line.words) previous.words.push(word);
      }
    } else {
      merged.push(line);
    }
  }
  return merged;
}

export function activeLyric(lines, seconds) {
  let low = 0;
  let high = lines.length;
  while (low < high) {
    const mid = (low + high) >>> 1;
    if (lines[mid].at <= seconds) low = mid + 1;
    else high = mid;
  }
  return low - 1;
}

export function lyricSpanAt(lines, index, totalDurationSeconds) {
  if (index < 0 || index >= lines.length) return { start: 0, span: 0 };
  const gaps = [];
  for (let i = 0; i + 1 < lines.length; i++) {
    const gap = lines[i + 1].at - lines[i].at;
    if (gap > 0) gaps.push(gap);
  }
  gaps.sort(function(a, b) { return a - b; });
  const typical = gaps.length === 0 ? 4 : gaps[Math.floor((gaps.length - 1) / 2)];
  const start = lines[index].at;
  const gap = index + 1 < lines.length ? lines[index + 1].at - start : 0;
  const span = gap > 0 && gap <= typical * 4
    ? gap
    : totalDurationSeconds && totalDurationSeconds > start
      ? Math.min(typical, totalDurationSeconds - start)
      : typical;
  return { start, span: Math.max(0.1, span) };
}

export function lyricProgress(lines, seconds, offsetMs) {
  if (!lines.length) return -1;
  const effective = seconds + (offsetMs || 0) / 1000;
  const index = activeLyric(lines, effective);
  if (index < 0) return -1;
  const span = lyricSpanAt(lines, index);
  if (span.span <= 0) return -1;
  if (effective < span.start) return 0;
  return Math.max(0, Math.min(1, (effective - span.start) / span.span));
}

export function lyricGapSeconds(lines, seconds, offsetMs) {
  if (!lines.length) return 0;
  const effective = seconds + (offsetMs || 0) / 1000;
  if (effective < lines[0].at) return Math.ceil(lines[0].at - effective);
  const index = activeLyric(lines, effective);
  if (index < 0 || index >= lines.length - 1) return 0;
  const span = lyricSpanAt(lines, index);
  if (effective < span.start + span.span) return 0;
  const remaining = lines[index + 1].at - effective;
  return remaining > 0 ? Math.ceil(remaining) : 0;
}

export function previewLyric(lines, seconds, offsetMs) {
  if (!lines.length) return '';
  const effective = seconds + (offsetMs || 0) / 1000;
  const index = activeLyric(lines, effective);
  if (index < 0) return '';
  const span = lyricSpanAt(lines, index);
  return effective >= span.start && effective < span.start + span.span ? lines[index].text : '';
}

export function activeLyricWord(line, seconds, offsetMs) {
  const words = line && Array.isArray(line.words) ? line.words : [];
  const effective = seconds + (offsetMs || 0) / 1000;
  let low = 0;
  let high = words.length;
  while (low < high) {
    const mid = (low + high) >>> 1;
    if (words[mid].at <= effective) low = mid + 1;
    else high = mid;
  }
  return low - 1;
}

export function lyricWordSpanAt(line, index) {
  const words = line && Array.isArray(line.words) ? line.words : [];
  if (index < 0 || index + 1 >= words.length) return { start: 0, span: 0 };
  return { start: words[index].at, span: Math.max(0, words[index + 1].at - words[index].at) };
}

export function lyricWordProgress(line, index, seconds, offsetMs) {
  const span = lyricWordSpanAt(line, index);
  if (span.span <= 0) return -1;
  const effective = seconds + (offsetMs || 0) / 1000;
  return Math.max(0, Math.min(1, (effective - span.start) / span.span));
}

export function canLookupLyrics(player) {
  if (!player || typeof player.title !== 'string' || typeof player.artist !== 'string'
      || !player.title.trim() || !player.artist.trim()) return false;
  const telegram = /telegram/i.test(`${player.id || ''} ${player.name || ''}`);
  const messageTitle = /(?:\b\d{1,2}:\d{2}\b|voice message|голосов[еє] повідомлення|голосовое сообщение)/i.test(player.title);
  return !(telegram && !(typeof player.album === 'string' && player.album.trim()) && messageTitle);
}

export function lyricsKey(player) {
  const sourceKey = typeof player.sourceKey === 'string' && player.sourceKey
    ? player.sourceKey : (player.id || '');
  const duration = typeof player.lengthSeconds === 'number'
    ? Math.round(player.lengthSeconds)
    : Math.round((player.lengthMicros || 0) / 1000000);
  return JSON.stringify([
    sourceKey,
    player.trackId || '',
    player.title || '',
    player.artist || '',
    player.album || '',
    duration,
  ]);
}

function normalizeLyricsIdentity(value) {
  return typeof value === 'string'
    ? value.normalize('NFKC').trim().toLocaleLowerCase().replace(/\s+/g, ' ')
    : '';
}

export function lyricsCacheKey(track) {
  if (!track || typeof track !== 'object') return '';
  const duration = typeof track.lengthSeconds === 'number'
    ? track.lengthSeconds
    : typeof track.lengthMicros === 'number' ? track.lengthMicros / 1000000 : 0;
  return JSON.stringify([
    normalizeLyricsIdentity(track.title),
    normalizeLyricsIdentity(track.artist),
    normalizeLyricsIdentity(track.album),
    Math.round(duration || 0),
  ]);
}

export function retryAfterDelay(headers, now = Date.now()) {
  if (typeof headers !== 'string' || !headers) return null;
  const blocks = headers.split(/\r?\n\r?\n/).filter((block) => /^HTTP\/\S+\s+\d{3}/i.test(block.trim()));
  if (!blocks.length) return null;
  const final = blocks[blocks.length - 1];
  const match = /^\s*retry-after\s*:\s*(.*?)\s*$/im.exec(final);
  if (!match) return null;
  if (/^\d+$/.test(match[1])) {
    const seconds = Number(match[1]);
    const milliseconds = seconds * 1000;
    return Number.isFinite(milliseconds) ? Math.max(0, milliseconds) : null;
  }
  if (!/^[A-Za-z]{3,9}(?:,| )/.test(match[1])) return null;
  const at = Date.parse(match[1]);
  const delay = at - now;
  return Number.isFinite(delay) ? Math.max(0, delay) : null;
}

export function lyricsBackoffDelay(failures) {
  const exponent = Math.max(0, Math.min(5, Math.floor(Number(failures) || 0)));
  return Math.min(600000, 30000 * (2 ** exponent));
}

export function validateLyricsCacheEntry(entry, now = Date.now()) {
  if (!entry || typeof entry !== 'object' || !Number.isFinite(entry.savedAt)
      || !entry.value || typeof entry.value !== 'object') return null;
  const ttl = entry.negative ? 3600000 : 30 * 24 * 3600000;
  if (entry.savedAt < 0 || entry.savedAt > now || now - entry.savedAt >= ttl) return null;
  const value = entry.value;
  if (!Array.isArray(value.lines) || typeof value.plain !== 'string' || typeof value.instrumental !== 'boolean') return null;
  const empty = !value.instrumental && value.lines.length === 0 && !value.plain.trim();
  if ((entry.negative === true) !== empty) return null;
  if (value.lines.length > 20000 || value.plain.length > 1048576) return null;
  for (const line of value.lines) {
    if (!line || !Number.isFinite(line.at) || line.at < 0 || typeof line.text !== 'string' || line.text.length > 20000) return null;
    if (line.words !== undefined && (!Array.isArray(line.words) || line.words.length > 1000
        || line.words.some((word) => !word || !Number.isFinite(word.at) || word.at < 0 || typeof word.text !== 'string'))) return null;
  }
  return { savedAt: entry.savedAt, negative: entry.negative === true, value };
}

export function getLyricOffset(trackKey) {
  if (!trackKey) return 0;
  return offsetsMap.has(trackKey) ? offsetsMap.get(trackKey) : defaultLyricOffsetMs;
}

export function setLyricOffset(trackKey, offsetMs) {
  if (!trackKey) return 0;
  const value = Number.isFinite(Number(offsetMs)) ? Math.round(Number(offsetMs)) : 0;
  const clamped = Math.max(-10000, Math.min(10000, value));
  offsetsMap.set(trackKey, clamped);
  return clamped;
}

export function decodeLyrics(value) {
  if (!value || typeof value !== 'object') throw new Error('Invalid lyrics response');
  return {
    lines: parseLrc(typeof value.syncedLyrics === 'string' ? value.syncedLyrics : ''),
    plain: typeof value.plainLyrics === 'string' ? value.plainLyrics : '',
    instrumental: value.instrumental === true,
  };
}

export function lyricsPresentation(state) {
  if (!state || state.kind === 'starting') return 'loading';
  if (state.kind === 'error') return 'error';
  if (state.kind !== 'ready') return 'missing';
  const value = state.value || {};
  if (value.instrumental) return 'instrumental';
  if (Array.isArray(value.lines) && value.lines.length) return 'synced';
  if (typeof value.plain === 'string' && value.plain.trim()) return 'plain';
  return 'missing';
}

export function matchLyricsRecord(records, track) {
  if (!Array.isArray(records)) return null;
  const durationSeconds = typeof track.lengthSeconds === 'number'
    ? track.lengthSeconds
    : typeof track.lengthMicros === 'number' ? track.lengthMicros / 1000000 : 0;
  function normalize(value) {
    return typeof value === 'string' ? value.normalize('NFKC').trim().toLowerCase().replace(/\s+/g, ' ') : '';
  }
  const matches = records.filter(function(record) {
    if (!record || typeof record !== 'object') return false;
    const durationMatches = !durationSeconds
      || (typeof record.duration === 'number'
        && Math.abs(record.duration - durationSeconds) <= 2);
    return normalize(record.trackName) === normalize(track.title)
      && normalize(record.artistName) === normalize(track.artist)
      && durationMatches;
  });
  if (track.album) {
    for (const record of matches) {
      if (normalize(record.albumName) === normalize(track.album)) return record;
    }
  }
  if (!durationSeconds && matches.length !== 1) return null;
  for (const record of matches) {
    if (typeof record.syncedLyrics === 'string' && record.syncedLyrics.length > 0) return record;
  }
  return matches.length ? matches[0] : null;
}
