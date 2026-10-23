import assert from 'node:assert/strict';
import test from 'node:test';
import { createClockTimerController, datePattern, formatTimer, idleTimerState, timePattern } from '../../quickshell/logic/clock.mjs';

test('bar clock patterns follow the time format, seconds and date style', () => {
  assert.equal(timePattern('24h', false), 'HH:mm');
  assert.equal(timePattern(undefined, true), 'HH:mm:ss');
  assert.equal(timePattern('12h', false), 'h:mm AP');
  assert.equal(timePattern('12h', true), 'h:mm:ss AP');
  assert.equal(datePattern('day-month'), 'dd.MM');
  assert.equal(datePattern(undefined), 'dd.MM');
  assert.equal(datePattern('month-day'), 'MM/dd');
  assert.equal(datePattern('hidden'), '');
});

function fakeScheduler(start = 0) {
  let now = start;
  let serial = 0;
  const tasks = new Map();
  return {
    now: () => now,
    schedule(callback, delay) {
      const id = ++serial;
      tasks.set(id, { at: now + delay, callback });
      return id;
    },
    cancel(id) { tasks.delete(id); },
    pending: () => tasks.size,
    elapse(milliseconds) {
      now += milliseconds;
      let next;
      while ((next = Array.from(tasks.entries()).find(([, task]) => task.at <= now))) {
        tasks.delete(next[0]);
        next[1].callback();
      }
    },
    jump(milliseconds) { now += milliseconds; },
    wake() {
      const next = Array.from(tasks.entries()).sort((a, b) => a[1].at - b[1].at)[0];
      if (!next) return false;
      tasks.delete(next[0]);
      next[1].callback();
      return true;
    },
  };
}

test('timer validates duration, counts down from a deadline and finishes', () => {
  const scheduler = fakeScheduler();
  const timer = createClockTimerController(scheduler);
  assert.deepEqual(timer.read(), idleTimerState());
  for (const value of [0, -1, 1.5, NaN, 86401, '10']) assert.equal(timer.start(value), false);
  assert.equal(timer.start(86400), true);
  assert.equal(timer.read().remainingSeconds, 86400);
  assert.equal(scheduler.pending(), 1);
  timer.reset();
  assert.equal(timer.start(3), true);
  scheduler.elapse(1100);
  assert.equal(timer.read().remainingSeconds, 2);
  scheduler.elapse(1900);
  assert.deepEqual(timer.read(), { status: 'finished', durationSeconds: 3, remainingSeconds: 0 });
  assert.equal(scheduler.pending(), 0);
});

test('pause and resume preserve remaining whole seconds without accumulating ticks', () => {
  const scheduler = fakeScheduler(1000);
  const timer = createClockTimerController(scheduler);
  timer.start(12);
  scheduler.elapse(2500);
  assert.equal(timer.pause(), true);
  assert.deepEqual(timer.read(), { status: 'paused', durationSeconds: 12, remainingSeconds: 10 });
  assert.equal(scheduler.pending(), 0);
  scheduler.elapse(90000);
  assert.equal(timer.read().status, 'paused');
  assert.equal(timer.resume(), true);
  assert.equal(timer.read().remainingSeconds, 10);
  scheduler.elapse(10000);
  assert.equal(timer.read().status, 'finished');
  assert.equal(timer.read().remainingSeconds, 0);
});

test('refresh uses timestamps after sleep and wall-clock changes', () => {
  const scheduler = fakeScheduler();
  const timer = createClockTimerController(scheduler);
  timer.start(20);
  scheduler.jump(7500);
  assert.equal(timer.refresh().remainingSeconds, 13);
  scheduler.jump(-2500);
  assert.equal(timer.refresh().remainingSeconds, 15);
  scheduler.jump(30000);
  scheduler.wake();
  assert.equal(timer.read().status, 'finished');
  assert.equal(scheduler.pending(), 0);
});

test('restart replaces its scheduled callback and reset returns to idle', () => {
  const scheduler = fakeScheduler();
  const timer = createClockTimerController(scheduler);
  timer.start(30);
  scheduler.elapse(5000);
  timer.start(5);
  assert.equal(scheduler.pending(), 1);
  assert.equal(timer.read().durationSeconds, 5);
  scheduler.elapse(5000);
  assert.equal(timer.read().status, 'finished');
  timer.reset();
  assert.deepEqual(timer.read(), idleTimerState());
});

test('controllers are independent per placement', () => {
  const scheduler = fakeScheduler();
  const first = createClockTimerController(scheduler);
  const second = createClockTimerController(scheduler);
  first.start(4);
  assert.equal(first.read().status, 'running');
  assert.equal(second.read().status, 'idle');
  assert.equal(scheduler.pending(), 1);
});

test('subscribe, unsubscribe and dispose release scheduled work', () => {
  const scheduler = fakeScheduler();
  const timer = createClockTimerController(scheduler);
  const seen = [];
  const unsubscribe = timer.subscribe(state => seen.push(state.status));
  timer.start(5);
  unsubscribe();
  timer.pause();
  timer.resume();
  timer.dispose();
  timer.dispose();
  assert.deepEqual(seen, ['idle', 'running']);
  assert.equal(scheduler.pending(), 0);
  assert.equal(timer.start(1), false);
  assert.equal(timer.reset(), false);
});

test('formats idle durations as the legacy timer display', () => {
  assert.equal(formatTimer(0), '00:00');
  assert.equal(formatTimer(59), '00:59');
  assert.equal(formatTimer(1500), '25:00');
  assert.equal(formatTimer(3601), '01:00:01');
});
