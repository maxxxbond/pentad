import QtQuick
import Quickshell.Io
import Quickshell.Networking
import "../logic/network.mjs" as NetworkLogic

QtObject {
    id: root
    property bool preview: false
    property bool safeMode: false
    property var backendOverride: null
    property bool healthProbeOverride: false
    property int healthProbeInterval: 2500
    property bool wifiReadbackOverride: false
    property int wifiReadbackInterval: 2500
    property int nextRequestId: 1
    property var operation: null
    property bool ownerKnown: false
    property bool ownerPresent: false
    property string ownerProbeReason: "health-probe-pending"
    property int ownerProbeGeneration: 0
    property var ownerProbeProcess: null
    property bool wifiReadbackKnown: false
    property bool wifiReadbackReady: false
    property bool confirmedWifiEnabled: false
    property string wifiReadbackReason: "read-only-pending"
    property int wifiReadbackGeneration: 0
    property var wifiReadbackProcess: null
    readonly property bool active: !preview
    readonly property var nativeBackend: backendOverride || (active ? Networking : null)
    readonly property bool nativeBackendAvailable: active && nativeBackend !== null
        && (nativeBackend.backend !== undefined && nativeBackend.backend !== NetworkBackendType.None)
        && (!backendOverride || typeof nativeBackend.ready !== "boolean" || nativeBackend.ready)
    readonly property bool ownerProbeEnabled: active && (backendOverride ? healthProbeOverride : nativeBackendAvailable)
    readonly property bool backendReady: nativeBackendAvailable
        && (!ownerProbeEnabled || (ownerKnown && ownerPresent))
    readonly property bool wifiReadbackRequired: !backendOverride || wifiReadbackOverride
    readonly property var actualWifiEnabled: wifiReadbackRequired
        ? (wifiReadbackReady && wifiReadbackKnown ? confirmedWifiEnabled : null)
        : (backendReady ? nativeBackend.wifiEnabled : null)
    readonly property var state: {
        if (!backendReady) {
            let reason = preview ? "preview" : "service-missing";
            if (nativeBackendAvailable && ownerProbeEnabled) reason = ownerProbeReason;
            return ({ kind: "unavailable", reason: reason });
        }
        const devices = nativeBackend.devices.values;
        let connectedDevice = null;
        let connectedCount = 0;
        const accessPoints = [];
        for (let i = 0; i < devices.length; ++i) {
            const device = devices[i];
            if (device.connected) { connectedDevice = device; ++connectedCount; }
            if (device.type !== DeviceType.Wifi) continue;
            const networks = device.networks.values;
            for (let j = 0; j < networks.length; ++j) {
                const network = networks[j];
                accessPoints.push({
                    name: network.name,
                    connected: network.connected,
                    known: network.known,
                    state: NetworkLogic.connectionState(network.state),
                    security: NetworkLogic.securityName(network.security),
                    canUsePsk: NetworkLogic.supportsPsk(network.security),
                    signal: Math.round(Math.max(0, Math.min(1, network.signalStrength)) * 100),
                    bars: NetworkLogic.signalBars(Math.round(Math.max(0, Math.min(1, network.signalStrength)) * 100)),
                    device: device.name,
                    network: network
                });
            }
        }
        let primary = "none", label = null;
        if (connectedDevice) {
            primary = connectedCount > 1 ? "unknown"
                : connectedDevice.type === DeviceType.Wifi ? "wifi" : "wired";
            label = connectedDevice.name;
            const current = connectedDevice.networks.values.find(function(item) { return item.connected; });
            if (current) label = current.name;
        }
        return ({ kind: "ready", value: {
            primary: primary, connected: connectedCount > 0, label: label,
            connectivity: NetworkLogic.connectivityName(nativeBackend.connectivity),
            wifiEnabled: actualWifiEnabled,
            wifiReadbackReason: wifiReadbackReason,
            wifiHardwareEnabled: nativeBackend.wifiHardwareEnabled,
            wifiScanEnabled: devices.some(function(device) {
                return device.type === DeviceType.Wifi && device.scannerEnabled;
            }),
            devices: devices.map(function(device) {
                return { name: device.name, type: device.type === DeviceType.Wifi ? "wifi" : "wired",
                    connected: device.connected,
                    scannerEnabled: device.type === DeviceType.Wifi && device.scannerEnabled };
            }),
            accessPoints: NetworkLogic.sortAccessPoints(accessPoints)
        } });
    }
    signal commandFinished(string requestId, var result)

    property Component ownerProbeWorker: Component {
        Process {
            id: process
            required property int generation
            property bool startedOnce: false
            property bool outputOverflow: false
            property string output: ""
            command: ["busctl", "--system", "call", "org.freedesktop.DBus", "/org/freedesktop/DBus",
                "org.freedesktop.DBus", "NameHasOwner", "s", "org.freedesktop.NetworkManager"]
            stdout: SplitParser {
                splitMarker: ""
                onRead: function(chunk) { process.captureChunk(chunk); }
            }
            stderr: SplitParser { splitMarker: "" }
            property Timer deadline: Timer {
                interval: 1000
                running: false
                onTriggered: {
                    if (process.running) process.signal(9);
                    root.finishOwnerProbe(process, null, "read-only-unavailable");
                }
            }
            onStarted: { startedOnce = true; output = ""; outputOverflow = false; deadline.restart(); }
            onRunningChanged: if (!running && !startedOnce)
                root.finishOwnerProbe(process, null, "read-only-unavailable");
            onExited: function(code, exitStatus) {
                deadline.stop();
                if (code !== 0 || exitStatus !== 0 || outputOverflow) {
                    root.finishOwnerProbe(process, null, "read-only-unavailable"); return;
                }
                const match = /^\s*b\s+(true|false)\s*$/.exec(output);
                if (!match) { root.finishOwnerProbe(process, null, "read-only-unavailable"); return; }
                root.finishOwnerProbe(process, match[1] === "true", match[1] === "true" ? "" : "service-missing");
            }
            function captureChunk(chunk) {
                const text = String(chunk);
                if (output.length + text.length > 512) {
                    outputOverflow = true;
                    if (running) signal(9);
                    return;
                }
                output += text;
            }
        }
    }
    property Component wifiReadbackWorker: Component {
        Process {
            id: process
            required property int generation
            property bool startedOnce: false
            property bool outputOverflow: false
            property string output: ""
            command: ["busctl", "--system", "get-property", "org.freedesktop.NetworkManager",
                "/org/freedesktop/NetworkManager", "org.freedesktop.NetworkManager", "WirelessEnabled"]
            stdout: SplitParser {
                splitMarker: ""
                onRead: function(chunk) { process.captureChunk(chunk); }
            }
            stderr: SplitParser { splitMarker: "" }
            property Timer deadline: Timer {
                interval: 1000
                running: false
                onTriggered: {
                    if (process.running) process.signal(9);
                    root.finishWifiReadback(process, null, "timeout");
                }
            }
            onStarted: { startedOnce = true; output = ""; outputOverflow = false; deadline.restart(); }
            onRunningChanged: if (!running && !startedOnce)
                root.finishWifiReadback(process, null, "read-only-unavailable");
            onExited: function(code, exitStatus) {
                deadline.stop();
                if (code !== 0 || exitStatus !== 0 || outputOverflow) {
                    root.finishWifiReadback(process, null, "read-only-unavailable"); return;
                }
                const match = /^\s*b\s+(true|false)\s*$/.exec(output);
                if (!match) { root.finishWifiReadback(process, null, "read-only-unavailable"); return; }
                root.finishWifiReadback(process, match[1] === "true", "");
            }
            function captureChunk(chunk) {
                const text = String(chunk);
                if (output.length + text.length > 512) {
                    outputOverflow = true;
                    if (running) signal(9);
                    return;
                }
                output += text;
            }
        }
    }
    property Timer ownerProbeTimer: Timer {
        interval: Math.max(100, root.healthProbeInterval)
        repeat: true
        running: root.ownerProbeEnabled
        triggeredOnStart: true
        onTriggered: root.startOwnerProbe()
    }
    property Timer wifiReadbackTimer: Timer {
        interval: root.operation && root.operation.kind === "wifi" ? 250 : Math.max(100, root.wifiReadbackInterval)
        repeat: true
        running: root.backendReady && root.wifiReadbackRequired
        triggeredOnStart: true
        onTriggered: root.startWifiReadback()
    }

    function startOwnerProbe() {
        if (!ownerProbeEnabled || ownerProbeProcess) return;
        const generation = ++ownerProbeGeneration;
        const worker = ownerProbeWorker.createObject(root, { generation: generation });
        if (!worker) { applyOwnerProbeResult(generation, null, "read-only-unavailable"); return; }
        ownerProbeProcess = worker;
        worker.running = true;
    }
    function finishOwnerProbe(worker, present, reason) {
        if (!worker) return;
        const current = ownerProbeProcess === worker && worker.generation === ownerProbeGeneration;
        if (ownerProbeProcess === worker) ownerProbeProcess = null;
        worker.deadline.stop();
        if (current) applyOwnerProbeResult(worker.generation, present, reason);
        worker.destroy();
    }
    function applyOwnerProbeResult(generation, present, reason) {
        if (generation !== ownerProbeGeneration) return;
        ownerKnown = true;
        ownerPresent = present === true;
        ownerProbeReason = reason || (ownerPresent ? "" : "service-missing");
        if (!ownerPresent) invalidateWifiReadback("service-missing", true);
        else if (wifiReadbackRequired) startWifiReadback();
        checkOperation();
    }
    function invalidateWifiReadback(reason, resetActual) {
        ++wifiReadbackGeneration;
        const worker = wifiReadbackProcess;
        wifiReadbackProcess = null;
        if (worker) {
            worker.deadline.stop();
            if (worker.running) worker.signal(9);
            worker.destroy();
        }
        if (resetActual) {
            wifiReadbackReady = false;
            wifiReadbackReason = reason || "read-only-unavailable";
        }
    }
    function startWifiReadback() {
        if (!wifiReadbackRequired || !backendReady || wifiReadbackProcess) return;
        const generation = ++wifiReadbackGeneration;
        const worker = wifiReadbackWorker.createObject(root, { generation: generation });
        if (!worker) { applyWifiReadbackResult(generation, null, "read-only-unavailable"); return; }
        wifiReadbackProcess = worker;
        worker.running = true;
    }
    function finishWifiReadback(worker, actual, reason) {
        if (!worker) return;
        const current = wifiReadbackProcess === worker && worker.generation === wifiReadbackGeneration;
        if (wifiReadbackProcess === worker) wifiReadbackProcess = null;
        worker.deadline.stop();
        if (current) applyWifiReadbackResult(worker.generation, actual, reason);
        worker.destroy();
    }
    function applyWifiReadbackResult(generation, actual, reason) {
        if (generation !== wifiReadbackGeneration) return;
        if (actual === true || actual === false) {
            wifiReadbackKnown = true;
            wifiReadbackReady = true;
            confirmedWifiEnabled = actual;
            wifiReadbackReason = "";
            checkOperation();
            return;
        }
        wifiReadbackReady = false;
        wifiReadbackReason = reason || "read-only-unavailable";
        if (operation && operation.kind === "wifi") finishOperation(false, wifiReadbackReason);
    }

    property Timer deadline: Timer {
        interval: 20000
        repeat: false
        onTriggered: root.finishOperation(false, "timeout")
    }

    function findDevice(name) {
        if (!backendReady || !nativeBackend.devices) return null;
        return nativeBackend.devices.values.find(function(device) { return device.name === name; }) || null;
    }
    function findNetwork(name, deviceName) {
        const device = findDevice(deviceName);
        if (!device) return null;
        return device.networks.values.find(function(network) { return network.name === name; }) || null;
    }
    function begin(kind, target) {
        const requestId = `network-${nextRequestId++}`;
        if (operation) {
            Qt.callLater(function() { commandFinished(requestId, { ok: false, reason: "busy" }); });
            return requestId;
        }
        operation = { requestId: requestId, kind: kind, target: target,
            wifiDevices: kind === "wifi" && nativeBackend.devices
                ? nativeBackend.devices.values.filter(function(device) { return device.type === DeviceType.Wifi; })
                : [] };
        if (kind === "wifi") deadline.interval = 5000;
        deadline.restart();
        return requestId;
    }
    function finishOperation(ok, reason) {
        if (!operation) return;
        const current = operation;
        operation = null;
        deadline.stop();
        deadline.interval = 20000;
        commandFinished(current.requestId, ok ? { ok: true } : { ok: false, reason: reason });
    }
    function checkOperation() {
        if (!operation) return;
        if (!backendReady || !nativeBackend.devices) {
            if (operation.kind === "wifi" && wifiReadbackRequired)
                invalidateWifiReadback("service-missing", true);
            finishOperation(false, "service-missing"); return;
        }
        const current = operation;
        if (current.kind === "wifi") {
            if (current.wifiDevices.length > 0 && current.wifiDevices.some(function(device) {
                return !devicePresent(device);
            })) {
                if (wifiReadbackRequired) invalidateWifiReadback("device-removed", true);
                finishOperation(false, "device-removed"); return;
            }
            const actual = wifiReadbackRequired ? actualWifiEnabled : nativeBackend.wifiEnabled;
            if (actual === current.target) finishOperation(true, "");
        } else if (current.kind === "scan") {
            if (!current.target || !devicePresent(current.target)) finishOperation(false, "device-removed");
        } else {
            const network = current.target;
            if (!network || !networkPresent(network)) { finishOperation(false, "network-removed"); return; }
            if (current.kind === "connect" && network.connected) finishOperation(true, "");
            else if (current.kind === "disconnect" && !network.connected && !network.stateChanging)
                finishOperation(true, "");
        }
    }
    function isCurrentOperation(requestId) { return !!operation && operation.requestId === requestId; }
    function devicePresent(target) {
        return backendReady && nativeBackend.devices && nativeBackend.devices.values.indexOf(target) >= 0;
    }
    function networkPresent(target) {
        return devicePresent(target.device) && target.device.networks
            && target.device.networks.values.indexOf(target) >= 0;
    }
    function setWifiEnabled(enabled) {
        if (!backendReady || safeMode || !nativeBackend.wifiHardwareEnabled)
            return unavailable("wifi-control-unavailable");
        if (wifiReadbackRequired && (!wifiReadbackReady || !wifiReadbackKnown))
            return unavailable(wifiReadbackReason || "read-only-unavailable");
        const requestId = begin("wifi", !!enabled);
        if (isCurrentOperation(requestId)) {
            if (wifiReadbackRequired) invalidateWifiReadback("", false);
            nativeBackend.wifiEnabled = !!enabled;
            if (wifiReadbackRequired) startWifiReadback();
        }
        return requestId;
    }
    function scan(deviceName) {
        if (!backendReady || safeMode) return unavailable("scan-unavailable");
        const device = findDevice(deviceName);
        if (!device || device.type !== DeviceType.Wifi || actualWifiEnabled !== true)
            return unavailable("scan-unavailable");
        const requestId = begin("scan", device);
        if (isCurrentOperation(requestId)) {
            device.scannerEnabled = true;
            Qt.callLater(function() {
                if (NetworkLogic.requestIsCurrent(operation, requestId, devicePresent(device)))
                    finishOperation(true, "");
            });
        }
        return requestId;
    }
    function stopScan(deviceName) {
        if (!backendReady || safeMode) return unavailable("scan-unavailable");
        const device = findDevice(deviceName);
        if (!device || device.type !== DeviceType.Wifi) return unavailable("scan-unavailable");
        const requestId = `network-${nextRequestId++}`;
        if (device.scannerEnabled) device.scannerEnabled = false;
        Qt.callLater(function() {
            if (devicePresent(device) && !device.scannerEnabled)
                commandFinished(requestId, { ok: true });
            else commandFinished(requestId, { ok: false, reason: "device-removed" });
        });
        return requestId;
    }
    function connectNetwork(name, deviceName, password) {
        if (!backendReady || safeMode) return unavailable("network-unavailable");
        const network = findNetwork(name, deviceName);
        if (!network) return unavailable("network-unavailable");
        if (password !== undefined && password !== "") {
            if (network.device.type !== DeviceType.Wifi || !NetworkLogic.supportsPsk(network.security))
                return unavailable("credentials-unsupported");
            const requestId = begin("connect", network);
            if (isCurrentOperation(requestId)) network.connectWithPsk(password);
            return requestId;
        }
        const requestId = begin("connect", network);
        if (isCurrentOperation(requestId)) network.connect();
        return requestId;
    }
    function disconnectNetwork(name, deviceName) {
        if (!backendReady || safeMode) return unavailable("network-unavailable");
        const network = findNetwork(name, deviceName);
        if (!network || !network.connected) return unavailable("network-unavailable");
        const requestId = begin("disconnect", network);
        if (isCurrentOperation(requestId)) network.disconnect();
        return requestId;
    }
    function unavailable(reason) {
        const requestId = `network-${nextRequestId++}`;
        Qt.callLater(function() { commandFinished(requestId, { ok: false, reason: reason }); });
        return requestId;
    }
    function handleConnectionFailure(network, reason) {
        if (!operation || operation.kind !== "connect" || operation.target !== network) return;
        finishOperation(false, NetworkLogic.failureReason(reason));
    }

    property Connections networkChanges: Connections {
        target: root.operation && root.operation.target
            && root.operation.target.device !== undefined ? root.operation.target : null
        function onStateChanged() { root.checkOperation(); }
        function onStateChangingChanged() { root.checkOperation(); }
        function onConnectedChanged() { root.checkOperation(); }
        function onConnectionFailed(reason) { root.handleConnectionFailure(target, reason); }
    }
    property Connections deviceChanges: Connections {
        target: root.operation && root.operation.kind === "scan" ? root.operation.target : null
        function onScannerEnabledChanged() { root.checkOperation(); }
    }
    property Connections devicesChanges: Connections {
        target: root.backendReady ? root.nativeBackend.devices : null
        function onValuesChanged() { root.checkOperation(); }
    }
    property Connections networksChanges: Connections {
        target: root.backendReady && root.operation && root.operation.target && root.operation.target.device
            && root.operation.kind !== "wifi" && root.operation.kind !== "scan"
            ? root.operation.target.device.networks : null
        function onValuesChanged() { root.checkOperation(); }
    }
    property Connections nativeWifiChanges: Connections {
        target: root.active && !root.backendOverride ? root.nativeBackend : null
        function onWifiEnabledChanged() {
            if (root.wifiReadbackRequired) root.startWifiReadback();
            else root.checkOperation();
        }
    }
    property Connections overrideChanges: Connections {
        target: root.backendOverride
        function onWifiEnabledChanged() {
            if (root.wifiReadbackRequired) root.startWifiReadback();
            else root.checkOperation();
        }
        function onBackendChanged() { root.checkOperation(); }
        function onReadyChanged() { root.checkOperation(); }
        function onDevicesChanged() { root.checkOperation(); }
    }
    Component.onDestruction: {
        finishOperation(false, "service-stopped");
        ownerProbeGeneration++;
        const worker = ownerProbeProcess;
        ownerProbeProcess = null;
        if (worker) {
            worker.deadline.stop();
            if (worker.running) worker.signal(9);
            worker.destroy();
        }
        invalidateWifiReadback("service-stopped", false);
    }
}
