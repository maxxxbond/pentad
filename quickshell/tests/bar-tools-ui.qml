import QtQuick
import QtTest
import Quickshell
import qs.theme
import qs.services
import qs.shell

// Real Services and a real bar: clicks the new bar tools and follows each click down to the Desktop
// service. slurp, grim, the clipboard and the browser are stand-ins supplied through PATH.
ShellRoot {
    id: root
    property Services services: Services { }
    property var checks: []
    property var finished: []
    property int step: -1
    property int waitingFor: 0
    property TestEvent pointer: TestEvent {}
    function check(name, passed, detail) { checks.push({ name: name, passed: passed === true, detail: detail || '' }); }
    function findNamed(item, name) {
        if (!item) return null;
        if (item.objectName === name) return item;
        for (const child of item.children || []) {
            const found = findNamed(child, name);
            if (found) return found;
        }
        return null;
    }
    function findText(item, value) {
        if (!item) return null;
        if (item.text === value) return item;
        for (const child of item.children || []) {
            const found = findText(child, value);
            if (found) return found;
        }
        return null;
    }
    function click(name) {
        const target = root.findNamed(bar.barFace, name);
        root.check(name + '-exists', !!target);
        if (!target) return false;
        root.waitingFor = root.finished.length + 1;
        root.check(name + '-click-dispatched', root.pointer.mouseClick(target, target.width / 2, target.height / 2, Qt.LeftButton, Qt.NoModifier, 0));
        return true;
    }
    property int hold: 0
    property var photoRect: null
    // The tools choose their area in Pentad's own overlay. Unless a step drives the overlay by hand, this
    // "user" moves to a spot on the synthetic page and clicks the thing suggested there.
    property string autoPick: 'text'
    property int autoStage: 0
    property int autoWaits: 0
    property int retries: 0
    readonly property var pickPoints: ({ text: { x: 820, y: 140 }, photo: { x: 300, y: 225 }, card: { x: 360, y: 560 } })
    function overlayCanvas() {
        const windows = screenshotHost.instances || [];
        for (let i = 0; i < windows.length; i++) {
            const found = root.findNamed(windows[i].contentItem, 'screenshot-canvas');
            if (found && found.visible) return found;
        }
        return null;
    }
    function overlayReady() {
        const canvas = root.overlayCanvas();
        return !!canvas && canvas.selecting && canvas.imageReady && root.services.screenshot.phase === 'selecting' ? canvas : null;
    }
    function near(rect, x, y, width, height, slack) {
        return !!rect && Math.abs(rect.x - x) <= slack && Math.abs(rect.y - y) <= slack
            && Math.abs(rect.width - width) <= slack * 2 && Math.abs(rect.height - height) <= slack * 2;
    }
    // Click without waiting for a desktop command result (the toggles answer through other services).
    function clickNow(name) {
        const target = root.findNamed(bar.barFace, name);
        root.check(name + '-exists', !!target);
        if (target) root.check(name + '-click-dispatched', root.pointer.mouseClick(target, target.width / 2, target.height / 2, Qt.LeftButton, Qt.NoModifier, 0));
    }
    function showOnly(ids) {
        // Keys that are left out fall back to the defaults, so every tool is named explicitly.
        const show = {};
        ['dnd', 'inhibit', 'night', 'bluetooth', 'airplane', 'saver', 'overnight', 'focus', 'privacy', 'screenshot', 'record', 'ocr', 'picker',
            'translate', 'imageSearch', 'qrScan', 'audioOutput', 'ruler', 'magnifier'].forEach(function(id) { show[id] = ids.indexOf(id) >= 0; });
        const layout = Object.assign({}, root.services.config.documents.layout,
            { barTools: Object.assign({}, root.services.config.documents.layout.barTools, { show: show }) });
        root.services.config.documents = Object.assign({}, root.services.config.documents, { layout: layout });
    }
    function finish() {
        const passed = checks.length > 0 && checks.every(function(item) { return item.passed; });
        console.log('PENTAD_TEST ' + JSON.stringify({ status: passed ? 'pass' : 'fail', checks: checks }));
        Qt.quit();
    }
    Connections {
        target: root.services.desktop
        function onCommandFinished(requestId, result) { root.finished = root.finished.concat([result]); }
    }
    ScreenshotHost { id: screenshotHost; services: root.services }
    Timer {
        id: autopilot
        interval: 200; repeat: true; running: root.autoPick !== 'off'
        onTriggered: {
            const canvas = root.overlayReady();
            if (!canvas) { root.autoStage = 0; return; }
            // Suggestions come from the helper a moment after the overlay appears; give them time.
            if (!canvas.contentRegions.length && root.autoWaits++ < 20) return;
            const point = canvas.viewPoint(root.pickPoints[root.autoPick]);
            if (root.autoStage === 0) { root.pointer.mouseMove(canvas, point.x, point.y, 0, Qt.NoButton, Qt.NoModifier); root.autoStage = 1; return; }
            root.autoStage = 0;
            root.autoWaits = 0;
            root.pointer.mouseClick(canvas, point.x, point.y, Qt.LeftButton, Qt.NoModifier, 0);
        }
    }
    Loader {
        id: magnifier
        active: root.services.desktop.magnifierSource !== ''
        sourceComponent: Component { MagnifierWindow { services: root.services } }
    }
    BarWindow {
        id: bar
        services: root.services
        screen: Quickshell.screens[0]
    }
    // Nothing in this fixture may wait forever: a stuck step ends the run with a report.
    Timer {
        interval: 170000; running: true
        onTriggered: { root.check('fixture-completed-in-time', false, 'stuck at step ' + root.step); root.finish(); }
    }
    Timer {
        id: driver
        interval: 400; running: true; repeat: true
        property int waited: 0
        onTriggered: {
            if (root.hold > 0) { root.hold--; return; }
            if (root.waitingFor > root.finished.length) {
                waited++;
                if (waited > 40) { const shot = root.services.screenshot;
                    const canvas = root.overlayCanvas();
                    root.check('tool-command-finished-in-time', false, JSON.stringify({ step: root.step, active: shot.active, phase: shot.phase, mode: shot.mode,
                        error: shot.error, token: shot.pickToken, canvas: !!canvas, selecting: canvas ? canvas.selecting : null, ready: canvas ? canvas.imageReady : null,
                        regions: canvas ? canvas.contentRegions.length : -1, hover: canvas ? canvas.hoverWindow : null, frames: Object.keys(shot.frames).map(function(key) { return key + ':' + (shot.frames[key].contentRegions || []).length; }), helper: shot.helperPath })); root.finish(); }
                return;
            }
            waited = 0;
            root.step++;
            const widget = root.findNamed(bar.barFace, 'quick-tools-widget');
            const last = root.finished.length ? root.finished[root.finished.length - 1] : null;
            if (root.step === 0) {
                root.check('tools-widget-present', !!widget);
                root.check('default-tools-drawn', !!widget && widget.buttonRepeater.count === 8, widget ? String(widget.buttonRepeater.count) : '');
                root.check('desktop-service-ready', root.services.desktop.state.kind === 'ready', JSON.stringify(root.services.desktop.state.kind));
                root.click('tools-input-ocr');
            } else if (root.step === 1) {
                root.check('ocr-finished-ok', !!last && last.ok === true && last.reason === 'ok', JSON.stringify(last));
                root.click('tools-input-picker');
            } else if (root.step === 2) {
                root.check('picker-finished-ok', !!last && last.ok === true, JSON.stringify(last));
                root.click('tools-input-translate');
            } else if (root.step === 3) {
                root.check('translate-without-key-reports-it', !!last && last.ok === false && last.reason === 'missing-key', JSON.stringify(last));
                root.click('tools-input-image-search');
            } else if (root.step === 4) {
                root.check('image-search-asks-which-engine', !!last && last.ok === true && last.reason === 'choose', JSON.stringify(last));
                root.check('engine-popup-opened', !!widget && widget.searchPopup.opened === true);
                const engine = widget && widget.searchPopup.contentItem ? root.findText(widget.searchPopup.contentItem, 'Yandex') : null;
                root.check('engine-button-listed', !!engine);
                if (engine) {
                    root.waitingFor = root.finished.length + 1;
                    root.check('engine-button-click-dispatched', root.pointer.mouseClick(engine, engine.width / 2, engine.height / 2, Qt.LeftButton, Qt.NoModifier, 0));
                } else root.finish();
            } else if (root.step === 5) {
                root.check('chosen-engine-opened', !!last && last.ok === true && last.reason === 'opened', JSON.stringify(last));
                root.check('tool-busy-cleared', root.services.desktop.state.value.toolBusy === false);
                // The file helper is not available in this harness, so the document is replaced in memory.
                root.showOnly(['dnd', 'inhibit', 'night', 'bluetooth', 'airplane', 'saver', 'overnight', 'focus', 'privacy', 'screenshot', 'record', 'ocr',
                    'picker', 'translate', 'imageSearch', 'qrScan', 'audioOutput', 'ruler', 'magnifier']);
            } else if (root.step === 6) {
                root.check('all-nineteen-tools-drawn', !!widget && widget.buttonRepeater.count === 19, widget ? String(widget.buttonRepeater.count) : '');
                // Overnight mode is drawn but never clicked: it would block sleep on the shared system bus.
                ['night', 'bluetooth', 'airplane', 'saver', 'overnight'].forEach(function(id) {
                    root.check(id + '-toggle-drawn', !!root.findNamed(bar.barFace, 'tools-input-' + id));
                });
                // The test window is narrow; with fewer tools the pill does not run under the status area.
                root.showOnly(['dnd', 'inhibit', 'focus', 'privacy', 'qrScan', 'audioOutput']);
                root.hold = 2;
            } else if (root.step === 7) {
                root.click('tools-input-focus');
            } else if (root.step === 8) {
                root.check('focus-finished-ok', !!last && last.ok === true, JSON.stringify(last));
                const privacy = root.findNamed(bar.barFace, 'tools-input-privacy');
                root.check('privacy-click-dispatched', !!privacy && root.pointer.mouseClick(privacy, privacy.width / 2, privacy.height / 2, Qt.LeftButton, Qt.NoModifier, 0));
            } else if (root.step === 9) {
                root.check('focus-marker-seen-by-service', root.services.desktop.focusActive === true, String(root.services.desktop.focusActive));
                root.check('privacy-hides-notification-text', root.services.notifications.privacy === true);
                const qr = root.findNamed(bar.barFace, 'tools-input-qr-scan');
                root.check('qr-tool-available', !!qr && qr.parent.actionAvailable === true,
                    JSON.stringify({ state: qr ? qr.parent.toolState : null, desktop: root.services.desktop.state.value, x: qr ? qr.parent.x : -1, w: widget ? widget.width : -1 }));
                root.click('tools-input-qr-scan');
            } else if (root.step === 10) {
                root.check('qr-without-code-reports-it', !!last && last.ok === false && last.reason === 'no-text', JSON.stringify(last));
                root.click('tools-input-audio-output');
            } else if (root.step === 11) {
                root.check('audio-output-finished-ok', !!last && last.ok === true, JSON.stringify(last));
                root.showOnly(['ruler', 'magnifier', 'night', 'bluetooth', 'airplane', 'saver']);
                root.hold = 2;
            } else if (root.step === 12) {
                root.click('tools-input-ruler');
            } else if (root.step === 13) {
                root.check('ruler-finished-ok', !!last && last.ok === true && last.reason === 'ok', JSON.stringify(last));
                const lens = root.findNamed(bar.barFace, 'tools-input-magnifier');
                root.check('magnifier-tool-available', !!lens && lens.parent.actionAvailable === true,
                    JSON.stringify({ state: lens ? lens.parent.toolState : null, busy: root.services.desktop.scriptRequest, cfg: root.services.desktop.barTools ? root.services.desktop.barTools.magnifier : null }));
                root.click('tools-input-magnifier');
            } else if (root.step === 14) {
                root.check('magnifier-finished-ok', !!last && last.ok === true && last.reason === 'ok', JSON.stringify(last));
                root.check('magnifier-source-set', root.services.desktop.magnifierSource.startsWith('/') && root.services.desktop.magnifierSource.endsWith('.png'), root.services.desktop.magnifierSource);
                root.hold = 2;
            } else if (root.step === 15) {
                const shown = magnifier.item;
                root.check('magnifier-window-opened', !!shown && shown.visible === true);
                root.check('magnifier-image-loaded', !!shown && shown.picture.status === Image.Ready && shown.picture.width > 0, shown ? String(shown.picture.status) + ' ' + shown.picture.width : '');
                root.hold = 2;
            } else if (root.step === 16) {
                const shown = magnifier.item;
                const stage = shown ? root.findNamed(shown.contentItem, 'magnifier-stage') : null;
                root.check('magnifier-stage-found', !!stage);
                if (stage) stage.forceActiveFocus();
                root.check('magnifier-escape-dispatched', root.pointer.keyClick(Qt.Key_Escape, Qt.NoModifier, 0));
                root.hold = 2;
            } else if (root.step === 17) {
                root.check('magnifier-closed-by-escape', root.services.desktop.magnifierSource === '' && magnifier.item === null, root.services.desktop.magnifierSource);
                const night = root.findNamed(bar.barFace, 'tools-input-night');
                root.check('night-available-from-backend', !!night && night.parent.actionAvailable === true, night ? JSON.stringify(night.parent.toolState) : '');
                root.clickNow('tools-input-night');
                root.hold = 3;
            } else if (root.step === 18) {
                const night = root.findNamed(bar.barFace, 'tools-input-night');
                root.check('night-toggle-is-on', !!night && night.parent.toolState.active === true, night ? JSON.stringify(night.parent.toolState) : '');
                root.clickNow('tools-input-airplane');
                root.hold = 4;
            } else if (root.step === 19) {
                // With a real Bluetooth adapter visible, the airplane read-back cannot match the stand-in radios,
                // so only the issued command is checked (by the runner); the toggle itself must stay drawn.
                root.check('airplane-toggle-still-drawn', !!root.findNamed(bar.barFace, 'tools-input-airplane'));
                root.clickNow('tools-input-saver');
                root.hold = 4;
            } else if (root.step === 20) {
                const saver = root.findNamed(bar.barFace, 'tools-input-saver');
                root.check('saver-toggle-is-on', !!saver && saver.parent.toolState.active === true, saver ? JSON.stringify(saver.parent.toolState) : '');
                // The system bus is shared with the real session, so a real adapter may be visible here.
                // Bluetooth is therefore drawn but never clicked: that would switch the real adapter.
                root.check('bluetooth-toggle-is-drawn-and-left-alone', !!root.findNamed(bar.barFace, 'tools-input-bluetooth'));
                root.hold = 1;
            } else if (root.step === 21) {
                // From here the overlay is driven by hand.
                root.autoPick = 'off';
                root.showOnly(['ocr']);
                root.hold = 2;
            } else if (root.step === 22) {
                root.clickNow('tools-input-ocr');
                root.hold = 1;
            } else if (root.step === 23) {
                const canvas = root.overlayReady();
                if (!canvas && ++root.retries < 40) { root.step--; return; }
                root.retries = 0;
                root.check('overlay-opened-in-pick-mode', !!canvas && root.services.screenshot.mode === 'pick', canvas ? root.services.screenshot.mode : 'no overlay');
                root.check('overlay-names-the-tool', !!root.services.screenshot.pickLabel, root.services.screenshot.pickLabel);
            } else if (root.step === 24) {
                const canvas = root.overlayReady();
                if (canvas && !canvas.contentRegions.length && ++root.retries < 40) { root.step--; return; }
                root.retries = 0;
                const kinds = canvas ? canvas.contentRegions.map(function(item) { return item.kind; }) : [];
                root.check('suggestions-arrive-from-the-frozen-pixels', kinds.indexOf('image') >= 0 && kinds.indexOf('text') >= 0, JSON.stringify(kinds));
                const photo = canvas ? canvas.viewPoint(root.pickPoints.photo) : null;
                if (photo) root.pointer.mouseMove(canvas, photo.x, photo.y, 0, Qt.NoButton, Qt.NoModifier);
                root.hold = 1;
            } else if (root.step === 25) {
                const canvas = root.overlayReady();
                const small = canvas ? canvas.hoverWindow : null;
                root.check('hover-highlights-the-photo', root.near(small, 100, 100, 400, 250, 14), JSON.stringify(small));
                root.check('hover-names-what-it-is', !!canvas && canvas.hoverTitle.indexOf('Image') === 0, canvas ? canvas.hoverTitle : '');
                const before = canvas ? canvas.hoverWindow : null;
                const photo = canvas ? canvas.viewPoint(root.pickPoints.photo) : null;
                if (canvas && typeof root.pointer.mouseWheel === 'function') root.pointer.mouseWheel(canvas, photo.x, photo.y, Qt.NoButton, Qt.NoModifier, 0, 120, 0);
                else if (canvas) canvas.stepHover(1);
                root.photoRect = before;
                root.hold = 1;
            } else if (root.step === 26) {
                const canvas = root.overlayReady();
                const grown = canvas ? canvas.hoverWindow : null;
                root.check('wheel-up-grows-the-suggestion', !!grown && !!root.photoRect && grown.width * grown.height > root.photoRect.width * root.photoRect.height && canvas.hoverLevel === 1,
                    JSON.stringify({ grown: grown, level: canvas ? canvas.hoverLevel : -1 }));
                const photo = canvas ? canvas.viewPoint(root.pickPoints.photo) : null;
                if (canvas && typeof root.pointer.mouseWheel === 'function') root.pointer.mouseWheel(canvas, photo.x, photo.y, Qt.NoButton, Qt.NoModifier, 0, -120, 0);
                else if (canvas) canvas.stepHover(-1);
                root.hold = 1;
            } else if (root.step === 27) {
                const canvas = root.overlayReady();
                root.check('wheel-down-returns-to-the-photo', !!canvas && canvas.hoverLevel === 0 && root.near(canvas.hoverWindow, 100, 100, 400, 250, 14), canvas ? JSON.stringify(canvas.hoverWindow) : '');
                const last = canvas ? canvas.hoverChain[canvas.hoverChain.length - 1] : null;
                root.check('the-whole-screen-is-the-last-step', !!last && last.kind === 'screen', JSON.stringify(last));
                const card = canvas ? canvas.viewPoint(root.pickPoints.card) : null;
                if (card) root.pointer.mouseMove(canvas, card.x, card.y, 0, Qt.NoButton, Qt.NoModifier);
                root.hold = 1;
            } else if (root.step === 28) {
                const canvas = root.overlayReady();
                root.check('hover-finds-the-card-as-a-panel', !!canvas && canvas.hoverTitle.indexOf('Panel') === 0 && root.near(canvas.hoverWindow, 100, 458, 520, 192, 16),
                    canvas ? canvas.hoverTitle + ' ' + JSON.stringify(canvas.hoverWindow) : '');
                // Escape gives up without choosing anything.
                root.waitingFor = root.finished.length + 1;
                root.check('escape-dispatched', root.pointer.keyClick(Qt.Key_Escape, Qt.NoModifier, 0));
            } else if (root.step === 29) {
                root.check('escape-cancels-the-pick', !!last && last.ok === false && last.reason === 'cancelled', JSON.stringify(last));
                root.check('overlay-closed-and-tool-free-again', root.services.screenshot.active === false && root.services.desktop.state.value.toolBusy === false);
            } else if (root.step === 30) {
                const path = Quickshell.env('PENTAD_ARTIFACT_PATH');
                if (!path) root.finish();
                else bar.barFace.grabToImage(function(result) {
                    root.check('bar-capture-saved', result.saveToFile(path));
                    root.finish();
                });
            }
        }
    }
}
