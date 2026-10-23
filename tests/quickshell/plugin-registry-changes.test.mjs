import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';

const source = readFileSync(new URL('../../quickshell/services/Plugins.qml', import.meta.url), 'utf8');
const registerManifest = /^    function registerManifest\([^\n]*\) \{.*?^    \}/ms.exec(source)[0];

function registry() {
  const events = [];
  const context = vm.createContext({
    safeMode: false, catalog: {}, revision: 0,
    Rules: { validateManifest: () => ({ ok: true }) },
    changeNotice: { restart: () => events.push('restart') },
    changed: () => events.push('changed'),
  });
  vm.runInContext(registerManifest, context, { timeout: 1000 });
  return { context, events };
}

test('a burst of manifest loads schedules one change notice instead of emitting per manifest', () => {
  const { context, events } = registry();
  for (const id of ['pentad.clock', 'pentad.telemetry', 'pentad.tools'])
    assert.equal(context.registerManifest({ id, controller: '' }, 'file:///' + id + '/', true).ok, true);
  assert.equal(context.revision, 3);
  assert.deepEqual(Object.keys(context.catalog), ['pentad.clock', 'pentad.telemetry', 'pentad.tools']);
  assert.deepEqual(events, ['restart', 'restart', 'restart']);
});

test('the change notice is a single-shot timer that emits changed()', () => {
  const timer = /property Timer changeNotice: Timer \{([^}]*)\}/.exec(source)?.[1] || '';
  assert.match(timer, /onTriggered: registry\.changed\(\)/);
  assert.doesNotMatch(timer, /repeat: true/);
});

test('a rejected manifest neither changes the catalog nor schedules a notice', () => {
  const { context, events } = registry();
  context.Rules.validateManifest = () => ({ ok: false, errors: ['bad'] });
  assert.equal(context.registerManifest({ id: 'pentad.bad' }, 'file:///bad/', true).ok, false);
  assert.equal(context.revision, 0);
  assert.deepEqual(events, []);
});
