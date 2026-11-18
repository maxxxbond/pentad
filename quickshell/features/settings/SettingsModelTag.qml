import QtQuick
import QtQuick.Controls.Basic
import qs.components
import qs.theme

// A small capsule on the Models page: a model capability ("vision", "tools"), a size, a status with a
// leading dot, or (interactive) a provider kind to add. The ink is a group hue or muted text; the
// fill is the next tonal step, tinted with the hue, never an accent flood.
AbstractButton {
    id: root
    property color ink: Theme.tokens.textMuted
    property color base: Theme.tokens.surfaceOverlay
    property bool dot: false
    property bool interactive: false
    property url iconSource: ""
    readonly property bool tinted: ink !== Theme.tokens.textMuted
    readonly property real stateLayer: interactive && down ? Metrics.statePressed : interactive && hovered ? Metrics.stateHover : 0
    implicitHeight: interactive ? Metrics.controlSmall - Metrics.space1 : Metrics.space5 - Metrics.space1
    implicitWidth: row.implicitWidth + 2 * Metrics.space2
    padding: 0
    focusPolicy: interactive ? Qt.StrongFocus : Qt.NoFocus
    hoverEnabled: interactive
    // A static tag takes no input, so a press or hover reaches the control under it.
    enabled: interactive
    Accessible.role: interactive ? Accessible.Button : Accessible.StaticText
    Accessible.name: text
    Keys.onPressed: function(event) {
        if (root.interactive && (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)) {
            root.clicked();
            event.accepted = true;
        }
    }

    background: Rectangle {
        readonly property color fill: root.tinted ? Qt.tint(root.base, Qt.alpha(root.ink, 0.12)) : root.base
        radius: Metrics.radiusPill
        color: root.stateLayer > 0 ? Qt.tint(fill, Qt.alpha(Theme.tokens.text, root.stateLayer)) : fill
        border.width: root.visualFocus ? 1 : 0
        border.color: Theme.tokens.accent
        Behavior on color { enabled: !Theme.tokens.reducedMotion; ColorAnimation { duration: Motion.state } }
    }
    contentItem: Item {
        Row {
            id: row
            anchors.centerIn: parent
            spacing: Metrics.space1
            Rectangle {
                visible: root.dot
                anchors.verticalCenter: parent.verticalCenter
                width: Metrics.space2 - 2
                height: width
                radius: width / 2
                color: root.ink
            }
            PentadIcon {
                visible: root.iconSource.toString() !== ""
                anchors.verticalCenter: parent.verticalCenter
                source: root.iconSource
                pixelSize: Metrics.textCaption
                color: root.ink
                Accessible.ignored: true
            }
            PentadText {
                anchors.verticalCenter: parent.verticalCenter
                text: root.text
                textFormat: Text.PlainText
                role: "caption"
                wrapMode: Text.NoWrap
                color: root.interactive && root.hovered && !root.tinted ? Theme.tokens.text : root.ink
                font.features: ({ tnum: 1 })
            }
        }
    }
}
