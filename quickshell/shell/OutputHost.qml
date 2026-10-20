pragma ComponentBehavior: Bound
import QtQuick
import QtQml
import Quickshell
import "../services"

QtObject {
    id: host
    required property Services services
    property var outputs: Quickshell.screens
    property Component surfaceComponent: Component {
        BarWindow {
            required property var modelData
            screen: modelData
            services: host.services
        }
    }
    property Instantiator outputWindows: Instantiator {
        model: host.outputs
        asynchronous: false
        delegate: host.surfaceComponent
    }
}
