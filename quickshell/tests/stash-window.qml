import QtQuick
import QtQuick.Window
import QtQml
import QtTest
import Quickshell
import Quickshell.Wayland
import qs.services
import qs.features.shelf
import qs.shell
import qs.theme
import "../logic/stash-view.mjs" as StashLogic

// The Stash view in a plain window, on a real Shelf and StashController over a fake config store.
// HOME is the runner's scratch directory, which holds the photos and files the seed points at.
// A StashHost on its own services then opens the same view as the overlay and as a normal window.
ShellRoot {
    id: root
    property TestEvent keys: TestEvent {}
    property int phase: 0
    property int ticks: 0
    property bool stepping: false
    property var checks: []
    property int closes: 0
    property var picks: []
    readonly property string home: Quickshell.env('HOME')
    readonly property real startedAt: Date.now()
    onPhaseChanged: ticks = 0
    function at(seconds) { return new Date(startedAt - seconds * 1000).toISOString(); }
    function file(path) { return 'file://' + root.home + path; }
    function photo(id, index, seconds) {
        return { id: id, uri: file('/Pictures/Stash/photo-' + index + '.png'), label: 'photo-' + index + '.png', addedAt: at(seconds), pinned: false };
    }
    readonly property var seed: ({ schemaVersion: 2, entries: [
        { id: 'pin-note', kind: 'text', uri: '', text: 'Пароль від гостьової мережі', label: 'Пароль від гостьової мережі', addedAt: at(3 * 86400), pinned: true },
        { id: 'old-file', uri: 'file:///tmp/stash-fixture-missing/notes.txt', label: 'notes.txt', addedAt: '', pinned: false },
        { id: 'zip', uri: file('/Downloads/archive.zip'), label: 'archive.zip', addedAt: at(86400 + 60), pinned: false },
        { id: 'song', kind: 'spotify', uri: 'https://open.spotify.com/track/7h2ABjmIKKbT7VBWFM2nZD', label: 'Song of the day', addedAt: at(86400 + 30), pinned: false },
        photo('y-photo-1', 10, 86400 + 20), photo('y-photo-2', 11, 86400 + 10),
        { id: 'report', uri: file('/Documents/report.pdf'), label: 'report.pdf', addedAt: at(40), pinned: false },
        photo('photo-1', 1, 39), photo('photo-2', 2, 38), photo('photo-3', 3, 37), photo('photo-4', 4, 36), photo('photo-5', 5, 35),
        photo('photo-6', 6, 34), photo('photo-7', 7, 33), photo('photo-8', 8, 32), photo('photo-9', 9, 31),
        { id: 'docs', kind: 'link', uri: 'https://example.test/docs/stash', label: 'Pentad Stash docs', addedAt: at(20), pinned: false },
        { id: 'note', kind: 'text', uri: '', text: 'Купити кабель USB-C\nі перехідник', label: 'Купити кабель USB-C', addedAt: at(10), pinned: false }
    ] })
    readonly property int photoCount: 9

    component FakeConfig: QtObject {
        property bool preview: false
        property var seed: ({ schemaVersion: 2, entries: [] })
        property string helperPath: decodeURIComponent(Qt.resolvedUrl('helpers/pentad-files.py').toString().replace(/^file:\/\//, ''))
        property var documents: ({ interface: { language: 'uk' } })
        property int serial: 0
        property int saves: 0
        property int failSaves: 0
        signal commandFinished(string requestId, var result)
        signal documentChanged(string name)
        function reload(name) {
            var requestId = 'read-' + (++serial);
            if (documents.shelf === undefined)
                documents = Object.assign({}, documents, { shelf: seed });
            Qt.callLater(function() { commandFinished(requestId, { ok: true }); });
            return requestId;
        }
        function save(name, value) {
            var requestId = 'save-' + (++serial);
            saves++;
            if (failSaves > 0) {
                failSaves--;
                Qt.callLater(function() { commandFinished(requestId, { ok: false, reason: 'too-large' }); });
                return requestId;
            }
            Qt.callLater(function() {
                documents = Object.assign({}, documents, { [name]: value });
                documentChanged(name);
                commandFinished(requestId, { ok: true });
            });
            return requestId;
        }
    }
    component FakeServices: QtObject {
        id: fake
        required property var config
        function text(uk, en) { return config.documents.interface.language === 'uk' ? uk : en; }
        readonly property Shelf shelf: Shelf { config: fake.config }
        readonly property StashController stash: StashController { config: fake.config }
        readonly property QtObject toolWorkspace: QtObject { property int exports: 0 }
        // The screenshot flow announces a capture; the overlay must be gone from the picture.
        readonly property QtObject popups: QtObject { signal capturePreparing() }
        // Records the call and answers like the portal helper, after the current event.
        readonly property QtObject filePicker: QtObject {
            function pick(options) {
                root.picks = root.picks.concat([{ stashVisible: fake.stash.visible }]);
                Qt.callLater(function() { options.done({ ok: true, uris: [root.file('/Pictures/Stash/picked.png')] }); });
                return true;
            }
        }
    }
    property FakeConfig fakeConfig: FakeConfig { seed: root.seed }
    property FakeConfig emptyConfig: FakeConfig {}
    property FakeServices services: FakeServices { config: root.fakeConfig }
    property FakeServices emptyServices: FakeServices { config: root.emptyConfig }
    // Not a preview config, so setMode() saves interface.stashWindow and the frame follows it.
    readonly property var hostSeed: ({ schemaVersion: 2, entries: [
        { id: 'host-link', kind: 'link', uri: 'https://example.test/stash/host', label: 'Stash host link', addedAt: at(40), pinned: false },
        { id: 'host-report', uri: file('/Documents/report.pdf'), label: 'report.pdf', addedAt: at(30), pinned: false }
    ].concat(Array.from({ length: 9 }, (unused, index) => ({ id: 'host-note-' + index, kind: 'text', uri: '',
        text: 'Номер замовлення ' + (4410 + index), label: 'Номер замовлення ' + (4410 + index), addedAt: at(20 - index), pinned: false }))) })
    property FakeConfig hostConfig: FakeConfig { seed: root.hostSeed }
    property FakeServices hostServices: FakeServices { config: root.hostConfig }
    property var hostStart: ({})

    StashHost { id: host; services: root.hostServices }

    // One window, so the synthetic keys reach it: the stocked view on the left, an empty one on the right.
    FloatingWindow {
        visible: true
        implicitWidth: 1060; implicitHeight: 720
        color: Theme.tokens.surface
        StashView {
            id: view
            width: 520; height: 720
            services: root.services
            framed: true
            onCloseRequested: root.closes++
        }
        StashView { id: emptyView; x: 540; width: 520; height: 420; services: root.emptyServices; framed: true }
    }

    function find(item, name) {
        if (!item) return null;
        if (item.objectName === name) return item;
        const children = Array.prototype.slice.call(item.children || []);
        if (item.contentItem && children.indexOf(item.contentItem) < 0) children.push(item.contentItem);
        for (const child of children) { const found = find(child, name); if (found) return found; }
        return null;
    }
    function rows() { return view.items.filter(item => item.kind === 'row'); }
    // 'overlay' or 'window' for the frame the host has loaded, '' when the Stash is closed.
    function frameKind() { return host.item ? host.item.kind || '' : ''; }
    function rowType(item) {
        return StashLogic.entryType(item.entry, root.services.shelf.files.metadata[item.entry.kind ? item.entry.localUri || '' : item.entry.uri]);
    }
    function settled(condition) { return condition || ++root.ticks > 60; }
    // Opens an entry only when the runner put a recording xdg-open stub on PATH; a real app must never start here.
    function openWithStub(target, id) { return Quickshell.env('PENTAD_FAKE_OPEN') === '1' ? target.openEntry(id) : null; }
    function check(name, passed, detail) { checks.push({ name: name, passed: passed === true, detail: detail || '' }); }
    function finish() {
        console.log('PENTAD_TEST ' + JSON.stringify({
            status: checks.length > 0 && checks.every(item => item.passed) ? 'pass' : 'fail',
            checks: checks
        }));
        Qt.quit();
    }

    Timer {
        interval: 25
        repeat: true
        running: true
        onTriggered: {
            // Synthetic key events process pending events, which can fire this timer again mid-phase.
            if (root.stepping) return;
            root.stepping = true;
            const shelf = root.services.shelf, stash = root.services.stash;
            const photoUris = shelf.entries.filter(entry => /\.png$/.test(entry.uri)).map(entry => entry.uri);
            if (root.phase === 0 && shelf.ready && root.emptyServices.shelf.ready && shelf.entries.length === root.seed.entries.length
                    && root.settled(view.items.length > 0 && photoUris.every(uri => shelf.files.metadata[uri]))) {
                stash.show();
                const titles = view.items.filter(item => item.kind === 'header').map(item => item.title);
                const pinnedHeader = root.find(view, 'stash-section-pinned');
                const composer = root.find(view, 'stash-composer');
                const inputTop = composer.input.mapToItem(composer, 0, 0).y;
                root.check('composer-rests-at-top', Math.abs(inputTop - 8) < 0.5 && composer.height === 36, String(inputTop));
                root.check('sections-rendered', titles[0] === 'Закріплене' && titles[1] === 'Сьогодні' && titles[2] === 'Вчора'
                    && titles[3] === 'Раніше' && !!pinnedHeader && pinnedHeader.visible && pinnedHeader.text === 'Закріплене', JSON.stringify(titles));
                root.phase = 1;
            } else if (root.phase === 1 && root.settled(!!root.find(view, 'stash-photo-strip-today'))) {
                const strip = root.find(view, 'stash-photo-strip-today');
                const overflow = root.find(strip, 'stash-photo-more');
                const shown = strip ? strip.shownCount : -1;
                root.check('photo-strip-shown', !!strip && shown >= 3 && shown < root.photoCount && !!overflow && overflow.visible
                    && overflow.text === '+' + (root.photoCount - shown) && strip.tileHeight === 64,
                    'shown ' + shown + ', overflow ' + (overflow ? overflow.text : 'none'));
                // The screenshot shows the actions of a selected row.
                stash.selectOnly('docs');
                root.phase = 2;
            } else if (root.phase === 2 && ++root.ticks > 8) {
                root.phase = -1;
                view.grabToImage(result => {
                    root.check('stash-window-capture', result.saveToFile(Quickshell.env('PENTAD_ARTIFACT_PATH')));
                    emptyView.grabToImage(empty => {
                        root.check('stash-empty-capture', empty.saveToFile(Quickshell.env('PENTAD_ARTIFACT_PATH') + '.empty.png'));
                        // A list 548 px wide: one strip slot fewer than the list width alone would give.
                        view.width = 560;
                        root.phase = 21;
                    });
                });
            } else if (root.phase === 21 && root.settled(view.stripWidth === 536)) {
                const strip = root.find(view, 'stash-photo-strip-today');
                const rendered = strip.photos.slice(0, strip.shownCount).map(photo => photo.id);
                const navigable = view.navigationOrder.filter(id => /^photo-\d$/.test(id));
                root.check('navigation-matches-rendered-tiles', strip.slots === view.stripSlots && strip.slots === 7
                    && navigable.join(',') === rendered.join(',') && rendered.every(id => !!root.find(strip, 'stash-photo-' + id)),
                    'slots ' + strip.slots + '/' + view.stripSlots + ', navigable ' + navigable.length + ', rendered ' + rendered.length);
                view.width = 520;
                stash.filter = 'link';
                root.phase = 3;
            } else if (root.phase === 3 && root.settled(root.rows().length > 0 && root.rows().every(item => root.rowType(item) === 'link'))) {
                const rows = root.rows();
                root.check('filter-narrows', rows.length === 2 && rows.every(item => root.rowType(item) === 'link')
                    && !view.items.some(item => item.kind === 'strip'), rows.map(item => item.entry.id).join(','));
                stash.filter = 'all';
                stash.query = 'report';
                root.phase = 4;
            } else if (root.phase === 4 && root.settled(root.rows().length === 1)) {
                const rows = root.rows();
                root.check('search-narrows', rows.length === 1 && rows[0].entry.id === 'report' && view.items.length === 2,
                    rows.map(item => item.entry.id).join(','));
                stash.query = '';
                root.phase = 5;
            } else if (root.phase === 5 && root.settled(root.rows().length > 4)) {
                const order = view.navigationOrder;
                stash.selectOnly(order[0]);
                view.focusList();
                root.keys.keyClick(Qt.Key_Down, Qt.NoModifier, 0);
                root.check('keyboard-nav', order.length > 2 && stash.selectedIds.length === 1 && stash.selectedIds[0] === order[1],
                    JSON.stringify(stash.selectedIds) + ' / ' + order.slice(0, 3).join(','));
                // A pointer click carries its modifiers; the right button opens the item menu.
                const reportRow = root.find(view, 'stash-row-report');
                stash.selectOnly('note');
                root.keys.mouseClick(reportRow, 120, 22, Qt.LeftButton, Qt.ControlModifier, -1);
                root.check('ctrl-click-extends-selection', stash.selectedIds.slice().sort().join(',') === 'note,report',
                    JSON.stringify(stash.selectedIds));
                root.keys.mouseClick(reportRow, 120, 22, Qt.RightButton, Qt.NoModifier, -1);
                root.check('right-click-opens-menu', view.itemMenu.visible && view.itemMenu.entryId === 'report');
                view.itemMenu.close();
                view.focusList();
                root.keys.keyClick(Qt.Key_V, Qt.ControlModifier, 0);
                root.phase = 51;
            } else if (root.phase === 51 && root.settled(shelf.entries.some(entry => entry.text === 'Вставлено з буфера'))) {
                root.check('ctrl-v-pastes', shelf.entries.some(entry => entry.kind === 'text' && entry.text === 'Вставлено з буфера'));
                // P on the Ukrainian layout: the key arrives as the Cyrillic letter.
                stash.selectOnly('docs');
                view.focusList();
                root.keys.keySequence('з');
                root.phase = 6;
            } else if (root.phase === 6 && root.settled(view.items.some(item => item.kind === 'row' && item.sectionId === 'pinned' && item.entry.id === 'docs'))) {
                const docs = shelf.entries.find(entry => entry.id === 'docs');
                root.check('pin-moves-row', !!docs && docs.pinned === true && root.fakeConfig.documents.shelf.entries.find(entry => entry.id === 'docs').pinned === true
                    && view.items.some(item => item.kind === 'row' && item.sectionId === 'pinned' && item.entry.id === 'docs')
                    && !view.items.some(item => item.kind === 'row' && item.sectionId === 'today' && item.entry.id === 'docs'));
                view.focusList();
                root.keys.keyClick(Qt.Key_Slash, Qt.NoModifier, 0);
                const search = root.find(view, 'stash-search');
                const searchFocused = search.activeFocus;
                for (const character of 'zip') root.keys.keyClickChar(character, Qt.NoModifier, 0);
                root.check('slash-focuses-search', searchFocused && stash.query === 'zip', JSON.stringify(stash.query));
                stash.query = '';
                view.focusList();
                root.keys.keyClickChar('.', Qt.NoModifier, 0);
                root.check('ukrainian-slash-focuses-search', search.activeFocus && stash.query === '', JSON.stringify(stash.query));
                stash.query = 'кабель';
                view.focusList();
                root.keys.keyClick(Qt.Key_Escape, Qt.NoModifier, 0);
                const cleared = stash.query === '' && root.closes === 0;
                root.keys.keyClick(Qt.Key_Escape, Qt.NoModifier, 0);
                root.check('esc-clears-search-first', cleared && root.closes === 1, 'query "' + stash.query + '", closes ' + root.closes);
                const input = root.find(view, 'stash-composer-input');
                input.forceActiveFocus();
                for (const character of 'Milk') root.keys.keyClickChar(character, Qt.NoModifier, 0);
                root.keys.keyClick(Qt.Key_Return, Qt.ShiftModifier, 0);
                root.keys.keyClickChar('x', Qt.NoModifier, 0);
                root.check('composer-shift-enter-newline', stash.draft === 'Milk\nx', JSON.stringify(stash.draft));
                root.keys.keyClick(Qt.Key_Return, Qt.NoModifier, 0);
                root.phase = 7;
            } else if (root.phase === 7 && root.settled(stash.draft === '' && root.rows().some(item => item.entry.text === 'Milk\nx'))) {
                const input = root.find(view, 'stash-composer-input');
                root.check('composer-adds-note', shelf.entries.some(entry => entry.kind === 'text' && entry.text === 'Milk\nx')
                    && stash.draft === '' && input.text === '' && root.rows().some(item => item.entry.text === 'Milk\nx'),
                    JSON.stringify({ draft: stash.draft, input: input.text, rows: root.rows().length }));
                // Two selected rows disappear behind the photo filter; Delete must not reach them.
                stash.selectedIds = ['docs', 'note'];
                stash.filter = 'photo';
                root.hostStart = { saves: root.fakeConfig.saves };
                root.phase = 71;
            } else if (root.phase === 71 && root.settled(!root.rows().length && view.items.some(item => item.kind === 'strip')) && ++root.ticks > 8) {
                root.hostStart.visibleBefore = view.visibleSelection.length;
                view.focusList();
                root.keys.keyClick(Qt.Key_Delete, Qt.NoModifier, 0);
                view.pinSelected();
                root.phase = 72;
            } else if (root.phase === 72 && ++root.ticks > 8) {
                root.check('hidden-selection-takes-no-action', root.hostStart.visibleBefore === 0
                    && !!shelf.entries.find(entry => entry.id === 'docs') && !!shelf.entries.find(entry => entry.id === 'note')
                    && shelf.entries.find(entry => entry.id === 'note').pinned === false
                    && root.fakeConfig.saves === root.hostStart.saves && stash.selectedIds.join(',') === 'docs,note',
                    JSON.stringify({ visible: root.hostStart.visibleBefore, selected: stash.selectedIds, saves: [root.hostStart.saves, root.fakeConfig.saves] }));
                stash.filter = 'all';
                root.phase = 73;
            } else if (root.phase === 73 && root.settled(root.rows().length > 4 && view.visibleSelection.length === 2)) {
                // Back in view, the same two rows are selected again and act as before.
                root.check('selection-survives-filter', view.visibleSelection.join(',') === 'docs,note', JSON.stringify(view.visibleSelection));
                stash.clearSelection();
                const input = root.find(view, 'stash-composer-input');
                root.fakeConfig.failSaves = 1;
                stash.draft = 'Ще одна нотатка';
                input.forceActiveFocus();
                root.keys.keyClick(Qt.Key_Return, Qt.NoModifier, 0);
                root.phase = 8;
            } else if (root.phase === 8 && root.settled(view.message !== '')) {
                const caption = root.find(view, 'stash-message');
                root.check('too-large-message', !!caption && caption.visible && caption.text === 'Сховок переповнений. Приберіть щось, щоб додати нове.'
                    && Qt.colorEqual(caption.color, Theme.tokens.error) && stash.draft === 'Ще одна нотатка', caption ? caption.text : 'no caption');
                root.find(view, 'stash-composer-add').clicked();
                root.phase = 9;
            } else if (root.phase === 9 && root.settled(shelf.entries.some(entry => entry.label === 'picked.png'))) {
                root.check('plus-picks-files', root.picks.length === 1 && root.picks[0].stashVisible === false && stash.visible === true
                    && shelf.entries.some(entry => entry.label === 'picked.png'), JSON.stringify(root.picks));
                const zone = root.find(emptyView, 'stash-drop-zone');
                const fullZone = root.find(view, 'stash-drop-zone');
                root.check('empty-drop-zone', !!zone && zone.visible && zone.opacity === 1 && emptyView.items.length === 0
                    && (!fullZone || !fullZone.visible));
                // A long draft stays inside the composer and scrolls to keep the cursor in view.
                const input = root.find(view, 'stash-composer-input');
                stash.draft = Array.from({ length: 12 }, (unused, index) => 'Рядок ' + (index + 1)).join('\n');
                input.forceActiveFocus();
                input.cursorPosition = input.length;
                root.phase = 10;
            } else if (root.phase === 10 && ++root.ticks > 8) {
                const composer = root.find(view, 'stash-composer');
                const flick = composer.scroller;
                root.check('composer-stays-bounded', composer.height <= 116 && composer.scroller.clip
                    && flick.contentHeight > flick.height && flick.contentY > 0
                    && composer.mapToItem(view, 0, composer.height).y <= view.height,
                    JSON.stringify({ height: composer.height, content: flick.contentHeight, y: flick.contentY }));
                // The fake clipboard answers the next paste with an owned image and the one after with nothing.
                view.pasteClipboard();
                view.pasteClipboard();
                root.phase = 101;
            } else if (root.phase === 101 && root.settled(view.messageClipboard && view.message !== '')) {
                const caption = root.find(view, 'stash-message');
                root.check('empty-clipboard-caption', !!caption && caption.visible && caption.text === 'Буфер обміну порожній.'
                    && view.messageReason === 'empty' && shelf.entries.some(entry => entry.owned === true && entry.label === 'clip-fixture.png'),
                    JSON.stringify({ text: caption ? caption.text : null, reason: view.messageReason }));
                root.phase = 11;
            } else if (root.phase === 11 && root.settled(root.hostServices.shelf.ready
                    && root.hostServices.shelf.entries.length === root.hostSeed.entries.length)) {
                // The shortcut opens the overlay: a centered 520 px frame that takes the keyboard.
                root.hostServices.stash.toggle();
                root.phase = 12;
            } else if (root.phase === 12 && root.settled(root.frameKind() === 'overlay' && host.item.view.activeFocus)) {
                const overlay = host.item;
                const frame = overlay ? overlay.frame : null;
                root.check('overlay-opens', root.frameKind() === 'overlay' && overlay.view.activeFocus && overlay.view.framed
                    && frame.width === 520 && frame.height <= Math.round(overlay.height * 0.7)
                    && frame.height >= Math.min(overlay.view.implicitHeight, Math.round(overlay.height * 0.7))
                    && Math.abs(frame.x + frame.width / 2 - overlay.width / 2) < 1 && Math.abs(frame.y + frame.height / 2 - overlay.height / 2) < 1
                    && overlay.WlrLayershell.keyboardFocus === WlrKeyboardFocus.Exclusive,
                    JSON.stringify({ kind: root.frameKind(), focus: overlay ? overlay.view.activeFocus : null,
                        frame: frame ? [frame.x, frame.y, frame.width, frame.height] : null,
                        window: overlay ? [overlay.width, overlay.height] : null }));
                root.phase = -1;
                const next = () => {
                    // Narrowing the list leaves the frame, and with it the search field, where it was.
                    root.hostStart = frame ? { y: frame.y, height: frame.height, content: overlay.view.implicitHeight } : {};
                    root.hostServices.stash.filter = 'link';
                    root.phase = 30;
                };
                const grabbing = !!frame && frame.grabToImage(result => {
                    root.check('stash-overlay-capture', result.saveToFile(Quickshell.env('PENTAD_ARTIFACT_PATH') + '.overlay.png'));
                    next();
                });
                if (!grabbing) {
                    root.check('stash-overlay-capture', false, 'not grabbed');
                    next();
                }
            } else if (root.phase === 30 && root.settled(!!host.item && host.item.view.items.filter(item => item.kind === 'row').length === 1)) {
                const overlay = host.item;
                const frame = overlay ? overlay.frame : null;
                root.check('overlay-keeps-place-while-filtering', !!frame && overlay.view.implicitHeight < root.hostStart.content
                    && frame.y === root.hostStart.y && frame.height === root.hostStart.height,
                    JSON.stringify({ before: root.hostStart, after: frame ? { y: frame.y, height: frame.height, content: overlay.view.implicitHeight } : null }));
                root.hostServices.stash.filter = 'all';
                root.keys.keyClick(Qt.Key_Escape, Qt.NoModifier, 0);
                root.phase = 13;
            } else if (root.phase === 13 && root.settled(!root.hostServices.stash.visible && !host.item)) {
                root.check('overlay-esc-closes', !root.hostServices.stash.visible && !host.item && root.hostServices.stash.mode === 'overlay');
                // State set in the overlay must survive overlay → window → overlay.
                const stash = root.hostServices.stash;
                stash.show();
                stash.query = 'report';
                stash.filter = 'file';
                stash.selectOnly('host-report');
                stash.draft = 'Незбережена нотатка';
                root.hostStart = { query: stash.query, filter: stash.filter, selected: stash.selectedIds.join(','), draft: stash.draft };
                root.phase = 14;
            } else if (root.phase === 14 && root.settled(root.frameKind() === 'overlay')) {
                const detach = root.find(host.item ? host.item.view : null, 'stash-detach');
                if (detach) detach.clicked();
                root.phase = 15;
            } else if (root.phase === 15 && root.settled(root.frameKind() === 'window' && !!host.item.view.Window.window
                    && host.item.view.Window.window.visible)) {
                const floating = host.item;
                root.check('window-frame', root.frameKind() === 'window' && root.hostServices.stash.mode === 'window'
                    && floating.title === 'Сховок' && floating.minimumSize.width === 400 && floating.minimumSize.height === 360
                    && floating.width === 520 && floating.height === 640 && !floating.view.framed,
                    floating ? JSON.stringify({ title: floating.title, size: [floating.width, floating.height] }) : 'no window');
                root.phase = -1;
                const next = () => {
                    const detach = root.find(host.item ? host.item.view : null, 'stash-detach');
                    if (detach) detach.clicked();
                    root.phase = 16;
                };
                const grabbing = !!floating && floating.view.grabToImage(result => {
                    root.check('stash-window-frame-capture', result.saveToFile(Quickshell.env('PENTAD_ARTIFACT_PATH') + '.window.png'));
                    next();
                });
                if (!grabbing) {
                    root.check('stash-window-frame-capture', false, 'not grabbed');
                    next();
                }
            } else if (root.phase === 16 && root.settled(root.frameKind() === 'overlay')) {
                const stash = root.hostServices.stash;
                const view = host.item ? host.item.view : null;
                const now = { query: stash.query, filter: stash.filter, selected: stash.selectedIds.join(','), draft: stash.draft };
                const search = root.find(view, 'stash-search');
                const input = root.find(view, 'stash-composer-input');
                root.check('mode-switch-keeps-state', root.frameKind() === 'overlay' && JSON.stringify(now) === JSON.stringify(root.hostStart)
                    && now.selected === 'host-report' && !!search && search.text === 'report' && !!input && input.text === 'Незбережена нотатка',
                    JSON.stringify({ before: root.hostStart, after: now }));
                stash.setMode('window');
                root.phase = 17;
            } else if (root.phase === 17 && root.settled(root.frameKind() === 'window' && !!host.item.view.Window.window
                    && host.item.view.Window.window.visible)) {
                // The shortcut on an open window raises it instead of hiding it.
                const floating = host.item;
                root.hostServices.stash.toggle();
                root.check('window-toggle-keeps-window', root.hostServices.stash.visible && host.item === floating && root.frameKind() === 'window',
                    JSON.stringify({ visible: root.hostServices.stash.visible, frame: root.frameKind(), focus: !!host.item && host.item.view.activeFocus }));
                // Opening an entry from the window leaves the window where it is.
                const openedFromWindow = root.openWithStub(floating.view, 'host-link');
                root.check('window-stays-after-open', openedFromWindow === true && root.hostServices.stash.visible && host.item === floating,
                    JSON.stringify({ opened: openedFromWindow, visible: root.hostServices.stash.visible }));
                // The compositor closing the window (its close button, a keybind) hides the Stash, not the mode.
                // The backing window exists one event after the frame is loaded.
                const backing = host.item ? host.item.view.Window.window : null;
                if (backing) backing.close();
                root.phase = 18;
            } else if (root.phase === 18 && root.settled(!root.hostServices.stash.visible && !host.item)) {
                const stash = root.hostServices.stash;
                root.check('window-close-keeps-mode', !stash.visible && !host.item && stash.mode === 'window',
                    JSON.stringify({ visible: stash.visible, mode: stash.mode, frame: root.frameKind() }));
                stash.setMode('overlay');
                root.phase = 19;
            } else if (root.phase === 19 && root.settled(root.hostServices.stash.mode === 'overlay')) {
                root.hostServices.stash.show();
                root.phase = 20;
            } else if (root.phase === 20 && root.settled(root.frameKind() === 'overlay' && host.item.view.activeFocus)) {
                // A row or photo starts a native drag out: the overlay lets the pointer and keyboard through.
                root.hostServices.stash.exporting = true;
                root.hostServices.stash.dragging = true;
                root.phase = 22;
            } else if (root.phase === 22 && root.settled(!!host.item && host.item.frame.opacity < 0.2)) {
                const overlay = host.item;
                root.check('export-pass-through', !!overlay && overlay.frame.opacity < 0.2 && overlay.mask.width === 0 && overlay.mask.height === 0
                    && overlay.WlrLayershell.keyboardFocus === WlrKeyboardFocus.None,
                    overlay ? JSON.stringify({ opacity: overlay.frame.opacity, mask: [overlay.mask.width, overlay.mask.height],
                        keyboard: overlay.WlrLayershell.keyboardFocus }) : 'no overlay');
                // Drop, cancel (Esc) and Drag.onDragFinished all end in exporting = dragging = false.
                root.hostServices.stash.dragging = false;
                root.hostServices.stash.exporting = false;
                root.phase = 23;
            } else if (root.phase === 23 && root.settled(!!host.item && host.item.frame.opacity === 1)) {
                const overlay = host.item;
                const frame = overlay ? overlay.frame : null;
                const mask = overlay ? overlay.mask : null;
                root.check('export-cancel-restores', !!overlay && frame.opacity === 1
                    && mask.x <= frame.x && mask.y <= frame.y && mask.x + mask.width >= frame.x + frame.width && mask.y + mask.height >= frame.y + frame.height
                    && overlay.WlrLayershell.keyboardFocus === WlrKeyboardFocus.Exclusive,
                    overlay ? JSON.stringify({ opacity: frame.opacity, mask: [mask.x, mask.y, mask.width, mask.height],
                        keyboard: overlay.WlrLayershell.keyboardFocus }) : 'no overlay');
                // A press on the frame's empty header keeps the Stash.
                if (frame) root.keys.mouseClick(frame, 200, 24, Qt.LeftButton, Qt.NoModifier, -1);
                root.hostStart = { keptOpen: root.hostServices.stash.visible && root.frameKind() === 'overlay' };
                // Opening an entry hands the screen to its app: the overlay hides.
                root.hostStart.opened = overlay ? root.openWithStub(overlay.view, 'host-link') : null;
                root.phase = 231;
            } else if (root.phase === 231 && root.settled(!root.hostServices.stash.visible && !host.item)) {
                root.check('overlay-hides-after-open', root.hostStart.opened === true && !root.hostServices.stash.visible && !host.item
                    && root.hostServices.stash.mode === 'overlay',
                    JSON.stringify({ opened: root.hostStart.opened, visible: root.hostServices.stash.visible, frame: root.frameKind() }));
                root.hostServices.stash.show();
                root.phase = 232;
            } else if (root.phase === 232 && root.settled(root.frameKind() === 'overlay' && host.item.view.activeFocus)) {
                // A screenshot is about to be taken: the overlay leaves the picture.
                root.hostServices.popups.capturePreparing();
                root.phase = 233;
            } else if (root.phase === 233 && root.settled(!root.hostServices.stash.visible && !host.item)) {
                root.check('overlay-hides-for-screenshot', !root.hostServices.stash.visible && !host.item,
                    JSON.stringify({ visible: root.hostServices.stash.visible, frame: root.frameKind() }));
                root.hostServices.stash.show();
                root.phase = 234;
            } else if (root.phase === 234 && root.settled(root.frameKind() === 'overlay' && host.item.view.activeFocus)) {
                // A press beside the frame closes it.
                const frame = host.item ? host.item.frame : null;
                if (frame) root.keys.mousePress(frame, -24, -24, Qt.LeftButton, Qt.NoModifier, -1);
                root.phase = 24;
            } else if (root.phase === 24 && root.settled(!root.hostServices.stash.visible && !host.item)) {
                root.check('overlay-press-outside-closes', root.hostStart.keptOpen === true && !root.hostServices.stash.visible && !host.item,
                    JSON.stringify({ keptOpen: root.hostStart.keptOpen, visible: root.hostServices.stash.visible, frame: root.frameKind() }));
                // A drag cannot outlive the window: hiding the Stash ends the export state too.
                root.hostServices.stash.exporting = true;
                root.hostServices.stash.dragging = true;
                root.hostServices.stash.hide();
                root.check('hide-ends-export', !root.hostServices.stash.exporting && !root.hostServices.stash.dragging && !host.item);
                root.finish();
                stop();
            }
            root.stepping = false;
        }
    }
}
