import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.theme
import qs.components

// Shows the enlarged capture made by the magnifier tool. Escape, a click or the close hint dismisses it.
PanelWindow {
    id: window
    objectName: "magnifier-window"
    required property var services
    readonly property string source: services.desktop.magnifierSource
    readonly property alias picture: picture
    screen: {
        const state = services.hyprland.state;
        const outputs = state.kind === 'ready' ? state.value.outputs : [];
        const focused = outputs.find(output => state.kind === 'ready' && output.id === state.value.focusedOutputId);
        return Quickshell.screens.find(output => focused && output.name === focused.name) || Quickshell.screens[0] || null;
    }
    visible: source !== ""
    onVisibleChanged: {
        services.popups.hostVisibility('magnifier', visible);
        if (visible) stage.forceActiveFocus();
    }
    Component.onDestruction: services.popups.hostVisibility('magnifier', false)
    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }
    color: 'transparent'
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: 'pentad-magnifier'
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    Rectangle {
        id: stage
        objectName: "magnifier-stage"
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.55)
        focus: true
        Keys.onEscapePressed: window.services.desktop.closeMagnifier()
        MouseArea {
            anchors.fill: parent
            onClicked: window.services.desktop.closeMagnifier()
        }
        Rectangle {
            id: frame
            anchors.centerIn: parent
            width: picture.width + 16
            height: picture.height + 16
            color: Theme.tokens.surface
            radius: Metrics.radiusBlock
            Image {
                id: picture
                objectName: "magnifier-image"
                anchors.centerIn: parent
                source: window.source ? "file://" + window.source : ""
                cache: false
                smooth: false
                asynchronous: false
                fillMode: Image.PreserveAspectFit
                width: Math.min(implicitWidth, Math.max(1, window.width - 64))
                height: implicitWidth > 0 ? width * implicitHeight / implicitWidth : 0
            }
        }
        PentadText {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: frame.bottom
            anchors.topMargin: 12
            role: "caption"
            color: Qt.rgba(1, 1, 1, 0.8)
            text: window.services.text("Esc або клік — закрити", "Esc or click to close")
        }
    }
}
