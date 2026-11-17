import QtQuick
import QtQuick.Window
import QtQml
import Quickshell
import Quickshell.Wayland
import qs.services
import qs.shell
import qs.theme
import "../logic/keybinds.mjs" as KeybindsLogic
import "../logic/keybinds-sample.mjs" as KeybindsSample
import "../logic/keybind-hints.mjs" as KeybindHints

// The submap hint on the preview sample: no window while no submap is active, the strip with the
// `resize` submap's binds, an unknown submap, a reset, the cheatsheet and a screenshot taking its
// place, both languages, and a submap with more binds than fit. The submap name is set on the
// state service directly; nothing here listens to a compositor or runs hyprctl.
ShellRoot {
    id: root
    property int phase: 0
    property int ticks: 0
    property bool stepping: false
    property var checks: []
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
        property var calls: []
        signal changed
        signal capturePreparing
        function close() {
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
        readonly property SubmapState submap: SubmapState {
            preview: true
            safeMode: true
        }
        // The same demand as in Services.qml.
        readonly property Keybinds keybinds: Keybinds {
            preview: fake.previewBinds
            safeMode: true
            command: fake.command
            active: fake.cheatsheet.open || fake.submap.name !== ''
        }
        readonly property FakePopups popups: FakePopups {}
        readonly property QtObject screenshot: QtObject {
            property bool active: false
        }
    }
    property FakeServices services: FakeServices {}
    // 14 described binds and a Lua bind without a description in a submap written "Launch".
    property FakeServices overflowServices: FakeServices {
        previewBinds: false
        command: ['printf', '%s', JSON.stringify(Array.from({ length: 14 }, (unused, index) => ({
            modmask: 0, key: 'code:' + (10 + index), keycode: 0, dispatcher: 'exec', arg: 'app-' + index,
            description: 'Open application ' + index, submap: 'Launch'
        })).concat([{ modmask: 72, key: 'F1', keycode: 0, dispatcher: '__lua', arg: '9', description: '', submap: 'Launch' }]))]
    }
    // The real container in preview: services.submap drives services.keybinds and the host.
    property Services nativeServices: Services {
        preview: true
        safeMode: true
    }

    SubmapHintHost {
        id: host
        services: root.services
    }
    SubmapHintHost {
        id: overflowHost
        services: root.overflowServices
    }
    SubmapHintHost {
        id: nativeHost
        services: root.nativeServices
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
    function rowTexts(target) {
        return findAll(target, item => item.objectName === 'submap-hint-row').map(row => {
            const caps = findAll(row, item => item.objectName === 'submap-hint-keycap').map(cap => cap.label);
            const label = find(row, 'submap-hint-description');
            return caps.join('+') + ' | ' + (label ? label.text : '');
        });
    }
    function shown(target) {
        const window = target.overlay;
        return !!window && !!window.view && window.frame.reveal === 1 && window.width > 0 && window.frame.width > 1;
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
    function grab(target, suffix, next) {
        // The window's own content item has no QML engine to grab with, so the strip itself is captured.
        const frame = target.overlay ? target.overlay.frame : null;
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
            const submap = root.services.submap;
            const binds = root.services.keybinds;
            const window = host.overlay;
            const view = window ? window.view : null;
            const native = root.nativeServices;
            if (root.phase === 0 && ++root.ticks > 4) {
                // Nothing is shown and nothing is read while no submap is active.
                root.check('no-window-without-submap', !host.overlay && !nativeHost.overlay && !overflowHost.overlay
                    && !binds.active && binds.state.kind === 'loading' && root.overflowServices.keybinds.state.kind === 'loading'
                    && native.submap.name === '' && !native.keybinds.active && native.keybinds.state.kind === 'loading',
                    JSON.stringify({ binds: binds.state.kind, native: native.keybinds.state.kind }));
                native.submap.name = 'resize';
                root.phase = 1;
            } else if (root.phase === 1 && root.settled(root.shown(nativeHost) && root.rowTexts(nativeHost.overlay.view).length === 3)) {
                const nativeView = nativeHost.overlay ? nativeHost.overlay.view : null;
                root.check('services-wire-the-submap', !!nativeView && native.keybinds.active && native.keybinds.state.kind === 'ready'
                    && nativeView.captionLabel.text === 'Submap: resize' && root.rowTexts(nativeView).length === 3,
                    JSON.stringify({ active: native.keybinds.active, state: native.keybinds.state.kind,
                        rows: nativeView ? root.rowTexts(nativeView) : null }));
                native.submap.name = '';
                root.phase = 2;
            } else if (root.phase === 2 && root.settled(!nativeHost.overlay)) {
                root.check('services-reset-closes', !nativeHost.overlay && !native.keybinds.active);
                submap.name = 'resize';
                root.phase = 3;
            } else if (root.phase === 3 && root.settled(root.shown(host) && binds.state.kind === 'ready' && root.rowTexts(view).length > 0)) {
                const frame = window.frame;
                const mask = window.mask;
                root.check('calm-overlay-window', window.WlrLayershell.layer === WlrLayer.Overlay
                    && window.WlrLayershell.keyboardFocus === WlrKeyboardFocus.None
                    && window.WlrLayershell.namespace === 'pentad-submap-hint'
                    && window.exclusionMode === ExclusionMode.Normal && window.exclusiveZone === 0,
                    JSON.stringify({ layer: window.WlrLayershell.layer, focus: window.WlrLayershell.keyboardFocus,
                        namespace: window.WlrLayershell.namespace, exclusion: window.exclusionMode, zone: window.exclusiveZone }));
                root.check('clicks-pass-through', !!mask && mask.width === 0 && mask.height === 0 && !mask.item
                    && mask.regions.length === 0, mask ? JSON.stringify([mask.width, mask.height, mask.regions.length]) : 'no mask');
                root.check('bottom-centre', Math.abs(frame.x + frame.width / 2 - window.width / 2) <= 1
                    && frame.y === Metrics.overlayShadowRoom && window.height - (frame.y + frame.height) === Metrics.overlayShadowRoom
                    && frame.width <= Math.min(720, window.width - 32) && frame.width < 720,
                    JSON.stringify({ frame: [frame.x, frame.y, frame.width, frame.height], window: [window.width, window.height] }));
                const caption = view.captionLabel;
                root.check('caption-names-submap', caption.text === 'Submap: resize' && Qt.colorEqual(caption.color, Theme.tokens.textMuted)
                    && caption.font.pixelSize === Metrics.textCaption && view.Accessible.name === 'Submap: resize', caption.text);
                const expected = KeybindHints.submapHint(root.sample.groups, 'resize', { text: 'en' }).rows
                    .map(row => row.keys.join('+') + ' | ' + row.description);
                const rows = root.rowTexts(view);
                root.check('rows-render', JSON.stringify(rows) === JSON.stringify(['→ | resizeactive 20 0', '← | resizeactive -20 0', 'Esc | submap reset'])
                    && JSON.stringify(rows) === JSON.stringify(expected) && view.columns.length === 1
                    && root.findAll(view, item => item.objectName === 'submap-hint-column').length === 1, JSON.stringify(rows));
                const caps = root.findAll(view, item => item.objectName === 'submap-hint-keycap');
                const firstLabel = root.find(view, 'submap-hint-description');
                // The cheatsheet's shared PentadKeycap, raised on its lip over the strip's surface.
                root.check('keycaps-look-like-the-cheatsheet', caps.length === 3
                    && caps.every(cap => String(cap).indexOf('PentadKeycap') === 0 && cap.look === 'raised' && cap.lip === 2
                        && cap.face.radius === Metrics.radiusSmall && cap.height === 24 && Qt.colorEqual(cap.base, Theme.tokens.surface)
                        && cap.hue.a === 0 && cap.text === cap.label)
                    && Qt.colorEqual(firstLabel.color, Theme.tokens.textMuted) && firstLabel.font.pixelSize === Metrics.textBody,
                    JSON.stringify(caps.map(cap => [cap.label, String(cap).split('(')[0], cap.height])));
                root.check('no-overflow-for-few-rows', !view.overflowLabel.visible);
                root.check('binds-read-for-the-submap', binds.active && binds.state.kind === 'ready');
                root.phase = -1;
                root.grab(host, '', () => {
                    root.services.ukrainian = true;
                    root.phase = 4;
                });
            } else if (root.phase === 4 && root.settled(!!view && view.captionLabel.text === 'Режим клавіш: resize')) {
                root.check('ukrainian-caption', view.captionLabel.text === 'Режим клавіш: resize' && root.rowTexts(view).length === 3,
                    view.captionLabel.text);
                root.phase = -1;
                root.grab(host, '.uk.png', () => {
                    root.services.ukrainian = false;
                    root.services.submap.name = 'no-such-mode';
                    root.phase = 5;
                });
            } else if (root.phase === 5 && root.settled(!!view && view.captionLabel.text === 'Submap: no-such-mode')) {
                const columns = root.find(view, 'submap-hint-columns');
                root.check('unknown-submap-shows-caption-only', view.captionLabel.text === 'Submap: no-such-mode'
                    && root.rowTexts(view).length === 0 && !!columns && !columns.visible && !view.overflowLabel.visible
                    && window.frame.height === view.implicitHeight && view.implicitHeight < 60,
                    JSON.stringify({ rows: root.rowTexts(view), height: view.implicitHeight }));
                root.phase = -1;
                root.grab(host, '.empty.png', () => {
                    root.services.submap.name = '';
                    root.phase = 6;
                });
            } else if (root.phase === 6 && root.settled(!host.overlay)) {
                root.check('hides-on-reset', !host.overlay && !binds.active);
                // The cheatsheet card lists the submaps itself; the strip waits behind it.
                root.services.cheatsheet.show();
                submap.name = 'resize';
                root.phase = 7;
            } else if (root.phase === 7 && ++root.ticks > 6) {
                root.check('hidden-while-cheatsheet-open', !host.overlay && submap.name === 'resize' && binds.active);
                root.services.cheatsheet.hide();
                root.phase = 8;
            } else if (root.phase === 8 && root.settled(root.shown(host))) {
                root.check('returns-after-cheatsheet', !!host.overlay && root.rowTexts(host.overlay.view).length === 3);
                // A screenshot is about to be taken: the strip leaves the picture.
                root.services.popups.capturePreparing();
                root.phase = 9;
            } else if (root.phase === 9 && root.settled(!host.overlay)) {
                root.check('steps-aside-for-screenshot', !host.overlay && host.suspended && submap.name === 'resize');
                root.services.screenshot.active = true;
                root.phase = 10;
            } else if (root.phase === 10 && ++root.ticks > 6) {
                root.check('stays-hidden-during-screenshot', !host.overlay);
                root.services.screenshot.active = false;
                root.phase = 11;
            } else if (root.phase === 11 && root.settled(root.shown(host))) {
                root.check('returns-after-screenshot', !!host.overlay && !host.suspended && root.rowTexts(host.overlay.view).length === 3);
                // Registering would make the popup manager grab focus over the bars; the strip never does.
                root.check('never-registers-with-popups', root.services.popups.calls.length === 0
                    && root.overflowServices.popups.calls.length === 0, JSON.stringify(root.services.popups.calls));
                root.overflowServices.submap.name = 'launch';
                root.phase = 12;
            } else if (root.phase === 12 && root.settled(root.shown(overflowHost) && root.overflowServices.keybinds.state.kind === 'ready'
                    && root.rowTexts(overflowHost.overlay.view).length === 12)) {
                const other = overflowHost.overlay;
                const rows = root.rowTexts(other.view);
                root.check('overflow-caps-rows', rows.length === 12 && rows[0] === '1 | Open application 0'
                    && rows[11] === '= | Open application 11' && rows.every(text => text.indexOf('Lua') < 0)
                    && other.view.columns.length === 3 && other.view.overflowLabel.visible && other.view.overflowLabel.text === '+2'
                    && other.view.captionLabel.text === 'Submap: launch' && other.frame.width <= Math.min(720, other.width - 32),
                    JSON.stringify({ rows: rows, columns: other.view.columns.length, overflow: other.view.overflowLabel.text,
                        width: other.frame.width }));
                root.phase = -1;
                root.grab(overflowHost, '.overflow.png', () => {
                    root.overflowServices.submap.name = '';
                    root.phase = 13;
                });
            } else if (root.phase === 13 && root.settled(!overflowHost.overlay)) {
                root.check('overflow-reset-closes', !overflowHost.overlay && !root.overflowServices.keybinds.active);
                // The name comes from the user's config: markup stays text.
                submap.name = '<b>x</b>';
                root.phase = 14;
            } else if (root.phase === 14 && root.settled(!!view && view.captionLabel.text === 'Submap: <b>x</b>')) {
                root.check('name-is-plain-text', view.captionLabel.text === 'Submap: <b>x</b>' && view.captionLabel.textFormat === Text.PlainText,
                    view.captionLabel.text);
                submap.name = '';
                root.phase = 15;
            } else if (root.phase === 15 && root.settled(!host.overlay)) {
                root.check('final-reset-closes', !host.overlay && !binds.active);
                root.finish();
                stop();
            }
            root.stepping = false;
        }
    }
}
