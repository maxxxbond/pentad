import test from 'node:test';
import assert from 'node:assert/strict';
import {
  activeLyric, activeLyricWord, canLookupLyrics, decodeLyrics, getLyricOffset,
  lyricsKey, lyricsCacheKey, retryAfterDelay, lyricsBackoffDelay, validateLyricsCacheEntry,
  lyricsPresentation, lyricGapSeconds, lyricProgress, lyricSpanAt, lyricWordProgress,
  lyricWordSpanAt, matchLyricsRecord, parseLrc, previewLyric, setLyricOffset,
} from '../../quickshell/logic/lyrics.mjs';

function changed(value, updates) {
  return Object.assign({}, value, updates);
}

test('legacy LRC vectors sort, expand repeated line stamps, and apply signed millisecond offsets', () => {
  const lines = parseLrc('[offset:-500]\n[00:03.50][01:02.005]Повтор\n[00:01.2]Початок\n[ar:Artist]');
  assert.deepEqual(lines, [
    { at: 0.7, text: 'Початок' },
    { at: 3, text: 'Повтор' },
    { at: 61.505, text: 'Повтор' },
  ]);
});

test('lyrics presentation keeps loading, failures, plain text, and empty results distinct', () => {
  assert.equal(lyricsPresentation({ kind: 'starting' }), 'loading');
  assert.equal(lyricsPresentation({ kind: 'error', reason: 'timeout' }), 'error');
  assert.equal(lyricsPresentation({ kind: 'unavailable', reason: 'rate-limited' }), 'missing');
  assert.equal(lyricsPresentation({ kind: 'ready', value: { lines: [], plain: 'Words', instrumental: false } }), 'plain');
  assert.equal(lyricsPresentation({ kind: 'ready', value: { lines: [], plain: '  \n ', instrumental: false } }), 'missing');
  assert.equal(lyricsPresentation({ kind: 'ready', value: { lines: [{ at: 0, text: 'Words' }], plain: '', instrumental: false } }), 'synced');
  assert.equal(lyricsPresentation({ kind: 'ready', value: { lines: [], plain: '', instrumental: true } }), 'instrumental');
  assert.equal(lyricsPresentation({ kind: 'ready', value: { lines: [{ at: 0, text: 'Ignored' }], plain: '', instrumental: true } }), 'instrumental');
  assert.equal(lyricsPresentation({ kind: 'ready', value: { lines: [], plain: '', instrumental: false } }), 'missing');
  const recovery = [
    lyricsPresentation({ kind: 'starting' }),
    lyricsPresentation({ kind: 'error', reason: 'timeout' }),
    lyricsPresentation({ kind: 'ready', value: { lines: [], plain: 'Recovered', instrumental: false } }),
  ];
  assert.deepEqual(recovery, ['loading', 'error', 'plain']);
});

test('parses CRLF, period and colon fractions with legacy decimal semantics', () => {
  assert.deepEqual(parseLrc('[offset:+125]\r\n[00:01.2]dot\r\n[00:02:03]colon\r\n[123:59.999]long'), [
    { at: 1.325, text: 'dot' },
    { at: 2.155, text: 'colon' },
    { at: 7440.124, text: 'long' },
  ]);
});

test('clamps negative normalized line and enhanced-word timestamps at zero', () => {
  assert.deepEqual(parseLrc('[offset:-5000]\n[00:02.000]<00:01.000>early <00:03.000>later'), [
    { at: 0, text: 'early later', words: [{ at: 0, text: 'early' }, { at: 0, text: 'later' }] },
  ]);
});

test('normalizes repeated enhanced lines before clamping timestamps at zero', () => {
  assert.deepEqual(parseLrc('[offset:-10000]\n[00:01][00:11]<00:01.5>early <00:02>later'), [
    { at: 0, text: 'early later', words: [{ at: 0, text: 'early' }, { at: 0, text: 'later' }] },
    { at: 1, text: 'early later', words: [{ at: 1.5, text: 'early' }, { at: 2, text: 'later' }] },
  ]);
});

test('merges duplicate timestamps in stable source order and combines enhanced words', () => {
  assert.deepEqual(parseLrc('[00:05.00]<00:05.10>Hello <00:05.50>world\n[00:05.00]Привіт світе\n[00:10.00]Next'), [
    { at: 5, text: 'Hello world\nПривіт світе', words: [{ at: 5.1, text: 'Hello' }, { at: 5.5, text: 'world' }] },
    { at: 10, text: 'Next' },
  ]);
});

test('enhanced LRC keeps leading unmarked text at line time and word starts exact', () => {
  const line = parseLrc('[00:10.00]Intro <00:10.40>sing <00:11.25>along')[0];
  assert.deepEqual(line, {
    at: 10,
    text: 'Intro sing along',
    words: [
      { at: 10, text: 'Intro' },
      { at: 10.4, text: 'sing' },
      { at: 11.25, text: 'along' },
    ],
  });
  assert.equal(activeLyricWord(line, 9.999), -1);
  assert.equal(activeLyricWord(line, 10), 0);
  assert.equal(activeLyricWord(line, 10.4), 1);
  assert.equal(activeLyricWord(line, 11.25), 2);
  const wordSpan = lyricWordSpanAt(line, 1);
  assert.equal(wordSpan.start, 10.4);
  assert.ok(Math.abs(wordSpan.span - 0.85) < 1e-9);
  assert.ok(Math.abs(lyricWordProgress(line, 1, 10.825) - 0.5) < 1e-9);
  assert.deepEqual(lyricWordSpanAt(line, 2), { start: 0, span: 0 });
  assert.equal(lyricWordProgress(line, 2, 11.5), -1);
});

test('ignores malformed line timestamps and does not fabricate word timing', () => {
  assert.deepEqual(parseLrc('[00:99]bad\nplain text\n[00:01.000]untimed legacy text'), [
    { at: 1, text: 'untimed legacy text' },
  ]);
  assert.deepEqual(parseLrc('[00:01.000]plain <00:99.000>marker')[0], {
    at: 1, text: 'plain <00:99.000>marker',
  });
});

test('active line selection handles intro, exact boundaries, duplicate lines, and backward seeks', () => {
  const lines = parseLrc('[00:02.00]One\n[00:04.00]\n[00:08.00]Two');
  assert.equal(activeLyric(lines, 0), -1);
  assert.equal(activeLyric(lines, 8), 2);
  assert.equal(activeLyric(lines, 4), 1);
  assert.equal(activeLyric(lines, 3), 0);
  assert.equal(activeLyric(lines, 9), 2);
  assert.equal(activeLyric(lines, 1), -1);
  assert.equal(activeLyric([], 100), -1);
});

test('malformed service data, plain lyrics, and instrumental responses are preserved', () => {
  assert.deepEqual(decodeLyrics({ plainLyrics: 'Text', syncedLyrics: null }), {
    lines: [], plain: 'Text', instrumental: false,
  });
  assert.deepEqual(decodeLyrics({ syncedLyrics: '[00:01.0]Line', instrumental: true }), {
    lines: [{ at: 1, text: 'Line' }], plain: '', instrumental: true,
  });
  assert.throws(() => decodeLyrics(null), /Invalid lyrics response/);
  assert.throws(() => decodeLyrics('invalid'), /Invalid lyrics response/);
});

test('uses the legacy lower median gap, long-solo fallback, and final-line span', () => {
  const lines = parseLrc('[00:02.00]One\n[00:05.00]Two\n[00:08.00]Three\n[01:00.00]Four');
  assert.deepEqual(lyricSpanAt(lines, 0), { start: 2, span: 3 });
  assert.deepEqual(lyricSpanAt(lines, 1), { start: 5, span: 3 });
  assert.deepEqual(lyricSpanAt(lines, 2), { start: 8, span: 3 });
  assert.deepEqual(lyricSpanAt(lines, 3), { start: 60, span: 3 });
  assert.deepEqual(lyricSpanAt([], 0), { start: 0, span: 0 });
});

test('limits the final line span to remaining track duration when available', () => {
  const lines = parseLrc('[00:02.00]One\n[00:06.00]Two');
  assert.deepEqual(lyricSpanAt(lines, 1, 7), { start: 6, span: 1 });
  assert.deepEqual(lyricSpanAt(lines, 1, 6.05), { start: 6, span: 0.1 });
});

test('progress and preview honor offsets and recompute correctly after backward seeks', () => {
  const lines = parseLrc('[00:02.00]One\n[00:06.00]Two');
  assert.equal(lyricProgress(lines, 0), -1);
  assert.equal(lyricProgress(lines, 2), 0);
  assert.equal(lyricProgress(lines, 4), 0.5);
  assert.equal(lyricProgress(lines, 6), 0);
  assert.equal(lyricProgress(lines, 1.5, 500), 0);
  assert.equal(previewLyric(lines, 1), '');
  assert.equal(previewLyric(lines, 3), 'One');
  assert.equal(previewLyric(lines, 7), 'Two');
  assert.equal(previewLyric(lines, 4), 'One');
  assert.equal(previewLyric(lines, 20), '');
});

test('counts intro and instrumental gaps with ceiling semantics', () => {
  const lines = parseLrc('[00:02.00]Intro\n[00:06.00]First\n[00:10.00]Second\n[00:30.00]After solo');
  assert.equal(lyricGapSeconds(lines, 0), 2);
  assert.equal(lyricGapSeconds(lines, 1), 1);
  assert.equal(lyricGapSeconds(lines, 6), 0);
  assert.equal(lyricGapSeconds(lines, 20), 10);
  assert.equal(lyricGapSeconds([], 20), 0);
});

test('offsets default per key, clamp and round, and reject an empty key', () => {
  const key = 'lyrics-offset-vector';
  assert.equal(getLyricOffset(key), 500);
  assert.equal(getLyricOffset(''), 0);
  assert.equal(setLyricOffset(key, 15000), 10000);
  assert.equal(getLyricOffset(key), 10000);
  assert.equal(setLyricOffset(key, -20000), -10000);
  assert.equal(setLyricOffset(key, 125.4), 125);
  assert.equal(setLyricOffset('', 700), 0);
});

test('offset compensation remains deterministic at lyric boundaries', () => {
  const lines = parseLrc('[00:02.00]One\n[00:06.00]Two');
  const offset = getLyricOffset('lyrics-lag-vector');
  assert.equal(activeLyric(lines, 1.499 + offset / 1000), -1);
  assert.equal(activeLyric(lines, 1.5 + offset / 1000), 0);
  assert.equal(lyricProgress(lines, 3.5, offset), 0.5);
  assert.equal(lyricGapSeconds(lines, 0.5, offset), 1);
});

test('Telegram voice metadata is filtered only when album metadata is absent', () => {
  const telegram = { id: 'org.mpris.MediaPlayer2.TelegramDesktop', name: 'TelegramDesktop', title: 'today at 18:46', artist: 'Sender' };
  assert.equal(canLookupLyrics(telegram), false);
  assert.equal(canLookupLyrics(changed(telegram, { title: 'Голосове повідомлення' })), false);
  assert.equal(canLookupLyrics(changed(telegram, { title: 'Song' })), true);
  assert.equal(canLookupLyrics(changed(telegram, { title: '18:46', album: 'Album' })), true);
  assert.equal(canLookupLyrics({ id: 'spotify', name: 'Spotify', title: '18:46', artist: 'Artist' }), true);
  assert.equal(canLookupLyrics({ title: '  ', artist: 'Artist' }), false);
});

test('lyrics keys invalidate on source and track changes while normalizing duration', () => {
  const player = { id: 'player-a', trackId: '/track/1', title: 'Song', artist: 'Artist', album: 'Album', lengthMicros: 180500000 };
  const key = lyricsKey(player);
  assert.equal(key, JSON.stringify(['player-a', '/track/1', 'Song', 'Artist', 'Album', 181]));
  assert.notEqual(key, lyricsKey(changed(player, { id: 'player-b' })));
  assert.notEqual(key, lyricsKey(changed(player, { trackId: '/track/2' })));
  assert.notEqual(key, lyricsKey(changed(player, { title: 'Other' })));
  assert.equal(lyricsKey(changed(player, { lengthSeconds: 181 })), key);
  assert.equal(lyricsKey(changed(player, { sourceKey: 'preferred-source' })).startsWith('["preferred-source"'), true);
  setLyricOffset(key, 1250);
  assert.equal(getLyricOffset(key), 1250);
  assert.equal(getLyricOffset(lyricsKey(changed(player, { id: 'player-b' }))), 500);
});

test('search matching requires exact normalized recording and applies album/duration preference', () => {
  const records = [
    { trackName: 'Song', artistName: 'Artist', albumName: 'Live', duration: 250, syncedLyrics: 'live' },
    { trackName: 'Other', artistName: 'Artist', duration: 180, syncedLyrics: 'other' },
    { trackName: 'Ｓｏｎｇ', artistName: ' Artist ', albumName: 'Studio', duration: 181, syncedLyrics: 'studio' },
    { trackName: 'Song', artistName: 'Artist', albumName: 'Studio', duration: 180, plainLyrics: 'plain' },
  ];
  assert.equal(matchLyricsRecord(records, { title: 'Song', artist: 'Artist', lengthMicros: 180000000 }), records[2]);
  assert.equal(matchLyricsRecord(records, { title: 'Song', artist: 'Artist', lengthSeconds: 180 }), records[2]);
  assert.equal(matchLyricsRecord(records, { title: 'Song', artist: 'Artist', album: 'Studio', lengthMicros: 180000000 }), records[2]);
  assert.equal(matchLyricsRecord(records, { title: 'Song', artist: 'Artist' }), null);
  const plainOnly = { trackName: 'Song', artistName: 'Artist', duration: 180 };
  assert.equal(matchLyricsRecord([plainOnly], { title: 'Song', artist: 'Artist', lengthMicros: 180000000 }), plainOnly);
  assert.equal(matchLyricsRecord(null, { title: 'Song', artist: 'Artist' }), null);
});

test('song cache identity follows metadata across MPRIS sources', () => {
  const first = { id: 'player-a', sourceKey: 'a', trackId: '/a', title: '  Ｓｏｎｇ  ', artist: 'Artist', album: 'Album', lengthMicros: 180400000 };
  const other = { ...first, id: 'player-b', sourceKey: 'b', trackId: '/b', title: 'Song', lengthSeconds: 180 };
  assert.notEqual(lyricsKey(first), lyricsKey(other));
  assert.equal(lyricsCacheKey(first), lyricsCacheKey(other));
  assert.notEqual(lyricsCacheKey(first), lyricsCacheKey({ ...other, album: 'Live' }));
});

test('Retry-After reads seconds and final HTTP block dates only', () => {
  const now = Date.parse('Wed, 21 Oct 2015 07:27:00 GMT');
  assert.equal(retryAfterDelay('HTTP/1.1 100 Continue\r\n\r\nHTTP/2 429\r\nRetry-After: 12\r\n\r\n', now), 12000);
  assert.equal(retryAfterDelay('HTTP/1.1 429\r\nRetry-After: 999\r\n\r\nHTTP/2 429\r\nRetry-After: Wed, 21 Oct 2015 07:27:04 GMT\r\n\r\n', now), 4000);
  assert.equal(retryAfterDelay('HTTP/2 429\r\nRetry-After: past\r\n\r\n', now), null);
  assert.equal(retryAfterDelay('curl: (6) DNS failure', now), null);
  assert.equal(retryAfterDelay('HTTP/2 429\r\nRetry-After: 1.5\r\n\r\n', now), null);
  assert.equal(retryAfterDelay('HTTP/2 429\r\nRetry-After: -1\r\n\r\n', now), null);
  assert.equal(retryAfterDelay('HTTP/2 429\r\nRetry-After: 0\r\n\r\n', now), 0);
  assert.equal(retryAfterDelay('HTTP/2 429\r\nRetry-After: Wed, 21 Oct 2015 07:26:00 GMT\r\n\r\n', now), 0);
});

test('fallback rate-limit delay grows to a ten-minute cap', () => {
  assert.deepEqual([0, 1, 2, 3, 4, 5, 6].map(lyricsBackoffDelay), [30000, 60000, 120000, 240000, 480000, 600000, 600000]);
});

test('cache validation separates one-hour misses from thirty-day lyric results', () => {
  const empty = { savedAt: 1000, negative: true, value: { lines: [], plain: '', instrumental: false } };
  const success = { savedAt: 1000, negative: false, value: { lines: [{ at: 2, text: 'hello', words: [{ at: 2, text: 'hello' }] }], plain: '', instrumental: false } };
  assert.ok(validateLyricsCacheEntry(empty, 1000 + 3599999));
  assert.equal(validateLyricsCacheEntry(empty, 1000 + 3600000), null);
  assert.ok(validateLyricsCacheEntry(success, 1000 + 30 * 24 * 3600000 - 1));
  assert.equal(validateLyricsCacheEntry(success, 1000 + 30 * 24 * 3600000), null);
  assert.equal(validateLyricsCacheEntry({ ...empty, negative: false }, 1001), null);
  assert.equal(validateLyricsCacheEntry({ ...success, value: { ...success.value, lines: [{ at: -1, text: 'bad' }] } }, 1001), null);
});
