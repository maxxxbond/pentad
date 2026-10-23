import test from 'node:test';
import assert from 'node:assert/strict';
import { dayKey, monthDates, eventsForDay, eventColor, eventMarksByDay, addTask, updateTask,
  removeTask, parseOrganizer, orderedTasks } from '../../quickshell/logic/organizer.mjs';

test('calendar spans six Monday-first weeks across a leap month', () => {
  const dates = monthDates(new Date(2024, 1, 29));
  assert.equal(dates.length, 42);
  assert.equal(dates[0].getDay(), 1);
  assert.equal(dayKey(dates[0]), '2024-01-29');
  assert.equal(dayKey(dates[41]), '2024-03-10');
});

test('calendar follows the locale week start', () => {
  const sunday = monthDates(new Date(2026, 10, 1), 0);
  assert.equal(dayKey(sunday[0]), '2026-11-01');
  assert.equal(sunday[0].getDay(), 0);
  const saturday = monthDates(new Date(2026, 10, 15), 6);
  assert.equal(dayKey(saturday[0]), '2026-10-31');
  assert.equal(dayKey(monthDates(new Date(2026, 10, 1), 7)[0]), '2026-11-01');
  assert.equal(dayKey(monthDates(new Date(2026, 10, 1), Number.NaN)[0]), '2026-10-26');
});

test('event marks keep at most three source colours and reject untrusted values', () => {
  assert.equal(eventColor('#4FA3F7'), '#4FA3F7');
  assert.equal(eventColor('#4fa3f7cc'), '#4fa3f7cc');
  assert.equal(eventColor('red'), '');
  assert.equal(eventColor('#fff; x'), '');
  const event = (id, day, color) => ({ id, title: id, start: `2026-10-${day}`, end: `2026-10-${day + 1}`,
    allDay: true, color });
  const events = [event('a', 12, '#111111'), event('b', 12, 'url(x)'), event('c', 12, '#333333'),
    event('d', 12, '#444444'), event('e', 14, '#555555')];
  const marks = eventMarksByDay(events, monthDates(new Date(2026, 9, 1)));
  assert.deepEqual(marks['2026-10-12'], ['#111111', '', '#333333']);
  assert.deepEqual(marks['2026-10-14'], ['#555555']);
  assert.equal(marks['2026-10-13'], undefined);
  assert.deepEqual(eventMarksByDay([], monthDates(new Date(2026, 9, 1))), {});
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
