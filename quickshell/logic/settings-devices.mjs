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

// Segmented options for the power profiles the power service reports, in its order.
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

const bluetoothReasons = Object.freeze({
  busy: ['Зачекайте, триває інша дія', 'Another action is in progress'],
  timeout: ['Пристрій не відповів вчасно', 'The device did not answer in time'],
  'pairing-failed': ['Не вдалося спарити. Можливо, пристрій просить PIN-код', 'Pairing failed. The device may ask for a PIN'],
  'adapter-unavailable': ['Bluetooth вимкнено або недоступний', 'Bluetooth is off or unavailable'],
  'device-unavailable': ['Пристрій більше недоступний', 'The device is no longer available'],
  preview: ['Лише перегляд', 'Preview only'],
  'safe-mode': ['У безпечному режимі лише читання', 'Read only in safe mode'],
});

// The message under the Bluetooth row for a failed operation reason from QuickSettings.
export function bluetoothError(reason, text) {
  const names = bluetoothReasons[reason];
  return names ? text(names[0], names[1]) : text('Дія Bluetooth не вдалася', 'Bluetooth action failed') + ' (' + (reason || 'failed') + ')';
}

// The icon (in assets/icons/material/devices/) for a Bluetooth device kind from QuickSettings.
const kindIcons = Object.freeze({
  earbuds: 'earbuds', headphones: 'headphones', headset: 'headset-mic', speaker: 'speaker', phone: 'smartphone',
  tablet: 'tablet', laptop: 'computer', computer: 'computer', desktop: 'desktop-windows', keyboard: 'keyboard',
  mouse: 'mouse', gamepad: 'sports-esports', watch: 'watch', tv: 'tv', printer: 'print', camera: 'photo-camera',
});
export function bluetoothKindIcon(kind) {
  // The QML engine has no Object.hasOwn.
  return (Object.prototype.hasOwnProperty.call(kindIcons, kind) ? kindIcons[kind] : 'bluetooth') + '-symbolic.svg';
}

// The main action of a device row, shown as an icon button with a hint.
const deviceActions = Object.freeze({
  pair: { icon: 'add-link-symbolic.svg', names: ['Спарити', 'Pair'] },
  pairing: { icon: 'add-link-symbolic.svg', names: ['Спарювання…', 'Pairing…'] },
  connect: { icon: 'link-symbolic.svg', names: ['Підключити', 'Connect'] },
  disconnect: { icon: 'link-off-symbolic.svg', names: ['Відключити', 'Disconnect'] },
});
export function bluetoothAction(device) {
  const id = !device.paired ? (device.pairing ? 'pairing' : 'pair') : device.connected ? 'disconnect' : 'connect';
  const action = deviceActions[id];
  return { id, icon: action.icon, label: (text) => text(action.names[0], action.names[1]) };
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
