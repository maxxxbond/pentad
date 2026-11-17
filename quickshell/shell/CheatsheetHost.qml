pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.theme
import qs.components
import qs.features.cheatsheet

// The keybind cheatsheet as a centred overlay on the focused output, while services.cheatsheet
// is open; a closed cheatsheet has no window at all. Like Spotlight it closes the bar menus and
// the overview when it opens, takes the keyboard, and closes on Esc, on a press beside the card,
// on a click on another output and before a screenshot.
Loader {
    id: host
    required property var services
    readonly property var cheatsheet: services.cheatsheet
    readonly property var overlay: item

    active: !!cheatsheet && cheatsheet.open
    sourceComponent: Component {
        PanelWindow {
            id: window
            readonly property var services: host.services
            readonly property alias frame: card
            readonly property alias view: cheatsheetView
            // The tallest the content has been since the overlay opened. A search that narrows the
            // list does not shrink the card, so the header and the search field stay in place.
            property real tallest: 0

            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }
            exclusiveZone: 0
            exclusionMode: ExclusionMode.Ignore
            color: 'transparent'
            WlrLayershell.namespace: 'pentad-cheatsheet'
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
            // The compositor closed the surface, for example because its output went away.
            onClosed: host.cheatsheet.hide()
            Component.onCompleted: {
                const services = window.services;
                // An active submap already keeps the bind reader on, so opening would read nothing.
                if (services.submap && services.submap.name !== '' && services.keybinds)
                    services.keybinds.refresh();
                if (services.popups && typeof services.popups.close === 'function')
                    services.popups.close();
                if (services.navigation && services.navigation.active)
                    services.navigation.cancel();
                if (services.spotlight && services.spotlight.visible)
                    services.spotlight.close();
                window.screen = window.focusedScreen();
                if (services.popups && typeof services.popups.hostVisibility === 'function')
                    services.popups.hostVisibility('cheatsheet', true);
            }
            Component.onDestruction: {
                const popups = window.services.popups;
                if (popups && typeof popups.hostVisibility === 'function')
                    popups.hostVisibility('cheatsheet', false);
            }

            function focusedScreen() {
                const state = window.services.hyprland ? window.services.hyprland.state : null;
                const outputs = state && state.kind === 'ready' ? state.value.outputs : [];
                const focused = outputs.find(output => output.id === state.value.focusedOutputId);
                return Quickshell.screens.find(screen => !!focused && screen.name === focused.name) || null;
            }

            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.AllButtons
                onPressed: host.cheatsheet.hide()
            }
            Item {
                id: card
                objectName: 'cheatsheet-frame'
                anchors.centerIn: parent
                width: Math.max(1, Math.min(920, window.width - 32))
                height: Math.max(1, Math.min(Math.max(window.tallest, cheatsheetView.implicitHeight), Math.round(window.height * 0.8)))
                // Presses inside the card never reach the closing area behind it.
                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.AllButtons
                }
                ContinuousSurface {
                    anchors.fill: parent
                    fill: Theme.tokens.surface
                    extent: Metrics.radiusPopover
                    castsShadow: true
                    clipContent: false
                }
                CheatsheetView {
                    id: cheatsheetView
                    anchors.fill: parent
                    services: window.services
                    focus: true
                    onImplicitHeightChanged: window.tallest = Math.max(window.tallest, cheatsheetView.implicitHeight)
                    onCloseRequested: host.cheatsheet.hide()
                }
            }
            HyprlandFocusGrab {
                active: window.visible
                windows: [window]
                onCleared: if (window.visible)
                    host.cheatsheet.hide()
            }
            Connections {
                target: window.services.popups || null
                // A screenshot must not show the overlay; it steps aside the way Spotlight does.
                function onCapturePreparing() {
                    host.cheatsheet.hide();
                }
                // A bar menu opened over it (a click on the bar of another output).
                function onChanged() {
                    if (window.services.popups.surface)
                        host.cheatsheet.hide();
                }
            }
        }
    }
}
