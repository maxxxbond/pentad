import QtQuick
import QtQml
import Quickshell
import "../services"

// Drives the real Desktop service through the bar tool commands. The area picker is replaced by a stand-in
// that answers like Screenshot.pick (a file and the geometry, or a cancel); the harness puts stand-ins for the
// clipboard and notifications first in PATH. This file checks the command results.
ShellRoot {
    id: root
    property string scenario: Quickshell.env("PENTAD_BT_SCENARIO") || "text"
    property QtObject picker: QtObject {
        id: picker
        signal picked(string token, var result)
        signal pickCancelled(string token)
        property int count: 0
        property var calls: []
        function pick(token, options) {
            calls.push({ token: token, options: options });
            const hex = ("00000000000000000000000000000000" + (++count).toString(16)).slice(-32);
            const scale = options.scale || 1;
            Qt.callLater(function() {
                if (root.scenario === "cancel") { picker.pickCancelled(token); return; }
                picker.picked(token, { path: Quickshell.env("PENTAD_BT_PICKS") + "/pentad-pick-" + hex + ".png", width: 320 * scale, height: 200 * scale,
                    scale: scale, rect: { x: 10, y: 20, width: 320, height: 200 }, outputId: "DP-1",
                    logical: root.scenario === "nologic" ? null : { x: 100, y: 50, width: 320, height: 200 } });
            });
            return true;
        }
    }
    property var engines: ({ google: true, yandex: true, bing: true, tineye: true, baidu: true, sogou: true, saucenao: true, iqdb: true, ascii2d: true })
    property var config: ({
        show: {}, ocr: { languages: "eng" }, picker: { format: "rgb" }, magnifier: { zoom: 4 },
        translate: { target: "UK", provider: "deepl", keyFile: Quickshell.env("PENTAD_BT_KEY") },
        search: { mode: root.scenario === "direct" ? "direct" : "ask", engine: "bing", engines: root.engines }
    })
    property Desktop desktop: Desktop { telemetryEnabled: false; barTools: root.config; screenshotController: root.picker }
    property var pending: ({})
    property var checks: []
    property int step: 0
    property var steps: ({
        text: [
            ["ocr", function(r) { return r.ok && r.reason === "ok"; }],
            ["translate", function(r) { return r.ok && r.reason === "ok"; }],
            ["image-search", function(r) { return r.ok && r.reason === "choose"; }],
            ["image-open:yandex", function(r) { return r.ok && r.reason === "opened"; }],
            ["image-search:saucenao", function(r) { return r.ok && r.reason === "opened"; }],
            ["image-open:nope", function(r) { return !r.ok; }]
        ],
        direct: [["image-search", function(r) { return r.ok && r.reason === "opened"; }]],
        qr: [["qr-scan", function(r) { return r.ok && r.reason === "ok"; }]],
        cancel: [
            ["ocr", function(r) { return !r.ok && r.reason === "cancelled"; }],
            ["image-search", function(r) { return !r.ok && r.reason === "cancelled"; }]
        ],
        nokey: [["translate", function(r) { return !r.ok && r.reason === "missing-key"; }]],
        nologic: [["record", function(r) { return !r.ok && r.reason === "unavailable"; }]],
        record: [
            ["record", function(r) { return r.ok && r.reason === "ok" && r.message === "Recording started"; }],
            ["record", function(r) { return r.ok && r.message === "Recording stopped"; }]
        ],
        misc: [
            ["ruler", function(r) { return r.ok && r.reason === "ok"; }],
            ["magnifier", function(r) { return r.ok && r.reason === "ok" && r.message.endsWith(".png"); }],
            ["audio-output", function(r) { return r.ok; }],
            ["picker", function(r) { return r.ok; }],
            ["focus", function(r) { return r.ok; }],
            ["inhibit:900", function(r) { return r.ok; }],
            ["inhibit", function(r) { return r.ok; }]
        ]
    })

    function check(name, passed, detail) { checks.push({ name: name, passed: passed === true, detail: detail || "" }); }
    // Leave time for the cleanup commands that run after the last result before the report is written.
    function finish() { endTimer.start(); }
    Timer { id: endTimer; interval: 600; onTriggered: root.finishNow() }
    function finishNow() {
        const passed = checks.length > 0 && checks.every(function(item) { return item.passed; });
        console.log("PENTAD_TEST " + JSON.stringify({ status: passed ? "pass" : "fail", checks: checks }));
        Qt.quit();
    }
    function advance() {
        const list = root.steps[root.scenario] || [];
        if (root.step >= list.length) { Qt.callLater(root.afterSteps); return; }
        const entry = list[root.step];
        const id = root.desktop.command(entry[0]);
        root.pending[id] = entry;
        if (/^(ocr|translate|image-search|qr-scan|audio-output)/.test(entry[0]) && root.scenario !== "nokey")
            root.check(entry[0] + "-marks-tool-busy", root.desktop.state.value.toolBusy === true, JSON.stringify(root.desktop.state.value.toolBusy));
    }
    function afterSteps() {
        if (root.scenario === "text") {
            const first = root.desktop.command("qr-scan");
            const second = root.desktop.command("ocr");
            root.pending[first] = ["qr-scan-finishes", function(r) { return !r.ok && r.reason === "no-text"; }, true];
            root.pending[second] = ["second-tool-is-rejected-while-busy", function(r) { return !r.ok && r.reason === "busy"; }, true];
            root.extra = 2;
            return;
        }
        const labels = root.picker.calls.map(function(call) { return call.options.label; });
        if (root.scenario === "text")
            root.check("pick-labels-name-the-tool", labels[0] === "Recognize text" && labels[1] === "Translate text" && labels[2] === "Search by image", JSON.stringify(labels));
        if (root.scenario === "misc") {
            const zoomCall = root.picker.calls.find(function(call) { return call.options.label === "Magnifier"; });
            root.check("magnifier-asks-for-the-configured-zoom", !!zoomCall && zoomCall.options.scale === 4, JSON.stringify(zoomCall));
            root.check("magnifier-window-source-set", root.desktop.magnifierSource.indexOf("/pentad-pick-") > 0, root.desktop.magnifierSource);
            root.desktop.closeMagnifier();
            root.check("magnifier-source-cleared-on-close", root.desktop.magnifierSource === "");
        }
        if (root.scenario === "misc") {
            root.check("inhibit-timed-then-stopped", root.desktop.state.value.inhibited === false, JSON.stringify(root.desktop.state.value));
            root.check("focus-marker-created", root.desktop.focusActive === true, String(root.desktop.focusActive));
        }
        root.check("tool-busy-cleared", root.desktop.state.value.toolBusy === false);
        finish();
    }
    property int extra: 0

    Connections {
        target: root.desktop
        function onCommandFinished(requestId, result) {
            const entry = root.pending[requestId];
            if (!entry) return;
            delete root.pending[requestId];
            root.check(entry[0], entry[1](result), JSON.stringify(result));
            if (entry[2]) {
                root.extra--;
                if (root.extra === 0) { root.check("tool-busy-cleared", root.desktop.state.value.toolBusy === false); root.finish(); }
                return;
            }
            root.step++;
            if (root.scenario === "misc" && entry[0] === "inhibit:900") root.check("inhibit-timed-active", root.desktop.state.value.inhibited === true && root.desktop.state.value.inhibitSeconds === 900);
            // Let the stand-in inhibitor start before the next step stops it.
            if (entry[0] === "inhibit:900" || (entry[0] === "record" && root.step === 1)) settle.start(); else root.advance();
        }
    }
    Timer { id: settle; interval: 400; onTriggered: root.advance() }
    Timer { interval: 25000; running: true; onTriggered: { root.check("completed-in-time", false, "timeout at step " + root.step); root.finish(); } }
    Component.onCompleted: Qt.callLater(root.advance)
}
