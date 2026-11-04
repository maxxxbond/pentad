import QtQuick
import QtQml
import Quickshell
import Quickshell.Io
import "../services"
import '../logic/workspace-super.mjs' as WorkspaceSuper
import '../logic/workspaces.mjs' as Workspaces

QtObject {
    id: bridge
    required property Services services
    property IpcHandler handler: IpcHandler {
        target: "pentad"
        function request(command: string, payload: string): string {
            return bridge.request(command, payload);
        }
    }
    function request(command: string, payload: string): string {
        var data;
        try { data = JSON.parse(payload); }
        catch (error) { return JSON.stringify({ ok: false, reason: "invalid-payload" }); }
        if (!data || typeof data !== "object" || Array.isArray(data))
            return JSON.stringify({ ok: false, reason: "invalid-payload" });
        if (command === "ping")
            return JSON.stringify({ ok: true, apiVersion: services.apiVersion,
                safeMode: services.safeMode, preview: services.preview });
        if (command === 'screenshot') {
            if (data.mode === 'settings') return JSON.stringify({ ok: services.screenshot.openSettings() });
            if (!['edit', 'copy', 'window', 'monitor'].includes(data.mode)
                || (data.outputId !== undefined && typeof data.outputId !== 'string'))
                return JSON.stringify({ ok: false, reason: 'invalid-payload' });
            const output = selectedOutput(data.outputId);
            if (!output) return JSON.stringify({ ok: false, reason: 'output-unavailable' });
            const accepted = services.screenshot.open(data.mode, output);
            return JSON.stringify({ ok: accepted, reason: accepted ? 'accepted' : 'unavailable',
                message: services.screenshot.error });
        }
        if (command === 'wallpaper') {
            if (data.outputId !== undefined && typeof data.outputId !== 'string')
                return JSON.stringify({ ok: false, reason: 'invalid-payload' });
            const target = data.outputId || '';
            let requestId = '';
            if (data.action === 'set' && typeof data.path === 'string') requestId = services.wallpaper.set(data.path, target);
            else if (['random', 'next', 'previous'].includes(data.action)) requestId = services.wallpaper.step(data.action, target);
            else return JSON.stringify({ ok: false, reason: 'invalid-payload' });
            return JSON.stringify(requestId ? { ok: true, reason: 'accepted' }
                : { ok: false, reason: 'unavailable', message: services.wallpaper.error });
        }
        if (command === 'settings') {
            if (data.page !== undefined && typeof data.page !== 'string')
                return JSON.stringify({ ok: false, reason: 'invalid-payload' });
            return JSON.stringify({ ok: services.settings.openPage(data.page) });
        }
        if (command === 'stash') {
            const action = data.action === undefined ? 'toggle' : data.action;
            if (!['toggle', 'open', 'close'].includes(action))
                return JSON.stringify({ ok: false, reason: 'invalid-payload' });
            if (action === 'open') services.stash.show();
            else if (action === 'close') services.stash.hide();
            else services.stash.toggle();
            return JSON.stringify({ ok: true });
        }
        if (command === 'cheatsheet') {
            const sheetAction = data.action === undefined ? 'toggle' : data.action;
            if (!['toggle', 'open', 'close'].includes(sheetAction))
                return JSON.stringify({ ok: false, reason: 'invalid-payload' });
            if (sheetAction === 'open') services.cheatsheet.show();
            else if (sheetAction === 'close') services.cheatsheet.hide();
            else services.cheatsheet.toggle();
            return JSON.stringify({ ok: true, open: services.cheatsheet.open });
        }
        if (command === 'workspace-super') {
            var held = WorkspaceSuper.handleWorkspaceSuperRequest([command, data.key, data.action]);
            if (held.ok) services.navigation.modifier(data.key, data.action === 'press');
            return JSON.stringify(held);
        }
        if (command === 'overview') {
            if (!['open', 'close', 'toggle'].includes(data.action))
                return JSON.stringify({ ok: false, reason: 'invalid-payload' });
            if (data.action === 'close') services.navigation.cancel();
            else if (data.action === 'toggle' || services.navigation.mode !== 'overview') services.navigation.toggleOverview();
            return JSON.stringify({ ok: true, active: services.navigation.active });
        }
        if (command === 'window-switcher') {
            if (!['all', 'application'].includes(data.mode)
                    || !['next', 'previous', 'commit', 'cancel'].includes(data.action))
                return JSON.stringify({ ok: false, reason: 'invalid-payload' });
            if (data.action === 'cancel') services.navigation.cancel();
            else if (data.action === 'commit') services.navigation.commit();
            else services.navigation.beginSwitcher(data.mode, data.action === 'previous' ? -1 : 1);
            return JSON.stringify({ ok: true, active: services.navigation.active });
        }
        if (command === 'panel') {
            if (!['left', 'right', 'activity'].includes(data.surface) || !['open', 'close', 'toggle'].includes(data.action))
                return JSON.stringify({ ok: false, reason: 'invalid-payload' });
            var output = selectedOutput(data.outputId);
            if (!output) return JSON.stringify({ ok: false, reason: 'output-unavailable' });
            if (data.action === 'close') services.popups.close();
            else services.popups[data.action](data.surface, output);
            return JSON.stringify({ ok: true });
        }
        if (command === 'workspace-slot') {
            if (!Number.isInteger(data.slot) || data.slot < 1 || data.slot > 9)
                return JSON.stringify({ ok: false, reason: 'invalid-payload' });
            var state = services.hyprland.state;
            if (state.kind !== 'ready') return JSON.stringify({ ok: false, reason: 'unavailable' });
            if (services.preview || services.safeMode) return JSON.stringify({ ok: false, reason: 'denied' });
            var choice = Workspaces.workspaceChoiceAtSlot(state.value, selectedOutput(data.outputId), data.slot);
            if (!choice) return JSON.stringify({ ok: false, reason: 'output-unavailable' });
            return JSON.stringify({ ok: true, accepted: true, requestId: services.hyprland.focusWorkspace(choice.id) });
        }
        return JSON.stringify({ ok: false, reason: "unsupported", command: command });
    }
    function selectedOutput(requested) {
        var state = services.hyprland.state;
        var outputs = state.kind === 'ready' ? state.value.outputs : [];
        if (requested) {
            var match = outputs.find(function(output) { return output.id === requested || output.name === requested });
            var screen = Quickshell.screens.find(function(screen) { return screen.name === requested || (match && screen.name === match.name) });
            return screen ? screen.name : '';
        }
        var focused = outputs.find(function(output) { return state.kind === 'ready' && output.id === state.value.focusedOutputId });
        return focused && Quickshell.screens.some(function(screen) { return screen.name === focused.name })
            ? focused.name : Quickshell.screens.length ? Quickshell.screens[0].name : '';
    }
}
