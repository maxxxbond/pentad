import { isRecognizedGameClass } from './game-identification.mjs';
export { isRecognizedGameClass };
const positiveWorkspaceId = /^[1-9]\d{0,9}$/;
const addressPattern = /^0x[\da-f]{1,16}$/i;

function clientIdentity(client) {
    return client.instanceId === undefined || client.instanceId === null ? client.address : client.instanceId;
}

export function createGameWorkspaceIpcPort(dispatch, getMode) {
    return {
        async moveWindow(address, workspaceId, monitorName, follow) {
            if (!addressPattern.test(address) || !positiveWorkspaceId.test(workspaceId)
                    || Number(workspaceId) > 2147483647 || !/^[\w.-]{1,128}$/.test(monitorName)) return false;
            const selector = String(workspaceId);
            const window = 'address:' + address;
            const mode = await getMode();
            const move = mode === 'lua'
                ? 'hl.dsp.window.move({ window = ' + JSON.stringify(window) + ', workspace = ' + JSON.stringify(selector) + ', follow = ' + (follow ? 'true' : 'false') + ' })'
                : (follow ? 'movetoworkspace ' : 'movetoworkspacesilent ') + selector + ',' + window;
            const legacyMove = (follow ? 'movetoworkspace ' : 'movetoworkspacesilent ') + selector + ',' + window;
            if (!(await dispatch(move, legacyMove))) return false;
            const placeLua = 'hl.dsp.workspace.move({ workspace = ' + JSON.stringify(selector) + ', monitor = ' + JSON.stringify(monitorName) + ' })';
            const placeLegacy = 'moveworkspacetomonitor ' + selector + ' ' + monitorName;
            await dispatch(placeLua, placeLegacy);
            return true;
        },
        async activateWorkspace(workspaceId, monitorName) {
            if (!positiveWorkspaceId.test(workspaceId) || Number(workspaceId) > 2147483647
                    || !/^[\w.-]{1,128}$/.test(monitorName)) return false;
            const focusMonitor = 'hl.dsp.focus({ monitor = ' + JSON.stringify(monitorName) + ' })';
            if (!(await dispatch(focusMonitor, 'focusmonitor ' + monitorName))) return false;
            return dispatch(
                'hl.dsp.focus({ workspace = ' + JSON.stringify(workspaceId) + ', on_current_monitor = true })',
                'focusworkspaceoncurrentmonitor ' + workspaceId,
            );
        },
    };
}

export function createGameWorkspaceCoordinator(port, onFullscreenOutputs) {
    const routed = new Map();
    const pending = new Set();
    const manuallyMoved = new Set();
    const listeners = new Set();
    let nextWorkspaceId = 9000;
    let lastOutputs = new Set();
    let disposed = false;

    function publish(outputs) {
        lastOutputs = new Set(outputs);
        onFullscreenOutputs(lastOutputs);
        for (const listener of listeners) listener(lastOutputs);
    }

    async function route(client, monitorName, takenIds, follow) {
        const identity = clientIdentity(client);
        pending.add(identity);
        let workspaceId = null;
        for (let attempts = 0; attempts < 10000; attempts++) {
            const candidate = String(nextWorkspaceId++);
            if (!takenIds.has(candidate)) { workspaceId = candidate; break; }
        }
        if (!workspaceId || !/^[\w.-]{1,128}$/.test(monitorName)) {
            pending.delete(identity);
            return;
        }
        try {
            if (!(await port.moveWindow(client.address, workspaceId, monitorName, follow)) || disposed) return;
            routed.set(identity, {
                workspaceId, sourceWorkspaceId: client.workspaceId, monitorName, wasActive: follow,
            });
        } catch (_error) {
        } finally {
            pending.delete(identity);
        }
    }

    async function restore(game, snapshot, currentWorkspaceId) {
        if (disposed || !game.wasActive || currentWorkspaceId !== game.workspaceId
                || !positiveWorkspaceId.test(game.sourceWorkspaceId)) return;
        const outputs = snapshot.desktop.outputs;
        let focusedOutput = null;
        for (const output of outputs) {
            if (output.id === snapshot.desktop.focusedOutputId) { focusedOutput = output; break; }
        }
        if (!focusedOutput || focusedOutput.name !== game.monitorName) return;
        try { await port.activateWorkspace(game.sourceWorkspaceId, game.monitorName); }
        catch (_error) {  }
    }

    function update(snapshot) {
        if (disposed) return;
        const outputs = new Set();
        const activeWorkspaceByMonitor = new Map();
        for (const output of snapshot.desktop.outputs) activeWorkspaceByMonitor.set(output.name, output.activeWorkspaceId);
        for (const output of snapshot.desktop.outputs) {
            const activeId = activeWorkspaceByMonitor.get(output.name);
            for (const client of snapshot.clients) {
                if (client.monitorId === output.name && client.workspaceId === activeId
                        && client.fullscreen && isRecognizedGameClass(client.appClass)) {
                    outputs.add(output.name);
                    break;
                }
            }
        }
        publish(outputs);

        const clientsByIdentity = new Map();
        for (const client of snapshot.clients) clientsByIdentity.set(clientIdentity(client), client);
        for (const [identity, game] of routed) {
            const client = clientsByIdentity.get(identity);
            if (!client) {
                routed.delete(identity);
                manuallyMoved.delete(identity);
                void restore(game, snapshot, activeWorkspaceByMonitor.get(game.monitorName));
                continue;
            }
            game.wasActive = snapshot.activeAddress === client.address;
            if (client.workspaceId !== game.workspaceId) {
                routed.delete(identity);
                manuallyMoved.add(identity);
            }
        }
        for (const identity of manuallyMoved) if (!clientsByIdentity.has(identity)) manuallyMoved.delete(identity);

        const occupied = new Set();
        for (const workspace of snapshot.desktop.workspaces) occupied.add(workspace.id);
        for (const client of snapshot.clients) {
            const identity = clientIdentity(client);
            if (!client.fullscreen || !isRecognizedGameClass(client.appClass) || routed.has(identity)
                    || pending.has(identity) || manuallyMoved.has(identity)) continue;
            void route(client, client.monitorId, occupied, snapshot.activeAddress === client.address);
        }
    }

    return {
        update,
        readFullscreenOutputs() { return new Set(lastOutputs); },
        subscribe(listener) {
            if (disposed) return function() {};
            listeners.add(listener);
            listener(new Set(lastOutputs));
            return function() { listeners.delete(listener); };
        },
        dispose() {
            disposed = true;
            routed.clear(); pending.clear(); manuallyMoved.clear(); listeners.clear();
        },
    };
}
