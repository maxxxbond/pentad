import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { createCapabilityPort } from '../../quickshell/logic/capability-port.mjs';

const read = name => readFileSync(new URL(`../../quickshell/${name}`, import.meta.url), 'utf8');
const list = (source, name) => {
  const match = new RegExp(`readonly property var ${name}: \\[([^\\]]*)\\]`).exec(source);
  assert.ok(match, `${name} list`);
  return match[1].split(',').map(item => item.trim().replace(/^'|'$/g, '')).filter(Boolean);
};

test('the widget services facade forwards every container member except the worker', () => {
  const container = read('services/Services.qml');
  // Top-level members of the container: one indent level inside the root object.
  const properties = [...container.matchAll(/^ {4}(?:readonly )?property [\w.]+ (\w+)\b/gm)].map(match => match[1]);
  const functions = [...container.matchAll(/^ {4}function (\w+)\(/gm)].map(match => match[1]);
  assert.ok(properties.includes('worker') && properties.includes('capabilities') && properties.includes('audio'));
  assert.deepEqual(functions.sort(), ['brightnessFor', 'releaseBrightness', 'text']);

  const facade = read('plugins/WidgetServices.qml');
  const forwarded = list(facade, 'forwarded');
  const builtinOnly = list(facade, 'builtinOnly');
  const withheld = list(facade, 'withheld');
  assert.deepEqual(withheld, ['worker'], 'only the worker is withheld');
  assert.deepEqual(builtinOnly, ['chat']);
  assert.deepEqual([...forwarded, ...builtinOnly, ...withheld, 'capabilities'].sort(), [...properties].sort(),
    'a member added to Services.qml must be forwarded (or deliberately withheld) in WidgetServices.qml');
  assert.deepEqual(list(facade, 'forwardedFunctions').sort(), functions);

  const declared = [...facade.matchAll(/^ {4}property var (\w+)\b/gm)].map(match => match[1]);
  assert.deepEqual(declared.sort(), [...forwarded, ...builtinOnly, ...functions, 'capabilities'].sort(),
    'every forwarded member is a declared property, and nothing else is');
  assert.ok(!declared.includes('worker'));
  // The container is reachable through closures only, never through a property of the facade.
  assert.doesNotMatch(facade, /property (?:var|QtObject|Services) (?:host|source|container)\b/);

  const capabilities = read('plugins/CapabilityFacade.qml');
  const methods = [...capabilities.matchAll(/^ {4}function (\w+)\(/gm)].map(match => match[1]).sort();
  assert.deepEqual(methods, ['available', 'bind', 'call', 'cancel', 'listModels', 'warm']);
  assert.doesNotMatch(capabilities, /\b(attach|detach)\(/);
});

test('every services member a built-in widget reads is forwarded', () => {
  const facade = read('plugins/WidgetServices.qml');
  const known = new Set([...list(facade, 'forwarded'), ...list(facade, 'builtinOnly'), ...list(facade, 'forwardedFunctions'), 'capabilities']);
  const used = new Set();
  const root = new URL('../../quickshell/widgets/', import.meta.url);
  const files = readdirSync(root, { recursive: true }).filter(name => String(name).endsWith('.qml'));
  assert.ok(files.length > 20);
  for (const file of files)
    for (const match of readFileSync(new URL(String(file), root), 'utf8').matchAll(/\bservices\.([A-Za-z]\w*)/g)) used.add(match[1]);
  assert.ok(used.has('text'));
  assert.deepEqual([...used].filter(name => !known.has(name)), []);
});

function fakeService() {
  const signal = () => {
    const listeners = new Set();
    const emit = (...args) => { for (const listener of [...listeners]) listener(...args); };
    emit.connect = listener => listeners.add(listener);
    emit.disconnect = listener => listeners.delete(listener);
    emit.count = () => listeners.size;
    return emit;
  };
  const service = {
    log: [], serial: 0, state: { kind: 'ready', value: { worker: 'idle' } },
    progress: signal(), partial: signal(), commandFinished: signal(),
    available(name, instanceId, options) { this.log.push(['available', name, instanceId, options]); return { available: instanceId === 'mine' }; },
    call(name, input, options) { this.log.push(['call', name, options]); return 'capability-' + (++this.serial); },
    cancel(id) { this.log.push(['cancel', id]); },
    warm(name, instanceId, options) { this.log.push(['warm', name, instanceId, options]); return { ok: true, warming: false }; },
    listModels(instanceId, provider, callback) { this.log.push(['listModels', instanceId, provider]); callback({ ok: true }); },
  };
  return service;
}

test('a capability port always calls as the instance the host bound', () => {
  const service = fakeService();
  const port = createCapabilityPort({});
  port.bind(service, 'mine');
  assert.deepEqual(port.state(), service.state);
  assert.deepEqual(port.available('llm.chat'), { available: true });
  port.available('llm.chat', 'chat-main');
  port.available('llm.chat', 'chat-main', { role: 'fast', instanceId: 'chat-main' });
  port.available('llm.chat', { role: 'fast', instanceId: 'chat-main' });
  port.warm('llm.chat', 'chat-main', { instanceId: 'chat-main' });
  port.warm('llm.chat', { role: 'fast' });
  const options = { instanceId: 'chat-main', role: 'fast' };
  port.call('llm.chat', {}, options);
  port.call('llm.chat', {});
  port.listModels({ kind: 'ollama' }, () => {});
  port.listModels('chat-main', { kind: 'ollama' }, () => {});
  assert.deepEqual(options, { instanceId: 'chat-main', role: 'fast' }, 'the caller\'s options are not mutated');
  assert.deepEqual(service.log, [
    ['available', 'llm.chat', 'mine', {}],
    ['available', 'llm.chat', 'mine', {}],
    ['available', 'llm.chat', 'mine', { role: 'fast' }],
    ['available', 'llm.chat', 'mine', { role: 'fast' }],
    ['warm', 'llm.chat', 'mine', {}],
    ['warm', 'llm.chat', 'mine', { role: 'fast' }],
    ['call', 'llm.chat', { role: 'fast', instanceId: 'mine' }],
    ['call', 'llm.chat', { instanceId: 'mine' }],
    ['listModels', 'mine', { kind: 'ollama' }],
    ['listModels', 'mine', { kind: 'ollama' }],
  ]);
  for (const name of ['attach', 'detach', 'bindings', 'service', 'instanceId']) assert.equal(port[name], undefined, name);
});

test('a capability port relays and cancels only its own requests', () => {
  const service = fakeService();
  const events = [];
  const port = createCapabilityPort({
    progress: (id, data) => events.push(['progress', id, data]),
    partial: (id, chunk) => events.push(['partial', id, chunk]),
    commandFinished: (id, result) => events.push(['finished', id, result]),
  });
  port.bind(service, 'mine');
  const foreign = service.call('llm.chat', {}, { instanceId: 'other' });
  const own = port.call('llm.chat', {}, {});
  service.progress(foreign, { stage: 'started' });
  service.partial(foreign, { text: 'secret' });
  service.commandFinished(foreign, { ok: true, value: { text: 'secret' } });
  service.progress(own, { stage: 'started' });
  service.partial(own, { text: 'hi' });
  service.commandFinished(own, { ok: true, value: { text: 'hi' }, cached: false });
  service.commandFinished(own, { ok: true });
  assert.deepEqual(events, [
    ['progress', own, { stage: 'started' }],
    ['partial', own, { text: 'hi' }],
    ['finished', own, { ok: true, value: { text: 'hi' }, cached: false }],
  ]);
  port.cancel(foreign);
  port.cancel(own);
  assert.deepEqual(service.log.filter(item => item[0] === 'cancel'), [], 'neither a foreign nor a finished id is cancelled');
  const running = port.call('llm.chat', {}, {});
  port.cancel(running);
  assert.deepEqual(service.log.filter(item => item[0] === 'cancel'), [['cancel', running]]);

  // Rebinding to the same service (a settings change) keeps running calls; release cancels them.
  port.bind(service, 'mine');
  assert.equal(service.commandFinished.count(), 1);
  port.release();
  assert.deepEqual(service.log.filter(item => item[0] === 'cancel'), [['cancel', running], ['cancel', running]]);
  assert.equal(service.commandFinished.count(), 0);
  assert.equal(service.progress.count(), 0);
  service.commandFinished(running, { ok: false, reason: 'cancelled' });
  assert.equal(events.length, 3);
});

test('an unbound capability port answers service-missing and never throws', () => {
  const events = [];
  const queue = [];
  const port = createCapabilityPort({ commandFinished: (id, result) => events.push([id, result]), later: fn => queue.push(fn) });
  assert.deepEqual(port.state(), { kind: 'unavailable', reason: 'service-missing' });
  assert.deepEqual(port.available('llm.chat'), { available: false, reason: 'service-missing' });
  assert.equal(port.warm('llm.chat').reason, 'service-missing');
  const id = port.call('llm.chat', {}, {});
  assert.equal(events.length, 0, 'the call returns before its result');
  queue.forEach(fn => fn());
  assert.equal(events[0][0], id);
  assert.equal(events[0][1].reason, 'service-missing');
  let listed = null;
  port.listModels({}, result => { listed = result; });
  queue.at(-1)();
  assert.equal(listed.reason, 'service-missing');
  port.cancel(id);
  port.release();
  const service = fakeService();
  port.bind(service, 'mine');
  port.bind(null, '');
  assert.equal(port.bound(), false);
  assert.equal(service.commandFinished.count(), 0);
});
