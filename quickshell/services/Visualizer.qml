import QtQml
import Quickshell.Io
import "../logic/visualizer.mjs" as VisualizerLogic
import "../theme"

QtObject {
    id: root
    property bool preview: false
    property bool safeMode: false
    property bool reducedMotion: Theme.tokens.reducedMotion
    property var consumers: []
    property var frame: ({ values: [], left: [], right: [], available: false, reason: "inactive" })
    property bool processStarted: false
    property string processError: ""
    property bool exitHandled: false
    property bool stopping: false
    property bool restartAfterStop: false
    readonly property bool enabled: !preview && !safeMode && !reducedMotion && consumers.length > 0
    readonly property var state: frame.available
        ? ({ kind: "ready", value: frame })
        : ({ kind: "unavailable", reason: frame.reason })

    function publishUnavailable(reason) {
        frame = { values: [], left: [], right: [], available: false, reason: reason || "unavailable" };
    }

    function acquire(consumerId) {
        if (!consumerId || consumers.indexOf(String(consumerId)) >= 0) return;
        consumers = consumers.concat([String(consumerId)]);
        updateProcess();
    }

    function release(consumerId) {
        consumers = consumers.filter(function(id) { return id !== String(consumerId); });
        updateProcess();
    }

    function updateProcess() {
        if (enabled && !analyzer.running) {
            publishUnavailable("starting");
            processStarted = false;
            processError = "";
            exitHandled = false;
            stopping = false;
            restartAfterStop = false;
            startTimeout.restart();
            analyzer.stdinEnabled = true;
            analyzer.running = true;
        } else if (enabled && stopping) {
            restartAfterStop = true;
        } else if (!enabled && analyzer.running) {
            stopping = true;
            restartAfterStop = false;
            analyzer.running = false;
            startTimeout.stop();
            processStarted = false;
            publishUnavailable(preview ? "preview" : safeMode ? "safe-mode" : reducedMotion ? "reduced-motion" : "inactive");
        } else if (!enabled) {
            restartAfterStop = false;
            publishUnavailable(preview ? "preview" : safeMode ? "safe-mode" : reducedMotion ? "reduced-motion" : "inactive");
        }
    }

    onEnabledChanged: updateProcess()
    Component.onCompleted: updateProcess()
    Component.onDestruction: analyzer.running = false

    property Timer startTimeout: Timer {
        interval: 3000
        repeat: false
        onTriggered: {
            if (root.enabled && !root.processStarted) {
                root.publishUnavailable("start-timeout");
                root.analyzer.running = false;
            }
        }
    }

    property Process analyzer: Process {
        command: ["cava", "-p", "/dev/stdin"]
        stdinEnabled: true
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: function(data) {
                var values = VisualizerLogic.parseCavaFrame(String(data));
                if (values) {
                    var midpoint = Math.floor(values.length / 2);
                    root.frame = {
                        values: values,
                        left: values.slice(0, midpoint).reverse(),
                        right: values.slice(midpoint),
                        available: true,
                        reason: ""
                    };
                }
            }
        }
        stderr: SplitParser {
            splitMarker: "\n"
            onRead: function(data) {
                var message = String(data).trim();
                if (message) root.processError = message;
            }
        }
        onStarted: {
            root.processStarted = true;
            root.startTimeout.stop();
            write("[general]\nmode = waves\nframerate = 60\nautosens = 1\nbars = 50\n[input]\nmethod = pulse\nsource = auto\n[output]\nmethod = raw\nraw_target = /dev/stdout\ndata_format = ascii\nascii_max_range = 1000\nbar_delimiter = 59\nframe_delimiter = 10\nchannels = stereo\n[smoothing]\nnoise_reduction = 20\n");
            stdinEnabled = false;
        }
        onExited: function(exitCode, exitStatus) {
            root.startTimeout.stop();
            root.processStarted = false;
            root.exitHandled = true;
            if (root.enabled && !root.restartAfterStop) {
                var reason = root.processError || ("process exited with code " + exitCode + " (status " + exitStatus + ")");
                root.publishUnavailable(reason);
            }
        }
        onRunningChanged: {
            if (!running && root.enabled && root.restartAfterStop) {
                root.restartAfterStop = false;
                root.stopping = false;
                root.updateProcess();
            } else if (!running && root.enabled && !root.processStarted && !root.exitHandled) {
                root.startTimeout.stop();
                root.publishUnavailable("process-unavailable");
            } else if (!running) {
                root.stopping = false;
            }
        }
    }
}
