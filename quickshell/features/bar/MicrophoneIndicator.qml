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

    readonly property string iconName: muted ? "microphone-disabled-symbolic" : "microphone-sensitivity-high-symbolic"
    // Empty when the icon theme lacks the name; the glyph below keeps the privacy signal drawn.
    readonly property string iconSource: Quickshell.iconPath(iconName, true)

    PentadIcon {
        objectName: "bar-microphone-icon"
        anchors.fill: parent
        visible: !!root.iconSource
        pixelSize: Metrics.statusIcon
        color: Theme.tokens.warning
        accessibleName: root.hint
        source: root.iconSource
    }
    Text {
        objectName: "bar-microphone-glyph"
        anchors.fill: parent
        visible: !root.iconSource
        text: root.muted ? "mic_off" : "mic"
        color: Theme.tokens.warning
        font.family: "Material Symbols Rounded"
        font.pixelSize: Metrics.statusIcon
        font.weight: Font.Medium
        font.variableAxes: ({ FILL: 1, wght: 500, GRAD: 0, opsz: Metrics.statusIcon })
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        Accessible.name: root.hint
    }
    MouseArea { id: pointer; anchors.fill: parent; hoverEnabled: true; acceptedButtons: Qt.NoButton }
    PentadToolTip {
        objectName: "microphone-tooltip"
        visible: pointer.containsMouse
        text: root.hint
    }
}
