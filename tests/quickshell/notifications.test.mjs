import test from 'node:test';
import assert from 'node:assert/strict';
import { createNotificationController, parseNotificationArchive, groupNotifications, routeNotifications,
  notificationButtons, hasDefaultAction, findNotificationWindow, formatNotificationTime } from '../../quickshell/logic/notifications.mjs';

function harness() {
  let wall = 1000, mono = 0, next = 1;
  const timers = new Map(), closed = [], actions = [], changes = [];
  const scheduler = {
    wallNow: () => wall,
    monotonicNow: () => mono,
    schedule(delay, callback) {
      const id = next++; timers.set(id, { at: mono + delay, callback });
      return () => timers.delete(id);
    },
  };
  const effects = { closed: (id, reason) => closed.push([id, reason]), action: (id, key) => actions.push([id, key]),
    reply: (id, text) => actions.push([id, 'reply', text]), changed: state => changes.push(state) };
  const controller = createNotificationController('test-session', scheduler, effects);
  controller.setStatus('available');
  function advance(ms) {
    mono += ms; wall += ms;
    const due = Array.from(timers.entries()).filter(([, timer]) => timer.at <= mono);
    for (const [id, timer] of due) { timers.delete(id); timer.callback(); }
  }
  function notify(extra = {}) {
    return controller.notify(Object.assign({ app: 'Example', replacesId: 0, icon: '', title: 'Title', body: 'Body',
      actions: [], hints: {}, expireTimeout: -1, sender: ':1.42' }, extra));
  }
  return { controller, advance, notify, closed, actions, changes };
}

test('replacement preserves archive key and swaps live actions without a duplicate record', () => {
  const { controller, notify } = harness();
  const id = notify({ title: 'First', actions: ['open', 'Open'] });
  const key = controller.read().history[0].key;
  assert.equal(notify({ replacesId: id, title: 'Updated', actions: ['new', 'New'] }), id);
  assert.equal(controller.read().history.length, 1);
  assert.equal(controller.read().history[0].key, key);
  assert.equal(controller.read().history[0].title, 'Updated');
  assert.equal(controller.invoke(key, 'open'), false);
  assert.equal(controller.invoke(key, 'new'), true);
});

test('mapped popup timeout pauses on hover and resumes with remaining time', () => {
  const { controller, notify, advance } = harness();
  notify({ expireTimeout: 1000 });
  const key = controller.read().history[0].key;
  controller.setPresented(key, true);
  advance(400);
  controller.setHovered(key, true);
  advance(5000);
  assert.equal(controller.read().history[0].wireId !== null, true);
  controller.setHovered(key, false);
  advance(599);
  assert.equal(controller.read().history[0].wireId !== null, true);
  advance(1);
  assert.equal(controller.read().history[0].wireId, null);
});

test('DND stores no popup backlog, marks clear groups, and maps center-visible records read', () => {
  const { controller, notify } = harness();
  notify();
  controller.setDnd(true);
  notify({ title: 'Suppressed' });
  assert.equal(controller.read().popups.length, 0);
  assert.equal(controller.read().history[0].wireId, null);
  controller.setCenterOpen('out-1', true);
  controller.setCenterPresented('out-1', true);
  assert.equal(controller.read().unread, 0);
  controller.clearGroup('example');
  assert.equal(controller.read().history.length, 0);
});

test('transient notifications are excluded and stale actions cannot invoke', () => {
  const { controller, notify, actions } = harness();
  notify({ hints: { transient: true }, title: 'Transient' });
  assert.equal(controller.read().history.length, 0);
  assert.equal(controller.read().popups.length, 1);
  const id = notify({ actions: ['go', 'Go'] });
  const key = controller.read().history[0].key;
  assert.equal(controller.invoke(key, 'go'), true);
  assert.deepEqual(actions, [[id, 'go']]);
  assert.equal(controller.invoke(key, 'go'), false);
});

test('dismissing a live center card removes its archive snapshot in one action', () => {
  const { controller, notify } = harness();
  notify();
  const key = controller.read().history[0].key;
  controller.dismiss(key);
  assert.equal(controller.read().history.length, 0);
});

test('archive validation rejects duplicate/oversized identity and drops live-only fields', () => {
  const { controller, notify } = harness();
  notify({ actions: ['a', 'A'] });
  const archive = controller.archive();
  assert.equal(archive.records[0].wireId, null);
  assert.equal(archive.records[0].sender, null);
  assert.deepEqual(archive.records[0].actions, []);
  assert.equal(parseNotificationArchive(archive).records.length, 1);
  assert.equal(parseNotificationArchive({ ...archive, records: [archive.records[0], archive.records[0]] }), null);
});

test('groups notifications and preserves valid popup output across focus changes', () => {
  const { controller, notify } = harness();
  notify({ hints: { 'desktop-entry': 'app.desktop' } });
  const record = controller.read().history[0];
  assert.equal(groupNotifications([record])[0].key, 'app.desktop');
  const previous = routeNotifications([record], [{ id: 'a', name: 'A' }, { id: 'b', name: 'B' }], 'b', new Map());
  assert.equal(previous.get(record.key), 'b');
  const retained = routeNotifications([record], [{ id: 'a', name: 'A' }, { id: 'b', name: 'B' }], 'a', previous);
  assert.equal(retained.get(record.key), 'b');
});

test('empty and already-read center openings do not republish or replace the history model', () => {
  const { controller, notify, changes } = harness();
  const initial = controller.read();
  const initialChanges = changes.length;
  controller.setCenterOpen('out-1', false);
  controller.setCenterPresented('out-1', false);
  controller.setCenterOpen('out-1', true);
  controller.setCenterPresented('out-1', true);
  assert.equal(controller.read(), initial, 'empty opening should not rebuild the notification model');
  assert.equal(changes.length, initialChanges);

  notify();
  const readState = controller.read();
  const count = changes.length;
  assert.equal(readState.history[0].read, true);
  controller.setCenterPresented('out-1', true);
  controller.setCenterOpen('out-1', false);
  controller.setCenterPresented('out-1', false);
  controller.setCenterOpen('out-1', true);
  controller.setCenterPresented('out-1', true);
  assert.equal(controller.read(), readState, 'warm reopening should reuse the complete read model');
  assert.equal(changes.length, count);
});

test('marking the center presented changes only unread records and publishes once', () => {
  const { controller, notify, changes } = harness();
  controller.setDnd(true);
  controller.setCenterOpen('out-1', true);
  controller.setCenterPresented('out-1', true);
  notify({ title: 'Already read' });
  const readRecord = controller.read().history[0];
  controller.setCenterOpen('out-1', false);
  notify({ title: 'Unread' });
  const count = changes.length;
  controller.setCenterOpen('out-1', true);
  controller.setCenterPresented('out-1', true);
  assert.equal(changes.length, count + 1);
  assert.equal(controller.read().unread, 0);
  assert.equal(controller.read().history.find(record => record.key === readRecord.key), readRecord);
});

test('center opening still dismisses live popups and retains suppression until the final output closes', () => {
  const { controller, notify, closed } = harness();
  const critical = notify({ hints: { urgency: 2 } });
  const transient = notify({ hints: { transient: true } });
  controller.setCenterOpen('out-1', true);
  assert.equal(controller.read().popups.length, 0);
  assert.deepEqual(closed, [[critical, 4], [transient, 4]]);
  controller.setCenterPresented('out-1', true);
  controller.setCenterOpen('out-2', true);
  controller.setCenterPresented('out-2', true);
  controller.setCenterOpen('out-1', false);
  notify({ title: 'Second output still open' });
  assert.equal(controller.read().popups.length, 0);
  assert.equal(controller.read().history[0].read, true);
  controller.setCenterOpen('out-2', false);
  notify({ title: 'After closing' });
  assert.equal(controller.read().popups.length, 1);
  assert.equal(controller.read().unread, 1);
});

test('popup-only updates preserve the archived history identity', () => {
  const { controller, notify } = harness();
  controller.setDnd(true);
  notify();
  controller.setDnd(false);
  const history = controller.read().history;
  assert.equal(history.length, 1);
  notify({ hints: { transient: true } });
  assert.equal(controller.read().history, history);
});

test('interactive popups leave the stack on timeout but stay live for the center', () => {
  const { controller, notify, advance, closed } = harness();
  const id = notify({ expireTimeout: 1000, actions: ['open', 'Open'] });
  const plain = notify({ expireTimeout: 1000 });
  controller.read().history.forEach(record => controller.setPresented(record.key, true));
  advance(1000);
  assert.equal(controller.read().popups.length, 0);
  assert.deepEqual(closed, [[plain, 1]], 'only the plain popup expires natively');
  const record = controller.read().history.find(item => item.wireId === id);
  assert.ok(record, 'the interactive record keeps its wire id');
  assert.equal(controller.invoke(record.key, 'open'), true);
});

test('center and DND suppression keep interactive notifications actionable without a popup', () => {
  const { controller, notify, closed } = harness();
  controller.setCenterOpen('out-1', true);
  const id = notify({ actions: ['default', 'Open'] });
  assert.equal(controller.read().popups.length, 0);
  assert.equal(controller.read().history[0].wireId, id);
  assert.equal(hasDefaultAction(controller.read().history[0]), true);
  assert.deepEqual(notificationButtons(controller.read().history[0]), []);
  controller.setCenterOpen('out-1', false);
  controller.setDnd(true);
  const plain = notify({ title: 'Plain' });
  assert.deepEqual(closed, [[plain, 4]]);
  controller.dismiss(controller.read().history.find(item => item.wireId === id).key);
  assert.deepEqual(closed, [[plain, 4], [id, 2]]);
});

test('inline replies send trimmed text once and drop non-resident notifications', () => {
  const { controller, notify, actions } = harness();
  const id = notify({ reply: { placeholder: 'Message' } });
  const key = controller.read().history[0].key;
  assert.deepEqual(controller.read().history[0].reply, { placeholder: 'Message' });
  assert.equal(controller.reply(key, '   '), false);
  assert.equal(controller.reply(key, '  hello '), true);
  assert.deepEqual(actions, [[id, 'reply', 'hello']]);
  assert.equal(controller.read().history[0].reply, null);
  assert.equal(controller.reply(key, 'again'), false);
});

test('archives keep file images only and accept older archives without images', () => {
  const { controller, notify } = harness();
  notify({ image: 'file:///home/user/avatar.png' });
  notify({ image: 'image://qsimage/42' });
  const archive = controller.archive();
  assert.deepEqual(archive.records.map(record => record.image).sort(), ['', 'file:///home/user/avatar.png']);
  const legacy = archive.records.map(record => { const copy = { ...record }; delete copy.image; return copy; });
  assert.equal(parseNotificationArchive({ ...archive, records: legacy }).records[0].image, '');
  assert.equal(parseNotificationArchive({ ...archive, records: [{ ...archive.records[0], image: 7 }] }), null);
});

test('source window prefers matching class, then a matching title, then recent use', () => {
  const record = { app: 'kitty', desktopEntry: '', title: 'Long build' };
  const clients = [
    { address: '0x1', instanceId: 'a', appClass: 'kitty', title: 'zsh' },
    { address: '0x2', instanceId: 'b', appClass: 'kitty', title: 'Long build — pentad' },
    { address: '0x3', instanceId: 'c', appClass: 'firefox', title: 'Long build docs' },
  ];
  assert.equal(findNotificationWindow(record, clients, ['a', 'b']).instanceId, 'b');
  assert.equal(findNotificationWindow({ ...record, title: 'Done' }, clients, ['b', 'a']).instanceId, 'b');
  assert.equal(findNotificationWindow({ ...record, title: 'Done' }, clients, ['a', 'b']).instanceId, 'a');
  const telegram = { app: 'Telegram Desktop', desktopEntry: 'org.telegram.desktop', title: 'Anna' };
  assert.equal(findNotificationWindow(telegram, [{ address: '0x4', instanceId: 'd', appClass: 'org.telegram.desktop' }], []).instanceId, 'd');
  assert.equal(findNotificationWindow({ app: 'mail', desktopEntry: '', title: '' }, clients, []), null);
});

test('relative times stay short and fall back to clock and dates', () => {
  const now = new Date(2026, 9, 19, 18, 0).getTime();
  const minute = 60 * 1000;
  assert.equal(formatNotificationTime(now - 20 * 1000, now), 'now');
  assert.equal(formatNotificationTime(now - 5 * minute, now), '5 min');
  assert.equal(formatNotificationTime(now - 130 * minute, now), '2 h');
  assert.equal(formatNotificationTime(new Date(2026, 9, 19, 9, 5).getTime(), now), '09:05');
  assert.equal(formatNotificationTime(new Date(2026, 9, 18, 9, 5).getTime(), now), 'Yesterday');
  assert.equal(formatNotificationTime(new Date(2026, 9, 1, 9, 5).getTime(), now, { date: () => '1 Oct' }), '1 Oct');
});
