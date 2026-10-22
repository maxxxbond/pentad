import QtQuick
import Quickshell
import qs.components
import qs.theme

Item {
    id: root
    required property var entry
    property var fileInfo: ({})
    property bool readOnly: false
    property bool selected: false
    property string language: 'en'
    property bool showFallbackIcon: true
    property int navigationColumns: 3
    property var exportUris: [entry.uri]
    property var exportData: ({ 'text/uri-list': exportUris.join('\r\n') + '\r\n' })
    property string previewOverride: ''
    property string previewObjectName: 'shelf-thumbnail-' + entry.id
    property string typeLabel: fileInfo.folder ? tr('Тека', 'Folder') : fileInfo.mimeType === 'application/pdf' ? 'PDF'
        : fileInfo.mimeType && fileInfo.mimeType.startsWith('image/') ? tr('Зображення', 'Image')
        : (entry.label.match(/\.([^.]{1,8})$/) || ['', 'File'])[1].toUpperCase()
    property var openAction: null
    property bool exportInProgress: false
    property bool preparingDrag: false
    property var dragImage: null
    readonly property bool available: fileInfo.available !== false
    readonly property string thumbnailSource: previewOverride || fileInfo.thumbnail ||
        (/\.(png|jpe?g|webp|gif|bmp|svg)$/i.test(entry.uri.split(/[?#]/, 1)[0]) ? entry.uri : '')
    readonly property alias previewStatus: preview.status
    readonly property alias mouseArea: pointer
    readonly property string fileIcon: iconSource()
    signal selectedRequested(int modifiers)
    signal contextRequested(point position)
    signal navigationRequested(int offset, int modifiers)
    signal openRequested(string uri)
    signal removeRequested(string id)
    signal exportStarted(var uris)
    signal exportFinished(int action)
    width: 124
    implicitHeight: 150
    height: implicitHeight
    activeFocusOnTab: !readOnly
    Accessible.name: entry.label + (available ? '' : ' · File unavailable')
    Accessible.role: Accessible.ListItem
    Accessible.selected: selected
    Accessible.onPressAction: openEntry()
    Keys.onReturnPressed: openEntry()
    Keys.onSpacePressed: selectedRequested(Qt.ControlModifier)
    Keys.onDeletePressed: if (!readOnly) removeRequested(entry.id)
    Keys.onLeftPressed: event => navigationRequested(-1, event.modifiers)
    Keys.onRightPressed: event => navigationRequested(1, event.modifiers)
    Keys.onUpPressed: event => navigationRequested(-navigationColumns, event.modifiers)
    Keys.onDownPressed: event => navigationRequested(navigationColumns, event.modifiers)
    Keys.onMenuPressed: contextRequested(Qt.point(width / 2, height / 2))

    function openEntry() {
        if (readOnly || !available) return false;
        if (typeof openAction === 'function') openAction();
        else openRequested(entry.uri);
        return true;
    }
    function tr(uk, en) { return language === 'uk' ? uk : en; }
    function iconSource() {
        if (fileInfo.iconSource) return fileInfo.iconSource;
        const names = fileInfo.iconNames || (fileInfo.folder ? ['folder'] : ['text-x-generic']);
        for (const name of names) if (Quickshell.hasThemeIcon(name)) return Quickshell.iconPath(name, true);
        return Qt.resolvedUrl('../../assets/icons/material/media/description-symbolic.svg');
    }
    function beginExport() {
        if (readOnly || !available || preparingDrag || exportInProgress) return false;
        preparingDrag = true;
        root.grabToImage(result => {
            preparingDrag = false;
            if (!pointer.pressed || readOnly || !available) return;
            dragImage = result;
            root.Drag.imageSource = result.url;
            root.Drag.hotSpot = Qt.point(root.width / 2, 48);
            exportInProgress = true;
            root.exportStarted(root.exportUris);
            root.Drag.active = true;
            root.Drag.startDrag(Qt.CopyAction);
            root.Drag.active = false;
            exportInProgress = false;
            dragImage = null;
        }, Qt.size(Math.round(width), Math.round(height)));
        return true;
    }
    Drag.dragType: Drag.None
    Drag.supportedActions: Qt.CopyAction
    Drag.proposedAction: Qt.CopyAction
    Drag.mimeData: exportData
    Drag.onDragFinished: action => root.exportFinished(action)

    Rectangle {
        anchors.fill: parent
        radius: Metrics.radiusSmall
        color: root.selected ? Qt.alpha(Theme.tokens.accent, root.activeFocus ? 0.26 : 0.18)
            : pointer.containsMouse ? Qt.alpha(Theme.tokens.text, 0.055) : 'transparent'
        Behavior on color { ColorAnimation { duration: Theme.tokens.reducedMotion ? 0 : 100 } }
    }
    Rectangle {
        x: 8; y: 8; width: 4; height: 4; radius: 2
        color: Theme.tokens.accent
        visible: root.activeFocus
    }
    Image {
        id: preview
        objectName: root.previewObjectName
        x: (parent.width - width) / 2; y: 12
        width: Math.min(96, parent.width - 24); height: 76
        source: root.available ? root.thumbnailSource : ''
        sourceSize.width: 256; sourceSize.height: 256
        fillMode: Image.PreserveAspectFit
        asynchronous: true
        smooth: true
        opacity: root.exportInProgress ? 0.35 : 1
    }
    PentadIcon {
        anchors.centerIn: preview
        width: 56; height: 56
        source: root.fileIcon
        pixelSize: 56
        color: Theme.tokens.textMuted
        symbolic: !root.available || root.fileInfo.iconSymbolic === true || root.fileIcon.indexOf('symbolic') >= 0
            || (!root.fileInfo.iconSource && (root.fileInfo.iconNames || []).length === 0)
        visible: root.showFallbackIcon && preview.status !== Image.Ready
        opacity: root.available ? 1 : 0.4
    }
    PentadText {
        id: nameLabel
        x: 8; y: 96; width: parent.width - 16
        text: root.entry.label
        textFormat: Text.PlainText
        font.pixelSize: 13
        solid: true
        font.weight: root.selected ? Font.Medium : Font.Normal
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignTop
        wrapMode: Text.Wrap
        maximumLineCount: 2
        elide: Text.ElideRight
        color: root.available ? Theme.tokens.text : Theme.tokens.textMuted
        renderType: Text.NativeRendering
    }
    PentadText {
        // Follows the name, one or two lines tall, with no gap.
        x: 8; y: nameLabel.y + nameLabel.height; width: parent.width - 16
        text: root.available ? root.typeLabel : root.tr('Недоступний', 'Unavailable')
        textFormat: Text.PlainText
        font.pixelSize: 11
        solid: true
        wrapMode: Text.NoWrap
        color: Theme.tokens.textMuted
        opacity: 0.8
        horizontalAlignment: Text.AlignHCenter
        elide: Text.ElideRight
    }
    Rectangle {
        visible: root.preparingDrag && root.exportUris.length > 1
        x: root.width - 32; y: 10; width: 24; height: 24; radius: 6
        color: Theme.tokens.accent
        Text { anchors.centerIn: parent; text: root.exportUris.length; color: Theme.tokens.surface; font.pixelSize: 12; font.bold: true }
    }
    MouseArea {
        id: pointer
        anchors.fill: parent
        enabled: !root.readOnly
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        property point pressPosition
        property bool dragged: false
        property bool wasSelected: false
        onPressed: event => {
            pressPosition = Qt.point(event.x, event.y);
            dragged = false;
            wasSelected = root.selected;
            if (event.button === Qt.RightButton) { root.contextRequested(pressPosition); return; }
            if (!root.selected) root.selectedRequested(event.modifiers);
            root.forceActiveFocus();
        }
        onPositionChanged: event => {
            if (!pressed || !(pressedButtons & Qt.LeftButton) || dragged) return;
            const dx = event.x - pressPosition.x, dy = event.y - pressPosition.y;
            if (dx * dx + dy * dy < 100) return;
            dragged = true;
            root.beginExport();
        }
        onClicked: event => { if (event.button === Qt.LeftButton && !dragged && wasSelected) root.selectedRequested(event.modifiers); }
        onDoubleClicked: event => { if (event.button === Qt.LeftButton && !dragged) root.openEntry(); }
    }
}
