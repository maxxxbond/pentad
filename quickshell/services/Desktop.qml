import QtQuick
import QtQml
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import "../logic/telemetry.mjs" as Telemetry
import "../logic/bar-tools.mjs" as Tools
import "../logic/keyboard-layout.mjs" as KeyboardLayout

QtObject {
    id: root
    property bool preview: false
    property bool safeMode: false
    property var screenshotController: null
    property var barTools: null
    property int inhibitSeconds: 0
    property bool focusActive: false
    property string scriptRequest: ""
    // Path of the enlarged capture shown by the magnifier window; empty when it is closed.
    property string magnifierSource: ""
    readonly property string focusMarker: Tools.focusPath(Quickshell.env("HOME") || "")
    property bool telemetryEnabled: true
    property var cpuPrevious: null
    property var networkPrevious: null
    property double sampleTime: 0
    property int loadedFiles: 0
    property int gpuGeneration: 0
    property int gpuExpected: 0
    property int gpuSettled: 0
    property var gpuWorkers: []
    property var gpuRaw: ({})
    property var gpuSamples: []
    property var gpuPercent: null
    property bool samplingPending: true
    property bool telemetrySampleAvailable: false
    property bool recording: false
    property string recordingPath: ""
    property var keyboardLayoutValue: null
    property var keyboardLayoutNames: ({})
    property bool keyboardLayoutStale: false
    property int serial: 0
    readonly property var tailscaleEntry: DesktopEntries.applications.values.find(function(entry) {
        return entry.id === "dev.deedles.Trayscale";
    }) || null
    readonly property bool tailscaleAvailable: !preview && !safeMode && !!tailscaleEntry
    property string inhibitRequest: ""
    property bool inhibitStopping: false
    property bool inhibitStarted: false
    property bool recordStopping: false
    property bool recordStarting: false
    property string recordRequest: ""
    readonly property bool recordPending: recordRequest !== "" || recordStarting || recordStopping
        || (recorderProcess.running && !recording)
    readonly property bool inhibitPending: inhibitRequest !== "" || inhibitStopping
        || (inhibitProcess.running && !inhibitStarted)
    property var telemetryValue: ({ cpuPercent: null, memory: null, rxBytesPerSecond: null, txBytesPerSecond: null, gpuPercent: null, gpus: [] })
    readonly property bool telemetryActive: !preview && telemetryEnabled
    readonly property bool telemetryReady: telemetryActive && telemetrySampleAvailable
    readonly property var state: ({
        kind: preview ? "unavailable" : "ready",
        reason: preview ? "preview-disabled" : "",
        value: {
            telemetry: telemetryReady ? telemetryValue : null,
            telemetryStatus: {
                kind: !telemetryEnabled ? "disabled" : (telemetryReady ? "ready" : "unavailable"),
                reason: !telemetryEnabled ? "telemetry-disabled" : (telemetryReady ? "" : "procfs-unavailable")
            },
            recording: recording,
            recordPending: recordPending,
            keyboardLayout: keyboardLayoutValue ? keyboardLayoutValue.label : null,
            keyboardLayoutName: keyboardLayoutValue ? keyboardLayoutValue.name : "",
            keyboardLayoutIndex: keyboardLayoutValue ? keyboardLayoutValue.index : -1,
            keyboardLayoutCount: keyboardLayoutValue ? keyboardLayoutValue.count : 0,
            keyboardLayouts: keyboardLayoutValue ? keyboardLayoutValue.layouts.map(function(layout) {
                return { index: layout.index, label: layout.label, name: KeyboardLayout.keyboardLayoutName(layout, keyboardLayoutNames) };
            }) : [],
            inhibited: inhibitProcess.running,
            inhibitPending: inhibitPending,
            inhibitSeconds: inhibitSeconds,
            focus: focusActive,
            toolBusy: scriptRequest !== "",
            dndAvailable: false
        }
    })
    signal commandFinished(string requestId, var result)

    property FileView cpuFile: FileView {
        path: root.telemetryActive ? "/proc/stat" : ""; watchChanges: false; printErrors: false
        onLoaded: root.fileLoaded(1)
        onLoadFailed: root.fileLoadFailed(1)
    }
    property FileView memoryFile: FileView {
        path: root.telemetryActive ? "/proc/meminfo" : ""; watchChanges: false; printErrors: false
        onLoaded: root.fileLoaded(2)
        onLoadFailed: root.fileLoadFailed(2)
    }
    property FileView networkFile: FileView {
        path: root.telemetryActive ? "/proc/net/dev" : ""; watchChanges: false; printErrors: false
        onLoaded: root.fileLoaded(4)
        onLoadFailed: root.fileLoadFailed(4)
    }
    property Timer sampler: Timer {
        interval: 1000; repeat: true
        running: root.telemetryActive
        onTriggered: root.sample()
    }
    property Timer gpuDeadline: Timer {
        interval: 1800
        onTriggered: root.finishGpuSample(root.gpuGeneration, false)
    }
    property Component gpuWorkerComponent: Component {
        Process {
            id: worker
            required property int generation
            required property string purpose
            required property string gpuId
            required property string field
            property bool settled: false
            command: []
            stdout: StdioCollector { }
            property Timer startGuard: Timer {
                interval: 1000; running: true
                onTriggered: if (!worker.settled && !worker.running) root.settleGpuWorker(worker, -1)
            }
            onExited: function(code, status) { root.settleGpuWorker(worker, code); }
            onRunningChanged: {
                if (!running && !settled && startGuard.running)
                    root.settleGpuWorker(worker, -1);
            }
        }
    }

    // Hyprland announces layout changes per keyboard, so the main keyboard is re-read from the device list.
    property Process keyboardLayoutReader: Process {
        command: ["hyprctl", "-j", "devices"]
        stdout: StdioCollector { onStreamFinished: root.applyKeyboardLayout(text) }
        onRunningChanged: if (!running && root.keyboardLayoutStale) root.readKeyboardLayout()
    }
    property Connections keyboardLayoutEvents: Connections {
        target: root.preview || root.safeMode ? null : Hyprland
        function onRawEvent(event) {
            const name = event ? event.name : "";
            if (name === "activelayout" || name === "configreloaded") root.readKeyboardLayout();
        }
    }
    // Names for the layout list; without the registry the list falls back to the short codes.
    property FileView keyboardLayoutRegistry: FileView {
        path: root.preview || root.safeMode ? "" : "/usr/share/X11/xkb/rules/evdev.lst"
        watchChanges: false; printErrors: false
        onLoaded: root.keyboardLayoutNames = KeyboardLayout.keyboardLayoutNames(text())
    }
    Component.onCompleted: readKeyboardLayout()

    // The focus marker is the same file that puts the repository's agents in quiet mode.
    property FileView focusFile: FileView {
        path: root.preview || root.safeMode ? "" : root.focusMarker
        watchChanges: true; printErrors: false
        onLoaded: root.focusActive = true
        onLoadFailed: root.focusActive = false
        onFileChanged: reload()
    }
    property Timer focusPoll: Timer {
        interval: 3000; repeat: true; running: !root.preview && !root.safeMode
        onTriggered: root.focusFile.reload()
    }
    property Process inhibitProcess: Process {
        command: Tools.inhibitCommand(root.inhibitSeconds)
        onStarted: {
            root.inhibitStarted = true;
            if (root.inhibitRequest) {
                const requestId = root.inhibitRequest;
                root.inhibitRequest = "";
                root.commandFinished(requestId, { ok: true, reason: "ok", message: "" });
            } else inhibitProcess.signal(9);
        }
        onExited: function(code, status) {
            root.inhibitStarted = false;
            if (root.inhibitRequest) {
                const requestId = root.inhibitRequest;
                const wasStopping = root.inhibitStopping;
                root.inhibitRequest = "";
                root.inhibitStopping = false;
                root.commandFinished(requestId, wasStopping
                    ? { ok: true, reason: "ok", message: "Sleep inhibition stopped" }
                    : { ok: false, reason: "unavailable", message: "systemd-inhibit exited before becoming active" });
            }
        }
        onRunningChanged: {
            if (!running && root.inhibitRequest && !root.inhibitStopping && !root.inhibitStarted) {
                const requestId = root.inhibitRequest;
                root.inhibitRequest = "";
                root.commandFinished(requestId, { ok: false, reason: "unavailable", message: "systemd-inhibit could not start" });
            }
        }
    }
    property Process recorderProcess: Process {
        onStarted: {
            root.recordStarting = false;
            root.recording = true;
            if (root.recordRequest) {
                const requestId = root.recordRequest;
                root.recordRequest = "";
                root.commandFinished(requestId, { ok: true, reason: "ok", message: "Recording started", path: root.recordingPath });
            } else recorderProcess.signal(9);
        }
        onExited: function(code, status) {
            root.recording = false;
            root.recordStarting = false;
            if (root.recordRequest) {
                const requestId = root.recordRequest;
                const wasStopping = root.recordStopping;
                root.recordRequest = "";
                root.recordStopping = false;
                root.commandFinished(requestId, wasStopping
                    ? { ok: true, reason: "ok", message: "Recording stopped", path: root.recordingPath }
                    : { ok: false, reason: "unavailable", message: "wf-recorder exited before recording started" });
            }
        }
        onRunningChanged: {
            if (!running && root.recordStarting && root.recordRequest) {
                const requestId = root.recordRequest;
                root.recordStarting = false;
                root.recordRequest = "";
                root.commandFinished(requestId, { ok: false, reason: "unavailable", message: "wf-recorder could not start" });
            }
        }
    }
    property Timer inhibitStartDeadline: Timer {
        interval: 8000; running: root.inhibitRequest !== "" && !root.inhibitStarted && !root.inhibitStopping
        onTriggered: {
            if (!root.inhibitRequest) return;
            const requestId = root.inhibitRequest;
            root.inhibitRequest = ""; root.inhibitProcess.signal(9); root.inhibitStarted = false;
            root.commandFinished(requestId, { ok: false, reason: "timeout", message: "systemd-inhibit start timed out" });
        }
    }
    property Timer recordStartDeadline: Timer {
        interval: 8000; running: root.recordStarting
        onTriggered: {
            if (!root.recordRequest) return;
            const requestId = root.recordRequest;
            root.recordRequest = ""; root.recordStarting = false; root.recorderProcess.signal(9); root.recording = false;
            root.commandFinished(requestId, { ok: false, reason: "timeout", message: "wf-recorder start timed out" });
        }
    }
    property Timer recordStopDeadline: Timer {
        interval: 5000; running: root.recordStopping
        onTriggered: if (root.recorderProcess.running) root.recorderProcess.signal(9)
    }
    property Timer inhibitStopDeadline: Timer {
        interval: 5000; running: root.inhibitStopping
        onTriggered: if (root.inhibitProcess.running) root.inhibitProcess.signal(9)
    }

    property Component commandWorker: Component {
        Process {
            id: worker
            required property string requestId
            required property string purpose
            required property var argv
            property bool settled: false
            property int timeout: purpose.startsWith("script:") ? 110000 : 8000
            command: argv
            stdout: StdioCollector { }
            stderr: StdioCollector { }
            property Timer deadline: Timer {
                interval: worker.timeout; running: true
                onTriggered: {
                    if (worker.running) worker.signal(9);
                    root.processFailed(worker, "Desktop command timed out or did not start");
                }
            }
            onExited: function(code, status) {
                root.processFinished(worker, code, status);
            }
            onRunningChanged: {
                if (!running && !settled && deadline.running)
                    root.processFailed(worker, "Desktop command could not start");
            }
        }
    }

    function fileLoaded(bit) {
        if (!telemetryActive) return;
        loadedFiles |= bit;
        finishSampleIfReady();
    }

    function fileLoadFailed(bit) {
        if (!telemetryActive) return;
        loadedFiles |= bit;
        finishSampleIfReady();
    }

    function finishSampleIfReady() {
        if (loadedFiles !== 7 || gpuDeadline.running) return;
        samplingPending = false;
        if (telemetryActive && cpuFile.loaded && memoryFile.loaded && networkFile.loaded) readSnapshot();
        else telemetrySampleAvailable = false;
    }

    function sample() {
        if (!telemetryActive || samplingPending) return;
        samplingPending = true;
        loadedFiles = 0;
        startGpuSample();
        cpuFile.reload(); memoryFile.reload(); networkFile.reload();
    }

    function startGpuSample() {
        if (!telemetryActive) return;
        cancelGpuSample();
        const generation = gpuGeneration;
        gpuExpected = 1; gpuSettled = 0; gpuRaw = ({});
        gpuDeadline.start();
        launchGpuWorker(generation, "list", "", "", ["ls", "-1", "/sys/class/drm"]);
    }

    function launchGpuWorker(generation, purpose, gpuId, field, argv) {
        const worker = gpuWorkerComponent.createObject(root, {
            generation: generation, purpose: purpose, gpuId: gpuId, field: field
        });
        if (!worker) { gpuSettled++; return; }
        worker.command = argv;
        gpuWorkers = gpuWorkers.concat([worker]);
        worker.running = true;
    }

    function settleGpuWorker(worker, code) {
        if (worker.settled) return;
        worker.settled = true;
        worker.startGuard.stop();
        const generation = worker.generation;
        const output = worker.stdout.text.trim();
        const purpose = worker.purpose, gpuId = worker.gpuId, field = worker.field;
        gpuWorkers = gpuWorkers.filter(item => item !== worker);
        worker.destroy();
        if (!telemetryActive || generation !== gpuGeneration || !gpuDeadline.running) return;
        if (purpose === "list") {
            const cards = code === 0 ? output.split(/\r?\n/).filter(name => /^card\d+$/.test(name)).sort().slice(0, 16) : [];
            gpuExpected = cards.length * 3;
            gpuSettled = 0;
            if (!gpuExpected) { finishGpuSample(generation, true); return; }
            for (const card of cards) {
                const base = "/sys/class/drm/" + card + "/device/";
                launchGpuWorker(generation, "value", card, "load", ["cat", base + "gpu_busy_percent"]);
                launchGpuWorker(generation, "value", card, "used", ["cat", base + "mem_info_vram_used"]);
                launchGpuWorker(generation, "value", card, "total", ["cat", base + "mem_info_vram_total"]);
            }
            return;
        }
        gpuSettled++;
        if (code === 0) {
            const entry = gpuRaw[gpuId] || ({ load: "", used: "", total: "" });
            entry[field] = output;
            gpuRaw[gpuId] = entry;
        }
        if (gpuSettled >= gpuExpected) finishGpuSample(generation, true);
    }

    function finishGpuSample(generation, complete) {
        if (generation !== gpuGeneration || !gpuDeadline.running || !telemetryActive) return;
        gpuDeadline.stop();
        const workers = gpuWorkers.slice();
        gpuWorkers = [];
        for (const worker of workers) {
            worker.settled = true; worker.startGuard.stop();
            if (worker.running) worker.signal(9);
            worker.destroy();
        }
        gpuSamples = complete ? Object.keys(gpuRaw).sort().map(id => Telemetry.gpuSample(id,
            gpuRaw[id].load, gpuRaw[id].used, gpuRaw[id].total)) : [];
        gpuPercent = complete ? Telemetry.gpuPercent(gpuSamples) : null;
        finishSampleIfReady();
    }

    function cancelGpuSample() {
        gpuGeneration++;
        gpuDeadline.stop();
        const workers = gpuWorkers.slice();
        gpuWorkers = [];
        for (const worker of workers) {
            worker.settled = true; worker.startGuard.stop();
            if (worker.running) worker.signal(9);
            worker.destroy();
        }
        gpuExpected = 0; gpuSettled = 0; gpuRaw = ({});
    }

    function readSnapshot() {
        if (!telemetryActive || loadedFiles !== 7) return;
        const cpu = Telemetry.parseCpu(cpuFile.text());
        const memory = Telemetry.memoryUsage(memoryFile.text());
        const network = Telemetry.networkBytes(networkFile.text());
        const now = Date.now() / 1000;
        const traffic = Telemetry.rates(networkPrevious, network, now - sampleTime);
        telemetryValue = {
            cpuPercent: Telemetry.cpuUsage(cpuPrevious, cpu), memory: memory,
            rxBytesPerSecond: traffic ? traffic.rxBytesPerSecond : null,
            txBytesPerSecond: traffic ? traffic.txBytesPerSecond : null,
            gpuPercent: gpuPercent, gpus: gpuSamples
        };
        cpuPrevious = cpu; networkPrevious = network; sampleTime = now;
        telemetrySampleAvailable = true;
    }

    onTelemetryActiveChanged: {
        loadedFiles = 0;
        telemetrySampleAvailable = false;
        samplingPending = telemetryActive;
        if (telemetryActive) {
            samplingPending = true;
            cpuFile.reload(); memoryFile.reload(); networkFile.reload();
        } else {
            cancelGpuSample();
            gpuSamples = []; gpuPercent = null;
            cpuPrevious = null; networkPrevious = null; sampleTime = 0;
            telemetryValue = ({ cpuPercent: null, memory: null, rxBytesPerSecond: null, txBytesPerSecond: null, gpuPercent: null, gpus: [] });
        }
    }

    function run(argv, purpose, requestId) {
        const worker = commandWorker.createObject(root, { argv: argv, purpose: purpose, requestId: requestId });
        if (purpose.startsWith("script:")) console.log("[bar-tools] spawn " + purpose + (worker ? "" : " FAILED to create the worker"));
        if (!worker) {
            if (purpose.startsWith("record-dir:")) {
                recordStarting = false;
                recordRequest = "";
            }
            commandFinished(requestId, { ok: false, reason: "unavailable", message: "Could not start desktop command" });
            return;
        }
        worker.running = true;
    }

    function processFinished(worker, code, status) {
        if (worker.settled) return;
        worker.settled = true;
        const requestId = worker.requestId;
        const output = worker.stdout.text.trim();
        const error = worker.stderr.text.trim();
        const purpose = worker.purpose;
        worker.destroy();
        if (purpose === "notice") return;
        if (purpose.startsWith("pictures:")) {
            const capture = JSON.parse(purpose.slice("pictures:".length));
            const pictures = code === 0 && output.startsWith("/") && !output.includes("\n")
                ? output : (Quickshell.env("HOME") || "/tmp") + "/Pictures";
            const directory = pictures + "/Pentad";
            const filename = "pentad-" + new Date().toISOString().replace(/[:.]/g, "-") + (capture.record ? ".mp4" : ".png");
            const path = directory + "/" + filename;
            if (capture.record) recordingPath = path;
            run(["mkdir", "-p", directory], (capture.record ? "record-dir:" : "screenshot-dir:") + JSON.stringify({ geometry: capture.geometry, path: path }), requestId);
            return;
        }
        if (purpose.startsWith("script:")) {
            // script:<kind>[:<engine id>]; exit 1 is a cancelled region selection.
            const parts = purpose.split(":");
            console.log("[bar-tools] finished " + purpose + " exit=" + code + (error ? " stderr=" + error.slice(0, 300) : ""));
            discardPick(requestId);
            if (code !== 0) {
                root.scriptRequest = "";
                const reasons = { 1: "cancelled", 3: "missing-key", 4: "no-text", 5: "service-failed", 7: "missing-tool", 124: "timeout" };
                // The script reports the failures it knows by itself; anything else must not stay silent.
                if (!reasons[code]) run(["notify-send", "-a", "Pentad", "Pentad", error || "Tool failed (exit " + code + ")"], "notice", requestId);
                else if (code === 124) run(["notify-send", "-a", "Pentad", "Pentad", "The tool timed out"], "notice", requestId);
                commandFinished(requestId, { ok: false, reason: reasons[code] || "unavailable", message: error });
            } else if (parts[1] === "capture" && parts[2]) {
                const engine = Tools.searchEngine(parts[2]);
                if (!engine) { root.scriptRequest = ""; commandFinished(requestId, { ok: false, reason: "unavailable", message: "Unknown search engine" }); }
                else run(["xdg-open", engine.url], "opened", requestId);
            } else {
                root.scriptRequest = "";
                if (parts[1] === "magnifier") {
                    if (!output.startsWith("/") || output.includes("\n")) { commandFinished(requestId, { ok: false, reason: "service-failed", message: "No image was captured" }); return; }
                    root.closeMagnifier();
                    root.magnifierSource = output;
                }
                commandFinished(requestId, { ok: true, reason: parts[1] === "capture" ? "choose" : "ok", message: output });
            }
            return;
        }
        if (purpose === "opened" || purpose === "focus") {
            if (purpose === "focus") focusFile.reload();
            else root.scriptRequest = "";
            commandFinished(requestId, { ok: code === 0, reason: code === 0 ? purpose === "focus" ? "ok" : "opened" : "unavailable", message: error });
            return;
        }
        if (code !== 0) {
            if (purpose.startsWith("record-dir:")) {
                root.recordRequest = "";
                root.recordStarting = false;
            }
            commandFinished(requestId, { ok: false, reason: "unavailable", message: error || "Desktop utility failed or is unavailable" });
            return;
        }
        if (purpose === "keyboard-layout") {
            readKeyboardLayout();
            commandFinished(requestId, { ok: true, reason: "ok", message: "" });
        } else if (purpose === "picker") {
            commandFinished(requestId, { ok: true, reason: "ok", message: "" });
        } else if (purpose.startsWith("screenshot-dir:") || purpose.startsWith("record-dir:")) {
            const record = purpose.startsWith("record-dir:");
            const payload = JSON.parse(purpose.slice(record ? "record-dir:".length : "screenshot-dir:".length));
            if (record) {
                recordStarting = true;
                recorderProcess.command = ["wf-recorder", "-g", payload.geometry, "-f", payload.path]; recorderProcess.running = true;
            } else run(["grim", "-g", payload.geometry, payload.path], "screenshot:" + payload.path, requestId);
        } else if (purpose.startsWith("screenshot:")) {
            commandFinished(requestId, { ok: true, reason: "ok", message: "Screenshot saved", path: purpose.slice("screenshot:".length) });
        }
    }

    function processFailed(worker, error) {
        if (worker.settled) return;
        worker.settled = true;
        const purpose = worker.purpose;
        const requestId = worker.requestId;
        worker.destroy();
        if (purpose === "notice") return;
        if (purpose.startsWith("script:")) console.log("[bar-tools] failed " + purpose + ": " + error);
        if (purpose.startsWith("pictures:")) {
            const capture = JSON.parse(purpose.slice("pictures:".length));
            const directory = (Quickshell.env("HOME") || "/tmp") + "/Pictures/Pentad";
            const filename = "pentad-" + new Date().toISOString().replace(/[:.]/g, "-") + (capture.record ? ".mp4" : ".png");
            const path = directory + "/" + filename;
            if (capture.record) recordingPath = path;
            run(["mkdir", "-p", directory], (capture.record ? "record-dir:" : "screenshot-dir:") + JSON.stringify({ geometry: capture.geometry, path: path }), requestId);
            return;
        }
        if (purpose.startsWith("record-dir:") || purpose.startsWith("pictures:")) {
            recordRequest = "";
            recordStarting = false;
        }
        if (purpose.startsWith("script:") || purpose === "opened") { scriptRequest = ""; discardPick(requestId); }
        commandFinished(requestId, { ok: false, reason: "unavailable", message: "Desktop utility could not start" });
    }

    function openTailscale(requestId) {
        Qt.callLater(function() {
            if (!root.tailscaleAvailable) {
                root.commandFinished(requestId, { ok: false, reason: "unavailable", message: "Trayscale is unavailable" });
                return;
            }
            root.commandFinished(requestId, { ok: true, reason: "accepted", message: "" });
            root.tailscaleEntry.execute();
        });
    }

    // Drop the enlarged capture and remove its file.
    function closeMagnifier() {
        const old = magnifierSource;
        magnifierSource = "";
        if (old) run(["rm", "-f", old], "notice", "");
    }

    // Files made by the area picker that still belong to a running tool, by request id.
    property var pickFiles: ({})
    // Tools waiting for the user to choose an area, by request id.
    property var pendingPicks: ({})

    function discardPick(requestId) {
        const path = pickFiles[requestId];
        if (!path) return;
        const next = Object.assign({}, pickFiles);
        delete next[requestId];
        pickFiles = next;
        if (/^\/.*\/pentad-pick-[0-9a-f]{32}\.png$/.test(path)) run(["rm", "-f", path], "notice", "");
    }

    // Ask the Pentad overlay for an area; the tool continues in onPicked below.
    function startPick(kind, requestId, forcedEngine) {
        const config = barTools || {};
        const controller = screenshotController;
        const fail = function(reason, message) {
            if (kind === "record") recordRequest = "";
            else scriptRequest = "";
            Qt.callLater(function() { root.commandFinished(requestId, { ok: false, reason: reason, message: message }); });
        };
        if (!controller || typeof controller.pick !== "function") { fail("unavailable", "The area picker is unavailable"); return; }
        if (kind === "image-search" && !forcedEngine && Tools.searchPlan(config).kind === "none") {
            fail("no-engines", "Enable a search engine in settings");
            return;
        }
        pendingPicks[requestId] = { kind: kind, engine: forcedEngine || "" };
        const zoom = kind === "magnifier" && config.magnifier && Tools.magnifierZooms.indexOf(config.magnifier.zoom) >= 0 ? config.magnifier.zoom : 1;
        if (!controller.pick(requestId, { label: Tools.pickLabel(kind, function(uk, en) { return en; }), scale: zoom })) {
            delete pendingPicks[requestId];
            fail("busy", "The screenshot overlay is busy");
        }
    }

    function pickDone(requestId, result) {
        const entry = pendingPicks[requestId];
        if (!entry) return;
        delete pendingPicks[requestId];
        const kind = entry.kind;
        const config = barTools || {};
        console.log("[bar-tools] picked " + kind + " " + Math.round(result.rect.width) + "x" + Math.round(result.rect.height));
        const wrap = function(script, args) { return ["timeout", "100", "sh", "-c", script, "pentad"].concat(args); };
        const withFile = function(script, args, purpose) {
            pickFiles[requestId] = result.path;
            run(wrap(script, [result.path].concat(args)), purpose, requestId);
        };
        const languages = config.ocr && config.ocr.languages ? config.ocr.languages : "eng";
        if (kind === "magnifier") {
            scriptRequest = "";
            closeMagnifier();
            magnifierSource = result.path;
            commandFinished(requestId, { ok: true, reason: "ok", message: result.path });
        } else if (kind === "ruler") {
            pickFiles[requestId] = result.path;
            discardPick(requestId);
            run(wrap(Tools.rulerScript, [Math.round(result.rect.width) + "x" + Math.round(result.rect.height)]), "script:ruler", requestId);
        } else if (kind === "record") {
            pickFiles[requestId] = result.path;
            discardPick(requestId);
            if (!result.logical) {
                recordRequest = "";
                commandFinished(requestId, { ok: false, reason: "unavailable", message: "The monitor layout is unknown, so the area cannot be recorded" });
                return;
            }
            const area = result.logical.x + "," + result.logical.y + " " + result.logical.width + "x" + result.logical.height;
            run(["xdg-user-dir", "PICTURES"], "pictures:" + JSON.stringify({ geometry: area, record: true }), requestId);
        } else if (kind === "ocr") {
            withFile(Tools.ocrScript(languages), [], "script:ocr");
        } else if (kind === "qr-scan") {
            withFile(Tools.qrScript, [], "script:qr");
        } else if (kind === "translate") {
            const translate = config.translate || {};
            withFile(Tools.translateScript({ target: translate.target, provider: translate.provider, languages: languages }),
                [Tools.expandHome(translate.keyFile || "", Quickshell.env("HOME") || "")], "script:translate");
        } else if (kind === "image-search") {
            const forced = entry.engine ? Tools.searchEngine(entry.engine) : null;
            const plan = forced ? { kind: "direct", engine: forced } : Tools.searchPlan(config);
            withFile(Tools.imageCaptureScript, [], plan.kind === "direct" ? "script:capture:" + plan.engine.id : "script:capture");
        }
    }

    function pickCancelled(requestId) {
        const entry = pendingPicks[requestId];
        if (!entry) return;
        delete pendingPicks[requestId];
        if (entry.kind === "record") { recordRequest = ""; recordStarting = false; }
        else scriptRequest = "";
        commandFinished(requestId, { ok: false, reason: "cancelled", message: "" });
    }

    property Connections pickConnections: Connections {
        target: root.screenshotController
        ignoreUnknownSignals: true
        function onPicked(token, result) { root.pickDone(token, result); }
        function onPickCancelled(token) { root.pickCancelled(token); }
    }

    function startScript(kind, requestId, forcedEngine) {
        if (scriptRequest) {
            Qt.callLater(function() { root.commandFinished(requestId, { ok: false, reason: "busy", message: "Another tool is running" }); });
            return;
        }
        console.log("[bar-tools] start " + kind + " " + requestId);
        scriptRequest = requestId;
        if (kind === "audio-output") {
            run(["timeout", "100", "sh", "-c", Tools.audioOutputScript, "pentad"], "script:audio", requestId);
            return;
        }
        // Everything else works on an area the user chooses in the Pentad overlay.
        startPick(kind, requestId, forcedEngine);
    }

    function readKeyboardLayout() {
        if (preview || safeMode) return;
        keyboardLayoutStale = keyboardLayoutReader.running;
        if (!keyboardLayoutReader.running) keyboardLayoutReader.running = true;
    }

    function applyKeyboardLayout(text) {
        keyboardLayoutValue = KeyboardLayout.keyboardLayoutState(text);
    }

    // "keyboard-layout" moves to the next layout, "keyboard-layout:<index>" picks one from the list.
    function keyboardLayoutCommand(name) {
        if (name === "keyboard-layout") return ["hyprctl", "switchxkblayout", "current", "next"];
        const index = Number(name.slice("keyboard-layout:".length));
        const count = keyboardLayoutValue ? keyboardLayoutValue.count : 0;
        return Number.isInteger(index) && index >= 0 && index < count
            ? ["hyprctl", "switchxkblayout", "current", String(index)] : null;
    }

    function command(name) {
        const requestId = "desktop-" + (++serial);
        let inhibitFor = 0;
        if (name.startsWith("inhibit:")) { inhibitFor = parseInt(name.slice(8)); name = "inhibit"; }
        if (preview || safeMode) {
            Qt.callLater(function() { root.commandFinished(requestId, { ok: false, reason: "denied", message: "Desktop actions are disabled in preview or safe mode" }); });
            return requestId;
        }
        if ((name === "record" && recordPending) || (name === "inhibit" && inhibitPending)) {
            const action = name;
            Qt.callLater(function() {
                root.commandFinished(requestId, { ok: false, reason: "busy", message: action === "record"
                    ? "A recording operation is already in progress" : "A sleep inhibition operation is already in progress" });
            });
            return requestId;
        }
        if (name === "screenshot") {
            const accepted = screenshotController && screenshotController.open('edit', '');
            Qt.callLater(function() {
                root.commandFinished(requestId, { ok: !!accepted, reason: accepted ? 'accepted' : 'unavailable',
                    message: accepted ? '' : 'Screenshot editor is unavailable or busy' });
            });
        }
        else if (name === "record" && recording) {
            recordRequest = requestId; recordStopping = true; recorderProcess.signal(2);
        }
        else if (name === "record") {
            recordRequest = requestId;
            startPick("record", requestId, "");
        }
        else if (name === "keyboard-layout" || name.startsWith("keyboard-layout:")) {
            const argv = keyboardLayoutCommand(name);
            if (argv) run(argv, "keyboard-layout", requestId);
            else Qt.callLater(function() { root.commandFinished(requestId, { ok: false, reason: "unavailable", message: "Unknown keyboard layout" }); });
        }
        else if (name === "tailscale") openTailscale(requestId);
        else if (name === "color-picker" || name === "picker")
            run(Tools.pickerCommand(barTools && barTools.picker ? barTools.picker.format : "hex"), "picker", requestId);
        else if (Tools.scriptActions.indexOf(name) >= 0) startScript(name, requestId, "");
        else if (name.startsWith("image-search:")) startScript("image-search", requestId, name.slice("image-search:".length));
        else if (name.startsWith("image-open:")) {
            const engine = Tools.searchEngine(name.slice("image-open:".length));
            if (!engine || scriptRequest) Qt.callLater(function() {
                root.commandFinished(requestId, { ok: false, reason: engine ? "busy" : "unavailable", message: "" });
            });
            else { scriptRequest = requestId; run(["xdg-open", engine.url], "opened", requestId); }
        }
        else if (name === "focus")
            run(["sh", "-c", 'f="$1"; if [ -e "$f" ]; then rm -f "$f"; else mkdir -p "${f%/*}" && : > "$f"; fi', "pentad", focusMarker], "focus", requestId);
        else if (name === "inhibit" && inhibitProcess.running) {
            inhibitRequest = requestId; inhibitStopping = true; inhibitProcess.signal(2);
        } else if (name === "inhibit") {
            inhibitSeconds = Tools.inhibitDurations.indexOf(inhibitFor) >= 0 ? inhibitFor : 0;
            inhibitRequest = requestId; inhibitStarted = false; inhibitProcess.running = true;
        } else if (name === "dnd")
            Qt.callLater(function() { root.commandFinished(requestId, { ok: false, reason: "unavailable", message: "No notification service is available to control DND" }); });
        else Qt.callLater(function() { root.commandFinished(requestId, { ok: false, reason: "unavailable", message: "Unknown desktop action" }); });
        return requestId;
    }

}
