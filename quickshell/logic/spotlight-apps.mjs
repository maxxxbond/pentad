export function indexApplications(entries) {
  const apps = [];
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
  return apps.sort((a, b) => a.name.localeCompare(b.name) || a.id.localeCompare(b.id));
}
