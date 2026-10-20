import QtQuick
import QtQml
import Quickshell
import qs.theme
import qs.features.screenshot
import "../logic/screenshot.mjs" as Model

ShellRoot {
    id: root
    property int phase: 0
    property var checks: []
    property string sourcePath: ''
    readonly property string artifact: Quickshell.env('PENTAD_ARTIFACT_PATH')
    readonly property var windowRegions: [
        { x: 60, y: 70, width: 560, height: 420, title: 'Files — Documents', address: '0x1', outputId: 'fixture' },
        { x: 560, y: 220, width: 560, height: 440, title: 'Terminal — pentad', address: '0x2', outputId: 'fixture' }
    ]
    readonly property var region: ({ x: 300, y: 180, width: 560, height: 380 })
    property QtObject services: QtObject {
        property bool preview: true
        property bool safeMode: true
        property var config: QtObject {
            property var documents: ({
                    screenshots: {
                        color: '#ff5252',
                        strokeWidth: 4,
                        fontSize: 24,
                        localKeys: { cancel: 'Esc', copy: 'Ctrl+C', save: 'Ctrl+S', undo: 'Ctrl+Z', redo: 'Ctrl+Shift+Z' }
                    }
                })
            function save(name, value) {}
        }
        function text(uk, en) { return en; }
    }
    property QtObject screenshot: QtObject {
        property string outputId: 'fixture'
        property string imagePath: root.sourcePath
        property int imageWidth: 1200
        property int imageHeight: 800
        property var windowRegions: root.windowRegions
        property bool busy: false
        property string phase: 'selecting'
        property string error: ''
        property var lastExport: null
        signal exported(bool closeAfter)
        function chooseOutput(output) { return true; }
        function exportImage(document, action, closeAfter) { return true; }
        function close() {}
    }

    function check(name, passed, detail) { checks.push({ name: name, passed: passed === true, detail: detail || '' }); }
    function finish() {
        console.log('PENTAD_TEST ' + JSON.stringify({
            status: checks.every(function (item) { return item.passed; }) ? 'pass' : 'fail',
            checks: checks
        }));
        Qt.quit();
    }
    function find(item, name) {
        if (!item) return null;
        if (item.objectName === name) return item;
        for (const child of item.children || []) { const found = find(child, name); if (found) return found; }
        return null;
    }
    function capture(suffix, next, item) {
        (item || stage).grabToImage(function (result) {
            root.check('capture' + (suffix || '-selecting'), result.saveToFile(root.artifact + suffix));
            next();
        });
    }

    FloatingWindow {
        id: fixtureWindow
        visible: true
        implicitWidth: 1200
        implicitHeight: 800
        color: 'black'

        Item {
        id: stage
        anchors.fill: parent
        Item {
            id: desktop
            width: 1200
            height: 800
            visible: root.phase === 0
            Rectangle {
                anchors.fill: parent
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0; color: '#3b5b7a' }
                    GradientStop { position: 1; color: '#c38a5c' }
                }
            }
            Repeater {
                model: root.windowRegions
                Rectangle {
                    required property var modelData
                    required property int index
                    x: modelData.x; y: modelData.y; width: modelData.width; height: modelData.height
                    radius: 10
                    color: index === 0 ? '#f4f1ea' : '#1d2125'
                    Rectangle { width: parent.width; height: 34; radius: 10; color: index === 0 ? '#e2ddd2' : '#2b3137' }
                    Text { x: 14; y: 8; text: parent.modelData.title; color: parent.index === 0 ? '#333' : '#ddd'; font.pixelSize: 15 }
                    Column {
                        x: 18; y: 54; spacing: 12
                        Repeater {
                            model: 10
                            Rectangle {
                                required property int index
                                width: 160 + (index * 47) % 300; height: 10; radius: 5
                                color: parent.parent.index === 0 ? '#c9c2b4' : (index % 3 === 0 ? '#7bd88f' : '#5c6670')
                            }
                        }
                    }
                }
            }
        }

        Loader {
            id: editorLoader
            anchors.fill: parent
            active: !!root.sourcePath
            sourceComponent: ScreenshotEditor {
                services: root.services
                screenshot: root.screenshot
                outputId: 'fixture'
                capture: ({ path: root.sourcePath, width: 1200, height: 800, windowRegions: root.windowRegions })
                mode: 'edit'
                initialCrop: null
            }
        }
        ScreenshotCrosshair {
            anchors.fill: parent
            visible: root.phase === 2
            camera: true
            pointX: 320.4
            pointY: 260.6
            label: 'Files — Documents'
        }
        ScreenshotCrosshair {
            id: crosshairProbe
            anchors.fill: parent
            visible: root.phase === 3
            pointX: 980.4
            pointY: 140.6
            label: '980, 140'
        }
        }
    }

    Timer {
        id: poll
        interval: 60
        repeat: true
        running: true
        onTriggered: {
            const editor = editorLoader.item;
            const canvas = root.find(editor, 'screenshot-canvas');
            const toolbar = root.find(editor, 'screenshot-toolbar');
            if (root.phase === 0) {
                root.phase = 1;
                desktop.grabToImage(function (result) {
                    const target = root.artifact + '.source.png';
                    root.check('fixture-desktop-rendered', result.saveToFile(target));
                    root.sourcePath = target;
                });
            } else if (root.phase === 1 && editor && editor.ready && canvas) {
                root.check('selector-starts-in-selection-mode', canvas.selecting && !toolbar.visible);
                canvas.hoverWindow = root.windowRegions[0];
                canvas.hoverTitle = root.windowRegions[0].title;
                root.phase = 2;
                stop();
                settle.start();
            } else if (root.phase === 4) {
                const rect = root.region;
                canvas.gesture = { kind: 'new-crop', start: { x: rect.x, y: rect.y } };
                canvas.draft = { kind: 'crop', rect: rect };
                root.phase = 5;
                stop();
                settle.start();
            } else if (root.phase === 6) {
                canvas.gesture = null;
                canvas.draft = null;
                editor.edit(Model.setCrop(editor.document, root.region));
                canvas.selecting = false;
                editor.tool = 'arrow';
                root.phase = 7;
                stop();
                settle.start();
            }
        }
    }
    Timer {
        id: settle
        interval: 400
        onTriggered: {
            const editor = editorLoader.item;
            const canvas = root.find(editor, 'screenshot-canvas');
            const toolbar = root.find(editor, 'screenshot-toolbar');
            if (root.phase === 2) {
                root.check('hovered-window-shows-camera-hole', canvas.hoverWindow && canvas.hoverTitle === 'Files — Documents');
                root.capture('', function () {
                    root.phase = 3;
                    settle.start();
                });
            } else if (root.phase === 3) {
                root.capture('.crosshair.png', function () {
                    root.phase = 4;
                    canvas.hoverWindow = null;
                    canvas.hoverTitle = '';
                    poll.start();
                });
            } else if (root.phase === 5) {
                root.check('dragged-region-reports-size', canvas.sizeLabel(canvas.draftCrop) === '560 × 380');
                root.capture('.region.png', function () {
                    root.phase = 6;
                    poll.start();
                });
            } else if (root.phase === 7) {
                const crop = canvas.cropView;
                root.check('toolbar-appears-after-selection', toolbar.visible && !canvas.selecting);
                root.check('toolbar-defaults-below-selection', toolbar.horizontal
                    && Math.abs(toolbar.y - (crop.y + crop.height + 10)) < 0.5
                    && Math.abs(toolbar.x + toolbar.width / 2 - (crop.x + crop.width / 2)) < 0.5,
                    JSON.stringify({ x: toolbar.x, y: toolbar.y, w: toolbar.width, crop: crop }));
                root.capture('.selected.png', function () {
                    toolbar.dragged(crop.x + crop.width - 20, crop.y + 30, 10);
                    root.phase = 8;
                    settle.start();
                });
            } else if (root.phase === 8) {
                const crop = canvas.cropView;
                const insideRight = !toolbar.horizontal && toolbar.x + toolbar.width <= crop.x + crop.width
                    && toolbar.x >= crop.x + crop.width - toolbar.width - 11;
                root.check('toolbar-docks-vertically-inside-right-edge', insideRight,
                    JSON.stringify({ x: toolbar.x, y: toolbar.y, w: toolbar.width, h: toolbar.height, crop: crop }));
                root.check('toolbar-length-is-orientation-independent', Math.abs(toolbar.height - toolbar.length) < 0.5);
                root.capture('.right.png', function () {
                    toolbar.dragged(crop.x - 80, crop.y + crop.height + 10, 10);
                    root.phase = 9;
                    settle.start();
                });
            } else if (root.phase === 9) {
                const crop = canvas.cropView;
                root.check('toolbar-docks-outside-left-edge', !toolbar.horizontal && toolbar.x + toolbar.width <= crop.x,
                    JSON.stringify({ x: toolbar.x, y: toolbar.y, crop: crop }));
                root.capture('.left.png', function () {
                    const colorButton = root.toolbarColorChip(toolbar);
                    if (colorButton)
                        colorButton.clicked();
                    root.phase = 10;
                    settle.start();
                });
            } else if (root.phase === 10) {
                root.check('color-chip-opens-palette', toolbar.paletteMenu.visible);
                root.capture('.palette.png', function () {
                    root.finish();
                }, toolbar.paletteMenu.contentItem.parent);
            }
        }
    }
    function toolbarColorChip(toolbar) {
        const queue = [toolbar];
        while (queue.length) {
            const item = queue.shift();
            if (item.accessibleName && String(item.accessibleName).indexOf('Color ') === 0 && item.clicked)
                return item;
            for (const child of item.children || [])
                queue.push(child);
        }
        return null;
    }
}
