// Preview-mode desktop and overview snapshots for the Hyprland service.

export function numberOr(value, fallback) {
    const n = Number(value);
    return Number.isFinite(n) ? n : fallback;
}

export function previewStateForScreens(screens) {
    const outputs = [];
    if (screens && typeof screens.length === 'number') {
        for (let i = 0; i < screens.length; i++) {
            const screen = screens[i];
            const name = screen && String(screen.name || '');
            if (!name) continue;
            let scale = numberOr(screen.devicePixelRatio, 1);
            if (!(scale > 0)) scale = 1;
            outputs.push({ id: name, name: name,
                x: numberOr(screen.x, numberOr(screen.virtualX, i * 1920)),
                y: numberOr(screen.y, numberOr(screen.virtualY, 0)),
                width: numberOr(screen.width, 1920), height: numberOr(screen.height, 1080),
                scale: scale, transform: 0, reserved: [0, 0, 0, 0],
                activeWorkspaceId: String(outputs.length * 5 + 1) });
        }
    }
    if (!outputs.length) outputs.push({ id: 'preview', name: 'preview', x: 0, y: 0,
        width: 1920, height: 1080, scale: 1, transform: 0, reserved: [0, 0, 0, 0],
        activeWorkspaceId: '1' });

    const workspaces = [];
    for (let outputIndex = 0; outputIndex < outputs.length; outputIndex++) {
        for (let number = 1; number <= 5; number++) {
            const id = outputIndex * 5 + number;
            workspaces.push({ id: String(id), name: String(id), monitor: outputs[outputIndex].name,
                special: false, active: number === 1, occupied: false, apps: [] });
        }
    }
    return { workspaces: workspaces, outputs: outputs, focusedOutputId: outputs[0].id,
        activeTitle: '', activeClass: '' };
}

export function previewOverviewForScreens(screens) {
    const base = previewStateForScreens(screens);
    const desktop = Object.assign({}, base, { outputs: base.outputs.slice(),
        workspaces: base.workspaces.map(function(workspace) { return Object.assign({}, workspace); }) });
    const clients = [];
    for (let i = 0; i < desktop.outputs.length; i++) {
        const output = desktop.outputs[i];
        const workspaceId = output.activeWorkspaceId;
        const address = '0x' + (4096 + i).toString(16);
        clients.push({ address: address, instanceId: 'preview:' + address,
            appId: 'preview.desktop', workspaceId: workspaceId, monitorId: output.name,
            title: 'Preview window', appClass: 'preview', x: output.x + 48, y: output.y + 48,
            width: 960, height: 600, mapped: true, hidden: false, pinned: false,
            floating: true, fullscreen: false, grouped: [] });
        const workspace = desktop.workspaces.find(function(item) { return item.id === workspaceId; });
        if (workspace) {
            workspace.occupied = true;
            workspace.apps = [{ appId: 'preview.desktop', appClass: 'preview',
                width: 960, height: 600, pinned: false }];
        }
    }
    if (clients.length) {
        desktop.activeTitle = clients[0].title;
        desktop.activeClass = clients[0].appClass;
    }
    return { revision: 1, desktop: desktop, clients: clients,
        activeAddress: clients.length ? clients[0].address : null,
        mru: clients.length ? [clients[0].instanceId] : [] };
}
