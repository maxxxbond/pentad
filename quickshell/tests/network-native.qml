import QtQuick
import Quickshell
import "../services"
import "../features/system"

ShellRoot {
    id: root
    property var checks: []
    property var results: ({})
    property string waitingId: ""
    property var waitingCallback: null
    property int connectCalls: 0
    property int pskCalls: 0
    property string fakePsk: ""
    property bool missingCredentials: false
    property bool rejectPsk: false
    property bool deferConnect: false

    QtObject {
        id: fakeNetwork
        property var device: fakeDevice
        property string name: "Test Wi-Fi"
        property bool known: false
        property bool connected: false
        property bool stateChanging: false
        property int state: 4
        property int security: 3
        property real signalStrength: 0.76
        signal connectionFailed(int reason)
        function connect() {
            root.connectCalls++;
            if (root.deferConnect) return;
            if (root.missingCredentials) {
                Qt.callLater(function() { fakeNetwork.connectionFailed(1); });
                return;
            }
            fakeNetwork.state = 1;
            fakeNetwork.stateChanging = true;
            Qt.callLater(function() {
                fakeNetwork.connected = true;
                fakeDevice.connected = true;
                fakeNetwork.state = 2;
                fakeNetwork.stateChanging = false;
            });
        }
        function connectWithPsk(psk) {
            root.pskCalls++;
            root.fakePsk = psk;
            if (root.rejectPsk) {
                Qt.callLater(function() { fakeNetwork.connectionFailed(1); });
                return;
            }
            fakeNetwork.state = 1;
            fakeNetwork.stateChanging = true;
            Qt.callLater(function() {
                fakeNetwork.connected = true;
                fakeDevice.connected = true;
                fakeNetwork.state = 2;
                fakeNetwork.stateChanging = false;
            });
        }
        function disconnect() {
            fakeNetwork.state = 3;
            fakeNetwork.stateChanging = true;
            Qt.callLater(function() {
                fakeNetwork.connected = false;
                fakeDevice.connected = false;
                fakeNetwork.state = 4;
                fakeNetwork.stateChanging = false;
            });
        }
    }
    QtObject {
        id: fakeNetworks
        property var values: [fakeNetwork]
    }
    QtObject {
        id: fakeDevice
        property string name: "wlan0"
        property int type: 1
        property var networks: fakeNetworks
        property bool connected: false
        property bool scannerEnabled: false
    }
    QtObject {
        id: fakeDevices
        property var values: [fakeDevice]
    }
    QtObject {
        id: fakeBackend
        property int backend: 1
        property bool ready: true
        property int connectivity: 4
        property var wifiEnabled: true
        property bool wifiHardwareEnabled: true
        property var devices: fakeDevices
    }

    Network {
        id: network
        backendOverride: fakeBackend
    }
    NetworkControls { id: controls; visible: true; services: ({ network: network }) }
    Network { id: previewNetwork; preview: true }
    Connections {
        target: network
        function onCommandFinished(requestId, result) { root.record(requestId, result); }
    }
    Connections {
        target: previewNetwork
        function onCommandFinished(requestId, result) { root.record(requestId, result); }
    }
    Timer {
        interval: 30
        running: true
        onTriggered: root.startMatrix()
    }

    function check(name, passed, detail) { checks.push({ name: name, passed: passed, detail: detail || "" }); }
    function findNamed(item, name) {
        if (item.objectName === name) return item;
        const children = item.children || [];
        for (let i = 0; i < children.length; i++) {
            const found = findNamed(children[i], name);
            if (found) return found;
        }
        return null;
    }
    function record(requestId, result) {
        const next = Object.assign({}, results, { [requestId]: result });
        results = next;
        consumeResult();
    }
    function expect(requestId, callback) {
        if (!requestId) { check("request-id-returned", false); finish(); return; }
        waitingId = requestId;
        waitingCallback = callback;
        Qt.callLater(consumeResult);
    }
    function consumeResult() {
        if (!waitingId || !results[waitingId]) return;
        const result = results[waitingId];
        const callback = waitingCallback;
        const remaining = Object.assign({}, results);
        delete remaining[waitingId];
        results = remaining;
        waitingId = "";
        waitingCallback = null;
        callback(result);
    }
    function startMatrix() {
        const state = network.state;
        const wifiToggle = findNamed(controls, "networkWifiToggle");
        const emptyAccessPoints = findNamed(controls, "networkEmptyAccessPoints");
        check("wifi-ui-preserves-confirmed-boolean-state", wifiToggle && wifiToggle.checked && wifiToggle.enabled);
        fakeBackend.wifiEnabled = null;
        fakeNetworks.values = [];
        check("unknown-wifi-state-is-labeled-and-toggle-disabled", wifiToggle && !wifiToggle.enabled
            && emptyAccessPoints && emptyAccessPoints.visible && emptyAccessPoints.text === "Wi-Fi state unavailable");
        fakeBackend.wifiEnabled = true;
        fakeNetworks.values = [fakeNetwork];
        check("wifi-ui-recovers-when-confirmed-state-returns", wifiToggle && wifiToggle.checked && wifiToggle.enabled);
        controls.run("network-fixture-wifi-pending", "wifi-toggle");
        check("wifi-toggle-exposes-pending-state-by-operation-kind",
            controls.pendingWifiToggleId === "network-fixture-wifi-pending");
        controls.pendingWifiToggleId = "";
        controls.pendingRequestId = "";
        check("fake-backend-state-and-ap-list", state.kind === "ready" && state.value.accessPoints.length === 1
            && state.value.accessPoints[0].security === "WPA2" && state.value.accessPoints[0].signal === 76);
        check("preview-does-not-touch-native-singleton", previewNetwork.state.kind === "unavailable"
            && previewNetwork.nativeBackend === null && previewNetwork.operation === null);
        expect(previewNetwork.scan("wlan0"), function(result) {
            check("preview-action-denied-with-request-id", result.reason === "scan-unavailable");
            setWifi(false);
        });
    }
    function setWifi(enabled) {
        const requestId = network.setWifiEnabled(enabled);
        expect(requestId, function(result) {
            check(`wifi-${enabled ? "enable" : "disable"}-confirmed`, result.ok && fakeBackend.wifiEnabled === enabled);
            if (!enabled) setWifi(true); else startScan();
        });
    }
    function startScan() {
        expect(network.scan("wlan0"), function(result) {
            check("scan-reports-enabled-not-in-flight", result.ok && fakeDevice.scannerEnabled && network.state.value.wifiScanEnabled);
            expect(network.stopScan("wlan0"), function(stopped) {
                check("scan-stops", stopped.ok && !fakeDevice.scannerEnabled);
                connectSaved();
            });
        });
    }
    function connectSaved() {
        fakeNetwork.known = true;
        expect(network.connectNetwork(fakeNetwork.name, fakeDevice.name), function(result) {
            check("saved-connect-completes-from-state", result.ok && connectCalls === 1 && fakeNetwork.connected);
            expect(network.disconnectNetwork(fakeNetwork.name, fakeDevice.name), function(disconnected) {
                check("disconnect-completes-from-state", disconnected.ok && !fakeNetwork.connected);
                connectNeedsSecrets();
            });
        });
    }
    function connectNeedsSecrets() {
        fakeNetwork.known = false;
        missingCredentials = true;
        expect(network.connectNetwork(fakeNetwork.name, fakeDevice.name), function(result) {
            check("no-secrets-is-reported-for-ui-prompt", result.reason === "secrets-required");
            check("operation-cleared-after-no-secrets", network.operation === null);
            retryWrongPassword();
        });
    }
    function retryWrongPassword() {
        rejectPsk = true;
        expect(network.connectNetwork(fakeNetwork.name, fakeDevice.name, "wrong-test-only"), function(result) {
            check("psk-is-passed-only-to-native-method", result.reason === "secrets-required"
                && pskCalls === 1 && fakePsk === "wrong-test-only");
            check("secret-is-not-kept-in-operation", network.operation === null);
            retryCorrectPassword();
        });
    }
    function retryCorrectPassword() {
        rejectPsk = false;
        expect(network.connectNetwork(fakeNetwork.name, fakeDevice.name, "right-test-only"), function(result) {
            check("psk-retry-connects", result.ok && fakeNetwork.connected && pskCalls === 2);
            rejectEnterpriseCredentials();
        });
    }
    function rejectEnterpriseCredentials() {
        fakeNetwork.security = 2;
        const callsBefore = pskCalls;
        expect(network.connectNetwork(fakeNetwork.name, fakeDevice.name, "enterprise-test-only"), function(result) {
            check("enterprise-credential-path-is-unsupported", result.reason === "credentials-unsupported"
                && pskCalls === callsBefore);
            invalidateRemovedDevice();
        });
    }
    function invalidateRemovedDevice() {
        fakeNetwork.security = 10;
        deferConnect = true;
        const requestId = network.connectNetwork(fakeNetwork.name, fakeDevice.name);
        fakeDevices.values = [];
        expect(requestId, function(result) {
            check("removed-device-invalidates-pending-request", result.reason === "network-removed"
                && network.operation === null);
            testBusyRequestIds();
        });
        consumeResult();
    }
    function testBusyRequestIds() {
        deferConnect = false;
        fakeDevices.values = [fakeDevice];
        const callsBefore = connectCalls;
        const activeId = network.connectNetwork(fakeNetwork.name, fakeDevice.name);
        const busyId = network.connectNetwork(fakeNetwork.name, fakeDevice.name);
        check("busy-request-gets-distinct-id-without-native-action", !!busyId && busyId !== activeId
            && connectCalls === callsBefore + 1 && network.operation.requestId === activeId);
        expect(busyId, function(result) {
            check("busy-completion-correlates-to-returned-id", result.reason === "busy");
            fakeNetwork.connectionFailed(0);
            Qt.callLater(function() {
                check("active-request-completes-separately", network.operation === null);
                reconnectService();
            });
        });
    }
    function reconnectService() {
        fakeNetwork.connected = false;
        fakeDevice.connected = false;
        fakeNetwork.known = true;
        missingCredentials = false;
        deferConnect = true;
        const requestId = network.connectNetwork(fakeNetwork.name, fakeDevice.name);
        fakeBackend.ready = false;
        expect(requestId, function(result) {
            check("backend-loss-cancels-pending-command", result.reason === "service-missing"
                && network.operation === null && network.state.kind === "unavailable");
            fakeBackend.ready = true;
            deferConnect = false;
            Qt.callLater(function() {
                check("backend-reconnect-restores-observed-state", network.state.kind === "ready"
                    && network.state.value.devices.length === 1);
                expect(network.connectNetwork(fakeNetwork.name, fakeDevice.name), function(reconnected) {
                    check("command-works-after-backend-reconnect", reconnected.ok && fakeNetwork.connected,
                        JSON.stringify({ result: reconnected, connected: fakeNetwork.connected,
                            backend: network.state.kind, operation: network.operation }));
                    testWifiDeviceRemoval();
                });
            });
        });
    }
    function testWifiDeviceRemoval() {
        fakeDevices.values = [fakeDevice];
        const requestId = network.begin("wifi", false);
        expect(requestId, function(result) {
            check("wifi-device-removal-cancels-pending-global-toggle",
                result.reason === "device-removed" && network.operation === null);
            finish();
        });
        fakeDevices.values = [];
    }
    function finish() {
        console.log("PENTAD_TEST " + JSON.stringify({
            status: checks.every(function(item) { return item.passed; }) ? "pass" : "fail",
            checks: checks
        }));
        Qt.quit();
    }
}
