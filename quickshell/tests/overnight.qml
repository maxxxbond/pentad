import QtQuick
import Quickshell
import Quickshell.Io
import "../services"

// The overnight service against fake power, audio, notifications and config. The runner puts
// recording stand-ins for systemd-inhibit, python3, openrgb, timeout, hyprctl and notify-send on
// a PATH that holds nothing else; their calls land in $XDG_STATE_HOME/overnight-calls.log.
ShellRoot {
    id: root
    readonly property string stateHome: Quickshell.env("XDG_STATE_HOME") || ""
    property var checks: []
    property bool finished: false
    property int step: 0
    property int waited: 0
    property int mark: 0
    property int requestMark: 0
    property var instance: null

    function check(name, passed, detail) {
        checks.push({ name: name, passed: passed === true, detail: detail || "" });
    }
    function finish() {
        if (finished) return;
        finished = true;
        if (instance) instance.destroy();
        console.log("PENTAD_TEST " + JSON.stringify({
            status: checks.length > 0 && checks.every(function(item) { return item.passed; }) ? "pass" : "fail",
            checks: checks
        }));
        Qt.quit();
    }

    QtObject {
        id: fakePower
        property string actual: "balanced"
        property bool busyOnce: false
        property int serial: 0
        property var requests: []
        readonly property var profileState: ({ kind: "ready", value: {
            profiles: ["power-saver", "balanced", "performance"], actual: actual, pending: false } })
        signal commandFinished(string requestId, var result)
        function setProfile(profile) {
            const id = "power-" + (++serial);
            const busy = busyOnce;
            busyOnce = false;
            requests = requests.concat([profile]);
            Qt.callLater(function() {
                if (!busy) fakePower.actual = profile;
                fakePower.commandFinished(id, busy ? { ok: false, reason: "busy" } : { ok: true, value: profile });
            });
            return id;
        }
    }
    QtObject {
        id: fakeAudio
        property bool muted: false
        property int serial: 0
        readonly property var state: ({ kind: "ready", value: { output: { id: "10", muted: muted } } })
        signal commandFinished(string requestId, var result)
        function setMuted(kind, value) {
            const id = "audio-" + (++serial);
            Qt.callLater(function() {
                fakeAudio.muted = value;
                fakeAudio.commandFinished(id, { ok: true, muted: value });
            });
            return id;
        }
    }
    QtObject {
        id: fakeNotifications
        property bool restoreComplete: true
        property var state: ({ status: "available", dnd: false })
        function setDnd(enabled) { state = Object.assign({}, state, { dnd: enabled }); }
    }
    QtObject {
        id: fakeConfig
        property var saved: []
        property var documents: ({ interface: { language: "en" }, layout: { barTools: { overnight: {
            end: "08:00", openrgb: { start: "Night", end: "Day" }, commands: { start: "fans quiet", end: "fans auto" } } } } })
        function save(name, value) {
            saved = saved.concat([{ name: name, value: value }]);
            const next = Object.assign({}, documents);
            next[name] = value;
            documents = next;
            return "config-" + saved.length;
        }
    }
    QtObject {
        id: fakeServices
        property var power: fakePower
        property var audio: fakeAudio
        property var notifications: fakeNotifications
        property var config: fakeConfig
        function text(uk, en) { return en; }
    }

    Component {
        id: overnightComponent
        Overnight {}
    }
    Component {
        id: writerComponent
        FileView {
            preload: false
            blockWrites: true
            printErrors: false
        }
    }
    FileView {
        id: reader
        blockAllReads: true
        printErrors: false
    }
    function read(path) {
        reader.path = path;
        reader.reload();
        return reader.text();
    }
    function write(path, text) {
        // Assigned after creation, so the FileView sees the path before the write.
        const writer = writerComponent.createObject(root);
        writer.path = path;
        writer.setText(text);
        writer.destroy();
    }
    function dir(name) { return stateHome + "/" + name; }
    function create(name, extra) {
        if (instance) instance.destroy();
        mark = calls().length;
        instance = overnightComponent.createObject(root, Object.assign({ services: fakeServices, stateRoot: dir(name) }, extra || {}));
        waited = 0;
    }
    // Calls of the fake programs, each a list of words; `since` skips the ones before a mark.
    function calls() {
        return read(stateHome + "/overnight-calls.log").split("\n").filter(Boolean).map(function(line) { return line.split("\t"); });
    }
    function callsSince() { return calls().slice(mark); }
    function find(list, program) { return list.filter(function(call) { return call[0] === program; }); }
    function state(name) {
        const text = read(dir(name) + "/overnight.json");
        try { return text ? JSON.parse(text) : null; } catch (error) { return "invalid"; }
    }
    function seed(name, endsAt, applied) {
        write(dir(name) + "/overnight.json", JSON.stringify({ version: 1, startedAt: Date.now() - 3600000, endsAt: endsAt,
            prior: { profile: "balanced", muted: false, dnd: false, razer: [] }, applied: applied }));
    }
    function settled() { return !!instance && instance.recovered && instance.phase === "idle" && !instance.pending; }

    // One step per tick; a step that waits returns early until its condition holds or it times out.
    function wait(condition, name) {
        if (condition) return true;
        if (++waited < 160) return false;
        check(name + "-timed-out", false, JSON.stringify({ phase: instance ? instance.phase : "", calls: callsSince() }));
        finish();
        return false;
    }
    function advance() {
        waited = 0;
        step++;
    }

    Timer {
        interval: 50
        repeat: true
        running: true
        onTriggered: root.tick()
    }

    function tick() {
        if (finished) return;
        if (step === 0) {
            write(stateHome + "/inhibit-mode", "ok");
            fakePower.busyOnce = true;
            create("night");
            advance();
        } else if (step === 1) {
            if (!wait(instance.recovered, "first-load")) return;
            check("idle-without-state-file", instance.phase === "idle" && !instance.active);
            check("start-accepted", instance.start("07:00") === true && instance.pending);
            advance();
        } else if (step === 2) {
            if (!wait(instance.phase === "active", "start")) return;
            const list = callsSince();
            const inhibit = find(list, "systemd-inhibit");
            check("inhibitor-blocks-sleep-until-the-end", inhibit.length === 1 && inhibit[0].indexOf("--what=sleep") > 0
                && inhibit[0].indexOf("--mode=block") > 0 && inhibit[0][inhibit[0].length - 2] === "sleep"
                && /^\d+$/.test(inhibit[0][inhibit[0].length - 1]) && instance.inhibitProcess.running, JSON.stringify(inhibit));
            check("busy-power-profile-is-retried-once", JSON.stringify(fakePower.requests) === '["power-saver","power-saver"]'
                && fakePower.actual === "power-saver", JSON.stringify(fakePower.requests));
            check("output-muted-and-dnd-on", fakeAudio.muted && fakeNotifications.state.dnd === true);
            const sets = find(list, "python3").filter(function(call) { return call[1] === "set"; });
            check("razer-brightness-to-zero", sets.length === 1 && JSON.stringify(JSON.parse(sets[0][2])) === '[{"serial":"PM1","brightness":0}]',
                JSON.stringify(sets));
            check("openrgb-night-profile", JSON.stringify(find(list, "openrgb")) === '[["openrgb","--profile","Night"]]');
            check("user-start-command-with-timeout", JSON.stringify(find(list, "timeout")) === '[["timeout","10","sh","-c","fans quiet"]]');
            const saved = state("night");
            check("state-file-records-prior-and-applied", !!saved && saved.version === 1 && saved.endsAt === instance.endsAt
                && JSON.stringify(saved.prior) === '{"profile":"balanced","muted":false,"dnd":false,"razer":[{"serial":"PM1","brightness":42}]}'
                && JSON.stringify(saved.applied) === '{"profile":"power-saver","muted":true,"dnd":true,"razer":true,"openrgb":true,"command":true}',
                JSON.stringify(saved));
            const remembered = fakeConfig.saved.length === 1 ? fakeConfig.saved[0].value.barTools.overnight : null;
            check("menu-choice-is-remembered", !!remembered && remembered.end === "07:00" && remembered.openrgb.start === "Night");
            check("ends-at-the-next-seven", instance.endsAt > Date.now() && instance.endsAt - Date.now() <= 86400000
                && new Date(instance.endsAt).getHours() === 7 && new Date(instance.endsAt).getMinutes() === 0);
            advance();
        } else if (step === 3) {
            const list = callsSince();
            if (!wait(find(list, "notify-send").length > 0, "summary")) return;
            const order = list.map(function(call) { return call[0]; });
            check("displays-off-last", order.indexOf("hyprctl") > order.lastIndexOf("timeout")
                && JSON.stringify(find(list, "hyprctl")) === '[["hyprctl","dispatch","hl.dsp.dpms({ action = \\"disable\\" })"]]',
                JSON.stringify(order));
            check("summary-names-the-end", JSON.stringify(find(list, "notify-send")) === '[["notify-send","-a","Pentad","Overnight mode on until 07:00"]]',
                JSON.stringify(find(list, "notify-send")));
            // The user's own change during the night wins over the restore.
            fakePower.actual = "performance";
            mark = calls().length;
            check("toggle-stops", instance.toggle() === true && instance.phase === "stopping");
            advance();
        } else if (step === 4) {
            if (!wait(instance.phase === "idle", "stop")) return;
            const list = callsSince();
            const order = list.map(function(call) { return call[0] + (call[0] === "python3" ? ":" + call[1] : ""); });
            check("restore-runs-in-reverse-order", JSON.stringify(order) === '["timeout","openrgb","python3:set"]', JSON.stringify(list));
            check("restore-runs-end-command-day-profile-and-razer-levels", JSON.stringify(list[0]) === '["timeout","10","sh","-c","fans auto"]'
                && JSON.stringify(list[1]) === '["openrgb","--profile","Day"]'
                && JSON.stringify(JSON.parse(list[2][2])) === '[{"serial":"PM1","brightness":42}]', JSON.stringify(list));
            check("user-changed-profile-is-kept", fakePower.actual === "performance" && fakePower.requests.length === 2,
                JSON.stringify(fakePower.requests));
            check("mute-and-dnd-restored", !fakeAudio.muted && fakeNotifications.state.dnd === false);
            check("inhibitor-released-and-state-cleared", !instance.inhibitProcess.running && state("night") === null
                && !instance.active && instance.endsAt === 0);
            advance();
        } else if (step === 5) {
            // A restart in the middle of the night holds the block for the time that is left.
            fakePower.actual = "power-saver";
            fakeAudio.muted = true;
            fakeNotifications.setDnd(true);
            seed("restart", Date.now() + 2500, { profile: "power-saver", muted: true, dnd: true, razer: false, openrgb: false, command: false });
            create("restart");
            advance();
        } else if (step === 6) {
            if (!wait(instance.phase === "active", "restart")) return;
            const inhibit = find(callsSince(), "systemd-inhibit");
            const seconds = inhibit.length === 1 ? Number(inhibit[0][inhibit[0].length - 1]) : 0;
            check("restart-reacquires-for-the-remaining-time", seconds >= 1 && seconds <= 3, JSON.stringify(inhibit));
            check("restart-changes-nothing", callsSince().length === 1 && fakePower.requests.length === 2);
            advance();
        } else if (step === 7) {
            if (!wait(instance.phase === "idle", "end-timer")) return;
            check("end-timer-restores", fakePower.actual === "balanced" && !fakeAudio.muted && fakeNotifications.state.dnd === false,
                JSON.stringify({ profile: fakePower.actual, muted: fakeAudio.muted, dnd: fakeNotifications.state.dnd }));
            check("end-timer-clears-state", state("restart") === null && !instance.inhibitProcess.running);
            check("end-without-failures-sends-nothing", find(callsSince(), "notify-send").length === 0, JSON.stringify(callsSince()));
            advance();
        } else if (step === 8) {
            // A state file whose end passed while the shell was down is undone at once.
            fakePower.actual = "power-saver";
            fakeAudio.muted = true;
            seed("expired", Date.now() - 60000, { profile: "power-saver", muted: true, dnd: null, razer: false, openrgb: false, command: false });
            create("expired");
            advance();
        } else if (step === 9) {
            if (!wait(settled() && fakePower.actual === "balanced", "expired")) return;
            check("expired-state-restores-without-blocking-sleep", find(callsSince(), "systemd-inhibit").length === 0
                && !fakeAudio.muted && fakeNotifications.state.dnd === false, JSON.stringify(callsSince()));
            check("expired-state-is-cleared", state("expired") === null);
            advance();
        } else if (step === 10) {
            // When sleep cannot be blocked the mode aborts before changing anything.
            write(stateHome + "/inhibit-mode", "fail");
            requestMark = fakePower.requests.length;
            create("refused");
            advance();
        } else if (step === 11) {
            if (!wait(instance.recovered, "refused-load")) return;
            check("refused-start-accepted", instance.start("08:00") === true);
            advance();
        } else if (step === 12) {
            if (!wait(settled() && find(callsSince(), "notify-send").length > 0, "refused")) return;
            const list = callsSince();
            const programs = list.map(function(call) { return call[0] + (call[0] === "python3" ? ":" + call[1] : ""); });
            check("refused-inhibitor-applies-nothing", JSON.stringify(programs) === '["python3:read","systemd-inhibit","notify-send"]'
                && fakePower.actual === "balanced" && fakePower.requests.length === requestMark && !fakeAudio.muted
                && fakeNotifications.state.dnd === false, JSON.stringify(list));
            check("refused-inhibitor-is-reported", find(list, "notify-send")[0][3] === "Overnight mode not turned on");
            check("refused-inhibitor-clears-state", state("refused") === null && !instance.active);
            write(stateHome + "/inhibit-mode", "ok");
            write(dir("broken") + "/overnight.json", "{broken");
            create("broken");
            advance();
        } else if (step === 13) {
            if (!wait(instance.recovered && read(dir("broken") + "/overnight.json.broken") !== "", "broken")) return;
            check("broken-state-is-kept-aside", read(dir("broken") + "/overnight.json.broken") === "{broken"
                && read(dir("broken") + "/overnight.json") === "" && instance.phase === "idle");
            check("broken-state-is-reported", find(callsSince(), "notify-send").length === 1
                && find(callsSince(), "systemd-inhibit").length === 0, JSON.stringify(callsSince()));
            create("preview", { preview: true });
            check("preview-is-unavailable", !instance.available && instance.start("08:00") === false
                && instance.toggle() === false && !instance.pending);
            advance();
        } else if (step === 14) {
            check("preview-writes-nothing", read(dir("preview") + "/overnight.json") === "" && callsSince().length === 0);
            finish();
        }
    }
}
