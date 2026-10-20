import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';

const source = readFileSync(new URL('../../quickshell/components/SurfaceRegion.qml', import.meta.url), 'utf8');

function qmlFunction(name) {
  const start = source.indexOf(`function ${name}(`);
  assert.notEqual(start, -1, `missing QML function ${name}`);
  const open = source.indexOf('{', start);
  let depth = 0;
  for (let i = open; i < source.length; i++) {
    if (source[i] === '{') depth++;
    else if (source[i] === '}' && --depth === 0) return source.slice(start, i + 1);
  }
  assert.fail(`unclosed QML function ${name}`);
}

function fixture({ active = true, visible = true } = {}) {
  const events = [];
  const root = {
    disposed: false,
    active,
    originX: 10,
    originY: 20,
    rows: [],
    bands: [],
    surface: {
      visible: active,
      width: 8,
      height: 4,
      contains(point) { return point.x >= 0.5 && point.x < this.width && point.y >= 0.5 && point.y < this.height; },
      Window: { window: { visible, update() {
        events.push({ type: 'frame', rows: root.rows.map(row => ({ x: row.x, y: row.y, width: row.width, height: row.height })) });
      } } },
    },
    rowFactory: { createObject(_parent, band) { return { ...band, destroy() {} }; } },
    changed() { events.push({ type: 'changed', count: root.rows.length }); },
  };
  root.root = root;
  root.Qt = { point: (x, y) => ({ x, y }) };
  const functions = ['requestInputMaskFrame', 'reposition', 'rebuild'].map(qmlFunction).join('\n');
  const context = vm.createContext(root);
  vm.runInContext(functions, context, { timeout: 1000 });
  Object.assign(root, vm.runInContext('({ requestInputMaskFrame, reposition, rebuild })', context, { timeout: 1000 }));
  return { root, events };
}

test('async resize rebuild publishes rows before requesting a native mask frame', () => {
  const { root, events } = fixture();
  root.rebuild();
  events.length = 0;

  root.surface.width = 30;
  root.surface.height = 12;
  root.rebuild();

  assert.equal(root.rows.length, 1);
  assert.deepEqual(JSON.parse(JSON.stringify(root.bands)), [{ x: 0, y: 0, width: 30, height: 12 }]);
  assert.deepEqual(events.map(event => event.type), ['changed', 'frame']);
  assert.equal(events[1].rows[0].width, 30);
  assert.equal(events[1].rows[0].height, 12);
});

test('reposition moves the existing mask rows before requesting a frame', () => {
  const { root, events } = fixture();
  root.rebuild();
  events.length = 0;
  root.originX = 40;
  root.originY = 70;

  root.reposition();

  assert.equal(root.rows[0].x, 40);
  assert.equal(root.rows[0].y, 70);
  assert.deepEqual(events.map(event => event.type), ['changed', 'frame']);
  assert.equal(events[1].rows[0].x, 40);
  assert.equal(events[1].rows[0].y, 70);
});

test('rebuilding an inactive region clears its mask with a frame while the window is visible', () => {
  const { root, events } = fixture();
  root.rebuild();
  assert.equal(root.rows.length, 1);
  events.length = 0;
  root.active = false;

  root.rebuild();

  assert.equal(root.rows.length, 0);
  assert.deepEqual(events.map(event => event.type), ['changed', 'frame']);
  assert.equal(events[1].rows.length, 0);
});

test('hidden windows and disposed regions do not request native frames', () => {

  const hidden = fixture({ visible: false });
  hidden.root.requestInputMaskFrame();
  assert.equal(hidden.events.length, 0);

  const disposed = fixture();
  disposed.root.disposed = true;
  disposed.root.requestInputMaskFrame();
  assert.equal(disposed.events.length, 0);
});
