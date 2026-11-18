import QtQuick
import "../logic/capabilities.mjs" as Rules
import "../logic/models.mjs" as Models

// services.capabilities (widget API v1): shared capabilities over the model registry and the
// resident worker. Policy lives in logic/capabilities.mjs; this adapter binds loaded views and
// controllers to their manifests, dispatches calls to the worker and relays its signals.
// Every call emits progress(id, { stage: 'started', disclosure }) before the worker gets the
// request, then the worker's progress/partial, then exactly one commandFinished(id, result).
QtObject {
    id: root
    property bool preview: false
    property bool safeMode: false
    property var worker: null
    // The parsed `models` document.
    property var models: Models.modelsDefaults
    // instanceId -> { manifest, builtin, count }: views and controllers of one placement share an id.
    property var bindings: ({})
    // requestId -> { workerId, cancelled }
    property var calls: ({})
    property var warming: ({})
    property int serial: 0
    readonly property var state: preview ? {
        kind: 'unavailable',
        reason: 'preview'
    } : !worker ? {
        kind: 'unavailable',
        reason: 'service-missing'
    } : worker.state === 'unavailable' ? {
        kind: 'unavailable',
        reason: 'unavailable'
    } : {
        kind: 'ready',
        value: {
            worker: worker.state
        }
    }
    signal progress(string requestId, var data)
    signal partial(string requestId, var chunk)
    signal commandFinished(string requestId, var result)

    function registry() {
        const document = root.models;
        return {
            resolveRole: role => Models.resolveRole(document, role),
            providerDisclosure: Models.providerDisclosure,
            models: document
        };
    }
    // Host-internal, not part of widget API v1: a built-in instance may pass `options.provider`
    // (an inline { id, kind, name, baseUrl, credential, credentialEnv }) and `options.model`
    // instead of a registry role, so a chat placement can keep its own endpoint. The provider is
    // checked with the models document rules, every role resolves to it, and the call is still
    // disclosed and consented like a role (privacy.localOnly applies). External widgets get
    // `denied`: a provider they could name would receive the user's key references.
    function registryFor(binding, options) {
        if (!options || options.provider === undefined)
            return {
                ok: true,
                registry: registry()
            };
        if (!binding || binding.builtin !== true)
            return failure('denied', 'Only built-in widgets may name a provider');
        const checked = Models.inlineProvider(options.provider);
        if (!checked.ok)
            return failure(checked.reason, checked.message);
        if (!Models.validModelName(options.model))
            return failure('invalid-input', 'options.model must name a model');
        const provider = checked.provider;
        const model = options.model.trim();
        return {
            ok: true,
            registry: {
                resolveRole: role => ({
                            ok: true,
                            provider: provider,
                            model: model,
                            roleOptions: {}
                        }),
                providerDisclosure: Models.providerDisclosure,
                models: root.models
            }
        };
    }
    function attach(instanceId, manifest, builtin) {
        if (typeof instanceId !== 'string' || !instanceId || !manifest || typeof manifest !== 'object')
            return;
        const previous = bindings[instanceId];
        const next = Object.assign({}, bindings);
        next[instanceId] = {
            manifest: manifest,
            builtin: builtin === true,
            count: previous ? previous.count + 1 : 1
        };
        bindings = next;
    }
    function detach(instanceId) {
        const previous = bindings[instanceId];
        if (!previous)
            return;
        const next = Object.assign({}, bindings);
        if (previous.count > 1)
            next[instanceId] = {
                manifest: previous.manifest,
                builtin: previous.builtin,
                count: previous.count - 1
            };
        else
            delete next[instanceId];
        bindings = next;
    }
    function bound(instanceId) {
        return typeof instanceId === 'string' && Object.prototype.hasOwnProperty.call(bindings, instanceId) ? bindings[instanceId] : null;
    }
    function workerDown() {
        return !worker || worker.state === 'unavailable' || worker.state === 'crash-loop';
    }
    // A user-initiated call gives a worker that went down one fresh start per 30 s window.
    function reviveWorker() {
        if (worker && workerDown() && typeof worker.recover === 'function')
            worker.recover();
    }
    // options (optional, beyond the documented pair): { role } for llm.chat; built-in instances
    // may also pass the host-internal { provider, model } (see registryFor).
    function available(name, instanceId, options) {
        const binding = bound(instanceId);
        const source = registryFor(binding, options);
        if (!source.ok)
            return {
                available: false,
                reason: source.reason
            };
        const result = Rules.availability({
            manifest: binding ? binding.manifest : null,
            builtin: binding ? binding.builtin : false,
            name: name,
            options: options || {},
            registry: source.registry,
            preview: preview,
            safeMode: safeMode
        });
        if (result.available && workerDown()) {
            const down = {
                available: false,
                reason: worker ? 'unavailable' : 'service-missing'
            };
            if (result.disclosure)
                down.disclosure = result.disclosure;
            return down;
        }
        return result;
    }
    function call(name, input, options) {
        const requestId = 'capability-' + (++serial);
        const opts = options && typeof options === 'object' ? options : {};
        const binding = bound(opts.instanceId);
        const source = registryFor(binding, opts);
        if (!source.ok) {
            finishLater(requestId, source);
            return requestId;
        }
        const prepared = Rules.prepareCall({
            manifest: binding ? binding.manifest : null,
            builtin: binding ? binding.builtin : false,
            name: name,
            input: input,
            options: opts,
            registry: source.registry,
            preview: preview,
            safeMode: safeMode
        });
        if (!prepared.ok) {
            finishLater(requestId, failure(prepared.reason, prepared.message));
            return requestId;
        }
        if (!worker) {
            finishLater(requestId, failure('service-missing', 'The worker is not available'));
            return requestId;
        }
        reviveWorker();
        const next = Object.assign({}, calls);
        next[requestId] = {
            workerId: 0,
            cancelled: false
        };
        calls = next;
        Qt.callLater(() => root.dispatch(requestId, prepared));
        return requestId;
    }
    function dispatch(requestId, prepared) {
        const entry = calls[requestId];
        if (!entry)
            return;
        if (entry.cancelled) {
            finish(requestId, failure('cancelled', 'Cancelled'));
            return;
        }
        const disclosure = prepared.disclosure;
        progress(requestId, {
            stage: 'started',
            disclosure: {
                execution: disclosure.execution,
                provider: disclosure.provider,
                host: disclosure.host,
                model: disclosure.model
            }
        });
        if (!calls[requestId])
            return;
        // A listener may have cancelled while handling the started progress.
        if (calls[requestId].cancelled) {
            finish(requestId, failure('cancelled', 'Cancelled'));
            return;
        }
        const workerId = worker.request(prepared.op, prepared.payload, {
            timeoutMs: prepared.timeoutMs,
            onProgress: data => {
                if (root.calls[requestId])
                    root.progress(requestId, data);
            },
            onPartial: chunk => {
                if (root.calls[requestId])
                    root.partial(requestId, chunk);
            },
            onResult: result => root.finish(requestId, result)
        });
        const current = calls[requestId];
        if (current)
            current.workerId = workerId;
    }
    function cancel(requestId) {
        const entry = calls[requestId];
        if (!entry)
            return;
        if (entry.workerId > 0)
            worker.cancel(entry.workerId);
        else
            entry.cancelled = true;
    }
    // Loads the model behind a capability ahead of Run (R14). Returns { ok, warming } or a failure;
    // a no-op for remote providers, local ops and servers other than Ollama.
    // options (optional, beyond the documented pair): { role } for llm.chat, as in available().
    function warm(name, instanceId, options) {
        const binding = bound(instanceId);
        const opts = options && typeof options === 'object' ? options : {};
        const source = registryFor(binding, opts);
        if (!source.ok)
            return source;
        const prepared = Rules.prepareWarm({
            manifest: binding ? binding.manifest : null,
            builtin: binding ? binding.builtin : false,
            name: name,
            options: opts,
            registry: source.registry,
            preview: preview,
            safeMode: safeMode
        });
        if (!prepared.ok)
            return failure(prepared.reason, prepared.message);
        if (prepared.skip)
            return {
                ok: true,
                warming: false
            };
        reviveWorker();
        if (workerDown())
            return failure(worker ? 'unavailable' : 'service-missing', 'The worker is not available');
        const key = prepared.payload.provider.baseUrl + '\n' + prepared.payload.model;
        if (warming[key])
            return {
                ok: true,
                warming: true
            };
        const next = Object.assign({}, warming);
        next[key] = true;
        warming = next;
        worker.request(prepared.op, prepared.payload, {
            timeoutMs: prepared.timeoutMs,
            onResult: () => {
                const done = Object.assign({}, root.warming);
                delete done[key];
                root.warming = done;
            }
        });
        return {
            ok: true,
            warming: true
        };
    }
    // Host-internal, not part of widget API v1: the models a provider offers, for the chat's quick
    // setup and (later) the Models settings page. Built-in instances only, user-initiated, never
    // in preview or safe mode. callback(result) runs exactly once, after this returns, with plain
    // JSON: { ok: true, value: { models: [{ name, sizeBytes?, parameterSize?, capabilities? }] } }
    // or { ok: false, reason, message }.
    function listModels(instanceId, provider, callback) {
        const reply = result => Qt.callLater(() => callback(JSON.parse(JSON.stringify(result))));
        const binding = bound(instanceId);
        if (preview)
            return reply(failure('preview', 'Models are not listed in preview'));
        if (safeMode)
            return reply(failure('safe-mode', 'Models are not listed in safe mode'));
        if (!binding || binding.builtin !== true)
            return reply(failure('denied', 'Only built-in widgets may list models'));
        const checked = Models.inlineProvider(provider);
        if (!checked.ok)
            return reply(failure(checked.reason, checked.message));
        const disclosure = Models.providerDisclosure(checked.provider, '');
        if (disclosure.execution !== 'local' && root.models && root.models.privacy && root.models.privacy.localOnly === true)
            return reply(failure('denied', 'remote models are disabled (local only)'));
        reviveWorker();
        if (workerDown() || !worker.accepts('llm.models'))
            return reply(failure(worker ? 'unavailable' : 'service-missing', 'The worker is not available'));
        const source = checked.provider;
        worker.request('llm.models', {
            provider: {
                kind: source.kind,
                baseUrl: source.baseUrl,
                credential: source.credential,
                credentialEnv: source.credentialEnv
            }
        }, {
            timeoutMs: 60000,
            onResult: result => {
                if (result && result.ok === true)
                    callback(JSON.parse(JSON.stringify({
                        ok: true,
                        value: result.value && typeof result.value === 'object' ? result.value : {}
                    })));
                else
                    callback(failure(result ? result.reason : 'io', result ? result.message : ''));
            }
        });
    }
    // --- Host-internal: the settings window's Models page ---------------------------------------
    // Not part of widget API v1 and never forwarded by CapabilityFacade (which only exposes state,
    // available, call, cancel, warm and listModels), so only code holding this service itself (the
    // shell's hosts and services/ModelSettings.qml) reaches them. Each callback runs exactly once,
    // after the call returns, with plain JSON { ok: true, value } or { ok: false, reason, message }.
    // Network and keyring work (llm.*, secret.*) is refused in preview and safe mode; the local reads
    // (system.vram, worker.stats, worker.clear-cache) only in preview. `revive` gives a worker that
    // went down one fresh start (see Worker.recover); a poll passes false, a click passes true.
    function hostRequest(op, payload, timeoutMs, callback, revive) {
        const reply = result => Qt.callLater(() => callback(JSON.parse(JSON.stringify(result))));
        if (preview)
            return reply(failure('preview', 'The worker does not run in preview'));
        const local = op === 'system.vram' || op === 'worker.stats' || op === 'worker.clear-cache';
        if (safeMode && !local)
            return reply(failure('safe-mode', 'Models and keys are off in safe mode'));
        if (!worker)
            return reply(failure('service-missing', 'The worker is not available'));
        if (revive === true)
            reviveWorker();
        if (workerDown() || !worker.accepts(op))
            return reply(failure(workerDown() ? 'unavailable' : 'unsupported', 'The worker is not available'));
        worker.request(op, payload, {
            timeoutMs: timeoutMs,
            onResult: result => {
                if (result && result.ok === true)
                    callback(JSON.parse(JSON.stringify({
                        ok: true,
                        value: result.value && typeof result.value === 'object' ? result.value : {}
                    })));
                else
                    callback(failure(result ? result.reason : 'io', result ? result.message : ''));
            }
        });
    }
    // A document provider (or an inline one) reduced to what the worker needs: references only.
    function hostProvider(provider) {
        const checked = Models.inlineProvider(provider);
        if (!checked.ok)
            return checked;
        const source = checked.provider;
        return {
            ok: true,
            local: Models.providerDisclosure(source, '').execution === 'local',
            payload: {
                kind: source.kind,
                baseUrl: source.baseUrl,
                credential: source.credential,
                credentialEnv: source.credentialEnv
            }
        };
    }
    // The models a provider offers (llm.models). Like listModels, a remote provider is not asked
    // while privacy.localOnly is on.
    function hostListModels(provider, callback, revive) {
        const checked = hostProvider(provider);
        if (!checked.ok)
            return Qt.callLater(() => callback(failure(checked.reason, checked.message)));
        if (!checked.local && root.models && root.models.privacy && root.models.privacy.localOnly === true)
            return Qt.callLater(() => callback(failure('denied', 'remote models are disabled (local only)')));
        hostRequest('llm.models', {
            provider: checked.payload
        }, 60000, callback, revive);
    }
    // What a local Ollama holds in memory now (llm.loaded, /api/ps). Remote providers are never asked.
    function hostLoadedModels(provider, callback) {
        const checked = hostProvider(provider);
        if (!checked.ok || !checked.local)
            return Qt.callLater(() => callback(checked.ok ? failure('unsupported', 'Only a local server reports loaded models') : failure(checked.reason, checked.message)));
        hostRequest('llm.loaded', {
            provider: checked.payload
        }, 15000, callback, false);
    }
    function hostVram(callback) {
        hostRequest('system.vram', {}, 15000, callback, false);
    }
    function hostWorkerStats(callback) {
        hostRequest('worker.stats', {}, 15000, callback, false);
    }
    function hostClearCache(callback) {
        hostRequest('worker.clear-cache', {}, 30000, callback, true);
    }
    function secretRef(ref) {
        return typeof ref === 'string' && /^secret:\/\/pentad\/[a-z0-9._-]+(?:\/[a-z0-9._-]+)*$/.test(ref);
    }
    function hostSecretStatus(ref, callback) {
        if (!secretRef(ref))
            return Qt.callLater(() => callback(failure('invalid-input', 'Not a secret://pentad/ reference')));
        hostRequest('secret.status', {
            ref: ref
        }, 15000, callback, false);
    }
    // The one request that carries a key: the value goes into the worker payload and nowhere else.
    // It is never logged, stored on this object or echoed in the reply.
    function hostStoreSecret(ref, value, callback) {
        if (!secretRef(ref) || typeof value !== 'string' || value.trim() === '' || value.length > 4096)
            return Qt.callLater(() => callback(failure('invalid-input', 'A key and a secret://pentad/ reference are required')));
        hostRequest('secret.store', {
            ref: ref,
            value: value.trim()
        }, 30000, callback, true);
    }
    function hostClearSecret(ref, callback) {
        if (!secretRef(ref))
            return Qt.callLater(() => callback(failure('invalid-input', 'Not a secret://pentad/ reference')));
        hostRequest('secret.clear', {
            ref: ref
        }, 30000, callback, true);
    }
    // Loads a role's model now (llm.warm) and reports how long that took; a no-op answer
    // { warmed: false } for roles that are empty, remote or not served by Ollama.
    function hostWarmRole(role, callback) {
        const resolved = Models.resolveRole(root.models, role);
        if (!resolved.ok)
            return Qt.callLater(() => callback(failure(resolved.reason, resolved.reason)));
        const checked = hostProvider(resolved.provider);
        if (!checked.ok)
            return Qt.callLater(() => callback(failure(checked.reason, checked.message)));
        if (resolved.provider.kind !== 'ollama' || Models.providerDisclosure(resolved.provider, resolved.model).execution !== 'local')
            return Qt.callLater(() => callback({
                    ok: true,
                    value: {
                        warmed: false
                    }
                }));
        const payload = {
            provider: checked.payload,
            model: resolved.model
        };
        if (resolved.roleOptions && typeof resolved.roleOptions.keepAlive === 'string' && resolved.roleOptions.keepAlive)
            payload.keepAlive = resolved.roleOptions.keepAlive;
        hostRequest('llm.warm', payload, 300000, callback, true);
    }
    function failure(reason, message) {
        return {
            ok: false,
            reason: typeof reason === 'string' && reason ? reason : 'io',
            message: typeof message === 'string' ? message : ''
        };
    }
    function finishLater(requestId, result) {
        Qt.callLater(() => root.commandFinished(requestId, result));
    }
    function finish(requestId, result) {
        if (!calls[requestId])
            return;
        const next = Object.assign({}, calls);
        delete next[requestId];
        calls = next;
        let settled;
        if (result && result.ok === true)
            settled = {
                ok: true,
                value: result.value && typeof result.value === 'object' ? result.value : {},
                cached: result.cached === true
            };
        else
            settled = failure(result ? result.reason : 'io', result ? result.message : '');
        commandFinished(requestId, settled);
    }
    Component.onDestruction: {
        for (const requestId of Object.keys(calls)) {
            const entry = calls[requestId];
            if (entry.workerId > 0 && worker)
                worker.cancel(entry.workerId);
        }
    }
}
