import QtQuick
import qs.components
import qs.theme

// A circle with a caption; the first press arms it, a second press within two seconds runs it.
Item {
    id: root

    required property var context
    property url iconSource: ""
    property string label: ""
    property bool armed: false

    signal confirmed

    implicitWidth: Math.max(button.implicitWidth, caption.implicitWidth)
    implicitHeight: button.implicitHeight + Metrics.statusGap + caption.implicitHeight

    Timer {
        id: disarm
        interval: 2000
        onTriggered: root.armed = false
    }

    PentadButton {
        id: button
        anchors.horizontalCenter: parent.horizontalCenter
        controlHeight: Metrics.controlLarge
        iconSource: root.iconSource
        focusPolicy: Qt.NoFocus
        restFill: root.armed ? Theme.tokens.surfaceOverlay : Qt.alpha(Theme.tokens.surfaceRaised, 0.72)
        accessibleName: root.label
        onClicked: {
            if (root.armed) {
                disarm.stop();
                root.armed = false;
                root.confirmed();
            } else {
                root.armed = true;
                disarm.restart();
            }
        }
    }

    PentadText {
        id: caption
        anchors.top: button.bottom
        anchors.topMargin: Metrics.statusGap
        anchors.horizontalCenter: parent.horizontalCenter
        role: "caption"
        wrapMode: Text.NoWrap
        textFormat: Text.PlainText
        color: root.armed ? Theme.tokens.text : Theme.tokens.textMuted
        text: root.armed ? root.context.text("Ще раз", "Again") : root.label
    }
}
