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
    property var quickReceived: []
    property int rowExports: 0
    property bool quickInvitationSeen: false
    property real emptyZoneHeight: 0
    property int widgetToggles: 0
    // Screen points for the drag driver: from, then to.
    property var dragPoints: [111, 280, 870, 300]
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
    // A Stash row drags out like the window's rows; its export mirrors into stash.exporting.
    property QtObject rowServices: QtObject {
        function text(uk, en) { return uk; }
        readonly property QtObject stash: QtObject {
            property bool exporting: false
            onExportingChanged: if (exporting) root.rowExports++
        }
        readonly property QtObject toolWorkspace: QtObject { property int exports: 0 }
    }
    // The native recipient for the row: the Activity quick tab on its own recording shelf.
    property QtObject quickShelf: QtObject {
        property bool ready: true
        property bool writable: true
        property string loadError: ''
        property var files: root.metadata
        property var entries: []
        signal commandFinished(string requestId, var result)
        function addUris(uris) {
            root.quickReceived = uris;
            entries = uris.map((uri, index) => ({ id: 'quick-' + index, label: 'Received photo.svg', uri, addedAt: new Date().toISOString(), pinned: false }));
            Qt.callLater(() => commandFinished('quick-drop', { ok: true }));
            return 'quick-drop';
        }
    }
    property QtObject quickServices: QtObject {
        function text(uk, en) { return uk; }
        readonly property var shelf: root.quickShelf
        readonly property QtObject stash: QtObject { property bool exporting: false }
        readonly property QtObject toolWorkspace: QtObject { property int exports: 0 }
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
            StashRow {
                id: stashRow
                objectName: 'stash-row-source'
                x: 20; y: 340; width: 420
                services: root.rowServices
                entry: ({ id: 'row-photo', label: 'Світлина.svg', uri: root.imageUri, addedAt: new Date().toISOString(), pinned: false })
                info: root.metadata.metadata[root.imageUri]
                sectionId: 'recent'
                compact: true
            }
        }
    }
    PanelWindow {
        screen: Quickshell.screens[0]
        anchors { left: true; top: true }
        margins { left: 650; top: 620 }
        exclusiveZone: 0
        WlrLayershell.layer: WlrLayer.Overlay
        visible: true
        implicitWidth: 440; implicitHeight: 400
        color: Theme.tokens.surface
        Rectangle {
            id: quickPane
            anchors.fill: parent
            color: Theme.tokens.surface
            StashQuick {
                id: quickReceiver
                x: 24; y: 16; width: 392
                services: root.quickServices
                readOnly: false
                onDropInvitedChanged: if (dropInvited) {
                    root.quickInvitationSeen = true;
                    quickInvitationCapture.restart();
                }
            }
        }
        Timer {
            id: quickInvitationCapture
            interval: 180
            onTriggered: quickPane.grabToImage(result => result.saveToFile(Quickshell.env('PENTAD_ARTIFACT_PATH') + '.quick-drop.png'))
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
        command: [Quickshell.env('PENTAD_DND_DRIVER'), String(sourceWindow.screen.x + root.dragPoints[0]), String(sourceWindow.screen.y + root.dragPoints[1]),
            String(sourceWindow.screen.x + root.dragPoints[2]), String(sourceWindow.screen.y + root.dragPoints[3])]
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
                root.emptyZoneHeight = root.find(quickReceiver, 'stash-quick-drop-zone').height;
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
                    instanceId: 'shelf-fixture', context: { preview: false }, settings: {}, controller: {}, x: 20, y: 420,
                    services: { shelf: root.shelf, text: (uk, en) => uk, stash: { toggle: () => root.widgetToggles++ } }
                }) : null;
                const widgetButton = widget ? root.find(widget, 'shelf-widget-button') : null;
                if (widgetButton) root.testPointer.mouseClick(widgetButton, widgetButton.width / 2, widgetButton.height / 2, Qt.LeftButton, Qt.NoModifier, 0);
                root.check('widget-button-toggles-stash-window', !!widgetButton && widgetButton.text === 'Сховок'
                    && root.widgetToggles === 1 && widget.shelfGrid === undefined);
                if (widget) widget.destroy();
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
                // From the Stash row (screen 144, 542) to the quick tab's drop zone (870, 680).
                root.dragPoints = [144, 542, 870, 680];
                driver.running = true;
                root.phase = 5;
            } else if (root.phase === 5 && root.quickReceived.length > 0 && !driver.running) {
                root.check('stash-row-export-delivers-uri-list', root.quickReceived.length === 1
                    && root.quickReceived[0] === root.imageUri);
                root.check('stash-row-export-mirrors-exporting', root.rowExports === 1 && !root.rowServices.stash.exporting
                    && !stashRow.exporting);
                root.check('native-drop-into-stash-quick-shows-photo', quickReceiver.photos.length === 1
                    && quickReceiver.message === '' && root.quickShelf.entries.length === 1);
                root.check('native-hover-invites-drop-into-stash-quick', root.quickInvitationSeen);
                const zone = root.find(quickReceiver, 'stash-quick-drop-zone');
                root.check('stash-quick-zone-full-when-empty-slim-with-entries', root.emptyZoneHeight === 92
                    && zone.height === 48 && !quickReceiver.dragHovered);
                console.log('PENTAD_TEST ' + JSON.stringify({ status: root.checks.every(c => c.passed) ? 'pass' : 'fail', checks: root.checks }));
                Qt.quit();
                root.phase = 6;
            }
            if (root.ticks > 180) {
                root.check('thumbnail-and-export-deadline', false);
                console.log('PENTAD_TEST ' + JSON.stringify({ status: 'fail', checks: root.checks, metadata: root.metadata.metadata, exports: root.exports, nativeDrags: root.nativeDrags, received: root.receivedUris, quickReceived: root.quickReceived, rowExports: root.rowExports }));
                Qt.quit();
            }
        }
    }
}
