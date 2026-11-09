import { overnightEnds } from './bar-tools.mjs';

export { overnightEnds };

const isObject = value => value !== null && typeof value === 'object' && !Array.isArray(value);
const defaultEnd = '08:00';

// Epoch ms of the next local occurrence of the chosen time, strictly after nowMs; 0 means no end.
export function endTimestamp(choice, nowMs) {
  if (choice === 'none') return 0;
  const [hours, minutes] = (overnightEnds.includes(choice) ? choice : defaultEnd).split(':').map(Number);
  const end = new Date(nowMs);
  end.setHours(hours, minutes, 0, 0);
  if (end.getTime() <= nowMs) end.setDate(end.getDate() + 1);
  return end.getTime();
}

export const remainingSeconds = (endsAt, nowMs) => endsAt === 0 ? 0 : Math.max(1, Math.ceil((endsAt - nowMs) / 1000));
export const isExpired = (endsAt, nowMs) => endsAt > 0 && nowMs >= endsAt;

export function inhibitCommand(seconds) {
  const length = Number.isInteger(seconds) && seconds > 0 && seconds <= 86400 ? String(seconds) : 'infinity';
  return ['systemd-inhibit', '--what=sleep', '--mode=block', '--who=Pentad', '--why=Overnight mode', 'sleep', length];
}

// Exit 7 with nothing printed when openrazer is not installed or its daemon is unreachable.
const razerRead = `import json, sys
try:
    from openrazer.client import DeviceManager
    devices = DeviceManager().devices
except Exception:
    sys.exit(7)
print(json.dumps([{"serial": d.serial, "brightness": d.brightness} for d in devices if d.has("brightness")]))`;

const razerSet = `import json, sys
try:
    from openrazer.client import DeviceManager
    devices = DeviceManager().devices
except Exception:
    sys.exit(7)
levels = {e["serial"]: max(0, min(100, float(e["brightness"]))) for e in json.loads(sys.argv[1])}
for d in devices:
    if d.serial in levels and d.has("brightness"):
        d.brightness = levels[d.serial]`;

export const razerReadCommand = () => ['python3', '-c', razerRead];

export function parseRazer(stdout) {
  let list;
  try { list = JSON.parse(String(stdout)); } catch { return null; }
  if (!Array.isArray(list)) return null;
  const entries = [];
  for (const item of list) {
    if (!isObject(item) || typeof item.serial !== 'string' || typeof item.brightness !== 'number' || !Number.isFinite(item.brightness)) return null;
    entries.push({ serial: item.serial, brightness: item.brightness });
  }
  return entries;
}

export const razerSetCommand = entries => ['python3', '-c', razerSet, JSON.stringify(entries.map(entry => ({
  serial: String(entry.serial), brightness: Math.max(0, Math.min(100, Number(entry.brightness) || 0)),
})))];

export const openrgbCommand = profile => typeof profile === 'string' && /^[\w .-]{1,64}$/.test(profile) ? ['openrgb', '--profile', profile] : null;

export const userCommand = text => typeof text === 'string' && text.trim() ? ['timeout', '10', 'sh', '-c', text] : null;

export const dpmsOffCommand = () => ['hyprctl', 'dispatch', 'hl.dsp.dpms({ action = "disable" })'];

export const serializeState = state => JSON.stringify(state);

const optionalBool = value => value === null || typeof value === 'boolean';
const validRazer = list => Array.isArray(list) && list.every(item => isObject(item) && typeof item.serial === 'string' && typeof item.brightness === 'number');

// { ok: true, value } for a state, { ok: true, value: null } for no state, { ok: false, reason } otherwise.
export function parseState(text) {
  if (text === undefined || text === null || !String(text).trim()) return { ok: true, value: null };
  let state;
  try { state = JSON.parse(String(text)); } catch { return { ok: false, reason: 'not valid JSON' }; }
  if (!isObject(state)) return { ok: false, reason: 'not an object' };
  if (state.version !== 1) return { ok: false, reason: 'unsupported version' };
  if (!Number.isFinite(state.startedAt) || !Number.isFinite(state.endsAt) || state.endsAt < 0) return { ok: false, reason: 'invalid times' };
  const { prior, applied } = state;
  if (!isObject(prior) || typeof prior.profile !== 'string' || !optionalBool(prior.muted) || !optionalBool(prior.dnd) || !validRazer(prior.razer))
    return { ok: false, reason: 'invalid prior state' };
  if (!isObject(applied) || typeof applied.profile !== 'string' || !optionalBool(applied.muted) || !optionalBool(applied.dnd)
    || typeof applied.razer !== 'boolean' || typeof applied.openrgb !== 'boolean' || typeof applied.command !== 'boolean')
    return { ok: false, reason: 'invalid applied state' };
  return { ok: true, value: state };
}

// Ordered undo steps. A setting is only restored while it still holds what the mode applied.
export function restorePlan(state, current, config) {
  const { prior, applied } = state;
  const plan = [];
  if (applied.command && config.commands.end.trim()) plan.push({ step: 'command', value: config.commands.end });
  if (applied.openrgb) plan.push({ step: 'openrgb', value: config.openrgb.end });
  if (applied.razer) plan.push({ step: 'razer', value: prior.razer });
  for (const step of ['dnd', 'muted', 'profile'])
    if (applied[step] !== null && applied[step] !== '' && current[step] === applied[step]) plan.push({ step, value: prior[step] });
  return plan;
}
