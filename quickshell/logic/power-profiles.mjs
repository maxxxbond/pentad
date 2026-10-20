const PROFILE = /^[a-z][a-z0-9-]{0,31}$/;

export function parseProfiles(output) {
  if (typeof output !== 'string' || output.length > 16384) throw new Error('invalid-response');
  const profiles = [];
  for (const line of output.split(/\r?\n/)) {
    const match = line.trim().match(/^\*?\s*([a-z][a-z0-9-]{0,31})\s*:/);
    if (match && PROFILE.test(match[1]) && !profiles.includes(match[1])) profiles.push(match[1]);
  }
  if (!profiles.length) throw new Error('service-missing');
  return profiles;
}

export function parseActiveProfile(output, profiles) {
  const active = typeof output === 'string' ? output.trim() : '';
  if (!PROFILE.test(active) || !profiles.includes(active)) throw new Error('invalid-response');
  return active;
}

export function validProfile(profile, profiles) {
  return typeof profile === 'string' && PROFILE.test(profile) && profiles.includes(profile);
}
