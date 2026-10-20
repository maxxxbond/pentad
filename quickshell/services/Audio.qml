pragma ComponentBehavior: Bound
import QtQuick
import Quickshell.Io
import Quickshell.Services.Pipewire
import "../logic/audio.mjs" as AudioLogic

QtObject {
    id: root
    property bool preview: false
    property bool safeMode: false
    property var backendOverride: null
    property int nextRequestId: 1
    property double contextualFeedbackUntil: 0
    property var operations: ({})
    property var confirmedAudio: ({})
    property var probes: ({})
    property var probeGenerations: ({})
    property var mixerConsumers: ({})
    property var nodeIdentities: []
    property var knownNodes: []
    property int nextNodeIdentity: 1
    readonly property bool active: !preview && !!backend && backend.ready
    readonly property var backend: backendOverride || (!preview ? Pipewire : null)
    readonly property var state: !active
        ? ({ kind: "unavailable", reason: preview ? "preview" : "service-missing" })
        : ({ kind: "ready", value: {
            output: describe(backend.defaultAudioSink),
            input: describe(backend.defaultAudioSource),
            outputs: devices("output"),
            inputs: devices("input"),
            streams: mixerConsumersCount ? playbackStreams() : []
        } })
    readonly property int mixerConsumersCount: Object.keys(mixerConsumers).length
    signal commandFinished(string requestId, var result)

    property Component commandWorker: Component {
        Process {
            id: process
            required property string key
            required property string requestId
            required property string kind
            required property string nodeId
            required property string field
            required property real targetValue
            required property bool targetMuted
            property bool startedOnce: false
            property bool settled: false
            property bool outputOverflow: false
            property string output: ""
            command: ["wpctl", "get-volume", nodeId]
            stdout: SplitParser {
                splitMarker: ""
                onRead: function(chunk) { process.captureChunk(chunk); }
            }
            stderr: SplitParser { splitMarker: "" }
            property Timer commandDeadline: Timer {
                interval: 1200
                running: false
                onTriggered: {
                    if (process.running) process.signal(9);
                    root.finishOperation(process.key, false, "timeout");
                }
            }
            property Timer startDeadline: Timer {
                interval: 1200
                running: true
                onTriggered: if (!process.startedOnce && !process.settled)
                    root.finishOperation(process.key, false, "unavailable");
            }
            property Timer retry: Timer {
                interval: 125
                running: false
                onTriggered: {
                    if (!process.settled && root.operations[process.key]) {
                        process.running = true;
                    }
                }
            }
            property Timer deadline: Timer {
                interval: 3000
                running: true
                onTriggered: root.finishOperation(process.key, false, "timeout");
            }
            onStarted: {
                startedOnce = true;
                output = "";
                outputOverflow = false;
                startDeadline.stop(); commandDeadline.restart();
            }
            onRunningChanged: if (!running && !startedOnce && !settled)
                root.finishOperation(key, false, "unavailable");
            onExited: function(code, exitStatus) {
                commandDeadline.stop();
                if (settled || !root.operations[key]) return;
                if (outputOverflow) {
                    root.finishOperation(key, false, "invalid-response");
                    return;
                }
                if (code !== 0 || exitStatus !== 0) {
                    root.finishOperation(key, false, "io");
                    return;
                }
                try {
                    const actual = AudioLogic.parseWpctlVolume(output);
                    const operation = root.operations[key];
                    if (operation && (!root.containsNode(operation.node)
                        || root.audioKey(operation.node) !== operation.nodeKey)) {
                        root.finishOperation(key, false, "device-removed");
                        return;
                    }
                    if (operation) root.updateFromReadback(operation, actual);
                    const matches = field === "volume"
                        ? AudioLogic.volumeMatches(actual.volume, targetValue)
                        : actual.muted === targetMuted;
                    if (matches) root.finishOperation(key, true, "ok", actual);
                    else retry.restart();
                } catch (error) {
                    root.finishOperation(key, false, error.message || "invalid-response");
                }
            }
            function captureChunk(chunk) {
                const text = String(chunk);
                if (output.length + text.length > 4096) {
                    outputOverflow = true;
                    if (running) signal(9);
                    return;
                }
                output += text;
            }
        }
    }

    property Component probeWorker: Component {
        Process {
            id: process
            required property string nodeKey
            required property string nodeAddress
            required property var node
            required property int generation
            property bool startedOnce: false
            property bool outputOverflow: false
            property string output: ""
            command: ["wpctl", "get-volume", nodeAddress]
            stdout: SplitParser {
                splitMarker: ""
                onRead: function(chunk) { process.captureChunk(chunk); }
            }
            stderr: SplitParser { splitMarker: "" }
            property Timer deadline: Timer {
                interval: 1200
                running: false
                onTriggered: {
                    if (process.running) process.signal(9);
                    root.finishProbe(process, null);
                }
            }
            onStarted: { startedOnce = true; output = ""; outputOverflow = false; deadline.restart(); }
            onRunningChanged: if (!running && !startedOnce) root.finishProbe(process, null);
            onExited: function(code, exitStatus) {
                deadline.stop();
                if (code !== 0 || exitStatus !== 0 || outputOverflow) {
                    root.finishProbe(process, null); return;
                }
                try { root.finishProbe(process, AudioLogic.parseWpctlVolume(output)); }
                catch (error) { root.finishProbe(process, null); }
            }
            function captureChunk(chunk) {
                const text = String(chunk);
                if (output.length + text.length > 4096) {
                    outputOverflow = true;
                    if (running) signal(9);
                    return;
                }
                output += text;
            }
        }
    }

    property Component defaultDeadline: Component {
        Timer {
            required property string key
            interval: 3000
            repeat: false
            onTriggered: root.finishOperation(key, false, "timeout");
        }
    }

    property Timer probeTimer: Timer {
        interval: 1500
        repeat: true
        running: root.active
        onTriggered: root.startProbes()
    }

    function requestId() { return `audio-${nextRequestId++}`; }
    function finishLater(id, result) {
        Qt.callLater(function() { root.commandFinished(id, result); });
    }
    function audioNode(kind) {
        if (!active || (kind !== "input" && kind !== "output")) return null;
        const node = kind === "input" ? backend.defaultAudioSource : backend.defaultAudioSink;
        return node && node.ready && node.audio ? node : null;
    }
    function nodeId(node) { return node ? String(node.id) : ""; }
    function identity(node) {
        if (!node) return "";
        let record = nodeIdentities.find(function(item) { return item.node === node; });
        if (!record) {
            record = { node: node, token: `node-${nextNodeIdentity++}` };
            nodeIdentities = nodeIdentities.concat([record]);
        }
        return record.token;
    }
    function existingIdentity(node) {
        const record = nodeIdentities.find(function(item) { return item.node === node; });
        return record ? record.token : "";
    }
    function audioKey(node) { return existingIdentity(node) || nodeId(node); }
    function operationKey(node, field) {
        const id = audioKey(node);
        const kind = id.startsWith("node-") ? "stream" : (node.isSink ? "output" : "input");
        return `${field}:${kind}:${id}`;
    }
    function pruneNodeIdentities() {
        const nodes = backend && backend.nodes ? backend.nodes.values : [];
        const cache = Object.assign({}, confirmedAudio);
        for (let i = 0; i < knownNodes.length; ++i) {
            const node = knownNodes[i];
            if (nodes.indexOf(node) >= 0) continue;
            delete cache[audioKey(node)];
            invalidateProbe(audioKey(node));
            const keys = Object.keys(operations).filter(function(key) { return operations[key].node === node; });
            for (let j = 0; j < keys.length; ++j) finishOperation(keys[j], false, "device-removed");
        }
        confirmedAudio = cache;
        knownNodes = nodes.filter(function(node) { return node && !existingIdentity(node); });
        const live = [];
        for (let i = 0; i < nodeIdentities.length; ++i) {
            const record = nodeIdentities[i];
            if (nodes.indexOf(record.node) >= 0) live.push(record);
            else {
                const streamCache = Object.assign({}, confirmedAudio); delete streamCache[record.token]; confirmedAudio = streamCache;
                invalidateProbe(record.token);
                const keys = Object.keys(operations).filter(function(key) { return operations[key].node === record.node; });
                for (let j = 0; j < keys.length; ++j) finishOperation(keys[j], false, "device-removed");
            }
        }
        nodeIdentities = live;
        if (mixerConsumersCount) {
            for (let i = 0; i < nodes.length; ++i) {
                const node = nodes[i];
                if (node && node.isStream && !node.isSink) identity(node);
            }
        }
    }
    function describe(node) {
        if (!node || !node.ready || !node.audio) return null;
        const confirmed = confirmedAudio[audioKey(node)];
        const volume = Math.round(Math.max(0, Math.min(1,
            confirmed ? confirmed.volume : node.audio.volume)) * 100) / 100;
        // Feedback follows the pending target so fast wheel steps don't freeze or rewind on readback.
        const pending = operations[operationKey(node, "volume")];
        return Object.assign(AudioLogic.audioDevicePresentation(node), {
            id: nodeId(node),
            volume: volume,
            requestedVolume: pending ? pending.targetValue : volume,
            muted: confirmed ? confirmed.muted : node.audio.muted
        });
    }
    function playbackStreams() {
        if (!active || !mixerConsumersCount || !backend.nodes) return [];
        return backend.nodes.values.filter(function(node) {
            return node && node.ready && node.isStream && !node.isSink && node.audio;
        }).map(function(node) {
            const id = existingIdentity(node), key = `stream:${id}`;
            const volumeOperation = operations[`volume:${key}`];
            const muteOperation = operations[`mute:${key}`];
            const props = node.properties || ({});
            const appName = props["application.name"] || props["application.process.binary"]
                || node.description || node.nickname || node.name || "Unknown application";
            const mediaName = props["media.name"] || "";
            const confirmed = confirmedAudio[id];
            return {
                id: id, nodeId: nodeId(node), appName: String(appName),
                label: String(mediaName || appName), mediaName: String(mediaName),
                icon: String(props["application.icon-name"] || props["application.icon"] || ""),
                volume: Math.round(Math.max(0, Math.min(1,
                    confirmed ? confirmed.volume : node.audio.volume)) * 100) / 100,
                muted: confirmed ? confirmed.muted : node.audio.muted,
                pendingVolume: !!volumeOperation, pendingMute: !!muteOperation,
                requestedVolume: volumeOperation ? volumeOperation.targetValue
                    : Math.round(Math.max(0, Math.min(1,
                        confirmed ? confirmed.volume : node.audio.volume)) * 100) / 100
            };
        });
    }
    function retainMixer(consumerId) {
        if (typeof consumerId !== "string" || !consumerId) return;
        mixerConsumers = Object.assign({}, mixerConsumers, { [consumerId]: true });
        pruneNodeIdentities();
        startProbes();
    }
    function releaseMixer(consumerId) {
        if (typeof consumerId !== "string" || !mixerConsumers[consumerId]) return;
        const next = Object.assign({}, mixerConsumers); delete next[consumerId]; mixerConsumers = next;
        if (!mixerConsumersCount) {
            const ids = Object.keys(probes);
            for (let i = 0; i < ids.length; ++i)
                if (!probes[ids[i]].node || probes[ids[i]].node.isStream) invalidateProbe(ids[i]);
        }
    }
    function devices(kind) {
        if (!active || (kind !== "input" && kind !== "output")) return [];
        return AudioLogic.disambiguateAudioDevices(backend.nodes.values
            .filter(function(node) {
                return node && node.ready && node.audio && !node.isStream && node.isSink === (kind === "output");
            })
            .map(function(node) { return describe(node); }));
    }
    function findNode(kind, id) {
        if (!active || !backend.nodes) return null;
        return backend.nodes.values.find(function(node) {
            return node && node.ready && node.audio && !node.isStream
                && node.isSink === (kind === "output") && nodeId(node) === id;
        }) || null;
    }
    function containsNode(node) { return !!node && !!backend && !!backend.nodes
        && backend.nodes.values.indexOf(node) >= 0 && node.ready; }
    function updateFromNativeSignal(node) {
        if (!active || !containsNode(node)) return;
        const id = audioKey(node);
        if (operations[operationKey(node, "volume")] || operations[operationKey(node, "mute")]) return;
        confirmedAudio = Object.assign({}, confirmedAudio, {
            [id]: { volume: node.audio.volume, muted: node.audio.muted }
        });
    }
    function updateFromReadback(operation, actual) {
        if (!containsNode(operation.node) || audioKey(operation.node) !== operation.nodeKey) return;
        confirmedAudio = Object.assign({}, confirmedAudio, {
            [operation.nodeKey]: { volume: actual.volume, muted: actual.muted }
        });
    }

    function invalidateProbe(id) {
        const generations = Object.assign({}, probeGenerations, { [id]: (probeGenerations[id] || 0) + 1 });
        probeGenerations = generations;
        const probe = probes[id];
        if (!probe) return;
        const next = Object.assign({}, probes); delete next[id]; probes = next;
        probe.deadline.stop();
        if (probe.running) probe.signal(9);
        probe.destroy();
    }
    function startProbes() {
        if (!active || !backend.nodes) return;
        const nodes = backend.nodes.values.filter(function(node) {
            return node && node.ready && node.audio
                && (!node.isStream || (!node.isSink && mixerConsumersCount));
        });
        for (let i = 0; i < nodes.length; ++i) {
            const node = nodes[i], id = audioKey(node);
            if (node.isStream && !mixerConsumersCount) continue;
            const writing = operations[operationKey(node, "volume")]
                || operations[operationKey(node, "mute")];
            if (writing || probes[id]) continue;
            const probe = probeWorker.createObject(root, {
                nodeKey: id, nodeAddress: nodeId(node), node: node, generation: probeGenerations[id] || 0
            });
            if (!probe) continue;
            probes = Object.assign({}, probes, { [id]: probe });
            probe.running = true;
        }
    }
    function finishProbe(probe, actual) {
        if (!probe) return;
        const id = probe.nodeKey;
        const current = probes[id] === probe
            && (probeGenerations[id] || 0) === probe.generation
            && !operations[operationKey(probe.node, "volume")]
            && !operations[operationKey(probe.node, "mute")]
            && containsNode(probe.node)
            && (!probe.node.isStream || mixerConsumersCount > 0);
        if (probes[id] === probe) {
            const next = Object.assign({}, probes); delete next[id]; probes = next;
        }
        probe.deadline.stop();
        if (current && actual) {
            confirmedAudio = Object.assign({}, confirmedAudio, { [id]: actual });
        }
        probe.destroy();
    }

    function begin(key, id, kind, node, field, value, muted) {
        invalidateProbe(audioKey(node));
        if (operations[key]) finishOperation(key, false, "superseded");
        const numericId = nodeId(node), nodeKey = audioKey(node);
        if (!confirmedAudio[nodeKey]) {
            confirmedAudio = Object.assign({}, confirmedAudio, {
                [nodeKey]: { volume: node.audio.volume, muted: node.audio.muted }
            });
        }
        const worker = commandWorker.createObject(root, {
            key: key, requestId: id, kind: kind, nodeId: numericId, field: field,
            targetValue: value, targetMuted: muted
        });
        if (!worker) { finishLater(id, { ok: false, reason: "unavailable" }); return; }
        const operation = { requestId: id, key: key, kind: kind, node: node,
            nodeId: numericId, nodeKey: nodeKey, field: field, targetValue: value, targetMuted: muted,
            worker: worker, deadline: null };
        const next = Object.assign({}, operations, { [key]: operation });
        operations = next;
        if (field === "default") {
            worker.deadline.stop();
            worker.destroy();
            operation.worker = null;
            operation.deadline = defaultDeadline.createObject(root, { key: key });
            if (!operation.deadline) finishOperation(key, false, "unavailable");
            else operation.deadline.start();
        }
        return operation;
    }
    function finishOperation(key, ok, reason, actual) {
        const operation = operations[key];
        if (!operation) return;
        const next = Object.assign({}, operations);
        delete next[key];
        operations = next;
        if (operation.deadline) { operation.deadline.stop(); operation.deadline.destroy(); }
        if (operation.worker) {
            const worker = operation.worker;
            worker.settled = true;
            worker.deadline.stop(); worker.retry.stop(); worker.commandDeadline.stop(); worker.startDeadline.stop();
            if (worker.running) worker.signal(9);
            worker.destroy();
        }
        const result = ok ? operation.field === "default"
            ? { ok: true, id: operation.nodeId }
            : { ok: true, value: actual.volume, muted: actual.muted }
            : { ok: false, reason: reason, id: operation.nodeId };
        if (ok && operation.field !== "default") {
            confirmedAudio = Object.assign({}, confirmedAudio, {
                [operation.nodeKey]: { volume: actual.volume, muted: actual.muted }
            });
        }
        finishLater(operation.requestId, result);
    }
    function cancelForBackend(reason) {
        const keys = Object.keys(operations);
        for (let i = 0; i < keys.length; ++i) finishOperation(keys[i], false, reason);
    }
    function validateWrite(kind) {
        if (safeMode) return "safe-mode";
        if (!active) return preview ? "preview" : "unavailable";
        if (kind !== "input" && kind !== "output") return "unsupported";
        return "";
    }
    function setVolume(kind, value) {
        const id = requestId(), error = validateWrite(kind);
        if (error) { finishLater(id, { ok: false, reason: error }); return id; }
        if (!Number.isFinite(value) || value < 0 || value > 1) {
            finishLater(id, { ok: false, reason: "unsupported" }); return id;
        }
        const node = audioNode(kind);
        if (!node) { finishLater(id, { ok: false, reason: "unavailable" }); return id; }
        const target = Math.round(value * 100) / 100;
        const key = `volume:${kind}:${nodeId(node)}`;
        const operation = begin(key, id, kind, node, "volume", target, false);
        if (operation && operations[key] === operation) {
            node.audio.volume = target;
            operation.worker.running = true;
        }
        return id;
    }
    function streamNode(streamId) {
        if (!active || !mixerConsumersCount || typeof streamId !== "string") return null;
        return backend.nodes.values.find(function(node) {
            return node && node.ready && node.isStream && !node.isSink && node.audio
                && existingIdentity(node) === streamId;
        }) || null;
    }
    function setStreamVolume(streamId, value) {
        const id = requestId();
        if (safeMode || !active) {
            finishLater(id, { ok: false, reason: safeMode ? "safe-mode" : (preview ? "preview" : "unavailable") });
            return id;
        }
        if (!Number.isFinite(value) || value < 0 || value > 1) {
            finishLater(id, { ok: false, reason: "unsupported" }); return id;
        }
        const node = streamNode(streamId);
        if (!node) { finishLater(id, { ok: false, reason: "device-removed" }); return id; }
        const target = Math.round(value * 100) / 100, key = `volume:stream:${streamId}`;
        const operation = begin(key, id, "stream", node, "volume", target, false);
        if (operation && operations[key] === operation && containsNode(node) && existingIdentity(node) === streamId) {
            node.audio.volume = target;
            operation.worker.running = true;
        }
        return id;
    }
    function toggleStreamMute(streamId) {
        const id = requestId();
        if (safeMode || !active) {
            finishLater(id, { ok: false, reason: safeMode ? "safe-mode" : (preview ? "preview" : "unavailable") });
            return id;
        }
        const node = streamNode(streamId);
        if (!node) { finishLater(id, { ok: false, reason: "device-removed" }); return id; }
        const muted = !node.audio.muted, key = `mute:stream:${streamId}`;
        const operation = begin(key, id, "stream", node, "muted", 0, muted);
        if (operation && operations[key] === operation && containsNode(node) && existingIdentity(node) === streamId) {
            node.audio.muted = muted;
            operation.worker.running = true;
        }
        return id;
    }
    function adjustVolume(kind, steps) {
        const node = audioNode(kind);
        if (!node || !Number.isInteger(steps)) {
            const id = requestId();
            finishLater(id, { ok: false, reason: node ? "unsupported" : "unavailable" });
            return id;
        }
        let volume = Math.max(0, Math.min(1, node.audio.volume));
        const direction = Math.sign(steps);
        for (let i = 0; i < Math.abs(steps); ++i)
            volume = Math.max(0, Math.min(1, volume + direction * (volume < 0.1 ? 0.01 : 0.02)));
        return setVolume(kind, Math.round(volume * 100) / 100);
    }
    function toggleMute(kind) {
        const id = requestId(), error = validateWrite(kind);
        if (error) { finishLater(id, { ok: false, reason: error }); return id; }
        const node = audioNode(kind);
        if (!node) { finishLater(id, { ok: false, reason: "unavailable" }); return id; }
        const muted = !node.audio.muted;
        const key = `mute:${kind}:${nodeId(node)}`;
        const operation = begin(key, id, kind, node, "muted", 0, muted);
        if (operation && operations[key] === operation) {
            node.audio.muted = muted;
            operation.worker.running = true;
        }
        return id;
    }
    function setDefault(kind, id) {
        const request = requestId(), error = validateWrite(kind);
        if (error) { finishLater(request, { ok: false, reason: error }); return request; }
        if (typeof id !== "string") { finishLater(request, { ok: false, reason: "unsupported" }); return request; }
        const node = findNode(kind, id);
        if (!node) { finishLater(request, { ok: false, reason: "unavailable" }); return request; }
        const current = kind === "input" ? backend.defaultAudioSource : backend.defaultAudioSink;
        if (current && nodeId(current) === id && !operations[`default:${kind}`]) {
            finishLater(request, { ok: true, id: id }); return request;
        }
        const key = `default:${kind}`;
        if (!begin(key, request, kind, node, "default", 0, false)) return request;
        if (backendOverride) backend.setDefault(kind, node);
        else if (kind === "input") backend.preferredDefaultAudioSource = node;
        else backend.preferredDefaultAudioSink = node;
        checkDefault(kind);
        return request;
    }
    function cycleDefault(kind, steps) {
        const id = requestId();
        if (!Number.isInteger(steps)) { finishLater(id, { ok: false, reason: "unsupported" }); return id; }
        if (safeMode || !active) {
            finishLater(id, { ok: false, reason: safeMode ? "safe-mode" : "unavailable" }); return id;
        }
        const current = kind === "input" ? backend.defaultAudioSource : backend.defaultAudioSink;
        const nodes = devices(kind);
        const pending = operations[`default:${kind}`];
        const currentId = pending ? pending.nodeId : nodeId(current);
        const index = nodes.findIndex(function(node) { return node.id === currentId; });
        if (nodes.length < 2 || index < 0) { finishLater(id, { ok: false, reason: "unavailable" }); return id; }
        const next = ((index + steps) % nodes.length + nodes.length) % nodes.length;
        return setDefault(kind, nodes[next].id);
    }
    function checkDefault(kind) {
        const key = `default:${kind}`, operation = operations[key];
        if (!operation) return;
        const actual = kind === "input" ? backend.defaultAudioSource : backend.defaultAudioSink;
        if (!containsNode(operation.node)) finishOperation(key, false, "device-removed");
        else if (actual && nodeId(actual) === operation.nodeId) finishOperation(key, true, "ok");
    }
    function checkOperations() {
        if (!active) {
            cancelForBackend("service-missing");
            const probeIds = Object.keys(probes);
            for (let i = 0; i < probeIds.length; ++i) invalidateProbe(probeIds[i]);
            confirmedAudio = ({});
            nodeIdentities = [];
            knownNodes = [];
            return;
        }
        pruneNodeIdentities();
        const keys = Object.keys(operations);
        for (let i = 0; i < keys.length; ++i) {
            const operation = operations[keys[i]];
            if (!containsNode(operation.node)) finishOperation(keys[i], false, "device-removed");
            else if (operation.field === "default") checkDefault(operation.kind);
        }
    }

    property Connections backendChanges: Connections {
        target: root.backend
        function onReadyChanged() { root.checkOperations(); }
        function onDefaultAudioSinkChanged() { root.checkDefault("output"); }
        function onDefaultAudioSourceChanged() { root.checkDefault("input"); }
    }
    property Connections outputAudioChanges: Connections {
        target: root.backend && root.backend.defaultAudioSink ? root.backend.defaultAudioSink.audio : null
        function onVolumesChanged() { root.updateFromNativeSignal(root.backend.defaultAudioSink); }
        function onMutedChanged() { root.updateFromNativeSignal(root.backend.defaultAudioSink); }
    }
    property Connections inputAudioChanges: Connections {
        target: root.backend && root.backend.defaultAudioSource ? root.backend.defaultAudioSource.audio : null
        function onVolumesChanged() { root.updateFromNativeSignal(root.backend.defaultAudioSource); }
        function onMutedChanged() { root.updateFromNativeSignal(root.backend.defaultAudioSource); }
    }
    property Connections nodesChanges: Connections {
        target: root.backend ? root.backend.nodes : null
        function onValuesChanged() { root.checkOperations(); }
    }
    property PwObjectTracker tracker: PwObjectTracker {
        objects: root.active && !root.backendOverride ? root.backend.nodes.values.filter(function(node) {
            return node && (!node.isStream || (root.mixerConsumersCount && !node.isSink));
        }) : []
    }
    Component.onDestruction: cancelForBackend("service-stopped")
}
