import QtQuick
import QtQml
import Quickshell.Io
import Quickshell.Bluetooth
import "../logic/quick-settings.mjs" as Rules

QtObject {
    id: root
    property bool preview: false
    property bool safeMode: false
    property bool initialized: false
    property bool vpnAvailable: false
    property bool airplaneKnown: false
    property bool profileAvailable: false
    property var vpnProfiles: []
    property var radioState: null
    property var restoreRadios: null
    property bool airplane: false
    property bool night: false
    property bool nightAvailable: false
    property string profile: ""
    property string error: ""
    property string errorSetting: ""
    property var operation: null
    property var bluetoothDeviceTarget: null
    property var process: null
    property int serial: 0
    property int generation: 0
    property var jobs: []
    readonly property var adapter: preview || safeMode ? null : Bluetooth.defaultAdapter
    readonly property var state: ({
        kind: preview || safeMode ? "unavailable" : adapter || initialized ? "ready" : "starting",
        reason: preview ? "preview" : safeMode ? "safe-mode" : "",
        value: {
            bluetooth: Rules.bluetoothState(adapter).enabled,
            bluetoothAvailable: Rules.bluetoothState(adapter).available,
            bluetoothDevices: Rules.bluetoothState(adapter).devices,
            bluetoothDiscovering: !!adapter && adapter.discovering === true,
            bluetoothNearby: Rules.bluetoothNearby(adapter),
            vpns: vpnProfiles,
            vpnAvailable: vpnAvailable,
            airplane: airplaneKnown ? airplane : null,
            airplaneAvailable: airplaneKnown,
            night: night,
            nightAvailable: nightAvailable,
            profile: profile,
            profileAvailable: profileAvailable,
            busy: !!operation,
            error: error,
            errorSetting: errorSetting,
        },
    })
    signal commandFinished(string requestId, var result)
    signal tailscaleFallbackRequested()

    property Component commandWorker: Component {
        Process {
            id: worker
            required property string requestId
            required property var argv
            property bool startedOnce: false
            property bool overflow: false
            property string outputText: ""
            command: argv
            stdout: SplitParser { splitMarker: ""; onRead: function(chunk) { worker.capture(chunk); } }
            stderr: SplitParser { splitMarker: "" }
            property Timer deadline: Timer {
                interval: 12000
                running: false
                onTriggered: { if (worker.running) worker.signal(9); root.finishCommand(worker, false, "timeout"); }
            }
            onStarted: { startedOnce = true; outputText = ""; overflow = false; deadline.restart(); }
            onRunningChanged: if (!running && !startedOnce) root.finishCommand(worker, false, "unavailable");
            onExited: function(code, exitStatus) {
                deadline.stop();
                root.finishCommand(worker, code === 0 && exitStatus === 0 && !overflow,
                    overflow ? "invalid-response" : code === 0 ? "failed" : "unavailable");
            }
            function capture(chunk) {
                if (outputText.length + String(chunk).length > 8192) {
                    overflow = true; if (running) signal(9); return;
                }
                outputText += String(chunk);
            }
        }
    }
    property Timer poller: Timer {
        interval: 5000; repeat: true; running: !root.preview && !root.safeMode
        onTriggered: root.refresh()
    }
    property Timer bluetoothDeadline: Timer {
        interval: 5000; repeat: false
        onTriggered: if (root.operation && (root.operation.kind === "bluetooth" || root.operation.kind === "bluetooth-device")) root.finishOperation(false, "timeout")
    }
    property Connections adapterConnections: Connections {
        target: root.adapter
        function onEnabledChanged() {
            if (root.operation && root.operation.kind === "bluetooth"
                && root.adapter.enabled === root.operation.target) root.finishOperation(true, "ok");
        }
    }
    // Pairing waits for the user to confirm on the other device, so it gets far longer than a toggle.
    property Timer pairDeadline: Timer {
        interval: 30000; repeat: false
        onTriggered: if (root.operation && root.operation.kind === "bluetooth-pair") {
            if (root.bluetoothDeviceTarget) root.bluetoothDeviceTarget.cancelPair();
            root.finishOperation(false, "timeout");
        }
    }
    property Connections bluetoothDeviceConnections: Connections {
        target: root.bluetoothDeviceTarget
        function onConnectedChanged() {
            if (root.operation && root.operation.kind === "bluetooth-device"
                && root.bluetoothDeviceTarget.connected === root.operation.target) root.finishOperation(true, "ok");
        }
        function onPairedChanged() {
            const device = root.bluetoothDeviceTarget;
            if (!root.operation || root.operation.kind !== "bluetooth-pair" || !device.paired) return;
            // Trusted devices reconnect on their own later, as GNOME does after pairing.
            device.trusted = true;
            device.connect();
            root.finishOperation(true, "ok");
        }
        function onPairingChanged() {
            const device = root.bluetoothDeviceTarget;
            if (root.operation && root.operation.kind === "bluetooth-pair" && !device.pairing && !device.paired)
                root.finishOperation(false, "pairing-failed");
        }
    }
    property Connections managerConnections: Connections {
        target: root.preview || root.safeMode ? null : Bluetooth
        function onDefaultAdapterChanged() { root.backendChanged(); }
    }
    Component.onCompleted: if (!preview && !safeMode) refresh()
    onPreviewChanged: if (preview) stopNative("preview"); else if (!safeMode) refresh()
    onSafeModeChanged: if (safeMode) stopNative("safe-mode"); else if (!preview) refresh()
    Component.onDestruction: stopNative("service-stopped")

    function stopNative(reason) {
        generation++;
        poller.stop();
        bluetoothDeadline.stop();
        pairDeadline.stop();
        bluetoothDeviceTarget = null;
        const current = process;
        process = null;
        if (current) {
            current.deadline.stop();
            if (current.running) current.signal(9);
            current.destroy();
        }
        jobs = [];
        if (operation) finishOperation(false, reason);
        initialized = false;
        vpnProfiles = [];
        vpnAvailable = false;
        radioState = null;
        airplaneKnown = false;
        nightAvailable = false;
        profileAvailable = false;
    }
    function backendChanged() {
        generation++;
        const current = process;
        process = null;
        if (current) {
            current.deadline.stop();
            if (current.running) current.signal(9);
            current.destroy();
        }
        jobs = [];
        if (operation) finishOperation(false, "device-removed");
        if (!preview && !safeMode) refresh();
    }

    function nextId() { return "quick-settings-" + (++serial); }
    function finishOperation(ok, reason) {
        if (!operation) return;
        const id = operation.id;
        const kind = operation.kind;
        const target = operation.target;
        bluetoothDeadline.stop();
        pairDeadline.stop();
        bluetoothDeviceTarget = null;
        operation = null;
        error = ok ? "" : reason || "failed";
        errorSetting = ok ? "" : kind;
        commandFinished(id, { ok: ok, reason: reason || (ok ? "ok" : "failed") });
        if (!ok && kind === "vpn" && target === Rules.tailscaleUuid) tailscaleFallbackRequested();
        if (ok) refresh();
    }
    function begin(kind) {
        const id = nextId();
        if (preview || safeMode) {
            Qt.callLater(function() { commandFinished(id, { ok: false, reason: preview ? "preview" : "safe-mode" }); });
            return "";
        }
        if (operation) {
            Qt.callLater(function() { commandFinished(id, { ok: false, reason: "busy" }); });
            return "";
        }
        operation = { id: id, kind: kind };
        error = "";
        errorSetting = "";
        return id;
    }
    function refresh() {
        if (preview || safeMode || operation || process) return;
        const id = "refresh-" + (++serial);
        const commands = [
            ["nmcli", "-t", "-f", "UUID,TYPE,NAME", "connection", "show"],
            ["nmcli", "-t", "-f", "UUID", "connection", "show", "--active"],
            ["nmcli", "-t", "-f", "WIFI,WWAN", "radio"],
            ["powerprofilesctl", "get"],
            ["hyprctl", "hyprsunset", "temperature"],
            ["hyprctl", "hyprsunset", "identity", "get"],
            Array.from(Rules.tailscaleStatusCommand),
        ];
        runCommands(id, commands, function(outputs) {
            const tailscale = Rules.tailscaleProfile(Rules.parseTailscaleStatus(outputs[6]));
            vpnProfiles = Rules.mergeVpnProfiles(Rules.parseVpnProfiles(outputs[0], outputs[1]), tailscale);
            vpnAvailable = outputs[0] !== "" || !!tailscale;
            radioState = Rules.parseRadioState(outputs[2]);
            airplaneKnown = radioState !== null;
            profile = outputs[3].trim();
            profileAvailable = profile !== "";
            nightAvailable = outputs[4] !== "" && outputs[5] !== "";
            const temperature = Number(outputs[4]);
            if (Number.isFinite(temperature) && temperature > 0) night = outputs[5].trim() !== "true" && temperature < 6000;
            if (radioState) airplane = !radioState.wifi && !radioState.wwan && (!adapter || !adapter.enabled);
            initialized = true;
        }, function() {
            initialized = true;
            vpnAvailable = false;
            airplaneKnown = false;
            profileAvailable = false;
            nightAvailable = false;
        }, true);
    }
    function runCommands(requestId, commands, success, failure, isRead) {
        jobs = jobs.concat([{ requestId: requestId, generation: generation, commands: commands, index: 0, outputs: [], success: success, failure: failure, isRead: isRead }]);
        startNext();
    }
    function startNext() {
        if (process || !jobs.length) return;
        const job = jobs[0];
        if (job.index >= job.commands.length) {
            jobs = jobs.slice(1);
            if (job.success) job.success(job.outputs);
            startNext();
            return;
        }
        const worker = commandWorker.createObject(root, { requestId: job.requestId, argv: job.commands[job.index] });
        if (!worker) {
            jobs = jobs.slice(1);
            if (job.isRead) { if (job.failure) job.failure("unavailable"); }
            else if (operation && operation.id === job.requestId) finishOperation(false, "unavailable");
            startNext();
            return;
        }
        process = worker;
        worker.running = true;
    }
    function finishCommand(worker, ok, reason) {
        if (!worker || worker !== process) return;
        const output = worker.outputText;
        const requestId = worker.requestId;
        process = null;
        worker.deadline.stop(); worker.destroy();
        const job = jobs.length ? jobs[0] : null;
        if (!job || job.requestId !== requestId) { startNext(); return; }
        if (job.generation !== generation || (!job.isRead
            && !Rules.requestIsCurrent(operation, requestId, job.generation, generation))) {
            jobs = jobs.slice(1);
            if (!job.isRead && operation && operation.id === requestId) finishOperation(false, "stale-request");
            startNext(); return;
        }
        if (!ok) {
            if (job.isRead) {
                job.outputs.push("");
                job.index++;
                jobs = [job].concat(jobs.slice(1));
            } else {
                jobs = jobs.slice(1);
                if (operation && operation.id === requestId) finishOperation(false, reason);
            }
            startNext(); return;
        }
        job.outputs.push(output.trim());
        job.index++;
        jobs = [job].concat(jobs.slice(1));
        startNext();
    }
    function toggleBluetooth() {
        const id = begin("bluetooth"); if (!id) return id;
        if (!adapter) { finishOperation(false, "adapter-unavailable"); return id; }
        operation = Object.assign({}, operation, { target: !adapter.enabled });
        adapter.enabled = operation.target;
        bluetoothDeadline.restart();
        return id;
    }
    function toggleBluetoothDevice(deviceId) {
        const id = begin("bluetooth-device"); if (!id) return id;
        if (!adapter || !adapter.enabled) { finishOperation(false, "adapter-unavailable"); return id; }
        const device = adapter.devices.values.find(function(item) {
            return (item.address || item.dbusPath) === deviceId && (item.paired || item.connected);
        });
        if (!device) { finishOperation(false, "device-unavailable"); return id; }
        bluetoothDeviceTarget = device;
        operation = Object.assign({}, operation, { target: !device.connected });
        bluetoothDeadline.restart();
        device.connected = operation.target;
        return id;
    }
    function findBluetoothDevice(deviceId) {
        if (!adapter) return null;
        return adapter.devices.values.find(function(item) { return (item.address || item.dbusPath) === deviceId; }) || null;
    }
    // The settings page scans only while it is shown; it is not an operation, so it never blocks one.
    function setBluetoothDiscovering(on) {
        if (preview || safeMode || !adapter || !adapter.enabled) return false;
        if (adapter.discovering !== on) adapter.discovering = on;
        return true;
    }
    function pairBluetoothDevice(deviceId) {
        const id = begin("bluetooth-pair"); if (!id) return id;
        if (!adapter || !adapter.enabled) { finishOperation(false, "adapter-unavailable"); return id; }
        const device = findBluetoothDevice(deviceId);
        if (!device || device.paired) { finishOperation(false, "device-unavailable"); return id; }
        bluetoothDeviceTarget = device;
        pairDeadline.restart();
        device.pair();
        return id;
    }
    function forgetBluetoothDevice(deviceId) {
        const id = begin("bluetooth-forget"); if (!id) return id;
        const device = findBluetoothDevice(deviceId);
        if (!device) { finishOperation(false, "device-unavailable"); return id; }
        device.forget();
        Qt.callLater(function() { if (root.operation && root.operation.id === id) root.finishOperation(true, "ok"); });
        return id;
    }
    function toggleVpn(uuid) {
        const id = begin("vpn"); if (!id) return id;
        const profileItem = uuid ? vpnProfiles.find(function(item) { return item.uuid === uuid; })
            : vpnProfiles.find(function(item) { return item.active; }) || vpnProfiles[0];
        if (!profileItem) { finishOperation(false, "profile-required"); return id; }
        if (profileItem.kind === "tailscale") { switchTailscale(id, profileItem); return id; }
        runCommands(id, [["nmcli", "--wait", "10", "connection", profileItem.active ? "down" : "up", "uuid", profileItem.uuid]],
            function() { verifyVpn(id, profileItem.uuid, !profileItem.active); }, null, false);
        return id;
    }
    function switchTailscale(id, profileItem) {
        operation = Object.assign({}, operation, { target: Rules.tailscaleUuid });
        const command = Rules.tailscaleCommand(profileItem);
        if (!command || command.kind === "login") { finishOperation(false, "login-required"); return; }
        runCommands(id, [command.argv], function() { verifyTailscale(id, !profileItem.active); }, null, false);
    }
    function verifyTailscale(requestId, expectedActive) {
        const commands = expectedActive ? [["sleep", "1"], Array.from(Rules.tailscaleStatusCommand)]
            : [Array.from(Rules.tailscaleStatusCommand)];
        runCommands(requestId, commands, function(outputs) {
            const status = Rules.parseTailscaleStatus(outputs[outputs.length - 1]);
            const result = Rules.readbackResult("vpn", expectedActive, status ? status.active : null);
            if (status) {
                vpnProfiles = vpnProfiles.map(function(item) {
                    return item.kind === "tailscale" ? Object.assign({}, item, { active: status.active }) : item;
                });
            }
            finishOperation(result.ok, result.reason);
        }, null, true);
    }
    function verifyVpn(requestId, uuid, expectedActive) {
        runCommands(requestId, [["nmcli", "-t", "-f", "UUID", "connection", "show", "--active"]], function(outputs) {
            const activeIds = outputs[0].split(/\r?\n/).filter(Boolean);
            const result = Rules.readbackResult("vpn", expectedActive, activeIds.indexOf(uuid) >= 0);
            vpnProfiles = vpnProfiles.map(function(item) {
                return Object.assign({}, item, { active: activeIds.indexOf(item.uuid) >= 0 });
            });
            finishOperation(result.ok, result.reason);
        }, null, true);
    }
    function toggleAirplane() {
        const id = begin("airplane"); if (!id) return id;
        if (!airplane) {
            if (!radioState) { finishOperation(false, "radio-state-unavailable"); return id; }
            restoreRadios = Rules.airplaneSnapshot(radioState, adapter ? adapter.enabled : null);
            const commands = [["nmcli", "radio", "all", "off"]];
            if (adapter) commands.push(["bluetoothctl", "power", "off"]);
            runCommands(id, commands, function() { verifyAirplane(id, { wifi: false, wwan: false, bluetooth: adapter ? false : null }, true); }, null, false);
        } else {
            const commands = Rules.restoreAirplaneRadios(restoreRadios);
            if (!commands) { finishOperation(false, "restore-state-unavailable"); return id; }
            runCommands(id, commands, function() { verifyAirplane(id, restoreRadios, false); }, null, false);
        }
        return id;
    }
    function verifyAirplane(requestId, expected, active) {
        runCommands(requestId, [["nmcli", "-t", "-f", "WIFI,WWAN", "radio"]], function(outputs) {
            const actual = Rules.parseRadioState(outputs[0]);
            if (!actual) {
                finishOperation(false, "radio-state-unavailable");
                return;
            }
            const result = Rules.readbackResult("airplane", expected, {
                wifi: actual.wifi, wwan: actual.wwan,
                bluetooth: adapter ? adapter.enabled : null
            });
            radioState = actual;
            airplaneKnown = true;
            airplane = !actual.wifi && !actual.wwan && (!adapter || !adapter.enabled);
            if (result.ok) {
                restoreRadios = active ? restoreRadios : null;
            }
            finishOperation(result.ok, result.reason);
        }, null, true);
    }
    function toggleNight() {
        const id = begin("night"); if (!id) return id;
        if (!nightAvailable) { finishOperation(false, "backend-unavailable"); return id; }
        runCommands(id, [["hyprctl", "hyprsunset", night ? "identity" : "temperature"].concat(night ? [] : ["4000"])],
            function() { night = !night; finishOperation(true, "ok"); }, null, false);
        return id;
    }
}
