import QtQuick
import qs.components
import qs.theme
import "../../logic/shelf.mjs" as ShelfLogic
import "../../logic/drag-drop.mjs" as DropLogic
import "../../logic/stash-view.mjs" as StashLogic

// The Activity menu's Stash tab: drop something in, grab something recent out, or open the
// whole Stash. A drop zone, up to six newest photos, the three newest other entries and the
// "All of Stash" capsule. The whole tab takes drops the way the Stash window does; the bar's
// drag ingress hands its drops to receiveDrop() too.
Item {
    id: root
    required property var services
    property bool readOnly: true
    // Also set by the bar's drag ingress when a drop it routes here is refused.
    property string message: ''
    property var pendingRequests: []
    property var now: new Date()
    readonly property var shelf: services.shelf
    readonly property var stash: services.stash
    readonly property var entries: shelf ? shelf.entries || [] : []
    readonly property var metadata: shelf && shelf.files ? shelf.files.metadata || ({}) : ({})
    readonly property bool writable: !readOnly && !!shelf && shelf.ready && shelf.writable
    // A row or photo of any Stash surface is being dragged out; it must not drop back in.
    readonly property bool exportInProgress: !!stash && stash.exporting === true
    readonly property bool dragHovered: dropArea.containsDrag
    readonly property bool dropInvited: dragHovered && !exportInProgress
    readonly property var latest: StashLogic.newestFirst(entries)
    readonly property var photos: latest.filter(entry => root.isPhoto(entry)).slice(0, 6)
    readonly property var rows: latest.filter(entry => !root.isPhoto(entry)).slice(0, 3)
    signal closeRequested

    implicitWidth: 392
    implicitHeight: layout.implicitHeight
    onVisibleChanged: {
        if (visible)
            now = new Date();
        else
            message = '';
    }

    function infoFor(entry) {
        const uri = ShelfLogic.shelfLocalUri(entry);
        return uri ? metadata[uri] : undefined;
    }
    function isPhoto(entry) {
        return StashLogic.entryType(entry, infoFor(entry)) === 'photo';
    }
    function failureMessage(reason) {
        if (reason === 'too-large')
            return services.text('Сховок переповнений. Приберіть щось, щоб додати нове.', 'Stash is full. Remove something to add more.');
        if (reason === 'limit')
            return services.text('Досягнуто 300 записів. Закріпіть важливе або приберіть зайве.', '300 items reached. Pin what matters or remove some.');
        return services.text('Не вдалося додати це до Сховку.', 'Could not add this to the Stash.');
    }
    // Files go in as references, everything else (links, web images, text) through the content
    // helper, exactly as the Stash window accepts them.
    function receiveDrop(drop) {
        if (!writable || exportInProgress) {
            drop.accepted = false;
            return false;
        }
        const offer = DropLogic.readShelfOffer(drop);
        let requestId = '';
        if (offer.ok) {
            const uriText = offer.offer.uris || '';
            if (/^file:/im.test(uriText)) {
                const parsed = ShelfLogic.parseUriList(uriText);
                if (parsed.ok)
                    requestId = shelf.addUris(parsed.uris);
            } else {
                requestId = shelf.addOffer(offer.offer);
            }
        }
        if (!requestId) {
            drop.accepted = false;
            message = failureMessage('');
            return false;
        }
        pendingRequests = pendingRequests.concat([requestId]);
        message = '';
        drop.accept(Qt.CopyAction);
        return true;
    }
    // A note opens in the Stash, already selected; files and links open in their apps.
    function openEntry(id) {
        const entry = entries.find(item => item.id === id);
        if (!entry)
            return false;
        if (entry.kind === 'text') {
            stash.selectOnly(entry.id);
            stash.show();
            root.closeRequested();
            return true;
        }
        const local = ShelfLogic.shelfLocalUri(entry);
        const info = infoFor(entry);
        if (readOnly || (local && info && info.available === false))
            return false;
        return Qt.openUrlExternally(local || entry.uri);
    }

    Connections {
        target: root.shelf
        function onCommandFinished(requestId, result) {
            if (root.pendingRequests.indexOf(requestId) < 0)
                return;
            root.pendingRequests = root.pendingRequests.filter(id => id !== requestId);
            root.message = result && result.ok ? '' : root.failureMessage(result ? result.reason : '');
        }
    }
    DropArea {
        id: dropArea
        anchors.fill: parent
        onEntered: drag => {
            drag.accepted = root.writable && !root.exportInProgress && DropLogic.supportsShelfOffer(drag.formats);
            if (drag.accepted)
                drag.accept(Qt.CopyAction);
        }
        onDropped: drop => root.receiveDrop(drop)
    }
    Column {
        id: layout
        width: root.width
        spacing: 8
        // Slim while the Stash has something to show; full while a drag hovers or when empty.
        PentadDropZone {
            id: zone
            objectName: 'stash-quick-drop-zone'
            readonly property bool compact: root.entries.length > 0 && !root.dropInvited
            width: parent.width
            height: compact ? 48 : 92
            Behavior on height {
                enabled: !Theme.tokens.reducedMotion
                NumberAnimation {
                    duration: Motion.state
                    easing.type: Easing.OutCubic
                }
            }
            active: root.dropInvited
            iconSource: compact ? '' : Qt.resolvedUrl('../../assets/icons/material/media/cloud-upload-symbolic.svg')
            title: root.dropInvited ? root.services.text('Відпустіть тут', 'Release here') : root.services.text('Перетягніть сюди', 'Drop here')
        }
        PentadText {
            objectName: 'stash-quick-message'
            width: parent.width
            visible: root.message !== ''
            text: root.message
            role: 'caption'
            color: Theme.tokens.error
            maximumLineCount: 2
            elide: Text.ElideRight
        }
        // Inset like the rows' leads, so photos and row thumbnails share one edge.
        StashPhotoStrip {
            objectName: 'stash-quick-photos'
            x: 6
            width: parent.width - 12
            visible: root.photos.length > 0
            services: root.services
            photos: root.photos
            metadata: root.metadata
            tileHeight: 56
            slots: 6
            onOpened: id => root.openEntry(id)
        }
        Column {
            id: recent
            width: parent.width
            visible: root.rows.length > 0
            Repeater {
                model: root.rows
                delegate: StashRow {
                    id: row
                    required property var modelData
                    objectName: 'stash-quick-row-' + modelData.id
                    width: recent.width
                    services: root.services
                    entry: modelData
                    info: root.infoFor(modelData)
                    sectionId: 'recent'
                    compact: true
                    now: root.now
                    onOpened: root.openEntry(row.entry.id)
                }
            }
        }
        PentadButton {
            objectName: 'stash-quick-open-all'
            width: parent.width
            text: root.services.text('Увесь Сховок · ', 'All of Stash · ') + root.entries.length
            onClicked: {
                root.stash.show();
                root.closeRequested();
            }
        }
    }
}
