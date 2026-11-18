import QtQuick
import "../logic/capability-port.mjs" as Port

// services.capabilities as one widget instance sees it (widget API v1). The host binds it to the
// Capabilities service and to the instance id it attached to the widget's manifest; the widget
// gets state, available, call, cancel, warm and the three signals for its own calls only.
// attach/detach stay on the host service, and an `instanceId` in the options is ignored.
// listModels and `options.provider` are host-internal: the service refuses them unless the
// instance is built in.
QtObject {
    id: facade
    // Bumped when the host (re)binds the instance, so bindings on available() and state follow.
    property int revision: 0
    readonly property var port: Port.createCapabilityPort({
        progress: (requestId, data) => facade.progress(requestId, data),
        partial: (requestId, chunk) => facade.partial(requestId, chunk),
        commandFinished: (requestId, result) => facade.commandFinished(requestId, result),
        later: fn => Qt.callLater(fn)
    })
    readonly property var state: facade.revision >= 0 && facade.port ? facade.port.state() : {
        kind: 'unavailable',
        reason: 'service-missing'
    }
    signal progress(string requestId, var data)
    signal partial(string requestId, var chunk)
    signal commandFinished(string requestId, var result)

    // available(name[, options]); the older available(name, instanceId[, options]) still works.
    function available(name, second, third) {
        // Reading the revision makes a binding on this call follow a rebind.
        return facade.revision >= 0 ? port.available(name, second, third) : null;
    }
    function call(name, input, options) {
        return port.call(name, input, options);
    }
    function cancel(requestId) {
        port.cancel(requestId);
    }
    // warm(name[, options]); the older warm(name, instanceId[, options]) still works.
    function warm(name, second, third) {
        return port.warm(name, second, third);
    }
    function listModels(provider, callback) {
        port.listModels(provider, callback);
    }
    // Host only: it takes the Capabilities service itself, which a widget is never given.
    function bind(service, instanceId) {
        port.bind(service, instanceId);
        revision++;
    }
    Component.onDestruction: port.release()
}
