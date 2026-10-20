export const DEFAULT_ORGANIZER = Object.freeze({
  schemaVersion: 1,
  tab: 'calendar',
  collapsed: false,
  tasks: [],
});

const object = (value) => value !== null && typeof value === 'object' && !Array.isArray(value);

export function dayKey(date) {
  return `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, '0')}-${String(date.getDate()).padStart(2, '0')}`;
}

export function parseDayKey(value) {
  if (typeof value !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(value)) return null;
  const [year, month, day] = value.split('-').map(Number);
  const date = new Date(year, month - 1, day);
  return dayKey(date) === value ? date : null;
}

export function monthDates(month) {
  const first = new Date(month.getFullYear(), month.getMonth(), 1);
  const offset = (first.getDay() + 6) % 7;
  return Array.from({ length: 42 }, (_, index) =>
    new Date(first.getFullYear(), first.getMonth(), 1 - offset + index));
}

function eventDate(value, allDay) {
  if (allDay) return parseDayKey(value) || new Date(NaN);
  const date = new Date(value);
  return Number.isFinite(date.getTime()) ? date : new Date(NaN);
}

export function eventsForDay(events, day) {
  const start = new Date(day.getFullYear(), day.getMonth(), day.getDate());
  const end = new Date(day.getFullYear(), day.getMonth(), day.getDate() + 1);
  return events.filter((event) => {
    const from = eventDate(event.start, event.allDay).getTime();
    const to = eventDate(event.end, event.allDay).getTime();
    return from < to && from < end.getTime() && to > start.getTime();
  }).sort((a, b) => Number(b.allDay) - Number(a.allDay)
    || eventDate(a.start, a.allDay).getTime() - eventDate(b.start, b.allDay).getTime()
    || a.title.localeCompare(b.title));
}

function validateTask(task, ids) {
  if (!object(task) || typeof task.id !== 'string' || !task.id || ids.has(task.id)
    || typeof task.text !== 'string' || !task.text.trim() || task.text.length > 500
    || task.text !== task.text.trim() || typeof task.done !== 'boolean'
    || !Number.isFinite(task.createdAt)) throw new TypeError('Invalid organizer task');
  ids.add(task.id);
  return { id: task.id, text: task.text, done: task.done, createdAt: task.createdAt };
}

export function parseOrganizer(value) {
  if (!object(value) || value.schemaVersion !== 1 || !['calendar', 'tasks'].includes(value.tab)
    || typeof value.collapsed !== 'boolean' || !Array.isArray(value.tasks) || value.tasks.length > 500)
    throw new TypeError('Invalid organizer document');
  const ids = new Set();
  return {
    schemaVersion: 1,
    tab: value.tab,
    collapsed: value.collapsed,
    tasks: value.tasks.map((task) => validateTask(task, ids)),
  };
}

export function addTask(tasks, text, id, now = Date.now()) {
  if (tasks.length >= 500 || typeof text !== 'string' || typeof id !== 'string' || !id
    || !Number.isFinite(now)) throw new TypeError('Invalid organizer task');
  const clean = text.trim();
  if (!clean || clean.length > 500 || tasks.some((task) => task.id === id))
    throw new TypeError('Invalid organizer task');
  return tasks.concat([{ id, text: clean, done: false, createdAt: now }]);
}

export function updateTask(tasks, id, patch) {
  if (!object(patch) || !tasks.some((task) => task.id === id)) throw new TypeError('Unknown organizer task');
  return tasks.map((task) => {
    if (task.id !== id) return task;
    const next = Object.assign({}, task, patch);
    const ids = new Set(tasks.filter((item) => item.id !== id).map((item) => item.id));
    return validateTask(next, ids);
  });
}

export function removeTask(tasks, id) {
  return tasks.filter((task) => task.id !== id);
}

export function orderedTasks(tasks) {
  return tasks.slice().sort((a, b) => Number(a.done) - Number(b.done) || a.createdAt - b.createdAt);
}
