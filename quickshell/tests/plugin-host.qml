import QtQuick
import QtQml
import Quickshell
import Quickshell.Io
import qs.services
import qs.plugins
import qs.features.bar

ShellRoot {
    id: root
    property int step: 0
    property int producerStarts: 0
    property var fakeServices: QtObject {
        id: fake
        // The members a widget must not be able to use against another instance.
        property QtObject worker: QtObject {
            readonly property string state: 'ready'
            property var requests: []
            function accepts(op) { return true; }
            function request(op, payload, callbacks) {
                requests = requests.concat([op]);
                Qt.callLater(function() { callbacks.onResult({ ok: true, value: { codes: [] } }); });
                return requests.length;
            }
            function cancel(id) {}
        }
        property Capabilities capabilities: Capabilities { worker: fake.worker }
        property QtObject chat: QtObject {}
        property bool preview: true
        property var plugins: root.registry
        property var config: ({ documents: { layout: { widgets: root.barWidgets } } })
        // Documented for every widget (packages/widget-api/v1/contracts.d.ts WidgetServices).
        property QtObject audio: QtObject {
            readonly property var state: ({ kind: 'ready', value: { streams: [] } })
        }
        property QtObject toolWorkspace: QtObject {
            function draftFor(id) { return ''; }
        }
        // Host-internal: only built-in widgets see these.
        property QtObject fileTools: QtObject {}
        property QtObject desktop: QtObject {}
        function text(uk, en) { return en; }
        function brightnessFor(outputId) { return null; }
        property QtObject media: QtObject {
            readonly property int producerCount: root.producerStarts
            property int controllerCreates: 0
            property int controllerDisposals: 0
            Component.onCompleted: root.producerStarts++
            property var state: ({ kind: 'ready', value: { playback: 'playing', positionMicros: 1000000, lengthMicros: 60000000 } })
            property int serial: 0
            signal commandFinished(string requestId, var result)
            function playPause() {
                var id = 'media-' + (++serial);
                state = { kind: 'ready', value: Object.assign({}, state.value, { playback: state.value.playback === 'playing' ? 'paused' : 'playing' }) };
                commandFinished(id, { ok: true });
                return id;
            }
        }
    }
    property Plugins registry: Plugins { safeMode: false; services: root.fakeServices }
    property FileView externalManifest: FileView { path: Qt.resolvedUrl('tests/external-example/manifest.json') }
    property bool controllerShared: false
    property var manifest: ({ id: 'fixture.media', name: 'Media lifecycle fixture', version: '1.0.0', apiVersion: 1,
        entry: 'FixtureWidget.qml', controller: 'FixtureController.qml', allowedSlots: ['center', 'system'], defaults: {}, settingsFields: [] })
    property var placement: ({ instanceId: 'shared-placement', moduleId: 'fixture.media', slot: 'center', enabled: true, settings: {} })
    property var viewComponent: Component { PluginHost {} }
    property var first: null
    property var second: null
    property var third: null
    property SettingsForm settingsForm: SettingsForm {
        manifest: ({ id: 'fixture.settings', name: 'Settings', version: '1.0.0', apiVersion: 1,
            entry: 'FixtureWidget.qml', allowedSlots: ['center'], defaults: {},
            settingsFields: [{ key: 'count', kind: 'integer', label: 'Count', default: 3, min: 1, max: 5 },
                { key: 'enabled', kind: 'boolean', label: 'Enabled', default: true }] })
        settings: ({})
        onSettingsEdited: function(value) { settings = value; }
    }
    function createView(outputId, slot) {
        return viewComponent.createObject(root, { instanceId: placement.instanceId, moduleId: placement.moduleId,
            context: { outputId: outputId, slot: slot, compact: false, preview: true }, settings: {}, services: fakeServices, registry: registry });
    }
    Timer {
        interval: 40; running: true; repeat: true
        onTriggered: {
            root.step++;
            if (root.step === 1) {
                root.registry.registerManifest(root.manifest, Qt.resolvedUrl('tests/'), true);
                root.registry.reconcile([root.placement]);
                root.first = root.createView('bar-A', 'system');
                root.second = root.createView('island-A', 'center');
                root.registry.registerManifest(Object.assign(JSON.parse(root.externalManifest.text()), { capabilities: ['image.barcode'] }), Qt.resolvedUrl('tests/external-example/'), false);
                // A built-in instance with more rights than the external widget, bound by the host.
                root.fakeServices.capabilities.attach('victim', { capabilities: ['image.ocr', 'llm.chat'] }, true);
                root.third = root.viewComponent.createObject(root, { instanceId: 'example-placement', moduleId: 'example.hello', context: { outputId: 'example-B', slot: 'sidebar-left', compact: false, preview: true }, settings: {}, services: root.fakeServices, registry: root.registry });
            } else if (root.step === 2) {
                if (!root.first.view || !root.second.view || !root.third.view) { root.step--; return; }
                root.first.view.togglePlayback();
                root.first.view.startTimer();
                root.probeFacade();
            } else if (root.step === 3) {
                root.judgeFacade();
                var shared = root.first.view.services.media === root.second.view.services.media
                    && root.second.view.services.media === root.third.view.services.media;
                var synchronized = root.first.view.observedMedia.value.playback === 'paused'
                    && root.second.view.observedMedia.value.playback === 'paused' && root.third.view.observedMedia.value.playback === 'paused';
                var timerSynchronized = root.first.controllerWrapper.item.timerState.status === 'running'
                    && root.second.controllerWrapper.item.timerState.status === 'running';
                var previous = root.registry.catalog['fixture.media'];
                var rejected = root.registry.registerManifest(Object.assign({}, root.manifest, { apiVersion: 99 }), Qt.resolvedUrl('tests/'), true);
                var retained = !rejected.ok && root.registry.catalog['fixture.media'] === previous;
                root.second.destroy();
                root.second = root.createView('island-readded', 'center');
                root.registry.reconcile([root.placement]);
                root.checkShared = shared && synchronized && timerSynchronized && retained;
            } else if (root.step === 4) {
                root.controllerShared = root.first.controllerWrapper === root.second.controllerWrapper
                    && root.third.controllerWrapper === null && root.fakeServices.media.controllerCreates === 1
                    && root.first.controllerWrapper.item.timerState.status === 'running';
                root.first.destroy(); root.second.destroy(); root.third.destroy();
                root.registry.reconcile([]);
            } else if (root.step === 5) {
                var disposed = root.fakeServices.media.controllerDisposals === 1 && Object.keys(root.registry.controllers).length === 0;
                var edited = root.settingsForm.change('count', 4);
                var settingsValid = edited && root.settingsForm.settings.count === 4 && root.settingsForm.settings.enabled === true
                    && !root.settingsForm.change('count', 6) && root.settingsForm.settings.count === 4;
                root.disposed = disposed;
                root.settingsValid = settingsValid;
                root.registry.registerManifest(root.manifest, Qt.resolvedUrl('tests/'), true);
                root.systemSlot = root.slotComponent.createObject(root, { services: root.fakeServices, slot: 'system', outputId: 'bar-P', compact: false });
                root.centerSlot = root.slotComponent.createObject(root, { services: root.fakeServices, slot: 'center', outputId: 'bar-P', compact: false });
            } else if (root.step === 6) {
                var systemSlot = root.systemSlot, centerSlot = root.centerSlot;
                var disposed = root.disposed, settingsValid = root.settingsValid;
                var delegates = centerSlot.children.filter(function(child) { return child.frameInset !== undefined; });
                var placementApplied = systemSlot.placements.length === 1 && systemSlot.placements[0].instanceId === 'legacy'
                    && centerSlot.placements.length === 2 && centerSlot.placements[1].instanceId === 'framed'
                    && centerSlot.placements[1].frame.margin === 8 && centerSlot.placements[1].zone === 'center';
                root.widthDetail = JSON.stringify(delegates.map(function(child) { return [child.width, child.frameInset]; }));
                var frameAddsSpace = delegates.length === 2 && delegates[0].frameInset === 0 && delegates[1].frameInset === 12
                    && Math.abs((delegates[1].width - delegates[0].width) - 24) < 0.5;
                systemSlot.destroy(); centerSlot.destroy();
                const facadePassed = root.facadeChecks.length === 8 && root.facadeChecks.every(function(item) { return item.passed; });
                var passed = facadePassed && placementApplied && frameAddsSpace && root.checkShared && root.controllerShared && disposed && settingsValid && root.fakeServices.media.producerCount === 1;
                console.log('PENTAD_TEST ' + JSON.stringify({ status: passed ? 'pass' : 'fail', checks: [
                    { name: 'shared-media-state-and-command', passed: root.checkShared },
                    { name: 'one-controller-per-placement-shares-timer-state-across-output-views', passed: root.controllerShared },
                    { name: 'controller-disposed-on-disable', passed: disposed },
                    { name: 'generated-settings-retain-default-and-reject-out-of-bounds', passed: settingsValid },
                    { name: 'bar-slot-applies-stored-section', passed: placementApplied },
                    { name: 'bar-slot-frame-adds-margin-and-padding', passed: frameAddsSpace, detail: root.widthDetail },
                    { name: 'single-producer-after-readd', passed: root.fakeServices.media.producerCount === 1 }
                ].concat(root.facadeChecks) }));
                Qt.quit();
            }
        }
    }
    // What an external widget can do with the `services` it is handed (the view's own object).
    property var facadeChecks: []
    property var facadeProbe: ({})
    property var facadeEvents: ({})
    readonly property var attackerProvider: ({ id: 'x', kind: 'openai-compatible', name: 'x', baseUrl: 'https://attacker.example/v1',
        credential: 'secret://pentad/providers/openai', credentialEnv: '' })
    function probeFacade() {
        var host = root.fakeServices.capabilities;
        var external = root.third.view.services;
        var caps = external.capabilities;
        caps.commandFinished.connect(function(requestId, result) {
            root.facadeEvents = Object.assign({}, root.facadeEvents, { [requestId]: result });
        });
        var uri = { uri: 'file:///tmp/pentad-fixture.png' };
        var builtin = root.first.view.services;
        var hidden = ['config', 'plugins', 'fileTools', 'desktop', 'worker', 'chat', 'brightnessFor', 'releaseBrightness', 'popups'];
        root.facadeProbe = {
            forwards: external.media === root.fakeServices.media && external.preview === true
                && builtin.chat === root.fakeServices.chat && caps.available('image.barcode').available === true,
            // External widgets get the documented services only; built-in widgets keep the rest.
            externalHidden: hidden.filter(function(name) { return external[name] !== undefined && external[name] !== null; }),
            externalDocumented: external.media === root.fakeServices.media && external.audio === root.fakeServices.audio
                && external.toolWorkspace === root.fakeServices.toolWorkspace && external.capabilities === caps && caps !== root.fakeServices.capabilities
                && external.text('Привіт', 'Hello') === 'Hello' && external.preview === true,
            builtinFull: builtin.config === root.fakeServices.config && builtin.plugins === root.registry && builtin.fileTools === root.fakeServices.fileTools
                && builtin.desktop === root.fakeServices.desktop && builtin.audio === root.fakeServices.audio && typeof builtin.brightnessFor === 'function'
                && builtin.brightnessFor('x') === null && builtin.text('Привіт', 'Hello') === 'Hello',
            worker: external.worker === undefined && builtin.worker === undefined && external.chat === null,
            attach: caps.attach === undefined && caps.detach === undefined && caps.bindings === undefined,
            victimIsBound: host.available('image.ocr', 'victim').available === true,
            spoofedAvailability: [caps.available('image.ocr', 'victim').reason, caps.available('image.ocr', { instanceId: 'victim' }).reason,
                caps.warm('llm.chat', 'victim').reason, caps.warm('llm.chat', { instanceId: 'victim' }).reason],
            providerAvailability: caps.available('llm.chat', { instanceId: 'victim', provider: root.attackerProvider, model: 'm' }).reason,
            own: caps.call('image.barcode', uri, {}),
            spoofed: caps.call('image.ocr', uri, { instanceId: 'victim' }),
            provider: caps.call('llm.chat', { messages: [{ role: 'user', content: 'hi' }] },
                { instanceId: 'victim', provider: root.attackerProvider, model: 'm' }),
            // The host calls for the built-in instance: the external widget must not see it finish.
            foreign: host.call('image.ocr', uri, { instanceId: 'victim' })
        };
    }
    function judgeFacade() {
        var probe = root.facadeProbe, events = root.facadeEvents;
        var reason = function(id) { return events[id] ? events[id].reason : 'pending'; };
        root.facadeChecks = [
            { name: 'facade-forwards-shared-services-and-own-capabilities', passed: probe.forwards === true && !!events[probe.own] && events[probe.own].ok === true, detail: JSON.stringify(events[probe.own] || null) },
            { name: 'external-widget-gets-only-documented-services', passed: probe.externalHidden.length === 0 && probe.externalDocumented === true, detail: JSON.stringify(probe.externalHidden) },
            { name: 'builtin-widget-keeps-the-full-services', passed: probe.builtinFull === true },
            { name: 'widget-cannot-reach-the-worker', passed: probe.worker === true },
            { name: 'widget-cannot-attach-or-detach', passed: probe.attach === true },
            { name: 'widget-cannot-call-as-another-instance', passed: probe.victimIsBound === true && probe.spoofedAvailability.join() === 'denied,denied,denied,denied' && reason(probe.spoofed) === 'denied', detail: JSON.stringify([probe.spoofedAvailability, reason(probe.spoofed)]) },
            { name: 'widget-cannot-name-a-provider', passed: probe.providerAvailability === 'denied' && reason(probe.provider) === 'denied', detail: probe.providerAvailability + ' ' + reason(probe.provider) },
            { name: 'widget-sees-only-its-own-calls', passed: events[probe.foreign] === undefined && Object.keys(events).length === 3 && JSON.stringify(root.fakeServices.worker.requests) === '["image.barcode","image.ocr"]', detail: JSON.stringify([Object.keys(events), root.fakeServices.worker.requests]) }
        ];
    }
    property bool checkShared: false
    property string widthDetail: ''
    property bool disposed: false
    property bool settingsValid: false
    property var systemSlot: null
    property var centerSlot: null
    // Placement in the bar: a stored section moves the widget to that section's slot, and the frame adds space.
    property var barWidgets: [
        { instanceId: 'plain', moduleId: 'fixture.media', slot: 'system', enabled: true, settings: { _zones: ['center'] } },
        { instanceId: 'legacy', moduleId: 'fixture.media', slot: 'system', enabled: true, settings: {} },
        { instanceId: 'framed', moduleId: 'fixture.media', slot: 'system', enabled: true,
            settings: { _zones: ['center'], _margin: 8, _padding: 4, _bg: 'solid' } }
    ]
    property var slotComponent: Component { BarSlot { height: 32 } }
}
