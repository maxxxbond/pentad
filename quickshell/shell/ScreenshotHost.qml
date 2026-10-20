pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.components
import qs.theme
import "../features/screenshot" as Screenshot

Variants {
    id: host
    required property var services
    model: Quickshell.screens
    PanelWindow {
        id: window
        required property var modelData
        property string captureMode: 'edit'
        property var initialCrop: null
        property bool captureReady: false
        readonly property var screenshot: host.services.screenshot
        readonly property var capture: screenshot.frames[modelData.name] || null
        readonly property bool ownsOutput: screenshot.choosingOutput ? !!capture : screenshot.outputId === modelData.name
        screen: modelData
        visible: screenshot.active && ownsOutput && ((captureReady && editor.item && editor.item.ready) || screenshot.phase === 'error')
        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }
        exclusionMode: ExclusionMode.Ignore
        color: 'transparent'
        WlrLayershell.namespace: 'pentad-screenshot'
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
        onVisibleChanged: {
            window.screenshot.overlayVisibility(modelData.name, visible || backingWindowVisible);
            host.services.popups.hostVisibility('screenshot-' + modelData.name, visible);
            if (visible)
                Qt.callLater(function () {
                    if (window.visible && window.screenshot.active && window.ownsOutput && editor.item)
                        editor.item.forceActiveFocus();
                });
        }
        onBackingWindowVisibleChanged: window.screenshot.overlayVisibility(modelData.name, visible || backingWindowVisible)
        Connections {
            target: window.screenshot
            function onCaptured(mode, initialCrop) {
                window.captureMode = mode;
                window.initialCrop = initialCrop;
                window.captureReady = true;
            }
            function onActiveChanged() {
                if (!window.screenshot.active)
                    window.captureReady = false;
            }
        }
        Loader {
            id: editor
            anchors.fill: parent
            active: window.screenshot.active && window.captureReady && window.ownsOutput && !!window.capture && !!window.capture.path && window.capture.width > 0 && window.capture.height > 0
            sourceComponent: Screenshot.ScreenshotEditor {
                services: host.services
                screenshot: window.screenshot
                outputId: window.modelData.name
                capture: window.capture
                mode: window.captureMode
                initialCrop: window.initialCrop
            }
        }
        Rectangle {
            anchors.fill: parent
            visible: window.visible && !window.capture
            color: '#99000000'
            focus: visible
            Keys.onEscapePressed: window.screenshot.close()
            ContinuousSurface {
                anchors.centerIn: parent
                width: Math.min(parent.width - 32, 480)
                height: failureBody.height + 16
                extent: 16
                fill: Theme.tokens.surface
                Column {
                    id: failureBody
                    x: 8
                    y: 8
                    width: parent.width - 16
                    spacing: 8
                    PentadText {
                        width: parent.width
                        wrapMode: Text.Wrap
                        role: 'section'
                        text: host.services.text('Не вдалося зробити скріншот', 'Could not capture screenshot')
                    }
                    PentadIcon {
                        source: Qt.resolvedUrl('../assets/icons/material/screenshot/error-symbolic.svg')
                        pixelSize: Metrics.exposedIcon
                        color: Theme.tokens.error
                    }
                    PentadText {
                        width: parent.width
                        wrapMode: Text.WrapAnywhere
                        text: window.screenshot.error
                    }
                    Flow {
                        width: parent.width
                        spacing: 8
                        Screenshot.ScreenshotIconButton {
                            text: host.services.text('Повторити', 'Retry')
                            iconSource: Qt.resolvedUrl('../assets/icons/material/screenshot/redo-symbolic.svg')
                            requestedEnabled: !window.screenshot.busy
                            onClicked: {
                                const mode = window.screenshot.mode, output = window.screenshot.outputId;
                                window.screenshot.close();
                                // A pick belongs to the tool that asked; retrying means asking again from that tool.
                                if (mode === 'pick')
                                    return;
                                Qt.callLater(function () {
                                    window.screenshot.open(mode, output);
                                });
                            }
                        }
                        Screenshot.ScreenshotIconButton {
                            iconSource: Qt.resolvedUrl('../assets/icons/material/media/close-symbolic.svg')
                            text: host.services.text('Закрити', 'Close')
                            onClicked: window.screenshot.close()
                        }
                    }
                }
            }
        }
        Component.onDestruction: {
            window.screenshot.overlayVisibility(modelData.name, false);
            host.services.popups.hostVisibility('screenshot-' + modelData.name, false);
            if (ownsOutput && screenshot.active)
                screenshot.outputRemoved(modelData.name);
        }
    }
}
