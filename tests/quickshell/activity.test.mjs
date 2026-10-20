import test from 'node:test';
import assert from 'node:assert/strict';
import { emptyActivityDocument, mutateActivities, parseActivity, parseActivityDocument, selectActivity, timerForActivity } from '../../quickshell/logic/activity.mjs';

const record = (id, kind, updatedAt = 1, expiresAt = 200) => ({
    id, kind, title: id, detail: '', progress: null, updatedAt, expiresAt
});
const timer = { status: 'running', durationSeconds: 1500, remainingSeconds: 900 };
const playing = { playback: 'playing' };
const paused = { playback: 'paused' };

test('activity parser validates IDs, fields, progress, and times', () => {
    assert.deepEqual(parseActivity(record('build-1', 'task')), record('build-1', 'task'));
    for (const patch of [
        { id: '../build' }, { kind: 'unknown' }, { title: 'x'.repeat(161) },
        { detail: 'x'.repeat(513) }, { progress: -0.1 }, { progress: 1.1 },
        { progress: NaN }, { updatedAt: Infinity }, { expiresAt: 'later' },
    ]) assert.equal(parseActivity({ ...record('build', 'task'), ...patch }), null);
});

test('document parser rejects duplicate and malformed records without dropping them', () => {
    assert.deepEqual(parseActivityDocument(undefined), { ok: true, value: emptyActivityDocument() });
    assert.equal(parseActivityDocument({ schemaVersion: 1, activities: [record('same', 'task'), record('same', 'recording')] }).ok, false);
    assert.equal(parseActivityDocument('{broken').reason, 'invalid-document');
});

test('selection follows timer, task, recording, playing media, DND notification, paused media priority', () => {
    const notification = record('notice', 'notification', 4);
    const recording = record('record', 'recording', 3);
    const task = record('task', 'task', 2);
    assert.equal(selectActivity(timer, [task, recording, notification], playing, 100, false).kind, 'timer');
    assert.equal(selectActivity(null, [task, recording, notification], playing, 100, false).kind, 'task');
    assert.equal(selectActivity(null, [recording, notification], playing, 100, false).kind, 'recording');
    assert.equal(selectActivity(null, [notification], playing, 100, false).kind, 'media');
    assert.equal(selectActivity(null, [notification], paused, 100, true).kind, 'media');
    assert.equal(selectActivity(null, [notification], paused, 100, false).kind, 'notification');
    assert.equal(selectActivity(null, [notification], null, 100, true).kind, 'idle');
    assert.equal(selectActivity(null, [record('expired', 'task', 1, 100)], null, 100, false).kind, 'idle');
    assert.equal(selectActivity(null, [record('new', 'task', 5), record('old', 'task', 4)], null, 0).activity.id, 'new');
});

test('finished timer keeps activity priority for five seconds, then yields', () => {
    const finished = { status: 'finished', durationSeconds: 1500, remainingSeconds: 0 };
    assert.equal(timerForActivity(finished, 1000, 5999), finished);
    assert.equal(timerForActivity(finished, 1000, 6000), null);
    assert.equal(timerForActivity(finished, -1, 1001), null);
    assert.equal(timerForActivity({ status: 'paused', remainingSeconds: 3 }, 1000, 100000).status, 'paused');
});

test('start and update honor CLI defaults and preserve ID/title, end is idempotent, expiry prunes', () => {
    const started = mutateActivities(undefined, 'start', { id: 'job-1', title: 'Build', options: {} }, 1000);
    assert.equal(started.value.expiresAt, 61000);
    const updated = mutateActivities(started.document, 'update', {
        id: 'job-1', options: { progress: 0.5, detail: 'Half', ttl: 10 }
    }, 2000);
    assert.deepEqual(updated.value, {
        id: 'job-1', kind: 'task', title: 'Build', detail: 'Half', progress: 0.5,
        updatedAt: 2000, expiresAt: 12000
    });
    const notification = mutateActivities(updated.document, 'start', {
        id: 'notice', title: 'Ready', options: { kind: 'notification' }
    }, 3000);
    assert.equal(notification.value.expiresAt, 8000);
    assert.equal(mutateActivities(notification.document, 'update', { id: 'absent' }, 4000).reason, 'not-found');
    const ended = mutateActivities(notification.document, 'end', { id: 'job-1' }, 4000);
    assert.deepEqual(ended.document.activities.map(item => item.id), ['notice']);
    assert.equal(mutateActivities(ended.document, 'end', { id: 'job-1' }, 4000).ok, true);
    assert.deepEqual(mutateActivities(ended.document, 'expire', {}, 8000).document.activities, []);
});

test('mutations reject unsafe IDs, unknown options, bad TTL and invalid progress', () => {
    assert.equal(mutateActivities(undefined, 'start', { id: '../x', title: 'x' }).reason, 'invalid-id');
    assert.equal(mutateActivities(undefined, 'start', { id: 'x', title: 'x', options: { ttl: 86401 } }).reason, 'invalid-ttl');
    assert.equal(mutateActivities(undefined, 'start', { id: 'x', title: 'x', options: { progress: 1.1 } }).reason, 'invalid-activity');
    assert.equal(mutateActivities(undefined, 'start', { id: 'x', title: 'x', options: { shell: true } }).reason, 'invalid-options');
});
