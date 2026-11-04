import QtQuick

// System facts and settings for the settings window, through tools/pentad_system.py. Nothing runs
// until a page asks; preview runs nothing and safe mode only reads.
QtObject {
    id: root
    required property var config
    property bool preview: false
    property bool safeMode: false
    property var about: null
    property var time: null
    property var timezones: []
    property var defaultApps: null
    property var idle: null
    property bool idleRestartRequired: false
    property string error: ""
    property int serial: 0
    signal commandFinished(string requestId, var result)

    function request(payload, done) {
        if (preview) { Qt.callLater(function() { done({ ok: false, reason: "preview" }); }); return; }
        const component = Qt.createComponent("SystemRequest.qml");
        if (component.status !== Component.Ready) { Qt.callLater(function() { done({ ok: false, reason: "unavailable" }); }); return; }
        const worker = component.createObject(root, {
            helperPath: root.config.helperPath.replace(/pentad-files\.py$/, "pentad_system.py"),
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
    // A page may be built twice in a row; a read that is already running is not started again.
    property var reading: ({})
    function read(operation, apply) {
        if (reading[operation]) return;
        reading = Object.assign({}, reading, { [operation]: true });
        request({ operation: operation }, function(result) {
            const next = Object.assign({}, root.reading);
            delete next[operation];
            root.reading = next;
            apply(result);
        });
    }
    function refreshAbout() { read("about", function(result) { root.about = result.ok ? result : null; }); }
    function refreshTime() { read("time", function(result) { root.time = result.ok ? result : null; }); }
    function loadTimezones() {
        if (timezones.length > 0) return;
        read("timezones", function(result) { root.timezones = result.ok ? result.timezones : []; });
    }
    function refreshDefaultApps() { read("default-apps", function(result) { root.defaultApps = result; }); }
    function refreshIdle() { read("idle", function(result) { root.idle = result; }); }
    // Writes report through commandFinished and refresh what they changed.
    function write(payload, after) {
        const requestId = "system-" + (++serial);
        if (preview || safeMode) {
            Qt.callLater(function() { root.commandFinished(requestId, { ok: false, reason: preview ? "preview" : "safe-mode" }); });
            return requestId;
        }
        request(payload, function(result) {
            root.error = result.ok ? "" : result.reason || "failed";
            if (payload.operation === "set-idle-timeout" && result.ok && result.restartRequired)
                root.idleRestartRequired = true;
            root.commandFinished(requestId, result);
            after();
        });
        return requestId;
    }
    function setTimezone(zone) { return write({ operation: "set-timezone", timezone: zone }, refreshTime); }
    function setNtp(enabled) { return write({ operation: "set-ntp", enabled: enabled }, refreshTime); }
    function setDefaultApp(category, desktopId) {
        return write({ operation: "set-default-app", category: category, desktopId: desktopId }, refreshDefaultApps);
    }
    function setIdleTimeout(action, seconds) {
        return write({ operation: "set-idle-timeout", action: action, seconds: seconds,
            revision: idle && idle.ok ? idle.revision : "" }, refreshIdle);
    }
}
