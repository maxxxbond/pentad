const TYPES = new Set(['brush', 'line', 'arrow', 'rectangle', 'ellipse', 'text', 'highlight', 'redact']);
const MAX_DIMENSION = 16_384;
const MAX_PIXELS = 64 * 1024 * 1024;
const MAX_POINTS = 10_000;
const MAX_TOTAL_POINTS = 100_000;
const MAX_ANNOTATIONS = 1_000;
const MAX_TEXT_LENGTH = 4_096;
const MAX_HISTORY = 100;

const finite = (value, name) => {
  if (!Number.isFinite(value)) throw new TypeError(`${name} must be finite`);
  return value;
};

function dimensions(width, height) {
  finite(width, 'width'); finite(height, 'height');
  if (!Number.isInteger(width) || !Number.isInteger(height) || width <= 0 || height <= 0 || width > MAX_DIMENSION || height > MAX_DIMENSION || width * height > MAX_PIXELS)
    throw new RangeError('image dimensions are outside supported limits');
}

const clonePoint = (point) => ({ x: point.x, y: point.y });
const cloneAnnotation = (annotation) => Object.assign({}, annotation, { points: annotation.points.map(clonePoint) });
const snapshot = (doc) => ({ crop: Object.assign({}, doc.crop), annotations: doc.annotations.slice() });
const restore = (doc, state, history, future) => ({
  width: doc.width, height: doc.height, crop: Object.assign({}, state.crop),
  annotations: state.annotations.slice(), history, future,
});

function bounded(value, max) { return Math.max(0, Math.min(max, value)); }

function normalizeRect(rect, width, height, allowEmpty = false) {
  if (!rect || typeof rect !== 'object') throw new TypeError('rectangle must be an object');
  let x = finite(rect.x, 'x'), y = finite(rect.y, 'y');
  let right = x + finite(rect.width, 'width'), bottom = y + finite(rect.height, 'height');
  if (!Number.isFinite(right) || !Number.isFinite(bottom)) throw new RangeError('rectangle is outside supported limits');
  if (right < x) [x, right] = [right, x];
  if (bottom < y) [y, bottom] = [bottom, y];
  x = bounded(x, width); right = bounded(right, width);
  y = bounded(y, height); bottom = bounded(bottom, height);
  const result = { x, y, width: right - x, height: bottom - y };
  if (!allowEmpty && (result.width <= 0 || result.height <= 0)) throw new RangeError('rectangle must intersect the image with positive area');
  return result;
}

function normalizeAnnotation(input, width, height) {
  if (!input || typeof input !== 'object') throw new TypeError('annotation must be an object');
  if (typeof input.id !== 'string' || !input.id) throw new TypeError('annotation id must be a non-empty string');
  if (!TYPES.has(input.type)) throw new RangeError('unsupported annotation type');
  let rect;
  if (input.type === 'line' || input.type === 'arrow') {
    const x = finite(input.x, 'x'), y = finite(input.y, 'y');
    const endX = x + finite(input.width, 'width'), endY = y + finite(input.height, 'height');
    if (!Number.isFinite(endX) || !Number.isFinite(endY)) throw new RangeError('annotation endpoint is outside supported limits');
    const startX = bounded(x, width), startY = bounded(y, height);
    rect = { x: startX, y: startY, width: bounded(endX, width) - startX, height: bounded(endY, height) - startY };
  } else {
    rect = normalizeRect(input, width, height, true);
  }
  // Arrays that went through a QML `var` property come back as array-likes, not real Arrays.
  const raw = input.points ?? [];
  const points = Array.isArray(raw) ? raw : raw && Number.isInteger(raw.length) && typeof raw !== 'string' ? Array.from(raw) : null;
  if (!points || points.length > MAX_POINTS) throw new RangeError('annotation points exceed supported limits');
  const normalizedPoints = points.map((point) => ({
    x: bounded(finite(point?.x, 'point.x'), width),
    y: bounded(finite(point?.y, 'point.y'), height),
  }));
  const strokeWidth = input.strokeWidth ?? 2;
  const fontSize = input.fontSize ?? 16;
  if (!Number.isFinite(strokeWidth) || strokeWidth <= 0 || strokeWidth > 1000) throw new RangeError('strokeWidth is outside supported limits');
  if (!Number.isFinite(fontSize) || fontSize <= 0 || fontSize > 1000) throw new RangeError('fontSize is outside supported limits');
  const text = input.text ?? '';
  const color = input.color ?? '#ff0000';
  if (typeof text !== 'string') throw new TypeError('annotation text must be a string');
  if (text.length > MAX_TEXT_LENGTH) throw new RangeError('annotation text exceeds supported limits');
  if (typeof color !== 'string' || !/^#[0-9a-fA-F]{6}$/.test(color)) throw new TypeError('annotation color must be #RRGGBB');
  return Object.assign({}, rect, {
    id: input.id, type: input.type, points: normalizedPoints,
    text, color, strokeWidth, fontSize,
  });
}

function edited(doc, crop, annotations) {
  const history = doc.history.concat([snapshot(doc)]).slice(-MAX_HISTORY);
  return Object.assign({}, doc, { crop: Object.assign({}, crop), annotations: annotations.slice(), history, future: [] });
}

export function createDocument(width, height) {
  dimensions(width, height);
  return { width, height, crop: { x: 0, y: 0, width, height }, annotations: [], history: [], future: [] };
}

export function setCrop(doc, rect) {
  const crop = normalizeRect(rect, doc.width, doc.height);
  return edited(doc, crop, doc.annotations);
}

export function addAnnotation(doc, annotation) {
  if (doc.annotations.length >= MAX_ANNOTATIONS) throw new RangeError('annotation count exceeds supported limits');
  const value = normalizeAnnotation(annotation, doc.width, doc.height);
  if (doc.annotations.some((item) => item.id === value.id)) throw new RangeError(`annotation id already exists: ${value.id}`);
  if (doc.annotations.reduce((total, item) => total + item.points.length, value.points.length) > MAX_TOTAL_POINTS)
    throw new RangeError('annotation points exceed supported limits');
  return edited(doc, doc.crop, doc.annotations.concat([value]));
}

export function updateAnnotation(doc, id, patch) {
  const index = doc.annotations.findIndex((item) => item.id === id);
  if (index < 0) return doc;
  if (!patch || typeof patch !== 'object') throw new TypeError('patch must be an object');
  const value = normalizeAnnotation(Object.assign({}, doc.annotations[index], patch, { id }), doc.width, doc.height);
  if (doc.annotations.reduce((total, item, itemIndex) => total + (itemIndex === index ? value.points.length : item.points.length), 0) > MAX_TOTAL_POINTS)
    throw new RangeError('annotation points exceed supported limits');
  const annotations = doc.annotations.slice(); annotations[index] = value;
  return edited(doc, doc.crop, annotations);
}

export function deleteAnnotation(doc, id) {
  const annotations = doc.annotations.filter((item) => item.id !== id);
  return annotations.length === doc.annotations.length ? doc : edited(doc, doc.crop, annotations);
}

export function undo(doc) {
  if (!doc.history.length) return doc;
  return restore(doc, doc.history[doc.history.length - 1], doc.history.slice(0, -1), [snapshot(doc)].concat(doc.future).slice(0, MAX_HISTORY));
}

export function redo(doc) {
  if (!doc.future.length) return doc;
  return restore(doc, doc.future[0], doc.history.concat([snapshot(doc)]).slice(-MAX_HISTORY), doc.future.slice(1));
}

function distanceToSegment(point, a, b) {
  const dx = b.x - a.x, dy = b.y - a.y;
  const length = dx * dx + dy * dy;
  const t = length ? Math.max(0, Math.min(1, ((point.x - a.x) * dx + (point.y - a.y) * dy) / length)) : 0;
  return Math.hypot(point.x - (a.x + t * dx), point.y - (a.y + t * dy));
}

function contains(annotation, point, tolerance) {
  const { x, y, width, height, type, points, strokeWidth } = annotation;
  const radius = tolerance + strokeWidth / 2;
  if (type === 'brush' && points.length) {
    if (points.length === 1) return Math.hypot(point.x - points[0].x, point.y - points[0].y) <= radius;
    return points.slice(1).some((p, i) => distanceToSegment(point, points[i], p) <= radius);
  }
  if (type === 'line' || type === 'arrow') return distanceToSegment(point, { x, y }, { x: x + width, y: y + height }) <= radius;
  if (type === 'brush') return false;
  if (type === 'ellipse') {
    if (!width || !height) return Math.hypot(point.x - x, point.y - y) <= radius;
    const nx = (point.x - (x + width / 2)) / (width / 2), ny = (point.y - (y + height / 2)) / (height / 2);
    return Math.abs(Math.hypot(nx, ny) - 1) * Math.min(width, height) / 2 <= radius;
  }
  if (type === 'rectangle') return point.x >= x - radius && point.x <= x + width + radius && point.y >= y - radius && point.y <= y + height + radius;
  return point.x >= x - tolerance && point.x <= x + width + tolerance && point.y >= y - tolerance && point.y <= y + height + tolerance;
}

export function hitTest(doc, point, tolerance = 0) {
  finite(point?.x, 'point.x'); finite(point?.y, 'point.y'); finite(tolerance, 'tolerance');
  if (tolerance < 0) throw new RangeError('tolerance must be non-negative');
  for (let i = doc.annotations.length - 1; i >= 0; i--) if (contains(doc.annotations[i], point, tolerance)) return doc.annotations[i].id;
  return null;
}

function transformPoint(point, transform, inverse) {
  const x = finite(point?.x, 'point.x'), y = finite(point?.y, 'point.y');
  const scale = finite(transform?.scale, 'scale'), offsetX = finite(transform?.offsetX, 'offsetX'), offsetY = finite(transform?.offsetY, 'offsetY');
  if (scale <= 0) throw new RangeError('scale must be positive');
  return inverse ? { x: (x - offsetX) / scale, y: (y - offsetY) / scale } : { x: x * scale + offsetX, y: y * scale + offsetY };
}

export function viewToImage(point, transform) { return transformPoint(point, transform, true); }
export function imageToView(point, transform) { return transformPoint(point, transform, false); }

export function exportDocument(doc) {
  const x = Math.floor(doc.crop.x), y = Math.floor(doc.crop.y);
  const right = Math.min(doc.width, Math.ceil(doc.crop.x + doc.crop.width));
  const bottom = Math.min(doc.height, Math.ceil(doc.crop.y + doc.crop.height));
  return { width: doc.width, height: doc.height, crop: { x, y, width: right - x, height: bottom - y }, annotations: doc.annotations.map(cloneAnnotation) };
}
