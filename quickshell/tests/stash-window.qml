import QtQuick
import QtQml
import QtTest
import Quickshell
import qs.services
import qs.features.shelf
import qs.theme
import "../logic/stash-view.mjs" as StashLogic

// The Stash view in a plain window, on a real Shelf and StashController over a fake config store.
// HOME is the runner's scratch directory, which holds the photos and files the seed points at.
ShellRoot {
    id: root
    property TestEvent keys: TestEvent {}
    property int phase: 0
    property int ticks: 0
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
        StashView { id: emptyView; x: 540; width: 520; height: 420; services: root.emptyServices }
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
    function rowType(item) {
        return StashLogic.entryType(item.entry, root.services.shelf.files.metadata[item.entry.kind ? item.entry.localUri || '' : item.entry.uri]);
    }
    function settled(condition) { return condition || ++root.ticks > 60; }
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
            const shelf = root.services.shelf, stash = root.services.stash;
            const photoUris = shelf.entries.filter(entry => /\.png$/.test(entry.uri)).map(entry => entry.uri);
            if (root.phase === 0 && shelf.ready && root.emptyServices.shelf.ready && shelf.entries.length === root.seed.entries.length
                    && root.settled(view.items.length > 0 && photoUris.every(uri => shelf.files.metadata[uri]))) {
                stash.show();
                const titles = view.items.filter(item => item.kind === 'header').map(item => item.title);
                const pinnedHeader = root.find(view, 'stash-section-pinned');
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
                        stash.filter = 'link';
                        root.phase = 3;
                    });
                });
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
                stash.selectOnly('docs');
                view.focusList();
                root.keys.keyClick(Qt.Key_P, Qt.NoModifier, 0);
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
                root.finish();
                stop();
            }
        }
    }
}
