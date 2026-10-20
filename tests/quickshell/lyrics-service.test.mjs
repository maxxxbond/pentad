import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';
import * as Rules from '../../quickshell/logic/lyrics.mjs';

const service = readFileSync(new URL('../../quickshell/services/Lyrics.qml', import.meta.url), 'utf8');
const methods = [...service.matchAll(/^    function \w+\([^\n]*\) \{.*?^    \}/gms)]
  .map((match) => match[0]).join('\n');
const retryHandler = /property Timer retryTimer: Timer \{.*?onTriggered: \{(.*?)\n        \}/s.exec(service)[1];

function fixture() {
  const requests = [];
  const helperCalls = [];
  const clock = { now: 1700000000000 };
  const player = {
    id: 'fixture-player', name: 'fixture-player', trackId: '/fixture/track',
    title: 'Test Song', artist: 'Test Artist', album: 'Test Album', lengthMicros: 180_000_000,
  };
  const FakeDate = class extends Date { static now() { return clock.now; } };
  const retryTimer = { running: false, interval: 0, start() { this.running = true; }, stop() { this.running = false; } };
  const context = vm.createContext({
    player, key: Rules.lyricsKey(player), songKey: Rules.lyricsCacheKey(player),
    state: { kind: 'unavailable', reason: 'no-track' },
    consumers: [], cache: {}, cacheRecords: {}, cacheKeys: [], request: null, helperRequests: [],
    generation: 0, retryAfterUntil: 0, preview: false, safeMode: false,
    cacheLoaded: true, cacheLoading: false, cacheWritePending: false, cacheWriteDirty: false,
    rateLimitFailures: 0, helperPath: '', retryTimer, Rules, Date: FakeDate,
    workerComponent: { createObject(_parent, properties) {
      const worker = Object.assign({}, properties, {
        settled: false, running: false, stdout: { text: '' }, stderr: { text: '' },
        signal(signal) { this.signalled = signal; },
        destroy() { this.destroyed = true; this.running = false; },
      });
      requests.push(worker);
      return worker;
    } },
  });
  context.root = context;
  vm.runInContext(methods, context, { timeout: 1000 });
  retryTimer.fire = function() {
    if (!this.running) return;
    this.running = false;
    vm.runInContext(retryHandler, context, { timeout: 1000 });
  };
  context.helper = function(payload, done) { helperCalls.push({ payload, done }); return null; };
  return { service: context, requests, helperCalls, clock };
}

function respond(service, worker, status, body, code = 0) {
  worker.stdout.text = `${body}\n${status}`;
  worker.stderr = worker.stderr || { text: '' };
  service.completed(worker, code, false, false);
}

test('lyrics service exact success decodes and caches a real synced response', () => {
  const { service: s, requests } = fixture();
  s.acquire('media-card');
  assert.equal(requests.length, 1);
  assert.match(requests[0].url, /\/api\/get\?/);
  assert.match(requests[0].url, /duration=180/);
  respond(s, requests[0], 200, JSON.stringify({ syncedLyrics: '[00:01.00]hello', plainLyrics: '', instrumental: false }));
  assert.equal(s.state.kind, 'ready');
  assert.equal(s.state.value.lines[0].text, 'hello');
  assert.equal(s.cache[s.songKey].lines.length, 1);
});

test('lyrics service 404 exact lookup falls back to matched search result', () => {
  const { service: s, requests } = fixture();
  s.acquire('media-card');
  respond(s, requests[0], 404, '');
  assert.equal(requests.length, 2);
  assert.match(requests[1].url, /\/api\/search\?/);
  respond(s, requests[1], 200, JSON.stringify([{
    trackName: 'Test Song', artistName: 'Test Artist', albumName: 'Test Album', duration: 180,
    syncedLyrics: '[00:02.00]found', plainLyrics: null,
  }]));
  assert.equal(s.state.kind, 'ready');
  assert.equal(s.state.value.lines[0].text, 'found');
});

test('lyrics service reports process failures and invalid HTTP payloads as errors', () => {
  const failed = fixture();
  failed.service.acquire('media-card');
  respond(failed.service, failed.requests[0], 200, '{invalid');
  assert.deepEqual(JSON.parse(JSON.stringify(failed.service.state)), { kind: 'error', reason: 'invalid-response' });

  const httpFailure = fixture();
  httpFailure.service.acquire('media-card');
  respond(httpFailure.service, httpFailure.requests[0], 503, 'unavailable');
  assert.deepEqual(JSON.parse(JSON.stringify(httpFailure.service.state)), {
    kind: 'error', reason: 'lookup-failed', exitCode: 0, httpStatus: 503,
  });

  const dnsFailure = fixture();
  dnsFailure.service.acquire('media-card');
  dnsFailure.requests[0].stdout.text = '';
  dnsFailure.service.completed(dnsFailure.requests[0], 6, false, false);
  assert.deepEqual(JSON.parse(JSON.stringify(dnsFailure.service.state)), {
    kind: 'error', reason: 'lookup-failed', exitCode: 6, httpStatus: 0,
  });
});

test('lyrics service reports preview and safe-mode suppression without starting workers', () => {
  const preview = fixture();
  preview.service.preview = true;
  preview.service.acquire('media-card');
  assert.deepEqual(JSON.parse(JSON.stringify(preview.service.state)), { kind: 'unavailable', reason: 'preview' });
  assert.equal(preview.requests.length, 0);

  const safeMode = fixture();
  safeMode.service.safeMode = true;
  safeMode.service.acquire('media-card');
  assert.deepEqual(JSON.parse(JSON.stringify(safeMode.service.state)), { kind: 'unavailable', reason: 'safe-mode' });
  assert.equal(safeMode.requests.length, 0);
});

test('lyrics service ignores stale responses and nonmember releases keep active consumers', () => {
  const { service: s, requests } = fixture();
  s.acquire('media-card');
  const stale = requests[0];
  s.release('island');
  assert.deepEqual(Array.from(s.consumers), ['media-card']);
  assert.equal(s.request, stale);

  s.release('media-card');
  assert.equal(stale.signalled, 9);
  s.acquire('media-card');
  const current = requests[1];
  respond(s, stale, 200, JSON.stringify({ syncedLyrics: '[00:01.00]stale' }));
  assert.equal(s.state.kind, 'starting');
  respond(s, current, 200, JSON.stringify({ syncedLyrics: '[00:01.00]current' }));
  assert.equal(s.state.kind, 'ready');
  assert.equal(s.state.value.lines[0].text, 'current');
});

function rateLimit(s, worker, after = '0') {
  worker.stderr.text = `HTTP/2 429\r\nRetry-After: ${after}\r\n\r\n`;
  respond(s, worker, 429, '');
}

function changeTrack(s, player) {
  s.player = player;
  s.key = player ? Rules.lyricsKey(player) : '';
  s.songKey = player ? Rules.lyricsCacheKey(player) : '';
  s.refresh();
}

for (const after of ['0', 'Wed, 21 Oct 2015 07:27:00 GMT']) {
  test(`lyrics service retries a zero/past Retry-After (${after}) after at least one second`, () => {
    const { service: s, requests, clock } = fixture();
    s.acquire('media-card');
    rateLimit(s, requests[0], after);
    assert.equal(s.state.reason, 'rate-limited');
    assert.equal(s.retryAfterUntil, clock.now + 1000);
    assert.equal(s.retryTimer.interval, 1000);
    assert.equal(s.retryTimer.running, true);
    clock.now += 999;
    s.retryTimer.fire();
    assert.equal(requests.length, 1);
    assert.equal(s.retryTimer.running, true);
    clock.now++;
    s.retryTimer.fire();
    assert.equal(requests.length, 2);
    respond(s, requests[1], 200, JSON.stringify({ plainLyrics: 'recovered' }));
    assert.equal(s.state.kind, 'ready');
    assert.equal(s.state.value.plain, 'recovered');
    assert.equal(s.retryAfterUntil, 0);
    assert.equal(s.rateLimitFailures, 0);
    assert.equal(s.retryTimer.running, false);
  });
}

test('lyrics service closing the last consumer stops retries and reopening preserves cooldown', () => {
  const { service: s, requests, clock } = fixture();
  s.acquire('media-card');
  s.acquire('island');
  rateLimit(s, requests[0], '10');
  s.release('media-card');
  assert.equal(s.retryTimer.running, true);
  s.release('island');
  assert.equal(s.retryTimer.running, false);
  clock.now += 2000;
  s.retryTimer.fire();
  assert.equal(requests.length, 1);
  s.acquire('media-card');
  assert.equal(s.retryTimer.interval, 8000);
  assert.equal(s.retryTimer.running, true);
  assert.equal(requests.length, 1);
  clock.now += 8000;
  s.retryTimer.fire();
  assert.equal(requests.length, 2);
});

test('lyrics service retries the current track after a track change during cooldown', () => {
  const { service: s, requests, clock } = fixture();
  s.acquire('media-card');
  rateLimit(s, requests[0], '2');
  changeTrack(s, { ...s.player, title: 'Next Song', trackId: '/fixture/next' });
  assert.equal(requests.length, 1);
  clock.now += 2000;
  s.retryTimer.fire();
  assert.equal(requests.length, 2);
  assert.match(requests[1].url, /track_name=Next%20Song/);
  respond(s, requests[1], 200, JSON.stringify({ plainLyrics: 'next lyrics' }));
  assert.equal(s.state.value.plain, 'next lyrics');
});

test('lyrics service does not retry when the player disappears during cooldown', () => {
  const { service: s, requests, clock } = fixture();
  s.acquire('media-card');
  rateLimit(s, requests[0]);
  changeTrack(s, null);
  clock.now += 1000;
  s.retryTimer.fire();
  assert.equal(requests.length, 1);
  assert.equal(s.state.reason, 'no-track');
  assert.equal(s.retryTimer.running, false);
});

for (const result of [null, { ok: false, reason: 'io' }, { ok: false, reason: 'timeout' },
  { ok: true, entries: {} }, { ok: true, entries: { corrupt: { value: null } } }]) {
  test(`lyrics service cache read ${JSON.stringify(result)} falls through to lookup`, () => {
    const { service: s, requests, helperCalls } = fixture();
    s.helperPath = '/fixture/helper';
    s.cacheLoaded = false;
    s.acquire('media-card');
    assert.equal(requests.length, 0);
    assert.equal(helperCalls.length, 1);
    assert.equal(helperCalls[0].payload.operation, 'lyrics-cache-read');
    helperCalls[0].done(result);
    assert.equal(s.cacheLoaded, true);
    assert.equal(s.cacheLoading, false);
    assert.equal(requests.length, 1);
    respond(s, requests[0], 200, JSON.stringify({ plainLyrics: 'network lyrics' }));
    assert.equal(s.state.kind, 'ready');
  });
}

for (const action of ['close', 'change-track', 'remove-player']) {
  test(`lyrics service cache read completion respects ${action}`, () => {
    const { service: s, requests, helperCalls } = fixture();
    s.helperPath = '/fixture/helper';
    s.cacheLoaded = false;
    s.acquire('media-card');
    if (action === 'close') s.release('media-card');
    else changeTrack(s, action === 'remove-player' ? null : { ...s.player, title: 'New Song' });
    helperCalls[0].done({ ok: false, reason: 'io' });
    assert.equal(s.cacheLoading, false);
    assert.equal(s.cacheLoaded, true);
    assert.equal(helperCalls.length, 1);
    assert.equal(requests.length, action === 'change-track' ? 1 : 0);
    if (action === 'change-track') assert.match(requests[0].url, /track_name=New%20Song/);
    if (action === 'close') {
      s.acquire('media-card');
      assert.equal(requests.length, 1);
    }
  });
}
