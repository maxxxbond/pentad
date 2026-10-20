import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';
import { validateSettings } from '../../quickshell/logic/plugin-manifest.mjs';

const source = readFileSync(new URL('../../quickshell/plugins/PluginHost.qml', import.meta.url), 'utf8');
const methods = [...source.matchAll(/^    function \w+\([^\n]*\) \{.*?^    \}/gms)].map(match => match[0]).join('\n');
function fixture() {
  const calls = [];
  const loader = { source: '', status: 0, item: null, setSource(url, properties) {
    this.source = url; this.status = 2; calls.push({ url, properties });
  } };
  const host = vm.createContext({
    componentReady: false, loadedViewSource: '', viewSettings: {}, diagnostic: '',
    moduleId: 'pentad.fake', instanceId: 'fake-1', context: { slot: 'system' },
    entry: { baseUrl: 'file:///fake/', manifest: { entry: 'View.qml', defaults: { size: 4 }, settingsFields: [{ key: 'size', kind: 'integer', min: 1, max: 10 }] } },
    settings: {}, services: { name: 'services' }, controllerWrapper: { item: { name: 'controller' } },
    loader, Loader: { Error: 3 }, Rules: { validateSettings },
  });
  vm.runInContext(methods, host, { timeout: 1000 });
  return { host, loader, calls };
}

test('initial binding changes wait for component completion before creating a widget', () => {
  const { host, calls } = fixture();
  host.loadView();
  assert.equal(calls.length, 0);
  host.componentReady = true;
  host.loadView();
  assert.equal(calls.length, 1);
});

test('registry refresh and settings changes preserve a nested incubating widget', () => {
  const { host, loader, calls } = fixture();
  host.componentReady = true;
  host.loadView();
  host.entry = { ...host.entry, manifest: { ...host.entry.manifest } };
  host.loadView();
  host.settings = { size: 7 };
  host.loadView();
  assert.equal(calls.length, 1, 'same source must not cancel/restart incubation');
  loader.item = {};
  host.syncView();
  assert.equal(loader.item.settings.size, 7);
  assert.equal(loader.item.controller, host.controllerWrapper.item);
});

test('live properties update an existing widget without rebuilding it', () => {
  const { host, loader, calls } = fixture();
  host.componentReady = true;
  host.loadView();
  loader.item = {};
  host.context = { slot: 'activity' };
  host.services = { name: 'replacement services' };
  host.controllerWrapper = { item: { name: 'replacement controller' } };
  host.settings = { size: 9 };
  host.loadView();
  assert.equal(calls.length, 1);
  assert.equal(loader.item.context, host.context);
  assert.equal(loader.item.services, host.services);
  assert.equal(loader.item.controller, host.controllerWrapper.item);
  assert.equal(loader.item.settings.size, 9);
});

test('changed sources and failed loads still reload; invalid settings recover', () => {
  const { host, loader, calls } = fixture();
  host.componentReady = true;
  host.loadView();
  host.entry = { ...host.entry, baseUrl: 'file:///replacement/' };
  host.loadView();
  assert.equal(calls.length, 2);
  loader.status = 3;
  host.loadView();
  assert.equal(calls.length, 3, 'failed view can be retried');
  host.settings = { size: -1 };
  host.loadView();
  assert.equal(loader.source, '');
  assert.match(host.diagnostic, /outside its bounds/);
  host.settings = { size: 3 };
  host.loadView();
  assert.equal(calls.length, 4);
  assert.equal(host.diagnostic, '');
  host.entry = null;
  host.loadView();
  assert.equal(loader.source, '');
  assert.match(host.diagnostic, /unavailable/);
});
