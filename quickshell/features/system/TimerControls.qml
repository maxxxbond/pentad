import QtQuick
import qs.components
import qs.theme
import "../../logic/clock.mjs" as ClockLogic

Column {
    id: root
    required property var controller
    required property var services
    required property int defaultDurationSeconds
    readonly property var timerState: controller ? controller.timerState : ClockLogic.idleTimerState()
    property string pendingRequestId: ""
    property string errorMessage: ""
    readonly property bool canControl: !!controller && !services.preview && !services.safeMode
    spacing: 8
    width: 220

    function request(action) {
        if (!canControl) {
            errorMessage = services.preview ? "Preview is read only" : "Read only in safe mode";
            return;
        }
        errorMessage = "";
        pendingRequestId = controller.timerCommand(action, defaultDurationSeconds);
    }

    Connections {
        target: root.controller
        function onCommandFinished(requestId, result) {
            if (requestId !== root.pendingRequestId) return;
            root.pendingRequestId = "";
            root.errorMessage = result.ok ? "" : result.reason === "denied"
                ? (root.services.preview ? "Preview is read only" : "Read only in safe mode")
                : result.reason === "invalid-duration" ? "Timer duration must be 1–86400 seconds"
                : "Timer action is unavailable";
        }
    }

    PentadText { text: "Timer"; role: "section" }
    Text {
        text: root.timerState.status === "finished" ? "Finished"
            : root.timerState.status === "idle" ? "Not started"
            : ClockLogic.formatTimer(root.timerState.remainingSeconds)
        color: Theme.tokens.text
        font.family: Theme.tokens.fontFamily
        font.pixelSize: 24
        font.weight: Font.Medium
        font.letterSpacing: -0.3
        font.features: { "tnum": 1 }
        Accessible.name: text
    }
    Row {
        spacing: 8
        PentadButton {
            text: root.timerState.status === "running" ? "Pause"
                : root.timerState.status === "paused" ? "Resume"
                : root.timerState.status === "finished" ? "Restart"
                : "Start · " + ClockLogic.formatTimer(root.defaultDurationSeconds)
            requestedEnabled: root.canControl && !root.pendingRequestId
            onPressed: root.request(root.timerState.status === "running" ? "pause"
                : root.timerState.status === "paused" ? "resume" : "start")
        }
        PentadButton {
            text: "Reset"
            visible: root.timerState.status !== "idle"
            requestedEnabled: root.canControl && !root.pendingRequestId
            onPressed: root.request("reset")
        }
    }
    PentadText {
        visible: !!root.errorMessage || !root.canControl
        text: root.errorMessage || (root.services.preview ? "Preview is read only" : "Read only in safe mode")
        role: "caption"
        color: Theme.tokens.error
    }
}
