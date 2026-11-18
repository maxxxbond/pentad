import QtQuick
import "../logic/chat.mjs" as ChatLogic
import "../logic/models.mjs" as Models

// Chat sessions per placement. Requests go through services.capabilities (llm.chat): a registry
// role, or for a "custom" placement its own endpoint as a host-internal inline provider. Keys
// never reach QML; the worker resolves the placement's key reference itself.
QtObject {
    id: root
    required property bool preview
    required property bool safeMode
    property var capabilities: null
    property var config: null
    // services.text, for messages produced here.
    property var localize: null
    property var streamOverride: null
    // requestId -> { onDelta, resolve, reject }
    property var streams: ({})
    // config requestId -> handler(result)
    property var saves: ({})
    // instanceId -> true while its quick setup or move runs
    property var busy: ({})
    signal stateChanged(string instanceId, var state)
    // result: { ok: true, assigned } or { ok: false, reason, message }
    signal setupFinished(string instanceId, var result)
    // result: { ok: true, binding } or { ok: false, reason, message }
    signal moveFinished(string instanceId, var result)
    readonly property var manager: ChatLogic.createChatService({
        stream: function (profile, messages, key, cancellation, onDelta) {
            return root.requestStream(profile, messages, key, cancellation, onDelta);
        },
        changed: function (instanceId, state) {
            root.stateChanged(instanceId, state);
        },
        text: function (uk, en) {
            return root.text(uk, en);
        },
        preview: root.preview,
        safeMode: root.safeMode
    })
    function text(uk, en) {
        return typeof localize === 'function' ? localize(uk, en) : en;
    }
    function acquire(instanceId, settings) {
        return manager.acquire(instanceId, settings);
    }
    // The capability options for a profile: a role, or the placement's own endpoint.
    function callOptions(profile, instanceId) {
        const options = {
            instanceId: instanceId,
            role: profile && profile.role === 'fast' ? 'fast' : 'chat'
        };
        if (profile && profile.source === 'custom') {
            const provider = ChatLogic.customProvider(profile);
            if (provider) {
                options.provider = provider;
                options.model = profile.model;
            }
        }
        return options;
    }
    function requestStream(profile, messages, key, cancellation, onDelta) {
        if (root.streamOverride)
            return root.streamOverride(profile, messages, key, cancellation, onDelta);
        return new Promise(function (resolve, reject) {
            if (root.preview || root.safeMode) {
                reject(new Error(root.text('У попередньому перегляді та безпечному режимі чат вимкнено.', 'Chat requests are disabled in preview and safe mode.')));
                return;
            }
            if (!root.capabilities) {
                reject(new Error(ChatLogic.chatFailureMessage({
                    reason: 'service-missing'
                }, root.text)));
                return;
            }
            if (cancellation.isCancelled()) {
                reject(new Error(ChatLogic.chatFailureMessage({
                    reason: 'cancelled'
                }, root.text)));
                return;
            }
            const options = root.callOptions(profile, profile.instanceId);
            if (profile.source === 'custom' && !options.provider) {
                reject(new Error(root.text('Адреса постачальника недійсна.', 'The provider endpoint is not valid.')));
                return;
            }
            const requestId = root.capabilities.call('llm.chat', {
                messages: messages.map(message => ({
                            role: message.role,
                            content: message.content
                        }))
            }, options);
            const next = Object.assign({}, root.streams);
            next[requestId] = {
                onDelta: onDelta,
                resolve: resolve,
                reject: reject,
                stopCancellation: function () {}
            };
            root.streams = next;
            root.streams[requestId].stopCancellation = cancellation.subscribe(function () {
                root.capabilities.cancel(requestId);
                root.settle(requestId, new Error(ChatLogic.chatFailureMessage({
                    reason: 'cancelled'
                }, root.text)));
            });
        });
    }
    // Ends one stream: resolve when error is null, reject otherwise.
    function settle(requestId, error) {
        const entry = streams[requestId];
        if (!entry)
            return;
        const next = Object.assign({}, streams);
        delete next[requestId];
        streams = next;
        entry.stopCancellation();
        if (error)
            entry.reject(error);
        else
            entry.resolve();
    }
    function deliver(requestId, delta) {
        const entry = streams[requestId];
        if (!entry)
            return;
        try {
            entry.onDelta(delta);
        } catch (error) {
            capabilities.cancel(requestId);
            settle(requestId, error instanceof Error ? error : new Error(String(error)));
        }
    }
    property Connections capabilityEvents: Connections {
        target: root.capabilities
        ignoreUnknownSignals: true
        function onPartial(requestId, chunk) {
            if (chunk && typeof chunk.text === 'string' && chunk.text)
                root.deliver(requestId, {
                    type: 'text',
                    text: chunk.text
                });
        }
        function onCommandFinished(requestId, result) {
            if (!root.streams[requestId])
                return;
            if (result && result.ok === true) {
                const reason = result.value && typeof result.value.finishReason === 'string' && result.value.finishReason ? result.value.finishReason : 'stop';
                root.deliver(requestId, {
                    type: 'done',
                    reason: reason
                });
                root.settle(requestId, null);
            } else
                root.settle(requestId, new Error(ChatLogic.chatFailureMessage(result, root.text)));
        }
    }

    // Saves one config document as mutate(current) -> { ok, value, changed } describes it, with
    // one reload and retry when the file changed underneath (`conflict`). done(result, outcome).
    function saveDocument(name, mutate, done, retried) {
        const outcome = mutate(config.documents[name]);
        if (!outcome.ok || outcome.changed === false) {
            done(outcome.ok ? {
                ok: true
            } : outcome, outcome);
            return;
        }
        const requestId = config.save(name, outcome.value);
        expectSave(requestId, function (result) {
            if (result && result.ok === true)
                done({
                    ok: true
                }, outcome);
            else if (result && result.reason === 'conflict' && !retried)
                root.expectSave(root.config.reload(name), function (read) {
                    if (read && read.ok === true)
                        root.saveDocument(name, mutate, done, true);
                    else
                        done(read || {
                            ok: false,
                            reason: 'io'
                        }, outcome);
                });
            else
                done(result || {
                    ok: false,
                    reason: 'io'
                }, outcome);
        });
    }
    function expectSave(requestId, handler) {
        const next = Object.assign({}, saves);
        next[requestId] = handler;
        saves = next;
    }
    property Connections configEvents: Connections {
        target: root.config
        ignoreUnknownSignals: true
        function onCommandFinished(requestId, result) {
            const handler = root.saves[requestId];
            if (!handler)
                return;
            const next = Object.assign({}, root.saves);
            delete next[requestId];
            root.saves = next;
            handler(result);
        }
    }
    function setBusy(instanceId, value) {
        const next = Object.assign({}, busy);
        if (value)
            next[instanceId] = true;
        else
            delete next[instanceId];
        busy = next;
    }
    function writable() {
        if (preview || safeMode)
            return {
                ok: false,
                reason: preview ? 'preview' : 'safe-mode'
            };
        if (!capabilities || !config)
            return {
                ok: false,
                reason: 'service-missing'
            };
        return {
            ok: true
        };
    }

    // Quick setup, one explicit click: list the local Ollama's models and bind them to the empty
    // roles of the models document. Never runs by itself.
    function connectLocalOllama(instanceId) {
        if (busy[instanceId])
            return false;
        const ready = writable();
        if (!ready.ok) {
            Qt.callLater(() => root.setupFinished(instanceId, ready));
            return false;
        }
        setBusy(instanceId, true);
        capabilities.listModels(instanceId, Models.localOllama, function (listed) {
            if (!listed.ok) {
                root.setBusy(instanceId, false);
                root.setupFinished(instanceId, {
                    ok: false,
                    reason: 'unreachable',
                    message: listed.message || listed.reason || ''
                });
                return;
            }
            const models = listed.value && Array.isArray(listed.value.models) ? listed.value.models : [];
            root.saveDocument('models', current => Models.applyLocalSetup(current, models), function (saved, outcome) {
                root.setBusy(instanceId, false);
                root.setupFinished(instanceId, saved.ok ? {
                    ok: true,
                    assigned: outcome.assigned || {}
                } : saved);
            });
        });
        return true;
    }

    // "Move to Models", one explicit click: the placement's own endpoint goes into the models
    // document (its role is bound only when empty), then the placement switches to the registry.
    function moveToModels(instanceId, settings) {
        if (busy[instanceId])
            return false;
        const ready = writable();
        const profile = ChatLogic.chatProfile(settings);
        const provider = ChatLogic.customProvider(profile);
        if (!ready.ok || !provider) {
            Qt.callLater(() => root.moveFinished(instanceId, ready.ok ? {
                    ok: false,
                    reason: 'invalid-input'
                } : ready));
            return false;
        }
        setBusy(instanceId, true);
        saveDocument('models', current => Models.importEndpoint(current, provider, profile.model, profile.role), function (saved, outcome) {
            if (!saved.ok) {
                root.setBusy(instanceId, false);
                root.moveFinished(instanceId, saved);
                return;
            }
            root.saveDocument('layout', current => ChatLogic.layoutWithModelSource(current, instanceId, 'registry'), function (placed) {
                root.setBusy(instanceId, false);
                root.moveFinished(instanceId, placed.ok ? {
                    ok: true,
                    binding: outcome.binding
                } : placed);
            });
        });
        return true;
    }
    Component.onDestruction: {
        manager.dispose();
        for (const requestId of Object.keys(streams))
            if (capabilities)
                capabilities.cancel(requestId);
    }
}
