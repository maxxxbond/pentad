import test from 'node:test';
import assert from 'node:assert/strict';
import { dayKey, monthDates, eventsForDay, addTask, updateTask,
  removeTask, parseOrganizer, orderedTasks } from '../../quickshell/logic/organizer.mjs';

test('calendar spans six Monday-first weeks across a leap month', () => {
  const dates = monthDates(new Date(2024, 1, 29));
  assert.equal(dates.length, 42);
  assert.equal(dates[0].getDay(), 1);
  assert.equal(dayKey(dates[0]), '2024-01-29');
  assert.equal(dayKey(dates[41]), '2024-03-10');
});

test('task edit/done/delete retain identity and do not mutate previous state', () => {
  const original = addTask([], '  Купити молоко  ', 'fixture-1', 123);
  const edited = updateTask(original, 'fixture-1', { text: 'Купити хліб', done: true });
  assert.equal(original[0].text, 'Купити молоко');
  assert.equal(original[0].done, false);
  assert.deepEqual(edited[0], { id: 'fixture-1', text: 'Купити хліб', done: true, createdAt: 123 });
  assert.deepEqual(removeTask(edited, 'fixture-1'), []);
  assert.throws(() => addTask([], '   ', 'fixture-2', 124), TypeError);
  assert.throws(() => parseOrganizer({ schemaVersion: 1, tab: 'calendar', collapsed: false,
    tasks: [original[0], original[0]] }), TypeError);
});

test('all-day exclusive end does not leak into the next day', () => {
  const event = { id: 'e', sourceId: 'fixture', title: 'Подія',
    start: '2026-10-12', end: '2026-10-13', allDay: true };
  assert.equal(eventsForDay([event], new Date(2026, 9, 12)).length, 1);
  assert.equal(eventsForDay([event], new Date(2026, 9, 13)).length, 0);
});

test('task ordering keeps incomplete tasks before completed tasks', () => {
  const tasks = [
    { id: 'done', text: 'done', done: true, createdAt: 1 },
    { id: 'later', text: 'later', done: false, createdAt: 3 },
    { id: 'first', text: 'first', done: false, createdAt: 2 },
  ];
  assert.deepEqual(orderedTasks(tasks).map((task) => task.id), ['first', 'later', 'done']);
});

test('organizer parser rejects invalid or oversized documents', () => {
  assert.throws(() => parseOrganizer({ schemaVersion: 2, tab: 'calendar', collapsed: false, tasks: [] }), TypeError);
  assert.throws(() => parseOrganizer({ schemaVersion: 1, tab: 'calendar', collapsed: false,
    tasks: [{ id: 'x', text: 'x'.repeat(501), done: false, createdAt: 0 }] }), TypeError);
});
