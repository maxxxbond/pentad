import QtQuick
import QtQuick.Window
import QtQml
import QtTest
import Quickshell
import Quickshell.Wayland
import qs.services
import qs.shell
import qs.theme
import "../logic/keybinds.mjs" as KeybindsLogic
import "../logic/keybinds-sample.mjs" as KeybindsSample

// The keybind cheatsheet overlay on the preview sample: groups, keycaps, the search, "Show all",
// both languages, and every way it closes. Separate Keybinds adapters outside preview run
// programs that are not hyprctl (a missing one, `false`, printf, head) for the reader's own
// paths; nothing here ever runs hyprctl.
ShellRoot {
    id: root
    property TestEvent keys: TestEvent {}
    property int phase: 0
    property int ticks: 0
    property bool stepping: false
    property var checks: []
    property var visibility: []
    property var start: ({})
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
    // Far more binds than fit: the card stops at 80 % of the screen and the list scrolls.
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
                root.check('overlay-opens', !!frame && frame.width === Math.min(920, window.width - 32)
                    && frame.height <= Math.round(window.height * 0.8)
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
                const firstLabel = root.find(windows, 'cheatsheet-description');
                root.check('keycaps-render', rows[0] === 'Super+Q | killactive' && rows.indexOf('Super+← | movefocus l') >= 0
                    && rows.indexOf('Super+LMB | movewindow') >= 0 && caps.length > 0
                    && caps.every(cap => cap.radius === Metrics.radiusSmall && Qt.colorEqual(cap.color, Theme.tokens.surfaceRaised) && cap.height === 24)
                    && Qt.colorEqual(firstLabel.color, Theme.tokens.textMuted), JSON.stringify(rows.slice(0, 4)));
                const pentad = root.rowTexts(root.find(view, 'cheatsheet-group-group:pentad'));
                root.check('described-binds-read-as-text', pentad[0] === 'Super | Search applications' && pentad.indexOf('Super+/ | Keybind cheatsheet') >= 0
                    && pentad.indexOf('Alt+` | Next window of the app') >= 0, JSON.stringify(pentad));
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
                root.keys.keyClick(Qt.Key_Escape, Qt.NoModifier, 0);
                root.phase = 9;
            } else if (root.phase === 9 && root.settled(!sheet.open && !host.overlay)) {
                const calls = root.services.popups.calls;
                root.check('escape-closes', !sheet.open && !host.overlay && calls[calls.length - 1] === 'cheatsheet:false', JSON.stringify(calls));
                sheet.show();
                root.phase = 10;
            } else if (root.phase === 10 && root.settled(!!view && view.searchField.activeFocus)) {
                const frame = root.overlay().frame;
                root.check('reopen-starts-with-empty-search', sheet.query === '' && view.searchField.text === '');
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
                root.check('long-list-stops-at-80-percent', window.frame.height === Math.round(window.height * 0.8)
                    && window.view.shownCount === 240 && list.contentHeight > list.height && list.contentY === 0,
                    JSON.stringify({ frame: window.frame.height, window: window.height, content: list.contentHeight, list: list.height }));
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
                root.find(brokenHost.overlay.view, 'cheatsheet-selector').activated('terminal');
                root.brokenServices.cheatsheet.query = 'search history backward';
                root.phase = 29;
            } else if (root.phase === 29 && root.settled(brokenHost.overlay.view.shownCount > 0)) {
                root.check('terminal-english-search', root.brokenServices.cheatsheet.sheet === 'terminal');
                root.brokenServices.cheatsheet.query = 'шукати назад';
                root.phase = 30;
            } else if (root.phase === 30 && root.settled(brokenHost.overlay.view.shownCount > 0)) {
                root.check('terminal-ukrainian-search', brokenHost.overlay.view.shownCount > 0);
                root.find(brokenHost.overlay.view, 'cheatsheet-selector').activated('kitty');
                root.brokenServices.cheatsheet.query = 'new tab';
                root.phase = 31;
            } else if (root.phase === 31 && root.settled(brokenHost.overlay.view.shownCount > 0)) {
                root.check('kitty-english-search', root.brokenServices.cheatsheet.sheet === 'kitty');
                root.brokenServices.cheatsheet.query = 'вкладку';
                root.phase = 32;
            } else if (root.phase === 32 && root.settled(brokenHost.overlay.view.shownCount > 0)) {
                root.check('kitty-ukrainian-search', brokenHost.overlay.view.shownCount > 0);
                root.brokenServices.cheatsheet.query = '';
                root.keys.keyClick(Qt.Key_Escape, Qt.NoModifier, 0);
                root.phase = 26;
            } else if (root.phase === 26 && root.settled(!brokenHost.overlay)) {
                root.check('reference-escape-closes', !root.brokenServices.cheatsheet.open);
                root.finish();
                stop();
            }
            root.stepping = false;
        }
    }
}
