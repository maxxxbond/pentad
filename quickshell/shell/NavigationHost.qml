pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.theme
import '../features/overview' as Overview
import '../features/windowswitcher' as Switcher

Variants {
    id: host
    required property var services
    model: Quickshell.screens
    PanelWindow {
        id: window
        required property var modelData
        readonly property var navigation: host.services.navigation
        property real entranceOffset: 0
        readonly property bool ownsOutput: navigation.outputId === modelData.name
            || !!navigation.snapshot && navigation.snapshot.desktop.outputs.some(function(output) {
                return output.id === navigation.outputId && output.name === window.modelData.name;
            })
        screen: modelData
        visible: ownsOutput && navigation.active && navigation.revealed
        anchors { top: true; bottom: true; left: true; right: true }
        exclusiveZone: 0
        exclusionMode: ExclusionMode.Ignore
        color: 'transparent'
        WlrLayershell.namespace: 'pentad-navigation'
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
        onVisibleChanged: if (visible) {
            entranceOffset = Motion.reducedMotion ? 0 : navigation.mode === 'overview' ? 12 : 8;
            entrance.restart();
            Qt.callLater(function() { if (body.item) body.item.forceActiveFocus(); else keys.forceActiveFocus(); });
        } else entrance.stop()
        NumberAnimation {
            id: entrance
            target: window; property: 'entranceOffset'; to: 0
            duration: window.navigation.mode === 'overview' ? Motion.medium : Motion.short
            easing.type: Easing.OutCubic
        }
        Item {
            id: keys
            anchors.fill: parent
            focus: window.visible
            Rectangle {
                anchors.fill: parent
                visible: window.navigation.mode === 'overview'
                // Opaque: desktop text bleeding through the cards read as blur and clutter.
                color: Theme.tokens.surface
            }
            Keys.onPressed: function(event) {
                if (event.key === Qt.Key_Escape) { window.navigation.dismissTop(); event.accepted = true; }
                else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                    window.navigation.activateSelected(); event.accepted = true;
                } else if (event.key === Qt.Key_PageUp && window.navigation.mode === 'overview') {
                    window.navigation.changePage(-1); event.accepted = true;
                } else if (event.key === Qt.Key_PageDown && window.navigation.mode === 'overview') {
                    window.navigation.changePage(1); event.accepted = true;
                } else if (window.navigation.mode !== 'overview' && (event.key === Qt.Key_Left || event.key === Qt.Key_Right)) {
                    window.navigation.stepSwitcher(event.key === Qt.Key_Left ? -1 : 1); event.accepted = true;
                }
            }
            MouseArea { anchors.fill: parent; onClicked: window.navigation.cancel() }
            Loader {
                id: body
                active: window.visible
                width: Math.max(0, parent.width - (parent.width < 600 ? 24 : 48))
                height: window.navigation.mode === 'overview' ? Math.max(0, parent.height
                    - host.services.config.documents.layout.barHeight - 36)
                    : Math.min(218, Math.max(0, parent.height - 48))
                anchors.horizontalCenter: parent.horizontalCenter
                y: window.entranceOffset + (window.navigation.mode === 'overview'
                    ? host.services.config.documents.layout.barHeight + 12
                    : Math.max(24, (parent.height - Math.min(218, Math.max(0, parent.height - 48))) / 2))
                sourceComponent: window.navigation.mode === 'overview' ? overview : switcher
                onLoaded: item.forceActiveFocus()
            }
            Component {
                id: overview
                Overview.OverviewWindow { services: host.services; navigation: window.navigation }
            }
            Component {
                id: switcher
                Switcher.WindowSwitcher { services: host.services; navigation: window.navigation }
            }
        }
        HyprlandFocusGrab {
            active: window.visible
            windows: [window]
            onCleared: if (window.visible) window.navigation.cancel()
        }
        Component.onDestruction: if (ownsOutput && navigation.active) navigation.cancel()
    }
}
