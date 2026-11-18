import QtQuick
import QtQml
import Quickshell
import Quickshell.Io
import qs.theme
import qs.components
import qs.services
import qs.plugins
import "../logic/models.mjs" as Models

// The chat on the model registry: the setup card and its one-click local Ollama setup, the
// disclosure line, streaming through services.capabilities, a placement's own endpoint as an
// inline provider, "Move to Models", warm-up once per presentation when the composer is engaged and the translate tool in
// safe mode. The real Chat, Capabilities and Plugins services run against a fake worker and a
// fake config store, so nothing reaches Ollama, the network or the user's files.
ShellRoot {
    id: root
    readonly property string capture: Quickshell.env('PENTAD_ARTIFACT_PATH')
    readonly property string appearance: Quickshell.env('PENTAD_GALLERY_APPEARANCE') === 'light' ? 'light' : 'dark'
    property string language: 'uk'
    property var checks: []
    property int step: 0
    property int ticks: 0
    property bool finished: false
    property int captures: 0
    property var placements: [
        {
            instanceId: 'chat-main',
            moduleId: 'pentad.chat',
            slot: 'sidebar-left',
            enabled: true,
            settings: {
                modelSource: 'registry',
                modelRole: 'chat'
            }
        },
        {
            instanceId: 'chat-custom',
            moduleId: 'pentad.chat',
            slot: 'sidebar-left',
            enabled: true,
            settings: {
                modelSource: 'custom',
                provider: 'ollama',
                baseUrl: 'http://127.0.0.1:11434',
                model: 'llama3.2:3b'
            }
        },
        {
            instanceId: 'chat-remote',
            moduleId: 'pentad.chat',
            slot: 'sidebar-left',
            enabled: true,
            settings: {
                modelSource: 'custom',
                modelRole: 'fast',
                provider: 'api',
                baseUrl: 'https://api.openai.com/v1',
                model: 'gpt-4o',
                credentialRef: 'pentad-chat-api',
                apiKeyEnv: 'OPENAI_API_KEY'
            }
        },
        {
            instanceId: 'translate-main',
            moduleId: 'pentad.translate',
            slot: 'sidebar-left',
            enabled: true,
            settings: {}
        }
    ]
    function settingsOf(id) {
        const placement = placements.find(item => item.instanceId === id);
        return placement ? placement.settings : ({});
    }
    function check(name, passed, detail) {
        checks.push({
            name: name,
            passed: passed === true,
            detail: detail === undefined ? '' : typeof detail === 'string' ? detail : JSON.stringify(detail)
        });
    }
    function findNamed(item, name) {
        if (!item)
            return null;
        if (item.objectName === name)
            return item;
        const children = item.children || [];
        for (let index = 0; index < children.length; index++) {
            const found = findNamed(children[index], name);
            if (found)
                return found;
        }
        return null;
    }
    function snapshot(item, name) {
        if (!capture || !item)
            return;
        captures++;
        item.grabToImage(function (result) {
            result.saveToFile(name ? root.capture + '.' + name + '.png' : root.capture);
            root.captures--;
        });
    }
    function requestsFor(op) {
        return fakeWorker.requests.filter(item => item.op === op);
    }

    // The resident worker, faked: answers the ops the chat and translate tools use.
    property QtObject fakeWorker: QtObject {
        property string state: 'ready'
        property bool ollamaUp: true
        property int serial: 0
        property var requests: []
        property var cancelled: []
        readonly property var models: [
            {
                name: 'qwen3.8:latest',
                sizeBytes: 17700000000,
                capabilities: ['completion', 'tools']
            },
            {
                name: 'gpt-oss:120b-cloud',
                sizeBytes: 384,
                capabilities: ['completion', 'tools', 'thinking']
            },
            {
                name: 'embeddinggemma-2:270m',
                sizeBytes: 300000000,
                capabilities: ['embedding']
            },
            {
                name: 'qwen3.5:9b',
                sizeBytes: 6600000000,
                capabilities: ['completion', 'vision', 'tools', 'thinking']
            },
            {
                name: 'qwen3.5:0.8b',
                sizeBytes: 1300000000,
                capabilities: ['completion', 'vision', 'tools', 'thinking']
            }
        ]
        function accepts(op) {
            return true;
        }
        function cancel(id) {
            cancelled = cancelled.concat([id]);
        }
        function request(op, payload, callbacks) {
            const id = ++serial;
            requests = requests.concat([
                {
                    id: id,
                    op: op,
                    payload: JSON.parse(JSON.stringify(payload))
                }
            ]);
            Qt.callLater(() => respond(op, payload, callbacks || {}));
            return id;
        }
        function respond(op, payload, callbacks) {
            const done = value => callbacks.onResult({
                    ok: true,
                    value: value,
                    cached: false
                });
            if (op === 'llm.models') {
                if (!ollamaUp)
                    callbacks.onResult({
                        ok: false,
                        reason: 'unavailable',
                        message: 'Connection refused'
                    });
                else
                    done({
                        models: models
                    });
            } else if (op === 'llm.warm')
                done({
                    warmed: true,
                    loadMs: 1
                });
            else if (op === 'llm.chat') {
                callbacks.onPartial({
                    text: 'Привіт'
                });
                callbacks.onPartial({
                    text: ' зі світу'
                });
                done({
                    text: 'Привіт зі світу',
                    finishReason: 'stop'
                });
            } else if (op === 'text.translate')
                done({
                    text: 'Hello'
                });
            else
                callbacks.onResult({
                    ok: false,
                    reason: 'unsupported',
                    message: op
                });
        }
    }

    // The config store, faked: one `conflict` on demand, then saves land in memory.
    property QtObject fakeConfig: QtObject {
        property var documents: ({
                layout: {
                    schemaVersion: 1,
                    widgets: root.placements
                },
                models: Models.parseModels({})
            })
        property int serial: 0
        property int conflictsLeft: 0
        property int conflicts: 0
        property int reloads: 0
        property var saved: []
        signal commandFinished(string requestId, var result)
        function save(name, value) {
            const requestId = 'fixture-save-' + (++serial);
            Qt.callLater(() => {
                if (conflictsLeft > 0) {
                    conflictsLeft--;
                    conflicts++;
                    commandFinished(requestId, {
                        ok: false,
                        reason: 'conflict',
                        message: 'Changed on disk'
                    });
                    return;
                }
                const parsed = name === 'models' ? Models.parseModels(value) : value;
                const next = Object.assign({}, documents);
                next[name] = parsed;
                documents = next;
                saved = saved.concat([name]);
                if (name === 'layout')
                    root.placements = parsed.widgets;
                commandFinished(requestId, {
                    ok: true
                });
            });
            return requestId;
        }
        function reload(name) {
            const requestId = 'fixture-read-' + (++serial);
            Qt.callLater(() => {
                reloads++;
                commandFinished(requestId, {
                    ok: true
                });
            });
            return requestId;
        }
    }
    property Capabilities capabilityService: Capabilities {
        preview: false
        safeMode: false
        worker: root.fakeWorker
        models: root.fakeConfig.documents.models
    }
    property Chat chatService: Chat {
        preview: false
        safeMode: false
        capabilities: root.capabilityService
        config: root.fakeConfig
        localize: function (uk, en) {
            return root.language === 'uk' ? uk : en;
        }
    }
    property QtObject fakeServices: QtObject {
        readonly property bool preview: false
        readonly property bool safeMode: false
        readonly property var config: root.fakeConfig
        readonly property var plugins: root.registry
        readonly property ToolWorkspace toolWorkspace: ToolWorkspace {}
        readonly property var capabilities: root.capabilityService
        readonly property var chat: root.chatService
        function text(uk, en) {
            return root.language === 'uk' ? uk : en;
        }
    }
    property Plugins registry: Plugins {
        safeMode: true
        services: root.fakeServices
    }
    property FileView chatManifest: FileView {
        path: Qt.resolvedUrl('widgets/chat/manifest.json')
        printErrors: false
    }
    property FileView translateManifest: FileView {
        path: Qt.resolvedUrl('widgets/translate/manifest.json')
        printErrors: false
    }

    FloatingWindow {
        id: fixtureWindow
        visible: true
        implicitWidth: 420
        implicitHeight: 1000
        color: Theme.tokens.surface
        Rectangle {
            id: backdrop
            width: parent.width
            height: hostColumn.height + 2 * Metrics.space4
            color: Theme.tokens.surface
            Column {
                id: hostColumn
                x: Metrics.space4
                y: Metrics.space4
                width: 380
                spacing: Metrics.space3
                Repeater {
                    model: ['chat-main', 'chat-custom', 'chat-remote', 'translate-main']
                    delegate: PentadCard {
                        id: card
                        required property string modelData
                        objectName: 'card-' + modelData
                        width: hostColumn.width
                        implicitHeight: host.implicitHeight + 2 * Metrics.space3
                        PluginHost {
                            id: host
                            objectName: 'host-' + card.modelData
                            x: Metrics.space3
                            y: Metrics.space3
                            width: parent.width - 2 * Metrics.space3
                            height: implicitHeight
                            instanceId: card.modelData
                            moduleId: card.modelData === 'translate-main' ? 'pentad.translate' : 'pentad.chat'
                            settings: root.settingsOf(card.modelData)
                            context: ({
                                    slot: 'sidebar-left',
                                    outputId: 'fixture-output',
                                    compact: false,
                                    preview: false
                                })
                            services: root.fakeServices
                            registry: root.registry
                        }
                    }
                }
            }
        }
    }

    function host(id) {
        return findNamed(hostColumn, 'host-' + id);
    }
    function view(id) {
        const found = host(id);
        return found ? found.view : null;
    }
    function label(id, name) {
        const found = findNamed(view(id), name);
        return found ? found.text : null;
    }
    function next() {
        step++;
        ticks = 0;
        return true;
    }
    function wait(condition, name, detail) {
        if (condition)
            return next();
        if (ticks > 80) {
            check(name, false, 'timed out: ' + (typeof detail === 'function' ? detail() : ''));
            return next();
        }
        return false;
    }

    readonly property var steps: [function () {
            if (!chatManifest.loaded || !translateManifest.loaded)
                return false;
            const chat = registry.registerManifest(JSON.parse(chatManifest.text()), Qt.resolvedUrl('widgets/chat/'), true);
            const translate = registry.registerManifest(JSON.parse(translateManifest.text()), Qt.resolvedUrl('widgets/translate/'), true);
            check('manifests-register', chat.ok && translate.ok, JSON.stringify([chat.errors || [], translate.errors || []]));
            Theme.resolve({
                appearance: root.appearance,
                accent: '#869677',
                fontFamily: 'Geist',
                reducedMotion: true
            });
            registry.reconcile(placements);
            return next();
        }, function () {
            return wait(!!view('chat-main') && !!view('chat-custom') && !!view('chat-remote') && !!view('translate-main') && view('chat-main').availability !== null, 'views-mount', () => ['chat-main', 'chat-custom', 'chat-remote', 'translate-main'].map(id => host(id) ? host(id).diagnostic : 'missing').join(' | '));
        }, function () {
            const main = view('chat-main');
            const setup = findNamed(main, 'chat-setup');
            check('setup-card-when-no-chat-role', main.needsModel && !!setup && setup.visible, main.availability);
            check('composer-hidden-while-setup', !findNamed(main, 'chat-composer').visible);
            check('registry-disclosure-before-setup', label('chat-main', 'chat-disclosure') === 'Моделі', label('chat-main', 'chat-disclosure'));
            check('custom-local-disclosure', label('chat-custom', 'chat-disclosure') === 'Локально · llama3.2:3b', label('chat-custom', 'chat-disclosure'));
            check('custom-cloud-disclosure', label('chat-remote', 'chat-disclosure') === 'Хмара · api.openai.com · gpt-4o', label('chat-remote', 'chat-disclosure'));
            check('move-offered-only-for-custom', !findNamed(main, 'chat-move-to-models').visible && findNamed(view('chat-remote'), 'chat-move-to-models').visible);
            check('nothing-starts-at-rest', fakeWorker.requests.length === 0, fakeWorker.requests);
            snapshot(findNamed(hostColumn, 'card-chat-main'), 'setup-card');
            snapshot(findNamed(hostColumn, 'card-chat-remote'), 'custom-cloud');
            return next();
        }, function () {
            if (captures > 0 && ticks < 40)
                return false;
            findNamed(view('chat-remote'), 'chat-move-to-models').clicked();
            return next();
        }, function () {
            const models = fakeConfig.documents.models;
            return wait(models.roles.fast === 'openai/gpt-4o' && settingsOf('chat-remote').modelSource === 'registry', 'move-to-models-imports-endpoint', () => JSON.stringify([models, settingsOf('chat-remote'), view('chat-remote').actionMessage]));
        }, function () {
            const models = fakeConfig.documents.models;
            const moved = settingsOf('chat-remote');
            check('move-to-models-imports-endpoint', models.providers.length === 1 && models.providers[0].id === 'openai' && models.providers[0].credentialEnv === 'OPENAI_API_KEY' && models.roles.chat === '', models);
            check('move-saves-models-then-layout', JSON.stringify(fakeConfig.saved) === JSON.stringify(['models', 'layout']), fakeConfig.saved);
            check('moved-placement-keeps-its-endpoint-keys', moved.baseUrl === 'https://api.openai.com/v1' && moved.apiKeyEnv === 'OPENAI_API_KEY' && moved.model === 'gpt-4o', moved);
            return wait(label('chat-remote', 'chat-disclosure') === 'Хмара · api.openai.com · gpt-4o' && view('chat-remote').registrySource, 'moved-placement-discloses-registry-route', () => label('chat-remote', 'chat-disclosure'));
        }, function () {
            check('remote-role-never-warms', requestsFor('llm.warm').length === 0, fakeWorker.requests);
            fakeWorker.ollamaUp = false;
            findNamed(view('chat-main'), 'chat-setup').actionButton.clicked();
            return next();
        }, function () {
            const main = view('chat-main');
            return wait(main.actionMessage.indexOf('127.0.0.1:11434') >= 0 && !main.setupBusy, 'unreachable-ollama-message', () => main.actionMessage);
        }, function () {
            const main = view('chat-main');
            check('unreachable-ollama-message', label('chat-main', 'chat-status') === main.actionMessage && main.actionMessage.indexOf('127.0.0.1:11434') >= 0, label('chat-main', 'chat-status'));
            check('unreachable-ollama-writes-nothing', fakeConfig.documents.models.roles.chat === '' && fakeConfig.saved.length === 2, fakeConfig.saved);
            snapshot(findNamed(hostColumn, 'card-chat-main'), 'setup-unreachable');
            return next();
        }, function () {
            // The capture renders on a later frame; keep the message on screen until it is taken.
            if (captures > 0 && ticks < 40)
                return false;
            fakeWorker.ollamaUp = true;
            fakeConfig.conflictsLeft = 1;
            findNamed(view('chat-main'), 'chat-setup').actionButton.clicked();
            return next();
        }, function () {
            return wait(fakeConfig.documents.models.roles.chat !== '' && !view('chat-main').setupBusy, 'quick-setup-binds-roles', () => JSON.stringify([fakeConfig.documents.models, view('chat-main').actionMessage]));
        }, function () {
            const models = fakeConfig.documents.models;
            const local = models.providers.find(item => item.id === 'local');
            check('quick-setup-binds-roles', models.roles.chat === 'local/qwen3.5:9b' && models.roles.vision === 'local/qwen3.5:9b' && models.roles.embed === 'local/embeddinggemma-2:270m', models.roles);
            check('quick-setup-never-overwrites-a-role', models.roles.fast === 'openai/gpt-4o', models.roles);
            check('quick-setup-adds-local-ollama', !!local && local.kind === 'ollama' && local.baseUrl === 'http://127.0.0.1:11434', models.providers);
            check('quick-setup-retries-once-on-conflict', fakeConfig.conflicts === 1 && fakeConfig.reloads === 1, [fakeConfig.conflicts, fakeConfig.reloads]);
            check('quick-setup-lists-local-ollama-only', requestsFor('llm.models').every(item => item.payload.provider.baseUrl === 'http://127.0.0.1:11434' && item.payload.provider.kind === 'ollama' && item.payload.provider.credential === ''), requestsFor('llm.models'));
            return wait(!view('chat-main').needsModel && label('chat-main', 'chat-disclosure') === 'Локально · qwen3.5:9b', 'local-disclosure-after-setup', () => label('chat-main', 'chat-disclosure'));
        }, function () {
            if (ticks < 4)
                return false;
            // Opening the panel alone does not load a model; reaching for the composer does.
            check('presenting-alone-does-not-warm', requestsFor('llm.warm').length === 0, requestsFor('llm.warm'));
            view('chat-main').engage();
            view('chat-main').engage();
            return next();
        }, function () {
            return wait(requestsFor('llm.warm').length >= 1 && ticks > 3, 'warm-once-per-presentation', () => JSON.stringify(fakeWorker.requests));
        }, function () {
            const warms = requestsFor('llm.warm');
            check('warm-once-per-presentation', warms.length === 1 && warms[0].payload.model === 'qwen3.5:9b' && warms[0].payload.provider.kind === 'ollama', warms);
            const composer = findNamed(view('chat-main'), 'chat-composer');
            composer.text = 'П';
            composer.text = 'Пр';
            composer.text = '';
            view('chat-main').session.send('Привіт');
            return next();
        }, function () {
            const main = view('chat-main');
            return wait(main.chatState.status === 'idle' && main.chatState.messages.length === 2, 'registry-chat-streams-partials', () => JSON.stringify(main.chatState));
        }, function () {
            const main = view('chat-main');
            const calls = requestsFor('llm.chat');
            const payload = calls.length ? calls[0].payload : {};
            check('typing-does-not-warm', requestsFor('llm.warm').length === 1, requestsFor('llm.warm').length);
            check('registry-chat-streams-partials', main.chatState.messages[1].content === 'Привіт зі світу' && main.chatState.messages[1].status === 'complete', main.chatState);
            check('registry-chat-routes-to-role', calls.length === 1 && payload.model === 'qwen3.5:9b' && payload.provider.baseUrl === 'http://127.0.0.1:11434' && payload.think === false && JSON.stringify(payload.messages) === JSON.stringify([
                {
                    role: 'user',
                    content: 'Привіт'
                }
            ]), payload);
            snapshot(findNamed(hostColumn, 'card-chat-main'), 'chat-local');
            view('chat-custom').session.send('hi');
            return next();
        }, function () {
            const custom = view('chat-custom');
            return wait(custom.chatState.status === 'idle' && custom.chatState.messages.length === 2, 'custom-endpoint-streams', () => JSON.stringify(custom.chatState));
        }, function () {
            const calls = requestsFor('llm.chat');
            const payload = calls.length > 1 ? calls[1].payload : {};
            check('custom-endpoint-goes-through-worker', calls.length === 2 && payload.model === 'llama3.2:3b' && payload.provider.kind === 'ollama' && payload.provider.baseUrl === 'http://127.0.0.1:11434', payload);
            findNamed(view('chat-custom'), 'chat-move-to-models').clicked();
            return next();
        }, function () {
            const custom = view('chat-custom');
            return wait(custom.actionMessage !== '' && !custom.setupBusy, 'move-never-takes-a-bound-role', () => custom.actionMessage);
        }, function () {
            const custom = view('chat-custom');
            check('move-never-takes-a-bound-role', custom.actionMessage.indexOf('local/qwen3.5:9b') >= 0 && settingsOf('chat-custom').modelSource === 'custom' && fakeConfig.documents.models.roles.chat === 'local/qwen3.5:9b', [custom.actionMessage, settingsOf('chat-custom')]);
            hostColumn.visible = false;
            return next();
        }, function () {
            if (ticks < 2)
                return false;
            hostColumn.visible = true;
            return next();
        }, function () {
            if (ticks < 3)
                return false;
            check('re-presenting-waits-for-the-composer', requestsFor('llm.warm').length === 1, requestsFor('llm.warm').length);
            view('chat-main').engage();
            return next();
        }, function () {
            return wait(requestsFor('llm.warm').length === 2, 'warm-again-on-next-presentation', () => requestsFor('llm.warm').length);
        }, function () {
            check('warm-again-on-next-presentation', requestsFor('llm.warm').length === 2);
            const translate = view('translate-main');
            findNamed(translate, 'translate-tool-source').text = 'Привіт';
            translate.translate();
            return next();
        }, function () {
            const translate = view('translate-main');
            return wait(translate.result === 'Hello' && translate.jobId === '', 'translate-through-capability', () => JSON.stringify([translate.result, translate.message]));
        }, function () {
            const calls = requestsFor('text.translate');
            check('translate-through-capability', calls.length === 1 && calls[0].payload.text === 'Привіт' && calls[0].payload.target === 'uk', calls);
            capabilityService.safeMode = true;
            view('translate-main').translate();
            return next();
        }, function () {
            const translate = view('translate-main');
            return wait(translate.message !== '' && translate.jobId === '', 'translate-safe-mode-message', () => translate.message);
        }, function () {
            const translate = view('translate-main');
            check('translate-safe-mode-message', translate.message === 'У безпечному режимі переклад вимкнено: він надсилає текст у мережу.' && requestsFor('text.translate').length === 1, translate.message);
            check('chat-warm-denied-in-safe-mode', capabilityService.warm('llm.chat', 'chat-main', {
                role: 'chat'
            }).reason === 'safe-mode');
            snapshot(findNamed(hostColumn, 'card-translate-main'), 'translate-safe-mode');
            capabilityService.safeMode = false;
            language = 'en';
            return next();
        }, function () {
            if (ticks < 2)
                return false;
            check('english-disclosure', label('chat-main', 'chat-disclosure') === 'Local · qwen3.5:9b' && label('chat-remote', 'chat-disclosure') === 'Cloud · api.openai.com · gpt-4o', [label('chat-main', 'chat-disclosure'), label('chat-remote', 'chat-disclosure')]);
            language = 'uk';
            return next();
        }, function () {
            if (ticks < 2)
                return false;
            snapshot(backdrop, '');
            return next();
        }, function () {
            return captures === 0 || ticks > 40 ? next() : false;
        }]

    Timer {
        interval: 50
        repeat: true
        running: true
        onTriggered: {
            if (root.finished)
                return;
            root.ticks++;
            if (root.step >= root.steps.length) {
                root.finish();
                return;
            }
            if (root.step === 0 && root.ticks > 100) {
                root.check('fixture-start', false, 'manifests did not load');
                root.finish();
                return;
            }
            root.steps[root.step]();
        }
    }
    function finish() {
        if (finished)
            return;
        finished = true;
        const passed = checks.length > 0 && checks.every(item => item.passed);
        console.log('PENTAD_TEST ' + JSON.stringify({
            status: passed ? 'pass' : 'fail',
            checks: checks
        }));
        Qt.quit();
    }
}
