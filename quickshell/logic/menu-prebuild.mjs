// Bar menus built ahead of time. In the "speed" mode (the default) every output builds its drawers
// once the shell has settled, one surface per step, control centers first; in the "memory" mode they
// are built only when hovered or opened.
export const barMenuModes = Object.freeze(['speed', 'memory']);
export const prebuildOrder = Object.freeze(['right', 'left', 'activity']);

export function prebuildEnabled(interfaceDocument) {
  return !interfaceDocument || interfaceDocument.barMenus !== 'memory';
}

// outputs: one entry per bar, in output order: { due: boolean, prepared: { right, left, activity } },
// or null for a bar that cannot build ahead of time. Returns the next { index, side } or null.
export function nextPrebuild(outputs) {
  const list = Array.isArray(outputs) ? outputs : [];
  for (const side of prebuildOrder) {
    for (let index = 0; index < list.length; index++) {
      const output = list[index];
      if (output && output.due === true && output.prepared && output.prepared[side] !== true) return { index, side };
    }
  }
  return null;
}
