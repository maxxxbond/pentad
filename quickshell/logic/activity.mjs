export const activityIdPattern = /^[a-z0-9.-]{1,64}$/;
export const activityKinds = ['task', 'recording', 'notification'];
export const FINISHED_TIMER_ACTIVITY_MS = 5000;

export function timerForActivity(timer, finishedAt, now = Date.now()) {
    if (!timer || !['running', 'paused', 'finished'].includes(timer.status)) return null;
    if (timer.status === 'finished' && finishedAt < 0) return null;
    if (timer.status === 'finished' && Number.isFinite(finishedAt)
        && finishedAt > 0 && now - finishedAt >= FINISHED_TIMER_ACTIVITY_MS) return null;
    return timer;
}

export function parseActivity(input) {
    if (!input || typeof input !== 'object' || Array.isArray(input)) return null;
    const { id, kind, title, detail, progress, updatedAt, expiresAt } = input;
    if (typeof id !== 'string' || !activityIdPattern.test(id)
        || !activityKinds.includes(kind)
        || typeof title !== 'string' || title.length > 160
        || typeof detail !== 'string' || detail.length > 512
        || !(progress === null || (typeof progress === 'number' && Number.isFinite(progress) && progress >= 0 && progress <= 1))
        || typeof updatedAt !== 'number' || !Number.isFinite(updatedAt)
        || typeof expiresAt !== 'number' || !Number.isFinite(expiresAt)) return null;
    return { id, kind, title, detail, progress, updatedAt, expiresAt };
}

export function emptyActivityDocument() {
    return { schemaVersion: 1, activities: [] };
}

export function parseActivityDocument(input) {
    if (input === undefined || input === null) return { ok: true, value: emptyActivityDocument() };
    let document = input;
    if (typeof document === 'string') {
        try { document = JSON.parse(document); }
        catch (error) { return { ok: false, reason: 'invalid-document' }; }
    }
    if (!document || typeof document !== 'object' || Array.isArray(document)
        || document.schemaVersion !== 1 || !Array.isArray(document.activities))
        return { ok: false, reason: 'invalid-document' };
    const activities = [];
    const ids = new Set();
    for (const inputActivity of document.activities) {
        const activity = parseActivity(inputActivity);
        if (!activity || ids.has(activity.id)) return { ok: false, reason: 'invalid-document' };
        ids.add(activity.id);
        activities.push(activity);
    }
    return { ok: true, value: { schemaVersion: 1, activities } };
}

export function mutateActivities(documentInput, action, input, now = Date.now()) {
    const parsed = parseActivityDocument(documentInput);
    if (!parsed.ok) return parsed;
    const { id, title, options = {} } = input || {};
    if (!['start', 'update', 'end', 'expire'].includes(action)) return { ok: false, reason: 'unsupported' };
    if (action !== 'expire' && (typeof id !== 'string' || !activityIdPattern.test(id))) return { ok: false, reason: 'invalid-id' };
    const current = parsed.value.activities.filter(activity => activity.expiresAt > now);
    if (action === 'expire') {
        const changed = current.length !== parsed.value.activities.length;
        return { ok: true, changed, document: { schemaVersion: 1, activities: current } };
    }
    if (action === 'end') {
        const next = current.filter(activity => activity.id !== id);
        return { ok: true, changed: next.length !== parsed.value.activities.length, document: { schemaVersion: 1, activities: next }, value: { id } };
    }
    if (!options || typeof options !== 'object' || Array.isArray(options)
        || Object.keys(options).some(key => !['kind', 'progress', 'detail', 'ttl'].includes(key)))
        return { ok: false, reason: 'invalid-options' };
    const existing = current.find(activity => activity.id === id) || null;
    if (action === 'update' && !existing) return { ok: false, reason: 'not-found' };
    if (action === 'start' && (typeof title !== 'string' || !title)) return { ok: false, reason: 'invalid-title' };
    const kind = options.kind === undefined ? (existing ? existing.kind : 'task') : options.kind;
    if (!activityKinds.includes(kind)) return { ok: false, reason: 'invalid-kind' };
    const ttl = options.ttl === undefined ? (kind === 'notification' ? 5 : 60) : Number(options.ttl);
    if (!Number.isFinite(ttl) || ttl < 1 || ttl > 86400) return { ok: false, reason: 'invalid-ttl' };
    const progress = options.progress === undefined ? (existing ? existing.progress : null) : options.progress;
    const detail = options.detail === undefined ? (existing ? existing.detail : '') : options.detail;
    const activity = parseActivity({
        id, kind, title: existing ? existing.title : title, detail, progress,
        updatedAt: now, expiresAt: now + ttl * 1000
    });
    if (!activity) return { ok: false, reason: 'invalid-activity' };
    const next = current.filter(item => item.id !== id).concat([activity]);
    return { ok: true, changed: true, document: { schemaVersion: 1, activities: next }, value: activity };
}

export function selectActivity(timer, activities, player, now = Date.now(), dnd = false) {
    if (timer && ['running', 'paused', 'finished'].includes(timer.status)) return { kind: 'timer', timer };
    const live = activities.filter(item => item.expiresAt > now)
        .slice().sort((a, b) => b.updatedAt - a.updatedAt || a.id.localeCompare(b.id));
    for (const kind of ['task', 'recording']) {
        const activity = live.find(item => item.kind === kind);
        if (activity) return { kind, activity };
    }
    if (player && player.playback === 'playing') return { kind: 'media', player };
    const notification = !dnd && live.find(item => item.kind === 'notification');
    if (notification) return { kind: 'notification', activity: notification };
    if (player && player.playback === 'paused') return { kind: 'media', player };
    return { kind: 'idle' };
}
