import QtQuick
import QtQuick.Controls.Basic
import qs.components
import qs.theme
import "../../logic/shelf.mjs" as ShelfLogic
import "../../logic/drag-drop.mjs" as DropLogic
import "../../logic/stash-view.mjs" as StashLogic

// The Stash: header, search, type filters, a time-ordered list and the composer. All state
// (query, filter, selection, draft, scroll, expanded days) lives in services.stash, so the
// overlay and the window frame show the same view. The list is virtual: sections are
// flattened into header, photo strip and row items for one ListView.
FocusScope {
    id: root
    required property var services
    // True in the overlay, which has no frame of its own; the toplevel window draws the surface.
    property bool framed: false
    readonly property var stash: services.stash
    readonly property var shelf: services.shelf
    readonly property string language: services.text('uk', 'en')
    readonly property bool writable: shelf.ready && shelf.writable
    readonly property bool dragHovered: dropArea.containsDrag
    readonly property bool dropInvited: dragHovered && !stash.exporting
    readonly property var metadata: shelf.files.metadata
    readonly property var counts: StashLogic.typeCounts(shelf.entries, metadata)
    readonly property var sections: StashLogic.buildSections(shelf.entries, metadata,
        { query: stash.query, filter: stash.filter, now: now, language: language })
    property var now: new Date()
    property var items: []
    property string signature: ''
    property bool rebuilding: false
    // The keyboard cursor inside a Shift range; the selection itself lives in services.stash.
    property string cursorId: ''
    property string messageReason: ''
    readonly property string message: messageReason === 'too-large'
        ? services.text('Сховок переповнений. Приберіть щось, щоб додати нове.', 'Stash is full. Remove something to add more.')
        : messageReason === 'limit' ? services.text('Досягнуто 300 записів. Закріпіть важливе або приберіть зайве.', '300 items reached. Pin what matters or remove some.')
        : messageReason === 'pin-limit' ? services.text('Можна закріпити до 50 записів.', 'You can pin up to 50 items.') : ''
    // Ids in visual order for ↑/↓: the photos a strip shows, then the rows of each section.
    readonly property int stripSlots: Math.max(1, Math.floor((list.width + 4) / 68))
    readonly property var navigationOrder: {
        const order = [];
        for (const item of items) {
            if (item.kind === 'row') order.push(item.entry.id);
            else if (item.kind === 'strip') {
                const all = stash.expandedDays.indexOf(item.sectionId) >= 0 || item.photos.length <= stripSlots;
                item.photos.slice(0, all ? item.photos.length : stripSlots - 1).forEach(photo => order.push(photo.id));
            }
        }
        return order;
    }
    readonly property alias itemMenu: contextMenu
    signal closeRequested
    signal detachRequested

    implicitWidth: 520
    implicitHeight: scroller.y + Math.max(240, list.contentHeight) + 4 + bottomBar.height + 12
    onSectionsChanged: rebuildTimer.restart()
    Component.onCompleted: {
        rebuild();
        list.contentY = Math.max(0, stash.contentY);
    }
    Component.onDestruction: { rebuildTimer.stop(); dayTimer.stop(); }

    function rebuild() {
        const flat = [];
        for (const section of sections) {
            flat.push({ kind: 'header', sectionId: section.id, title: section.title });
            if (section.photos.length) flat.push({ kind: 'strip', sectionId: section.id, photos: section.photos });
            for (const entry of section.rows) flat.push({ kind: 'row', sectionId: section.id, entry: entry });
        }
        const next = JSON.stringify(flat);
        if (next === signature) return;
        const y = list.contentY;
        rebuilding = true;
        signature = next;
        items = flat;
        list.forceLayout();
        list.contentY = Math.max(list.originY, Math.min(y, list.originY + list.contentHeight - list.height));
        rebuilding = false;
    }
    function entryById(id) { return shelf.entries.find(entry => entry.id === id) || null; }
    function infoFor(entry) {
        const uri = entry ? ShelfLogic.shelfLocalUri(entry) : '';
        return uri ? metadata[uri] : undefined;
    }
    function selectedEntries() { return shelf.entries.filter(entry => stash.selectedIds.indexOf(entry.id) >= 0); }
    function focusList() { listFocus.forceActiveFocus(); }
    function selectEntry(id, modifiers) {
        const order = navigationOrder;
        const index = order.indexOf(id);
        const extend = (modifiers & Qt.ControlModifier) !== 0;
        const anchor = order.indexOf(stash.selectionAnchor);
        if ((modifiers & Qt.ShiftModifier) && index >= 0 && anchor >= 0) {
            const range = order.slice(Math.min(index, anchor), Math.max(index, anchor) + 1);
            stash.selectedIds = extend ? Array.from(new Set(stash.selectedIds.concat(range))) : range;
        } else if (extend) {
            stash.selectedIds = stash.selectedIds.indexOf(id) >= 0 ? stash.selectedIds.filter(value => value !== id) : stash.selectedIds.concat([id]);
            stash.selectionAnchor = id;
        } else {
            stash.selectOnly(id);
        }
        cursorId = id;
    }
    function navigate(offset, modifiers) {
        const order = navigationOrder;
        if (!order.length) return;
        const current = stash.selectedIds.indexOf(cursorId) >= 0 ? cursorId : stash.selectedIds[stash.selectedIds.length - 1] || '';
        const index = order.indexOf(current);
        const next = order[index < 0 ? (offset > 0 ? 0 : order.length - 1) : Math.max(0, Math.min(order.length - 1, index + offset))];
        selectEntry(next, modifiers & Qt.ShiftModifier);
        const at = items.findIndex(item => item.kind === 'row' ? item.entry.id === next : item.kind === 'strip' && item.photos.some(photo => photo.id === next));
        if (at >= 0) list.positionViewAtIndex(at, ListView.Contain);
    }
    function openEntry(id) {
        const entry = entryById(id);
        if (!entry) return false;
        if (entry.kind === 'text') { notePopup.text = entry.text; notePopup.open(); return true; }
        const local = ShelfLogic.shelfLocalUri(entry);
        if (!local) return Qt.openUrlExternally(entry.uri);
        const info = infoFor(entry);
        return info && info.available === false ? false : Qt.openUrlExternally(local);
    }
    function showFolder(id) {
        const uri = ShelfLogic.shelfLocalUri(entryById(id) || {});
        return uri ? Qt.openUrlExternally(uri.slice(0, uri.replace(/\/+$/, '').lastIndexOf('/') + 1)) : false;
    }
    function pinSelected() {
        const selected = selectedEntries();
        const pinned = !selected.every(entry => entry.pinned);
        selected.forEach(entry => shelf.pin(entry.id, pinned));
    }
    function copyEntry(id) { if (id) shelf.copy(id); }
    function removeSelected() {
        selectedEntries().forEach(entry => shelf.remove(entry.id));
        stash.clearSelection();
    }
    function toggleDay(id) {
        const days = stash.expandedDays;
        stash.expandedDays = days.indexOf(id) >= 0 ? days.filter(day => day !== id) : days.concat([id]);
    }
    function showContext(id, item, position) {
        if (stash.selectedIds.indexOf(id) < 0) selectEntry(id, Qt.NoModifier);
        contextMenu.entryId = id;
        const point = item.mapToItem(root, position.x, position.y);
        contextMenu.popup(Math.max(0, Math.min(point.x, root.width - contextMenu.width)), point.y);
    }
    // Several selected files drag out together when the drag starts on one of them.
    function dragUrisFor(entry) {
        const own = ShelfLogic.shelfLocalUri(entry);
        if (stash.selectedIds.indexOf(entry.id) < 0 || stash.selectedIds.length < 2) return own ? [own] : [];
        return selectedEntries().map(item => ShelfLogic.shelfLocalUri(item))
            .filter(uri => uri && !(metadata[uri] && metadata[uri].available === false));
    }
    function receiveDrop(drop) {
        if (!writable || stash.exporting) { drop.accepted = false; return false; }
        const offer = DropLogic.readShelfOffer(drop);
        if (!offer.ok) { drop.accepted = false; return false; }
        const uriText = offer.offer.uris || '';
        let requestId = '';
        if (/^file:/im.test(uriText)) {
            const parsed = ShelfLogic.parseUriList(uriText);
            if (parsed.ok) requestId = shelf.addUris(parsed.uris);
        } else requestId = shelf.addOffer(offer.offer);
        if (!requestId) { drop.accepted = false; return false; }
        drop.accept(Qt.CopyAction);
        return true;
    }
    function handleKey(event) {
        const ctrl = (event.modifiers & Qt.ControlModifier) !== 0;
        if (event.key === Qt.Key_Escape) {
            if (stash.query) stash.query = '';
            else root.closeRequested();
        } else if ((event.key === Qt.Key_Down || event.key === Qt.Key_Up) && !composer.input.activeFocus) {
            navigate(event.key === Qt.Key_Down ? 1 : -1, event.modifiers);
            focusList();
        } else if (search.activeFocus || composer.input.activeFocus) {
            return;
        } else if (event.key === Qt.Key_Slash) search.forceActiveFocus();
        else if (ctrl && event.key === Qt.Key_V) shelf.pasteClipboard();
        else if (ctrl && event.key === Qt.Key_C) copyEntry(cursorId && stash.selectedIds.indexOf(cursorId) >= 0 ? cursorId : stash.selectedIds[0]);
        else if (!ctrl && event.key === Qt.Key_P && stash.selectedIds.length) pinSelected();
        else if (event.key === Qt.Key_Delete && stash.selectedIds.length) removeSelected();
        else if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && stash.selectedIds.length === 1) openEntry(stash.selectedIds[0]);
        else return;
        event.accepted = true;
    }
    Keys.onPressed: event => root.handleKey(event)

    Timer { id: rebuildTimer; interval: 30; onTriggered: root.rebuild() }
    // Section titles follow the date; only a new day needs a rebuild.
    Timer {
        id: dayTimer
        interval: 60000
        repeat: true
        running: root.visible && root.stash.visible
        onTriggered: if (new Date().toDateString() !== root.now.toDateString()) root.now = new Date()
    }
    Connections {
        target: root.shelf
        function onCommandFinished(requestId, result) {
            if (result && result.ok === false && ['too-large', 'limit', 'pin-limit'].indexOf(result.reason) >= 0) root.messageReason = result.reason;
            else if (result && result.ok) root.messageReason = '';
        }
        function onEntriesChanged() {
            const ids = root.stash.selectedIds.filter(id => !!root.entryById(id));
            if (ids.length !== root.stash.selectedIds.length) root.stash.selectedIds = ids;
        }
    }
    DropArea {
        id: dropArea
        anchors.fill: parent
        onEntered: drag => {
            drag.accepted = root.writable && !root.stash.exporting && DropLogic.supportsShelfOffer(drag.formats);
            if (drag.accepted) drag.accept(Qt.CopyAction);
        }
        onDropped: drop => root.receiveDrop(drop)
    }
    ContinuousSurface {
        anchors.fill: parent
        visible: root.framed
        fill: Theme.tokens.surface
        extent: Metrics.radiusPopover
    }
    Item { id: listFocus; focus: true }

    Item {
        id: header
        x: 12; y: 12; width: root.width - 24; height: 32
        Row {
            anchors.verticalCenter: parent.verticalCenter
            spacing: 8
            PentadText { id: title; text: root.services.text('Сховок', 'Stash'); role: 'section'; font.weight: Font.DemiBold; wrapMode: Text.NoWrap }
            PentadText {
                anchors.baseline: title.baseline
                text: root.shelf.entries.length || ''
                role: 'caption'; color: Theme.tokens.textMuted; wrapMode: Text.NoWrap
            }
        }
        Row {
            anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
            spacing: 4
            PentadButton {
                objectName: 'stash-detach'
                width: 28; controlHeight: 28; iconSize: Metrics.panelIcon; focusPolicy: Qt.TabFocus
                iconSource: Qt.resolvedUrl('../../assets/icons/material/stash/' + (root.stash.mode === 'overlay' ? 'open-in-new' : 'close-fullscreen') + '-symbolic.svg')
                accessibleName: root.stash.mode === 'overlay' ? root.services.text('Відкрити у вікні', 'Open in a window') : root.services.text('Показати поверх вікон', 'Show as overlay')
                onClicked: root.detachRequested()
            }
            PentadButton {
                objectName: 'stash-close'
                width: 28; controlHeight: 28; iconSize: Metrics.panelIcon; focusPolicy: Qt.TabFocus
                iconSource: Qt.resolvedUrl('../../assets/icons/material/media/close-symbolic.svg')
                accessibleName: root.services.text('Закрити', 'Close')
                onClicked: root.closeRequested()
            }
        }
    }
    PentadTextField {
        id: search
        objectName: 'stash-search'
        x: 12; y: header.y + header.height + 8; width: root.width - 24; height: 36
        leftPadding: 36
        text: root.stash.query
        onTextChanged: if (root.stash.query !== text) root.stash.query = text
        placeholderText: root.services.text('Пошук', 'Search')
        PentadIcon {
            x: 12; anchors.verticalCenter: parent.verticalCenter
            source: Qt.resolvedUrl('../../assets/icons/material/media/search-symbolic.svg')
            color: Theme.tokens.textMuted
        }
    }
    Row {
        id: filters
        x: 12; y: search.y + search.height + 8; height: 28
        spacing: 4
        Repeater {
            model: [{ id: 'all', uk: 'Усе', en: 'All' }, { id: 'file', uk: 'Файли', en: 'Files' }, { id: 'photo', uk: 'Фото', en: 'Photos' },
                { id: 'link', uk: 'Посилання', en: 'Links' }, { id: 'text', uk: 'Текст', en: 'Text' }]
            delegate: AbstractButton {
                id: chip
                required property var modelData
                readonly property bool current: root.stash.filter === modelData.id
                readonly property int count: root.counts[modelData.id] || 0
                objectName: 'stash-filter-' + modelData.id
                height: 28
                leftPadding: 12; rightPadding: 12
                focusPolicy: Qt.TabFocus
                text: root.services.text(modelData.uk, modelData.en)
                Accessible.name: text + ' ' + count
                Accessible.checked: current
                onClicked: root.stash.filter = modelData.id
                contentItem: Row {
                    spacing: 4
                    PentadText { anchors.verticalCenter: parent.verticalCenter; text: chip.text; wrapMode: Text.NoWrap; color: chip.current ? Theme.tokens.text : Theme.tokens.textMuted }
                    PentadText { anchors.verticalCenter: parent.verticalCenter; visible: chip.count > 0; text: chip.count; role: 'caption'; wrapMode: Text.NoWrap; color: Theme.tokens.textMuted }
                }
                background: ContinuousSurface {
                    extent: height / 2
                    fill: chip.current ? Theme.tokens.surfaceOverlay : chip.hovered ? Qt.alpha(Theme.tokens.surfaceOverlay, 0.6) : Theme.tokens.surfaceRaised
                    edge: chip.visualFocus ? Theme.tokens.accent : 'transparent'
                }
            }
        }
    }
    PentadScrollView {
        id: scroller
        x: 6; y: filters.y + filters.height + 8; width: root.width - 12
        height: Math.max(0, bottomBar.y - y - 4)
        opacity: root.dropInvited ? 0.22 : 1
        Behavior on opacity { NumberAnimation { duration: Theme.tokens.reducedMotion ? 0 : 140 } }
        ListView {
            id: list
            objectName: 'stash-list'
            clip: true
            model: root.items
            boundsBehavior: Flickable.StopAtBounds
            cacheBuffer: 240
            onContentYChanged: if (!root.rebuilding) root.stash.contentY = contentY
            delegate: Loader {
                id: slot
                required property var modelData
                required property int index
                width: ListView.view.width
                sourceComponent: modelData.kind === 'header' ? headerItem : modelData.kind === 'strip' ? stripItem : rowItem
                Component {
                    id: headerItem
                    Item {
                        height: slot.index === 0 ? 24 : 32
                        PentadText {
                            objectName: 'stash-section-' + slot.modelData.sectionId
                            x: 6; anchors.bottom: parent.bottom; bottomPadding: 6
                            text: slot.modelData.title
                            role: 'caption'; font.weight: Font.DemiBold; color: Theme.tokens.textMuted; wrapMode: Text.NoWrap
                        }
                    }
                }
                Component {
                    id: stripItem
                    Item {
                        height: strip.implicitHeight + 4
                        StashPhotoStrip {
                            id: strip
                            objectName: 'stash-photo-strip-' + slot.modelData.sectionId
                            x: 6; width: parent.width - 12
                            services: root.services
                            photos: slot.modelData.photos
                            metadata: root.metadata
                            expanded: root.stash.expandedDays.indexOf(slot.modelData.sectionId) >= 0
                            selectedIds: root.stash.selectedIds
                            onExpandRequested: root.toggleDay(slot.modelData.sectionId)
                            onActivated: (id, modifiers) => { root.selectEntry(id, modifiers); root.focusList(); }
                            onOpened: id => root.openEntry(id)
                            onContextRequested: (id, position) => root.showContext(id, strip, position)
                        }
                    }
                }
                Component {
                    id: rowItem
                    StashRow {
                        id: row
                        objectName: 'stash-row-' + slot.modelData.entry.id
                        services: root.services
                        entry: slot.modelData.entry
                        info: root.infoFor(slot.modelData.entry)
                        sectionId: slot.modelData.sectionId
                        selected: root.stash.selectedIds.indexOf(row.entry.id) >= 0
                        now: root.now
                        dragUris: root.dragUrisFor(row.entry)
                        onActivated: modifiers => { root.selectEntry(row.entry.id, modifiers); root.focusList(); }
                        onOpened: root.openEntry(row.entry.id)
                        onContextRequested: position => root.showContext(row.entry.id, row, position)
                        onPinToggled: root.shelf.pin(row.entry.id, !row.entry.pinned)
                        onCopyRequested: root.copyEntry(row.entry.id)
                    }
                }
            }
        }
    }
    PentadText {
        anchors.centerIn: scroller
        visible: root.shelf.entries.length > 0 && root.items.length === 0
        text: root.services.text('Нічого не знайдено', 'Nothing found')
        color: Theme.tokens.textMuted
    }
    PentadDropZone {
        objectName: 'stash-drop-zone'
        x: 12; y: scroller.y; width: root.width - 24; height: scroller.height
        readonly property bool shown: root.shelf.ready && root.shelf.entries.length === 0 || root.dropInvited
        opacity: shown ? 1 : 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: Theme.tokens.reducedMotion ? 0 : 140 } }
        active: root.dropInvited
        fill: root.shelf.entries.length ? Qt.alpha(Theme.tokens.surfaceRaised, 0.94) : root.dropInvited ? Theme.tokens.surfaceOverlay : Theme.tokens.surfaceRaised
        title: root.dropInvited ? root.services.text('Відпустіть тут', 'Release here') : root.services.text('Перетягніть сюди', 'Drop here')
        hint: root.services.text('файли, посилання, фото або текст', 'files, links, images or text')
    }
    Column {
        id: bottomBar
        x: 12; width: root.width - 24
        y: root.height - height - 12
        spacing: 8
        PentadText {
            objectName: 'stash-message'
            width: parent.width
            visible: root.message !== ''
            text: root.message
            role: 'caption'; color: Theme.tokens.error; maximumLineCount: 2; elide: Text.ElideRight
        }
        StashComposer { id: composer; objectName: 'stash-composer'; width: parent.width; services: root.services }
    }
    PentadMenu {
        id: contextMenu
        property string entryId: ''
        width: 210
        entries: {
            const entry = root.entryById(contextMenu.entryId);
            if (!entry) return [];
            const local = ShelfLogic.shelfLocalUri(entry), info = root.infoFor(entry);
            const result = [{ text: root.services.text('Відкрити', 'Open'), action: 'open', enabled: !(info && info.available === false) },
                { text: root.services.text('Копіювати', 'Copy'), action: 'copy' },
                { text: entry.pinned ? root.services.text('Відкріпити', 'Unpin') : root.services.text('Закріпити', 'Pin'), action: 'pin', enabled: root.writable }];
            if (local) result.push({ text: root.services.text('Показати теку', 'Show folder'), action: 'folder' });
            if (entry.kind === 'image' && !entry.localUri)
                result.push({ text: root.services.text('Завантажити', 'Download'), action: 'download', enabled: root.writable && !(root.shelf.downloads[entry.id] && root.shelf.downloads[entry.id].pending) });
            result.push({ separator: true });
            result.push({ text: root.services.text('Прибрати', 'Remove'), action: 'remove', enabled: root.writable,
                description: root.services.text('Прибрати вибране зі Сховку. Оригінальні файли залишаться на диску.', 'Remove the selection from the Stash. Original files stay on disk.') });
            return result;
        }
        onActivated: entry => {
            if (entry.action === 'open') root.openEntry(contextMenu.entryId);
            else if (entry.action === 'copy') root.copyEntry(contextMenu.entryId);
            else if (entry.action === 'pin') root.pinSelected();
            else if (entry.action === 'folder') root.showFolder(contextMenu.entryId);
            else if (entry.action === 'download') root.shelf.download(contextMenu.entryId);
            else if (entry.action === 'remove') root.removeSelected();
        }
    }
    Popup {
        id: notePopup
        property string text: ''
        x: 24; y: 64; width: root.width - 48
        height: Math.min(implicitHeight, root.height - 128)
        padding: 16
        background: ContinuousSurface { fill: Theme.tokens.surfaceRaised; extent: Metrics.radiusCard }
        contentItem: PentadScrollView {
            TextArea {
                readOnly: true; selectByMouse: true
                text: notePopup.text; textFormat: TextEdit.PlainText; wrapMode: TextEdit.Wrap
                color: Theme.tokens.text; selectionColor: Theme.tokens.accent; selectedTextColor: Theme.tokens.surface
                font.family: Theme.tokens.fontFamily; font.pixelSize: Metrics.textBody
                padding: 0; background: null
            }
        }
    }
}
