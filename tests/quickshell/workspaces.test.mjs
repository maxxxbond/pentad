import assert from 'node:assert/strict';
import test from 'node:test';
import {
    workspaceChoiceAtSlot,
    workspaceChoicesForOutput,
    workspaceDescription,
    workspaceLabel,
    workspaceNumberLabel,
    workspacesForOutput,
    representativeWorkspaceApps,
    matchWorkspaceDesktopEntry,
} from '../../quickshell/logic/workspaces.mjs';

const state = {
    outputs: [
        { id: '0', name: 'DP-1', activeWorkspaceId: '1' },
        { id: '1', name: 'HDMI-A-1', activeWorkspaceId: '2' },
    ],
    workspaces: [
        { id: '1', name: '1', monitor: 'DP-1', special: false, active: true },
        { id: '2', name: '2', monitor: 'HDMI-A-1', special: false, active: true },
        { id: 'special:scratch', name: 'special:scratch', monitor: 'DP-1', special: true, active: false },
        { id: 'special:music', name: 'special:music', monitor: 'DP-1', special: true, active: false },
        { id: '8', name: '8', monitor: 'DP-1', special: false, active: false },
    ],
};

test('workspace choices keep occupied IDs local, share globally free 1–5, and preserve specials', () => {
    const first = workspaceChoicesForOutput(state, '0');
    const second = workspaceChoicesForOutput(state, 'HDMI-A-1');
    assert.deepEqual(first.map((item) => item.id), ['1', '3', '4', '5', '8', 'special:music', 'special:scratch']);
    assert.deepEqual(second.map((item) => item.id), ['2', '3', '4', '5']);
    // layout.workspaceCount changes how many empty numbered workspaces are offered; occupied ones stay.
    assert.deepEqual(workspaceChoicesForOutput(state, 'HDMI-A-1', 3).map((item) => item.id), ['2', '3']);
    assert.deepEqual(workspaceChoicesForOutput(state, 'HDMI-A-1', 7).map((item) => item.id), ['2', '3', '4', '5', '6', '7']);
    assert.deepEqual(workspaceChoicesForOutput(state, '0', 1).map((item) => item.id), ['1', '8', 'special:music', 'special:scratch']);
    assert.equal(first.find((item) => item.id === '1').occupied, true);
    assert.equal(first.find((item) => item.id === '3').occupied, false);
    assert.deepEqual(workspacesForOutput(state, 'DP-1').map((item) => item.id), ['1', '8', 'special:music', 'special:scratch']);
    assert.equal(workspaceChoiceAtSlot(state, 'DP-1', 2).monitor, 'HDMI-A-1');
    assert.equal(workspaceChoiceAtSlot(state, 'DP-1', 9).id, '9');
    assert.equal(workspaceChoiceAtSlot(state, 'missing', 1), undefined);
});

test('labels hide special ordinals and expose their name', () => {
    const special = state.workspaces[2];
    assert.equal(workspaceLabel(special), 'scratch');
    assert.equal(workspaceNumberLabel(special), '');
    assert.equal(workspaceLabel({ id: '9000', name: '9000', game: true, displayName: 'Game X' }), 'Game X');
    assert.equal(workspaceDescription(special), 'scratch');
    assert.equal(workspaceDescription(state.workspaces[0]), '1');
    assert.equal(workspaceDescription({ id: 4, name: 'Code' }), '4 · Code');
});

test('workspace choices preserve real empty-workspace state', () => {
    const withEmpty = {
        outputs: state.outputs,
        workspaces: [{ ...state.workspaces[0], occupied: false }],
    };
    assert.equal(workspaceChoicesForOutput(withEmpty, 'DP-1')[0].occupied, false);
});

test('selects the largest non-pinned app per workspace on the requested output', () => {
    const withApps = {
        outputs: state.outputs,
        workspaces: [
            { ...state.workspaces[0], apps: [
                { appId: 'small.desktop', appClass: 'Small', width: 500, height: 400 },
                { appId: 'pinned.desktop', appClass: 'Pinned', pinned: true, width: 2000, height: 1000 },
                { appId: 'large.desktop', appClass: 'Large', width: 1200, height: 800 },
            ] },
            { ...state.workspaces[1], apps: [{ appId: 'other.desktop', appClass: 'Other' }] },
        ],
    };
    assert.deepEqual(representativeWorkspaceApps(withApps, 'DP-1'), [
        { workspaceId: '1', appId: 'large.desktop', appClass: 'Large' },
    ]);
});

test('matches native desktop entries by app ID, class and name initials in priority order', () => {
    const entries = [
        { id: 'Browser.desktop', startupClass: 'Browser', name: 'Web Browser', icon: 'web', command: ['/usr/bin/browser'] },
        { id: 'org.example.Editor.desktop', startupClass: 'Editor', name: 'Text Editor', icon: 'editor', command: ['/usr/bin/editor'] },
        { id: 'hidden.desktop', name: 'Hidden App', noDisplay: true },
    ];
    assert.equal(matchWorkspaceDesktopEntry({ appId: 'org.example.editor', appClass: 'Browser' }, entries).icon, 'editor');
    assert.equal(matchWorkspaceDesktopEntry({ appId: '', appClass: 'Browser' }, entries).icon, 'web');
    assert.equal(matchWorkspaceDesktopEntry({ appId: '', appClass: 'Firefox' }, [
        { id: 'org.mozilla.firefox.desktop', startupClass: 'Firefox', name: 'Firefox Web Browser', icon: 'firefox' },
    ]).icon, 'firefox');
    assert.equal(matchWorkspaceDesktopEntry({ appId: '', appClass: 'TB' }, [
        { id: 'unrelated.desktop', name: 'Text Browser', icon: 'tb' },
    ]).icon, 'tb');
    assert.equal(matchWorkspaceDesktopEntry({ appId: 'hidden', appClass: '' }, entries), null);
});
