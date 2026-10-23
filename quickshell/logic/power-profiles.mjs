// power-profiles-daemon over D-Bus. The Quickshell PowerProfiles singleton observes changes;
// these bounded busctl calls probe availability once, write a profile and read it back.
const PROFILE = /^[a-z][a-z0-9-]{0,31}$/;
const SERVICE = 'org.freedesktop.UPower.PowerProfiles';
const OBJECT = '/org/freedesktop/UPower/PowerProfiles';
const BUSCTL = ['busctl', '--system', '--timeout=2'];
// Display order: fastest first, as `powerprofilesctl list` showed it.
const ORDER = ['performance', 'balanced', 'power-saver'];

export const probeCommand = Object.freeze([...BUSCTL, '--json=short', 'get-property', SERVICE, OBJECT, SERVICE,
  'ActiveProfile', 'Profiles']);
export const readbackCommand = Object.freeze([...BUSCTL, '--json=short', 'get-property', SERVICE, OBJECT, SERVICE,
  'ActiveProfile']);

export function setCommand(profile, profiles) {
  if (!validProfile(profile, profiles)) throw new Error('unavailable');
  return [...BUSCTL, 'set-property', SERVICE, OBJECT, SERVICE, 'ActiveProfile', 's', profile];
}

function values(output) {
  if (typeof output !== 'string' || output.length > 16384) throw new Error('invalid-response');
  try {
    return output.split(/\r?\n/).map((line) => line.trim()).filter(Boolean).map((line) => JSON.parse(line));
  } catch (error) {
    throw new Error('invalid-response');
  }
}

function activeFrom(value, profiles) {
  const active = value && value.type === 's' && typeof value.data === 'string' ? value.data : '';
  if (!PROFILE.test(active) || !profiles.includes(active)) throw new Error('invalid-response');
  return active;
}

export function orderProfiles(profiles) {
  const known = ORDER.filter((profile) => profiles.includes(profile));
  return known.concat(profiles.filter((profile) => !ORDER.includes(profile)));
}

// Output of probeCommand: the active profile, then the list of profile dictionaries.
export function parseProbe(output) {
  const [active, list] = values(output);
  if (!list || list.type !== 'aa{sv}' || !Array.isArray(list.data)) throw new Error('invalid-response');
  const profiles = [];
  for (const entry of list.data) {
    const name = entry && entry.Profile && entry.Profile.type === 's' ? entry.Profile.data : '';
    if (typeof name === 'string' && PROFILE.test(name) && !profiles.includes(name)) profiles.push(name);
  }
  if (!profiles.length) throw new Error('service-missing');
  return { profiles: orderProfiles(profiles), actual: activeFrom(active, profiles) };
}

// Output of readbackCommand.
export function parseReadback(output, profiles) {
  return activeFrom(values(output)[0], profiles);
}

export function validProfile(profile, profiles) {
  return typeof profile === 'string' && PROFILE.test(profile) && profiles.includes(profile);
}
