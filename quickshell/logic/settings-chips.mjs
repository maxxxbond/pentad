// Chip sets: a multi-select whose stored value is either a sentinel string (for example 'auto')
// or a non-empty list of choice codes. Pure helpers shared by SettingsChipSet and its tests.

export function selectedChoices(value) {
  return Array.isArray(value) ? value.filter(entry => typeof entry === 'string') : [];
}

// True when nothing explicit is chosen: the sentinel itself, a non-list, or an empty list.
export function isSentinel(value, sentinel = 'auto') {
  return value === sentinel || selectedChoices(value).length === 0;
}

// Adds or removes one code. Removing the last code falls back to the sentinel, so the stored
// value never becomes an empty list. Picks keep the order the user chose them in.
export function toggleChoice(value, code, sentinel = 'auto') {
  const list = selectedChoices(value);
  if (list.includes(code)) {
    const next = list.filter(entry => entry !== code);
    return next.length ? next : sentinel;
  }
  return list.concat([code]);
}
