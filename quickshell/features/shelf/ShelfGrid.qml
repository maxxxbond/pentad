import QtQuick
import QtQuick.Controls.Basic
import Quickshell
import qs.components
import qs.theme
import "../../logic/shelf.mjs" as ShelfLogic
import "../../logic/drag-drop.mjs" as DropLogic

Item {
    id: root
    required property var shelf
    property bool readOnly: true
    property var pendingRequests: []
    property var dropRequests: []
    property bool dropConfirmed: false
    readonly property bool dropInvited: dragHovered && !exportInProgress
    property var selectedIds: []
    property bool exportInProgress: false
    property string language: Qt.locale().name.startsWith('uk') ? 'uk' : 'en'
    property string selectionAnchor: ''
    readonly property var entries: shelf?.entries || []
    readonly property var selectedEntries: entries.filter(entry => selectedIds.indexOf(entry.id) >= 0)
    readonly property var selectedEntry: selectedEntries.length === 1 ? selectedEntries[0] : null
    readonly property var selectedTile: selectedEntry ? tileFor(selectedEntry.id) : null
    readonly property alias itemMenu: contextMenu
    function tr(uk, en) { return language === 'uk' ? uk : en; }
    function tileFor(id) {
        const index = entries.findIndex(entry => entry.id === id);
        return index >= 0 ? tileRepeater.itemAt(index)?.item || null : null;
    }
    function selectEntry(id, modifiers) {
        const index = entries.findIndex(entry => entry.id === id);
        if (index < 0) return;
        const extend = (modifiers & Qt.ControlModifier) !== 0;
        if ((modifiers & Qt.ShiftModifier) && selectionAnchor) {
            const anchor = entries.findIndex(entry => entry.id === selectionAnchor);
            const range = entries.slice(Math.min(index, Math.max(0, anchor)), Math.max(index, anchor) + 1).map(entry => entry.id);
            selectedIds = extend ? Array.from(new Set(selectedIds.concat(range))) : range;
        } else {
            selectedIds = extend ? (selectedIds.indexOf(id) >= 0 ? selectedIds.filter(value => value !== id) : selectedIds.concat([id])) : [id];
            selectionAnchor = id;
        }
    }
    function navigate(id, offset, modifiers) {
        const index = entries.findIndex(entry => entry.id === id);
        const next = entries[Math.max(0, Math.min(entries.length - 1, index + offset))];
        if (!next) return;
        selectEntry(next.id, modifiers);
        tileFor(next.id)?.forceActiveFocus();
    }
    function removeSelected() { selectedIds.slice().forEach(id => removeFile(id)); }
    function openSelected() { return selectedTile ? selectedTile.openEntry() : false; }
    function showFolder() {
        const uri = selectedEntry ? ShelfLogic.shelfLocalUri(selectedEntry) : '';
        return uri ? openFile(uri.endsWith('/') ? uri : uri.slice(0, uri.lastIndexOf('/') + 1)) : false;
    }
    function showContext(entry, tile, position) {
        if (selectedIds.indexOf(entry.id) < 0) selectEntry(entry.id, Qt.NoModifier);
        const point = tile.mapToItem(root, position.x, position.y);
        contextMenu.popup(Math.max(0, Math.min(point.x, root.width - contextMenu.width)), point.y);
    }
    function selectedUris(entry) {
        if (selectedIds.indexOf(entry.id) < 0) return [entry.uri];
        return (shelf?.entries || []).filter(item => selectedIds.indexOf(item.id) >= 0
            && ShelfLogic.shelfLocalUri(item)
            && shelf?.files?.metadata?.[ShelfLogic.shelfLocalUri(item)]?.available !== false).map(ShelfLogic.shelfLocalUri);
    }
    readonly property bool dragHovered: target.containsDrag
    property string message: ""
    // The part of the grid a scrolling parent shows, in grid coordinates. A tall shelf keeps its
    // drop zone inside this window instead of centring it below the fold.
    property real viewportTop: 0
    property real viewportHeight: Number.POSITIVE_INFINITY
    readonly property bool writable: !!shelf && shelf.ready && shelf.writable && !readOnly
    implicitHeight: layout.implicitHeight
    height: implicitHeight

    function addUris(uris) {
        if (!writable) return false;
        const requestId = shelf.addUris(uris);
        pendingRequests = pendingRequests.concat([requestId]);
        message = "";
        return !!requestId;
    }
    function removeFile(id) {
        if (!writable) return false;
        const requestId = shelf.remove(id);
        pendingRequests = pendingRequests.concat([requestId]);
        selectedIds = selectedIds.filter(value => value !== id);
        return !!requestId;
    }
    function acceptDrop(drop, requestId) {
        dropRequests = dropRequests.concat([requestId]);
        drop.accept(Qt.CopyAction);
        return true;
    }
    Timer { id: confirmation; interval: 1400; onTriggered: root.dropConfirmed = false }
    function receiveDrop(drop) {
        if (!writable) { drop.accepted = false; return false; }
        const offer = DropLogic.readShelfOffer(drop);
        if (!offer.ok) { message = offer.reason; drop.accepted = false; return false; }
        const uriText = offer.offer.uris || '';
        let requestId = '';
        if (/^file:/im.test(uriText)) {
            const parsed = ShelfLogic.parseUriList(uriText);
            if (parsed.ok && addUris(parsed.uris)) return acceptDrop(drop, pendingRequests[pendingRequests.length - 1]);
        } else if (typeof shelf.addOffer === 'function') {
            requestId = shelf.addOffer(offer.offer);
        }
        if (!requestId) { message = 'Could not add this content to the shelf.'; drop.accepted = false; return false; }
        pendingRequests = pendingRequests.concat([requestId]);
        message = '';
        return acceptDrop(drop, requestId);
    }
    function downloadFile(id) {
        if (!writable) return;
        const requestId = shelf.download(id);
        if (requestId) pendingRequests = pendingRequests.concat([requestId]);
    }
    function openFile(uri) {
        if (readOnly) return false;
        const opened = Qt.openUrlExternally(uri);
        if (!opened) message = "Could not open this item";
        return opened;
    }
    Connections {
        target: root.shelf
        function onEntriesChanged() { root.selectedIds = root.selectedIds.filter(id => root.entries.some(entry => entry.id === id)); }
        function onCommandFinished(requestId, result) {
            if (root.pendingRequests.indexOf(requestId) < 0) return;
            if (root.dropRequests.indexOf(requestId) >= 0) {
                root.dropRequests = root.dropRequests.filter(id => id !== requestId);
                root.dropConfirmed = !!result.ok;
                if (result.ok) confirmation.restart();
            }
            root.pendingRequests = root.pendingRequests.filter(id => id !== requestId);
            root.message = result.ok ? "" : result.message || result.reason || "Shelf update failed";
        }
    }
    DropArea {
        id: target
        anchors.fill: parent
        onEntered: function(drag) {
            drag.accepted = root.writable && DropLogic.supportsShelfOffer(drag.formats);
            if (drag.accepted) drag.accept(Qt.CopyAction);
        }
        onDropped: drop => root.receiveDrop(drop)
    }
    Column {
        id: layout
        width: root.width
        spacing: 12
        Item {
            width: parent.width; height: 32
            Row {
                anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
                spacing: 8
                Text { text: root.tr('Полиця', 'Shelf'); color: Theme.tokens.text; font.family: Theme.tokens.fontFamily; font.pixelSize: 18; font.weight: Font.DemiBold }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.entries.length || ''
                    color: Theme.tokens.textMuted
                    font.family: Theme.tokens.fontFamily; font.pixelSize: 12
                }
            }
            PentadButton {
                id: shelfActions
                anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                text: '⋯'; width: 32; controlHeight: 28
                accessibleName: root.tr('Дії полиці', 'Shelf actions')
                visible: root.entries.length > 0
                requestedEnabled: !root.readOnly && root.entries.length > 0
                onClicked: shelfMenu.popup(Math.max(0, root.width - shelfMenu.width), 44)
            }
        }
        ContinuousSurface {
            id: canvas
            width: parent.width
            height: root.entries.length ? grid.implicitHeight + 16 : 180
            extent: Metrics.radiusBlock
            MouseArea { anchors.fill: parent; onClicked: if (!root.readOnly) root.selectedIds = []; }
            Grid {
                id: grid
                x: 8; y: 8; width: parent.width - 16
                columns: Math.max(1, Math.floor((width + spacing) / 124))
                spacing: 4
                opacity: root.dropInvited ? 0.22 : 1
                Behavior on opacity { NumberAnimation { duration: Theme.tokens.reducedMotion ? 0 : 140 } }
                Repeater {
                    id: tileRepeater
                    model: root.entries
                    delegate: Loader {
                        id: tileLoader
                        required property var modelData
                        required property int index
                        width: (grid.width - grid.spacing * (grid.columns - 1)) / grid.columns
                        height: item ? item.height : 146
                        sourceComponent: modelData.kind ? contentCard : fileCard
                        Component {
                            id: fileCard
                            FileTile {
                                id: fileTile
                                width: tileLoader.width
                                entry: tileLoader.modelData
                                readOnly: root.readOnly
                                language: root.language
                                navigationColumns: grid.columns
                                selected: root.selectedIds.indexOf(entry.id) >= 0
                                fileInfo: root.shelf?.files?.metadata?.[entry.uri] || ({})
                                exportUris: root.selectedUris(entry)
                                onSelectedRequested: modifiers => root.selectEntry(entry.id, modifiers)
                                onContextRequested: point => root.showContext(entry, fileTile, point)
                                onNavigationRequested: (offset, modifiers) => root.navigate(entry.id, offset, modifiers)
                                onOpenRequested: uri => root.openFile(uri)
                                onRemoveRequested: id => root.selectedIds.indexOf(id) >= 0 ? root.removeSelected() : root.removeFile(id)
                                onExportStarted: uris => root.exportInProgress = true
                                onExportFinished: action => root.exportInProgress = false
                                onExportInProgressChanged: if (!exportInProgress) root.exportInProgress = false
                            }
                        }
                        Component {
                            id: contentCard
                            ContentTile {
                                id: contentTile
                                width: tileLoader.width
                                entry: tileLoader.modelData
                                readOnly: root.readOnly
                                language: root.language
                                navigationColumns: grid.columns
                                selected: root.selectedIds.indexOf(entry.id) >= 0
                                downloadState: root.shelf?.downloads?.[entry.id] || ({})
                                onSelectedRequested: modifiers => root.selectEntry(entry.id, modifiers)
                                onContextRequested: point => root.showContext(entry, contentTile, point)
                                onNavigationRequested: (offset, modifiers) => root.navigate(entry.id, offset, modifiers)
                                onOpenRequested: uri => root.openFile(uri)
                                onRemoveRequested: id => root.selectedIds.indexOf(id) >= 0 ? root.removeSelected() : root.removeFile(id)
                                onDownloadRequested: id => root.downloadFile(id)
                                onExportStarted: uris => root.exportInProgress = true
                                onExportFinished: action => root.exportInProgress = false
                                onExportInProgressChanged: if (!exportInProgress) root.exportInProgress = false
                            }
                        }
                    }
                }
            }
            // Empty, it is the drop zone itself; with items, the zone rises over the dimmed grid
            // while a drag hovers and briefly confirms the drop.
            PentadDropZone {
                objectName: 'shelf-drop-feedback'
                readonly property real visibleTop: Math.max(0, Math.min(canvas.height, root.viewportTop - layout.y - canvas.y))
                readonly property real visibleBottom: Math.max(visibleTop,
                    Math.min(canvas.height, root.viewportTop + root.viewportHeight - layout.y - canvas.y))
                y: visibleTop
                width: parent.width
                height: visibleBottom - visibleTop
                extent: canvas.extent
                readonly property bool shown: !root.entries.length || root.dropInvited || root.dropConfirmed
                opacity: shown ? 1 : 0
                visible: opacity > 0
                Behavior on opacity { NumberAnimation { duration: Theme.tokens.reducedMotion ? 0 : 140 } }
                active: root.dropInvited
                fill: root.entries.length ? Qt.alpha(Theme.tokens.surfaceRaised, 0.94)
                    : root.dropInvited ? Theme.tokens.surfaceOverlay : Theme.tokens.surfaceRaised
                iconSource: root.dropConfirmed && !root.dropInvited
                    ? Qt.resolvedUrl('../../assets/icons/material/controls/check-symbolic.svg')
                    : Qt.resolvedUrl('../../assets/icons/material/media/cloud-upload-symbolic.svg')
                title: root.dropInvited ? root.tr('Відпустіть тут', 'Release here')
                    : root.dropConfirmed ? root.tr('Додано', 'Added') : root.tr('Перетягніть сюди', 'Drop here')
                hint: root.dropConfirmed && !root.dropInvited ? '' : root.tr('файли, посилання, фото або текст', 'files, links, images or text')
            }
        }
        Item {
            width: parent.width; height: visible ? 36 : 0
            visible: root.selectedEntries.length > 0
            Text {
                width: root.selectedEntries.length ? Math.max(60, parent.width - actions.width - 12) : parent.width
                anchors.verticalCenter: parent.verticalCenter
                text: root.tr('Вибрано: ', 'Selected: ') + root.selectedEntries.length
                color: Theme.tokens.textMuted; font.family: Theme.tokens.fontFamily; font.pixelSize: 12
                elide: Text.ElideRight
            }
            Row {
                id: actions
                anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                spacing: 6
                visible: root.selectedEntries.length > 0
                PentadButton {
                    objectName: 'shelf-selection-open'
                    text: root.selectedEntry?.kind === 'text' ? root.tr('Читати', 'Read note') : root.tr('Відкрити', 'Open')
                    controlHeight: 28
                    visible: !!root.selectedEntry
                    requestedEnabled: !root.readOnly && root.selectedTile?.available !== false
                    onClicked: root.openSelected()
                }
                PentadButton {
                    objectName: 'shelf-selection-secondary'
                    visible: !!root.selectedTile?.hasSecondaryAction
                    text: root.selectedTile?.secondaryLabel || ''
                    controlHeight: 28
                    requestedEnabled: !!root.selectedTile?.secondaryEnabled
                    onClicked: root.selectedTile?.performSecondary()
                }
                PentadButton {
                    objectName: 'shelf-selection-remove'
                    text: root.tr('Прибрати', 'Remove'); controlHeight: 28
                    requestedEnabled: root.writable
                    onClicked: root.removeSelected()
                }
            }
        }
        PentadMenu {
            id: shelfMenu
            width: 200
            entries: [
                { text: root.tr('Вибрати все', 'Select all'), action: 'all' },
                { text: root.tr('Зняти виділення', 'Clear selection'), action: 'clear', enabled: root.selectedIds.length > 0 }
            ]
            onActivated: entry => { root.selectedIds = entry.action === 'all' ? root.entries.map(item => item.id) : []; }
        }
        PentadMenu {
            id: contextMenu
            width: 210
            entries: {
                const result = [{ text: root.selectedEntry?.kind === 'text' ? root.tr('Читати нотатку', 'Read note') : root.tr('Відкрити', 'Open'), action: 'open', enabled: !!root.selectedEntry && root.selectedTile?.available !== false }];
                if (root.selectedEntry && ShelfLogic.shelfLocalUri(root.selectedEntry))
                    result.push({ text: root.tr('Показати теку', 'Show folder'), description: root.tr('Відкрити теку цього файлу', 'Open the folder containing this file'), action: 'folder' });
                if (root.selectedTile?.hasSecondaryAction)
                    result.push({ text: root.selectedTile.secondaryLabel, action: 'download', enabled: root.selectedTile.secondaryEnabled });
                result.push({ text: root.tr('Прибрати', 'Remove'), description: root.tr('Прибрати вибране з полиці. Оригінальні файли залишаться на диску.', 'Remove the selection from the shelf. Original files stay on disk.'), action: 'remove', enabled: root.writable });
                return result;
            }
            onActivated: entry => {
                if (entry.action === 'open') root.openSelected();
                else if (entry.action === 'folder') root.showFolder();
                else if (entry.action === 'download') root.selectedTile?.performSecondary();
                else root.removeSelected();
            }
        }
        PentadText {
            width: parent.width
            visible: !!root.message || !!root.shelf?.loadError || !!root.selectedTile?.downloadState?.error
            text: root.message || root.shelf?.loadError || root.selectedTile?.downloadState?.error || ''
            textFormat: Text.PlainText
            role: 'caption'; color: Theme.tokens.error; maximumLineCount: 2; elide: Text.ElideRight
        }
    }
}
