import QtQuick
import QtTest
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.services
import qs.features.shelf
import qs.theme
import qs.components

ShellRoot {
    id: root
    property var checks: []
    property int phase: 0
    property int ticks: 0
    property int exports: 0
    property int nativeDrags: 0
    property bool invitationSeen: false
    property var exportedUris: []
    property var receivedUris: []
    property TestEvent testPointer: TestEvent {}
    Component.onCompleted: Theme.resolve({ appearance: Quickshell.env('PENTAD_GALLERY_APPEARANCE') || 'dark',
        accent: Quickshell.env('PENTAD_GALLERY_ACCENT') || '#869677', fontFamily: 'Geist',
        reducedMotion: Quickshell.env('PENTAD_GALLERY_REDUCED_MOTION') === '1' })
    property string imageUri: Qt.resolvedUrl('assets/icons/brand/logo-symbolic.svg').toString()
    property string textUri: Qt.resolvedUrl('tests/fixtures/tool-sample.json').toString()
    property string pdfUri: Qt.resolvedUrl('tests/fixtures/shelf-preview.pdf').toString()
    property string folderUri: Qt.resolvedUrl('tests/fixtures/').toString()
    property string missingUri: Qt.resolvedUrl('tests/fixtures/absent.png').toString()
    property ShelfFiles metadata: ShelfFiles {
        entries: root.shelf.entries
        helperPath: decodeURIComponent(Qt.resolvedUrl('helpers/pentad_shelf_preview.py').toString().replace(/^file:\/\//, ''))
    }
    property QtObject shelf: QtObject {
        property bool ready: true
        property bool writable: true
        property string loadError: ''
        property var files: root.metadata
        property var entries: [
            { id: 'photo', label: 'Світлина.svg', uri: root.imageUri },
            { id: 'text', label: 'Документ із довгою назвою.json', uri: root.textUri },
            { id: 'pdf', label: 'Документ.pdf', uri: root.pdfUri },
            { id: 'folder', label: 'Папка', uri: root.folderUri },
            { id: 'missing', label: 'Видалений файл.png', uri: root.missingUri }
        ]
        signal commandFinished(string requestId, var result)
        function addUris(uris) { return ''; }
        function remove(id) { return ''; }
    }
    property QtObject receiverShelf: QtObject {
        property bool ready: true
        property bool writable: true
        property string loadError: ''
        property var files: root.metadata
        property var entries: []
        signal commandFinished(string requestId, var result)
        function addUris(uris) {
            root.receivedUris = uris;
            entries = uris.map((uri, index) => ({ id: 'received-' + index, label: 'Received file', uri }));
            Qt.callLater(() => commandFinished('native-drop', { ok: true }));
            return 'native-drop';
        }
        function remove(id) { return ''; }
    }
    PanelWindow {
        id: sourceWindow
        screen: Quickshell.screens[0]
        anchors { left: true; top: true }
        margins { left: 24; top: 180 }
        exclusiveZone: 0
        WlrLayershell.layer: WlrLayer.Overlay
        visible: true
        implicitWidth: 460; implicitHeight: 500
        color: Theme.tokens.surface
        Rectangle {
            id: capture
            anchors.fill: parent; color: Theme.tokens.surface
            PentadScrollView {
                id: sourceScroll
                x: 20; y: 20; width: 420; height: 300
                contentWidth: availableWidth; contentHeight: grid.implicitHeight
                ShelfGrid { id: grid; width: sourceScroll.availableWidth; shelf: root.shelf; readOnly: false; language: 'uk' }
            }
        }
    }
    PanelWindow {
        screen: Quickshell.screens[0]
        anchors { left: true; top: true }
        margins { left: 650; top: 180 }
        exclusiveZone: 0
        WlrLayershell.layer: WlrLayer.Overlay
        visible: true
        implicitWidth: 440; implicitHeight: 420
        color: Theme.tokens.surfaceRaised
        ShelfGrid {
            id: receiverGrid
            anchors.fill: parent; shelf: root.receiverShelf; readOnly: false; language: 'uk'
            onDropInvitedChanged: if (dropInvited) {
                root.invitationSeen = true;
                invitationCapture.restart();
            }
        }
        Timer {
            id: invitationCapture
            interval: 180
            onTriggered: receiverGrid.grabToImage(result => result.saveToFile(Quickshell.env('PENTAD_ARTIFACT_PATH') + '.drop.png'))
        }
    }
    Process {
        id: driver
        stderr: SplitParser { onRead: line => console.log('DND_DRIVER_ERROR ' + line) }
        command: [Quickshell.env('PENTAD_DND_DRIVER'), String(sourceWindow.screen.x + 111), String(sourceWindow.screen.y + 280),
            String(sourceWindow.screen.x + 870), String(sourceWindow.screen.y + 300)]
        onStarted: console.log('DND_DRIVER ' + JSON.stringify(command) + ' screen=' + sourceWindow.screen.name)
        onExited: code => console.log('DND_DRIVER_EXIT ' + code)
    }
    function find(item, name) {
        if (item.objectName === name) return item;
        for (const child of item.children || []) { const result = find(child, name); if (result) return result; }
        return null;
    }
    function check(name, passed) { checks = checks.concat([{ name, passed: !!passed }]); }
    Timer {
        interval: 100; repeat: true; running: true
        onTriggered: {
            root.ticks++;
            if (root.phase === 0 && root.metadata.metadata[root.imageUri]?.thumbnail && root.metadata.metadata[root.pdfUri]?.thumbnail) {
                root.check('system-thumbnail-is-generated-and-cached', root.metadata.metadata[root.imageUri].thumbnail.startsWith('file://'));
                root.check('pdf-system-thumbnail-is-generated', root.metadata.metadata[root.pdfUri].thumbnail.startsWith('file://'));
                root.check('folder-metadata-and-missing-file-state', root.metadata.metadata[root.folderUri]?.folder
                    && root.metadata.metadata[root.missingUri]?.available === false);
                const preview = root.find(grid, 'shelf-thumbnail-photo');
                if (preview.status !== Image.Ready) return;
                root.check('generated-thumbnail-reaches-visible-tile', true);
                grid.selectEntry('photo', Qt.NoModifier);
                grid.selectEntry('text', Qt.ControlModifier);
                root.check('control-selection-exports-both-file-uris', grid.selectedUris(root.shelf.entries[0]).length === 2);
                const tile = preview.parent;
                tile.exportStarted.connect(uris => { root.exports++; root.exportedUris = uris; });
                tile.Drag.dragStarted.connect(() => root.nativeDrags++);
                driver.running = true;
                root.phase = 1;
            } else if (root.phase === 1 && root.receivedUris.length > 0 && !driver.running) {
                const tile = root.find(grid, 'shelf-thumbnail-photo').parent;
                root.check('native-drag-starts-with-selected-files-and-preview', root.nativeDrags === 1
                    && root.exportedUris.length === 2 && String(tile.Drag.imageSource).length > 0);
                root.check('native-drop-into-empty-shelf-receives-both-file-uris', root.receivedUris.length === 2
                    && root.receivedUris[0] === root.imageUri && root.receivedUris[1] === root.textUri);
                root.check('native-hover-shows-drop-invitation', root.invitationSeen);
                root.check('successful-drop-shows-confirmation', receiverGrid.dropConfirmed);
                root.check('native-drag-does-not-move-grid-tile', tile.x === 0 && tile.y === 0);
                const missing = root.find(grid, 'shelf-thumbnail-missing').parent;
                root.check('missing-file-cannot-start-export', !missing.beginExport());
                grid.selectEntry('photo', Qt.NoModifier);
                grid.selectEntry('pdf', Qt.ShiftModifier);
                root.check('shift-selects-contiguous-range', grid.selectedIds.length === 3);
                root.testPointer.mouseClick(tile.mouseArea, tile.width / 2, 110, Qt.RightButton, Qt.NoModifier, 0);
                root.check('right-click-opens-context-for-selection', grid.itemMenu.visible && grid.itemMenu.entries.length === 2);
                grid.itemMenu.close();
                grid.selectEntry('photo', Qt.NoModifier);
                grid.navigate('photo', 1, Qt.NoModifier);
                root.check('keyboard-navigation-focuses-selected-tile', grid.selectedEntry.id === 'text' && grid.selectedTile.activeFocus);
                grid.selectEntry('photo', Qt.NoModifier);
                grid.selectEntry('text', Qt.ControlModifier);
                const widgetComponent = Qt.createComponent('widgets/shelf/View.qml');
                const widget = widgetComponent.status === Component.Ready ? widgetComponent.createObject(sourceWindow.contentItem, {
                    instanceId: 'shelf-fixture', context: { preview: false }, settings: {},
                    services: { shelf: root.shelf }, controller: {}, visible: false
                }) : null;
                root.check('standalone-widget-uses-shared-grid-with-positive-width', widget && widget.shelfGrid
                    && widget.shelfGrid.shelf === root.shelf && widget.shelfGrid.width > 300);
                capture.grabToImage(result => {
                    root.check('shelf-nautilus-capture', result.saveToFile(Quickshell.env('PENTAD_ARTIFACT_PATH')));
                    root.phase = 2;
                });
                root.phase = -1;
            } else if (root.phase === 2) {
                root.receivedUris = [];
                root.shelf.entries = [{ id: 'downloaded', kind: 'image', label: 'Downloaded web image',
                    uri: 'https://example.test/source', imageUrl: 'https://example.test/image.png',
                    previewUrl: 'https://example.test/preview.png', localUri: root.imageUri }];
                root.phase = 3;
            } else if (root.phase === 3) {
                const preview = root.find(grid, 'shelf-content-preview-downloaded');
                if (!preview || preview.status !== Image.Ready) return;
                preview.parent.Drag.dragStarted.connect(() => root.nativeDrags++);
                driver.running = true;
                root.phase = 4;
            } else if (root.phase === 4 && root.receivedUris.length > 0 && !driver.running) {
                root.check('downloaded-web-card-starts-native-drag', root.nativeDrags === 2);
                root.check('native-drop-into-populated-shelf-receives-downloaded-file', root.receivedUris.length === 1
                    && root.receivedUris[0] === root.imageUri);
                console.log('PENTAD_TEST ' + JSON.stringify({ status: root.checks.every(c => c.passed) ? 'pass' : 'fail', checks: root.checks }));
                Qt.quit();
                root.phase = 5;
            }
            if (root.ticks > 120) {
                root.check('thumbnail-and-export-deadline', false);
                console.log('PENTAD_TEST ' + JSON.stringify({ status: 'fail', checks: root.checks, metadata: root.metadata.metadata, exports: root.exports, nativeDrags: root.nativeDrags, received: root.receivedUris }));
                Qt.quit();
            }
        }
    }
}
