import QtQuick
import QtQml
import qs.components
import '../logic/plugin-manifest.mjs' as Rules

Item {
    id: host
    required property string instanceId
    required property string moduleId
    required property var context
    required property var settings
    required property var services
    required property var registry
    property string diagnostic: ''
    property bool componentReady: false
    property string loadedViewSource: ''
    property var viewSettings: ({})
    // The instance id this host has bound to its manifest in services.capabilities, or ''.
    property string capabilityInstance: ''
    property var capabilityService: null
    signal actionRequested(string action)
    readonly property real renderedHeight: loader.item && loader.item.renderedHeight !== undefined
        ? loader.item.renderedHeight : implicitHeight
    readonly property var entry: { registry.revision; return context ? registry.entryFor(moduleId, context.slot) : null; }
    readonly property var controllerWrapper: registry.controllers[instanceId] || null
    readonly property alias view: loader.item
    readonly property var inputRegion: loader.item && loader.item.inputRegion ? loader.item.inputRegion : null
    implicitWidth: loader.item ? loader.item.implicitWidth : placeholder.implicitWidth
    implicitHeight: loader.item ? loader.item.implicitHeight : placeholder.implicitHeight
    function syncView() {
        if (!componentReady || !loader.item) return;
        loader.item.context = context;
        loader.item.settings = viewSettings;
        loader.item.services = widgetServices;
        loader.item.controller = controllerWrapper ? controllerWrapper.item : null;
    }
    // Views reach services.capabilities only once bound to their manifest; built-in entries come
    // from builtin-registry.json, everything else from the external plugin folders. The view's
    // capability facade is fixed to the id attached here.
    function bindCapabilities(id, manifest, builtin) {
        detachCapabilities();
        if (services && services.capabilities && id) {
            services.capabilities.attach(id, manifest, builtin === true);
            capabilityService = services.capabilities;
            capabilityInstance = id;
        }
        widgetServices.bindCapabilities(capabilityService, capabilityInstance);
    }
    function detachCapabilities() {
        if (capabilityInstance && capabilityService) capabilityService.detach(capabilityInstance);
        capabilityService = null;
        capabilityInstance = '';
    }
    function unbindCapabilities() {
        detachCapabilities();
        widgetServices.bindCapabilities(null, '');
    }
    function loadView() {
        if (!componentReady) return;
        if (!entry) {
            unbindCapabilities();
            diagnostic = 'Widget unavailable: ' + moduleId;
            loadedViewSource = '';
            loader.source = '';
            return;
        }
        var result = Rules.validateSettings(entry.manifest, settings);
        if (!result.ok) {
            unbindCapabilities();
            diagnostic = result.errors.join('; ');
            loadedViewSource = '';
            loader.source = '';
            return;
        }
        diagnostic = '';
        viewSettings = result.settings;
        const source = entry.baseUrl + entry.manifest.entry;
        const reuse = loadedViewSource === source && loader.status !== Loader.Error;
        // A reused view keeps the instanceId it was created with, so that id stays bound.
        bindCapabilities(reuse && capabilityInstance ? capabilityInstance : instanceId, entry.manifest, entry.builtin);
        if (reuse) {
            syncView();
            return;
        }
        loadedViewSource = source;
        loader.setSource(source, {
            instanceId: instanceId, context: context, settings: viewSettings, services: widgetServices,
            controller: controllerWrapper ? controllerWrapper.item : null
        });
    }
    onEntryChanged: loadView()
    onSettingsChanged: loadView()
    onContextChanged: loadView()
    onServicesChanged: syncView()
    onControllerWrapperChanged: syncView()
    Component.onCompleted: {
        widgetServices.adopt(() => host.services, () => !!host.entry && host.entry.builtin === true);
        componentReady = true;
        loadView();
    }
    Component.onDestruction: unbindCapabilities()
    // What the view receives as `services`: the shared container without the worker, with a
    // capability facade of its own. The view never gets the container itself.
    WidgetServices {
        id: widgetServices
    }
    Connections {
        target: host.controllerWrapper
        function onItemChanged() {
            if (loader.item) loader.item.controller = host.controllerWrapper.item;
        }
    }
    Loader {
        id: loader
        anchors.fill: parent
        onLoaded: host.syncView()
        onStatusChanged: { if (status === Loader.Error) host.diagnostic = 'Cannot load ' + host.moduleId; }
    }
    Connections {
        target: loader.item
        ignoreUnknownSignals: true
        function onActionRequested(action) { host.actionRequested(action) }
    }
    PentadText {
        id: placeholder
        visible: host.diagnostic !== ''
        text: host.diagnostic
        Accessible.name: text
        Accessible.role: Accessible.StaticText
    }
}
