import QtQuick
import QtQuick.Controls.Basic
import qs.theme
import "../logic/spring.mjs" as SpringLogic

// A capsule you press and hold to confirm: a fill grows under the press and the action fires when
// it reaches the end. Let go early and the fill springs back (the release spring) while the
// capsule squashes and rebounds (the morph spring); the label then reminds you to hold. Both
// springs use the stiffness and damping of the motion study they were drawn from.
//
// The fill itself is the safety delay, so it keeps its pace under reduced motion; only the spring
// movement is dropped then. Space held on the focused button fills it too.
//
// The caller passes the labels (`text`, `hintText`) and listens for confirmed(). After the hold
// lands the fill stays full until reset(), or until the button is hidden.
Button {
    id: root
    property url iconSource: ""
    // Shown for a moment after an early release; empty keeps the label as it is.
    property string hintText: ""
    property bool destructive: false
    property int holdDuration: 900
    property int iconSize: Metrics.statusIcon
    signal confirmed()

    // Fill level 0..1: the held fill while pressed, the release spring while it springs back.
    readonly property real progress: Math.max(0, Math.min(1, draining ? releaseSpring.value : fillLevel))
    readonly property real holdProgress: progress
    readonly property color tint: destructive ? Theme.tokens.error : Theme.tokens.accent

    property real fillLevel: 0
    property bool draining: false
    property bool holdHint: false
    property bool landed: false

    function preset(name) {
        return SpringLogic.holdSprings[name];
    }
    function reset() {
        fill.stop();
        hintTimer.stop();
        draining = false;
        landed = false;
        holdHint = false;
        fillLevel = 0;
        releaseSpring.snap();
        morphSpring.target = 1;
    }

    implicitHeight: Metrics.controlMedium + 4
    implicitWidth: 208
    hoverEnabled: true
    scale: morphSpring.value

    onPressedChanged: {
        if (pressed) {
            holdHint = false;
            hintTimer.stop();
            draining = false;
            if (landed)
                return;
            fill.duration = Math.max(1, (1 - fillLevel) * holdDuration);
            fill.start();
            morphSpring.target = 0.97;
        } else {
            morphSpring.target = 1;
            if (landed)
                return;
            fill.stop();
            if (fillLevel > 0) {
                releaseSpring.jump(fillLevel);
                draining = true;
            }
            if (hintText !== "") {
                holdHint = true;
                hintTimer.restart();
            }
        }
    }
    onVisibleChanged: if (!visible) reset()

    PentadSpring { id: releaseSpring; stiffness: root.preset("release")[0]; damping: root.preset("release")[1]; target: 0 }
    PentadSpring { id: morphSpring; stiffness: root.preset("morph")[0]; damping: root.preset("morph")[1]; value: 1; target: 1 }

    NumberAnimation {
        id: fill
        target: root
        property: "fillLevel"
        to: 1
        duration: root.holdDuration
        easing.type: Easing.InOutQuad
        onFinished: {
            root.landed = true;
            morphSpring.target = 1;
            morphSpring.kick(1.05);
            root.confirmed();
        }
    }
    Timer {
        id: hintTimer
        interval: 1600
        onTriggered: root.holdHint = false
    }
    // Runs only while a spring moves; a button at rest does no work.
    FrameAnimation {
        running: root.visible && (root.draining || !morphSpring.settled)
        onTriggered: {
            releaseSpring.advance(frameTime);
            morphSpring.advance(frameTime);
            if (root.draining && releaseSpring.settled) {
                root.draining = false;
                root.fillLevel = 0;
            }
        }
    }

    background: Rectangle {
        radius: height / 2
        color: root.destructive && (root.hovered || root.pressed) ? Qt.alpha(Theme.tokens.error, 0.18)
            : root.hovered || root.pressed ? Theme.tokens.surfaceOverlay : "transparent"
        border.width: root.visualFocus ? 1 : 0
        border.color: Theme.tokens.accent
        Behavior on color { ColorAnimation { duration: Motion.state } }
        Rectangle {
            objectName: "hold-button-fill"
            height: parent.height
            width: height + (parent.width - height) * root.progress
            radius: height / 2
            opacity: Math.min(1, root.progress * 6)
            color: Qt.alpha(root.tint, 0.32)
        }
    }

    contentItem: Item {
        opacity: root.enabled ? 1 : 0.45
        PentadIcon {
            id: glyph
            x: 6
            anchors.verticalCenter: parent.verticalCenter
            visible: root.iconSource.toString() !== ""
            source: root.iconSource
            pixelSize: root.iconSize
            color: root.destructive && root.hovered ? Theme.tokens.error : Theme.tokens.text
            Behavior on color { ColorAnimation { duration: Motion.state } }
        }
        Text {
            anchors.left: glyph.visible ? glyph.right : parent.left
            anchors.leftMargin: Metrics.space3
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: root.holdHint ? root.hintText : root.text
            color: root.holdHint ? Theme.tokens.textMuted
                : root.destructive && root.hovered ? Theme.tokens.error : Theme.tokens.text
            font.family: Theme.tokens.fontFamily
            font.pixelSize: Metrics.textBody
            elide: Text.ElideRight
        }
    }
}
