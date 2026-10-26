import QtQuick
import QtQuick.Controls.Basic
import qs.theme
import "../logic/hint-warmth.mjs" as HintWarmth

// The one passive hint: a PentadBubble on the item it is declared in, shown while `shown` holds. It waits
// Metrics.tooltipDelay, or nothing when another hint was on screen a moment ago, and never takes focus.
// A popup cannot let the pointer through, so the hint steps aside instead: the pointer entering it hides it
// until `shown` drops and rises again.
PentadBubble {
    id: hint
    property bool shown: false
    property int delay: Metrics.tooltipDelay
    property bool dodged: false
    focus: false
    closePolicy: Popup.NoAutoClose
    onShownChanged: {
        if (!shown) dodged = false;
        sync();
    }
    onTextChanged: sync()
    onHoveredChanged: if (hovered) {
        dodged = true;
        sync();
    }
    onVisibleChanged: visible ? HintWarmth.hintShown() : HintWarmth.hintHidden()
    Component.onCompleted: sync()
    Component.onDestruction: if (visible) HintWarmth.hintHidden()

    function sync() {
        if (!shown || dodged || text === "") {
            wait.stop();
            close();
        } else if (!visible && !wait.running) {
            if (delay <= 0 || HintWarmth.hintsWarm()) open();
            else wait.restart();
        }
    }

    Timer {
        id: wait
        interval: hint.delay
        onTriggered: if (hint.shown && !hint.dodged && hint.text !== "") hint.open()
    }
}
