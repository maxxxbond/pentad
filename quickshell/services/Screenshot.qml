import QtQuick
import QtQml
import Quickshell
import Quickshell.Io
import '../logic/screenshot-windows.mjs' as Windows

QtObject {
    id: root
    required property var services
    readonly property string helperPath: services.config.helperPath
        ? services.config.helperPath.replace(/pentad-files\.py$/, 'pentad_screenshot.py') : ''
    property bool active: false
    property string phase: 'idle'
    property string outputId: ''
    property string imagePath: ''
    property int imageWidth: 0
    property int imageHeight: 0
    property var windowRegions: []
    property var frames: ({})
    property bool choosingOutput: false
    property var captureTokens: []
    property string error: ''
    property var lastExport: null
    readonly property bool busy: phase === 'preparing' || phase === 'exporting' || worker !== null
    property bool settingsOpen: false
    property string mode: ''
    property string session: ''
    property string pendingOutput: ''
    property bool selectionPending: false
    property var pendingInitialCrop: null
    property int generation: 0
    property var worker: null
    property var frozenWindowSnapshot: null
    property var cancellingProcess: null
    property var overlayOutputs: ({})
    property var focusReturnTarget: null
    property bool focusReturnPending: false
    property bool focusReturnScheduled: false
    property int focusReturnSerial: 0
    signal captured(string mode, var initialCrop)
    signal exported(bool closeAfter)
    signal bindingsExported(var result)
    // Picking: the overlay doubles as an area chooser for other tools (OCR, search, ruler, recording...).
    // `picked` carries the cropped image and the geometry; `pickCancelled` fires when nothing was chosen.
    property string pickToken: ''
    property string pickLabel: ''
    property int pickScale: 1
    // Engines the overlay offers next to the chosen area ({ id, name }); empty when the tool needs no choice.
    property var pickEngines: []
    property var pickChoice: []
    property var analysis: null
    property var analysisQueue: []
    signal picked(string token, var result)
    signal pickCancelled(string token)

    // Ask the user to choose an area. `options`: { label, scale (integer enlargement of the crop), output }.
    function pick(token, options) {
        if (active || busy || !token) return false;
        pickToken = token;
        pickLabel = options && options.label ? String(options.label) : '';
        pickScale = options && Number.isInteger(options.scale) && options.scale >= 1 && options.scale <= 8 ? options.scale : 1;
        pickEngines = options && Array.isArray(options.engines) ? options.engines : [];
        pickChoice = [];
        if (open('pick', options && options.output ? options.output : '')) return true;
        pickToken = '';
        pickLabel = '';
        pickScale = 1;
        pickEngines = [];
        return false;
    }

    function finishPick(rect, engines) {
        if (!active || mode !== 'pick' || !pickToken || worker || !session || !rect) return false;
        // Signals hand arrays over as Qt lists, so the ids are copied into a plain array.
        const ids = [];
        for (let i = 0; engines && i < engines.length; i++) ids.push(String(engines[i]));
        pickChoice = ids;
        phase = 'exporting';
        error = '';
        startRequest({ operation: 'crop', session: session, rect: { x: rect.x, y: rect.y, width: rect.width, height: rect.height },
            scale: pickScale }, 'crop');
        return true;
    }

    // The chosen area in the compositor's coordinates (what recorders and window tools use), or null.
    function logicalRect(imageRect) {
        const snapshot = captureWindowSnapshot();
        const outputs = snapshot && snapshot.desktop && Array.isArray(snapshot.desktop.outputs) ? snapshot.desktop.outputs : [];
        const output = outputs.find(item => item.name === outputId || item.id === outputId);
        if (!output || !(output.width > 0) || !(output.height > 0) || !(imageWidth > 0) || !(imageHeight > 0)) return null;
        const scaleX = imageWidth / output.width, scaleY = imageHeight / output.height;
        return { x: Math.round(output.x + imageRect.x / scaleX), y: Math.round(output.y + imageRect.y / scaleY),
            width: Math.max(1, Math.round(imageRect.width / scaleX)), height: Math.max(1, Math.round(imageRect.height / scaleY)) };
    }

    // Suggestions come from the frozen pixels, one output at a time, without blocking the selection.
    function fetchContentRegions() {
        if (analysis || !active) return;
        const name = analysisQueue.shift();
        if (!name) return;
        const frame = frames[name];
        if (!frame || !helperPath) { fetchContentRegions(); return; }
        const request = requestComponent.createObject(root, { helperPath: helperPath,
            payload: { operation: 'proposals', session: frame.session } });
        if (!request) return;
        analysis = request;
        request.completed.connect(function(result) {
            request.watchdog.stop();
            if (analysis === request) analysis = null;
            request.destroy();
            const current = frames[name];
            // Signals hand arrays over as Qt lists, so they are copied into plain arrays before use.
            if (active && current && current.session === frame.session && result.ok && result.regions && result.regions.length !== undefined) {
                const regions = [];
                for (let i = 0; i < result.regions.length; i++) regions.push(result.regions[i]);
                const next = Object.assign({}, frames);
                next[name] = Object.assign({}, current, { contentRegions: regions });
                frames = next;
            }
            fetchContentRegions();
        });
        request.watchdog.restart();
        request.running = true;
    }

    function open(requestedMode, requestedOutput) {
        if (active || busy) return false;
        if (!['edit', 'copy', 'window', 'monitor', 'pick'].includes(requestedMode)) return false;
        if (requestedMode === 'pick' && !pickToken) return false;
        focusReturnSerial++;
        focusReturnPending = false;
        focusReturnTarget = null;
        mode = requestedMode;
        outputId = resolveOutput(requestedOutput || '');
        if (!outputId) {
            active = false;
            phase = 'error';
            error = 'No active monitor is available for screenshot capture.';
            return false;
        }
        pendingOutput = outputId;
        const windowState = services.hyprland ? services.hyprland.overviewSnapshot : null;
        frozenWindowSnapshot = windowState && windowState.kind === 'ready' ? windowState.value : null;
        error = '';
        imagePath = '';
        imageWidth = 0;
        imageHeight = 0;
        session = '';
        frames = ({});
        choosingOutput = false;
        captureTokens = [];
        if (services.safeMode || services.preview || !helperPath) {
            active = false;
            phase = 'error';
            error = services.safeMode || services.preview ? 'Screenshot capture is unavailable in preview mode.'
                : 'Screenshot helper is unavailable.';
            return false;
        }
        const previousClient = frozenWindowSnapshot && frozenWindowSnapshot.clients
            ? frozenWindowSnapshot.clients.find(client => client.address === frozenWindowSnapshot.activeAddress)
                || (!frozenWindowSnapshot.activeAddress && frozenWindowSnapshot.mru
                    ? frozenWindowSnapshot.clients.find(client => client.instanceId === frozenWindowSnapshot.mru[0]) : null)
            : null;
        focusReturnTarget = previousClient && previousClient.instanceId
            ? { address: previousClient.address, instanceId: previousClient.instanceId } : null;
        if (services.hyprland && typeof services.hyprland.refreshNativeCatalogNow === 'function')
            services.hyprland.refreshNativeCatalogNow();
        active = true;
        phase = 'preparing';
        if (mode === 'edit' || mode === 'copy' || mode === 'pick') captureAllOutputs();
        else captureOutput(pendingOutput);
        return phase === 'preparing';
    }

    function captureWindowSnapshot() {
        const state = services.hyprland ? services.hyprland.overviewSnapshot : null;
        return state && state.kind === 'ready' && state.value ? state.value : frozenWindowSnapshot;
    }

    function resolveOutput(requested) {
        const state = services.hyprland ? services.hyprland.state : null;
        const outputs = state && state.kind === 'ready' && state.value ? state.value.outputs || [] : [];
        let name = requested;
        if (requested) {
            const match = outputs.find(output => output.id === requested || output.name === requested);
            if (match) name = match.name;
        } else {
            const focusedId = state && state.kind === 'ready' && state.value
                ? state.value.focusedOutputId : '';
            const focused = outputs.find(output => output.id === focusedId || output.name === focusedId);
            name = focused ? focused.name : (Quickshell.screens.length ? Quickshell.screens[0].name : '');
        }
        return Quickshell.screens.some(screen => screen.name === name) ? name : '';
    }

    function newSessionId() {
        let token = '';
        while (token.length < 32)
            token += Math.floor(Math.random() * 0x100000000).toString(16).padStart(8, '0');
        return token.slice(0, 32);
    }

    function prepareSelection(initialCrop) {
        selectionPending = true;
        pendingInitialCrop = initialCrop;
        settingsOpen = false;
        if (services.navigation) services.navigation.cancel();
        if (services.popups && services.popups.prepareCapture) {
            captureGateDeadline.restart();
            services.popups.prepareCapture();
        } else fail('Screenshot selection requires the popup close gate.');
    }

    function onCaptureReady() {
        if (!active || phase !== 'preparing' || !selectionPending) return;
        captureGateDeadline.stop();
        selectionPending = false;
        const initialCrop = pendingInitialCrop;
        pendingInitialCrop = null;
        phase = 'selecting';
        error = '';
        captured(mode, initialCrop);
    }

    function captureAllOutputs() {
        if (!active || phase !== 'preparing' || worker) return false;
        const outputs = Quickshell.screens.map(screen => screen.name).filter(name => !!name);
        if (!outputs.length) { fail('No active monitor is available for screenshot capture.'); return false; }
        const sessions = outputs.map(() => newSessionId());
        captureTokens = sessions;
        startRequest({ operation: 'capture-all', outputs: outputs, sessions: sessions }, 'capture-all');
        return true;
    }

    function captureOutput(requestedOutput) {
        if (!active || phase !== 'preparing' || worker || requestedOutput !== pendingOutput) return false;
        if (!requestedOutput) { fail('No output selected for screenshot capture.'); return false; }
        const token = newSessionId();
        session = token;
        captureTokens = [token];
        startRequest({ operation: 'capture', output: requestedOutput, session: token }, 'capture');
        return true;
    }

    function chooseOutput(name) {
        if (!active) return false;
        if (!choosingOutput) return outputId === name && !!frames[name];
        const frame = frames[name];
        if (!frame) return false;
        outputId = frame.output;
        imagePath = frame.path;
        imageWidth = frame.width;
        imageHeight = frame.height;
        session = frame.session;
        windowRegions = frame.windowRegions;
        choosingOutput = false;
        return true;
    }

    function exportImage(document, action, closeAfter) {
        if (!active || worker || !session || !['copy', 'save'].includes(action)) return false;
        phase = 'exporting';
        error = '';
        lastExport = null;
        startRequest({ operation: 'export', session: session, document: document, action: action,
            directory: services.config.documents.screenshots.directory || '',
            autoSave: !!services.config.documents.screenshots.autoSave,
            fontFamily: services.config.documents.theme.fontFamily || 'Sans' }, 'export', !!closeAfter);
        return true;
    }

    function exportBindings(content) {
        if (!helperPath || services.safeMode || services.preview || worker) return false;
        startRequest({ operation: 'bindings', content: content }, 'bindings');
        return true;
    }

    function openSettings() {
        if (active || worker) return false;
        if (services.popups) services.popups.close();
        settingsOpen = true;
        return true;
    }

    function closeSettings() { settingsOpen = false; }

    function startRequest(payload, kind, closeAfter) {
        const requestGeneration = generation;
        const sessionsAtRequest = captureTokens.slice();
        const process = requestComponent.createObject(root, { helperPath: helperPath, payload: payload });
        if (!process) { fail('Could not start screenshot helper.'); return; }
        worker = process;
        process.completed.connect(function(result) {
            process.watchdog.stop();
            if (cancellingProcess === process) {
                cancellationKillTimer.stop();
                cancellingProcess = null;
            }
            if (worker === process) worker = null;
            if (requestGeneration !== generation) {
                const staleSessions = sessionsAtRequest.slice();
                if (payload.session) staleSessions.push(payload.session);
                if (payload.sessions) staleSessions.push.apply(staleSessions, payload.sessions);
                if (result.session) staleSessions.push(result.session);
                if (result.frames) result.frames.forEach(frame => staleSessions.push(frame.session));
                staleSessions.filter((token, index) => token && staleSessions.indexOf(token) === index)
                    .forEach(token => cleanupSession(token));
                process.destroy();
                return;
            }
            if (kind === 'capture-all') {
                const capturedFrames = result.frames || [];
                if (!result.ok || capturedFrames.length !== payload.outputs.length) {
                    fail(result.error || 'Screenshot capture failed on one or more monitors.');
                } else {
                    const map = ({});
                    const tokens = [];
                    const windowSnapshot = captureWindowSnapshot();
                    for (const frame of capturedFrames) {
                        const regions = Windows.capturedWindowRegions(windowSnapshot, frame.output,
                            frame.width, frame.height);
                        map[frame.output] = { output: frame.output, session: frame.session, path: frame.path,
                            width: frame.width, height: frame.height, windowRegions: regions };
                        tokens.push(frame.session);
                    }
                    frames = map;
                    captureTokens = tokens;
                    choosingOutput = true;
                    prepareSelection(null);
                    analysisQueue = capturedFrames.map(frame => frame.output);
                    fetchContentRegions();
                }
            } else if (kind === 'capture') {
                if (!result.ok || !result.path || !result.session || result.width < 1 || result.height < 1) {
                    fail(result.error || 'Screenshot capture failed.');
                } else {
                    outputId = pendingOutput;
                    imagePath = result.path;
                    imageWidth = result.width;
                    imageHeight = result.height;
                    session = result.session;
                    const windowSnapshot = captureWindowSnapshot();
                    windowRegions = Windows.capturedWindowRegions(windowSnapshot, outputId, imageWidth, imageHeight);
                    const map = ({});
                    map[outputId] = { output: outputId, session: session, path: imagePath,
                        width: imageWidth, height: imageHeight, windowRegions: windowRegions };
                    frames = map;
                    choosingOutput = false;
                    captureTokens = [session];
                    var initialCrop = null;
                    if (mode === 'monitor') initialCrop = { x: 0, y: 0, width: imageWidth, height: imageHeight };
                    if (mode === 'window') initialCrop = Windows.activeWindowCrop(windowSnapshot, outputId, imageWidth, imageHeight);
                    prepareSelection(initialCrop);
                }
            } else {
                if (kind === 'crop') {
                    if (!result.ok || !result.path) {
                        fail(result.error || 'Could not crop the selection.');
                        process.destroy();
                        return;
                    }
                    const token = pickToken;
                    const area = { x: result.x, y: result.y, width: result.cropWidth, height: result.cropHeight };
                    const chosen = { path: result.path, width: result.width, height: result.height, scale: result.scale || 1,
                        rect: area, outputId: outputId, logical: logicalRect(area) };
                    if (pickChoice.length) chosen.engines = pickChoice;
                    pickToken = '';
                    pickLabel = '';
                    pickScale = 1;
                    pickEngines = [];
                    pickChoice = [];
                    close();
                    picked(token, chosen);
                    process.destroy();
                    return;
                }
                if (kind === 'bindings') {
                    bindingsExported(result);
                    process.destroy();
                    return;
                }
                const action = payload.action;
                lastExport = result;
                const saveRequested = action === 'save' || (action === 'copy' && !!services.config.documents.screenshots.autoSave);
                const complete = result.ok && (action !== 'copy' || result.copied)
                    && (!saveRequested || result.saved);
                phase = complete ? 'editing' : 'error';
                error = complete ? '' : (result.copyError || result.saveError || result.error || 'Screenshot export failed.');
                if (complete) {
                    exported(closeAfter);
                    if (closeAfter) close();
                }
            }
            process.destroy();
        });
        process.watchdog.restart();
        process.running = true;
    }

    function cleanupSession(token) {
        if (!token || !helperPath) return;
        const process = requestComponent.createObject(root, { helperPath: helperPath,
            payload: { operation: 'cleanup', session: token } });
        if (!process) return;
        process.completed.connect(function(_result) { process.destroy(); });
        process.watchdog.restart();
        process.running = true;
    }

    function overlayVisibility(output, visible) {
        const next = Object.assign({}, overlayOutputs);
        if (visible) next[output] = true;
        else delete next[output];
        overlayOutputs = next;
        scheduleFocusReturn();
    }

    function scheduleFocusReturn() {
        if (!focusReturnPending || focusReturnScheduled || active || settingsOpen
            || Object.keys(overlayOutputs).length) return;
        const serial = focusReturnSerial;
        const target = focusReturnTarget;
        focusReturnScheduled = true;
        Qt.callLater(function() {
            root.focusReturnScheduled = false;
            if (serial !== root.focusReturnSerial) { root.scheduleFocusReturn(); return; }
            if (!root.focusReturnPending || root.active || root.settingsOpen || Object.keys(root.overlayOutputs).length) return;
            root.focusReturnPending = false;
            root.focusReturnTarget = null;
            if (!target || root.services.safeMode || root.services.preview || !root.services.hyprland) return;
            if (root.services.navigation && root.services.navigation.active) return;
            if (root.services.popups && (root.services.popups.surface || root.services.popups.childSurface)) return;
            const state = root.services.hyprland.overviewSnapshot;
            const client = state && state.kind === 'ready' && state.value.clients
                ? state.value.clients.find(item => item.address === target.address && item.instanceId === target.instanceId) : null;
            if (client) root.services.hyprland.focusWindow(target, true);
        });
    }

    function close() {
        const abandonedPick = pickToken;
        pickToken = '';
        pickLabel = '';
        pickScale = 1;
        pickEngines = [];
        pickChoice = [];
        analysisQueue = [];
        if (analysis && analysis.running) analysis.signal(15);
        if (active) focusReturnPending = !!focusReturnTarget && Object.keys(overlayOutputs).length > 0;
        active = false;
        captureGateDeadline.stop();
        selectionPending = false;
        pendingInitialCrop = null;
        if (!worker) captureTokens.forEach(token => cleanupSession(token));
        if (worker) {
            generation++;
            cancellingProcess = worker;
            if (worker.running) {
                worker.signal(15);
                cancellationKillTimer.restart();
            } else worker.running = false;
        }
        const current = worker;
        if (!current) cancellingProcess = null;
        session = '';
        captureTokens = [];
        frames = ({});
        choosingOutput = false;
        frozenWindowSnapshot = null;
        windowRegions = [];
        phase = 'idle';
        mode = '';
        pendingOutput = '';
        outputId = '';
        imagePath = '';
        imageWidth = 0;
        imageHeight = 0;
        error = '';
        scheduleFocusReturn();
        if (abandonedPick) pickCancelled(abandonedPick);
    }

    function outputRemoved(id) {
        if (!active || outputId !== id) return;
        close();
        outputId = resolveOutput('');
        mode = 'edit';
        active = !!outputId;
        error = 'The selected monitor was disconnected.';
        phase = 'error';
    }

    function fail(message) {
        captureGateDeadline.stop();
        selectionPending = false;
        pendingInitialCrop = null;
        error = message;
        phase = 'error';
    }

    property Connections captureConnections: Connections {
        target: root.services.popups
        function onCaptureReady() { root.onCaptureReady(); }
    }
    property Connections screenConnections: Connections {
        target: Quickshell
        function onScreensChanged() {
            if (root.active && !Quickshell.screens.some(screen => screen.name === root.outputId))
                root.outputRemoved(root.outputId);
        }
    }

    property Timer captureGateDeadline: Timer {
        interval: 10000
        onTriggered: {
            if (!root.active || root.phase !== 'preparing') return;
            root.fail('Timed out waiting for Pentad menus to close.');
        }
    }

    property Timer cancellationKillTimer: Timer {
        interval: 3000
        onTriggered: if (root.cancellingProcess && root.cancellingProcess.running)
            root.cancellingProcess.signal(9)
    }

    property Component requestComponent: Component {
        Process {
            id: request
            required property string helperPath
            required property var payload
            property bool startedOnce: false
            property bool settled: false
            property bool timedOut: false
            signal completed(var result)
            command: ['python3', helperPath]
            stdinEnabled: true
            stdout: StdioCollector { id: response }
            stderr: StdioCollector {}
            onStarted: {
                startedOnce = true;
                write(JSON.stringify(payload) + '\n');
                stdinEnabled = false;
            }
            onRunningChanged: {
                if (!running && !startedOnce && !settled) {
                    settled = true;
                    completed({ ok: false, error: 'Screenshot helper is unavailable.' });
                }
            }
            onExited: function(code) {
                watchdog.stop();
                hardKillTimer.stop();
                if (settled) return;
                settled = true;
                if (timedOut) {
                    completed({ ok: false, error: 'Screenshot operation timed out.' });
                    return;
                }
                var result;
                try { result = JSON.parse(response.text); }
                catch (_error) { result = { ok: false, error: 'Screenshot helper returned invalid data.' }; }
                if (code !== 0 && result.ok) result.ok = false;
                completed(result);
            }
            property Timer watchdog: Timer {
                id: watchdog
                interval: 60000
                onTriggered: {
                    if (request.settled) return;
                    request.timedOut = true;
                    if (request.running) request.signal(15);
                    hardKillTimer.restart();
                }
            }
            property Timer hardKillTimer: Timer {
                interval: 3000
                onTriggered: if (request.running) request.signal(9)
            }
        }
    }

    Component.onDestruction: close()
}
