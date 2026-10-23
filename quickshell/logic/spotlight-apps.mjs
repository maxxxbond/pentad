// Desktop files that only differ by file name (copies such as code.desktop and vscode.desktop with
// the same Name and Exec) collapse into one entry; field codes like %F do not count.
const launchKey = app => app.name.trim().toLowerCase() + '\n'
  + app.exec.replace(/%[a-zA-Z%]/g, ' ').trim().replace(/\s+/g, ' ');
const program = exec => (exec.trim().split(/\s+/)[0] || '').split('/').pop();

// Of duplicates, keep the one in the launch history, then the one named after its program, then the shortest id.
function preferredCopy(current, candidate, preferred) {
  const rank = app => [preferred.has('app-' + app.id) ? 0 : 1,
    app.id === program(app.exec) + '.desktop' ? 0 : 1, app.id.length];
  const a = rank(current), b = rank(candidate);
  for (let i = 0; i < a.length; i++) if (a[i] !== b[i]) return b[i] < a[i] ? candidate : current;
  return candidate.id < current.id ? candidate : current;
}

export function indexApplications(entries, preferredIds = []) {
  const apps = [];
  const preferred = new Set(Array.isArray(preferredIds) ? preferredIds : []);
  const seen = new Set();
  for (let i = 0; entries && i < Math.min(entries.length, 2000); i++) {
    const entry = entries[i];
    if (!entry || entry.noDisplay || typeof entry.id !== 'string' || !entry.id
        || typeof entry.name !== 'string' || !entry.name.trim() || seen.has(entry.id)) continue;
    seen.add(entry.id);
    const keywords = [];
    for (let k = 0; entry.keywords && k < Math.min(entry.keywords.length, 100); k++) {
      if (typeof entry.keywords[k] === 'string') keywords.push(entry.keywords[k]);
    }
    if (entry.genericName) keywords.push(String(entry.genericName));
    apps.push({ id: entry.id + '.desktop', name: entry.name, comment: String(entry.comment || ''),
      iconName: String(entry.icon || ''), exec: String(entry.execString || ''), keywords });
  }
  const unique = new Map();
  for (const app of apps) {
    const key = app.exec.trim() ? launchKey(app) : 'id\n' + app.id;
    unique.set(key, unique.has(key) ? preferredCopy(unique.get(key), app, preferred) : app);
  }
  return Array.from(unique.values()).sort((a, b) => a.name.localeCompare(b.name) || a.id.localeCompare(b.id));
}
