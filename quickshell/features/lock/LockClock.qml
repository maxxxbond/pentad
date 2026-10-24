pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import qs.components
import qs.theme

// Time over date; each digit rolls on its own when it changes.
Item {
    id: root

    required property var context
    readonly property string time: Qt.formatTime(clock.date, "HH:mm")

    implicitWidth: Math.max(digits.width, date.implicitWidth)
    implicitHeight: digits.height + date.implicitHeight

    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }

    TextMetrics {
        id: digitMetrics
        font.family: Theme.tokens.fontFamily
        font.pixelSize: Metrics.lockClock
        font.weight: Font.Light
        text: "0"
    }

    component Glyph: Text {
        color: Theme.tokens.text
        horizontalAlignment: Text.AlignHCenter
        textFormat: Text.PlainText
        font.family: Theme.tokens.fontFamily
        font.pixelSize: Metrics.lockClock
        font.weight: Font.Light
    }

    // One clipped cell: the old glyph slides up and fades while the new one rises from below.
    component Digit: Item {
        id: cell

        property string value: ""
        property string shown: ""
        property string previous: ""

        width: Math.ceil(digitMetrics.advanceWidth)
        height: Math.ceil(digitMetrics.height)
        clip: true

        Glyph {
            id: current
            width: cell.width
            text: cell.shown
        }

        Glyph {
            id: old
            width: cell.width
            text: cell.previous
            opacity: 0
        }

        onValueChanged: {
            if (shown === "" || Theme.tokens.reducedMotion) {
                shown = value;
                return;
            }
            if (value === shown)
                return;
            roll.stop();
            previous = shown;
            shown = value;
            roll.start();
        }

        ParallelAnimation {
            id: roll
            NumberAnimation { target: current; property: "y"; from: cell.height / 2; to: 0; duration: Motion.long * 1.4; easing.type: Easing.OutCubic }
            NumberAnimation { target: current; property: "opacity"; from: 0; to: 1; duration: Motion.long * 1.4; easing.type: Easing.OutCubic }
            NumberAnimation { target: old; property: "y"; from: 0; to: -cell.height / 2; duration: Motion.long * 1.4; easing.type: Easing.OutCubic }
            NumberAnimation { target: old; property: "opacity"; from: 1; to: 0; duration: Motion.long * 1.4; easing.type: Easing.OutCubic }
        }
    }

    Row {
        id: digits
        anchors.horizontalCenter: parent.horizontalCenter

        Digit { value: root.time.charAt(0) }
        Digit { value: root.time.charAt(1) }
        Glyph {
            width: Math.ceil(digitMetrics.advanceWidth / 2)
            height: Math.ceil(digitMetrics.height)
            text: ":"
        }
        Digit { value: root.time.charAt(3) }
        Digit { value: root.time.charAt(4) }
    }

    PentadText {
        id: date
        anchors.top: digits.bottom
        anchors.horizontalCenter: parent.horizontalCenter
        role: "title"
        solid: true
        wrapMode: Text.NoWrap
        textFormat: Text.PlainText
        color: Theme.tokens.textMuted
        text: root.context.locale.toString(clock.date, root.context.ukrainian ? "dddd, d MMMM" : "dddd, MMMM d")
    }
}
