pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import qs.components
import qs.theme

// Applications capturing a hardware microphone as a bar status icon: hidden while nobody listens,
// and the hint names who does. No click action.
Item {
    id: root
    objectName: "bar-microphone-indicator"
    required property var services
    readonly property var audioState: services.audio.state
    readonly property var microphone: audioState.kind === "ready" && audioState.value.microphone ? audioState.value.microphone : null
    readonly property bool active: !!microphone && microphone.active === true
    readonly property bool muted: active && microphone.muted === true
    readonly property string hint: !active ? ""
        : (muted ? text("Мікрофон вимкнено: ", "Microphone muted: ") : text("Мікрофон: ", "Microphone: "))
            + (microphone.apps || []).map(function(app) { return app.label; }).join(", ")

    function text(uk, en) { return typeof services.text === "function" ? services.text(uk, en) : en; }

    implicitWidth: Metrics.statusIcon
    implicitHeight: Metrics.statusIcon
    visible: active

    PentadIcon {
        objectName: "bar-microphone-icon"
        anchors.fill: parent
        pixelSize: Metrics.statusIcon
        color: Theme.tokens.warning
        accessibleName: root.hint
        source: Quickshell.iconPath(root.muted ? "microphone-disabled-symbolic" : "microphone-sensitivity-high-symbolic")
    }
    MouseArea { id: pointer; anchors.fill: parent; hoverEnabled: true; acceptedButtons: Qt.NoButton }
    PentadToolTip {
        objectName: "microphone-tooltip"
        visible: pointer.containsMouse
        text: root.hint
    }
}
