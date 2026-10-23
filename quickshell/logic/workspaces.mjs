export function workspaceLabel(workspace) {
    if (workspace.game) return workspace.displayName || 'Game';
    if (workspace.special) return String(workspace.name || '').replace(/^special:/, '');
    return String(workspace.name || workspace.id);
}

export function workspaceNumberLabel(workspace) {
    return workspace.special ? '' : String(workspace.id);
}

export function workspaceDescription(workspace) {
    var label = workspaceLabel(workspace);
    var number = workspaceNumberLabel(workspace);
    return number && number !== label ? number + ' · ' + label : label;
}

export function workspacesForOutput(state, outputId) {
    var output = state.outputs.find(function(item) {
        return item.id === String(outputId) || item.name === String(outputId);
    });
    if (!output) return [];
    return state.workspaces.filter(function(item) { return item.monitor === output.name; })
        .slice().sort(function(a, b) {
            return Number(a.special) - Number(b.special) || Number(a.id) - Number(b.id)
                || String(a.name).localeCompare(String(b.name));
        });
}

// `minimum` empty numbered workspaces are offered even before Hyprland creates them (layout.workspaceCount).
export function workspaceChoicesForOutput(state, outputId, minimum) {
    var count = Number.isInteger(minimum) ? Math.max(1, Math.min(8, minimum)) : 5;
    var output = state.outputs.find(function(item) {
        return item.id === String(outputId) || item.name === String(outputId);
    });
    if (!output) return [];
    var choices = workspacesForOutput(state, outputId).map(function(item) {
        return Object.assign({}, item, { occupied: item.occupied === undefined ? true : !!item.occupied });
    });
    var blocked = new Set(state.workspaces.map(function(item) { return String(item.id); }));
    var used = new Set(choices.map(function(item) { return String(item.id); }));
    for (var id = 1; id <= count; id++) {
        var key = String(id);
        if (blocked.has(key) || used.has(key)) continue;
        choices.push({ id: key, name: key, monitor: output.name, special: false,
            active: key === String(output.activeWorkspaceId), occupied: false });
        used.add(key);
    }
    return choices.sort(function(a, b) {
        return Number(a.special) - Number(b.special) || Number(a.id) - Number(b.id);
    });
}

export function representativeWorkspaceApps(state, outputId) {
    if (!state || !Array.isArray(state.outputs) || !Array.isArray(state.workspaces)) return [];
    var output = state.outputs.find(function(item) {
        return item.id === String(outputId) || item.name === String(outputId);
    });
    if (!output) return [];
    return workspacesForOutput(state, outputId).reduce(function(result, workspace) {
        var apps = (Array.isArray(workspace.apps) ? workspace.apps : [])
            .filter(function(app) { return app && app.pinned !== true; })
            .slice()
            .sort(function(a, b) { return Number(b.width) * Number(b.height) - Number(a.width) * Number(a.height); });
        if (apps.length) result.push({
            workspaceId: workspace.id,
            appId: String(apps[0].appId || ""),
            appClass: String(apps[0].appClass || ""),
        });
        return result;
    }, []);
}

function appToken(value) {
    return String(value || "").toLocaleLowerCase().replace(/\.desktop$/, "").replace(/_/g, "-").replace(/[^a-z0-9]+/g, "");
}

function appInitials(value) {
    return String(value || "").toLocaleLowerCase().split(/[^a-z0-9]+/).filter(Boolean)
        .map(function(part) { return part[0]; }).join("");
}

export function matchWorkspaceDesktopEntry(app, entries) {
    if (!app || !Array.isArray(entries)) return null;
    var visible = entries.filter(function(entry) { return entry && !entry.noDisplay; });
    var appId = appToken(app.appId);
    var appClass = appToken(app.appClass);
    var match = visible.find(function(entry) { return appId && appToken(entry.id) === appId; });
    if (match) return match;
    match = visible.find(function(entry) {
        var command = Array.isArray(entry.command) ? entry.command[0] : "";
        return appClass && (appToken(entry.id) === appClass || appToken(command) === appClass);
    });
    if (match) return match;
    match = visible.find(function(entry) { return appClass && appToken(entry.startupClass) === appClass; });
    if (match) return match;
    return visible.find(function(entry) {
        var name = String(entry.name || "");
        return appClass && (appToken(name) === appClass || appInitials(name) === appClass);
    }) || null;
}

export function workspaceChoiceAtSlot(state, outputId, slot) {
    if (!Number.isInteger(slot) || slot < 1 || slot > 9) return undefined;
    var id = String(slot);
    var output = state.outputs.find(function(item) {
        return item.id === String(outputId) || item.name === String(outputId);
    });
    if (!output) return undefined;
    var choices = workspaceChoicesForOutput(state, outputId);
    var choice = choices.find(function(item) { return String(item.id) === id; });
    if (choice) return choice;
    var existing = state.workspaces.find(function(item) { return String(item.id) === id; });
    if (existing) return existing;
    return { id: id, name: id, monitor: output.name, special: false,
        active: id === String(output.activeWorkspaceId), occupied: false };
}
