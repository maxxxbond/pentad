import QtQuick
import QtQuick.Controls.Basic
import qs.theme

// A quiet "?" that explains one setting in a PentadBubble. Resting the pointer or moving keyboard focus onto it
// shows the bubble passively; a click pins it and gives it focus, so its action is reachable.
// The bubble can lead with a short clip or image (`helpMedia`) and end with one action (`helpActionText`).
PentadButton {
    id: control
    required property string helpText
    // A video (mp4, webm, mkv, mov, ogv) loops muted; anything else is shown as a still or animated image.
    property url helpMedia: ""
    property real helpMediaRatio: 16 / 9
    property string helpActionText: ""
    // Opened externally when set; the action shows the "open in new" mark only then.
    property url helpActionUrl: ""
    signal helpActionTriggered()
    readonly property alias helpPopup: explanation
    readonly property alias helpLabel: explanation.label
    readonly property alias helpAction: explanation.action
    readonly property alias helpHoverTimer: hoverDelay
    // A pinned bubble came from a click or Space and stays until Escape or a press elsewhere.
    property bool pinned: false
    readonly property bool engaged: hovered || visualFocus || explanation.visible
    text: "?"
    accessibleName: "Information"
    Accessible.description: helpText
    implicitWidth: 24
    controlHeight: 24
    iconSize: Metrics.panelIcon
    checked: explanation.visible
    onClicked: {
        if (explanation.visible && pinned) {
            explanation.close();
            return;
        }
        pinned = true;
        if (explanation.visible) explanation.contentItem.forceActiveFocus();
        else explanation.open();
    }
    onHoveredChanged: {
        if (hovered) {
            leaveGrace.stop();
            if (!explanation.visible) hoverDelay.restart();
        } else {
            hoverDelay.stop();
            if (explanation.visible && !pinned) leaveGrace.restart();
        }
    }
    onVisualFocusChanged: if (visualFocus && !explanation.visible) explanation.open()
    onActiveFocusChanged: if (!activeFocus && explanation.visible && !pinned) leaveGrace.restart()
    Keys.onEscapePressed: event => {
        event.accepted = explanation.visible;
        explanation.close();
    }

    Timer {
        id: hoverDelay
        interval: Metrics.tooltipDelay
        onTriggered: if (control.hovered && !explanation.visible) explanation.open()
    }
    // A short grace lets the pointer cross from the "?" onto the bubble without it closing.
    Timer {
        id: leaveGrace
        interval: 160
        onTriggered: if (!control.pinned && !control.hovered && !explanation.hovered && !control.activeFocus)
            explanation.close()
    }

    contentItem: Item {
        implicitWidth: control.iconSize
        implicitHeight: control.iconSize
        PentadIcon {
            anchors.centerIn: parent
            visible: !explanation.visible
            source: Qt.resolvedUrl("../assets/icons/pentad/help-symbolic.svg")
            pixelSize: control.iconSize
            color: control.engaged ? Theme.tokens.text : Qt.alpha(Theme.tokens.textMuted, 0.9)
            Accessible.ignored: true
            Behavior on color { enabled: !Theme.tokens.reducedMotion; ColorAnimation { duration: Motion.short } }
        }
        // While the explanation is open the mark turns into a solid accent dot, so the tail has something to point at.
        Rectangle {
            anchors.centerIn: parent
            visible: explanation.visible
            width: control.iconSize + 2
            height: width
            radius: width / 2
            color: Theme.tokens.accent
            PentadIcon {
                anchors.centerIn: parent
                source: Qt.resolvedUrl("../assets/icons/pentad/question-symbolic.svg")
                pixelSize: control.iconSize - 4
                color: Theme.tokens.onAccent
                Accessible.ignored: true
            }
        }
    }
    background: Rectangle {
        radius: width / 2
        color: control.down && !explanation.visible ? Theme.tokens.surfaceOverlay
            : control.hovered && !explanation.visible ? Qt.alpha(Theme.tokens.text, 0.06) : "transparent"
        border.width: control.visualFocus ? 2 : 0
        border.color: Theme.tokens.accent
        Behavior on color { enabled: !Theme.tokens.reducedMotion; ColorAnimation { duration: Motion.short } }
    }

    PentadBubble {
        id: explanation
        objectName: "info-button-explanation"
        text: control.helpText
        media: control.helpMedia
        mediaRatio: control.helpMediaRatio
        actionText: control.helpActionText
        actionUrl: control.helpActionUrl
        onActionTriggered: control.helpActionTriggered()
        // A passive bubble must not take keyboard focus from wherever it is.
        focus: control.pinned
        // Both flags: a press closes it only outside the bubble and outside the "?", which toggles it itself.
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside | Popup.CloseOnPressOutsideParent
        onClosed: {
            control.pinned = false;
            leaveGrace.stop();
        }
        onHoveredChanged: {
            if (hovered) leaveGrace.stop();
            else if (!control.pinned && !control.hovered) leaveGrace.restart();
        }
    }
}
