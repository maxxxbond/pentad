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
        loader.item.services = services;
        loader.item.controller = controllerWrapper ? controllerWrapper.item : null;
    }
    function loadView() {
        if (!componentReady) return;
        if (!entry) {
            diagnostic = 'Widget unavailable: ' + moduleId;
            loadedViewSource = '';
            loader.source = '';
            return;
        }
        var result = Rules.validateSettings(entry.manifest, Object.assign({}, entry.manifest.defaults || {}, settings));
        if (!result.ok) {
            diagnostic = result.errors.join('; ');
            loadedViewSource = '';
            loader.source = '';
            return;
        }
        diagnostic = '';
        viewSettings = result.settings;
        const source = entry.baseUrl + entry.manifest.entry;
        if (loadedViewSource === source && loader.status !== Loader.Error) {
            syncView();
            return;
        }
        loadedViewSource = source;
        loader.setSource(source, {
            instanceId: instanceId, context: context, settings: viewSettings, services: services,
            controller: controllerWrapper ? controllerWrapper.item : null
        });
    }
    onEntryChanged: loadView()
    onSettingsChanged: loadView()
    onContextChanged: loadView()
    onServicesChanged: syncView()
    onControllerWrapperChanged: syncView()
    Component.onCompleted: { componentReady = true; loadView(); }
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
