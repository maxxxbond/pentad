import test from 'node:test';
import assert from 'node:assert/strict';
import {
  addAnnotation, createDocument, deleteAnnotation, exportDocument, hitTest,
  imageToView, redo, setCrop, undo, updateAnnotation, viewToImage,
} from '../../quickshell/logic/screenshot.mjs';

const annotation = (id, changes = {}) => ({ id, type: 'rectangle', x: 10, y: 12, width: 30, height: 20, ...changes });

test('creates bounded documents and normalizes reversed, out-of-bounds crops', () => {
  const doc = createDocument(100, 80);
  const cropped = setCrop(doc, { x: 120, y: 70, width: -60, height: -40 });
  assert.deepEqual(cropped.crop, { x: 60, y: 30, width: 40, height: 40 });
  assert.deepEqual(doc.crop, { x: 0, y: 0, width: 100, height: 80 });
  assert.throws(() => createDocument(Infinity, 10), /finite/);
  assert.throws(() => createDocument(16_385, 1), /supported limits/);
  assert.throws(() => createDocument(8_193, 8_192), /supported limits/);
  assert.throws(() => setCrop(doc, { x: 101, y: 0, width: 2, height: 2 }), /positive area/);
});

test('adds, edits and deletes annotations immutably with undo and redo', () => {
  const original = createDocument(100, 80);
  const added = addAnnotation(original, annotation('box', { x: -5, y: 5, width: 20, height: 15 }));
  assert.deepEqual(added.annotations[0], { id: 'box', type: 'rectangle', x: 0, y: 5, width: 15, height: 15, points: [], text: '', color: '#ff0000', strokeWidth: 2, fontSize: 16 });
  const changed = updateAnnotation(added, 'box', { text: 'label', color: '#00ff00' });
  const removed = deleteAnnotation(changed, 'box');
  assert.equal(removed.annotations.length, 0);
  assert.equal(undo(removed).annotations[0].text, 'label');
  assert.equal(redo(undo(removed)).annotations.length, 0);
  assert.equal(original.annotations.length, 0);
  assert.equal(deleteAnnotation(original, 'missing'), original);
});

test('new edits invalidate redo and history is bounded', () => {
  let doc = addAnnotation(createDocument(50, 50), annotation('a'));
  doc = undo(doc);
  doc = addAnnotation(doc, annotation('b'));
  assert.equal(redo(doc), doc);
  for (let i = 0; i < 120; i++) doc = setCrop(doc, { x: 0, y: 0, width: 40 + (i % 10), height: 40 });
  assert.equal(doc.history.length, 100);
});

test('rejects malformed annotation geometry and duplicates', () => {
  const doc = createDocument(100, 80);
  assert.throws(() => addAnnotation(doc, annotation('bad', { x: NaN })), /finite/);
  assert.throws(() => addAnnotation(doc, annotation('bad', { type: 'unknown' })), /unsupported/);
  assert.throws(() => addAnnotation(doc, annotation('bad', { strokeWidth: 0 })), /strokeWidth/);
  assert.throws(() => addAnnotation(doc, annotation('bad', { color: '#abcd' })), /#RRGGBB/);
  assert.throws(() => addAnnotation(doc, annotation('bad', { text: 'x'.repeat(4_097) })), /text exceeds/);
  assert.throws(() => addAnnotation(doc, annotation('bad', { points: Array(10_001).fill({ x: 1, y: 1 }) })), /points/);
  const once = addAnnotation(doc, annotation('same'));
  assert.throws(() => addAnnotation(once, annotation('same')), /already exists/);
});

test('line and arrow vectors preserve right-to-left and bottom-to-top direction', () => {
  let doc = createDocument(100, 80);
  doc = addAnnotation(doc, annotation('left', { type: 'arrow', x: 70, y: 20, width: -40, height: 0 }));
  doc = addAnnotation(doc, annotation('up', { type: 'arrow', x: 25, y: 70, width: 0, height: -50 }));
  doc = addAnnotation(doc, annotation('diag', { type: 'line', x: 80, y: 70, width: -60, height: -50 }));
  assert.deepEqual(doc.annotations.map(({ x, y, width, height }) => ({ x, y, width, height })), [
    { x: 70, y: 20, width: -40, height: 0 },
    { x: 25, y: 70, width: 0, height: -50 },
    { x: 80, y: 70, width: -60, height: -50 },
  ]);
  assert.equal(hitTest(doc, { x: 50, y: 20 }), 'left');
  assert.equal(hitTest(doc, { x: 25, y: 45 }), 'up');
  assert.equal(hitTest(doc, { x: 50, y: 45 }), 'diag');
});

test('hit testing returns the topmost matching annotation and handles strokes', () => {
  let doc = addAnnotation(createDocument(100, 80), annotation('under'));
  doc = addAnnotation(doc, annotation('stroke', { type: 'brush', x: 0, y: 0, width: 0, height: 0, points: [{ x: 50, y: 50 }, { x: 70, y: 50 }] }));
  assert.equal(hitTest(doc, { x: 60, y: 52 }, 1), 'stroke');
  assert.equal(hitTest(doc, { x: 15, y: 15 }), 'under');
  assert.equal(hitTest(doc, { x: 90, y: 70 }), null);
});

test('ellipse hit testing follows its outline rather than its empty interior', () => {
  const doc = addAnnotation(createDocument(100, 80), annotation('ellipse', { type: 'ellipse', x: 10, y: 10, width: 40, height: 20 }));
  assert.equal(hitTest(doc, { x: 30, y: 20 }), null);
  assert.equal(hitTest(doc, { x: 50, y: 20 }), 'ellipse');
});

test('view transforms round-trip fractional scale and offsets', () => {
  const point = { x: 123.75, y: 9.125 }, transform = { scale: 1.25, offsetX: -10.5, offsetY: 6.25 };
  const view = imageToView(point, transform);
  assert.deepEqual(viewToImage(view, transform), point);
  assert.throws(() => imageToView(point, { ...transform, scale: 0 }), /positive/);
});

test('export strips edit history and returns independent image-space data', () => {
  const edited = addAnnotation(setCrop(createDocument(100, 80), { x: 5, y: 6, width: 50, height: 40 }), annotation('a'));
  const exported = exportDocument(edited);
  assert.deepEqual(Object.keys(exported), ['width', 'height', 'crop', 'annotations']);
  assert.deepEqual(exported.crop, { x: 5, y: 6, width: 50, height: 40 });
  exported.annotations[0].points.push({ x: 1, y: 1 });
  assert.equal(edited.annotations[0].points.length, 0);
});

test('fractional crops export all covered pixels without rounding annotation geometry', () => {
  const doc = addAnnotation(setCrop(createDocument(100, 80), {x: 2.5, y: 1.2, width: 10.1, height: 8.5}), annotation('box', {x: 3.5}));
  const result = exportDocument(doc);
  assert.deepEqual(result.crop, {x: 2, y: 1, width: 11, height: 9});
  assert.equal(result.annotations[0].x, 3.5);
  assert.equal(doc.crop.x, 2.5);
  assert.throws(() => createDocument(10.5, 12), /supported limits/);
});

test('undo shares unchanged strokes and later edits preserve older snapshots', () => {
  const points = [{x: 10,y: 10},{x: 30,y: 30}];
  const original = addAnnotation(createDocument(100,80),annotation('stroke',{type:'brush',points}));
  points[0].x = 99;
  const cropped = setCrop(original,{x:0,y:0,width:50,height:50});
  assert.equal(cropped.history.at(-1).annotations[0].points,original.annotations[0].points);
  const moved = updateAnnotation(cropped,'stroke',{points:[{x:15,y:15},{x:35,y:35}]});
  assert.equal(original.annotations[0].points[0].x,10);
  assert.equal(undo(moved).annotations[0].points[0].x,10);
});

test('annotations edited repeatedly accept array-like points from QML var properties', () => {
  let doc = createDocument(200, 100);
  doc = addAnnotation(doc, { id: 't', type: 'text', x: 10, y: 10, width: 40, height: 20, text: 'hi' });
  for (let i = 0; i < 4; i++) {
    const a = doc.annotations[0];
    const arrayLike = { length: 0, 0: undefined };
    doc = updateAnnotation(doc, 't', { x: a.x + 5, y: a.y + 5, points: arrayLike });
  }
  assert.equal(doc.annotations[0].x, 30);
  assert.deepEqual(doc.annotations[0].points, []);
});
