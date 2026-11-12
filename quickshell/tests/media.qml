import QtQuick
import QtQml
import QtTest
import Quickshell
import qs.services
import qs.features.media
import qs.features.bar
import qs.theme
import qs.components
import '../logic/lyrics.mjs' as LyricsLogic

ShellRoot {
    id: root
    readonly property string fixtureMode: ['playing', 'paused', 'no-art', 'no-player', 'missing-lyrics', 'long-title'].includes(Quickshell.env('PENTAD_MEDIA_FIXTURE'))
        ? Quickshell.env('PENTAD_MEDIA_FIXTURE') : 'playing'
    property Services nativeServices: Services { preview: true; safeMode: true }
    property TestEvent pointer: TestEvent {}
    property QtObject fakeMedia: QtObject {
        id: media
        property var consumers: []
        property var players: root.fixtureMode === 'no-player' ? [] : [
            { id: 'fixture.a', name: 'spotify', title: root.fixtureMode === 'long-title' ? 'Дуже довга назва композиції, яка точно не вміщується в картку плеєра повністю' : 'Тестова пісня', artist: 'Pentad fixture', album: 'Test', playback: root.fixtureMode === 'paused' ? 'paused' : 'playing', positionMicros: 13000000, positionUpdatedAt: Date.now() + 60000, lengthMicros: 180000000, trackId: '/track/a', trackRevision: 'a', canPlayPause: true, canPrevious: true, canNext: true, canSeek: true },
            { id: 'fixture.b', name: 'vlc', title: 'Second source', artist: 'Fixture', playback: 'paused', positionMicros: 0, lengthMicros: 90000000, trackId: '/track/b', trackRevision: 'b', canPlayPause: true, canPrevious: false, canNext: true, canSeek: true }
        ]
        property string selectedId: 'fixture.a'
        property var commands: []
        signal commandFinished(string requestId, var result)
        readonly property var state: ({ kind: 'ready', value: { players: players, selectedId: selectedId, current: players.find(function(item) { return item.id === selectedId }) || null } })
        function acquire(id) { if (id && !consumers.includes(id)) consumers = consumers.concat([id]) }
        function release(id) { consumers = consumers.filter(function(item) { return item !== id }) }
        function selectPlayer(id) { selectedId = id; return 'fixture-selection' }
        function command(id, action) { commands = commands.concat([{ id: id, action: action }]); return 'fixture-command' }
        property var seeks: []
        function seek(id, track, value, revision) { seeks = seeks.concat([{ id: id, track: track, value: value }]); return 'fixture-seek' }
    }
    property QtObject fakeLyrics: QtObject {
        property var consumers: []
        property int offsetMs: 500
        readonly property var state: ({ kind: 'ready', value: {
            lines: root.fixtureMode === 'missing-lyrics' ? [] : LyricsLogic.parseLrc(root.fixtureMode === 'long-title'
                ? '[00:04.00]Попередній рядок\n[00:10.00]<00:10.00>Дуже довгий рядок пісні, який <00:12.00>ніяк не вміщується <00:14.00>в острів навіть дрібнішим шрифтом\n[00:18.00]Наступний рядок'
                : '[00:04.00]Попередній рядок\n[00:10.00]<00:10.00>Тестова <00:12.00>пісня <00:14.00>для Pentad\n[00:18.00]Наступний рядок'),
            plain: '', instrumental: false
        } })
        function acquire(id) { if (id && !consumers.includes(id)) consumers = consumers.concat([id]) }
        function release(id) { consumers = consumers.filter(function(item) { return item !== id }) }
    }
    property QtObject fakeVisualizer: QtObject {
        property var consumers: []
        readonly property var state: ({ kind: 'ready', value: { values: [0.2, 0.45, 0.8, 0.9, 0.6, 0.3, 0.1, 0.35, 0.7, 0.5, 0.2, 0.1] } })
        function acquire(id) { if (id && !consumers.includes(id)) consumers = consumers.concat([id]) }
        function release(id) { consumers = consumers.filter(function(item) { return item !== id }) }
    }
    property QtObject fakeArtwork: QtObject {
        property var states: ({})
        property var consumers: []
        function stateFor(id) { return states[id] || ({ kind: 'unavailable', source: '', reason: 'no-artwork' }) }
        function request(id, urls) {
            if (!consumers.includes(id)) consumers = consumers.concat([id]);
            if (states[id] && states[id].kind === 'ready' && urls.includes(states[id].source)) return;
            var next = Object.assign({}, states);
            next[id] = { kind: 'unavailable', source: '', reason: urls.length ? 'fixture' : 'no-artwork' };
            states = next;
        }
        function release(id) {
            consumers = consumers.filter(function(item) { return item !== id });
            var next = Object.assign({}, states); delete next[id]; states = next;
        }
    }
    property QtObject fixtureServices: QtObject {
        readonly property bool preview: true
        readonly property bool safeMode: true
        readonly property var config: root.nativeServices.config
        readonly property var plugins: root.nativeServices.plugins
        readonly property var media: root.fakeMedia
        readonly property var artwork: root.fakeArtwork
        readonly property var lyrics: root.fakeLyrics
        readonly property var visualizer: root.fakeVisualizer
        readonly property var activity: root.nativeServices.activity
        readonly property var popups: root.nativeServices.popups
    }
    property var checks: []
    property var firstPlacement: null
    property var secondPlacement: null
    property bool wrapPreview: false
    property string savedCardAccent: ''
    property string savedFocusAccent: ''
    property QtObject fakeShelf: QtObject {
        property bool ready: true
        property bool writable: true
        property string loadError: ""
        property var files: ({ metadata: ({}) })
        property var entries: [
            { id: "image", label: "Sample.svg", uri: 'file://' + Quickshell.env('XDG_CONFIG_HOME') + '/quickshell-fixture/assets/icons/brand/logo-symbolic.svg' },
            { id: "document", label: "Нотатки.txt", uri: "file:///tmp/pentad-menu-notes.txt" },
            { id: "archive", label: "Project.zip", uri: "file:///tmp/pentad-menu-project.zip" }
        ]
        signal commandFinished(string requestId, var result)
        function addUris(uris) {
            entries = entries.concat([{ id: "added", label: "Added.txt", uri: uris[0] }]);
            Qt.callLater(function() { commandFinished("fixture-add", { ok: true }); });
            return "fixture-add";
        }
        function remove(id) {
            entries = entries.filter(function(entry) { return entry.id !== id; });
            Qt.callLater(function() { commandFinished("fixture-remove", { ok: true }); });
            return "fixture-remove";
        }
    }
    // The quick Stash tab takes the full services: the activity facade carries no Stash and no text().
    // The shell language is Ukrainian here, so every label the menu shows must come out Ukrainian.
    property QtObject stashServices: QtObject {
        readonly property var shelf: root.fakeShelf
        readonly property var stash: root.nativeServices.stash
        readonly property var toolWorkspace: root.nativeServices.toolWorkspace
        function text(uk, en) { return uk; }
    }
    function findImage(item, source) {
        if (!item) return null;
        if (String(item).indexOf('QQuickImage') === 0 && String(item.source) === source) return item;
        const items = (item.children || []).concat(item.overhangSurface ? [item.overhangSurface] : []);
        for (let index = 0; index < items.length; index++) {
            const found = findImage(items[index], source);
            if (found) return found;
        }
        return null;
    }
    function findNamedItem(item, name) {
        if (!item) return null;
        if (item.objectName === name) return item;
        // The island's karaoke overhang is a popup window, outside the visual tree.
        const items = (item.children || []).concat(item.overhangSurface ? [item.overhangSurface] : []);
        for (let index = 0; index < items.length; index++) {
            const found = findNamedItem(items[index], name);
            if (found) return found;
        }
        return null;
    }
    function mediaButtons(item) {
        var found = item.iconReady !== undefined && item.glyph !== undefined ? [item] : [];
        var children = item.children || [];
        for (var i = 0; i < children.length; i++) found = found.concat(mediaButtons(children[i]));
        return found;
    }
    function checkCardLayout() {
        var surface = findNamedItem(card, 'music-player-surface');
        var controls = findNamedItem(card, 'music-player-controls');
        var time = findNamedItem(card, 'music-player-time-row');
        var seek = findNamedItem(card, 'music-player-seek-row');
        var origin = controls.mapToItem(surface, 0, 0);
        var buttons = mediaButtons(card);
        root.checks.push({ name: 'media-icons-load-from-local-svg-without-font-glyphs', passed: buttons.length >= 6
            && buttons.every(function(button) { return button.iconReady && String(button.iconSource).endsWith('.svg'); }) });
        root.checks.push({ name: 'media-controls-fit-inside-surface-insets', passed: origin.y >= 12
            && origin.x + controls.width <= surface.width - 12
            && origin.y + controls.height <= surface.height - 12 });
        root.checks.push({ name: 'primary-transport-and-seek-have-separate-rows', passed: time.height === 44
            && seek.y >= time.y + time.height + 4
            && Math.abs(time.childrenRect.width - time.width) < 0.01
            && Math.abs(seek.childrenRect.width - seek.width) < 0.01 });
        var fallback = findNamedItem(card, 'music-cover-fallback');
        root.checks.push({ name: 'missing-cover-uses-local-svg', passed: fallback.imageStatus === Image.Ready });
    }
    Component.onCompleted: {
        var appearance = Quickshell.env('PENTAD_GALLERY_APPEARANCE') === 'light' ? 'light' : 'dark';
        var requestedAccent = Quickshell.env('PENTAD_GALLERY_ACCENT') || '#869677';
        var accent = /^#[0-9a-f]{6}$/i.test(requestedAccent) ? requestedAccent : '#869677';
        var reducedMotion = Quickshell.env('PENTAD_GALLERY_REDUCED_MOTION') === '1';
        Theme.resolve({ appearance: appearance, accent: accent, fontFamily: 'Geist', reducedMotion: reducedMotion });
    }
    FloatingWindow {
        visible: true
        implicitWidth: 800; implicitHeight: 600
        color: Theme.tokens.surface
        Item {
            id: capture
            width: 800; height: 600
            Rectangle { anchors.fill: parent; color: root.wrapPreview ? '#41473d' : Theme.tokens.surface }
            Rectangle {
                x: 0; y: 10; width: parent.width; height: root.nativeServices.config.documents.layout.barHeight
                color: Theme.tokens.surface
                visible: root.wrapPreview
            }
            LiveIsland { id: island; x: 220; y: 10; width: implicitWidth; height: implicitHeight; services: root.fixtureServices; outputId: 'fixture'; consumerId: 'fixture-island' }
            MusicCard { id: card; x: 190; y: 140; width: 420; services: root.fixtureServices; outputId: 'fixture'; karaokeEnabled: true }
            ContinuousSurface {
                id: menuSurface
                x: 146; y: 42; width: 508
                height: menu.implicitHeight + 24
                extent: Metrics.attachedRadius
                concaveShoulder: Metrics.attachedShoulder
                joinOffset: 0
                fill: Theme.tokens.surface
                visible: false
                ActivityMenu {
                    id: menu
                    x: 44; y: 12; width: 420
                    services: root.fixtureServices
                    stashServices: root.stashServices
                    outputId: "fixture-menu"
                    property int closeRequests: 0
                    onCloseRequested: closeRequests++
                }
            }
        }
    }
    Timer {
        id: steps
        interval: 180; running: true; repeat: true
        property int step: 0
        onTriggered: {
            step++;
            if (step === 1) {
                if (root.fixtureMode === 'missing-lyrics') {
                    root.checkCardLayout();
                    root.checks.push({ name: 'missing-lyrics-hides-unusable-search-and-offset-toolbar',
                        passed: !root.findNamedItem(card, 'lyrics-toolbar').visible });
                    capture.grabToImage(function(result) {
                        root.checks.push({ name: 'missing-lyrics-capture', passed: result.saveToFile(Quickshell.env('PENTAD_ARTIFACT_PATH')) });
                        result.saveToFile(Quickshell.env('PENTAD_ARTIFACT_PATH') + '.focus.png');
                        console.log('PENTAD_TEST ' + JSON.stringify({ status: root.checks.every(function(check) { return check.passed }) ? 'pass' : 'fail', checks: root.checks }));
                        Qt.quit();
                    });
                    stop();
                    return;
                }
                if (root.fixtureMode === 'no-player') {
                    root.checks.push({ name: 'no-player-hides-media-card', passed: card.player === null && !card.visible });
                    capture.grabToImage(function(result) {
                        root.checks.push({ name: 'no-player-capture', passed: result.saveToFile(Quickshell.env('PENTAD_ARTIFACT_PATH')) });
                        result.saveToFile(Quickshell.env('PENTAD_ARTIFACT_PATH') + '.focus.png');
                        console.log('PENTAD_TEST ' + JSON.stringify({ status: root.checks.every(function(check) { return check.passed }) ? 'pass' : 'fail', checks: root.checks }));
                        Qt.quit();
                    });
                    stop();
                    return;
                }
                root.nativeServices.activity.karaoke = true;
                var component = Qt.createComponent('widgets/activity/Controller.qml');
                root.firstPlacement = component.createObject(root, { instanceId: 'first', settings: { preferredId: 'fixture.a' }, services: root.fixtureServices });
                root.secondPlacement = component.createObject(root, { instanceId: 'second', settings: { preferredId: 'fixture.b' }, services: root.fixtureServices });
            } else if (step === 2) {
                root.checkCardLayout();
                root.checks.push({ name: 'karaoke-overhang', passed: island.expanded && island.overhangHeight > island.implicitHeight
                    && island.renderedHeight === island.implicitHeight && island.inputRegion === null && island.width === 360 });
                root.checks.push({ name: 'expanded-island-starts-in-bar-without-empty-header', passed:
                    island.implicitHeight === root.nativeServices.config.documents.layout.barHeight
                    && island.overhangHeight === 88
                    && root.findNamedItem(island, 'island-lyrics').y < island.implicitHeight });
                const outer = root.findNamedItem(island, 'island-outer-surface');
                const inner = root.findNamedItem(island, 'island-focus-card');
                root.checks.push({ name: 'bar-wraps-focus-card-with-concentric-corners-and-even-rim', passed:
                    outer.cornerGeometry.join === island.implicitHeight
                    && inner.x - outer.cornerGeometry.shoulder === 4
                    && inner.y === 4 && outer.height - inner.y - inner.height === 4
                    && outer.cornerGeometry.radius - inner.extent === 4 });
                if (root.fixtureMode === 'paused') root.checks.push({ name: 'paused-fixture-state', passed: card.player && card.player.playback === 'paused' });
                var playerTitle = root.findNamedItem(card, 'music-player-title');
                var karaokeLine = root.findNamedItem(island, 'island-karaoke-line');
                root.checks.push({ name: 'karaoke-line-shrinks-then-fades-instead-of-clipping', passed: !!karaokeLine
                    && (root.fixtureMode === 'long-title'
                        ? karaokeLine.overflows && karaokeLine.pixelSize === karaokeLine.minPixelSize && (karaokeLine.hiddenLeft || karaokeLine.hiddenRight)
                        : !karaokeLine.overflows && karaokeLine.pixelSize === karaokeLine.maxPixelSize && !karaokeLine.hiddenLeft && !karaokeLine.hiddenRight),
                    detail: karaokeLine ? JSON.stringify({ size: karaokeLine.pixelSize, overflows: karaokeLine.overflows, left: karaokeLine.hiddenLeft, right: karaokeLine.hiddenRight, progress: karaokeLine.progress, offset: karaokeLine.scrollOffset, textWidth: karaokeLine.textWidth, width: karaokeLine.width }) : 'missing' });
                root.checks.push({ name: 'player-title-marquee-scrolls-only-when-overflowing', passed: !!playerTitle
                    && (root.fixtureMode === 'long-title' ? playerTitle.overflow > 0 : playerTitle.overflow === 0) });
                if (root.fixtureMode === 'no-art') {
                    root.checks.push({ name: 'no-art-fixture-state', passed: card.artState.kind === 'unavailable' });
                }
                var artworkImage = root.findNamedItem(card, 'audio-wave-artwork');
                root.checks.push({ name: 'empty-artwork-url-hides-wave-image', passed: !!artworkImage
                    && String(artworkImage.source) === '' && !artworkImage.visible });
                root.checks.push({ name: 'karaoke-input-mask-follows-scene-contour', passed: island.overhangRegion.containsPoint(180, 60) && !island.overhangRegion.containsPoint(0, 87) && island.overhangRegion.originX === 0 && island.overhangRegion.originY === 0 });
                root.checks.push({ name: 'shared-media-views', passed: card.player.id === island.player.id });
                var seekBar = root.findNamedItem(card, 'music-seek');
                var refreshPlayers = function() {
                    root.fakeMedia.players = root.fakeMedia.players.map(function(player) { return Object.assign({}, player); });
                };
                if (seekBar) {
                    root.fakeMedia.seeks = [];
                    root.pointer.mousePress(seekBar, seekBar.width * 0.3, seekBar.height / 2, Qt.LeftButton, Qt.NoModifier, 0);
                    root.pointer.mouseMove(seekBar, seekBar.width * 0.5, seekBar.height / 2, 0, Qt.LeftButton, Qt.NoModifier);
                    refreshPlayers();
                    root.pointer.mouseMove(seekBar, seekBar.width * 0.7, seekBar.height / 2, 0, Qt.LeftButton, Qt.NoModifier);
                    root.pointer.mouseRelease(seekBar, seekBar.width * 0.7, seekBar.height / 2, Qt.LeftButton, Qt.NoModifier, 0);
                    refreshPlayers();
                }
                var seeks = root.fakeMedia.seeks;
                var seekRatio = seeks.length ? seeks[0].value / 180000000 : 0;
                root.checks.push({ name: 'drag-seeks-once-on-release-and-holds-target', passed: !!seekBar
                    && seeks.length === 1 && seeks[0].id === 'fixture.a' && seeks[0].track === '/track/a'
                    && seekRatio > 0.6 && seekRatio < 0.8
                    && Math.abs(card.positionMicros - seeks[0].value) < 1000000,
                    detail: JSON.stringify({ seeks: seeks, shown: card.positionMicros }) });
                root.checks.push({ name: 'placement-preferences-independent', passed: !!root.firstPlacement && !!root.secondPlacement && root.firstPlacement.media.state.value.current.id === 'fixture.a' && root.secondPlacement.media.state.value.current.id === 'fixture.b' });
                root.firstPlacement.media.selectPlayer('fixture.b');
                root.secondPlacement.media.selectPlayer('fixture.a');
                root.firstPlacement.settings = { preferredId: 'fixture.a', retainedUnknownKey: true };
                card.cyclePlayer(1);
            } else if (step === 3) {
                root.checks.push({ name: 'source-selection-synchronizes', passed: card.player.id === 'fixture.b' && island.player.id === 'fixture.b' });
                root.checks.push({ name: 'placement-selection-independent', passed: root.firstPlacement.media.state.value.current.id === 'fixture.b' && root.secondPlacement.media.state.value.current.id === 'fixture.a' && root.firstPlacement.services.media === root.secondPlacement.services.media });
                root.firstPlacement.settings = { preferredId: 'fixture.b' };
                root.checks.push({ name: 'changed-preference-applied-live', passed: root.firstPlacement.selectedId === 'fixture.b' });
                root.fakeMedia.selectPlayer('fixture.a');
                island.consumerId = 'fixture-island-rebound';
            } else if (step === 4) {
                root.checks.push({ name: 'context-change-releases-old-consumer', passed: !root.fakeMedia.consumers.includes('fixture-island')
                    && root.fakeMedia.consumers.includes('fixture-island-rebound')
                    && !root.fakeLyrics.consumers.includes('fixture-island')
                    && root.fakeLyrics.consumers.includes('fixture-island-rebound') });
                island.cycleSource(1);
                const cycledForward = island.player.id === 'fixture.b' && island.sourceHintVisible;
                island.cycleSource(-1);
                root.checks.push({ name: 'island-scroll-cycles-source', passed: cycledForward && island.player.id === 'fixture.a' });
                root.nativeServices.popups.open('activity', 'fixture');
                root.checks.push({ name: 'popup-suppresses-karaoke-overhang', passed: !island.expanded });
                root.nativeServices.popups.close();
            } else if (step === 5) {
                root.checks.push({ name: 'distinct-media-consumers', passed: root.fakeMedia.consumers.length === 2 });
                root.checks.push({ name: 'distinct-lyrics-consumers', passed: root.fakeLyrics.consumers.length === 2, detail: JSON.stringify(root.fakeLyrics.consumers) });
                capture.grabToImage(function(result) {
                    root.checks.push({ name: 'media-capture', passed: result.saveToFile(Quickshell.env('PENTAD_ARTIFACT_PATH')) });
                    root.checks.push({ name: 'native-pointer-move-accepted', passed: root.pointer.mouseMove(island.overhangSurface, 180, 16, 0, Qt.NoButton, Qt.NoModifier) });
                    steps.restart();
                });
                stop();
            } else if (step === 6) {
                root.checks.push({ name: 'karaoke-hover-restores-focus-card', passed: island.overhangHeight === 88
                    && root.findNamedItem(island, 'island-focus-card').y === 4
                    && root.findNamedItem(island, 'island-focus-card').visible,
                    detail: JSON.stringify({ visible: root.findNamedItem(island, 'island-focus-card').visible,
                        hit: island.overhangRegion.containsPoint(298, 48) }) });
                const play = root.findNamedItem(island, 'island-focus-play');
                const point = play.mapToItem(island.overhangSurface, play.width / 2, play.height / 2);
                root.pointer.mouseMove(island.overhangSurface, point.x, Math.max(point.y, island.implicitHeight + 8), 0, Qt.NoButton, Qt.NoModifier);
            } else if (step >= 7 && step <= 10) {
                const names = ['play', 'previous', 'next', 'exit'];
                const button = root.findNamedItem(island, 'island-focus-' + names[step - 7]);
                root.checks.push({ name: 'focus-' + names[step - 7] + '-receives-hover',
                    passed: button.hovered && root.findNamedItem(island, 'island-focus-card').visible });
                if (step < 10) {
                    const next = root.findNamedItem(island, 'island-focus-' + names[step - 6]);
                    const point = next.mapToItem(island.overhangSurface, next.width / 2, next.height / 2);
                    root.pointer.mouseMove(island.overhangSurface, point.x, point.y, 0, Qt.NoButton, Qt.NoModifier);
                } else {
                    root.pointer.mouseMove(island.overhangSurface, 1, island.overhangHeight - 1, 0, Qt.NoButton, Qt.NoModifier);
                }
            } else if (step === 11) {
                root.checks.push({ name: 'leaving-island-restores-lyrics',
                    passed: !root.findNamedItem(island, 'island-focus-card').visible
                        && root.findNamedItem(island, 'island-lyrics').visible });
                root.pointer.mouseMove(island.overhangSurface, 180, 16, 0, Qt.NoButton, Qt.NoModifier);
            } else if (step === 12) {
                const play = root.findNamedItem(island, 'island-focus-play');
                const point = play.mapToItem(island.overhangSurface, play.width / 2, play.height / 2);
                root.pointer.mouseMove(island.overhangSurface, point.x, point.y, 0, Qt.NoButton, Qt.NoModifier);
            } else if (step === 13) {
                root.checks.push({ name: 'hover-survives-below-compact-footprint', passed: island.overhangHeight === 88
                    && root.findNamedItem(island, 'island-focus-card').visible });
                const play = root.findNamedItem(island, 'island-focus-play');
                const previous = root.findNamedItem(island, 'island-focus-previous');
                const next = root.findNamedItem(island, 'island-focus-next');
                const title = root.findNamedItem(island, 'island-focus-title');
                const exit = root.findNamedItem(island, 'island-focus-exit');
                const titleBottom = title.mapToItem(play.parent, 0, title.height + 14).y;
                root.checks.push({ name: 'focus-transport-order-and-text-clearance', passed:
                    previous.x + previous.width < play.x && play.x + play.width < next.x
                    && titleBottom <= play.y && title.width >= 160
                    && exit.mapToItem(play.parent, 0, exit.height).y < play.y });
                const point = play.mapToItem(island.overhangSurface, play.width / 2, play.height / 2);
                root.pointer.mouseClick(island.overhangSurface, point.x, point.y, Qt.LeftButton, Qt.NoModifier, 0);
                root.checks.push({ name: 'hover-play-dispatches-current-player', passed: root.fakeMedia.commands.length === 1
                    && root.fakeMedia.commands[0].id === 'fixture.a' && root.fakeMedia.commands[0].action === 'play-pause' });
                island.overhangSurface.grabToImage(function(result) {
                    root.checks.push({ name: 'karaoke-focus-capture', passed: result.saveToFile(Quickshell.env('PENTAD_ARTIFACT_PATH') + '.focus.png') });
                    card.visible = false;
                    island.visible = false;
                    Qt.callLater(function() {
                        root.checks.push({ name: 'hidden-views-release-producers', passed: root.fakeMedia.consumers.length === 0 && root.fakeLyrics.consumers.length === 0 && root.fakeVisualizer.consumers.length === 0, detail: JSON.stringify({ media: root.fakeMedia.consumers, lyrics: root.fakeLyrics.consumers, visualizer: root.fakeVisualizer.consumers }) });
                    root.fakeMedia.selectPlayer('fixture.b');
                    root.checks.push({ name: 'hidden-card-releases-artwork-and-does-not-restart', passed:
                        root.fakeArtwork.consumers.length === 0 && card.activeArtworkConsumerId === '' });
                        root.nativeServices.popups.open('activity', 'fixture');
                        root.fakeMedia.selectPlayer('fixture.a');
                        island.visible = true;
                        menuSurface.visible = true;
                        menuSteps.start();
                    });
                });
                stop();
            }
        }
    }
    Timer {
        id: menuSteps
        interval: 240; repeat: true
        property int step: 0
        onTriggered: {
            step++;
            if (step === 1) {
                root.checks.push({ name: 'central-menu-has-four-tabs-and-contained-body', passed:
                    menu.labels.length === 4 && menu.width === 420 && menuSurface.height === menu.implicitHeight + 24 });
                root.checks.push({ name: 'activity-tabs-follow-the-shell-language', passed:
                    menu.labels[0] === 'Медіа' && menu.labels[2] === 'Сховок' && menu.labels[3] === 'Хмара'
                    && root.findNamedItem(menu, 'activity-tabs').accessibleName === 'Активності' });
                const readOnlyDrop = { formats: ['text/uri-list'], accepted: false,
                    getDataAsString: () => 'file:///tmp/ignored.txt', accept: function() { this.accepted = true; } };
                root.checks.push({ name: 'read-only-menu-does-not-launch-apps-or-save-files', passed:
                    !menu.openLocalSend() && !menu.shelfGrid.receiveDrop(readOnlyDrop) && !readOnlyDrop.accepted
                    && root.fakeShelf.entries.length === 3 });
                const deniedDrop = { formats: ['text/uri-list'], accepted: false,
                    getDataAsString: () => 'file:///tmp/ignored.txt', accept: function() { this.accepted = true; } };
                menu.receiveLocalDrop(deniedDrop);
                root.checks.push({ name: 'read-only-localsend-drop-is-rejected', passed: !deniedDrop.accepted });
                stop();
                capture.grabToImage(function(result) {
                    root.checks.push({ name: 'central-menu-media-capture', passed: result.saveToFile(Quickshell.env('PENTAD_ARTIFACT_PATH') + '.menu.png') });
                    root.pointer.mouseClick(root.findNamedItem(menu, 'activity-tab-2'), 40, 16, Qt.LeftButton, Qt.NoModifier, 0);
                    menuSteps.start();
                });
            } else if (step === 2) {
                const thumbnail = root.findImage(root.findNamedItem(menu, 'stash-photo-image'), root.fakeShelf.entries[0].uri);
                const tabs = root.findNamedItem(menu, 'activity-tabs');
                root.checks.push({ name: 'shelf-loads-native-file-thumbnail', passed: !!thumbnail && thumbnail.status === Image.Ready
                    && menu.shelfGrid.objectName === 'stash-quick' && menu.shelfGrid.rows.length === 2 });
                root.checks.push({ name: 'shelf-tab-click-slides-selection-and-releases-player', passed:
                    menu.currentIndex === 2 && Math.abs(menu.tabIndicator.x - tabs.inset - 2 * tabs.segmentWidth) < 0.5
                    && !root.fakeMedia.consumers.includes(menu.musicCard.mediaConsumerId)
                    && !root.fakeArtwork.consumers.includes(menu.musicCard.artworkConsumerId) });
                menu.readOnly = false;
                menu.localSendExecutable = '/usr/bin/true';
                const shareDrop = { formats: ['text/uri-list'], accepted: false,
                    getDataAsString: () => 'file:///tmp/Caf%C3%A9%20notes.txt', accept: function() { this.accepted = true; } };
                menu.receiveLocalDrop(shareDrop);
                root.checks.push({ name: 'localsend-handoff-decodes-files-with-separate-argv', passed: shareDrop.accepted
                    && menu.localSendCommand.length === 2 && menu.localSendCommand[1] === '/tmp/Café notes.txt' });
                const addDrop = { formats: ['text/uri-list'], accepted: false,
                    getDataAsString: () => 'file:///tmp/Added.txt\r\n', accept: function() { this.accepted = true; } };
                root.checks.push({ name: 'embedded-stash-drop-adds-via-existing-service', passed:
                    menu.shelfGrid.receiveDrop(addDrop) && addDrop.accepted && root.fakeShelf.entries.length === 4
                    && menu.shelfGrid.rows[0].id === 'added' });
                root.fakeShelf.remove('added');
                menu.readOnly = true;
                stop();
                capture.grabToImage(function(result) {
                    root.checks.push({ name: 'central-menu-shelf-capture', passed: result.saveToFile(Quickshell.env('PENTAD_ARTIFACT_PATH') + '.shelf.png') });
                    const openAll = root.findNamedItem(menu, 'stash-quick-open-all');
                    if (openAll) root.pointer.mouseClick(openAll, openAll.width / 2, openAll.height / 2, Qt.LeftButton, Qt.NoModifier, 0);
                    root.checks.push({ name: 'stash-open-all-shows-window-and-closes-menu', passed: !!openAll
                        && root.nativeServices.stash.visible && menu.closeRequests === 1 });
                    root.nativeServices.stash.hide();
                    menu.selectTab(3);
                    menuSteps.start();
                });
            } else if (step === 3) {
                root.checks.push({ name: 'cloud-page-stays-independent-from-shelf', passed: menu.currentIndex === 3 && root.fakeShelf.entries.length === 3 });
                stop();
                capture.grabToImage(function(result) {
                    root.checks.push({ name: 'central-menu-cloud-capture', passed: result.saveToFile(Quickshell.env('PENTAD_ARTIFACT_PATH') + '.cloud.png') });
                    menu.selectTab(1);
                    menuSteps.start();
                });
            } else if (step === 4) {
                stop();
                menu.readOnly = false;
                capture.grabToImage(function(result) {
                    root.checks.push({ name: 'central-menu-localsend-capture', passed: result.saveToFile(Quickshell.env('PENTAD_ARTIFACT_PATH') + '.localsend.png') });
                    root.pointer.mouseClick(root.findNamedItem(menu, 'activity-open-localsend'), 100, 16, Qt.LeftButton, Qt.NoModifier, 0);
                    root.checks.push({ name: 'localsend-button-requests-menu-close', passed: menu.closeRequests === 2
                        && menu.localSendCommand.length === 1 });
                    menu.readOnly = true;
                    Theme.resolve(Object.assign({}, Theme.config, { reducedMotion: true }));
                    menu.selectTab(0);
                    menuSteps.start();
                });
            } else if (step === 5) {
                const tabs = root.findNamedItem(menu, 'activity-tabs');
                root.checks.push({ name: 'central-tabs-respect-reduced-motion-and-retain-player-selection', passed:
                    menu.currentIndex === 0 && Math.abs(menu.tabIndicator.x - tabs.inset) < 0.5
                    && menu.musicCard.player.id === 'fixture.a' });
                menuSurface.visible = false;
                root.nativeServices.popups.close();
                root.wrapPreview = true;
                root.pointer.mouseMove(island.overhangSurface, 1, island.overhangHeight - 1, 0, Qt.NoButton, Qt.NoModifier);
            } else if (step === 6) {
                stop();
                island.overhangSurface.grabToImage(function(result) {
                    root.checks.push({ name: 'bar-wrap-lyrics-native-capture', passed: result.saveToFile(Quickshell.env('PENTAD_ARTIFACT_PATH') + '.wrap-lyrics.png') });
                    root.pointer.mouseMove(island.overhangSurface, 180, 16, 0, Qt.NoButton, Qt.NoModifier);
                    menuSteps.start();
                });
            } else if (step === 7) {
                root.checks.push({ name: 'wrapped-focus-card-remains-hoverable', passed: root.findNamedItem(island, 'island-focus-card').visible });
                stop();
                island.overhangSurface.grabToImage(function(result) {
                    root.checks.push({ name: 'bar-wrap-focus-native-capture', passed: result.saveToFile(Quickshell.env('PENTAD_ARTIFACT_PATH') + '.wrap-focus.png') });
                    const artworkUrl = 'file://' + Quickshell.env('XDG_CONFIG_HOME')
                        + '/quickshell-fixture/tests/fixtures/media-cover.svg';
                    root.fakeMedia.players = root.fakeMedia.players.map(function(player) {
                        return Object.assign({}, player, { artUrl: artworkUrl });
                    });
                    var states = Object.assign({}, root.fakeArtwork.states);
                    states[menu.musicCard.artworkConsumerId] = { kind: 'ready', source: artworkUrl };
                    states[root.findNamedItem(island, 'island-focus-card').artworkConsumerId] = { kind: 'ready', source: artworkUrl };
                    root.fakeArtwork.states = states;
                    menuSurface.visible = true;
                    menuSteps.start();
                });
            } else if (step === 8) {
                const focus = root.findNamedItem(island, 'island-focus-card');
                root.savedCardAccent = String(menu.musicCard.artAccent);
                root.savedFocusAccent = String(focus.accent);
                root.checks.push({ name: 'artwork-colors-loaded-before-metadata-refresh', passed:
                    root.savedCardAccent !== '#adad9e' && root.savedFocusAccent !== '#adad9e' });
                root.fakeMedia.players = root.fakeMedia.players.map(function(player) {
                    return Object.assign({}, player, { positionMicros: player.positionMicros + 1000000 });
                });
                root.pointer.mouseMove(menu.musicCard, 210, 70, 0, Qt.NoButton, Qt.NoModifier);
            } else if (step === 9) {
                const focus = root.findNamedItem(island, 'island-focus-card');
                root.checks.push({ name: 'media-hover-and-position-refresh-retain-artwork-colors', passed:
                    String(menu.musicCard.artAccent) === root.savedCardAccent
                    && String(focus.accent) === root.savedFocusAccent,
                    detail: JSON.stringify([String(menu.musicCard.artAccent), root.savedCardAccent, String(focus.accent), root.savedFocusAccent, focus.artworkConsumerId, focus.artState]) });
                root.fakeMedia.players = root.fakeMedia.players.map(function(player) {
                    return Object.assign({}, player, { artUrl: '' });
                });
            } else if (step === 10) {
                const focus = root.findNamedItem(island, 'island-focus-card');
                root.checks.push({ name: 'removed-artwork-restores-neutral-colors', passed:
                    String(menu.musicCard.artAccent) === '#adad9e' && String(focus.accent) === '#adad9e' });
                console.log('PENTAD_TEST ' + JSON.stringify({ status: root.checks.every(function(check) { return check.passed }) ? 'pass' : 'fail', checks: root.checks }));
                stop();
                Qt.quit();
            }
        }
    }
}
