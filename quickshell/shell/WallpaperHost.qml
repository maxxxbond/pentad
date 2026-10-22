pragma ComponentBehavior: Bound
import QtQuick
import QtQml
import Quickshell
import "../services"

// One background window per screen; a screen without a wallpaper keeps its window hidden.
QtObject {
    id: host
    required property Services services
    property Instantiator windows: Instantiator {
        model: Quickshell.screens
        asynchronous: false
        delegate: Component {
            WallpaperWindow {
                required property var modelData
                screen: modelData
                services: host.services
            }
        }
    }
}
