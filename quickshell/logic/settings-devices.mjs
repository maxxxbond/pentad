// Presentation helpers for the device pages of the settings window (Network, Sound, Power).

const profileNames = Object.freeze({
  'power-saver': ['Економія', 'Power saver'],
  balanced: ['Збалансований', 'Balanced'],
  performance: ['Продуктивність', 'Performance'],
});
const batteryStates = Object.freeze({
  charging: ['Заряджається', 'Charging'],
  discharging: ['Розряджається', 'Discharging'],
  full: ['Заряджено', 'Fully charged'],
});

// Segmented options for the power profiles powerprofilesctl reports, in its order.
export function profileOptions(profiles, text) {
  if (!Array.isArray(profiles)) return [];
  return profiles.filter(id => typeof id === 'string' && id !== '').map(id => {
    const names = profileNames[id];
    return { value: id, label: names ? text(names[0], names[1]) : id };
  });
}

// One line for the battery row: "64 % · Розряджається", or null without a battery.
export function batterySummary(battery, text) {
  if (!battery || typeof battery !== 'object') return null;
  const state = batteryStates[battery.state];
  const percent = Number.isFinite(battery.percent) ? Math.round(battery.percent) + ' %' : text('Невідомо', 'Unknown');
  return state ? percent + ' · ' + text(state[0], state[1]) : percent;
}

// Outputs that get a brightness row, by Hyprland name; specials and duplicates are skipped.
export function brightnessOutputs(state) {
  if (!state || state.kind !== 'ready' || !state.value || !Array.isArray(state.value.outputs)) return [];
  const seen = new Set();
  return state.value.outputs.filter(output => {
    if (!output || typeof output.name !== 'string' || output.name === '' || seen.has(output.name)) return false;
    seen.add(output.name);
    return true;
  }).map(output => output.name);
}
