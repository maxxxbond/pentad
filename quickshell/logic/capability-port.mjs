// The per-instance front of services.capabilities that a widget view or controller receives.
// The host binds it to the capability service and to the instance id it bound to the widget's
// manifest; both live in this closure, so a widget cannot name another instance, reach
// attach/detach, or see calls that are not its own. Qt-free: the QML wrapper is
// plugins/CapabilityFacade.qml.
//
// emit: { progress(id, data), partial(id, chunk), commandFinished(id, result), later(fn) }.
// service: the Capabilities adapter (available/call/cancel/warm/listModels and the three signals
// with connect/disconnect).

const isObject = value => value !== null && typeof value === 'object' && !Array.isArray(value);
const noService = () => ({ ok: false, reason: 'service-missing', message: 'The capability service is not available' });

// Options as the widget passed them, without the instance id: the host supplies that.
function widgetOptions(options) {
  const out = {};
  if (!isObject(options)) return out;
  for (const key of Object.keys(options)) if (key !== 'instanceId') out[key] = options[key];
  return out;
}

// available/warm take (name[, options]); the older (name, instanceId[, options]) form still
// works, with the id ignored.
function trailingOptions(second, third) {
  return isObject(second) ? second : third;
}

export function createCapabilityPort(emit) {
  const out = emit || {};
  const send = (name, id, value) => { if (typeof out[name] === 'function') out[name](id, value); };
  const later = fn => { if (typeof out.later === 'function') out.later(fn); else fn(); };
  let service = null;
  let instanceId = '';
  let own = {};
  let unboundSerial = 0;
  const handlers = {
    progress: (id, data) => { if (own[id] === true) send('progress', id, data); },
    partial: (id, chunk) => { if (own[id] === true) send('partial', id, chunk); },
    commandFinished: (id, result) => {
      if (own[id] !== true) return;
      delete own[id];
      send('commandFinished', id, result);
    }
  };
  const connect = (target, on) => {
    for (const name of Object.keys(handlers)) {
      const signal = target ? target[name] : null;
      if (!signal) continue;
      if (on && typeof signal.connect === 'function') signal.connect(handlers[name]);
      else if (!on && typeof signal.disconnect === 'function') signal.disconnect(handlers[name]);
    }
  };
  return {
    // Host only. bind(null, '') unbinds; calls still running are dropped, not cancelled.
    bind(nextService, nextInstanceId) {
      const target = nextService || null;
      if (target !== service) {
        connect(service, false);
        own = {};
        service = target;
        connect(service, true);
      }
      instanceId = service && typeof nextInstanceId === 'string' ? nextInstanceId : '';
    },
    // Host only: the instance is going away. Its unfinished calls are cancelled.
    release() {
      const ids = Object.keys(own);
      own = {};
      if (service && typeof service.cancel === 'function') for (const id of ids) service.cancel(id);
      connect(service, false);
      service = null;
      instanceId = '';
    },
    bound() { return !!service && instanceId !== ''; },
    state() {
      return service ? service.state : { kind: 'unavailable', reason: 'service-missing' };
    },
    available(name, second, third) {
      if (!service) return { available: false, reason: 'service-missing' };
      return service.available(name, instanceId, widgetOptions(trailingOptions(second, third)));
    },
    call(name, input, options) {
      if (!service) {
        const unbound = 'capability-unbound-' + (++unboundSerial);
        later(() => send('commandFinished', unbound, noService()));
        return unbound;
      }
      const sent = widgetOptions(options);
      sent.instanceId = instanceId;
      const id = service.call(name, input, sent);
      own[id] = true;
      return id;
    },
    cancel(id) {
      if (service && typeof id === 'string' && own[id] === true) service.cancel(id);
    },
    warm(name, second, third) {
      if (!service) return noService();
      return service.warm(name, instanceId, widgetOptions(trailingOptions(second, third)));
    },
    // Host-internal (built-in instances only; the service refuses everyone else).
    // listModels(provider, callback); an older leading instance id is ignored.
    listModels(first, second, third) {
      const legacy = typeof first === 'string';
      const provider = legacy ? second : first;
      const callback = legacy ? third : second;
      if (typeof callback !== 'function') return;
      if (!service || typeof service.listModels !== 'function') {
        later(() => callback(noService()));
        return;
      }
      service.listModels(instanceId, provider, callback);
    }
  };
}
