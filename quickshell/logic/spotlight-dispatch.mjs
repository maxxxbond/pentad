import { detectIntent, MAX_SPOTLIGHT_QUERY_LENGTH } from './spotlight-intent.mjs';

export function createSearchDispatcher(providers = []) {
  let active = null;
  return {
    cancel: function() {
      if (active) active.aborted = true;
      active = null;
    },
    query: function(rawQuery, browseApps) {
      browseApps = !!browseApps;
      if (active) active.aborted = true;
      const signal = { aborted: false };
      active = signal;
      const query = typeof rawQuery === 'string' ? rawQuery.trim().slice(0, MAX_SPOTLIGHT_QUERY_LENGTH) : '';
      if (!query && !browseApps) return Promise.resolve([]);
      const intent = detectIntent(query);
      const candidates = providers.filter(provider => {
        if (!provider || !provider.category) return false;
        if (!query && browseApps) return provider.category === 'app' && typeof provider.browse === 'function';
        if (intent.mode !== 'all' && provider.category !== intent.mode) return false;
        try { return typeof provider.matches === 'function' && provider.matches(query); }
        catch (error) { return false; }
      });
      const tasks = candidates.map(provider => Promise.resolve().then(function() {
        if (signal.aborted) return [];
        return !query && browseApps ? provider.browse(signal) : provider.search(query, signal);
      }).then(function(results) { return Array.isArray(results) ? results.slice(0, 500) : []; }, function(error) { return []; }));
      return Promise.all(tasks).then(function(batches) {
        if (signal.aborted) return [];
        const results = [];
        for (const batch of batches) for (const result of batch) results.push(result);
        return results.sort((a, b) => b.score - a.score);
      });
    },
  };
}

export const emptyHistory = () => ({ version: 1, pinned: [], recent: [] });

export function moveGridSelection(index, count, columns, direction) {
  if (count <= 0) return 0;
  columns = Math.max(1, Math.floor(columns));
  index = Math.max(0, Math.min(count - 1, index));
  if (direction === 'left') return Math.max(0, index - 1);
  if (direction === 'right') return Math.min(count - 1, index + 1);
  if (direction === 'up') return index < columns ? index : index - columns;
  if (direction === 'down') return Math.floor(index / columns) >= Math.floor((count - 1) / columns)
    ? index : Math.min(count - 1, index + columns);
  return index;
}

export function parseHistory(text) {
  const empty = emptyHistory();
  if (typeof text !== 'string' || text.length > 65536) return empty;
  try {
    const value = JSON.parse(text);
    if (!value || typeof value !== 'object' || Array.isArray(value) || value.version !== 1) return empty;
    const validId = id => typeof id === 'string' && id.startsWith('app-') && id.length < 512;
    const pinned = [];
    if (Array.isArray(value.pinned)) {
      for (const id of value.pinned) if (validId(id) && !pinned.includes(id) && pinned.length < 40) pinned.push(id);
    }
    const byId = new Map();
    if (Array.isArray(value.recent)) for (const item of value.recent) {
      if (!item || !validId(item.id) || !Number.isSafeInteger(item.count) || item.count <= 0
          || !Number.isFinite(item.used) || item.used < 0) continue;
      byId.set(item.id, { id: item.id, count: Math.min(10000, item.count), used: item.used });
    }
    const recent = [];
    byId.forEach(item => recent.push(item));
    recent.sort((a, b) => b.used - a.used);
    return { version: 1, pinned, recent: recent.slice(0, 100) };
  } catch (error) { return empty; }
}

export function togglePinned(history, id) {
  if (typeof id !== 'string' || !id.startsWith('app-') || id.length >= 512) return history;
  const pinned = history.pinned.includes(id) ? history.pinned.filter(value => value !== id) : history.pinned.concat([id]).slice(-40);
  return Object.assign({}, history, { pinned });
}

export function recordLaunch(history, id, now = Date.now()) {
  if (typeof id !== 'string' || !id.startsWith('app-') || id.length >= 512 || !Number.isFinite(now) || now < 0) return history;
  const old = history.recent.find(item => item.id === id);
  const recent = [{ id, count: Math.min(10000, (old?.count || 0) + 1), used: now }]
    .concat(history.recent.filter(item => item.id !== id)).slice(0, 100);
  return Object.assign({}, history, { recent });
}

export function rankResults(results, history, home = false) {
  const usage = new Map(history.recent.map(item => [item.id, item]));
  const bonus = item => item.category === 'app'
    ? (history.pinned.includes(item.id) ? 6 : 0) + Math.min(4, Math.log2((usage.get(item.id)?.count || 0) + 1)) : 0;
  return results.slice().sort((a, b) => {
    if (home) {
      const ap = history.pinned.indexOf(a.id), bp = history.pinned.indexOf(b.id);
      if (ap >= 0 || bp >= 0) return ap < 0 ? 1 : bp < 0 ? -1 : ap - bp;
      const recent = (usage.get(b.id)?.used || 0) - (usage.get(a.id)?.used || 0);
      return recent || a.title.localeCompare(b.title);
    }
    if (a.category === 'calc' && b.category !== 'calc') return -1;
    if (b.category === 'calc' && a.category !== 'calc') return 1;
    if (a.category === 'web' && b.category !== 'web') return 1;
    if (b.category === 'web' && a.category !== 'web') return -1;
    return b.score + bonus(b) - a.score - bonus(a);
  });
}

export class LauncherSession {
  constructor() {
    this.session = 0;
    this.revision = 0;
    this.opened = false;
    this.action = null;
    this.results = [];
    this.selected = 0;
    this.pending = false;
  }
  open() { this.session++; this.opened = true; this.reset(); }
  close() { this.session++; this.opened = false; this.reset(); }
  reset() { this.revision++; this.results = []; this.selected = 0; this.pending = false; this.action = null; }
  token() { return { session: this.session, revision: this.revision }; }
  live(token) { return this.opened && token.session === this.session; }
  current(token) { return this.live(token) && token.revision === this.revision; }
  beginQuery() { this.revision++; this.pending = true; return this.token(); }
  accept(token, results) {
    if (!this.current(token) || !Array.isArray(results)) return false;
    const previous = this.selectedResult?.id;
    this.results = results.slice(0, 500);
    this.selected = Math.max(0, this.results.findIndex(item => item.id === previous));
    this.pending = false;
    return true;
  }
  get selectedResult() { return this.results[this.selected]; }
  get actionPending() { return this.action !== null; }
  move(delta) {
    if (!this.results.length || this.pending || !Number.isInteger(delta)) return;
    this.selected = ((this.selected + delta) % this.results.length + this.results.length) % this.results.length;
  }
  beginAction() {
    if (!this.opened || this.pending || this.action || !this.selectedResult) return null;
    this.action = this.token();
    return this.action;
  }
  endAction(token) {
    if (this.action !== token) return false;
    this.action = null;
    return this.current(token);
  }
}
