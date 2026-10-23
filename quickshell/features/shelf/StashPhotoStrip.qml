import QtQuick
import QtQuick.Controls.Basic
import qs.components
import qs.theme
import "../sidebar"
import "../../logic/shelf.mjs" as ShelfLogic

// The photos of one day as 64 px thumbnails on one line. When they do not fit, the last slot
// reads "+N" and expands the strip into a wrapping grid. Every tile drags its file out natively.
Item {
    id: root
    required property var services
    required property var photos
    required property var metadata
    property bool expanded: false
    property var selectedIds: []
    // 64 in the window; the quick tab passes 56.
    property int tileHeight: 64
    readonly property int spacing: 4
    // The view passes its own count, so keyboard navigation sees the same tiles.
    property int slots: Math.max(1, Math.floor((width + spacing) / (tileHeight + spacing)))
    readonly property bool overflows: photos.length > slots
    readonly property int shownCount: expanded || !overflows ? photos.length : slots - 1
    signal expandRequested
    signal activated(string id, int modifiers)
    signal opened(string id)
    signal contextRequested(string id, point position)

    implicitHeight: flow.implicitHeight

    function infoFor(entry) {
        const uri = ShelfLogic.shelfLocalUri(entry);
        return uri ? root.metadata[uri] : undefined;
    }

    Flow {
        id: flow
        width: root.width
        spacing: root.spacing
        Repeater {
            model: root.photos.slice(0, root.shownCount)
            delegate: Item {
                id: tile
                required property var modelData
                readonly property var info: root.infoFor(modelData)
                readonly property string localUri: ShelfLogic.shelfLocalUri(modelData)
                readonly property bool available: !!localUri && (!info || info.available !== false)
                readonly property bool selected: root.selectedIds.indexOf(modelData.id) >= 0
                objectName: 'stash-photo-' + modelData.id
                width: root.tileHeight
                height: root.tileHeight
                Accessible.role: Accessible.ListItem
                Accessible.name: modelData.label
                Accessible.selected: tile.selected
                // Tiles share the row radius, concentric with the surface at the list inset.
                ContinuousSurface {
                    anchors.fill: parent
                    extent: Metrics.radiusPopover - 6
                    clipContent: false
                    fill: tile.selected ? Theme.tokens.surfaceOverlay : 'transparent'
                }
                ContinuousSurface {
                    anchors.fill: parent
                    anchors.margins: tile.selected ? 4 : 0
                    extent: tile.selected ? Metrics.radiusSmall : Metrics.radiusPopover - 6
                    fill: Theme.tokens.surfaceRaised
                    Image {
                        anchors.fill: parent
                        visible: tile.available
                        source: tile.available ? (tile.info && tile.info.thumbnail || tile.localUri) : ''
                        sourceSize.width: 128
                        sourceSize.height: 128
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        opacity: drag.exporting ? 0.35 : 1
                    }
                    PentadIcon {
                        anchors.centerIn: parent
                        visible: !tile.available
                        source: Qt.resolvedUrl('../../assets/icons/material/tools/image-symbolic.svg')
                        color: Theme.tokens.textMuted
                    }
                }
                TapHandler {
                    acceptedButtons: Qt.RightButton
                    onTapped: (eventPoint, button) => root.contextRequested(tile.modelData.id, tile.mapToItem(root, eventPoint.position))
                }
                FileDragSource {
                    id: drag
                    services: root.services
                    uris: tile.available ? [tile.localUri] : []
                    onClicked: mouse => { if (!exporting) root.activated(tile.modelData.id, mouse.modifiers); }
                    onDoubleClicked: root.opened(tile.modelData.id)
                    onExportingChanged: root.services.stash.exporting = exporting
                }
                // A tile destroyed during the blocking drag never reports its end.
                Component.onDestruction: if (drag.exporting) root.services.stash.exporting = false
            }
        }
        AbstractButton {
            id: toggle
            objectName: 'stash-photo-more'
            visible: root.overflows
            width: root.tileHeight
            height: root.tileHeight
            focusPolicy: Qt.TabFocus
            text: root.expanded ? '' : '+' + (root.photos.length - root.shownCount)
            Accessible.name: root.expanded ? root.services.text('Згорнути фото', 'Collapse photos')
                : root.services.text('Показати всі фото', 'Show all photos')
            onClicked: root.expandRequested()
            background: ContinuousSurface {
                extent: Metrics.radiusPopover - 6
                fill: toggle.hovered || toggle.down ? Theme.tokens.surfaceOverlay : Theme.tokens.surfaceRaised
                edge: toggle.visualFocus ? Theme.tokens.accent : 'transparent'
            }
            contentItem: Item {
                PentadText {
                    anchors.centerIn: parent
                    visible: !root.expanded
                    text: toggle.text
                    role: 'section'
                    font.weight: Font.DemiBold
                    wrapMode: Text.NoWrap
                    color: Theme.tokens.textMuted
                }
                PentadIcon {
                    anchors.centerIn: parent
                    visible: root.expanded
                    source: Qt.resolvedUrl('../../assets/icons/material/media/remove-symbolic.svg')
                    color: Theme.tokens.textMuted
                }
            }
        }
    }
}
