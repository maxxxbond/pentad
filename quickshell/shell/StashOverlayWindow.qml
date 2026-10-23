import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.theme
import qs.components
import qs.features.shelf

// The Stash as a centered overlay on the focused output. Esc, a press beside the frame or a
// click on another output closes it. While a row or photo is dragged out to another app, the
// frame fades and the overlay lets the pointer and the keyboard through until the drag ends.
PanelWindow {
    id: window
    required property var services
    readonly property var stash: services.stash
    readonly property string kind: 'overlay'
    readonly property bool passThrough: stash.exporting
    readonly property alias frame: stashFrame
    readonly property alias view: stashView
    // The tallest the content has been since the overlay opened. Narrowing the list by search or
    // a filter does not shrink the frame, so the header and the search field stay in place.
    property real tallest: 0
    signal detachRequested

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }
    exclusiveZone: 0
    exclusionMode: ExclusionMode.Ignore
    color: 'transparent'
    WlrLayershell.namespace: 'pentad-stash'
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: visible && !passThrough ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    // The whole output takes input, so a press beside the frame closes it; during a drag-out none of it does.
    mask: Region {
        width: window.passThrough ? 0 : window.width
        height: window.passThrough ? 0 : window.height
    }
    // The compositor closed the surface, for example because its output went away.
    onClosed: window.stash.hide()
    // Opens on the focused output and stays there when the pointer moves to another one.
    Component.onCompleted: window.screen = window.focusedScreen()

    function focusedScreen() {
        const state = window.services.hyprland ? window.services.hyprland.state : null;
        const outputs = state && state.kind === 'ready' ? state.value.outputs : [];
        const focused = outputs.find(output => output.id === state.value.focusedOutputId);
        return Quickshell.screens.find(screen => !!focused && screen.name === focused.name) || null;
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.AllButtons
        onPressed: window.stash.hide()
    }
    Item {
        id: stashFrame
        objectName: 'stash-overlay-frame'
        anchors.centerIn: parent
        width: Math.max(1, Math.min(520, window.width - 32))
        height: Math.max(1, Math.min(Math.max(window.tallest, stashView.implicitHeight), Math.round(window.height * 0.7)))
        opacity: window.passThrough ? 0.15 : 1
        Behavior on opacity {
            NumberAnimation {
                duration: Motion.short
                easing.type: Easing.OutCubic
            }
        }
        // Presses inside the frame never reach the closing area behind it.
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.AllButtons
        }
        // The shadow's silhouette; the view draws the surface itself.
        ContinuousSurface {
            anchors.fill: parent
            fill: Theme.tokens.surface
            extent: Metrics.radiusPopover
            castsShadow: true
            clipContent: false
        }
        StashView {
            id: stashView
            anchors.fill: parent
            services: window.services
            framed: true
            focus: true
            onImplicitHeightChanged: window.tallest = Math.max(window.tallest, stashView.implicitHeight)
            onCloseRequested: window.stash.hide()
            onDetachRequested: window.detachRequested()
        }
    }
    HyprlandFocusGrab {
        active: window.visible && !window.passThrough
        windows: [window]
        onCleared: if (window.visible && !window.passThrough)
            window.stash.hide()
    }
}
