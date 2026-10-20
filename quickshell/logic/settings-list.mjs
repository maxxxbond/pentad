export function moveItem(ids, from, to) {
  const out = ids.slice();
  if (out.length === 0) return out;
  if (!Number.isInteger(from) || from < 0 || from >= out.length) return out;
  const target = Math.min(Math.max(Number.isInteger(to) ? to : from, 0), out.length - 1);
  if (target === from) return out;
  const [moved] = out.splice(from, 1);
  out.splice(target, 0, moved);
  return out;
}
