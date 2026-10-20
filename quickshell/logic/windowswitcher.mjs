export function instanceId(client) {
    return typeof client.instanceId === 'string' ? client.instanceId : client.address;
}

export function applicationId(client) {
    return client.appId?.trim() || (client.appClass || '').trim().toLocaleLowerCase();
}

function inScope(client, snapshot, scope) {
    if (scope === 'all') return true;
    const output = snapshot.desktop.outputs.find(item => item.id === snapshot.desktop.focusedOutputId);
    if (client.pinned) return client.monitorId === output?.name;
    const activeId = output?.activeWorkspaceId;
    const workspace = snapshot.desktop.workspaces.find(item => item.id === activeId && !item.special);
    return client.workspaceId === (workspace?.id ?? activeId);
}

function eligibleClient(client, snapshot) {
    if (!client.mapped || (client.hidden && !client.pinned)) return false;
    if (client.pinned) return true;
    const workspace = snapshot.desktop.workspaces.find(item => String(item.id) === String(client.workspaceId));
    const special = workspace ? workspace.special
        : String(client.workspaceId).startsWith('special:') || Number(client.workspaceId) < 0;
    if (!special) return true;
    if (!workspace) return false;
    return workspace.active === true || snapshot.desktop.outputs.some(output =>
        String(output.activeWorkspaceId) === String(workspace.id));
}

export function switcherCandidates({ snapshot, mru, scope, mode, anchor }) {
    const byInstance = new Map(snapshot.clients.map(client => [instanceId(client), client]));
    const seen = new Set();
    const anchorApp = anchor ? applicationId(anchor) : '';
    const candidates = [];
    for (const id of [...mru, ...snapshot.clients.map(instanceId)]) {
        if (seen.has(id)) continue;
        seen.add(id);
        const client = byInstance.get(id);
        if (!client || !eligibleClient(client, snapshot)) continue;
        if (!inScope(client, snapshot, scope)) continue;
        if (mode === 'application' && (!anchorApp || applicationId(client) !== anchorApp)) continue;
        candidates.push(client);
    }
    return candidates;
}

export function beginSwitcherSession(options) {
    const anchor = options.snapshot.clients.find(client => client.address ===
        (options.anchorAddress ?? options.snapshot.activeAddress)) ?? null;
    const mode = options.mode ?? 'all';
    const scope = options.scope ?? 'all';
    const allCandidates = switcherCandidates({ snapshot: options.snapshot, mru: options.mru, scope, mode: 'all', anchor });
    const anchorApp = anchor ? applicationId(anchor) : '';
    const candidates = mode === 'application'
        ? allCandidates.filter(client => anchorApp && applicationId(client) === anchorApp)
        : allCandidates;
    const direction = options.direction ?? 1;
    let selectedIndex = anchor ? candidates.findIndex(client => instanceId(client) === instanceId(anchor)) : -1;
    if (selectedIndex < 0 && candidates.length) selectedIndex = direction === 1 ? 0 : candidates.length - 1;
    else if (options.advance !== false && candidates.length)
        selectedIndex = (selectedIndex + direction + candidates.length) % candidates.length;
    return {
        id: options.id, mode, scope,
        anchor: anchor ? { address: anchor.address, instanceId: instanceId(anchor) } : null,
        anchorApp, allCandidates, candidates,
        selectedInstanceId: selectedIndex < 0 ? null : instanceId(candidates[selectedIndex]), direction,
    };
}

export function changeSwitcherMode(session, mode) {
    if (mode !== 'all' && mode !== 'application') return session;
    if (session.mode === mode) return session;
    const allCandidates = session.allCandidates || session.candidates;
    const anchorApp = session.anchorApp || '';
    const candidates = mode === 'application'
        ? allCandidates.filter(client => anchorApp && applicationId(client) === anchorApp)
        : allCandidates;
    let selected = session.selectedInstanceId;
    if (!candidates.some(client => instanceId(client) === selected)) {
        selected = candidates.some(client => instanceId(client) === session.anchor?.instanceId)
            ? session.anchor.instanceId : (candidates[0] ? instanceId(candidates[0]) : null);
    }
    return Object.assign({}, session, { mode, candidates, selectedInstanceId: selected });
}

export function stepSwitcherSession(session, direction) {
    const candidates = session.candidates;
    if (!candidates.length) return Object.assign({}, session, { selectedInstanceId: null, direction });
    const index = candidates.findIndex(client => instanceId(client) === session.selectedInstanceId);
    const start = index < 0 ? (direction === 1 ? -1 : 0) : index;
    const selectedIndex = (start + direction + candidates.length) % candidates.length;
    return Object.assign({}, session, { selectedInstanceId: instanceId(candidates[selectedIndex]), direction });
}

export function reconcileSwitcherSession(session, snapshot) {
    const live = new Map(snapshot.clients.map(client => [instanceId(client), client]));
    const allCandidates = [];
    for (const client of session.allCandidates || session.candidates) {
        const next = live.get(instanceId(client));
        if (next && eligibleClient(next, snapshot)) allCandidates.push(next);
    }
    const candidates = session.mode === 'application'
        ? allCandidates.filter(client => session.anchorApp && applicationId(client) === session.anchorApp)
        : allCandidates;
    let selected = session.selectedInstanceId;
    if (!candidates.some(client => instanceId(client) === selected)) {
        const oldIndex = Math.max(0, session.candidates.findIndex(client => instanceId(client) === selected));
        const next = candidates.length ? candidates[oldIndex % candidates.length] : undefined;
        selected = next ? instanceId(next) : null;
    }
    return Object.assign({}, session, { allCandidates, candidates, selectedInstanceId: selected });
}

export function selectedWindow(session) {
    return session.candidates.find(client => instanceId(client) === session.selectedInstanceId) ?? null;
}
