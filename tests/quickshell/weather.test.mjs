import assert from 'node:assert/strict';
import test from 'node:test';
import {
  createCancellation, createWeatherManager, describeWeather, forecastUrl, geocodingUrl, parseCityResults,
  parseForecast, weatherConfig,
} from '../../quickshell/logic/weather.mjs';
import { readFile } from 'node:fs/promises';
import { validateManifest } from '../../quickshell/logic/plugin-manifest.mjs';

const config = weatherConfig({ city: 'Kyiv', country: 'Ukraine', region: 'Kyiv City',
  latitude: 50.45, longitude: 30.52, timezone: 'Europe/Kyiv', units: 'fahrenheit' });
const forecast = (temperature = 50) => ({
  current: { temperature_2m: temperature, apparent_temperature: 47, wind_speed_10m: 12,
    weather_code: 3, is_day: 1 },
  daily: { time: ['2026-10-10', '2026-10-11', '2026-10-12'],
    temperature_2m_min: [41, 40, 39], temperature_2m_max: [55, 56, 57], weather_code: [3, 2, 61] },
});
const flush = async () => { await Promise.resolve(); await Promise.resolve(); await new Promise(resolve => setImmediate(resolve)); };

test('weather config, Open-Meteo URL, forecast parsing, and WMO descriptions are bounded', async () => {
  assert.ok(config);
  assert.equal(weatherConfig({ city: '', country: '', region: '', latitude: 0, longitude: 0,
    timezone: '', units: 'celsius' }), null);
  assert.equal(weatherConfig({ city: 'Kyiv', country: 'Ukraine', region: 'Kyiv City', latitude: 91,
    longitude: 30.52, timezone: 'Europe/Kyiv', units: 'celsius' }), null);
  assert.match(forecastUrl(config), /temperature_unit=fahrenheit/);
  assert.match(forecastUrl(config), /timezone=Europe%2FKyiv/);
  const parsed = parseForecast(forecast(), 1234);
  assert.equal(parsed.days[0].date, '2026-10-10');
  assert.equal(parsed.temperature, 50);
  assert.equal(describeWeather(777), 'Unknown conditions');
  assert.throws(() => parseForecast({ ...forecast(), current: {} }, 1234));

  const manifest = JSON.parse(await readFile(
    new URL('../../quickshell/widgets/weather/manifest.json', import.meta.url), 'utf8',
  ));
  assert.equal(validateManifest(manifest, { slot: 'sidebar-left' }).ok, true);
});

test('geocoding URL and city results are bounded and validated', () => {
  assert.match(geocodingUrl('  Berlin & Potsdam '), /name=Berlin%20%26%20Potsdam/);
  assert.match(geocodingUrl('Berlin'), /count=5/);
  assert.equal(new URL(geocodingUrl('x'.repeat(130))).searchParams.get('name').length, 100);
  const valid = { name: 'Berlin', country: 'Germany', admin1: 'Berlin', latitude: 52.52,
    longitude: 13.405, timezone: 'Europe/Berlin' };
  const invalidFirst = parseCityResults({ results: [{ ...valid, latitude: 91 }, ...Array(6).fill(valid)] });
  assert.equal(invalidFirst.length, 4);
  assert.equal(invalidFirst[0].region, 'Berlin');
  assert.equal(parseCityResults({ results: Array(6).fill(valid) }).length, 5);
  assert.deepEqual(parseCityResults({ results: 'invalid' }), []);
});

test('city search ignores cancelled and disposed lookups', async () => {
  const resolveFetch = [];
  let seenUrl = '';
  const manager = createWeatherManager({
    now: () => 1000, changed: () => {}, every: () => () => {},
    fetchJson: (url) => {
      seenUrl = url;
      return new Promise(resolve => { resolveFetch.push(resolve); });
    },
  });
  const cancellation = createCancellation();
  const pending = manager.searchCities('Berlin', cancellation);
  await flush();
  assert.match(seenUrl, /geocoding-api\.open-meteo\.com/);
  cancellation.cancel();
  resolveFetch[0]({ results: [{ name: 'Berlin', country: 'Germany', latitude: 52.52,
    longitude: 13.405, timezone: 'Europe/Berlin' }] });
  assert.deepEqual(await pending, []);
  const afterDispose = manager.searchCities('Paris', { isCancelled: () => false });
  await flush();
  manager.dispose();
  resolveFetch[1]({ results: [{ name: 'Paris', country: 'France', latitude: 48.85,
    longitude: 2.35, timezone: 'Europe/Paris' }] });
  assert.deepEqual(await afterDispose, []);
});

test('two outputs share one request, cache result, and stop polling after last release', async () => {
  let now = 1000;
  let requests = 0;
  let resolveFetch;
  let cancelled;
  let timerStarts = 0;
  let timerStops = 0;
  const manager = createWeatherManager({
    now: () => now,
    changed: () => {},
    every: () => { timerStarts++; return () => timerStops++; },
    fetchJson: (_url, token) => {
      requests++;
      cancelled = token;
      return new Promise(resolve => { resolveFetch = resolve; });
    },
  });
  const outputA = manager.acquire(config);
  const outputB = manager.acquire(config);
  await flush();
  assert.equal(requests, 1);
  assert.equal(timerStarts, 1);
  resolveFetch(forecast(51));
  await flush();
  assert.equal(manager.read(outputA).status, 'ready');
  assert.equal(manager.read(outputB).value.temperature, 51);
  const stopsBeforeRelease = timerStops;
  manager.release(outputA);
  assert.equal(timerStops, stopsBeforeRelease);
  manager.release(outputB);
  assert.equal(timerStops, stopsBeforeRelease + 1);
  assert.equal(cancelled.isCancelled(), false);
  manager.dispose();
});

test('last release cancels an in-flight request and ignores a late response', async () => {
  let resolveFetch;
  let token;
  let emittedReady = false;
  const manager = createWeatherManager({
    now: () => 1000,
    changed: (_key, state) => { if (state.status === 'ready') emittedReady = true; },
    every: () => () => {},
    fetchJson: (_url, cancellation) => {
      token = cancellation;
      return new Promise(resolve => { resolveFetch = resolve; });
    },
  });
  const handle = manager.acquire(config);
  await flush();
  manager.release(handle);
  assert.equal(token.isCancelled(), true);
  resolveFetch(forecast());
  await flush();
  assert.equal(emittedReady, false);
  manager.dispose();
});

test('release before the transport microtask prevents a phantom request after reacquire', async () => {
  let requests = 0;
  const manager = createWeatherManager({
    now: () => 1000, changed: () => {}, every: () => () => {},
    fetchJson: async () => { requests++; return forecast(); },
  });
  const first = manager.acquire(config);
  manager.release(first);
  const second = manager.acquire(config);
  await flush();
  assert.equal(requests, 1);
  assert.equal(manager.read(second).status, 'ready');
  manager.release(second);
  manager.dispose();
});

test('network failures retry with bounded backoff, then return to the refresh interval', async () => {
  const timers = [];
  let calls = 0;
  const manager = createWeatherManager({
    now: () => 1000,
    changed: () => {},
    every: (milliseconds, callback) => {
      const timer = { milliseconds, callback, stopped: false };
      timers.push(timer);
      return () => { timer.stopped = true; };
    },
    fetchJson: async () => {
      calls++;
      if (calls < 3) throw new Error('offline');
      return forecast();
    },
  });
  const handle = manager.acquire(config);
  await flush();
  assert.equal(manager.read(handle).status, 'unavailable');
  assert.equal(timers.at(-1).milliseconds, 60 * 1000);
  timers.at(-1).callback();
  await flush();
  assert.equal(timers.at(-1).milliseconds, 5 * 60 * 1000);
  timers.at(-1).callback();
  await flush();
  assert.equal(manager.read(handle).status, 'ready');
  assert.equal(timers.at(-1).milliseconds, 15 * 60 * 1000);
  manager.release(handle);
  manager.dispose();
});

test('network failure uses a cache younger than 24 hours and drops expired data', async () => {
  let now = 1000;
  let failNext = false;
  const manager = createWeatherManager({
    now: () => now,
    changed: () => {},
    every: () => () => {},
    fetchJson: async () => {
      if (failNext) throw new Error('offline');
      return forecast();
    },
  });
  const first = manager.acquire(config);
  await flush();
  assert.equal(manager.read(first).status, 'ready');
  manager.release(first);

  now += 20 * 60 * 1000;
  failNext = true;
  const second = manager.acquire(config);
  await flush();
  assert.equal(manager.read(second).status, 'stale');
  assert.equal(manager.read(second).value.temperature, 50);
  manager.release(second);

  now += 24 * 60 * 60 * 1000;
  const third = manager.acquire(config);
  await flush();
  assert.equal(manager.read(third).status, 'unavailable');
  assert.equal(manager.read(third).value, null);
  manager.release(third);
  manager.dispose();
});
