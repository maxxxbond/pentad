pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.theme
import qs.components

Rectangle {
    id: root
    objectName: 'navigation-window-preview'
    required property var client
    required property var source
    required property bool captureEnabled
    property bool showFallbackTitle: true
    property bool showIconWithContent: true
    property bool sharedCapture: false
    property var frame: null
    readonly property bool hasContent: sharedCapture ? !!frame?.ready
        : captureLoader.item ? captureLoader.item.hasContent : false
    readonly property string caption: String(client?.title || client?.appClass || client?.appId || '')
    readonly property string appName: String(client?.appId || client?.appClass || '')
    readonly property bool themeIconAvailable: [client?.appId, client?.appClass]
        .some(name => name && Quickshell.hasThemeIcon(String(name)))
    property bool sourceStopped: false
    radius: 4
    color: Qt.alpha(Theme.tokens.text, 0.08)
    clip: true
    Accessible.name: caption
    Accessible.role: Accessible.Graphic

    function iconPath() {
        const names = [client?.appId, client?.appClass, 'application-x-executable'];
        for (const name of names) {
            if (name && Quickshell.hasThemeIcon(String(name))) return Quickshell.iconPath(String(name), true);
        }
        return Qt.resolvedUrl('../../assets/icons/material/media/description-symbolic.svg').toString();
    }

    onSourceChanged: sourceStopped = false
    Loader {
        id: captureLoader
        anchors.fill: parent
        active: !root.sharedCapture && root.captureEnabled && root.source !== null && root.source !== undefined && !root.sourceStopped
        sourceComponent: ScreencopyView {
            captureSource: root.captureEnabled && !root.sourceStopped ? root.source : null
            live: false
            paintCursor: false
            constraintSize: Qt.size(root.width * Screen.devicePixelRatio, root.height * Screen.devicePixelRatio)
            onStopped: root.sourceStopped = true
        }
    }
    // Samples the shared frozen texture directly (with its mipmaps) instead of re-rendering it
    // through a second offscreen pass, which kept full-size texels and blurred small text.
    Loader {
        anchors.fill: parent
        active: root.sharedCapture && root.hasContent && !!root.frame?.texture
        sourceComponent: ShaderEffect {
            property variant source: root.frame.texture
        }
    }
    Item {
        anchors.fill: parent
        visible: !root.hasContent
        Text {
            visible: root.showFallbackTitle && root.width >= 104 && root.height >= 64
            anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
            anchors.margins: 4
            text: root.caption
            color: Qt.alpha(Theme.tokens.text, 0.6)
            font.family: Theme.tokens.fontFamily
            font.pixelSize: 12
            elide: Text.ElideRight
            horizontalAlignment: Text.AlignHCenter
        }
    }
    PentadIcon {
        visible: root.showIconWithContent || !root.hasContent
        anchors.centerIn: parent
        pixelSize: Math.min(48, Math.max(24, Math.min(root.width, root.height) * 0.4))
        source: root.iconPath()
        symbolic: !root.themeIconAvailable
        color: Qt.alpha(Theme.tokens.text, 0.6)
    }
}
