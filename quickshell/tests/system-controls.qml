import QtQuick
import Quickshell
import qs.services
import qs.features.system

ShellRoot {
    id: root
    property var checks: []
    property string denial: ""

    property Services services: Services { preview: true; safeMode: true }
    readonly property var brightness: panel.brightness
    readonly property var control: panel.brightnessControl
    property var fakeRequests: []
    property int fakeSerial: 0
    property string fakeLatestId: ""
    property bool brightnessWheelPassed: false
    property var fakeBrightness: QtObject {
        property bool active: true
        property bool safeMode: false
        property var state: ({ kind: "ready", value: 0.5 })
        property var operation: null
        signal commandFinished(string requestId, var result)
        function adjust(steps) {
            const requestId = "fake-" + (++root.fakeSerial);
            root.fakeRequests = root.fakeRequests.concat([{ id: requestId, steps: steps }]);
            root.fakeLatestId = requestId;
            return requestId;
        }
    }
    Component.onCompleted: {
        services.popups.open('right', 'fixture-output');
        Qt.callLater(function() {
            wheelControl.brightnessSlider.handleWheel({ pixelDelta: { y: 40 }, angleDelta: { y: 0 }, accepted: false });
            root.brightnessWheelPassed = root.fakeRequests.length === 1 && root.fakeRequests[0].steps === 1;
            root.fakeBrightness.commandFinished(root.fakeLatestId, { ok: true, value: 0.55 });
            Qt.callLater(function() {
                raceControl.requestBrightness(0.8);
                raceControl.requestBrightness(0.2);
                const staleId = root.fakeLatestId;
                root.fakeBrightness.commandFinished(staleId, { ok: false, reason: "stale-failure" });
                Qt.callLater(function() {
                    root.checks.push({ name: "brightness-wheel-dispatches-one-backend-step", passed: root.brightnessWheelPassed });
                    root.checks.push({ name: "brightness-retries-latest-direction-after-stale-failure",
                        passed: root.fakeRequests.length === 3 && root.fakeRequests[1].steps > 0 && root.fakeRequests[2].steps < 0 });
                });
            });
        });
    }
    FloatingWindow {
        visible: true
        implicitWidth: 480
        implicitHeight: 700
        RightPanel { id: panel; x: 20; y: 20; width: 420; services: root.services; outputId: "fixture-output" }
    }
    BrightnessControls { width: 400; brightness: root.fakeBrightness; services: root.services; visible: false }
    BrightnessControls { id: wheelControl; width: 400; brightness: root.fakeBrightness; services: root.services; visible: false }
    BrightnessControls { id: raceControl; width: 400; brightness: root.fakeBrightness; services: root.services; visible: false }
    Connections {
        target: root.brightness
        function onCommandFinished(requestId, result) { root.denial = result.reason || ""; }
    }
    Timer {
        interval: 200
        running: true
        onTriggered: {
            root.checks.push({ name: "preview-brightness-is-disabled", passed: !control.canAdjust && !brightness.active });
            root.checks.push({ name: "preview-starts-no-brightness-worker", passed: brightness.operation === null && brightness.activeWorker === null });
            root.checks.push({ name: 'control-center-uses-output-shared-adapter', passed: brightness === root.services.brightnessAdapters['fixture-output'] });
            root.checks.push({ name: 'preview-network-is-unavailable-without-operations', passed: root.services.network.state.kind === 'unavailable' && root.services.network.operation === null });
            root.checks.push({ name: 'control-center-keeps-quick-settings-and-compact-ranges', passed:
                panel.quickSettingsGrid.visible && panel.brightnessControl.visible && panel.audioControls.visible });
            const requestId = brightness.adjust(1);
            Qt.callLater(function() {
                root.checks.push({ name: "preview-adjust-denied-without-worker", passed: requestId.startsWith("brightness-") && root.denial === "preview" && brightness.activeWorker === null });
                console.log("PENTAD_TEST " + JSON.stringify({ status: root.checks.every(function(check) { return check.passed }) ? "pass" : "fail", checks: root.checks }));
                stop();
                Qt.quit();
            });
        }
    }
}
