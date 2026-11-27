import QtQuick
import QtQuick.Window
import QtQml
import QtTest
import Quickshell
import Quickshell.Wayland
import qs.services
import qs.shell
import qs.theme
import qs.features.cheatsheet
import "../logic/keybinds.mjs" as KeybindsLogic
import "../logic/keybinds-sample.mjs" as KeybindsSample
import "../logic/keyboard-map.mjs" as KeyboardMap
import "../logic/keybind-hues.mjs" as KeybindHues

// The keybind cheatsheet overlay on the preview sample: group cards, keycaps, the search, "Show
// all", the modifier, duplicate and key chips, the keyboard view, the Super key's logo, the
// reference for the focused app, Ctrl+Tab, both languages, and every way it closes. Windows the
// size of the card on other outputs show the same view at the end: 360 px, 600 px, a 2560 × 1440
// output and a 1080 × 1920 portrait one. Separate Keybinds adapters outside preview run programs
// that are not hyprctl (a missing one, `false`, printf, head) for the reader's own paths; nothing
// here runs hyprctl.
ShellRoot {
    id: root
    property TestEvent keys: TestEvent {}
    property int phase: 0
    property int ticks: 0
    property bool stepping: false
    property var checks: []
    property var visibility: []
    property var start: ({})
    property bool narrowShown: false
    property int narrowWidth: 360
    property int narrowHeight: 860
    readonly property string pentadLogo: '/assets/icons/keys/super-pentad-symbolic.svg'
    // Group hues seen before a close, to compare after the reopening.
    property string savedHues: ''
    readonly property var sample: KeybindsLogic.parseBinds(KeybindsSample.SAMPLE_BINDS)
    readonly property string capture: Quickshell.env('PENTAD_ARTIFACT_PATH') || ''
    onPhaseChanged: ticks = 0
    // The runner's --appearance and --reduced-motion choices.
    Component.onCompleted: {
        const accent = Quickshell.env('PENTAD_GALLERY_ACCENT') || '#869677';
        Theme.resolve({
            appearance: Quickshell.env('PENTAD_GALLERY_APPEARANCE') === 'light' ? 'light' : 'dark',
            accent: /^#[0-9a-f]{6}$/i.test(accent) ? accent : '#869677',
            fontFamily: 'Geist',
            reducedMotion: Quickshell.env('PENTAD_GALLERY_REDUCED_MOTION') === '1'
        });
    }

    component FakePopups: QtObject {
        property string surface: ''
        property int closes: 0
        property var calls: []
        signal changed
        signal capturePreparing
        function close() {
            closes++;
        }
        function hostVisibility(key, visible) {
            calls = calls.concat([key + ':' + visible]);
        }
    }
    component FakeServices: QtObject {
        id: fake
        property bool ukrainian: false
        property bool previewBinds: true
        property var command: ['pentad-fixture-unused']
        function text(uk, en) {
            return ukrainian ? uk : en;
        }
        readonly property CheatsheetController cheatsheet: CheatsheetController {}
        readonly property Keybinds keybinds: Keybinds {
            preview: fake.previewBinds
            safeMode: true
            command: fake.command
            active: fake.cheatsheet.open
        }
        readonly property FakePopups popups: FakePopups {}
    }
    property FakeServices services: FakeServices {}
    // Outside preview, with a reader that cannot start: the cheatsheet says Hyprland is not answering.
    property FakeServices brokenServices: FakeServices {
        previewBinds: false
        command: ['pentad-fixture-missing-hyprctl']
    }
    // Far more binds than fit: the card stops at 86 % of the screen and the list scrolls.
    property FakeServices longServices: FakeServices {
        previewBinds: false
        command: ['printf', '%s', JSON.stringify(Array.from({ length: 240 }, (unused, index) => ({
            modmask: 64, key: 'code:' + (100 + index), keycode: 0, dispatcher: 'exec', arg: 'app-' + index,
            description: 'Group ' + (index % 8) + ': Open application number ' + index, submap: ''
        })))]
    }
    property Keybinds printed: Keybinds {
        command: ['printf', '%s', '[{"modmask":64,"key":"Q","keycode":0,"dispatcher":"killactive","arg":"","description":"Window: Close","submap":""},{"modmask":0,"key":"Super_L","keycode":0,"dispatcher":"__lua","arg":"4","description":"","submap":""}]']
    }
    property Keybinds failing: Keybinds {
        command: ['false']
    }
    property Keybinds oversized: Keybinds {
        command: ['head', '-c', '1100000', '/dev/zero']
    }

    CheatsheetHost {
        id: host
        services: root.services
    }
    CheatsheetHost {
        id: brokenHost
        services: root.brokenServices
    }
    CheatsheetHost {
        id: longHost
        services: root.longServices
    }
    // The view as the card of other outputs (360 px, the narrowest it supports, 600 px, and the
    // cards of a 2560 × 1440 and a 1080 × 1920 output), created only for the last captures. The
    // private compositor keeps a window within its 1280 × 1080 output, so a larger card overflows
    // its window and is captured from the item itself. The host would cap the card's height there.
    Loader {
        id: narrowLoader
        active: root.narrowShown
        sourceComponent: FloatingWindow {
            readonly property alias view: narrowView
            readonly property alias frame: narrowFrame
            screen: Quickshell.screens.length > 0 ? Quickshell.screens[0] : null
            visible: true
            implicitWidth: Math.min(root.narrowWidth, 1200)
            implicitHeight: Math.min(root.narrowHeight, 1000)
            minimumSize: Qt.size(implicitWidth, implicitHeight)
            maximumSize: minimumSize
            color: Theme.tokens.surface
            // The card's own fill, so the capture shows what the overlay would.
            // As tall as its content up to the output's limit, as the host's card.
            Rectangle {
                id: narrowFrame
                width: root.narrowWidth
                height: Math.min(root.narrowHeight, Math.max(1, Math.ceil(narrowView.implicitHeight)))
                color: Theme.tokens.surface
                CheatsheetView {
                    id: narrowView
                    anchors.fill: parent
                    services: root.services
                    heightLimit: root.narrowHeight
                }
            }
        }
    }

    function find(item, name) {
        if (!item)
            return null;
        if (item.objectName === name)
            return item;
        const children = Array.prototype.slice.call(item.children || []);
        if (item.contentItem && children.indexOf(item.contentItem) < 0)
            children.push(item.contentItem);
        for (const child of children) {
            const found = find(child, name);
            if (found)
                return found;
        }
        return null;
    }
    function findAll(item, test, found) {
        const list = found || [];
        if (!item)
            return list;
        if (test(item))
            list.push(item);
        const children = Array.prototype.slice.call(item.children || []);
        if (item.contentItem && children.indexOf(item.contentItem) < 0)
            children.push(item.contentItem);
        for (const child of children)
            findAll(child, test, list);
        return list;
    }
    function overlay() {
        return host.overlay;
    }
    function view() {
        return host.overlay ? host.overlay.view : null;
    }
    function groupBlocks(target) {
        return findAll(target, item => /^cheatsheet-group-/.test(item.objectName) && item.objectName !== 'cheatsheet-group-title');
    }
    function rowTexts(target) {
        return findAll(target, item => item.objectName === 'cheatsheet-row').map(row => {
            const caps = findAll(row, item => item.objectName === 'cheatsheet-keycap').map(cap => cap.label);
            const label = find(row, 'cheatsheet-description');
            return caps.join('+') + ' | ' + (label ? label.text : '');
        });
    }
    // The keys of the keyboard map by their layout id.
    function keyItems(target) {
        const byId = {};
        for (const item of findAll(target, item => item.objectName === 'cheatsheet-keyboard-key'))
            byId[item.keyId] = item;
        return byId;
    }
    function click(item) {
        if (item)
            root.keys.mouseClick(item, item.width / 2, item.height / 2, Qt.LeftButton, Qt.NoModifier, -1);
    }
    function sheetSegment(target, id) {
        return find(target, 'cheatsheet-sheet-' + target.sheetOptions.findIndex(option => option.value === id));
    }
    function visibleChips(target) {
        return findAll(find(target, 'cheatsheet-chips'), item => /^cheatsheet-(mod-|duplicates|key-chip)/.test(item.objectName) && item.visible)
            .map(item => item.objectName);
    }
    function modsAre(list) {
        return JSON.stringify(root.services.cheatsheet.mods) === JSON.stringify(list);
    }
    function appearance() {
        return Theme.config.appearance === 'light' ? 'light' : 'dark';
    }
    // The "Key shortcuts" tiles as "keys | action".
    function shortcutTexts(target) {
        return findAll(target, item => item.objectName === 'cheatsheet-shortcut').map(tile => tile.combo + ' | ' + tile.action);
    }
    function isKeycap(item) {
        return !!item && String(item).indexOf('PentadKeycap') === 0;
    }
    // A Loader that drew a logo: active, with the SVG loaded.
    function logoLoaded(loader) {
        const icon = loader && loader.active ? loader.item : null;
        const glyph = icon && icon.imageStatus !== undefined ? icon : icon ? root.findAll(icon, item => item.imageStatus !== undefined)[0] : null;
        return !!glyph && glyph.imageStatus === Image.Ready && String(glyph.source).endsWith(root.pentadLogo);
    }
    // The Super keycaps of the list: the logo in place of the word, which stays their text.
    function superCaps(target) {
        return root.findAll(target, item => item.objectName === 'cheatsheet-keycap' && item.label === 'Super');
    }
    function capShowsLogo(cap) {
        return cap.text === 'Super' && String(cap.icon).endsWith(root.pentadLogo) && !cap.legend.visible
            && root.logoLoaded(root.find(cap, 'keycap-icon'));
    }
    function capShowsWord(cap) {
        return cap.text === 'Super' && cap.icon === '' && cap.legend.visible && cap.legend.text === 'Super'
            && !root.find(cap, 'keycap-icon').active;
    }
    function grabItem(item, suffix, next) {
        const grabbing = root.capture !== '' && !!item && item.grabToImage(result => {
            root.check('capture' + suffix, result.saveToFile(root.capture + suffix), root.capture + suffix);
            next();
        });
        if (!grabbing) {
            root.check('capture' + suffix, false, 'not grabbed');
            next();
        }
    }
    function settled(condition) {
        return condition || ++root.ticks > 80;
    }
    function check(name, passed, detail) {
        checks.push({
            name: name,
            passed: passed === true,
            detail: detail || ''
        });
    }
    function grab(suffix, next) {
        const frame = host.overlay ? host.overlay.frame : brokenHost.overlay ? brokenHost.overlay.frame : null;
        const grabbing = root.capture !== '' && !!frame && frame.grabToImage(result => {
            root.check('capture' + (suffix || '.en'), result.saveToFile(root.capture + suffix), root.capture + suffix);
            next();
        });
        if (!grabbing) {
            root.check('capture' + (suffix || '.en'), false, 'not grabbed');
            next();
        }
    }
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
            if (root.stepping)
                return;
            root.stepping = true;
            const sheet = root.services.cheatsheet;
            const binds = root.services.keybinds;
            const view = root.view();
            if (root.phase === 0 && ++root.ticks > 4) {
                root.check('closed-has-no-window', !host.overlay && binds.state.kind === 'loading', JSON.stringify(binds.state));
                // The shortcut and `pentad cheatsheet toggle` both end here.
                sheet.toggle();
                root.phase = 1;
            } else if (root.phase === 1 && root.settled(!!view && binds.state.kind === 'ready' && view.searchField.activeFocus
                    && root.groupBlocks(view).length > 0)) {
                const window = root.overlay();
                const frame = window ? window.frame : null;
                root.check('overlay-opens', !!frame && frame.height <= KeybindsLogic.cardHeight(window.height)
                    && Math.abs(frame.x + frame.width / 2 - window.width / 2) < 1 && Math.abs(frame.y + frame.height / 2 - window.height / 2) < 1
                    && window.WlrLayershell.keyboardFocus === WlrKeyboardFocus.Exclusive && window.WlrLayershell.layer === WlrLayer.Overlay
                    && view.searchField.activeFocus && root.services.popups.closes === 1
                    && JSON.stringify(root.services.popups.calls) === JSON.stringify(['cheatsheet:true']),
                    JSON.stringify({ frame: frame ? [frame.x, frame.y, frame.width, frame.height] : null,
                        window: window ? [window.width, window.height] : null, focus: view.searchField.activeFocus,
                        closes: root.services.popups.closes, calls: root.services.popups.calls }));
                const visible = KeybindsLogic.filterBinds(root.sample.groups, '');
                const blocks = root.groupBlocks(view).map(block => block.objectName.replace('cheatsheet-group-', ''));
                root.check('groups-render', JSON.stringify(blocks.slice().sort()) === JSON.stringify(visible.map(group => group.id).sort())
                    && view.columnCount === 3 && view.columns.length === 3, JSON.stringify({ blocks: blocks, columns: view.columnCount }));
                const windows = root.find(view, 'cheatsheet-group-windows');
                const rows = root.rowTexts(windows);
                const caps = root.findAll(windows, item => item.objectName === 'cheatsheet-keycap');
                // Keycaps are the shared PentadKeycap. Only the last keycap of a row, the main key,
                // carries the group's hue.
                const windowsHue = view.hueColors.windows;
                const mainCaps = root.findAll(windows, item => item.objectName === 'cheatsheet-keys')
                    .map(flow => root.findAll(flow, item => item.objectName === 'cheatsheet-keycap')).map(list => list[list.length - 1]);
                root.check('keycaps-render', rows[0] === 'Super+Q | killactive' && rows.indexOf('Super+← | movefocus l') >= 0
                    && rows.indexOf('Super+LMB | movewindow') >= 0 && caps.length > 0
                    && caps.every(cap => root.isKeycap(cap))
                    && mainCaps.length === rows.length && mainCaps.every(cap => Qt.colorEqual(cap.hue, windowsHue))
                    && caps.filter(cap => mainCaps.indexOf(cap) < 0).every(cap => cap.hue.a === 0), JSON.stringify(rows.slice(0, 4)));
                const cards = root.groupBlocks(view);
                // Each group has its hue: the heading is set in it and the main keys share it;
                // neighbouring groups differ.
                const titleOf = id => root.find(root.find(view, 'cheatsheet-group-' + id), 'cheatsheet-group-title');
                const expectedHues = KeybindHues.hueColors(root.sample.groups, root.appearance());
                const ids = root.sample.groups.map(group => group.id);
                root.check('group-hues', ids.every(id => Qt.colorEqual(view.hueColors[id], expectedHues[id]))
                    && Qt.colorEqual(titleOf('windows').color, windowsHue) && !Qt.colorEqual(titleOf('windows').color, titleOf('launch').color)
                    && !Qt.colorEqual(titleOf('group:pentad').color, titleOf('windows').color)
                    && ids.slice(1).every((id, index) => view.hueColors[id] !== view.hueColors[ids[index]]),
                    JSON.stringify(view.hueColors));
                // The "Key shortcuts" strip tops the list: the Pentad group's first described binds,
                // one per description, the main key in the group's hue.
                const strip = root.find(view, 'cheatsheet-shortcuts');
                const tiles = root.findAll(view, item => item.objectName === 'cheatsheet-shortcut');
                const firstCard = cards.map(block => block.mapToItem(view, 0, 0).y).sort((a, b) => a - b)[0];
                root.check('shortcuts-strip', view.shortcutsShown && !!strip && strip.title.text === 'Key shortcuts'
                    && JSON.stringify(root.shortcutTexts(view)) === JSON.stringify(['Super | Search applications', 'Super+Tab | Workspace overview',
                        'Super+V | Clipboard history', 'Super+. | Emoji'])
                    && tiles.every(tile => Qt.colorEqual(tile.hue, view.hueColors['group:pentad']))
                    && strip.mapToItem(view, 0, 0).y + strip.height < firstCard,
                    JSON.stringify(root.shortcutTexts(view)));
                const pentad = root.rowTexts(root.find(view, 'cheatsheet-group-group:pentad'));
                root.check('described-binds-read-as-text', pentad[0] === 'Super | Search applications' && pentad.indexOf('Super+/ | Keybind cheatsheet') >= 0
                    && pentad.indexOf('Alt+` | Next window of the app') >= 0, JSON.stringify(pentad));
                // The Super key shows the Pentad logo by default: on every Super keycap and on the
                // shortcut tiles. The word stays the keycap's text.
                const superCaps = root.superCaps(view);
                const tileLogos = root.findAll(strip, item => item.objectName === 'cheatsheet-shortcut-logo' && item.active);
                root.check('super-logo-by-default', !!root.services.cheatsheet && superCaps.length > 10
                    && superCaps.every(cap => root.capShowsLogo(cap))
                    && tileLogos.length === 4 && tileLogos.every(loader => root.logoLoaded(loader)),
                    JSON.stringify({ caps: superCaps.length, logos: superCaps.filter(cap => root.capShowsLogo(cap)).length,
                        tiles: tileLogos.length, first: superCaps.length ? String(superCaps[0].icon) : '' }));
                root.check('lua-binds-hidden-by-default', view.shownCount === root.sample.total - KeybindsLogic.hiddenCount(root.sample.groups)
                    && root.rowTexts(view).every(text => text.indexOf('Lua function') < 0), String(view.shownCount));
                root.phase = -1;
                root.grab('', () => {
                    root.services.ukrainian = true;
                    root.phase = 2;
                });
            } else if (root.phase === 2 && root.settled(!!view && root.find(view, 'cheatsheet-title').text === 'Шпаргалка клавіш')) {
                const titleOf = id => {
                    const block = root.find(view, 'cheatsheet-group-' + id);
                    const title = root.find(block, 'cheatsheet-group-title');
                    return title ? title.text : '';
                };
                root.check('ukrainian-labels', titleOf('windows') === 'Вікна' && titleOf('workspaces') === 'Робочі простори'
                    && titleOf('launch') === 'Запуск' && titleOf('submap:resize') === 'Режим клавіш: resize' && titleOf('group:media') === 'Media'
                    && view.searchField.placeholderText === 'Пошук за клавішею або дією' && view.showAllToggle.text === 'Показати всі',
                    JSON.stringify([titleOf('windows'), titleOf('workspaces'), titleOf('submap:resize'), view.searchField.placeholderText]));
                root.phase = -1;
                root.grab('.uk.png', () => {
                    root.services.ukrainian = false;
                    root.phase = 3;
                });
            } else if (root.phase === 3 && root.settled(!!view && root.find(view, 'cheatsheet-title').text === 'Keybind cheatsheet')) {
                // A pointer click on "Show all" lists the Lua binds that have no description.
                const toggle = view.showAllToggle;
                root.keys.mouseClick(toggle, toggle.width / 2, toggle.height / 2, Qt.LeftButton, Qt.NoModifier, -1);
                root.phase = 4;
            } else if (root.phase === 4 && root.settled(sheet.showAll && view.shownCount === root.sample.total)) {
                const other = root.rowTexts(root.find(view, 'cheatsheet-group-other'));
                root.check('show-all-reveals-lua', sheet.showAll && view.shownCount === root.sample.total
                    && other.indexOf('Super | Lua function without a description') >= 0 && view.searchField.activeFocus,
                    JSON.stringify({ shown: view.shownCount, other: other }));
                const toggle = view.showAllToggle;
                root.keys.mouseClick(toggle, toggle.width / 2, toggle.height / 2, Qt.LeftButton, Qt.NoModifier, -1);
                root.phase = 5;
            } else if (root.phase === 5 && root.settled(!sheet.showAll)) {
                root.start = { height: root.overlay().frame.height };
                for (const character of 'kill')
                    root.keys.keyClickChar(character, Qt.NoModifier, 0);
                root.phase = 6;
            } else if (root.phase === 6 && root.settled(sheet.query === 'kill' && view.groups.length === 1)) {
                const frame = root.overlay().frame;
                root.check('search-filters', sheet.query === 'kill' && view.searchField.text === 'kill'
                    && JSON.stringify(root.groupBlocks(view).map(block => block.objectName)) === JSON.stringify(['cheatsheet-group-windows'])
                    && JSON.stringify(root.rowTexts(view)) === JSON.stringify(['Super+Q | killactive']),
                    JSON.stringify({ query: sheet.query, rows: root.rowTexts(view) }));
                root.check('card-keeps-its-height', frame.height === root.start.height, frame.height + ' vs ' + root.start.height);
                // A search narrows the list: the strip steps aside and the groups start at the top.
                root.check('shortcuts-hide-while-searching', view.shortcuts.length === 4 && !view.shortcutsShown
                    && !root.find(view, 'cheatsheet-shortcuts') && view.listTop === 0, JSON.stringify({ shown: view.shortcutsShown, top: view.listTop }));
                for (const character of ' zz')
                    root.keys.keyClickChar(character, Qt.NoModifier, 0);
                root.phase = 7;
            } else if (root.phase === 7 && root.settled(view.message === 'Nothing found')) {
                const message = root.find(view, 'cheatsheet-message');
                root.check('nothing-found', !!message && message.visible && message.text === 'Nothing found' && root.groupBlocks(view).length === 0,
                    message ? message.text : 'no message');
                root.keys.keyClick(Qt.Key_Escape, Qt.NoModifier, 0);
                root.phase = 8;
            } else if (root.phase === 8 && root.settled(sheet.query === '')) {
                root.check('escape-clears-search-first', sheet.query === '' && sheet.open && !!host.overlay && view.searchField.text === '');
                // The chips, the keyboard view and the sheet order come next; phase 62 closes with Esc.
                root.phase = 40;
            } else if (root.phase === 9 && root.settled(!sheet.open && !host.overlay)) {
                const calls = root.services.popups.calls;
                root.check('escape-closes', !sheet.open && !host.overlay && calls[calls.length - 1] === 'cheatsheet:false', JSON.stringify(calls));
                sheet.show();
                root.phase = 10;
            } else if (root.phase === 10 && root.settled(!!view && view.searchField.activeFocus && sheet.mods.length > 0)) {
                const frame = root.overlay().frame;
                root.check('reopen-starts-with-empty-search', sheet.query === '' && view.searchField.text === '');
                // The filters start over; the sheet, the keyboard view and "Show all" stay, and the
                // keyboard view picks the sheet's busiest layer again. No focused window here.
                root.check('reopen-resets-filters', sheet.key === '' && !sheet.duplicates && sheet.contextSheet === ''
                    && sheet.sheet === 'browser' && sheet.view === 'keys' && view.keyboardShown && root.modsAre(['Ctrl'])
                    && !root.find(view, 'cheatsheet-key-chip').visible, JSON.stringify({ sheet: sheet.sheet, view: sheet.view, mods: sheet.mods }));
                // A new view after the reopening gives every group the hue it had before.
                const tabs = root.find(root.find(view, 'cheatsheet-group-browser-tabs'), 'cheatsheet-group-title');
                root.check('hues-stay-across-reopen', root.savedHues !== '' && root.savedHues === JSON.stringify(view.hueColors)
                    && Object.keys(view.hueColors).length === 3 && !!tabs && Qt.colorEqual(tabs.color, view.hueColors['browser-tabs']),
                    root.savedHues + ' vs ' + JSON.stringify(view.hueColors));
                // A press on the card's header keeps it; a press beside the card closes it.
                root.keys.mouseClick(frame, 300, 24, Qt.LeftButton, Qt.NoModifier, -1);
                root.start = { keptOpen: sheet.open && !!host.overlay };
                root.keys.mousePress(frame, -24, -24, Qt.LeftButton, Qt.NoModifier, -1);
                root.phase = 11;
            } else if (root.phase === 11 && root.settled(!sheet.open && !host.overlay)) {
                root.check('press-outside-closes', root.start.keptOpen === true && !sheet.open && !host.overlay, JSON.stringify(root.start));
                sheet.show();
                root.phase = 12;
            } else if (root.phase === 12 && root.settled(!!view && view.searchField.activeFocus)) {
                // A screenshot is about to be taken: the overlay leaves the picture.
                root.services.popups.capturePreparing();
                root.phase = 13;
            } else if (root.phase === 13 && root.settled(!sheet.open && !host.overlay)) {
                root.check('hides-for-screenshot', !sheet.open && !host.overlay);
                sheet.show();
                root.phase = 14;
            } else if (root.phase === 14 && root.settled(!!view && view.searchField.activeFocus)) {
                // A bar menu opened: the overlay gives way.
                root.services.popups.surface = 'right';
                root.services.popups.changed();
                root.phase = 15;
            } else if (root.phase === 15 && root.settled(!sheet.open && !host.overlay)) {
                root.check('bar-menu-closes', !sheet.open && !host.overlay);
                root.services.popups.surface = '';
                root.printed.active = true;
                root.failing.active = true;
                root.oversized.active = true;
                root.brokenServices.cheatsheet.show();
                root.phase = 16;
            } else if (root.phase === 16 && root.settled(root.printed.state.kind === 'ready' && root.failing.state.kind === 'unavailable'
                    && root.oversized.state.kind === 'unavailable' && root.brokenServices.keybinds.state.kind === 'unavailable'
                    && !!brokenHost.overlay)) {
                const printedGroups = root.printed.state.value ? root.printed.state.value.groups : [];
                root.check('reader-parses-output', printedGroups.length === 2 && printedGroups[0].id === 'group:window'
                    && printedGroups[0].binds[0].description === 'Close', JSON.stringify(root.printed.state));
                root.check('failed-run-is-unavailable', root.failing.state.reason === 'failed', JSON.stringify(root.failing.state));
                root.check('oversized-output-is-ignored', root.oversized.state.reason === 'too-large', JSON.stringify(root.oversized.state));
                const broken = brokenHost.overlay.view;
                const message = root.find(broken, 'cheatsheet-message');
                const reason = root.find(broken, 'cheatsheet-reason');
                const retry = root.find(broken, 'cheatsheet-retry');
                root.check('missing-hyprctl-is-unavailable', root.brokenServices.keybinds.state.reason === 'missing'
                    && message.text === 'Hyprland is not answering' && reason.visible && reason.text === 'hyprctl was not found.'
                    && retry.visible, JSON.stringify({ state: root.brokenServices.keybinds.state, message: message.text, reason: reason.text }));
                root.phase = -1;
                root.grab('.unavailable.png', () => {
                    root.keys.keyClick(Qt.Key_Escape, Qt.NoModifier, 0);
                    root.phase = 17;
                });
            } else if (root.phase === 17 && root.settled(!brokenHost.overlay)) {
                root.check('unavailable-escape-closes', !brokenHost.overlay && !root.brokenServices.cheatsheet.open);
                root.longServices.cheatsheet.show();
                root.phase = 18;
            } else if (root.phase === 18 && root.settled(!!longHost.overlay && root.longServices.keybinds.state.kind === 'ready'
                    && longHost.overlay.view.flickable.contentHeight > longHost.overlay.view.flickable.height
                    && longHost.overlay.view.searchField.activeFocus)) {
                const window = longHost.overlay;
                const list = window.view.flickable;
                root.check('long-list-stops-at-86-percent', window.frame.height === KeybindsLogic.cardHeight(window.height)
                    && window.frame.height === Math.round(window.height * 0.86)
                    && window.view.shownCount === 240 && list.contentHeight > list.height && list.contentY === 0,
                    JSON.stringify({ frame: window.frame.height, window: window.height, content: list.contentHeight, list: list.height }));
                // Every bind there reads "Super + Key NNN", too long to set large: no strip at all.
                root.check('shortcuts-absent-when-none-qualify', window.view.shortcuts.length === 0 && !window.view.shortcutsShown
                    && !root.find(window.view, 'cheatsheet-shortcuts') && window.view.listTop === 0
                    && Object.keys(window.view.hueColors).length === 8, JSON.stringify(window.view.shortcuts));
                root.keys.keyClick(Qt.Key_PageDown, Qt.NoModifier, 0);
                root.phase = 19;
            } else if (root.phase === 19 && root.settled(!!longHost.overlay && longHost.overlay.view.flickable.contentY > 0)) {
                const list = longHost.overlay.view.flickable;
                root.check('page-down-scrolls', list.contentY > 0 && list.contentY <= list.contentHeight - list.height
                    && longHost.overlay.view.searchField.activeFocus, String(list.contentY));
                root.keys.keyClick(Qt.Key_Escape, Qt.NoModifier, 0);
                root.phase = 20;
            } else if (root.phase === 20 && root.settled(!longHost.overlay)) {
                root.check('long-list-escape-closes', !longHost.overlay && !root.longServices.cheatsheet.open);
                root.brokenServices.cheatsheet.show();
                root.phase = 21;
            } else if (root.phase === 21 && root.settled(!!brokenHost.overlay)) {
                const selector = root.find(brokenHost.overlay.view, 'cheatsheet-selector');
                root.brokenServices.cheatsheet.query = 'old query';
                selector.activated('neovim');
                root.phase = 22;
            } else if (root.phase === 22 && root.settled(!!brokenHost.overlay && brokenHost.overlay.view.shownCount > 0)) {
                const reference = brokenHost.overlay.view;
                root.check('reference-works-without-hyprland', reference.stateKind === 'ready'
                    && root.brokenServices.cheatsheet.sheet === 'neovim' && root.brokenServices.cheatsheet.query === ''
                    && !reference.showAllToggle.visible && reference.flickable.contentY === 0);
                root.brokenServices.cheatsheet.query = 'no-such-reference-action-123';
                root.phase = 23;
            } else if (root.phase === 23 && root.settled(brokenHost.overlay.view.shownCount === 0)) {
                root.check('reference-search-empty', brokenHost.overlay.view.message === 'Nothing found');
                root.brokenServices.ukrainian = true;
                root.find(brokenHost.overlay.view, 'cheatsheet-selector').activated('browser');
                root.phase = 24;
            } else if (root.phase === 24 && root.settled(brokenHost.overlay.view.shownCount > 0)) {
                const reference = brokenHost.overlay.view;
                root.check('reference-switch-clears-search', root.brokenServices.cheatsheet.query === ''
                    && root.brokenServices.cheatsheet.sheet === 'browser');
                root.check('reference-language-updates', root.find(reference, 'cheatsheet-title').text === 'Шпаргалка клавіш'
                    && root.find(reference, 'cheatsheet-selector').options[3].label !== 'Browser');
                root.find(reference, 'cheatsheet-selector').activated('pentad');
                root.phase = 25;
            } else if (root.phase === 25 && root.settled(brokenHost.overlay.view.shownCount > 0)) {
                root.check('pentad-reference-populated', root.brokenServices.cheatsheet.sheet === 'pentad');
                root.find(brokenHost.overlay.view, 'cheatsheet-selector').activated('git');
                root.brokenServices.cheatsheet.query = 'stash changes';
                root.phase = 27;
            } else if (root.phase === 27 && root.settled(brokenHost.overlay.view.shownCount > 0)) {
                root.check('git-english-search', root.brokenServices.cheatsheet.sheet === 'git');
                root.brokenServices.cheatsheet.query = 'сховати';
                root.phase = 28;
            } else if (root.phase === 28 && root.settled(brokenHost.overlay.view.shownCount > 0)) {
                root.check('git-ukrainian-search', brokenHost.overlay.view.shownCount > 0);
                root.brokenServices.cheatsheet.query = '';
                root.keys.keyClick(Qt.Key_Escape, Qt.NoModifier, 0);
                root.phase = 26;
            } else if (root.phase === 26 && root.settled(!brokenHost.overlay)) {
                root.check('reference-escape-closes', !root.brokenServices.cheatsheet.open);
                // Last, the same view in narrower windows, with the keyboard view still chosen.
                sheet.selectSheet('live');
                root.narrowWidth = 360;
                root.narrowShown = true;
                root.phase = 63;
            } else if (root.phase === 63 && root.settled(!!narrowLoader.item && narrowLoader.item.view.width === 360
                    && root.groupBlocks(narrowLoader.item.view).length > 0 && root.ticks > 12)) {
                // The ticks give the new window time to be mapped before it is grabbed. At 360 px
                // the map would be too small to read: the list stays, without the switch.
                const narrow = narrowLoader.item.view;
                const title = root.find(narrow, 'cheatsheet-title');
                const close = root.find(narrow, 'cheatsheet-close');
                const closeX = close.mapToItem(narrow, 0, 0).x;
                root.check('narrow-keeps-the-list', !narrow.keyboardShown && !narrow.viewSwitcher.visible && !root.find(narrow, 'cheatsheet-keyboard')
                    && sheet.view === 'keys' && narrow.columnCount === 1 && narrow.compactReferences && !title.truncated
                    && closeX + close.width <= narrow.width - Metrics.space3 + 1 && narrow.chips.childrenRect.width <= narrow.bodyWidth + 1,
                    JSON.stringify({ columns: narrow.columnCount, title: title.width, truncated: title.truncated, close: closeX,
                        chips: narrow.chips.childrenRect.width }));
                root.phase = -1;
                root.grabItem(narrowLoader.item.frame, '.narrow.png', () => {
                    root.narrowShown = false;
                    root.phase = 64;
                });
            } else if (root.phase === 64 && root.settled(!narrowLoader.item)) {
                root.narrowWidth = 600;
                root.narrowShown = true;
                root.phase = 65;
            } else if (root.phase === 65 && root.settled(!!narrowLoader.item && narrowLoader.item.view.width === 600
                    && !!root.find(narrowLoader.item.view, 'cheatsheet-keyboard') && root.modsAre(['Super']) && root.ticks > 12)) {
                // Two columns of groups: the smallest card that offers the map.
                const medium = narrowLoader.item.view;
                const keyboard = root.find(medium, 'cheatsheet-keyboard');
                root.check('medium-width-keyboard', medium.keyboardShown && medium.columnCount === 2 && keyboard.unit >= 28
                    && keyboard.boardWidth <= keyboard.width && keyboard.width <= medium.bodyWidth && root.keyItems(medium).q.bound,
                    JSON.stringify({ columns: medium.columnCount, keyboard: keyboard.width, unit: keyboard.unit }));
                root.phase = -1;
                root.grabItem(narrowLoader.item.frame, '.medium.png', () => {
                    root.narrowShown = false;
                    root.phase = 66;
                });
            } else if (root.phase === 66 && root.settled(!narrowLoader.item)) {
                // The card of a 2560 × 1440 output, first in the list view with no filter on.
                root.narrowWidth = KeybindsLogic.cardWidth(2560);
                root.narrowHeight = KeybindsLogic.cardHeight(1440);
                sheet.setView('list');
                sheet.setMods([]);
                root.narrowShown = true;
                root.phase = 67;
            } else if (root.phase === 67 && root.settled(!!narrowLoader.item && narrowLoader.item.view.width === root.narrowWidth
                    && root.groupBlocks(narrowLoader.item.view).length > 0 && !!root.find(narrowLoader.item.view, 'cheatsheet-shortcuts')
                    && root.ticks > 12)) {
                // Five columns, six shortcut tiles, every Super key a logo.
                const wide = narrowLoader.item.view;
                const tiles = root.findAll(wide, item => item.objectName === 'cheatsheet-shortcut');
                const blocks = root.groupBlocks(wide);
                root.check('wide-card-list', wide.columnCount === 5 && wide.columns.length === 5 && blocks.length > 0
                    && tiles.length === 6
                    && JSON.stringify(root.shortcutTexts(wide).slice(4)) === JSON.stringify(['Super+/ | Keybind cheatsheet', 'Alt+Tab | Next window'])
                    && root.superCaps(wide).every(cap => root.capShowsLogo(cap)),
                    JSON.stringify({ columns: wide.columnCount, width: wide.columnWidth, tiles: root.shortcutTexts(wide) }));
                root.phase = -1;
                root.grabItem(narrowLoader.item.frame, '.wide.png', () => {
                    sheet.setView('keys');
                    root.phase = 68;
                });
            } else if (root.phase === 68 && root.settled(!!narrowLoader.item && !!root.find(narrowLoader.item.view, 'cheatsheet-keyboard')
                    && root.modsAre(['Super']) && root.ticks > 12)) {
                // The map grows with the card, the whole board in sight.
                const wide = narrowLoader.item.view;
                const keyboard = root.find(wide, 'cheatsheet-keyboard');
                const keyCase = root.find(wide, 'cheatsheet-keyboard-case');
                const caseBottom = keyCase.mapToItem(wide, 0, keyCase.height).y;
                root.check('wide-card-keyboard', keyboard.legendRole === 'section' && keyboard.roomy
                    && caseBottom <= wide.height && root.logoLoaded(root.find(root.keyItems(wide).super, 'cheatsheet-keyboard-logo')),
                    JSON.stringify({ unit: keyboard.unit, caseBottom: caseBottom, height: wide.height }));
                root.phase = -1;
                root.grabItem(narrowLoader.item.frame, '.wide.keys.png', () => {
                    root.narrowShown = false;
                    root.phase = 69;
                });
            } else if (root.phase === 69 && root.settled(!narrowLoader.item)) {
                // The card of a 1080 × 1920 portrait output: as wide as before, much taller.
                root.narrowWidth = KeybindsLogic.cardWidth(1080);
                root.narrowHeight = KeybindsLogic.cardHeight(1920);
                root.narrowShown = true;
                root.phase = 75;
            } else if (root.phase === 75 && root.settled(!!narrowLoader.item && narrowLoader.item.view.width === root.narrowWidth
                    && !!root.find(narrowLoader.item.view, 'cheatsheet-keyboard') && root.ticks > 12)) {
                const portrait = narrowLoader.item.view;
                const keyboard = root.find(portrait, 'cheatsheet-keyboard');
                root.check('portrait-card', portrait.columnCount === 3 && keyboard.unit >= 48
                    && keyboard.board.width <= portrait.bodyWidth && portrait.flickable.contentHeight <= portrait.flickable.height,
                    JSON.stringify({ columns: portrait.columnCount, unit: keyboard.unit, content: portrait.flickable.contentHeight,
                        list: portrait.flickable.height }));
                root.phase = -1;
                root.grabItem(narrowLoader.item.frame, '.portrait.png', () => {
                    root.narrowShown = false;
                    root.phase = 76;
                });
            } else if (root.phase === 76 && root.settled(!narrowLoader.item)) {
                root.finish();
                stop();
            } else if (root.phase === 40 && root.settled(!!view && view.chips.visible)) {
                // The sample uses Super, Ctrl, Alt and Shift, and has one duplicate pair (Super+P).
                const chips = root.visibleChips(view);
                root.check('modifier-chips-render', JSON.stringify(chips) === JSON.stringify(['cheatsheet-mod-super', 'cheatsheet-mod-ctrl',
                    'cheatsheet-mod-alt', 'cheatsheet-mod-shift', 'cheatsheet-duplicates'])
                    && root.find(view, 'cheatsheet-duplicates').count === 2 && root.find(view, 'cheatsheet-duplicates').text === 'Duplicates'
                    && !Array.prototype.slice.call(view.chips.children).some(chip => chip.checked === true),
                    JSON.stringify(chips));
                // Tab goes from the search to the first chip; Space toggles it.
                root.keys.keyClick(Qt.Key_Tab, Qt.NoModifier, 0);
                root.phase = 70;
            } else if (root.phase === 70 && root.settled(root.find(view, 'cheatsheet-mod-super').activeFocus)) {
                root.keys.keyClick(Qt.Key_Space, Qt.NoModifier, 0);
                root.phase = 71;
            } else if (root.phase === 71 && root.settled(root.modsAre(['Super']))) {
                const chip = root.find(view, 'cheatsheet-mod-super');
                root.check('chips-take-tab-and-space', chip.activeFocus && chip.checked && chip.visualFocus, JSON.stringify(sheet.mods));
                root.keys.keyClick(Qt.Key_Space, Qt.NoModifier, 0);
                root.phase = 72;
            } else if (root.phase === 72 && root.settled(sheet.mods.length === 0)) {
                root.keys.keyClick(Qt.Key_Backtab, Qt.ShiftModifier, 0);
                root.phase = 73;
            } else if (root.phase === 73 && root.settled(view.searchField.activeFocus)) {
                // A pointer click on a chip leaves the keyboard in the search.
                root.click(root.find(view, 'cheatsheet-mod-super'));
                root.phase = 41;
            } else if (root.phase === 41 && root.settled(root.modsAre(['Super']))) {
                const expected = KeybindsLogic.countBinds(KeybindsLogic.filterBinds(root.sample.groups, '', { mods: ['Super'] }));
                const rows = root.rowTexts(view);
                root.check('modifier-chip-filters', view.shownCount === expected && rows.length === expected
                    && rows.every(text => text.split(' | ')[0].split('+').indexOf('Super') >= 0)
                    && root.find(view, 'cheatsheet-mod-super').checked && view.searchField.activeFocus && view.flickable.contentY === 0,
                    JSON.stringify({ shown: view.shownCount, expected: expected, focus: view.searchField.activeFocus }));
                root.check('shortcuts-hide-for-chips', !view.shortcutsShown && !root.find(view, 'cheatsheet-shortcuts'), String(view.shortcutsShown));
                root.phase = -1;
                root.grab('.chips.png', () => {
                    root.click(root.find(root.view(), 'cheatsheet-mod-shift'));
                    root.phase = 42;
                });
            } else if (root.phase === 42 && root.settled(root.modsAre(['Super', 'Shift']))) {
                const rows = root.rowTexts(view);
                root.check('modifier-chips-combine', rows.length > 0 && rows.every(text => /Super/.test(text.split(' | ')[0]) && /Shift/.test(text.split(' | ')[0]))
                    && rows.indexOf('Super+Shift+L | Lock the session') >= 0, JSON.stringify(rows));
                root.click(root.find(view, 'cheatsheet-mod-shift'));
                root.click(root.find(view, 'cheatsheet-duplicates'));
                root.phase = 43;
            } else if (root.phase === 43 && root.settled(sheet.duplicates && root.modsAre(['Super']))) {
                const marks = root.findAll(view, item => item.objectName === 'cheatsheet-duplicate');
                root.check('duplicates-chip-filters', JSON.stringify(root.rowTexts(view)) === JSON.stringify(['Super+P | pin', 'Super+P | exec hyprpicker -a'])
                    && marks.length === 2 && marks.every(mark => mark.accessibleName === 'These keys also do something else' && mark.visible)
                    && root.find(view, 'cheatsheet-duplicates').checked,
                    JSON.stringify({ rows: root.rowTexts(view), marks: marks.length }));
                for (const character of 'pin')
                    root.keys.keyClickChar(character, Qt.NoModifier, 0);
                root.phase = 44;
            } else if (root.phase === 44 && root.settled(sheet.query === 'pin' && view.shownCount === 1)) {
                root.check('filters-and-search-combine', JSON.stringify(root.rowTexts(view)) === JSON.stringify(['Super+P | pin']),
                    JSON.stringify(root.rowTexts(view)));
                root.keys.keyClick(Qt.Key_Escape, Qt.NoModifier, 0);
                root.phase = 45;
            } else if (root.phase === 45 && root.settled(sheet.query === '' && !sheet.duplicates)) {
                // One Esc clears the query and the duplicates filter together; the modifiers stay.
                root.check('escape-clears-query-and-duplicates-together', sheet.open && !!host.overlay && sheet.query === '' && !sheet.duplicates
                    && root.modsAre(['Super']) && view.searchField.text === '');
                root.click(root.find(view, 'cheatsheet-mod-super'));
                root.phase = 46;
            } else if (root.phase === 46 && root.settled(sheet.mods.length === 0)) {
                // No chip selected: the keyboard view picks the busiest layer itself.
                root.click(root.find(view, 'cheatsheet-view-1'));
                root.phase = 47;
            } else if (root.phase === 47 && root.settled(!!root.find(view, 'cheatsheet-keyboard') && sheet.mods.length > 0 && root.ticks > 10)) {
                // The ticks let the switch's thumb finish its slide before the capture.
                const keys = root.keyItems(view);
                const layer = KeyboardMap.layers(view.sheetGroups)[0].mods;
                const bound = ['q', 'p', 'v', 'slash', 'period', 'tab', 'space', '1', 'left', 'print'].filter(id => !!keys[id] && keys[id].bound);
                root.start = { height: root.overlay().frame.height };
                root.check('keyboard-view-default-layer', sheet.view === 'keys' && view.keyboardShown && JSON.stringify(layer) === '["Super"]'
                    && root.modsAre(layer) && root.find(view, 'cheatsheet-mod-super').checked && view.viewSwitcher.value === 'keys',
                    JSON.stringify({ view: sheet.view, mods: sheet.mods, layer: layer }));
                root.check('keyboard-bound-keys', bound.length === 10 && keys.p.count === 2 && !keys.z.bound && !keys.w.bound
                    && keys.super.held && !keys.shift.held && keys.shift.interactive && !keys.z.interactive,
                    JSON.stringify({ bound: bound, p: keys.p ? keys.p.count : -1 }));
                const capOf = key => root.find(key, 'cheatsheet-keyboard-cap');
                // A bound key takes the hue of its bind's group; Super+P pins a window and runs a
                // colour picker, two groups, so it stays neutral and counts them; a free key has no hue.
                root.check('keyboard-key-hues', Qt.colorEqual(keys.q.hue, view.hueColors.windows) && Qt.colorEqual(capOf(keys.q).hue, view.hueColors.windows)
                    && capOf(keys.q).tinted
                    && Qt.colorEqual(keys.v.hue, view.hueColors['group:pentad']) && keys.p.hue.a === 0 && capOf(keys.p).hue.a === 0
                    && !capOf(keys.p).tinted && keys.p.showCount && keys.z.hue.a === 0 && !capOf(keys.z).tinted,
                    JSON.stringify({ q: String(keys.q.hue), ink: String(capOf(keys.q).ink), p: String(keys.p.hue) }));
                // The map's Super key wears the logo where its legend would be.
                root.check('keyboard-super-logo', root.logoLoaded(root.find(keys.super, 'cheatsheet-keyboard-logo'))
                    && !root.find(keys.super, 'cheatsheet-keyboard-legend-text').visible
                    && root.find(keys.alt, 'cheatsheet-keyboard-legend-text').visible && root.find(keys.alt, 'cheatsheet-keyboard-legend-text').text === 'Alt',
                    String(root.find(keys.super, 'cheatsheet-keyboard-logo').active));
                // Under the board a legend names the groups of the layer, each with a dot in its hue.
                const legend = root.find(view, 'cheatsheet-keyboard-legend');
                const legendItems = root.findAll(legend, item => item.objectName === 'cheatsheet-keyboard-legend-item');
                const legendNames = legendItems.map(item => root.find(item, 'cheatsheet-keyboard-legend-name').text);
                root.check('keyboard-legend', !!legend && legend.visible
                    && JSON.stringify(legendNames) === JSON.stringify(['Pentad', 'Screenshot', 'Shell', 'Workspaces', 'Windows', 'Launch'])
                    && legendItems.every(item => Qt.colorEqual(item.hue, view.hueColors[item.groupId])),
                    JSON.stringify(legendNames));
                root.phase = -1;
                root.grab('.keys.png', () => {
                    // The setting asks for the word: every Super key prints "Super" again. A controller
                    // without the setting keeps the logo, and only the default was checked.
                    if (typeof root.services.cheatsheet.superKeyLogo === 'string') {
                        root.services.cheatsheet.superKeyLogo = 'text';
                        root.phase = 80;
                    } else {
                        root.click(root.keyItems(root.view()).shift);
                        root.phase = 48;
                    }
                });
            } else if (root.phase === 80 && root.settled(!root.find(root.keyItems(view).super, 'cheatsheet-keyboard-logo').active)) {
                const superKey = root.keyItems(view).super;
                const legend = root.find(superKey, 'cheatsheet-keyboard-legend-text');
                const caps = root.superCaps(view);
                root.check('super-word-with-text-setting', view.superIcon === '' && legend.visible && legend.text === 'Super'
                    && caps.length > 10 && caps.every(cap => root.capShowsWord(cap)),
                    JSON.stringify({ icon: view.superIcon, legend: legend.text, caps: caps.length, words: caps.filter(cap => root.capShowsWord(cap)).length }));
                // Anything the setting does not know draws the Pentad logo.
                root.services.cheatsheet.superKeyLogo = 'windows';
                root.phase = 81;
            } else if (root.phase === 81 && root.settled(root.logoLoaded(root.find(root.keyItems(view).super, 'cheatsheet-keyboard-logo')))) {
                root.check('super-logo-for-unknown-setting', root.superCaps(view).every(cap => root.capShowsLogo(cap)),
                    String(view.superIcon));
                root.services.cheatsheet.superKeyLogo = 'pentad';
                root.click(root.keyItems(view).shift);
                root.phase = 48;
            } else if (root.phase === 48 && root.settled(root.modsAre(['Super', 'Shift']))) {
                const keys = root.keyItems(view);
                root.check('keyboard-modifier-key-toggles-chip', keys.shift.held && keys['shift-r'].held && keys.l.bound && !keys.q.bound
                    && keys['1'].bound && root.find(view, 'cheatsheet-mod-shift').checked, JSON.stringify(sheet.mods));
                root.click(keys.shift);
                root.phase = 49;
            } else if (root.phase === 49 && root.settled(root.modsAre(['Super']))) {
                root.click(root.keyItems(view).q);
                root.phase = 50;
            } else if (root.phase === 50 && root.settled(sheet.key === 'Q')) {
                const chip = root.find(view, 'cheatsheet-key-chip');
                const frame = root.overlay().frame;
                root.check('keyboard-key-filters-list', JSON.stringify(root.rowTexts(view)) === JSON.stringify(['Super+Q | killactive'])
                    && chip.visible && chip.removable && chip.text === 'Q' && JSON.stringify(root.visibleChips(view).slice(-1)) === '["cheatsheet-key-chip"]',
                    JSON.stringify({ rows: root.rowTexts(view), key: sheet.key }));
                root.check('keyboard-card-keeps-its-height', frame.height === root.start.height, frame.height + ' vs ' + root.start.height);
                // The same key again clears the filter.
                root.click(root.keyItems(view).q);
                root.phase = 51;
            } else if (root.phase === 51 && root.settled(sheet.key === '')) {
                const expected = KeybindsLogic.countBinds(KeybindsLogic.filterBinds(root.sample.groups, '', { mods: ['Super'] }));
                root.check('same-key-clears-filter', !root.find(view, 'cheatsheet-key-chip').visible && view.shownCount === expected,
                    String(view.shownCount));
                root.click(root.keyItems(view).p);
                root.phase = 52;
            } else if (root.phase === 52 && root.settled(sheet.key === 'P')) {
                // Typing goes to the search wherever the focus is (the view switch has it now).
                root.click(root.find(view, 'cheatsheet-duplicates'));
                for (const character of 'hyp')
                    root.keys.keyClickChar(character, Qt.NoModifier, 0);
                root.phase = 53;
            } else if (root.phase === 53 && root.settled(sheet.query === 'hyp' && sheet.duplicates)) {
                root.check('key-duplicates-and-search-combine', JSON.stringify(root.rowTexts(view)) === JSON.stringify(['Super+P | exec hyprpicker -a'])
                    && view.searchField.text === 'hyp' && view.searchField.activeFocus, JSON.stringify(root.rowTexts(view)));
                root.keys.keyClick(Qt.Key_Escape, Qt.NoModifier, 0);
                root.phase = 54;
            } else if (root.phase === 54 && root.settled(sheet.query === '' && sheet.key === '' && !sheet.duplicates)) {
                root.check('escape-clears-query-key-and-duplicates-together', sheet.open && !!host.overlay && root.modsAre(['Super'])
                    && view.keyboardShown && !root.find(view, 'cheatsheet-key-chip').visible);
                root.services.ukrainian = true;
                root.phase = 55;
            } else if (root.phase === 55 && root.settled(!!view && root.find(view, 'cheatsheet-title').text === 'Шпаргалка клавіш')) {
                const keyboard = root.find(view, 'cheatsheet-keyboard');
                root.check('keyboard-ukrainian', keyboard.summary.indexOf('Прив’язано: ') === 0
                    && root.find(view, 'cheatsheet-duplicates').text === 'Дублікати'
                    && view.viewSwitcher.options[0].label === 'Список' && view.viewSwitcher.options[1].label === 'Клавіатура'
                    && view.sheetOptions[0].label === 'Поточні клавіші', keyboard.summary);
                root.phase = -1;
                root.grab('.keys.uk.png', () => {
                    root.services.ukrainian = false;
                    root.phase = 56;
                });
            } else if (root.phase === 56 && root.settled(!!view && root.find(view, 'cheatsheet-title').text === 'Keybind cheatsheet')) {
                root.keys.keyClick(Qt.Key_Tab, Qt.ControlModifier, 0);
                root.phase = 57;
            } else if (root.phase === 57 && root.settled(sheet.sheet !== 'live')) {
                root.check('ctrl-tab-next-sheet', sheet.sheet === view.sheetOptions[1].value && sheet.sheet === 'pentad' && sheet.query === ''
                    && !!host.overlay && view.keyboardShown, sheet.sheet);
                root.keys.keyClick(Qt.Key_Backtab, Qt.ControlModifier | Qt.ShiftModifier, 0);
                root.phase = 58;
            } else if (root.phase === 58 && root.settled(sheet.sheet === 'live' && sheet.mods.length > 0)) {
                root.check('ctrl-shift-tab-previous-sheet', sheet.sheet === 'live' && root.modsAre(['Super']), JSON.stringify(sheet.mods));
                root.click(root.sheetSegment(view, 'git'));
                root.phase = 59;
            } else if (root.phase === 59 && root.settled(sheet.sheet === 'git')) {
                // Typed commands: no chips (no space taken), no keyboard switch, the list only.
                const listTop = view.flickable.mapToItem(view, 0, 0).y;
                root.check('git-hides-chips-and-switch', !view.chips.visible && !view.viewSwitcher.visible && !view.keyboardShown
                    && !root.find(view, 'cheatsheet-keyboard') && sheet.view === 'keys' && view.shownCount > 0
                    && Math.abs(listTop - (view.searchField.y + view.searchField.height + Metrics.space3)) < 1,
                    JSON.stringify({ chips: view.chips.visible, listTop: listTop }));
                // A browser had focus when the cheatsheet opened (the controller reads it from Hyprland).
                sheet.contextSheet = 'browser';
                root.phase = 60;
            } else if (root.phase === 60 && root.settled(view.sheetOptions[1].value === 'browser')) {
                const options = view.sheetOptions;
                const segment = root.find(view, 'cheatsheet-sheet-1');
                root.check('context-sheet-second-and-marked', options[0].value === 'live' && options[1].marked === true
                    && options[1].description === 'for the focused app' && options.filter(option => option.marked === true).length === 1
                    && options.length === 7 && !!segment && segment.marked === true && !root.find(view, 'cheatsheet-sheet-0').marked
                    && sheet.sheet === 'git', JSON.stringify(options.map(option => option.value)));
                root.click(root.sheetSegment(view, 'live'));
                root.phase = 61;
            } else if (root.phase === 61 && root.settled(sheet.sheet === 'live')) {
                root.keys.keyClick(Qt.Key_Tab, Qt.ControlModifier, 0);
                root.phase = 62;
            } else if (root.phase === 62 && root.settled(sheet.sheet !== 'live' && sheet.mods.length > 0)) {
                root.check('ctrl-tab-follows-displayed-order', sheet.sheet === 'browser' && view.keyboardShown && root.modsAre(['Ctrl']),
                    JSON.stringify({ sheet: sheet.sheet, mods: sheet.mods }));
                root.savedHues = JSON.stringify(view.hueColors);
                root.keys.keyClick(Qt.Key_Escape, Qt.NoModifier, 0);
                root.phase = 9;
            }
            root.stepping = false;
        }
    }
}
