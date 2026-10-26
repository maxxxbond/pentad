// Shared by every PentadHint in the engine: while a hint is on screen, or was a moment ago,
// the next one shows at once, so sweeping across a row of controls does not wait at each of them.
export const warmWindow = 600;
let shown = 0;
let cooledAt = -Infinity;

export function hintShown() {
  shown += 1;
}

export function hintHidden(now = Date.now()) {
  shown = Math.max(0, shown - 1);
  if (shown === 0) cooledAt = now;
}

export function hintsWarm(now = Date.now()) {
  return shown > 0 || now - cooledAt < warmWindow;
}

export function resetHintWarmth() {
  shown = 0;
  cooledAt = -Infinity;
}
