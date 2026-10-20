import { isRecognizedGameClass } from './game-identification.mjs';

export function overviewWindowIds(clients) {
    return [...new Set(clients.map(client => client.instanceId).filter(id => typeof id === 'string' && id))];
}

export function workspaceGame(workspace, clients) {
    const game = (clients || []).find(client => !client.pinned
        && (isRecognizedGameClass(client.appClass) || isRecognizedGameClass(client.appId)));
    if (!game && !workspace?.game) return null;
    return { title: String(game?.title || workspace?.displayName || game?.appClass || 'Game'),
        instanceId: game?.instanceId || '' };
}

export function overviewWorkspaceIds(pageIds, workspaces, clients) {
    const ids = pageIds.map(String);
    for (const workspace of workspaces) {
        const id = String(workspace.id);
        const windows = clients.filter(client => String(client.workspaceId) === id);
        if ((!/^[1-9]\d*$/.test(id) || workspaceGame(workspace, windows)) && !ids.includes(id)) ids.push(id);
    }
    return ids;
}

export function overviewCaptureIds(clients, sceneId, workspaceIds, selectedId, dragId, limit = 20) {
    const candidates = clients.filter(client => !client.pinned && client.instanceId);
    const result = [];
    const add = client => {
        if (client && result.length < limit && !result.includes(client.instanceId)) result.push(client.instanceId);
    };
    add(candidates.find(client => client.instanceId === dragId));
    add(candidates.find(client => client.instanceId === selectedId));
    for (const id of workspaceIds) add(candidates.find(client => String(client.workspaceId) === String(id)));
    for (const client of candidates) if (String(client.workspaceId) === String(sceneId)) add(client);
    for (const client of candidates) if (workspaceIds.includes(String(client.workspaceId))) add(client);
    return result;
}

export function retainCaptureIds(requested, retained, alive, limit = 20) {
    return [...new Set(requested.concat(retained))].filter(id => alive.includes(id)).slice(0, limit);
}
