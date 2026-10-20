const addressPattern = /^0x[\da-f]{1,16}$/i;
const positiveWorkspaceId = /^[1-9]\d{0,9}$/;
const geometryEvents = new Set(['openwindow', 'closewindow', 'movewindow', 'movewindowv2',
    'changefloatingmode', 'fullscreen', 'moveworkspace', 'moveworkspacev2', 'pin',
    'togglegroup', 'moveintogroup', 'moveoutofgroup', 'monitoradded', 'monitoraddedv2',
    'monitorremoved', 'monitorremovedv2']);

// Hyprland keeps live workspace bindings but not window geometry; these events retile or relocate windows.
export function nativeGeometryEvent(name) {
    return geometryEvents.has(String(name || ''));
}

export function createOverviewIdentityTracker(mruLimit) {
    const limit = Number.isInteger(mruLimit) && mruLimit > 0 ? mruLimit : 128;
    let entries = [];
    let serial = 0;
    let mru = [];
    return {
        sync(objects, addresses) {
            const nextEntries = [];
            const instanceIds = [];
            for (let i = 0; i < objects.length; i++) {
                const object = objects[i];
                let entry = entries.find(item => item.object === object);
                if (!entry) entry = { object, id: 'quickshell:' + (++serial) + ':' + addresses[i], address: addresses[i] };
                nextEntries.push(entry);
                instanceIds.push(entry.id);
            }
            entries = nextEntries;
            const liveIds = new Set(instanceIds);
            mru = mru.filter(id => liveIds.has(id));
            return { instanceIds, mru: mru.slice() };
        },
        activate(address) {
            let activeId = null;
            for (const entry of entries) {
                if (entry.address === address) { activeId = entry.id; break; }
            }
            if (activeId) {
                mru = mru.filter(id => id !== activeId);
                mru.unshift(activeId);
            }
            if (mru.length > limit) mru.length = limit;
            return mru.slice();
        },
        clear() { entries = []; mru = []; },
    };
}

function text(value) {
    return typeof value === 'string' ? value : '';
}

function dimension(value) {
    return typeof value === 'number' && Number.isFinite(value) && value > 0
        ? Math.min(32768, Math.trunc(value)) : 0;
}

function coordinate(value) {
    return typeof value === 'number' && Number.isFinite(value) ? value : 0;
}

export function nativeSequenceToArray(value) {
    if (Array.isArray(value)) return value.slice();
    if (!value || !Number.isSafeInteger(value.length) || value.length < 0 || value.length > 4096)
        return [];
    const result = [];
    for (let i = 0; i < value.length; i++) result.push(value[i]);
    return result;
}

function strings(value) {
    if (!Array.isArray(value)) return [];
    return value.filter(item => typeof item === 'string');
}

export function normalizeOverviewClients(raw, outputs, labels) {
    outputs = Array.isArray(outputs) ? outputs : [];
    labels = labels || {};
    const fallbackTitle = labels.untitled || 'Untitled';
    if (!Array.isArray(raw)) return [];
    const clients = [];
    const seen = new Set();
    for (const value of raw) {
        if (typeof value !== 'object' || value === null) continue;
        const address = text(value.address);
        if (!addressPattern.test(address) || seen.has(address) || value.mapped === false) continue;
        const row = value;
        const size = Array.isArray(row.size) ? row.size : [];
        const at = Array.isArray(row.at) ? row.at : [];
        const workspaceId = String(row.workspace && row.workspace.id !== undefined && row.workspace.id !== null ? row.workspace.id : '');
        if (!workspaceId) continue;
        let monitorId = '';
        if (typeof row.monitor === 'number') {
            const output = outputs.find(item => item.id === String(row.monitor));
            monitorId = output ? output.name : '';
        } else monitorId = text(row.monitor);
        const isFullscreen = value => value === true || (typeof value === 'number' && value >= 2);
        seen.add(address);
        clients.push({
            address,
            appId: text(row.appId).trim(),
            workspaceId,
            monitorId,
            title: text(row.title).trim() || text(row.class).trim() || fallbackTitle,
            appClass: text(row.class) || text(row.initialClass),
            x: coordinate(at[0]),
            y: coordinate(at[1]),
            width: dimension(size[0]),
            height: dimension(size[1]),
            mapped: row.mapped !== false,
            hidden: row.hidden === true,
            pinned: row.pinned === true,
            floating: row.floating === true,
            fullscreen: isFullscreen(row.fullscreen) || isFullscreen(row.fullscreenClient),
            grouped: strings(row.grouped !== undefined && row.grouped !== null ? row.grouped : row.group),
        });
    }
    return clients;
}

export function captureHandle(address) {
    if (!/^0x[\da-f]{1,8}$/i.test(address)) return null;
    const value = Number.parseInt(address.slice(2), 16);
    return Number.isSafeInteger(value) && value > 0 ? value : null;
}

export function workspaceSelector(workspace) {
    const id = String(workspace.id);
    const name = String(workspace.name);
    if (workspace.special) {
        const specialName = name.replace(/^special:/, '');
        return specialName && !/[\0\r\n,]/.test(specialName) ? 'special:' + specialName : null;
    }
    if (positiveWorkspaceId.test(id) && Number(id) <= 2147483647) return id;
    const trimmed = name.trim();
    return trimmed && !/[\0\r\n,]/.test(trimmed) ? 'name:' + trimmed : null;
}

export function groupOverview(snapshot, labels) {
    labels = labels || {};
    const fallbackOutput = labels.noMonitor || 'No monitor';
    const sorted = snapshot.desktop.workspaces.slice().sort((a, b) => {
        const output = a.monitor.localeCompare(b.monitor);
        if (output) return output;
        if (a.special !== b.special) return Number(a.special) - Number(b.special);
        const an = Number(a.id);
        const bn = Number(b.id);
        if (Number.isFinite(an) && Number.isFinite(bn) && an !== bn) return an - bn;
        return a.name.localeCompare(b.name);
    });
    const grouped = [];
    for (const workspace of sorted) {
        const clients = snapshot.clients.filter(client => client.workspaceId === workspace.id && !client.pinned);
        grouped.push({ outputName: workspace.monitor || fallbackOutput, workspace, clients });
    }
    return grouped;
}

export function canMoveClient(client) {
    return !client.pinned && client.grouped.length === 0;
}

export function findWorkspace(workspaces, id) {
    return workspaces.find(workspace => workspace.id === id);
}

export function confirmOverviewCommand(pending, snapshot, activeWorkspaceId, now) {
    if (!pending || typeof pending !== 'object') return { ok: false, reason: 'unsupported' };
    const clients = snapshot && Array.isArray(snapshot.clients) ? snapshot.clients : [];
    if (pending.kind === 'focus' || pending.kind === 'move') {
        const ref = pending.ref || {};
        const client = clients.find(item => item.address === ref.address
            && item.instanceId === ref.instanceId);
        if (!client) return { ok: false, reason: 'device-removed' };
        if (pending.kind === 'focus' && snapshot.activeAddress === ref.address) return { ok: true };
        if (pending.kind === 'move' && client.workspaceId === pending.destinationId) return { ok: true };
    } else if (pending.kind === 'workspace'
            && String(activeWorkspaceId || '') === String(pending.destinationId)) {
        return { ok: true };
    }
    if (Number.isFinite(pending.deadline) && Number.isFinite(now) && now >= pending.deadline)
        return { ok: false, reason: 'timeout' };
    return null;
}

// Steps that put a moved tiled window at the dropped spot under dwindle: focus the window it lands
// next to, preselect the side, move silently, then give back the destination monitor's workspace
// and the original focus. Null means a plain move (empty or virtual destination, floating window).
export function placementPlan(snapshot, client, destinationId, placement) {
    if (!snapshot || !client || client.floating || !placement || !addressPattern.test(placement.target || '')
            || !['l', 'r', 'u', 'd'].includes(placement.direction))
        return null;
    const desktop = snapshot.desktop || {};
    const workspaces = Array.isArray(desktop.workspaces) ? desktop.workspaces : [];
    const outputs = Array.isArray(desktop.outputs) ? desktop.outputs : [];
    const destination = workspaces.find(item => item.id === String(destinationId));
    const target = (snapshot.clients || []).find(item => item.address === placement.target);
    if (!destination || !target || target.address === client.address || String(target.workspaceId) !== destination.id)
        return null;
    const output = outputs.find(item => item.name === destination.monitor);
    const shownThere = output && output.activeWorkspaceId && output.activeWorkspaceId !== destination.id
        ? output.activeWorkspaceId : '';
    const active = snapshot.activeAddress && snapshot.activeAddress !== client.address ? snapshot.activeAddress : '';
    const focusedOutput = outputs.find(item => item.id === String(desktop.focusedOutputId || ''));
    return {
        target: target.address,
        direction: placement.direction,
        restoreWorkspaceId: shownThere,
        restoreFocusAddress: active,
        restoreFocusWorkspaceId: active ? ''
            : (focusedOutput && focusedOutput.activeWorkspaceId) || String(client.workspaceId || ''),
    };
}
