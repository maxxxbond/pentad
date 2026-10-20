import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';
import { nativeGeometryEvent } from '../../quickshell/logic/overview.mjs';

test('window moves and retiles refresh native geometry; focus churn does not', () => {
    for (const name of ['movewindow', 'movewindowv2', 'openwindow', 'closewindow', 'changefloatingmode', 'fullscreen'])
        assert.equal(nativeGeometryEvent(name), true, name);
    for (const name of ['activewindow', 'activewindowv2', 'workspace', 'windowtitle', '', undefined])
        assert.equal(nativeGeometryEvent(name), false, String(name));
});

test('a confirmed move selects the moved window so the overview shows where it landed', () => {
    const service = readFileSync(new URL('../../quickshell/services/WindowNavigation.qml', import.meta.url), 'utf8');
    const method = service.match(/    function finishCommand\([^\n]*\) \{.*?^    \}/ms)[0];
    const moved = { address: '0x2', instanceId: 'two', workspaceId: '6' };
    const p = vm.createContext({ mode: 'overview', generation: 3, error: '', selectedRef: null, selectedWorkspaceId: '1',
        moveState: { kind: 'moving' },
        _pendingMoves: { 'move-1': { ref: { address: '0x2', instanceId: 'two' }, destinationId: '6', generation: 3 },
            'move-2': { ref: { address: '0x2', instanceId: 'two' }, destinationId: '7', generation: 3 } },
        clientFor(ref) { return ref?.instanceId === 'two' ? moved : null; },
        refFor(client) { return { address: client.address, instanceId: client.instanceId }; },
        syncSelected() { p.selectedWindow = p.clientFor(p.selectedRef); },
    });
    vm.runInContext(method, p, { timeout: 1000 });
    p.finishCommand('move-1', { ok: true });
    assert.equal(p.selectedWindow, moved);
    assert.equal(p.selectedWorkspaceId, '');
    assert.equal(p.moveState.kind, 'moved');
    assert.equal(p.moveState.destinationId, '6');
    p.finishCommand('move-2', { ok: false, reason: 'unavailable' });
    assert.equal(p.moveState.kind, 'error');
    assert.equal(p.error, 'unavailable');
});
