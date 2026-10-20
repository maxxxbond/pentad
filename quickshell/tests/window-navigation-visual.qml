import QtQuick
import QtTest
import Quickshell
import qs.theme
import "../services" as Native
import "../features/overview" as Overview
import "../features/windowswitcher" as Switcher

ShellRoot {
    id: root
    property var checks: []
    property int phase: 0
    property bool waiting: false
    property var calls: []
    property var moves: []
    property TestEvent pointer: TestEvent {}
    property QtObject source: QtObject {
        property var overviewSnapshot: ({ kind: 'ready', value: {
            revision: 1, desktop: { focusedOutputId: 'fixture', outputs: [
                { id: 'fixture', name: 'fixture', x: 0, y: 0, width: 1920, height: 1080,
                    reserved: [0, 40, 0, 0], activeWorkspaceId: '1' },
                { id: 'second', name: 'second', x: 1920, y: 0, width: 1080, height: 1920,
                    reserved: [0, 40, 0, 0], activeWorkspaceId: '6' }
            ], workspaces: [
                { id: '1', name: '1', monitor: 'fixture', active: true },
                { id: '2', name: '2', monitor: 'fixture' },
                { id: '6', name: '6', monitor: 'second', active: true },
                { id: 'named:dev', name: 'dev', monitor: 'fixture' }
            ] }, activeAddress: '0xa', mru: ['a:1', 'b:1', 'c:1'], clients: [
                { address: '0xa', instanceId: 'a:1', appClass: 'editor', appId: 'editor',
                    title: 'Редактор — довга українська назва поточного проєкту', workspaceId: '1',
                    monitorId: 'fixture', x: 0, y: 40, width: 960, height: 1040, mapped: true, hidden: false, pinned: false, grouped: [] },
                { address: '0xb', instanceId: 'b:1', appClass: 'browser', appId: 'browser',
                    title: 'Документація', workspaceId: '1', monitorId: 'fixture', x: 960, y: 40,
                    width: 960, height: 1040, mapped: true, hidden: false, pinned: false, grouped: [] },
                { address: '0xc', instanceId: 'c:1', appClass: 'editor', appId: 'editor',
                    title: 'Інший редактор', workspaceId: '6', monitorId: 'second', x: 2000, y: 100,
                    width: 800, height: 600, mapped: true, hidden: false, pinned: false, grouped: [] }
            ]
        } })
        signal commandFinished(string requestId, var result)
        function captureSourceFor(ref) { return null; }
        function focusWindow(ref) { root.calls = root.calls.concat([ref]); return 'focus-' + root.calls.length; }
        function moveWindow(ref, destination) {
            root.moves = root.moves.concat([{ ref: ref, destination: destination }]);
            return 'move-fixture-' + root.moves.length;
        }
        function activateOverviewWorkspace(id) { return 'workspace-fixture'; }
    }
    property QtObject popups: QtObject {
        property string surface: ''
        signal changed()
        function close() { surface = ''; changed(); }
    }
    property QtObject services: QtObject {
        property bool preview: false
        property bool safeMode: false
        property bool workspaceHeld: false
        property var hyprland: root.source
        property var popups: root.popups
        property var config: ({ documents: { interface: { language: 'uk' }, layout: { barHeight: 40 } } })
        function text(uk, en) { return uk; }
    }
    property Native.WindowNavigation navigation: Native.WindowNavigation { services: root.services }
    PanelWindow {
        id: window
        visible: true
        implicitWidth: 1240
        implicitHeight: 900
        color: '#364335'
        Item {
            id: frame
            anchors.fill: parent
            Overview.OverviewWindow {
                id: overview
                x: 24; y: 52; width: parent.width - 48; height: parent.height - 76
                services: root.services; navigation: root.navigation
                visible: root.navigation.mode === 'overview'
            }
            Switcher.WindowSwitcher {
                id: switcher
                x: 24; y: (parent.height - 218) / 2
                width: parent.width - 48; height: 218
                services: root.services; navigation: root.navigation
                visible: root.navigation.mode === 'all' || root.navigation.mode === 'application'
            }
        }
    }
    function check(name, passed, detail) { checks = checks.concat([{ name: name, passed: !!passed, detail: passed ? '' : String(detail || '') }]); }
    function find(item, name) {
        if (item.objectName === name) return item;
        for (let child of item.children || []) { let result = find(child, name); if (result) return result; }
        return null;
    }
    function capture(suffix) {
        waiting = true;
        frame.grabToImage(function(result) {
            check('capture-' + (suffix || 'overview'), result.saveToFile(Quickshell.env('PENTAD_ARTIFACT_PATH') + suffix));
            waiting = false;
            phase++;
        });
    }
    Component.onCompleted: {
        Theme.resolve({ appearance: Quickshell.env('PENTAD_GALLERY_APPEARANCE') || 'dark',
            reducedMotion: Quickshell.env('PENTAD_GALLERY_REDUCED_MOTION') === '1',
            accent: Quickshell.env('PENTAD_GALLERY_ACCENT') || '#869677', fontFamily: 'Geist' });
        navigation.openOverview();
    }
    Timer {
        interval: 120; running: true; repeat: true
        onTriggered: {
            if (root.waiting) return;
            if (root.phase === 0) {
                let first = root.find(overview, 'overview-workspace-1');
                let fifth = root.find(overview, 'overview-workspace-5');
                let sixth = root.find(overview, 'overview-workspace-6');
                let tenth = root.find(overview, 'overview-workspace-10');
                root.check('ten-global-workspace-slots', first && tenth && overview.pageIds.length === 10);
                root.check('wide-five-column-spatial-grid', first && fifth && sixth && overview.layout.columns === 5
                    && first.y === fifth.y && sixth.y > first.y && sixth.x < fifth.x
                    && Math.abs(first.height - sixth.height) < 1,
                    JSON.stringify({ columns: overview.layout.columns, first: first ? [first.x, first.y, first.width, first.height] : null,
                        fifth: fifth ? [fifth.x, fifth.y] : null, sixth: sixth ? [sixth.x, sixth.y, sixth.width, sixth.height] : null }));
                const shapeOf = function(card) {
                    const area = card.workarea;
                    return Math.abs(card.height / card.width - area.height / area.width);
                };
                root.check('cards-keep-their-own-monitor-shape', first && sixth && shapeOf(first) < 0.03 && shapeOf(sixth) < 0.03,
                    JSON.stringify({ first: [first.width, first.height, first.workarea], sixth: [sixth.width, sixth.height, sixth.workarea] }));
                root.check('cross-output-workspace-appears-once', sixth && sixth.workspace.monitor === 'second');
                let grid = root.find(overview, 'overview-grid');
                root.check('grid-stays-inside-the-overview-viewport', grid && grid.x >= 0 && grid.y >= 0
                    && grid.x + grid.width <= overview.width && grid.y + grid.height <= overview.height);
                let firstScreen = root.find(overview, 'overview-workspace-screen-1');
                let sixthScreen = root.find(overview, 'overview-workspace-screen-6');
                root.check('landscape-cell-preserves-output-workarea-aspect', firstScreen
                    && Math.abs(firstScreen.height / firstScreen.width - 1040 / 1920) < 0.01);
                root.check('portrait-workspace-preserves-its-own-output-aspect', sixthScreen
                    && Math.abs(sixthScreen.height / sixthScreen.width - 1880 / 1080) < 0.02
                    && sixthScreen.height <= sixth.height && sixthScreen.width < sixth.width);
                root.check('hyprland-reserved-order-left-top-right-bottom', first && first.workarea.x === 0
                    && first.workarea.y === 40 && first.workarea.height === 1040);
                let editor = root.find(first, 'overview-client-0xa');
                let browser = root.find(first, 'overview-client-0xb');
                root.check('tiled-windows-preserve-distinct-spatial-geometry', editor && browser
                    && editor.x === 0 && browser.x > editor.x
                    && editor.x + editor.width <= browser.x + 1 && editor.width > 20);
                root.navigation.setQuery('Документація');
                root.check('search-selects-matching-window-without-reordering', root.navigation.selectedWindow
                    && root.navigation.selectedWindow.instanceId === 'b:1' && overview.pageIds[0] === '1');
                root.navigation.setQuery('');
                root.capture('');
            } else if (root.phase === 1) {
                root.navigation.cancel(); root.navigation.beginSwitcher('all', 1);
                root.check('switcher-first-chord-selects-previous', root.navigation.selectedWindow.instanceId === 'b:1');
                root.phase++;
            } else if (root.phase === 2) root.capture('.all.png');
            else if (root.phase === 3) {
                root.navigation.beginSwitcher('application', 1);
                root.check('application-switcher-preserves-original-anchor', root.navigation.session.candidates.length === 2
                    && root.navigation.session.candidates.every(function(client) { return client.appClass === 'editor'; }));
                root.phase++;
            } else if (root.phase === 4) root.capture('.application.png');
            else if (root.phase === 5) {
                root.navigation.commit();
                root.check('commit-dispatches-once-and-releases-session', root.calls.length === 1 && !root.navigation.active);
                root.navigation.openOverview();
                root.phase++;
            } else if (root.phase === 6) {
                const hit = root.find(overview, 'overview-hit-a:1');
                root.pointer.mousePress(hit, hit.width / 2, hit.height / 2, Qt.LeftButton, Qt.NoModifier, 0);
                root.pointer.mouseMove(hit, hit.width / 2 + 24, hit.height / 2, 0, Qt.LeftButton, Qt.NoModifier);
                root.phase++;
            } else if (root.phase === 7) {
                const target = root.find(overview, 'overview-workspace-2');
                const point = target.mapToItem(overview, target.width / 2, target.height / 2);
                root.pointer.mouseMove(overview, point.x, point.y, 0, Qt.LeftButton, Qt.NoModifier);
                root.phase++;
            } else if (root.phase === 8) {
                const target = root.find(overview, 'overview-workspace-2');
                root.check('native-drag-reaches-other-workspace-outside-source-clip', target.dropHover);
                const point = target.mapToItem(overview, target.width / 2, target.height / 2);
                root.pointer.mouseRelease(overview, point.x, point.y, Qt.LeftButton, Qt.NoModifier, 0);
                root.phase++;
            } else if (root.phase === 9) {
                root.check('native-drop-moves-once-without-focus-or-dismiss', root.moves.length === 1
                    && root.moves[0].destination === '2' && root.moves[0].ref.instanceId === 'a:1'
                    && root.calls.length === 1 && root.navigation.active);
                root.source.commandFinished(root.navigation.moveState.requestId, { ok: true });
                const hit = root.find(overview, 'overview-hit-a:1');
                root.pointer.mousePress(hit, hit.width / 2, hit.height / 2, Qt.LeftButton, Qt.NoModifier, 0);
                root.pointer.mouseMove(hit, hit.width / 2 + 24, hit.height / 2, 0, Qt.LeftButton, Qt.NoModifier);
                root.phase++;
            } else if (root.phase === 10) {
                root.navigation.dismissTop();
                const target = root.find(overview, 'overview-workspace-3');
                const point = target.mapToItem(overview, target.width / 2, target.height / 2);
                root.pointer.mouseMove(overview, point.x, point.y, 0, Qt.LeftButton, Qt.NoModifier);
                root.pointer.mouseRelease(overview, point.x, point.y, Qt.LeftButton, Qt.NoModifier, 0);
                root.phase++;
            } else {
                root.check('escape-then-release-neither-moves-nor-activates', root.moves.length === 1
                    && root.calls.length === 1 && root.navigation.active && !root.navigation.dragToken
                    && root.navigation.moveState.kind === 'idle');
                root.navigation.cancel();
                console.log('PENTAD_TEST ' + JSON.stringify({ status: root.checks.every(function(check) { return check.passed; })
                    ? 'pass' : 'fail', checks: root.checks }));
                Qt.quit();
            }
        }
    }
    Timer { interval: 10000; running: true; onTriggered: {
        console.log('PENTAD_TEST ' + JSON.stringify({ status: 'fail', checks: [{ name: 'gallery-deadline', passed: false }] })); Qt.quit();
    } }
}
