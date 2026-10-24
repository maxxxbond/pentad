import QtQuick
import QtQuick.Controls.Basic
import Quickshell
import qs.components
import qs.theme
import "../sidebar"
import "../../logic/shelf.mjs" as ShelfLogic
import "../../logic/stash-view.mjs" as StashLogic

// One Stash entry as a 44 px row: a 32 px lead (thumbnail or type badge), the title over a muted
// subtitle, and the time on the right. Hovered or selected, the time gives way to pin, copy and
// more; `compact` (the quick tab) keeps the time. Files, web images and links drag out natively.
Item {
    id: row
    required property var services
    required property var entry
    required property var info
    required property string sectionId
    property bool selected: false
    property bool compact: false
    property var now: new Date()
    // What a drag exports; the view passes the whole selection when this row is part of it.
    property var dragUris: dragUri ? [dragUri] : []
    readonly property string language: services.text('uk', 'en')
    readonly property string localUri: ShelfLogic.shelfLocalUri(entry)
    readonly property string dragUri: ShelfLogic.shelfDragUri(entry, info)
    readonly property string type: StashLogic.entryType(entry, info)
    readonly property var badge: StashLogic.typeBadge(entry, info)
    readonly property string thumbnail: type !== 'photo' || !info || info.available === false ? ''
        : info.thumbnail || localUri
    readonly property bool showActions: !compact && (selected || hover.hovered)
    readonly property alias exporting: pointer.exporting
    signal activated(int modifiers)
    signal opened
    signal contextRequested(point position)
    signal pinToggled
    signal copyRequested

    implicitHeight: 44
    Accessible.role: Accessible.ListItem
    Accessible.name: title.text
    Accessible.description: subtitle.text
    Accessible.selected: row.selected

    HoverHandler { id: hover }
    // Concentric with the 16 px Stash surface at the list's 6 px inset: a 10 px row.
    ContinuousSurface {
        anchors.fill: parent
        extent: Metrics.radiusPopover - 6
        clipContent: false
        fill: row.selected ? Theme.tokens.surfaceOverlay : hover.hovered ? Qt.alpha(Theme.tokens.surfaceOverlay, 0.55) : 'transparent'
    }
    // The drag source takes the left button only; the right button falls through to the handler.
    TapHandler {
        acceptedButtons: Qt.RightButton
        onTapped: (eventPoint, button) => row.contextRequested(eventPoint.position)
    }
    FileDragSource {
        id: pointer
        services: row.services
        uris: row.dragUris
        onClicked: mouse => { if (!exporting) row.activated(mouse.modifiers); }
        onDoubleClicked: row.opened()
        // The overlay lets input through only while the native drag itself runs.
        onDraggingChanged: row.services.stash.exporting = dragging
    }
    // A row destroyed during the blocking drag never reports its end.
    Component.onDestruction: if (pointer.dragging) row.services.stash.exporting = false
    ContinuousSurface {
        id: lead
        x: 6
        anchors.verticalCenter: parent.verticalCenter
        width: 32
        height: 32
        extent: Metrics.radiusMedium
        readonly property string tone: row.badge.tone
        fill: row.thumbnail ? Theme.tokens.surfaceRaised
            : row.selected || hover.hovered ? Qt.tint(Theme.tokens.surfaceOverlay, Qt.alpha(Theme.tokens.text, 0.06))
            : tone === 'archive' || tone === 'neutral' ? Theme.tokens.surfaceRaised : Theme.tokens.surfaceOverlay
        Image {
            anchors.fill: parent
            visible: !!row.thumbnail
            source: row.thumbnail
            sourceSize.width: 64
            sourceSize.height: 64
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
        }
        PentadIcon {
            anchors.centerIn: parent
            visible: !row.thumbnail && row.badge.text === ''
            pixelSize: Metrics.panelIcon
            source: Qt.resolvedUrl('../../assets/icons/material/' + (lead.tone === 'note' ? 'stash/sticky-note-2-symbolic.svg'
                : lead.tone === 'link' ? 'stash/link-symbolic.svg' : lead.tone === 'media' ? 'tools/image-symbolic.svg'
                : row.info && row.info.folder ? 'tools/folder-open-symbolic.svg' : 'media/description-symbolic.svg'))
            color: lead.tone === 'note' || lead.tone === 'link' ? Qt.alpha(Theme.tokens.accent, 0.95) : Theme.tokens.textMuted
        }
        PentadText {
            anchors.centerIn: parent
            width: parent.width - 4
            visible: !row.thumbnail && row.badge.text !== ''
            text: row.badge.text
            role: 'caption'
            font.weight: Font.DemiBold
            wrapMode: Text.NoWrap
            horizontalAlignment: Text.AlignHCenter
            fontSizeMode: Text.HorizontalFit
            minimumPixelSize: 9
            color: lead.tone === 'archive' || lead.tone === 'neutral' ? Theme.tokens.textMuted : Theme.tokens.text
        }
    }
    Column {
        anchors.left: lead.right
        anchors.leftMargin: 10
        anchors.right: trailing.left
        anchors.rightMargin: 8
        anchors.verticalCenter: parent.verticalCenter
        PentadText {
            id: title
            width: parent.width
            solid: true
            text: row.entry.label || row.entry.uri
            textFormat: Text.PlainText
            wrapMode: Text.NoWrap
            elide: Text.ElideRight
        }
        PentadText {
            id: subtitle
            width: parent.width
            solid: true
            role: 'caption'
            color: Theme.tokens.textMuted
            text: StashLogic.entrySubtitle(row.entry, row.info, { language: row.language, home: Quickshell.env('HOME') || '' })
            textFormat: Text.PlainText
            wrapMode: Text.NoWrap
            elide: Text.ElideMiddle
        }
    }
    Item {
        id: trailing
        anchors.right: parent.right
        anchors.rightMargin: 6
        anchors.verticalCenter: parent.verticalCenter
        width: row.showActions ? actions.width : time.implicitWidth
        height: 28
        PentadText {
            id: time
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            visible: !row.showActions
            role: 'caption'
            color: Theme.tokens.textMuted
            wrapMode: Text.NoWrap
            text: StashLogic.rowTime(row.entry, row.sectionId, row.language, row.now)
        }
        Row {
            id: actions
            anchors.right: parent.right
            visible: row.showActions
            spacing: 4
            PentadButton {
                objectName: 'stash-row-pin'
                width: 28
                controlHeight: 28
                iconSize: Metrics.panelIcon
                iconSource: Qt.resolvedUrl('../../assets/icons/material/stash/push-pin-symbolic.svg')
                checked: row.entry.pinned === true
                accessibleName: row.entry.pinned ? row.services.text('Відкріпити', 'Unpin') : row.services.text('Закріпити', 'Pin')
                focusPolicy: Qt.TabFocus
                onClicked: row.pinToggled()
            }
            PentadButton {
                width: 28
                controlHeight: 28
                iconSize: Metrics.panelIcon
                iconSource: Qt.resolvedUrl('../../assets/icons/material/screenshot/content-copy-symbolic.svg')
                accessibleName: row.services.text('Копіювати', 'Copy')
                focusPolicy: Qt.TabFocus
                onClicked: row.copyRequested()
            }
            PentadButton {
                id: more
                width: 28
                controlHeight: 28
                iconSize: Metrics.panelIcon
                iconSource: Qt.resolvedUrl('../../assets/icons/material/stash/more-horiz-symbolic.svg')
                accessibleName: row.services.text('Більше дій', 'More actions')
                focusPolicy: Qt.TabFocus
                onClicked: row.contextRequested(more.mapToItem(row, 0, more.height))
            }
        }
    }
}
