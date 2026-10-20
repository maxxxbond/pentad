const REFRESH_MS = 15 * 60 * 1000;
const RETRY_MS = [60 * 1000, 5 * 60 * 1000, 15 * 60 * 1000];
const CACHE_MS = 24 * 60 * 60 * 1000;
const MAX_ENTRIES = 32;
const object = value => value !== null && typeof value === 'object' && !Array.isArray(value);
const finite = value => typeof value === 'number' && Number.isFinite(value);

export function weatherConfig(settings) {
  if (!object(settings)) return null;
  const city = typeof settings.city === 'string' ? settings.city.trim() : '';
  const country = typeof settings.country === 'string' ? settings.country.trim() : '';
  const region = typeof settings.region === 'string' ? settings.region.trim() : '';
  const timezone = typeof settings.timezone === 'string' ? settings.timezone.trim() : '';
  const latitude = settings.latitude;
  const longitude = settings.longitude;
  const units = settings.units;
  if (!city || city.length > 120 || country.length > 120 || region.length > 120
      || !timezone || timezone.length > 120 || !/^(?:UTC|[A-Za-z_+-]+(?:\/[A-Za-z0-9_+-]+)+)$/.test(timezone)
      || !finite(latitude) || latitude < -90 || latitude > 90
      || !finite(longitude) || longitude < -180 || longitude > 180
      || !['celsius', 'fahrenheit'].includes(units)) return null;
  return { location: { name: city, country, region, latitude, longitude, timezone }, units };
}

export function weatherKey(config) {
  const location = config.location;
  return `${location.latitude.toFixed(4)}:${location.longitude.toFixed(4)}:${location.timezone}:${config.units}`;
}

export function forecastUrl(config) {
  const params = {
    latitude: String(config.location.latitude),
    longitude: String(config.location.longitude),
    timezone: config.location.timezone,
    current: 'temperature_2m,apparent_temperature,weather_code,is_day,wind_speed_10m',
    daily: 'weather_code,temperature_2m_max,temperature_2m_min',
    forecast_days: '3',
    temperature_unit: config.units,
    wind_speed_unit: 'kmh',
  };
  const query = Object.entries(params).map(([key, value]) =>
    `${encodeURIComponent(key)}=${encodeURIComponent(value)}`).join('&');
  return `https://api.open-meteo.com/v1/forecast?${query}`;
}

export function geocodingUrl(query, language = 'en') {
  const normalized = typeof query === 'string' ? query.trim().slice(0, 100) : '';
  const params = { name: normalized, count: '5', language: /^[a-z]{2,3}$/.test(language) ? language : 'en', format: 'json' };
  const queryString = Object.entries(params).map(([key, value]) =>
    `${encodeURIComponent(key)}=${encodeURIComponent(value)}`).join('&');
  return `https://geocoding-api.open-meteo.com/v1/search?${queryString}`;
}

export function parseCityResults(input) {
  if (!object(input) || !Array.isArray(input.results)) return [];
  const matches = [];
  for (const row of input.results.slice(0, 5)) {
    if (!object(row)) continue;
    const name = typeof row.name === 'string' ? row.name.trim() : '';
    const country = typeof row.country === 'string' ? row.country.trim() : '';
    const region = typeof row.admin1 === 'string' ? row.admin1.trim() : '';
    const timezone = typeof row.timezone === 'string' ? row.timezone.trim() : '';
    const { latitude, longitude } = row;
    if (!name || name.length > 120 || !country || country.length > 120 || region.length > 120
        || !timezone || timezone.length > 120 || !/^(?:UTC|[A-Za-z_+-]+(?:\/[A-Za-z0-9_+-]+)+)$/.test(timezone)
        || !finite(latitude) || latitude < -90 || latitude > 90
        || !finite(longitude) || longitude < -180 || longitude > 180) continue;
    matches.push({ name, country, region, latitude, longitude, timezone });
  }
  return matches;
}

export function parseForecast(input, updatedAt) {
  if (!object(input) || !object(input.current) || !object(input.daily))
    throw new Error('Weather response is missing current or daily data');
  const { current, daily } = input;
  const arrays = [daily.time, daily.temperature_2m_min, daily.temperature_2m_max, daily.weather_code];
  if (arrays.some(value => !Array.isArray(value)) || arrays[0].length < 3
      || arrays.some(value => value.length !== arrays[0].length))
    throw new Error('Weather response has incomplete forecast days');
  const days = arrays[0].slice(0, 3).map((date, index) => {
    const min = arrays[1][index], max = arrays[2][index], code = arrays[3][index];
    if (typeof date !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(date)
        || !finite(min) || !finite(max) || !finite(code) || !Number.isInteger(code))
      throw new Error('Weather response has invalid forecast values');
    return { date, min, max, code };
  });
  const code = current.weather_code;
  if (!finite(current.temperature_2m) || !finite(current.apparent_temperature)
      || !finite(current.wind_speed_10m) || !finite(code) || !Number.isInteger(code)
      || (current.is_day !== 0 && current.is_day !== 1) || !finite(updatedAt))
    throw new Error('Weather response has invalid current conditions');
  return {
    temperature: current.temperature_2m,
    apparent: current.apparent_temperature,
    windKmh: current.wind_speed_10m,
    code,
    isDay: current.is_day === 1,
    days,
    updatedAt,
  };
}

export function describeWeather(code) {
  if (code === 0) return 'Clear';
  if ([1, 2].includes(code)) return 'Partly cloudy';
  if (code === 3) return 'Cloudy';
  if ([45, 48].includes(code)) return 'Fog';
  if ([51, 53, 55, 56, 57].includes(code)) return 'Drizzle';
  if ([61, 63, 65, 66, 67, 80, 81, 82].includes(code)) return 'Rain';
  if ([71, 73, 75, 77, 85, 86].includes(code)) return 'Snow';
  if ([95, 96, 99].includes(code)) return 'Thunderstorm';
  return 'Unknown conditions';
}

class Cancellation {
  constructor() { this.cancelled = false; this.listeners = new Set(); }
  isCancelled() { return this.cancelled; }
  subscribe(listener) {
    if (this.cancelled) listener();
    else this.listeners.add(listener);
    return () => this.listeners.delete(listener);
  }
  cancel() {
    if (this.cancelled) return;
    this.cancelled = true;
    for (const listener of [...this.listeners]) listener();
    this.listeners.clear();
  }
}

export function createCancellation() { return new Cancellation(); }

export function createWeatherManager(dependencies) {
  const entries = new Map();
  let disposed = false;
  let serial = 0;
  const publish = entry => dependencies.changed(entry.key, entry.state);
  const stopTimer = entry => {
    entry.stopTimer?.();
    entry.stopTimer = null;
  };
  const cancelRequest = entry => {
    if (!entry.cancellation) return;
    entry.cancellation.cancel();
    entry.cancellation = null;
    entry.request = null;
    entry.generation++;
  };
  const prune = () => {
    if (entries.size <= MAX_ENTRIES) return;
    const inactive = [...entries.values()].filter(entry => entry.references === 0)
      .sort((a, b) => a.lastUsed - b.lastUsed);
    while (entries.size > MAX_ENTRIES && inactive.length) {
      const entry = inactive.shift();
      stopTimer(entry);
      cancelRequest(entry);
      entries.delete(entry.key);
    }
  };
  const refresh = entry => {
    if (disposed || entry.references === 0 || entry.request) return entry.request || Promise.resolve();
    const cancellation = new Cancellation();
    const generation = ++entry.generation;
    entry.cancellation = cancellation;
    entry.state = entry.value
      ? { status: 'stale', value: entry.value, message: 'Refreshing weather…' }
      : { status: 'loading', value: null, message: '' };
    publish(entry);
    const request = Promise.resolve().then(() => {
      if (disposed || cancellation.isCancelled() || entry.generation !== generation || entry.references === 0) return;
      return dependencies.fetchJson(forecastUrl(entry.config), cancellation);
    }).then(raw => {
      if (disposed || cancellation.isCancelled() || entry.generation !== generation || entry.references === 0) return;
      const value = parseForecast(raw, dependencies.now());
      entry.value = value;
      entry.updatedAt = value.updatedAt;
      entry.state = { status: 'ready', value, message: '' };
      publish(entry);
      entry.retryAttempt = 0;
      if (entry.cancellation === cancellation) {
        entry.cancellation = null;
        entry.request = null;
      }
      stopTimer(entry);
      schedule(entry, REFRESH_MS);
    }).catch(error => {
      if (!disposed && !cancellation.isCancelled() && entry.generation === generation) {
        const age = entry.value ? dependencies.now() - entry.updatedAt : Infinity;
        if (entry.value && age >= 0 && age <= CACHE_MS) {
          entry.state = { status: 'stale', value: entry.value, message: 'Weather service is offline; showing cached data.' };
        } else {
          entry.value = null;
          entry.updatedAt = 0;
          entry.state = { status: 'unavailable', value: null, message: 'Weather is currently unavailable.' };
        }
        publish(entry);
      }
      const delay = RETRY_MS[Math.min(entry.retryAttempt, RETRY_MS.length - 1)];
      entry.retryAttempt = Math.min(entry.retryAttempt + 1, RETRY_MS.length - 1);
      if (entry.cancellation === cancellation) {
        entry.cancellation = null;
        entry.request = null;
      }
      stopTimer(entry);
      schedule(entry, delay);
    });
    entry.request = request;
    return request;
  };
  function schedule(entry, milliseconds = REFRESH_MS) {
    if (entry.stopTimer || entry.references === 0) return;
    entry.stopTimer = dependencies.every(milliseconds, () => {
      stopTimer(entry);
      if (entry.references > 0) void refresh(entry);
    });
  }
  const entryFor = config => {
    const key = weatherKey(config);
    let entry = entries.get(key);
    if (!entry) {
      entry = { key, config, references: 0, handles: new Set(), lastUsed: dependencies.now(),
        generation: 0, cancellation: null, request: null, stopTimer: null, retryAttempt: 0, value: null, updatedAt: 0,
        state: { status: 'setup', value: null, message: '' } };
      entries.set(key, entry);
    }
    return entry;
  };
  return {
    searchCities(query, cancellation) {
      const normalized = typeof query === 'string' ? query.trim().slice(0, 100) : '';
      if (disposed || normalized.length < 2 || cancellation?.isCancelled()) return Promise.resolve([]);
      return Promise.resolve().then(() => dependencies.fetchJson(geocodingUrl(normalized, dependencies.language ? dependencies.language() : 'en'), cancellation))
        .then(raw => cancellation?.isCancelled() || disposed ? [] : parseCityResults(raw));
    },
    acquire(config) {
      if (disposed || !config || !config.location) return null;
      const normalized = weatherConfig({
        city: config.location.name,
        country: config.location.country,
        region: config.location.region,
        latitude: config.location.latitude,
        longitude: config.location.longitude,
        timezone: config.location.timezone,
        units: config.units,
      });
      if (!normalized) return null;
      const key = weatherKey(normalized);
      const entry = entryFor(normalized);
      const token = `weather-${++serial}`;
      entry.handles.add(token);
      entry.references++;
      entry.lastUsed = dependencies.now();
      schedule(entry);
      if (entry.value) {
        const age = dependencies.now() - entry.updatedAt;
        if (age >= 0 && age < REFRESH_MS) entry.state = { status: 'ready', value: entry.value, message: '' };
        else if (age >= 0 && age <= CACHE_MS) {
          entry.state = { status: 'stale', value: entry.value, message: 'Refreshing weather…' };
          void refresh(entry);
        } else {
          entry.value = null;
          entry.updatedAt = 0;
          void refresh(entry);
        }
      } else void refresh(entry);
      return { key, token };
    },
    read(handle) {
      const entry = handle && entries.get(handle.key);
      return entry && entry.handles.has(handle.token) ? entry.state
        : { status: 'unavailable', value: null, message: 'Weather view is no longer active.' };
    },
    refresh(handle) {
      const entry = handle && entries.get(handle.key);
      if (!entry || !entry.handles.has(handle.token)) return Promise.resolve();
      return refresh(entry);
    },
    release(handle) {
      const entry = handle && entries.get(handle.key);
      if (!entry || !entry.handles.delete(handle.token)) return;
      entry.references = Math.max(0, entry.references - 1);
      entry.lastUsed = dependencies.now();
      if (entry.references === 0) {
        stopTimer(entry);
        cancelRequest(entry);
      }
      prune();
    },
    dispose() {
      if (disposed) return;
      disposed = true;
      for (const entry of entries.values()) {
        stopTimer(entry);
        cancelRequest(entry);
      }
      entries.clear();
    },
    diagnostics() {
      return { keys: entries.size, active: [...entries.values()].filter(entry => entry.references > 0).length,
        requests: [...entries.values()].filter(entry => !!entry.request).length };
    },
  };
}
