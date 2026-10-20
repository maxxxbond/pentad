export function trayAvailability(items) {
  if (!Array.isArray(items)) return { kind: 'unavailable', reason: 'binding-missing' };
  return { kind: 'ready', value: { items } };
}

export function trayIconMode(value) {
  return value === 'color' || value === 'monochrome' || value === 'soft' ? value : 'soft';
}

export function trayTooltip(item) {
  if (!item) return '';
  return [item.tooltipTitle, item.tooltipDescription].filter(function(part) {
    return typeof part === 'string' && part.length > 0;
  }).join('\n');
}
