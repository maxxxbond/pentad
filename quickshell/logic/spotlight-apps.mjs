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

// Icon names to try, in order, for a launcher entry. Steam writes `steam_icon_<appid>` into game shortcuts
// but only some icon themes ship those, so a game falls back to the Steam icon before the generic one.
export function iconCandidates(name) {
  const icon = String(name || '').trim();
  const names = [icon];
  if (/^steam_icon_\d+$/.test(icon)) names.push('steam');
  names.push('application-x-executable');
  return names.filter(Boolean);
}
