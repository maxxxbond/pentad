import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.theme
import qs.components
import "../features/settings"

PanelWindow {
    id: window
    required property var services
    screen: {
        const state = services.hyprland.state;
        const outputs = state.kind === 'ready' ? state.value.outputs : [];
        const focused = outputs.find(output => state.kind === 'ready' && output.id === state.value.focusedOutputId);
        return Quickshell.screens.find(output => focused && output.name === focused.name) || Quickshell.screens[0] || null;
    }
    visible: services.screenshot.settingsOpen
    onVisibleChanged: {
        services.popups.hostVisibility('screenshot-settings', visible);
        if (visible) card.forceActiveFocus();
    }
    Component.onDestruction: services.popups.hostVisibility('screenshot-settings', false)
    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }
    color: 'transparent'
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: 'pentad-screenshot-settings'
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: visible && !services.screenshot.active ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.5)
        MouseArea {
            anchors.fill: parent
            onClicked: card.forceActiveFocus()
        }
    }
    ContinuousSurface {
        id: card
        anchors.centerIn: parent
        width: Math.max(1, Math.min(640, parent.width - 32))
        height: Math.max(1, Math.min(720, parent.height - 32))
        fill: Theme.tokens.surface
        extent: Metrics.radiusPopover
        focus: true
        Keys.onEscapePressed: window.services.screenshot.closeSettings()
        ScreenshotSettings {
            anchors.fill: parent
            services: window.services
            ownerVisible: window.visible
            onCloseRequested: window.services.screenshot.closeSettings()
        }
    }
    Component.onCompleted: card.forceActiveFocus()
}
