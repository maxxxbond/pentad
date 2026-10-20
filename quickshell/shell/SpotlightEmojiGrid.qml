pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls.Basic
import qs.theme
import qs.components
import '../logic/spotlight-dispatch.mjs' as Dispatch

Item {
    id: root
    objectName: 'spotlight-emoji-grid'
    required property var spotlight
    required property var services
    readonly property bool emojiResults: spotlight.results.length > 0 && spotlight.results[0].category === 'emoji'
    readonly property bool wide: width >= 480
    readonly property bool showPreview: spotlight.selectedResult?.category === 'emoji' && height >= (wide ? 280 : 250)
    readonly property real previewWidth: wide && showPreview ? Math.min(192, width * 0.32) : 0
    readonly property int columns: Math.max(1, Math.floor(grid.width / 64))
    implicitHeight: wide ? 340 : 396

    function move(direction) {
        if (!spotlight.pending)
            spotlight.selectedIndex = Dispatch.moveGridSelection(
                spotlight.selectedIndex, spotlight.results.length, columns, direction);
    }

    PentadText {
        text: root.services.text('Емодзі', 'Emoji')
        role: 'caption'; color: Theme.tokens.textMuted
    }
    GridView {
        id: grid
        objectName: 'spotlight-emoji-results'
        x: 0; y: 32
        width: Math.max(0, root.width - root.previewWidth - (root.previewWidth ? 24 : 0))
        height: Math.max(0, root.height - y - (!root.wide && root.showPreview ? 120 : 0))
        cellWidth: width / root.columns; cellHeight: 72
        clip: true
        model: root.emojiResults ? root.spotlight.results : []
        currentIndex: root.spotlight.selectedIndex
        boundsBehavior: Flickable.StopAtBounds
        onCurrentIndexChanged: if (currentIndex >= 0 && currentIndex < count) positionViewAtIndex(currentIndex, GridView.Contain)
        onWidthChanged: if (currentIndex >= 0 && currentIndex < count) positionViewAtIndex(currentIndex, GridView.Contain)
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
        delegate: ItemDelegate {
            id: cell
            objectName: 'spotlight-emoji-' + index
            required property var modelData
            required property int index
            readonly property bool selected: index === root.spotlight.selectedIndex
            width: grid.cellWidth; height: grid.cellHeight
            focusPolicy: Qt.NoFocus; hoverEnabled: true
            enabled: !root.spotlight.pending
            Accessible.name: modelData.subtitle || modelData.title
            ToolTip.visible: hovered && !root.showPreview
            ToolTip.text: Accessible.name
            onHoveredChanged: if (hovered && !root.spotlight.pending) root.spotlight.selectedIndex = index
            onClicked: root.spotlight.activate(index)
            TapHandler {
                acceptedButtons: Qt.RightButton
                onTapped: {
                    if (root.spotlight.pending) return;
                    root.spotlight.selectedIndex = cell.index;
                    root.spotlight.showActions();
                }
            }
            contentItem: Text {
                text: cell.modelData.preview?.content || ''
                font.family: 'Noto Color Emoji'
                font.pixelSize: 32
                horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                textFormat: Text.PlainText
                color: Theme.tokens.text
                scale: cell.selected ? 1.08 : 1
                Behavior on scale { NumberAnimation { duration: Motion.short; easing.type: Easing.OutCubic } }
            }
            background: ContinuousSurface {
                x: 3; y: 3; width: cell.width - 6; height: cell.height - 6
                extent: 18; clipContent: false
                fill: Qt.alpha(Theme.tokens.accent, cell.selected ? 0.12 : 0)
                edge: Qt.alpha(Theme.tokens.accent, cell.selected ? 0.32 : 0)
            }
        }
        PentadText {
            anchors.centerIn: parent; width: Math.max(0, parent.width - 24)
            horizontalAlignment: Text.AlignHCenter
            visible: grid.count === 0
            text: root.spotlight.searchPending ? root.services.text('Шукаємо…', 'Searching…')
                : root.services.text('Спробуйте іншу назву емодзі', 'Try another emoji name')
            color: Theme.tokens.textMuted
        }
    }
    Item {
        id: preview
        visible: root.showPreview
        x: root.wide ? root.width - width : 0
        y: root.wide ? 32 : root.height - height
        width: root.wide ? root.previewWidth : root.width
        height: root.wide ? root.height - y : 108
        Rectangle {
            x: root.wide ? -12 : 0; y: 0
            width: root.wide ? 1 : parent.width
            height: root.wide ? parent.height : 1
            color: Qt.alpha(Theme.tokens.text, 0.08)
        }
        Text {
            id: glyph
            x: root.wide ? 0 : 4
            y: root.wide ? Math.max(0, (parent.height - 220) / 2) : 16
            width: root.wide ? parent.width : 76
            height: root.wide ? 108 : 76
            text: root.spotlight.selectedResult?.preview?.content || ''
            textFormat: Text.PlainText
            font.family: 'Noto Color Emoji'; font.pixelSize: root.wide ? 76 : 52
            color: Theme.tokens.text
            horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
        }
        PentadText {
            id: name
            x: root.wide ? 8 : 100
            y: root.wide ? glyph.y + glyph.height + 16 : 16
            width: Math.max(0, parent.width - x - 8)
            height: root.wide ? 60 : 44
            text: root.spotlight.selectedResult?.subtitle || ''
            textFormat: Text.PlainText
            horizontalAlignment: root.wide ? Text.AlignHCenter : Text.AlignLeft
            verticalAlignment: Text.AlignVCenter
            font.pixelSize: 15; wrapMode: Text.Wrap
            maximumLineCount: 3; elide: Text.ElideRight
        }
        ToolButton {
            id: copyButton
            x: root.wide ? Math.max(0, (parent.width - width) / 2) : 92
            y: Math.min(parent.height - height, name.y + name.height + 8)
            width: Math.max(0, Math.min(148, parent.width - (root.wide ? 0 : 92))); height: 36
            focusPolicy: Qt.NoFocus
            enabled: !root.spotlight.pending && !!root.spotlight.selectedResult
            Accessible.name: root.services.text('Копіювати емодзі', 'Copy emoji')
            onClicked: root.spotlight.activate()
            contentItem: Row {
                spacing: 8
                PentadIcon {
                    anchors.verticalCenter: parent.verticalCenter
                    pixelSize: 18; source: Qt.resolvedUrl('../assets/icons/spotlight/return.svg')
                    color: Theme.tokens.accent
                }
                PentadText {
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.services.text('Копіювати', 'Copy')
                    role: 'caption'; color: Theme.tokens.accent
                }
            }
            background: ContinuousSurface {
                extent: 10; clipContent: false
                fill: Qt.alpha(Theme.tokens.accent, copyButton.hovered ? 0.1 : 0)
            }
        }
    }
}
