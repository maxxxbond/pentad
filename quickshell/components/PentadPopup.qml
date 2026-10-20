import QtQuick
import QtQuick.Controls.Basic
import qs.theme

Popup {
    id: control

    padding: 4
    focus: true
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

    function openFor(anchor) {
        if (anchor) {
            control.parent = anchor
            control.x = 0
            control.y = anchor.height
        }
        control.open()
    }

    background: ContinuousSurface {
        fill: Theme.tokens.surfaceRaised
        extent: Metrics.radiusLarge
    }

    enter: Transition {
        NumberAnimation {
            property: "opacity"
            from: 0
            to: 1
            duration: Motion.short
        }
    }
    exit: Transition {
        NumberAnimation {
            property: "opacity"
            from: 1
            to: 0
            duration: Motion.short
        }
    }
}
