import QtQuick
import QtQml
import Quickshell
import qs.features.system
import "../widgets/clock" as ClockWidgets
import "../logic/clock.mjs" as ClockLogic

ShellRoot {
    id: root
    property string mode: Quickshell.env("PENTAD_CLOCK_TIMER_MODE") || "normal"
    property int phase: 0
    property var checks: []
    property string lastRequestId: ""
    property var lastResult: null
    property int writes: 0
    property bool finished: false
    property QtObject fakeClock: QtObject {
        property date date: new Date(2026, 0, 2, 3, 4, 5)
        property var locale: Qt.locale("en_US")
    }
    property QtObject fakeConfig: QtObject {
        property var documents: ({ layout: { showSeconds: true } })
        function save() { root.writes++; }
    }
    property QtObject fakeServices: QtObject {
        property bool preview: root.mode === "preview"
        property bool safeMode: root.mode === "safe-mode"
        readonly property var clock: root.fakeClock
        readonly property var config: root.fakeConfig
    }
    property ClockWidgets.Controller first: ClockWidgets.Controller {
        instanceId: "clock-placement-one"
        settings: ({ defaultDurationSeconds: 2 })
        services: root.fakeServices
        onCommandFinished: function(requestId, result) {
            root.lastRequestId = requestId;
            root.lastResult = result;
        }
    }
    property ClockWidgets.Controller second: ClockWidgets.Controller {
        instanceId: "clock-placement-two"
        settings: ({ defaultDurationSeconds: 2 })
        services: root.fakeServices
    }
    property var controls: null

    FloatingWindow {
        visible: false
        implicitWidth: 260
        implicitHeight: 220
        TimerControls {
            id: controlsItem
            controller: root.first
            services: root.fakeServices
            defaultDurationSeconds: 2
            visible: false
            Component.onCompleted: root.controls = controlsItem
        }
    }

    function check(name, passed, detail) {
        checks.push({ name: name, passed: passed === true, detail: detail || "" });
    }
    function finish() {
        if (finished) return;
        finished = true;
        fixtureTimer.stop();
        console.log("PENTAD_TEST " + JSON.stringify({
            status: checks.every(function(item) { return item.passed; }) ? "pass" : "fail",
            checks: checks
        }));
        Qt.quit();
    }

    Timer {
        id: fixtureTimer
        interval: 25
        repeat: true
        running: true
        onTriggered: {
            if (root.phase === 0 && root.controls) {
                root.check("TimerControls component loads", true);
                root.check("clock time/date and showSeconds API remains available",
                    root.first.time.length > 0 && root.first.date.length > 0 && root.first.showSeconds);
                root.check("controllers are placement-scoped", root.first.timerState.status === "idle"
                    && root.second.timerState.status === "idle" && root.first.timer !== root.second.timer);
                root.check("default duration formats like legacy clock timer",
                    ClockLogic.formatTimer(root.controls.defaultDurationSeconds) === "00:02");
                if (root.mode === "preview" || root.mode === "safe-mode") {
                    var deniedId = root.first.timerCommand("start", 2);
                    root.check("guarded action returns a placement request ID", deniedId.indexOf("clock-clock-placement-one-") === 0,
                        JSON.stringify({ deniedId: deniedId, lastRequestId: root.lastRequestId }));
                    root.phase = 10;
                } else {
                    root.lastResult = null;
                    root.lastRequestId = root.first.timerCommand("start", 86401);
                    root.phase = 1;
                }
            } else if (root.phase === 10 && root.lastResult) {
                root.check("preview and safe mode deny timer actions", !root.lastResult.ok
                    && root.lastResult.reason === "denied" && root.first.timerState.status === "idle");
                root.check("timer operations do not write config documents", root.writes === 0);
                root.finish();
                stop();
            } else if (root.phase === 1 && root.lastResult) {
                root.check("invalid duration reports an asynchronous request error",
                    !root.lastResult.ok && root.lastResult.reason === "invalid-duration"
                    && root.lastRequestId.indexOf("clock-clock-placement-one-") === 0,
                    JSON.stringify({ requestId: root.lastRequestId, result: root.lastResult }));
                root.lastResult = null;
                root.controls.request("start");
                root.phase = 2;
            } else if (root.phase === 2 && root.first.timerState.status === "running") {
                root.check("TimerControls starts its configured default and changes only this placement",
                    root.first.timerState.durationSeconds === root.controls.defaultDurationSeconds
                    && root.second.timerState.status === "idle");
                root.controls.request("pause");
                root.phase = 3;
            } else if (root.phase === 3 && root.first.timerState.status === "paused") {
                root.controls.request("resume");
                root.phase = 4;
            } else if (root.phase === 4 && root.first.timerState.status === "finished") {
                root.controls.request("reset");
                root.phase = 5;
            } else if (root.phase === 5 && root.first.timerState.status === "idle") {
                root.check("native controller supports start, pause, resume, finish and reset", true);
                root.check("timer operations do not write config documents", root.writes === 0);
                root.finish();
                stop();
            }
        }
    }
}
