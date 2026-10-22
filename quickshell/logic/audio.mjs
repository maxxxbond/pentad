export function parseWpctlVolume(output) {
  if (typeof output !== 'string' || output.length > 4096) throw new Error('invalid-response');
  const match = output.trim().match(/^Volume:\s*(0(?:\.\d+)?|1(?:\.0+)?)\s*(\[MUTED\])?$/i);
  if (!match) throw new Error('invalid-response');
  return { volume: Math.max(0, Math.min(1, Number(match[1]))), muted: Boolean(match[2]) };
}

export function volumeMatches(actual, desired) {
  return Number.isFinite(actual) && Number.isFinite(desired) && Math.abs(actual - desired) <= 0.015;
}

export function audioDevicePresentation(node) {
  const props = node.properties || {};
  const label = String(node.description || node.nickname || node.name || 'Audio device').trim();
  const shortLabel = String(node.nickname || label).trim()
    .replace(/\s+(?:Analog|Digital) (?:Stereo|Mono)(?=\s*(?:\(|$))/i, '') || label;
  const form = String(props['device.form-factor'] || '').toLowerCase();
  const hint = [props['device.icon-name'], props['device.profile.name'],
    props['api.alsa.path'], node.name, label].filter(Boolean).join(' ').toLowerCase();
  let icon = 'material/volume-up-symbolic.svg';
  if (!node.isSink) icon = 'material/media/mic-symbolic.svg';
  else if (/headphone|headset|earphone|earbud/.test(form)) icon = 'material/headphones-symbolic.svg';
  else if (/speaker/.test(form)) icon = 'material/volume-up-symbolic.svg';
  else if (/tv|display|monitor/.test(form)) icon = 'audio/display-speaker-symbolic.svg';
  else if (/hdmi|displayport/.test(hint)) icon = 'audio/display-speaker-symbolic.svg';
  else if (/headphone|headset|earphone|earbud/.test(hint)) icon = 'material/headphones-symbolic.svg';
  else if (/speaker/.test(hint)) icon = 'material/volume-up-symbolic.svg';
  else if (props['device.api'] === 'bluez5' || props['device.bus'] === 'bluetooth'
    || /bluez|bluetooth/.test(hint)) icon = 'material/bluetooth-symbolic.svg';
  return { label, shortLabel, icon };
}

export function disambiguateAudioDevices(devices) {
  return devices.map(device => devices.some(other => other.id !== device.id
    && other.shortLabel === device.shortLabel)
    ? Object.assign({}, device, { shortLabel: device.label }) : device);
}

// Clamp to 0..1 and round to whole percent.
export function roundVolume(x) {
  return Math.round(Math.max(0, Math.min(1, x)) * 100) / 100;
}

// Volume after `steps` wheel steps (sign gives direction); steps are finer below 10%.
export function adjustedVolume(volume, steps) {
  let next = Math.max(0, Math.min(1, volume));
  const direction = Math.sign(steps);
  for (let i = 0; i < Math.abs(steps); ++i)
    next = Math.max(0, Math.min(1, next + direction * (next < 0.1 ? 0.01 : 0.02)));
  return next;
}

// Index of the device `steps` away from currentId, wrapping around; -1 when currentId is absent or fewer than two devices.
export function nextDeviceIndex(devices, currentId, steps) {
  const index = devices.findIndex(function(device) { return device.id === currentId; });
  if (devices.length < 2 || index < 0) return -1;
  return ((index + steps) % devices.length + devices.length) % devices.length;
}
