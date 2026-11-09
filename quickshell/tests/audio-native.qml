import QtQuick
import Quickshell
import "../services"
import "../features/system"

ShellRoot {
    id: root
    property string scenario: Quickshell.env("PENTAD_AUDIO_SCENARIO") || "success"
    property var checks: []
    property var results: []
    property string firstRequest: ""
    property string latestRequest: ""
    property string invalidRequest: ""
    property bool requested: false
    property bool finished: false
    property int ticks: 0
    property bool staleProbeScheduled: false
    property var delayedProbe: null

    QtObject {
        id: outputAudio
        property real volume: 0.4
        property bool muted: false
        signal volumesChanged()
        onVolumeChanged: volumesChanged()
    }
    QtObject {
        id: outputAudio2
        property real volume: 0.5
        property bool muted: false
        signal volumesChanged()
        onVolumeChanged: volumesChanged()
    }
    QtObject {
        id: inputAudio
        property real volume: 0.6
        property bool muted: false
        signal volumesChanged()
        onVolumeChanged: volumesChanged()
    }
    QtObject {
        id: streamAudio
        property real volume: 0.45
        property bool muted: false
        signal volumesChanged()
        onVolumeChanged: volumesChanged()
    }
    QtObject {
        id: streamAudio2
        property real volume: 0.55
        property bool muted: false
        signal volumesChanged()
        onVolumeChanged: volumesChanged()
    }
    QtObject {
        id: recordingAudio
        property real volume: 0.65
        property bool muted: false
        signal volumesChanged()
        onVolumeChanged: volumesChanged()
    }
    QtObject {
        id: outputNode
        property string id: "10"
        property string name: "test-output"
        property string description: "Test Output"
        property bool ready: true
        property bool isSink: true
        property bool isStream: false
        property var properties: ({ "media.class": "Audio/Sink" })
        property var audio: outputAudio
    }
    QtObject {
        id: outputNode2
        property string id: "11"
        property string name: "test-output-2"
        property string description: "Second Output"
        property bool ready: true
        property bool isSink: true
        property bool isStream: false
        property var audio: outputAudio2
    }
    QtObject {
        id: inputNode
        property string id: "20"
        property string name: "test-input"
        property string description: "Test Input"
        property bool ready: true
        property bool isSink: false
        property bool isStream: false
        property var properties: ({ "media.class": "Audio/Source" })
        property var audio: inputAudio
    }
    QtObject {
        id: streamNode
        property string id: "31"
        property string name: "stream-one"
        property string description: "Editor"
        property bool ready: true
        property bool isSink: false
        property bool isStream: true
        property var properties: ({ "application.name": "Editor", "media.name": "Preview" })
        property var audio: streamAudio
    }
    QtObject {
        id: streamNode2
        property string id: "32"
        property string name: "stream-two"
        property string description: "Browser"
        property bool ready: true
        property bool isSink: false
        property bool isStream: true
        property var properties: ({ "application.name": "Browser", "application.icon-name": "web-browser" })
        property var audio: streamAudio2
    }
    QtObject {
        id: recordingNode
        property string id: "33"
        property string name: "recording"
        property bool ready: true
        property bool isSink: true
        property bool isStream: true
        property var audio: recordingAudio
    }
    QtObject {
        id: replacementAudio
        property real volume: 0.2
        property bool muted: false
    }
    QtObject {
        id: replacementNode
        property string id: "31"
        property string name: "replacement"
        property string description: "Replacement"
        property bool ready: false
        property bool isSink: false
        property bool isStream: true
        property var properties: ({ "application.name": "Replacement" })
        property var audio: replacementAudio
    }
    // Capture streams carry no audio object: only the sources they read from report mute.
    QtObject {
        id: captureNode
        property string id: "40"
        property string name: "alsa_capture.handy"
        property bool ready: true
        property bool isSink: true
        property bool isStream: true
        property var properties: ({ "media.class": "Stream/Input/Audio", "application.name": "PipeWire ALSA [handy]" })
    }
    QtObject {
        id: monitorCaptureNode
        property string id: "41"
        property string name: "cava"
        property bool ready: true
        property bool isSink: true
        property bool isStream: true
        property var properties: ({ "media.class": "Stream/Input/Audio", "application.process.binary": "cava" })
    }
    QtObject {
        id: fakeNodes
        property var values: [outputNode, outputNode2, inputNode, streamNode, streamNode2, recordingNode, captureNode, monitorCaptureNode]
    }
    QtObject { id: fakeLinkGroups; property var values: [] }
    QtObject {
        id: fakeBackend
        property bool ready: true
        property var nodes: fakeNodes
        property var linkGroups: fakeLinkGroups
        property var defaultAudioSink: outputNode
        property var defaultAudioSource: inputNode
        function setDefault(kind, node) {
            if (root.scenario === "default-timeout") return;
            Qt.callLater(function() {
                Qt.callLater(function() {
                    if (kind === "output") fakeBackend.defaultAudioSink = node;
                    else fakeBackend.defaultAudioSource = node;
                });
            });
        }
    }
    Audio { id: adapter; backendOverride: fakeBackend }
    QtObject {
        id: fakeConfig
        signal commandFinished(string requestId, var result)
        property var documents: ({ layout: ({}) })
        function save(document, value) { return "fixture-config-request"; }
    }
    AudioControls {
        width: 360; visible: false
        services: ({ audio: adapter, config: fakeConfig,
            text: function(uk, en) { return en; }, popups: null })
    }
    Connections {
        target: adapter
        function onCommandFinished(requestId, result) {
            root.results = root.results.concat([{ id: requestId, result: result }]);
        }
    }
    function check(name, passed, detail) {
        checks.push({ name: name, passed: passed === true, detail: detail || "" });
    }
    function finish() {
        if (finished) return;
        finished = true;
        console.log("PENTAD_TEST " + JSON.stringify({
            status: checks.length > 0 && checks.every(function(item) { return item.passed; }) ? "pass" : "fail",
            checks: checks
        }));
        Qt.quit();
    }
    function resultFor(id) { return results.find(function(item) { return item.id === id; }) || null; }
    function start() {
        if (scenario === "success") {
            firstRequest = adapter.setVolume("output", 0.7);
            latestRequest = firstRequest;
            check("native-setter-is-not-treated-as-readback", adapter.state.value.output.volume === 0.4
                && outputAudio.volume === 0.7 && results.length === 0);
        } else if (scenario === "mute") {
            firstRequest = adapter.toggleMute("output"); latestRequest = firstRequest;
            check("optimistic-mute-is-not-published-as-confirmed", outputAudio.muted
                && adapter.state.value.output.muted === false && results.length === 0);
        } else if (scenario === "set-mute") {
            // The input is already unmuted, so that request succeeds without a readback.
            invalidRequest = adapter.setMuted("input", false);
            firstRequest = adapter.setMuted("output", true); latestRequest = firstRequest;
            check("set-mute-applies-the-requested-state", outputAudio.muted && !inputAudio.muted
                && adapter.state.value.output.muted === false && results.length === 0);
        } else if (scenario === "default") {
            firstRequest = adapter.setDefault("output", "11"); latestRequest = firstRequest;
            check("default-waits-for-current-route", adapter.state.value.output.id === "10" && results.length === 0);
        } else if (scenario === "default-timeout") {
            firstRequest = adapter.setDefault("output", "11"); latestRequest = firstRequest;
        } else if (scenario === "supersede") {
            firstRequest = adapter.setVolume("output", 0.7);
            latestRequest = adapter.setVolume("output", 0.8);
        } else if (scenario === "stale-probe") {
            const probe = { nodeKey: "10", node: outputNode, generation: 4, running: false,
                deadline: { stop: function() {} }, destroy: function() {} };
            adapter.probeGenerations = ({ "10": 4 });
            adapter.probes = ({ "10": probe });
            root.delayedProbe = probe;
            firstRequest = adapter.setVolume("output", 0.7); latestRequest = firstRequest;
        } else if (scenario === "timeout" || scenario === "missing-utility") {
            firstRequest = adapter.setVolume("output", 0.7); latestRequest = firstRequest;
        } else if (scenario === "device-removed") {
            firstRequest = adapter.setVolume("output", 0.7); latestRequest = firstRequest;
            Qt.callLater(function() {
                outputNode.ready = false;
                fakeNodes.values = [outputNode2, inputNode];
            });
        } else if (scenario === "service-loss") {
            firstRequest = adapter.setVolume("output", 0.7); latestRequest = firstRequest;
            Qt.callLater(function() { fakeBackend.ready = false; });
        } else if (scenario === "streams") {
            adapter.retainMixer("fixture");
            const streams = adapter.state.value.streams;
            check("only-playback-streams-are-published", streams.length === 2
                && streams.every(function(item) { return item.id !== item.nodeId; })
                && streams.find(function(item) { return item.appName === "Editor" && item.mediaName === "Preview"; })
                && adapter.state.value.outputs.length === 2 && adapter.state.value.inputs.length === 1);
            check("mixer-consumer-does-not-start-probes", Object.keys(adapter.probes).length === 0);
            adapter.releaseMixer("fixture");
            check("consumer-release-hides-streams", adapter.state.value.streams.length === 0);
            check("consumer-release-stops-stream-probes", Object.keys(adapter.probes).every(function(key) {
                return !adapter.probes[key].node.isStream;
            }));
            finish();
        } else if (scenario === "stream-controls") {
            adapter.retainMixer("fixture");
            const streams = adapter.state.value.streams;
            const editor = streams.find(function(item) { return item.appName === "Editor"; });
            const browser = streams.find(function(item) { return item.appName === "Browser"; });
            firstRequest = adapter.setStreamVolume(editor.id, 0.72);
            root.firstRequest = firstRequest;
            latestRequest = adapter.toggleStreamMute(browser.id);
            check("stream-pending-state-separates-request-and-confirmation",
                adapter.state.value.streams.find(function(item) { return item.id === editor.id; }).requestedVolume === 0.72
                && adapter.state.value.streams.find(function(item) { return item.id === editor.id; }).volume === 0.45
                && adapter.state.value.streams.find(function(item) { return item.id === browser.id; }).pendingMute);
        } else if (scenario === "stream-recycled") {
            adapter.retainMixer("fixture");
            const oldId = adapter.state.value.streams.find(function(item) { return item.appName === "Editor"; }).id;
            firstRequest = adapter.setStreamVolume(oldId, 0.9); latestRequest = firstRequest;
            Qt.callLater(function() {
                streamNode.ready = false;
                replacementNode.ready = true;
                fakeNodes.values = [outputNode, outputNode2, inputNode, streamNode2, recordingNode, replacementNode];
                root.delayedProbe = { id: oldId };
            });
        } else if (scenario === "stream-guards") {
            adapter.retainMixer("fixture");
            const editor = adapter.state.value.streams.find(function(item) { return item.appName === "Editor"; });
            adapter.safeMode = true;
            firstRequest = adapter.setStreamVolume(editor.id, 0.9);
            adapter.safeMode = false;
            invalidRequest = adapter.setStreamVolume(editor.id, 1.1);
            adapter.preview = true;
            latestRequest = adapter.toggleStreamMute(editor.id);
            check("safe-and-preview-stream-requests-do-not-touch-native-state",
                streamAudio.volume === 0.45 && !streamAudio.muted && adapter.state.kind === "unavailable");
        } else if (scenario === "native-signals") {
            adapter.retainMixer("fixture");
            const editor = adapter.state.value.streams.find(function(item) { return item.appName === "Editor"; });
            root.firstRequest = editor.id;
            adapter.confirmedAudio = Object.assign({}, adapter.confirmedAudio, {
                "10": { volume: 0.4, muted: false }, "11": { volume: 0.5, muted: false },
                [editor.id]: { volume: 0.45, muted: false }
            });
            outputAudio.volume = 0.35;
            outputAudio2.volume = 0.25;
            streamAudio.muted = true;
            check("default-device-follows-native-volume-signal", adapter.confirmedAudio["10"].volume === 0.35
                && adapter.state.value.output.volume === 0.35);
            check("non-default-device-follows-native-volume-signal", adapter.confirmedAudio["11"].volume === 0.25
                && !adapter.confirmedAudio["11"].muted
                && adapter.state.value.outputs.find(function(item) { return item.id === "11"; }).volume === 0.25);
            check("watched-stream-follows-native-mute-signal", adapter.confirmedAudio[editor.id].muted === true
                && adapter.confirmedAudio[editor.id].volume === 0.45
                && adapter.state.value.streams.find(function(item) { return item.id === editor.id; }).muted === true);
            adapter.releaseMixer("fixture");
            streamAudio.volume = 0.3;
            check("unwatched-stream-ignores-native-signals", adapter.confirmedAudio[editor.id].volume === 0.45);
            adapter.retainMixer("fixture");
            check("rewatched-stream-drops-stale-confirmation", adapter.confirmedAudio[editor.id] === undefined
                && adapter.state.value.streams.find(function(item) { return item.id === editor.id; }).volume === 0.3);
        } else if (scenario === "microphone") {
            check("unlinked-capture-is-not-microphone-use", adapter.state.value.microphone.active === false
                && adapter.state.value.microphone.muted === false
                && adapter.state.value.microphone.apps.length === 0, JSON.stringify(adapter.state.value.microphone));
            // The streams already exist; only the new links may light the indicator.
            fakeLinkGroups.values = [{ source: inputNode, target: captureNode },
                { source: outputNode, target: monitorCaptureNode }];
            const linked = adapter.state.value.microphone;
            check("hardware-capture-is-published", linked.active === true && linked.apps.length === 1
                && linked.apps[0].key === "handy" && linked.apps[0].label === "Handy"
                && linked.apps[0].muted === inputAudio.muted && linked.muted === inputAudio.muted,
                JSON.stringify(linked));
            inputAudio.muted = true;
            const muted = adapter.state.value.microphone;
            check("muted-source-mutes-microphone-use", muted.active === true && muted.muted === true
                && muted.apps.length === 1 && muted.apps[0].muted === true, JSON.stringify(muted));
            fakeLinkGroups.values = fakeLinkGroups.values.concat([{ source: inputNode, target: null }]);
            check("link-without-target-is-ignored",
                JSON.stringify(adapter.state.value.microphone) === JSON.stringify(muted),
                JSON.stringify(adapter.state.value.microphone));
            finish();
        } else if (scenario === "late-confirmation") {
            firstRequest = adapter.setVolume("output", 0.7); latestRequest = firstRequest;
            adapter.finishOperation("volume:output:10", false, "timeout");
        } else if (scenario === "stream-ready") {
            fakeNodes.values = fakeNodes.values.concat([replacementNode]);
            adapter.retainMixer("fixture");
            const tokenRecord = adapter.nodeIdentities.find(function(item) { return item.node === replacementNode; });
            const token = tokenRecord ? tokenRecord.token : "";
            replacementNode.ready = true;
            const replacement = adapter.state.value.streams.find(function(item) { return item.appName === "Replacement"; });
            check("stream-token-survives-tracker-readiness", !!token && replacement && replacement.id === token);
            finish();
        }
    }
    Timer {
        interval: 25
        repeat: true
        running: true
        onTriggered: {
            root.ticks++;
            if (!root.requested && adapter.state.kind === "ready") {
                root.requested = true;
                root.start();
            }
            if (root.scenario === "service-loss" && root.results.length && fakeBackend.ready === false) {
                outputAudio.volume = 0.3;
                fakeBackend.ready = true;
                root.check("backend-reconnect-clears-confirmed-cache-for-reused-node-id",
                    adapter.state.kind === "ready" && Object.keys(adapter.operations).length === 0
                    && adapter.confirmedAudio["10"] === undefined
                    && adapter.state.value.output.volume === 0.3);
            }
            if (root.scenario === "native-signals" && root.requested) {
                // Longer than the former 1.5 s poll interval: an idle adapter must not probe.
                if (root.ticks < 80) return;
                root.check("idle-adapter-does-not-probe", Object.keys(adapter.probes).length === 0
                    && Object.keys(adapter.operations).length === 0);
                root.finish();
                return;
            }
            const latest = root.resultFor(root.latestRequest);
            if (!latest) {
                if (root.ticks > 240) { root.check("fixture-timed-out", false,
                    root.scenario + ":" + JSON.stringify({ operations: adapter.operations,
                        backendReady: fakeBackend.ready, request: root.latestRequest,
                        results: root.results })); root.finish(); }
                return;
            }
            if (root.scenario === "stream-controls") {
                const first = root.resultFor(root.firstRequest);
                root.check("independent-stream-commands-confirm", first && first.result.ok
                    && first.result.value === 0.72 && latest.result.ok && latest.result.muted);
                root.check("stream-confirmed-state-updates-by-lifetime-id",
                    adapter.state.value.streams.find(function(item) { return item.appName === "Editor"; }).volume === 0.72
                    && adapter.state.value.streams.find(function(item) { return item.appName === "Browser"; }).muted);
            } else if (root.scenario === "stream-guards") {
                const first = root.resultFor(root.firstRequest);
                root.check("safe-mode-rejects-stream-write", first && !first.result.ok
                    && first.result.reason === "safe-mode");
                root.check("preview-rejects-stream-write", !latest.result.ok
                    && latest.result.reason === "preview");
                const invalid = root.resultFor(root.invalidRequest);
                root.check("invalid-stream-volume-is-rejected", invalid && !invalid.result.ok
                    && invalid.result.reason === "unsupported");
            } else if (root.scenario === "stream-recycled") {
                const replacement = adapter.state.value.streams.find(function(item) { return item.appName === "Replacement"; });
                root.check("recycled-node-request-fails-against-old-lifetime", !latest.result.ok
                    && latest.result.reason === "device-removed");
                root.check("recycled-node-id-gets-fresh-token-and-state", replacement
                    && replacement.nodeId === "31" && replacement.id !== root.delayedProbe.id
                    && replacement.volume === 0.2 && !replacement.pendingVolume);
            } else if (root.scenario === "success") {
                root.check("volume-request-completes-with-readback", latest.result.ok
                    && latest.result.value === 0.7 && adapter.state.value.output.volume === 0.7);
            } else if (root.scenario === "mute") {
                root.check("mute-request-completes-with-readback", latest.result.ok
                    && latest.result.muted && adapter.state.value.output.muted === true);
            } else if (root.scenario === "set-mute") {
                const same = root.resultFor(root.invalidRequest);
                root.check("set-mute-to-current-state-is-a-no-op-success", !!same && same.result.ok
                    && same.result.muted === false && !inputAudio.muted);
                root.check("set-mute-completes-with-readback", latest.result.ok
                    && latest.result.muted && adapter.state.value.output.muted === true);
            } else if (root.scenario === "default") {
                root.check("default-request-completes-after-observed-route", latest.result.ok
                    && latest.result.id === "11" && adapter.state.value.output.id === "11");
            } else if (root.scenario === "default-timeout") {
                root.check("default-route-timeout-does-not-claim-configured-target", !latest.result.ok
                    && latest.result.reason === "timeout" && adapter.state.value.output.id === "10");
            } else if (root.scenario === "supersede") {
                const first = root.resultFor(root.firstRequest);
                root.check("superseded-request-resolves-once", first && !first.result.ok
                    && first.result.reason === "superseded"
                    && root.results.filter(function(item) { return item.id === root.firstRequest; }).length === 1);
                root.check("latest-volume-is-the-confirmed-value", latest.result.ok && latest.result.value === 0.8
                    && adapter.state.value.output.volume === 0.8);
            } else if (root.scenario === "stale-probe") {
                if (!root.staleProbeScheduled) {
                    root.staleProbeScheduled = true;
                    Qt.callLater(function() {
                        adapter.finishProbe(root.delayedProbe, { volume: 0.4, muted: false });
                        root.check("late-probe-cannot-overwrite-newer-confirmation",
                            latest.result.ok && adapter.state.value.output.volume === 0.7
                            && adapter.confirmedAudio["10"].volume === 0.7);
                        root.finish();
                    });
                    return;
                }
            } else if (root.scenario === "late-confirmation") {
                const confirmed = adapter.confirmedAudio["10"];
                if (confirmed && confirmed.volume === 0.7 && !Object.keys(adapter.probes).length) {
                    root.check("unconfirmed-write-is-reconciled-by-one-readback", !latest.result.ok
                        && latest.result.reason === "timeout" && adapter.state.value.output.volume === 0.7);
                } else if (root.ticks <= 200) return;
                else root.check("unconfirmed-write-is-reconciled-by-one-readback", false, JSON.stringify(confirmed));
            } else if (root.scenario === "timeout") {
                root.check("readback-timeout-preserves-last-confirmed-value", !latest.result.ok
                    && latest.result.reason === "timeout" && adapter.state.value.output.volume === 0.4);
            } else if (root.scenario === "device-removed") {
                root.check("device-removal-resolves-pending-request", !latest.result.ok
                    && latest.result.reason === "device-removed");
            } else if (root.scenario === "service-loss") {
                root.check("backend-loss-resolves-pending-request", !latest.result.ok
                    && latest.result.reason === "service-missing");
            } else if (root.scenario === "missing-utility") {
                root.check("missing-readback-utility-is-not-reported-as-success", !latest.result.ok
                    && latest.result.reason === "unavailable"
                    && adapter.state.value.output.volume === 0.4);
            }
            root.finish();
        }
    }
}
