const MAX_HISTORY = 100;
const MAX_ACTIONS = 8;
const DEFAULT_TIMEOUT = 7000;
// Interactive notifications outlive their popup so the center can still act or reply on them.
const MAX_RETAINED = 24;
const OFFLINE = { wireId: null, sender: null, actions: [], reply: null };
const EMPTY_STATE = { status: 'starting', dnd: false, history: [], popups: [], unread: 0 };
const isObject = (value) => value !== null && typeof value === 'object' && !Array.isArray(value);
const bounded = (value, max) => String(value || '').slice(0, max);
const hintString = (hints, key) => typeof hints[key] === 'string' ? hints[key] : '';
const hintBoolean = (hints, key) => hints[key] === true;
const urgency = (hints) => hints.urgency === 2 ? 'critical' : hints.urgency === 0 ? 'low' : 'normal';
const newestFirst = (a, b) => b.receivedAt - a.receivedAt || a.key.localeCompare(b.key);
const interactive = (record) => record.actions.length > 0 || record.reply !== null;
// Only file images survive a restart; pixmap URLs from the server die with the native object.
const persistentImage = (image) => /^file:\/\//.test(image) ? image : '';

function normalizeActions(values) {
  const seen = new Set(), actions = [];
  for (let i = 0; i + 1 < values.length && actions.length < MAX_ACTIONS; i += 2) {
    const key = bounded(values[i], 128), label = bounded(values[i + 1], 80);
    if (!key || seen.has(key)) continue;
    seen.add(key);
    actions.push({ key, label });
  }
  return actions;
}

export function parseNotificationArchive(input) {
  if (!isObject(input) || input.schemaVersion !== 1 || typeof input.dnd !== 'boolean'
    || !Array.isArray(input.records) || input.records.length > MAX_HISTORY) return null;
  const records = [], keys = new Set();
  for (const candidate of input.records) {
    if (!isObject(candidate) || typeof candidate.key !== 'string' || !candidate.key
      || candidate.key.length > 256 || keys.has(candidate.key)
      || typeof candidate.app !== 'string' || candidate.app.length > 80
      || typeof candidate.desktopEntry !== 'string' || candidate.desktopEntry.length > 512
      || typeof candidate.category !== 'string' || candidate.category.length > 512
      || typeof candidate.icon !== 'string' || candidate.icon.length > 512
      || typeof candidate.title !== 'string' || candidate.title.length > 160
      || typeof candidate.body !== 'string' || candidate.body.length > 4096
      || !Number.isFinite(candidate.receivedAt)
      || !['low', 'normal', 'critical'].includes(candidate.urgency)
      || typeof candidate.transient !== 'boolean' || typeof candidate.resident !== 'boolean'
      || typeof candidate.read !== 'boolean'
      || (candidate.image !== undefined && (typeof candidate.image !== 'string' || candidate.image.length > 512))) return null;
    keys.add(candidate.key);
    records.push({ key: candidate.key, wireId: null, sender: null, app: candidate.app,
      desktopEntry: candidate.desktopEntry, category: candidate.category, icon: candidate.icon,
      image: persistentImage(candidate.image || ''),
      title: candidate.title, body: candidate.body, receivedAt: candidate.receivedAt,
      urgency: candidate.urgency, transient: candidate.transient, resident: candidate.resident,
      read: candidate.read, actions: [], reply: null });
  }
  return { schemaVersion: 1, dnd: input.dnd, records: records };
}

export function createNotificationController(sessionId, scheduler, effects) {
  let state = Object.assign({}, EMPTY_STATE);
  let nextId = 1, disposed = false;
  const live = new Map(), ephemeral = new Map(), timers = new Map(), remaining = new Map(), deadlines = new Map();
  const generations = new Map(), presented = new Set(), hovered = new Set(), popupKeys = new Set();
  const openCenters = new Set(), visibleCenters = new Set();
  function publish() {
    if (disposed) return;
    const history = state.history.some((record, index, records) =>
      index > 0 && newestFirst(records[index - 1], record) > 0)
      ? state.history.slice().sort(newestFirst) : state.history;
    state = Object.assign({}, state, { history: history,
      unread: history.filter((record) => !record.read).length,
      popups: history.filter((record) => record.wireId !== null && popupKeys.has(record.key))
        .concat(Array.from(ephemeral.values())) });
    effects.changed(state);
  }
  function stopTimer(key) { const stop = timers.get(key); if (stop) stop(); timers.delete(key); }
  function update(key, patch) {
    state = Object.assign({}, state, { history: state.history.map((record) =>
      record.key === key ? Object.assign({}, record, patch) : record) });
  }
  function dropPopup(key, reason) {
    let id = null;
    live.forEach((record, liveId) => { if (record.key === key) id = liveId; });
    if (id === null) return false;
    stopTimer(key); live.delete(id); presented.delete(key); hovered.delete(key);
    remaining.delete(key); deadlines.delete(key); popupKeys.delete(key);
    if (ephemeral.has(key)) ephemeral.delete(key);
    else update(key, OFFLINE);
    effects.closed(id, reason);
    return true;
  }
  // Hides a popup. Interactive records stay live for the center; everything else closes natively.
  function retirePopup(key, reason) {
    let record = null;
    live.forEach((item) => { if (item.key === key) record = item; });
    if (!record) return false;
    if (ephemeral.has(key) || !interactive(record)) return dropPopup(key, reason);
    stopTimer(key); presented.delete(key); hovered.delete(key);
    remaining.delete(key); deadlines.delete(key); popupKeys.delete(key);
    const retained = state.history.filter((item) => item.wireId !== null && !popupKeys.has(item.key));
    retained.slice(MAX_RETAINED).forEach((item) => dropPopup(item.key, 1));
    return true;
  }
  function timeout(key, delay) {
    stopTimer(key);
    const generation = (generations.get(key) || 0) + 1;
    generations.set(key, generation);
    const duration = Math.max(0, delay);
    remaining.set(key, duration);
    deadlines.set(key, scheduler.monotonicNow() + duration);
    timers.set(key, scheduler.schedule(duration, function() {
      if (disposed || generations.get(key) !== generation) return;
      retirePopup(key, 1); publish();
    }));
  }
  function policyDismiss(reason) {
    const keys = Array.from(live.values()).filter((record) => popupKeys.has(record.key)
      && (presented.has(record.key) || record.urgency === 'critical')).map((record) => record.key);
    keys.forEach((key) => retirePopup(key, reason === undefined ? 4 : reason));
    publish();
  }
  function allocateId() {
    for (let count = 0; count <= 0xffffffff; count++) {
      const id = nextId; nextId = nextId === 0xffffffff ? 1 : nextId + 1;
      if (!live.has(id)) return id;
    }
    throw new Error('Notification ID space is exhausted');
  }
  function capHistory() {
    while (state.history.length > MAX_HISTORY) {
      const oldest = state.history[state.history.length - 1];
      if (oldest.wireId !== null) dropPopup(oldest.key, 4);
      state = Object.assign({}, state, { history: state.history.filter((record) => record.key !== oldest.key) });
    }
  }
  function archiveLive(id, reason) {
    const record = live.get(id);
    if (!record) return false;
    dropPopup(record.key, reason);
    return true;
  }
  function hasLivePopup(key) { return popupKeys.has(key); }
  function liveRecord(key) {
    const record = state.history.find((item) => item.key === key) || ephemeral.get(key);
    return record && record.wireId !== null ? record : null;
  }
  return {
    read: function() { return state; },
    notify: function(input) {
      if (disposed) return 0;
      const existing = input.replacesId > 0 ? live.get(input.replacesId) : null;
      const now = scheduler.wallNow(), id = existing ? input.replacesId : allocateId();
      const record = { key: existing ? existing.key : String(sessionId) + '.' + id,
        wireId: id, sender: input.sender || null, app: bounded(input.app || 'Unknown app', 80),
        desktopEntry: bounded(hintString(input.hints, 'desktop-entry'), 512),
        category: bounded(hintString(input.hints, 'category'), 512), icon: bounded(input.icon, 512),
        image: bounded(input.image, 512),
        title: bounded(input.title, 160), body: bounded(input.body, 4096), receivedAt: now,
        urgency: urgency(input.hints), transient: hintBoolean(input.hints, 'transient'),
        resident: hintBoolean(input.hints, 'resident'), read: visibleCenters.size > 0,
        actions: normalizeActions(input.actions || []),
        reply: input.reply ? { placeholder: bounded(input.reply.placeholder, 80) } : null };
      if (existing) {
        stopTimer(existing.key); presented.delete(existing.key); hovered.delete(existing.key); popupKeys.delete(existing.key);
      }
      if (record.transient) {
        if (existing) {
          ephemeral.delete(existing.key);
          state = Object.assign({}, state, { history: state.history.filter((item) => item.key !== existing.key) });
        }
        const canPopupTransient = state.status === 'available' && !state.dnd && openCenters.size === 0;
        if (!canPopupTransient) { live.delete(id); effects.closed(id, 4); publish(); return id; }
        ephemeral.set(record.key, record); live.set(id, record); presented.add(record.key); popupKeys.add(record.key);
        const requestedTimeout = Number(input.expireTimeout);
        if (record.urgency !== 'critical' && requestedTimeout !== 0) {
          const delay = requestedTimeout < 0 || !Number.isFinite(requestedTimeout)
            ? DEFAULT_TIMEOUT : Math.min(requestedTimeout, 0x7fffffff);
          remaining.set(record.key, delay);
        }
        const visiblePopups = state.history.filter((item) => popupKeys.has(item.key))
          .concat(Array.from(ephemeral.values()));
        visiblePopups.slice(3).forEach((overflow) => dropPopup(overflow.key, 4));
        publish(); return id;
      }
      if (existing) ephemeral.delete(existing.key);
      const canPopup = state.status === 'available' && !state.dnd && openCenters.size === 0;
      state = Object.assign({}, state, { history: [record].concat(state.history.filter((item) => item.key !== record.key)) });
      live.set(id, record);
      if (!canPopup) {
        // Suppressed popups still reach the center; only interactive ones keep their native object.
        if (state.status === 'available' && interactive(record)) {
          retirePopup(record.key, 4); capHistory(); publish(); return id;
        }
        if (existing) dropPopup(existing.key, 4); else effects.closed(id, 4);
        update(record.key, OFFLINE);
        live.delete(id); capHistory(); publish(); return id;
      }
      presented.add(record.key); popupKeys.add(record.key);
      const requested = Number(input.expireTimeout);
      if (record.urgency !== 'critical' && requested !== 0) {
        const delay = requested < 0 || !Number.isFinite(requested) ? DEFAULT_TIMEOUT : Math.min(requested, 0x7fffffff);
        remaining.set(record.key, delay);
      }
      const visible = state.history.filter((item) => popupKeys.has(item.key))
        .concat(Array.from(ephemeral.values()));
      visible.slice(3).forEach((overflow) => retirePopup(overflow.key, 4));
      capHistory(); publish(); return id;
    },
    closeFromSender: function(id) {
      const record = live.get(id); if (!record) return false;
      archiveLive(id, 3);
      state = Object.assign({}, state, { history: state.history.filter((item) => item.key !== record.key) });
      publish(); return true;
    },
    dismiss: function(key) {
      const record = state.history.find((item) => item.key === key) || ephemeral.get(key); if (!record) return;
      if (record.wireId !== null) archiveLive(record.wireId, 2);
      state = Object.assign({}, state, { history: state.history.filter((item) => item.key !== key) });
      publish();
    },
    clearGroup: function(groupKey) {
      const remove = state.history.filter((record) => (record.desktopEntry || record.app.trim().toLowerCase() || 'unknown') === groupKey);
      remove.forEach((record) => { if (record.wireId !== null) archiveLive(record.wireId, 4); });
      const keys = new Set(remove.map((record) => record.key));
      state = Object.assign({}, state, { history: state.history.filter((record) => !keys.has(record.key)) });
      publish();
    },
    clearAll: function() {
      state.history.slice().forEach((record) => { if (record.wireId !== null) archiveLive(record.wireId, 4); });
      state = Object.assign({}, state, { history: [] }); publish();
    },
    invoke: function(key, actionKey) {
      const record = liveRecord(key);
      if (!record || !record.actions.some((action) => action.key === actionKey)) return false;
      const id = record.wireId; effects.action(id, actionKey);
      if (!record.resident) archiveLive(id, 2);
      publish(); return true;
    },
    reply: function(key, text) {
      const record = liveRecord(key), message = String(text || '').trim();
      if (!record || record.reply === null || !message) return false;
      const id = record.wireId; effects.reply(id, message.slice(0, 4096));
      if (!record.resident) archiveLive(id, 2);
      publish(); return true;
    },
    setDnd: function(enabled) {
      if (state.dnd === enabled) return;
      state = Object.assign({}, state, { dnd: enabled });
      if (enabled) policyDismiss(); else publish();
    },
    setCenterOpen: function(outputId, open) {
      if (open && openCenters.has(outputId)) return;
      if (open) openCenters.add(outputId);
      else { openCenters.delete(outputId); visibleCenters.delete(outputId); }
      if (openCenters.size && Array.from(live.values()).some((record) => popupKeys.has(record.key)
        && (presented.has(record.key) || record.urgency === 'critical'))) policyDismiss();
    },
    setCenterPresented: function(outputId, isPresented) {
      if (isPresented) {
        visibleCenters.add(outputId);
        if (!state.history.some((record) => !record.read)) return;
        state = Object.assign({}, state, { history: state.history.map((record) =>
          record.read ? record : Object.assign({}, record, { read: true })) });
        publish();
      } else visibleCenters.delete(outputId);
    },
    setPresented: function(key, isPresented) {
      if (!hasLivePopup(key)) return;
      if (!isPresented) {
        if (!presented.has(key)) return;
        presented.delete(key);
        const deadline = deadlines.get(key);
        if (deadline !== undefined) {
          remaining.set(key, Math.max(0, deadline - scheduler.monotonicNow()));
          deadlines.delete(key); stopTimer(key); generations.set(key, (generations.get(key) || 0) + 1);
        }
        return;
      }
      if (state.dnd || openCenters.size) return;
      presented.add(key);
      const record = state.history.find((item) => item.key === key) || ephemeral.get(key);
      if (record && record.urgency !== 'critical' && !hovered.has(key) && remaining.has(key) && !timers.has(key))
        timeout(key, remaining.get(key));
    },
    setHovered: function(key, isHovered) {
      if (isHovered) {
        hovered.add(key);
        const cancel = timers.get(key);
        if (cancel) {
          const deadline = deadlines.get(key);
          if (deadline !== undefined) remaining.set(key, Math.max(0, deadline - scheduler.monotonicNow()));
          cancel(); timers.delete(key); deadlines.delete(key); generations.set(key, (generations.get(key) || 0) + 1);
        }
      } else {
        hovered.delete(key);
        if (presented.has(key) && remaining.has(key)) timeout(key, remaining.get(key));
      }
    },
    senderLost: function(sender) {
      const matches = [];
      live.forEach((record, id) => { if (record.sender === sender) matches.push([id, record]); });
      matches.forEach((pair) => {
        const id = pair[0], record = pair[1]; stopTimer(record.key); live.delete(id);
        presented.delete(record.key); deadlines.delete(record.key); popupKeys.delete(record.key);
        if (ephemeral.has(record.key)) ephemeral.delete(record.key);
        else update(record.key, OFFLINE);
      });
      publish();
    },
    setStatus: function(status) {
      if (state.status === status) return;
      const unavailable = state.status === 'available' && status !== 'available';
      state = Object.assign({}, state, { status: status });
      if (unavailable) Array.from(live.keys()).forEach((id) => archiveLive(id, 4));
      publish();
    },
    restore: function(archive) {
      const parsed = parseNotificationArchive(archive);
      if (!parsed) throw new TypeError('Invalid notification archive');
      state = Object.assign({}, state, { dnd: parsed.dnd,
        history: parsed.records.filter((record) => !record.transient) });
      capHistory(); publish();
    },
    archive: function() {
      return { schemaVersion: 1, dnd: state.dnd,
        records: state.history.filter((record) => !record.transient).slice(0, MAX_HISTORY).map((record) =>
          Object.assign({}, record, OFFLINE, { image: persistentImage(record.image) })) };
    },
    dispose: function() {
      if (disposed) return;
      timers.forEach((cancel) => cancel()); timers.clear(); live.clear(); presented.clear(); popupKeys.clear();
      openCenters.clear(); visibleCenters.clear(); deadlines.clear(); disposed = true;
    },
  };
}

export function notificationGroupKey(record) {
  return record.desktopEntry || record.app.trim().toLowerCase() || 'unknown';
}

export function groupNotifications(records) {
  const groups = new Map();
  records.forEach((record) => {
    const key = notificationGroupKey(record), group = groups.get(key) || [];
    group.push(record); groups.set(key, group);
  });
  return Array.from(groups.entries()).map(([key, items]) => {
    const sorted = items.slice().sort((a, b) => b.receivedAt - a.receivedAt);
    return { key: key, app: sorted[0].app, icon: sorted[0].icon, latestAt: sorted[0].receivedAt,
      unread: sorted.filter((item) => !item.read).length, records: sorted };
  }).sort((a, b) => b.latestAt - a.latestAt || a.key.localeCompare(b.key));
}

export function chooseNotificationOutput(outputs, focusedId) {
  if (!outputs.length) return null;
  const focused = focusedId && outputs.find((output) => output.id === focusedId || output.name === focusedId);
  return focused ? focused.id : outputs[0].id;
}

export function routeNotifications(records, outputs, focusedId, previous) {
  const valid = new Set(outputs.map((output) => output.id)), result = new Map();
  records.forEach((record) => {
    const prior = previous.get(record.key);
    result.set(record.key, prior && valid.has(prior) ? prior : chooseNotificationOutput(outputs, focusedId));
  });
  return result;
}

// The "default" action is the card click itself, so it never doubles as a button.
export function notificationButtons(record) {
  return record && record.wireId !== null ? record.actions.filter((action) => action.key !== 'default') : [];
}

export function hasDefaultAction(record) {
  return !!record && record.wireId !== null && record.actions.some((action) => action.key === 'default');
}

function sourceNames(record) {
  const names = new Set();
  const add = (value) => {
    const raw = String(value || '').trim().toLowerCase(), name = raw.replace(/\.desktop$/, '');
    if (!name) return;
    names.add(raw);
    names.add(name);
    // Reverse-DNS entries (org.telegram.desktop) often map to a short window class.
    const parts = name.split('.').filter((part) => part && part !== 'desktop');
    if (parts.length > 1) names.add(parts[parts.length - 1]);
  };
  add(record.desktopEntry);
  add(record.app);
  return names;
}

// Picks the window that most likely sent the notification: a matching class or app id,
// preferring a title that mentions the notification title, then the most recently used.
export function findNotificationWindow(record, clients, mru) {
  if (!record || !Array.isArray(clients)) return null;
  const names = sourceNames(record);
  if (!names.size) return null;
  const order = Array.isArray(mru) ? mru : [];
  const title = String(record.title || '').trim().toLowerCase();
  const rank = (client) => {
    const index = order.indexOf(client.instanceId);
    return index < 0 ? order.length : index;
  };
  const matches = clients.filter((client) => client && client.instanceId
    && (names.has(String(client.appClass || '').toLowerCase()) || names.has(String(client.appId || '').toLowerCase())));
  if (!matches.length) return null;
  const titled = title.length >= 3
    ? matches.filter((client) => String(client.title || '').toLowerCase().includes(title)) : [];
  const pool = titled.length ? titled : matches;
  return pool.slice().sort((a, b) => rank(a) - rank(b))[0];
}

// Compact relative time: "now", "5 min", "3 h", then a clock time today, "Yesterday" or a date.
export function formatNotificationTime(receivedAt, now, labels) {
  const text = labels || {};
  const delta = Math.max(0, now - receivedAt);
  const minute = 60 * 1000, hour = 60 * minute;
  if (delta < minute) return text.now || 'now';
  if (delta < hour) return Math.floor(delta / minute) + ' ' + (text.minutes || 'min');
  if (delta < 6 * hour) return Math.floor(delta / hour) + ' ' + (text.hours || 'h');
  const received = new Date(receivedAt), current = new Date(now);
  if (received.toDateString() === current.toDateString())
    return text.clock ? text.clock(received) : received.toTimeString().slice(0, 5);
  const yesterday = new Date(current.getFullYear(), current.getMonth(), current.getDate() - 1);
  if (received.toDateString() === yesterday.toDateString()) return text.yesterday || 'Yesterday';
  return text.date ? text.date(received) : received.toISOString().slice(0, 10);
}
