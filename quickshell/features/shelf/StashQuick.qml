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
    readonly property string language: services.text('uk', 'en')
    readonly property var shelf: services.shelf
    readonly property var stash: services.stash
    readonly property var entries: shelf ? shelf.entries || [] : []
    readonly property var metadata: shelf && shelf.files ? shelf.files.metadata || ({}) : ({})
    readonly property bool writable: !readOnly && !!shelf && shelf.ready && shelf.writable
    // A row or photo of any Stash surface is being dragged out; it must not drop back in.
    readonly property bool exportInProgress: !!stash && stash.exporting === true
    readonly property bool dragHovered: dropArea.containsDrag
    readonly property bool dropInvited: dragHovered && !exportInProgress
    // A file is held over the bar or the activity panel: the zone opens and wakes before the pointer arrives.
    property bool dragAwake: false
    readonly property bool dropHeld: dropInvited || dragAwake && !exportInProgress
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
        return StashLogic.stashFailureText(reason, language) || services.text('Не вдалося додати це до Сховку.', 'Could not add this to the Stash.');
    }
    // Routed like the Stash window: files as references, links, web images and text through the
    // content helper (DropLogic.shelfDropRequest).
    function receiveDrop(drop) {
        if (!writable || exportInProgress) {
            drop.accepted = false;
            return false;
        }
        const offer = DropLogic.readShelfOffer(drop);
        const request = offer.ok ? DropLogic.shelfDropRequest(offer.offer) : null;
        const requestId = request ? shelf[request.method](request.uris || request.offer) : '';
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
        // While a file is held it opens full height with its circle; as the empty tab's invitation it is
        // a short strip; at rest beside the Stash's content it takes no room.
        PentadFileDrop {
            id: zone
            objectName: 'stash-quick-drop-zone'
            readonly property bool shown: root.entries.length === 0 || root.dropHeld
            width: parent.width
            height: root.dropHeld ? 176 : shown ? 92 : 0
            visible: height > 0
            opacity: shown ? 1 : 0
            clip: true
            Behavior on height {
                enabled: !Theme.tokens.reducedMotion
                NumberAnimation {
                    duration: Motion.state
                    easing.type: Easing.OutCubic
                }
            }
            Behavior on opacity {
                enabled: !Theme.tokens.reducedMotion
                NumberAnimation {
                    duration: Motion.state
                    easing.type: Easing.OutCubic
                }
            }
            awake: root.dropHeld
            active: root.dropInvited
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
