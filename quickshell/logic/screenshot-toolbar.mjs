export const TOOLBAR_GAP = 10;
export const TOOLBAR_MARGIN = 8;

const EDGES = ['top', 'bottom', 'left', 'right'];
const clamp = (value, low, high) => Math.max(low, Math.min(high, value));
const finite = value => typeof value === 'number' && Number.isFinite(value);

function normalRect(rect) {
  if (!rect || ![rect.x, rect.y, rect.width, rect.height].every(finite)) return { x: 0, y: 0, width: 0, height: 0 };
  return { x: rect.x, y: rect.y, width: Math.max(0, rect.width), height: Math.max(0, rect.height) };
}

export function isHorizontalEdge(edge) {
  return edge === 'top' || edge === 'bottom';
}

export function normalizeDock(dock) {
  return {
    edge: EDGES.includes(dock?.edge) ? dock.edge : 'bottom',
    t: finite(dock?.t) ? clamp(dock.t, 0, 1) : 0.5,
    inside: dock?.inside === true,
  };
}

function sizeFor(edge, length, thickness) {
  return isHorizontalEdge(edge) ? { width: length, height: thickness } : { width: thickness, height: length };
}

function outsideRoom(rect, bounds, edge) {
  if (edge === 'top') return rect.y;
  if (edge === 'bottom') return bounds.height - rect.y - rect.height;
  if (edge === 'left') return rect.x;
  return bounds.width - rect.x - rect.width;
}

function fitsOutside(rect, bounds, edge, thickness) {
  return outsideRoom(rect, bounds, edge) >= thickness + TOOLBAR_GAP + TOOLBAR_MARGIN;
}

export function defaultDock(rect, bounds, length, thickness) {
  const r = normalRect(rect);
  for (const edge of ['bottom', 'top'])
    if (fitsOutside(r, bounds, edge, thickness)) return { edge, t: 0.5, inside: false };
  return { edge: 'bottom', t: 0.5, inside: true };
}

// Vertical panels prefer the right edge of the area, then the left, and sit inside only when neither fits.
export function defaultSideDock(rect, bounds, length, thickness) {
  const r = normalRect(rect);
  for (const edge of ['right', 'left'])
    if (fitsOutside(r, bounds, edge, thickness)) return { edge, t: 0.5, inside: false };
  return { edge: 'right', t: 0.5, inside: true };
}

export function dockGeometry(rect, bounds, length, thickness, dock) {
  const r = normalRect(rect);
  const d = normalizeDock(dock);
  const inside = d.inside || !fitsOutside(r, bounds, d.edge, thickness);
  const size = sizeFor(d.edge, length, thickness);
  let x, y;
  if (isHorizontalEdge(d.edge)) {
    x = r.x + d.t * r.width - size.width / 2;
    if (d.edge === 'top') y = inside ? r.y + TOOLBAR_GAP : r.y - TOOLBAR_GAP - size.height;
    else y = inside ? r.y + r.height - TOOLBAR_GAP - size.height : r.y + r.height + TOOLBAR_GAP;
  } else {
    y = r.y + d.t * r.height - size.height / 2;
    if (d.edge === 'left') x = inside ? r.x + TOOLBAR_GAP : r.x - TOOLBAR_GAP - size.width;
    else x = inside ? r.x + r.width - TOOLBAR_GAP - size.width : r.x + r.width + TOOLBAR_GAP;
  }
  x = clamp(x, TOOLBAR_MARGIN, Math.max(TOOLBAR_MARGIN, bounds.width - size.width - TOOLBAR_MARGIN));
  y = clamp(y, TOOLBAR_MARGIN, Math.max(TOOLBAR_MARGIN, bounds.height - size.height - TOOLBAR_MARGIN));
  return { x, y, width: size.width, height: size.height, horizontal: isHorizontalEdge(d.edge), edge: d.edge, inside };
}

export function dockFromPointer(rect, pointer, length, grabAlong) {
  const r = normalRect(rect);
  const p = { x: finite(pointer?.x) ? pointer.x : 0, y: finite(pointer?.y) ? pointer.y : 0 };
  const excess = {
    top: r.y - p.y,
    bottom: p.y - r.y - r.height,
    left: r.x - p.x,
    right: p.x - r.x - r.width,
  };
  const inside = EDGES.every(edge => excess[edge] <= 0);
  const edge = EDGES.reduce((best, item) => excess[item] > excess[best] ? item : best, 'top');
  const centreShift = (finite(length) ? length : 0) / 2 - (finite(grabAlong) ? grabAlong : 0);
  const horizontal = isHorizontalEdge(edge);
  const span = horizontal ? r.width : r.height;
  const along = (horizontal ? p.x - r.x : p.y - r.y) + centreShift;
  return { edge, t: span > 0 ? clamp(along / span, 0, 1) : 0.5, inside };
}
