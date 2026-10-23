import QtQuick
import QtQuick.Controls.Basic
import qs.components
import qs.theme

// A tool or quick-action tile: press to open, or release a drag on it to send that input there.
// `tile` is { toolId, actionId?, options?, label, symbol }.
Button {
    id: control
    required property var sidebar
    required property var tile
    property bool stacked: false
    property string description: ''
    readonly property bool dropTarget: drop.containsDrag
    // While something is dragged over the drawer, every tile that takes it shows its rim.
    readonly property bool accepting: sidebar.tileAccepts(tile, sidebar.dragHover)
    objectName: 'sidebar-tile-' + tile.toolId + (tile.actionId ? '-' + tile.actionId : '')
    hoverEnabled: true
    padding: 0
    implicitHeight: stacked ? 72 : 56
    Accessible.name: tile.label
    Accessible.description: description
    scale: down ? 0.97 : dropTarget ? 1.03 : 1
    Behavior on scale { enabled: !Theme.tokens.reducedMotion; NumberAnimation { duration: Motion.press } }
    onClicked: control.sidebar.openTile(control.tile)
    PentadToolTip { visible: !!control.description && (control.hovered || control.visualFocus); text: control.description }
    background: ContinuousSurface {
        fill: control.dropTarget ? Theme.tokens.surfaceOverlay
            : control.down ? Qt.alpha(Theme.tokens.text, 0.12)
            : control.visualFocus || control.hovered ? Theme.tokens.surfaceOverlay : Theme.tokens.surfaceRaised
        extent: Metrics.radiusCard
        Behavior on fill { enabled: !Theme.tokens.reducedMotion; ColorAnimation { duration: Motion.short } }
        DropOutline {
            anchors.fill: parent
            anchors.margins: 4
            extent: Metrics.radiusCard - 4
            visible: control.accepting || control.dropTarget
            active: control.dropTarget
            strokeWidth: 1.5
            dashLength: 6
            gapLength: 5
        }
    }
    contentItem: Item {
        PentadIcon {
            id: icon
            x: control.stacked ? (parent.width - width) / 2 : 16
            y: control.stacked ? 12 : (parent.height - height) / 2
            source: Qt.resolvedUrl('../../assets/icons/material/' + control.tile.symbol + '-symbolic.svg')
            pixelSize: control.stacked ? 24 : Metrics.statusIcon
            color: control.dropTarget ? Theme.tokens.accent
                : control.hovered || control.visualFocus ? Qt.alpha(Theme.tokens.text, 0.9) : Qt.alpha(Theme.tokens.text, 0.7)
            Behavior on color { enabled: !Theme.tokens.reducedMotion; ColorAnimation { duration: Motion.short } }
        }
        PentadText {
            x: control.stacked ? 6 : icon.x + icon.width + 12
            width: parent.width - x - (control.stacked ? 6 : 12)
            y: control.stacked ? icon.y + icon.height + 8 : (parent.height - height) / 2
            text: control.tile.label
            role: control.stacked ? 'caption' : 'body'
            font.weight: Font.Medium
            horizontalAlignment: control.stacked ? Text.AlignHCenter : Text.AlignLeft
            // Stacked tiles allow two solid lines (line box = font size) so longer names fit.
            wrapMode: control.stacked ? Text.Wrap : Text.NoWrap
            maximumLineCount: control.stacked ? 2 : 1
            lineHeightMode: control.stacked ? Text.FixedHeight : Text.ProportionalHeight
            lineHeight: control.stacked ? Metrics.textCaption : 1
            elide: Text.ElideRight
            color: control.dropTarget || control.visualFocus ? Theme.tokens.text : Qt.alpha(Theme.tokens.text, 0.8)
        }
    }
    DropArea {
        id: drop
        anchors.fill: parent
        onEntered: function(drag) {
            const info = control.sidebar.enterDrag(drag);
            drag.accepted = control.sidebar.tileAccepts(control.tile, info);
            if (drag.accepted) drag.accept(Qt.CopyAction);
        }
        onExited: control.sidebar.leaveDrag()
        onDropped: function(event) { control.sidebar.dropOnTile(event, control.tile); }
    }
}
