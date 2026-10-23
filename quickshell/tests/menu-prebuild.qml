import QtQuick
import QtTest
import Quickshell
import qs.services
import qs.shell

// Bar menus built ahead of time per output. "speed" (the default) builds every drawer once a bar has
// settled, one surface per step, control centers first; "memory" builds only what is hovered or
// opened. Real bars check the hidden-content guarantees (no window shown, no focus, no input-region
// change, no service consumers) and live mode switches; light stand-in bars check removal mid-way.
ShellRoot {
    id: root
    property Services services: Services { preview: true; safeMode: true }
    readonly property int delay: 1200
    readonly property int gap: 450
    readonly property var screenA: Quickshell.screens[0] || null
    readonly property var screenB: Quickshell.screens[1] || null
    property var checks: []
    property double startedAt: Date.now()
    property int phase: 0
    property double mark: 0
    property var events: []
    property var tracked: []
    property var masks: []
    property var keptContent: null
    property TestEvent pointer: TestEvent {}

    function check(name, passed, detail) { checks.push({ name: name, passed: passed === true, detail: detail || '' }); }
    function elapsed() { return Date.now() - startedAt; }
    function barsOf(owner) {
        const list = [];
        for (let index = 0; index < owner.outputWindows.count; index++) list.push(owner.outputWindows.objectAt(index));
        return list;
    }
    function realBars() { return barsOf(host).concat(barsOf(laterHost), barsOf(lateHost)); }
    // Names the bars of one host ("A1", "B1"…) and records when each of their menus first exists.
    function track(owner, suffix) {
        tracked = barsOf(owner).map((item, index) => ({ bar: item, label: String.fromCharCode(65 + index) + suffix, seen: ({}) }));
        events = [];
        mark = elapsed();
    }
    function sample() {
        for (const entry of tracked) {
            if (!entry.bar || !entry.bar.menusPrepared) continue;
            for (const side of ['right', 'left', 'activity']) {
                if (entry.bar.menusPrepared[side] && !entry.seen[side]) {
                    entry.seen[side] = true;
                    events = events.concat([{ name: entry.label + ':' + side, at: elapsed() - mark }]);
                }
            }
        }
    }
    function order() { return events.map(event => event.name).join(','); }
    function staggered() {
        for (let index = 1; index < events.length; index++)
            if (events[index].at - events[index - 1].at < gap - 100) return false;
        return events.length > 1;
    }
    function built(item) { return item.menusPrepared.right && item.menusPrepared.left && item.menusPrepared.activity; }
    function nothingBuilt(item) { return !item.menusPrepared.right && !item.menusPrepared.left && !item.menusPrepared.activity; }
    function setMode(mode) {
        const documents = services.config.documents;
        services.config.documents = Object.assign({}, documents,
            { interface: Object.assign({}, documents.interface, { barMenus: mode }) });
    }
    function hostsHidden() {
        return realBars().every(item => [item.leftPopup, item.rightPopup, item.activityPopup].every(popup =>
            !popup.visible && !popup.focusItem.activeFocus)) && services.popups.surface === '';
    }
    function consumers() {
        return { quickSettings: services.quickSettings.consumers.length, media: services.media.positionConsumers.length,
            lyrics: services.lyrics.consumers.length, visualizer: services.visualizer.consumers.length,
            mixer: services.audio.mixerConsumersCount };
    }
    function noConsumers() {
        const count = consumers();
        return Object.keys(count).every(key => count[key] === 0);
    }
    function finish() {
        console.log('PENTAD_TEST ' + JSON.stringify({ status: checks.length > 0 && checks.every(item => item.passed) ? 'pass' : 'fail',
            checks: checks }));
        Qt.quit();
    }

    OutputHost {
        id: host
        services: root.services
        outputs: root.screenA && root.screenB ? [root.screenA, root.screenB] : []
        prebuildDelay: root.delay
        prebuildGap: root.gap
    }
    OutputHost {
        id: laterHost
        services: root.services
        outputs: []
        prebuildDelay: root.delay
        prebuildGap: root.gap
    }
    OutputHost {
        id: lateHost
        services: root.services
        outputs: []
        prebuildDelay: root.delay
        prebuildGap: root.gap
    }
    // Stand-in bars with the BarWindow build-ahead API, so outputs can be removed mid-way without
    // tearing down whole bar windows.
    OutputHost {
        id: standInHost
        services: root.services
        outputs: []
        prebuildDelay: root.delay
        prebuildGap: root.gap
        surfaceComponent: Component {
            QtObject {
                id: standIn
                required property var modelData
                property bool menuPrebuildDue: false
                property var menusPrepared: ({ right: false, left: false, activity: false })
                function prebuildMenu(side) {
                    const next = Object.assign({}, menusPrepared);
                    next[side] = true;
                    menusPrepared = next;
                }
                property Timer settle: Timer {
                    interval: root.delay; running: true
                    onTriggered: {
                        standIn.menuPrebuildDue = true;
                        Qt.callLater(standInHost.prebuildNext);
                    }
                }
            }
        }
    }

    Timer {
        interval: 50; running: true; repeat: true
        onTriggered: {
            root.sample();
            const t = root.elapsed() - root.mark;
            if (root.phase === 0) {
                if (!root.screenA || !root.screenB) {
                    root.check('two-outputs-available', false, String(Quickshell.screens.length));
                    root.finish();
                    return;
                }
                root.track(host, '1');
                root.phase = 1;
            } else if (root.phase === 1 && t >= 900) {
                root.check('nothing-is-built-before-the-bar-settles', root.barsOf(host).every(item => root.nothingBuilt(item)),
                    root.order());
                root.masks = root.barsOf(host).map(item => item.mask.regions.length);
                root.phase = 2;
            } else if (root.phase === 2 && t >= 4800) {
                // Speed: every drawer on every output, control centers first, one surface per step.
                root.check('speed-builds-every-menu-on-every-output', root.barsOf(host).every(item => root.built(item)
                    && item.rightPopup.rightContentStatus === Loader.Ready && item.leftPopup.leftContentStatus === Loader.Ready
                    && item.activityPopup.activityContentStatus === Loader.Ready), root.order());
                root.check('control-centers-first-then-sidebars-then-activity',
                    root.order() === 'A1:right,B1:right,A1:left,B1:left,A1:activity,B1:activity', root.order());
                root.check('first-build-waits-for-the-settle-delay', root.events.length > 0 && root.events[0].at >= root.delay - 60,
                    JSON.stringify(root.events));
                root.check('builds-are-staggered', root.events.length === 6 && root.staggered(), JSON.stringify(root.events));
                root.check('stagger-stops-when-everything-is-built', !host.prebuildStagger.running);
                root.check('built-menus-stay-hidden-and-unfocused', root.hostsHidden());
                root.check('bar-input-regions-are-unchanged', JSON.stringify(root.barsOf(host).map(item => item.mask.regions.length))
                    === JSON.stringify(root.masks), JSON.stringify(root.masks));
                root.check('hidden-menus-start-no-service-consumers', root.noConsumers(), JSON.stringify(root.consumers()));
                root.keptContent = root.barsOf(host)[0].rightPopup.rightContent;
                root.services.popups.open('right', root.barsOf(host)[0].outputId);
                root.phase = 3;
            } else if (root.phase === 3 && t >= 5200) {
                const first = root.barsOf(host)[0];
                root.check('opened-control-center-is-the-prebuilt-one', first.rightPopup.visible
                    && first.rightPopup.rightContent === root.keptContent);
                root.check('quick-settings-are-held-while-shown', root.services.quickSettings.consumers.length === 1,
                    JSON.stringify(root.consumers()));
                root.services.popups.closeSurface('right', first.outputId);
                root.phase = 4;
            } else if (root.phase === 4 && t >= 5800) {
                root.check('closing-releases-quick-settings', !root.barsOf(host)[0].rightPopup.visible && root.noConsumers(),
                    JSON.stringify(root.consumers()));
                // Memory: bars that appear now build nothing ahead of time; hover prepares only its side.
                root.setMode('memory');
                laterHost.outputs = [root.screenA, root.screenB];
                root.track(laterHost, '2');
                root.phase = 5;
            } else if (root.phase === 5 && t >= root.delay + 3 * root.gap + 300) {
                root.check('memory-builds-nothing-ahead-of-time', root.barsOf(laterHost).length === 2
                    && root.barsOf(laterHost).every(item => item.menuPrebuildDue && root.nothingBuilt(item)), root.order());
                const face = root.barsOf(laterHost)[0].barFace;
                root.check('right-hover-dispatched', root.pointer.mouseMove(face, face.width - 2, face.height / 2, 0,
                    Qt.NoButton, Qt.NoModifier));
                root.phase = 6;
            } else if (root.phase === 6 && t >= root.delay + 3 * root.gap + 700) {
                root.check('memory-builds-only-the-hovered-menu', root.order() === 'A2:right'
                    && root.nothingBuilt(root.barsOf(laterHost)[1]), root.order());
                root.keptContent = root.barsOf(laterHost)[0].rightPopup.rightContent;
                // Live switch to speed: the rest is built at once, still one surface per step.
                root.track(laterHost, '2');
                root.tracked[0].seen.right = true;
                root.setMode('speed');
                root.phase = 7;
            } else if (root.phase === 7 && t >= 5 * root.gap + 600) {
                root.check('switching-to-speed-builds-the-rest',
                    root.order() === 'B2:right,A2:left,B2:left,A2:activity,B2:activity'
                    && root.barsOf(laterHost).every(item => root.built(item)), root.order());
                root.check('switching-to-speed-starts-at-once', root.events.length > 0 && root.events[0].at <= 150,
                    JSON.stringify(root.events));
                root.check('switched-builds-are-staggered', root.staggered(), JSON.stringify(root.events));
                root.check('hovered-menu-is-not-rebuilt', root.barsOf(laterHost)[0].rightPopup.rightContent === root.keptContent);
                root.check('switched-menus-stay-hidden-without-consumers', root.hostsHidden() && root.noConsumers(),
                    JSON.stringify(root.consumers()));
                // An output that appears later is built after its own delay.
                lateHost.outputs = [root.screenA];
                root.track(lateHost, '3');
                root.phase = 8;
            } else if (root.phase === 8 && t >= root.delay + 3 * root.gap + 400) {
                root.check('new-output-builds-after-its-own-delay', root.order() === 'A3:right,A3:left,A3:activity'
                    && root.events[0].at >= root.delay - 60 && root.staggered(), JSON.stringify(root.events));
                root.check('new-output-menus-stay-hidden-without-consumers', root.hostsHidden() && root.noConsumers(),
                    JSON.stringify(root.consumers()));
                standInHost.outputs = [root.screenA, root.screenB];
                root.track(standInHost, '4');
                root.phase = 9;
            } else if (root.phase === 9 && t >= root.delay + 150) {
                // Both outputs go away while the stagger still has work for them.
                root.check('stand-in-build-started', root.order() === 'A4:right' && standInHost.prebuildStagger.running,
                    root.order());
                standInHost.outputs = [];
                root.phase = 10;
            } else if (root.phase === 10 && t >= root.delay + 150 + 2 * root.gap) {
                root.check('removed-outputs-stop-the-stagger', !standInHost.prebuildStagger.running
                    && standInHost.outputWindows.count === 0 && root.order() === 'A4:right', root.order());
                standInHost.outputs = [root.screenB];
                root.track(standInHost, '5');
                root.phase = 11;
            } else if (root.phase === 11 && t >= root.delay + 150) {
                // Switching to memory while building stops further builds and keeps what exists.
                root.setMode('memory');
                root.phase = 12;
            } else if (root.phase === 12 && t >= root.delay + 4 * root.gap) {
                root.check('switching-to-memory-stops-further-builds', root.order() === 'A5:right'
                    && !standInHost.prebuildStagger.running && root.barsOf(standInHost)[0].menusPrepared.right, root.order());
                root.finish();
            }
        }
    }
    Timer { interval: 27000; running: true; onTriggered: { root.check('fixture-timeout', false, String(root.phase)); root.finish(); } }
}
