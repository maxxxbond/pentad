import QtQuick
import QtTest
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.services
import qs.features.shelf
import qs.shell
import qs.theme
import qs.components

ShellRoot {
    id: root
    property var checks: []
    property int phase: 0
    property int ticks: 0
    property int exports: 0
    property int nativeDrags: 0
    // What the overlay looked like the moment its export began: pass-through, and the native drag already active.
    property var overlayExportStart: null
    // The overlay's own drop zone must not invite the drag that leaves it.
    property bool overlayInvited: false
    property bool invitationSeen: false
    property var exportedUris: []
    property var receivedUris: []
    property var quickReceived: []
    property int rowExports: 0
    property bool quickInvitationSeen: false
    property real emptyZoneHeight: 0
    property int widgetToggles: 0
    // Screen points for the drag driver: from, then to.
    property var dragPoints: [0, 0, 0, 0]
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
        property var downloads: ({})
        property var entries: [
            { id: 'photo', label: 'Світлина.svg', uri: root.imageUri, addedAt: '', pinned: false },
            { id: 'text', label: 'Документ із довгою назвою.json', uri: root.textUri, addedAt: '', pinned: false },
            { id: 'pdf', label: 'Документ.pdf', uri: root.pdfUri, addedAt: '', pinned: false },
            { id: 'folder', label: 'Папка', uri: root.folderUri, addedAt: '', pinned: false },
            { id: 'missing', label: 'Видалений файл.png', uri: root.missingUri, addedAt: '', pinned: false }
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
        property var downloads: ({})
        property var entries: []
        signal commandFinished(string requestId, var result)
        function addUris(uris) {
            root.receivedUris = uris;
            entries = uris.map((uri, index) => ({ id: 'received-' + index, label: 'Received file', uri, addedAt: new Date().toISOString(), pinned: false }));
            Qt.callLater(() => commandFinished('native-drop', { ok: true }));
            return 'native-drop';
        }
        function remove(id) { return ''; }
    }
    // The two Stash views: the source with five files, and an empty one that receives drops.
    component ViewServices: QtObject {
        required property var shelf
        property var hyprland: null
        function text(uk, en) { return uk; }
        readonly property StashController stash: StashController { config: QtObject { property bool preview: false; property var documents: ({}) } }
        readonly property QtObject toolWorkspace: QtObject { property int exports: 0 }
        readonly property QtObject filePicker: QtObject { property bool busy: false }
    }
    property ViewServices sourceServices: ViewServices { shelf: root.shelf }
    property ViewServices receiverServices: ViewServices { shelf: root.receiverShelf }
    // The Stash overlay with one file row; its drag-out crosses the empty input mask to the receiver below.
    property QtObject overlayShelf: QtObject {
        property bool ready: true
        property bool writable: true
        property string loadError: ''
        property var files: root.metadata
        property var downloads: ({})
        property var entries: [{ id: 'overlay-text', label: 'Документ.json', uri: root.textUri, addedAt: new Date().toISOString(), pinned: false }]
        signal commandFinished(string requestId, var result)
        function addUris(uris) { return ''; }
        function remove(id) { return ''; }
    }
    // The overlay opens on the focused Hyprland output: the first screen, where the receiver windows are.
    property ViewServices overlayServices: ViewServices {
        shelf: root.overlayShelf
        hyprland: QtObject {
            readonly property var state: ({ kind: 'ready', value: { outputs: [{ id: '1', name: Quickshell.screens[0].name }], focusedOutputId: '1' } })
        }
    }
    StashHost { id: overlayHost; services: root.overlayServices }
    // A Stash row drags out like the window's rows; its export mirrors into stash.exporting.
    property QtObject rowServices: QtObject {
        function text(uk, en) { return uk; }
        readonly property QtObject stash: QtObject {
            property bool exporting: false
            property bool dragging: false
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
        readonly property QtObject stash: QtObject { property bool exporting: false; property bool dragging: false }
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
        implicitWidth: 460; implicitHeight: 580
        color: Theme.tokens.surface
        Rectangle {
            id: capture
            anchors.fill: parent; color: Theme.tokens.surface
            StashView { id: view; width: 460; height: 400; services: root.sourceServices; framed: true }
            StashRow {
                id: stashRow
                objectName: 'stash-row-source'
                x: 20; y: 420; width: 420
                services: root.rowServices
                entry: ({ id: 'row-photo', label: 'Світлина.svg', uri: root.imageUri, addedAt: new Date().toISOString(), pinned: false })
                info: root.metadata.metadata[root.imageUri]
                sectionId: 'recent'
                compact: true
            }
            // A link and a web image never downloaded export their web addresses, as a URI list and as text.
            StashRow {
                id: linkRow
                x: 20; y: 464; width: 420
                services: root.rowServices
                entry: ({ id: 'row-link', kind: 'link', label: 'Посилання', uri: 'https://example.test/page', addedAt: new Date().toISOString(), pinned: false })
                info: undefined
                sectionId: 'recent'
                compact: true
            }
            StashRow {
                id: webImageRow
                x: 20; y: 508; width: 420
                services: root.rowServices
                entry: ({ id: 'row-web-image', kind: 'image', label: 'Пін', uri: 'https://example.test/pin', imageUrl: 'https://example.test/original.png',
                    previewUrl: 'https://example.test/small.png', addedAt: new Date().toISOString(), pinned: false })
                info: undefined
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
        StashView {
            id: receiverView
            anchors.fill: parent; services: root.receiverServices; framed: true
            onDropInvitedChanged: if (dropInvited) {
                root.invitationSeen = true;
                invitationCapture.restart();
            }
        }
        Timer {
            id: invitationCapture
            interval: 180
            onTriggered: receiverView.grabToImage(result => result.saveToFile(Quickshell.env('PENTAD_ARTIFACT_PATH') + '.drop.png'))
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
        if (!item) return null;
        if (item.objectName === name) return item;
        const children = Array.prototype.slice.call(item.children || []);
        if (item.contentItem && children.indexOf(item.contentItem) < 0) children.push(item.contentItem);
        for (const child of children) { const result = find(child, name); if (result) return result; }
        return null;
    }
    function findWhere(item, test) {
        if (!item) return null;
        if (test(item)) return item;
        const children = Array.prototype.slice.call(item.children || []);
        if (item.contentItem && children.indexOf(item.contentItem) < 0) children.push(item.contentItem);
        for (const child of children) { const result = findWhere(child, test); if (result) return result; }
        return null;
    }
    // The native drag source of a Stash row or photo tile.
    function dragSourceOf(item) { return findWhere(item, child => child.uris !== undefined && child.exporting !== undefined); }
    // The screen point at the centre of an item inside a window placed at margins (left, top), relative to its screen.
    function screenCenter(item, left, top) {
        const point = item.mapToItem(null, item.width / 2, item.height / 2);
        return [left + Math.round(point.x), top + Math.round(point.y)];
    }
    function check(name, passed) { checks = checks.concat([{ name, passed: !!passed }]); }
    Timer {
        interval: 100; repeat: true; running: true
        onTriggered: {
            root.ticks++;
            if (root.ticks > 240 && root.phase >= 0 && root.phase < 8) {
                root.check('thumbnail-and-export-deadline', false);
                console.log('PENTAD_TEST ' + JSON.stringify({ status: 'fail', checks: root.checks, metadata: root.metadata.metadata, phase: root.phase, exports: root.exports, nativeDrags: root.nativeDrags, received: root.receivedUris, quickReceived: root.quickReceived, rowExports: root.rowExports, overlayExportStart: root.overlayExportStart }));
                root.phase = 9;
                Qt.quit();
            }
            if (root.phase === 0 && root.metadata.metadata[root.imageUri]?.thumbnail && root.metadata.metadata[root.pdfUri]?.thumbnail) {
                root.check('system-thumbnail-is-generated-and-cached', root.metadata.metadata[root.imageUri].thumbnail.startsWith('file://'));
                root.check('pdf-system-thumbnail-is-generated', root.metadata.metadata[root.pdfUri].thumbnail.startsWith('file://'));
                root.check('folder-metadata-and-missing-file-state', root.metadata.metadata[root.folderUri]?.folder
                    && root.metadata.metadata[root.missingUri]?.available === false);
                const tile = root.find(view, 'stash-row-photo');
                const textRow = root.find(view, 'stash-row-text'), pdfRow = root.find(view, 'stash-row-pdf');
                if (!tile || !textRow || !pdfRow || !root.findWhere(tile, item => item.status === Image.Ready)) return;
                root.check('generated-thumbnail-reaches-visible-row', true);
                root.emptyZoneHeight = root.find(quickReceiver, 'stash-quick-drop-zone').height;
                view.selectEntry('text', Qt.NoModifier);
                view.selectEntry('pdf', Qt.ControlModifier);
                root.check('control-selection-exports-both-file-uris', view.dragUrisFor(root.shelf.entries[1]).length === 2);
                const source = root.dragSourceOf(textRow);
                source.exportingChanged.connect(() => { if (source.exporting) { root.exports++; root.exportedUris = source.uris; } });
                source.Drag.dragStarted.connect(() => root.nativeDrags++);
                root.dragPoints = root.screenCenter(textRow, 24, 180).concat(root.screenCenter(receiverView, 650, 180));
                driver.running = true;
                root.phase = 1;
            } else if (root.phase === 1 && root.receivedUris.length > 0 && !driver.running && root.find(receiverView, 'stash-row-received-1')) {
                const textRow = root.find(view, 'stash-row-text');
                const source = root.dragSourceOf(textRow);
                root.check('native-drag-starts-with-selected-files-and-preview', root.nativeDrags === 1
                    && root.exportedUris.length === 2 && String(source.Drag.imageSource).length > 0);
                root.check('native-drop-into-empty-stash-receives-both-file-uris', root.receivedUris.length === 2
                    && root.receivedUris[0] === root.textUri && root.receivedUris[1] === root.pdfUri);
                root.check('native-hover-shows-drop-invitation', root.invitationSeen);
                root.check('successful-drop-lists-received-files', receiverView.message === ''
                    && !!root.find(receiverView, 'stash-row-received-0') && !receiverView.dropInvited);
                root.check('native-drag-does-not-move-row', textRow.x === 0 && textRow.y >= 0 && source.x === 0 && source.y === 0);
                const missing = root.find(view, 'stash-row-missing');
                root.check('missing-file-cannot-start-export', !!missing && missing.dragUris.length === 0
                    && view.dragUrisFor(root.shelf.entries[4]).length === 0);
                const order = view.navigationOrder;
                view.selectEntry(order[0], Qt.NoModifier);
                view.selectEntry(order[2], Qt.ShiftModifier);
                root.check('shift-selects-contiguous-range', order.length === 5 && view.stash.selectedIds.length === 3
                    && view.stash.selectedIds.join() === order.slice(0, 3).join());
                const pdf = root.find(view, 'stash-row-pdf');
                view.stash.selectOnly('text');
                view.stash.selectedIds = ['text', 'pdf'];
                root.testPointer.mouseClick(pdf, pdf.width / 2, pdf.height / 2, Qt.RightButton, Qt.NoModifier, 0);
                root.check('right-click-opens-context-for-selection', view.itemMenu.visible && view.itemMenu.entryId === 'pdf'
                    && view.stash.selectedIds.length === 2 && view.itemMenu.entries.length > 0);
                root.check('context-menu-ignores-pointer-leave', view.itemMenu.pointerDismiss === false);
                view.itemMenu.close();
                view.selectEntry(order[0], Qt.NoModifier);
                view.navigate(1, Qt.NoModifier);
                root.check('keyboard-navigation-moves-selection', view.stash.selectedIds.length === 1 && view.stash.selectedIds[0] === order[1]);
                view.selectEntry('text', Qt.NoModifier);
                view.selectEntry('pdf', Qt.ControlModifier);
                const widgetComponent = Qt.createComponent('widgets/shelf/View.qml');
                const widget = widgetComponent.status === Component.Ready ? widgetComponent.createObject(sourceWindow.contentItem, {
                    instanceId: 'shelf-fixture', context: { preview: false }, settings: {}, controller: {}, x: 20, y: 500,
                    services: { shelf: root.shelf, text: (uk, en) => uk, stash: { toggle: () => root.widgetToggles++ } }
                }) : null;
                const widgetButton = widget ? root.find(widget, 'shelf-widget-button') : null;
                if (widgetButton) root.testPointer.mouseClick(widgetButton, widgetButton.width / 2, widgetButton.height / 2, Qt.LeftButton, Qt.NoModifier, 0);
                root.check('widget-button-toggles-stash-window', !!widgetButton && widgetButton.text === 'Сховок'
                    && root.widgetToggles === 1 && widget.shelfGrid === undefined);
                if (widget) widget.destroy();
                capture.grabToImage(result => {
                    root.check('stash-source-capture', result.saveToFile(Quickshell.env('PENTAD_ARTIFACT_PATH')));
                    root.phase = 2;
                });
                root.phase = -1;
            } else if (root.phase === 2) {
                root.receivedUris = [];
                root.shelf.entries = [{ id: 'downloaded', kind: 'image', label: 'Downloaded web image',
                    uri: 'https://example.test/source', imageUrl: 'https://example.test/image.png',
                    previewUrl: 'https://example.test/preview.png', localUri: root.imageUri, addedAt: new Date().toISOString(), pinned: false }];
                root.phase = 3;
            } else if (root.phase === 3) {
                const tile = root.find(view, 'stash-photo-downloaded');
                if (!tile || !root.findWhere(tile, item => item.status === Image.Ready)) return;
                root.dragSourceOf(tile).Drag.dragStarted.connect(() => root.nativeDrags++);
                root.dragPoints = root.screenCenter(tile, 24, 180).concat(root.screenCenter(receiverView, 650, 180));
                driver.running = true;
                root.phase = 4;
            } else if (root.phase === 4 && root.receivedUris.length > 0 && !driver.running) {
                root.check('downloaded-web-entry-starts-native-drag', root.nativeDrags === 2);
                root.check('native-drop-into-populated-stash-receives-downloaded-file', root.receivedUris.length === 1
                    && root.receivedUris[0] === root.imageUri);
                // From the Stash row to the quick tab's drop zone.
                root.dragPoints = root.screenCenter(stashRow, 24, 180).concat(root.screenCenter(root.find(quickReceiver, 'stash-quick-drop-zone'), 650, 620));
                driver.running = true;
                root.phase = 5;
            } else if (root.phase === 5 && root.quickReceived.length > 0 && !driver.running) {
                root.check('stash-row-export-delivers-uri-list', root.quickReceived.length === 1
                    && root.quickReceived[0] === root.imageUri);
                root.check('stash-row-export-mirrors-exporting', root.rowExports === 1 && !root.rowServices.stash.exporting
                    && !stashRow.exporting);
                const linkSource = root.dragSourceOf(linkRow), imageSource = root.dragSourceOf(webImageRow);
                root.check('stash-web-rows-export-their-addresses', JSON.stringify(linkSource.uris) === '["https://example.test/page"]'
                    && linkSource.Drag.mimeData['text/uri-list'] === 'https://example.test/page\r\n'
                    && linkSource.Drag.mimeData['text/plain'] === 'https://example.test/page'
                    && JSON.stringify(imageSource.uris) === '["https://example.test/original.png"]'
                    && root.dragSourceOf(stashRow).Drag.mimeData['text/plain'] === undefined);
                root.check('native-drop-into-stash-quick-shows-photo', quickReceiver.photos.length === 1
                    && quickReceiver.message === '' && root.quickShelf.entries.length === 1);
                root.check('native-hover-invites-drop-into-stash-quick', root.quickInvitationSeen);
                const zone = root.find(quickReceiver, 'stash-quick-drop-zone');
                root.check('stash-quick-zone-shown-when-empty-hidden-at-rest-with-entries', root.emptyZoneHeight === 92
                    && zone.height === 0 && !zone.visible && !quickReceiver.dragHovered);
                // From a row in the Stash overlay, through its empty input mask, into the receiver window beneath.
                root.receivedUris = [];
                root.overlayServices.stash.show();
                root.phase = 6;
            } else if (root.phase === 6 && overlayHost.item && overlayHost.item.view.activeFocus && root.find(overlayHost.item.view, 'stash-row-overlay-text')) {
                const overlay = overlayHost.item;
                const row = root.find(overlay.view, 'stash-row-overlay-text');
                if (row.width <= 0 || overlay.mask.width !== overlay.width) return;
                const source = root.dragSourceOf(row);
                source.Drag.dragStarted.connect(() => root.nativeDrags++);
                const dragsBefore = root.nativeDrags;
                // Pass-through must begin once the native drag runs: neither at the 10 px threshold nor
                // before startDrag, which would move the pointer focus away and leave Qt no origin window.
                overlay.view.dropInvitedChanged.connect(() => { if (overlay.view.dropInvited) root.overlayInvited = true; });
                root.overlayServices.stash.draggingChanged.connect(() => {
                    if (root.overlayServices.stash.dragging && !root.overlayExportStart)
                        root.overlayExportStart = { mask: [overlay.mask.width, overlay.mask.height], keyboard: overlay.WlrLayershell.keyboardFocus,
                            dragActive: source.Drag.active, dragStarted: root.nativeDrags > dragsBefore };
                });
                const from = row.mapToItem(null, row.width / 2, row.height / 2);
                root.dragPoints = [Math.round(from.x), Math.round(from.y)].concat(root.screenCenter(receiverView, 650, 180));
                driver.running = true;
                root.phase = 7;
            } else if (root.phase === 7 && root.receivedUris.length > 0 && !driver.running && overlayHost.item && overlayHost.item.frame.opacity === 1) {
                const overlay = overlayHost.item;
                const start = root.overlayExportStart;
                root.check('overlay-export-pass-through-starts-with-the-native-drag', !!start && start.mask[0] === 0 && start.mask[1] === 0
                    && start.keyboard === WlrKeyboardFocus.None && start.dragActive === true && start.dragStarted === true);
                root.check('overlay-export-delivers-uri-list', root.receivedUris.length === 1 && root.receivedUris[0] === root.textUri
                    && root.nativeDrags === 3);
                root.check('overlay-restores-after-export', overlay.frame.opacity === 1 && overlay.mask.width === overlay.width
                    && overlay.mask.height === overlay.height && overlay.WlrLayershell.keyboardFocus === WlrKeyboardFocus.Exclusive
                    && !root.overlayServices.stash.exporting && !root.overlayServices.stash.dragging && root.overlayServices.stash.visible);
                root.check('overlay-never-invites-its-own-drag', !root.overlayInvited);
                console.log('PENTAD_TEST ' + JSON.stringify({ status: root.checks.every(c => c.passed) ? 'pass' : 'fail', checks: root.checks, overlayExportStart: start }));
                Qt.quit();
                root.phase = 8;
            }
        }
    }
}
