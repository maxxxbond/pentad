import QtQuick
import Quickshell.Io

// Every connection NetworkManager knows (wired, USB and Bluetooth tethering, mobile broadband,
// hotspot, VPN) for the Network settings page, through tools/pentad_network.py. Nothing runs
// until a page acquires it; while held, `nmcli monitor` pushes changes and a slow timer catches
// link speed and signal. Preview runs nothing and safe mode only reads.
QtObject {
    id: root
    required property var config
    property bool preview: false
    property bool safeMode: false
    // Tests answer requests here instead of the helper: function(payload, done).
    property var backendOverride: null
    property var status: null
    // Connection details by UUID, as the helper's `details` reply.
    property var details: ({})
    property int consumers: 0
    property int serial: 0
    readonly property bool live: consumers > 0 && !preview
    signal commandFinished(string requestId, var result)

    function acquire() { consumers += 1; refresh(); }
    function release() { consumers = Math.max(0, consumers - 1); }

    function request(payload, done) {
        if (backendOverride) { backendOverride(payload, done); return; }
        if (preview) { Qt.callLater(function() { done({ ok: false, reason: "preview" }); }); return; }
        const component = Qt.createComponent("SystemRequest.qml");
        if (component.status !== Component.Ready) { Qt.callLater(function() { done({ ok: false, reason: "unavailable" }); }); return; }
        const worker = component.createObject(root, {
            helperPath: root.config.helperPath.replace(/pentad-files\.py$/, "pentad_network.py"),
            payload: payload
        });
        if (!worker) { Qt.callLater(function() { done({ ok: false, reason: "unavailable" }); }); return; }
        worker.finished.connect(function(reply) {
            let result;
            try { result = JSON.parse(reply); } catch (error) { result = null; }
            done(result && typeof result === "object" ? result : { ok: false, reason: "io" });
        });
        worker.running = true;
    }

    // One status read at a time; a change that lands meanwhile asks for one more afterwards.
    property bool reading: false
    property bool readAgain: false
    function refresh() {
        if (reading) { readAgain = true; return; }
        reading = true;
        request({ operation: "status" }, function(result) {
            root.status = result;
            root.reading = false;
            if (root.readAgain) { root.readAgain = false; root.refresh(); }
        });
    }
    function loadDetails(uuid) {
        request({ operation: "details", uuid: uuid }, function(result) {
            const next = Object.assign({}, root.details);
            next[uuid] = result;
            root.details = next;
        });
    }

    // Writes report through commandFinished, then re-read what they changed.
    function write(payload) {
        const requestId = "network-" + (++serial);
        if (!backendOverride && (preview || safeMode)) {
            Qt.callLater(function() { root.commandFinished(requestId, { ok: false, reason: preview ? "preview" : "safe-mode" }); });
            return requestId;
        }
        request(payload, function(result) {
            root.commandFinished(requestId, result);
            root.refresh();
            if (payload.uuid && root.details[payload.uuid]) root.loadDetails(payload.uuid);
        });
        return requestId;
    }
    // The saved password is read only on an explicit request and never stored here.
    function revealSecret(uuid) {
        const requestId = "network-" + (++serial);
        if (!backendOverride && preview) {
            Qt.callLater(function() { root.commandFinished(requestId, { ok: false, reason: "preview" }); });
            return requestId;
        }
        request({ operation: "secret", uuid: uuid }, function(result) { root.commandFinished(requestId, result); });
        return requestId;
    }
    function activate(uuid) { return write({ operation: "activate", uuid: uuid }); }
    function deactivate(uuid) { return write({ operation: "deactivate", uuid: uuid }); }
    function forget(uuid) { return write({ operation: "forget", uuid: uuid }); }
    function connectDevice(device) { return write({ operation: "connect-device", device: device }); }
    function disconnectDevice(device) { return write({ operation: "disconnect-device", device: device }); }
    function setRadio(radio, enabled) { return write({ operation: "radio", radio: radio, enabled: enabled }); }
    function update(uuid, settings) { return write({ operation: "update", uuid: uuid, settings: settings }); }
    function joinHidden(ssid, security, password) {
        return write({ operation: "join-hidden", ssid: ssid, security: security, password: password });
    }
    function setHotspot(enabled, ssid, password) {
        const payload = { operation: "hotspot", enabled: enabled };
        if (ssid) payload.ssid = ssid;
        if (password) payload.password = password;
        return write(payload);
    }
    function setBluetoothTether(address, enabled) {
        return write({ operation: "bluetooth-tether", address: address, enabled: enabled });
    }
    function addMobile(apn, username, password) {
        const payload = { operation: "mobile-add", apn: apn };
        if (username) payload.username = username;
        if (password) payload.password = password;
        return write(payload);
    }
    function importVpn(path) { return write({ operation: "import-vpn", path: path, type: "auto" }); }

    // Live updates while a page holds the service: any monitor line schedules one re-read.
    property Timer settle: Timer {
        interval: 400
        onTriggered: root.refresh()
    }
    property Timer slowPoll: Timer {
        interval: 15000
        repeat: true
        running: root.live
        onTriggered: root.refresh()
    }
    property Process monitor: Process {
        command: ["nmcli", "monitor"]
        running: root.live && !root.backendOverride
        stdout: SplitParser {
            onRead: function(line) { root.settle.restart(); }
        }
    }
}
