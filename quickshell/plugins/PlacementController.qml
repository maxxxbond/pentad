import QtQuick
import QtQml

QtObject {
    id: wrapper
    required property string instanceId
    required property string moduleId
    required property var settings
    required property var services
    required property var entry
    property var item: null
    property var component: null
    property bool capabilityBound: false
    // What the controller receives as `services`; see WidgetServices.
    property WidgetServices widgetServices: WidgetServices {}
    onSettingsChanged: { if (item) item.settings = settings; }
    function load() {
        if (component && component.status === Component.Error) {
            console.warn('Cannot load controller for ' + moduleId + ': ' + component.errorString());
            return;
        }
        if (!component || component.status !== Component.Ready || item) return;
        // Bound before the controller exists, so its Component.onCompleted may already call capabilities.
        if (services && services.capabilities && !capabilityBound) {
            services.capabilities.attach(instanceId, entry.manifest, entry.builtin === true);
            capabilityBound = true;
            widgetServices.bindCapabilities(services.capabilities, instanceId);
        }
        item = component.createObject(wrapper, {
            instanceId: instanceId, settings: settings, services: widgetServices
        });
    }
    Component.onDestruction: {
        if (capabilityBound && services && services.capabilities) services.capabilities.detach(instanceId);
    }
    Component.onCompleted: {
        widgetServices.adopt(() => wrapper.services, () => !!wrapper.entry && wrapper.entry.builtin === true);
        component = Qt.createComponent(entry.baseUrl + entry.manifest.controller);
        if (component.status === Component.Loading) component.statusChanged.connect(load);
        else load();
    }
}
