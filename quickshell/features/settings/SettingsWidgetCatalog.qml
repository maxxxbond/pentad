pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls.Basic
import qs.components
import qs.theme
import "../../logic/settings-list.mjs" as ListLogic

// Installed widgets as a grid of cards: placement thumbnail, name, module id and where it
// lives, with the enable switch and per-widget actions. Cards reorder by dragging the grip
// or with Alt + arrows; the last card adds a widget.
// model: [{ id, label, moduleId, enabled, zones, zoneLabel, configurable }]
FocusScope {
    id: root
    property var model: []
    property bool addable: true
    property string addLabel: "Add widget"
    property string configureLabel: "Settings"
    property string removeLabel: "Remove"
    property string enableLabel: "Enabled"
    property string offLabel: "Off"
    property string moveHint: "Alt + arrows reorder"
    signal reordered(var ids)
    signal removed(string id)
    signal toggled(string id, bool enabled)
    signal configure(string id)
    signal added()

    readonly property alias repeater: cards
    readonly property int count: model ? model.length : 0
    readonly property int columns: width >= 560 ? 2 : 1
    readonly property real gap: 8
    readonly property real cardWidth: Math.max(1, Math.floor((width - gap * (columns - 1)) / columns))
    readonly property real cardHeight: 92
    readonly property int slots: count + (addable ? 1 : 0)
    readonly property int rowCount: Math.ceil(slots / columns)
    implicitWidth: 320
    implicitHeight: rowCount > 0 ? rowCount * cardHeight + (rowCount - 1) * gap : 0
    Accessible.role: Accessible.List

    function ids() { return (model || []).map(function(entry) { return entry.id; }); }
    function move(from, to) {
        const list = ids();
        const next = ListLogic.moveItem(list, from, to);
        if (next.join("\u0000") === list.join("\u0000")) return false;
        reordered(next);
        return true;
    }
    function cellX(index) { return (index % columns) * (cardWidth + gap); }
    function cellY(index) { return Math.floor(index / columns) * (cardHeight + gap); }
    // Card index under a point (center of the dragged card), clamped to the real cards.
    function indexAt(x, y) {
        const col = Math.max(0, Math.min(columns - 1, Math.floor(x / (cardWidth + gap))));
        const row = Math.max(0, Math.min(rowCount - 1, Math.floor(y / (cardHeight + gap))));
        return Math.max(0, Math.min(count - 1, row * columns + col));
    }

    component GhostButton: PentadButton {
        id: ghost
        controlHeight: Metrics.controlSmall
        implicitWidth: Metrics.controlSmall
        iconSize: Metrics.panelIcon
        background: Rectangle {
            radius: Metrics.radiusSmall
            color: ghost.down || ghost.checked ? Theme.tokens.surfaceOverlay
                : ghost.hovered ? Qt.alpha(Theme.tokens.text, 0.06) : "transparent"
            border.width: ghost.visualFocus ? 2 : 0
            border.color: Theme.tokens.accent
        }
    }

    Repeater {
        id: cards
        model: root.model
        delegate: Control {
            id: card
            required property int index
            required property var modelData
            readonly property bool widgetEnabled: modelData.enabled !== false
            readonly property bool configurable: modelData.configurable === true
            property bool dragging: false
            property real dx: 0
            property real dy: 0
            objectName: "widgetCard_" + modelData.id
            x: root.cellX(index) + dx
            y: root.cellY(index) + dy
            width: root.cardWidth
            height: root.cardHeight
            z: dragging ? 2 : 0
            activeFocusOnTab: true
            Accessible.role: Accessible.ListItem
            Accessible.name: modelData.label
            Accessible.description: root.moveHint
            Behavior on x { enabled: !card.dragging && !Theme.tokens.reducedMotion; NumberAnimation { duration: Motion.medium; easing.type: Easing.OutCubic } }
            Behavior on y { enabled: !card.dragging && !Theme.tokens.reducedMotion; NumberAnimation { duration: Motion.medium; easing.type: Easing.OutCubic } }

            function moveBy(delta) {
                const target = Math.max(0, Math.min(root.count - 1, index + delta));
                if (root.move(index, target)) {
                    Qt.callLater(function() {
                        const moved = cards.itemAt(target);
                        if (moved) moved.forceActiveFocus(Qt.TabFocusReason);
                    });
                }
            }
            Keys.onPressed: function(event) {
                if (event.modifiers & Qt.AltModifier) {
                    if (event.key === Qt.Key_Left || event.key === Qt.Key_Up) { moveBy(event.key === Qt.Key_Up ? -root.columns : -1); event.accepted = true; }
                    else if (event.key === Qt.Key_Right || event.key === Qt.Key_Down) { moveBy(event.key === Qt.Key_Down ? root.columns : 1); event.accepted = true; }
                    return;
                }
                if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && card.configurable) {
                    root.configure(card.modelData.id);
                    event.accepted = true;
                }
            }

            // Borderless card: tonal lift on hover and drag, an edge only for keyboard focus.
            ContinuousSurface {
                anchors.fill: parent
                fill: card.dragging ? Theme.tokens.surfaceOverlay
                    : cardHover.hovered ? Qt.tint(Theme.tokens.surfaceRaised, Qt.alpha(Theme.tokens.text, 0.05)) : Theme.tokens.surfaceRaised
                edge: card.visualFocus ? Theme.tokens.accent : "transparent"
                extent: Metrics.radiusCard
                Behavior on fill { enabled: !Theme.tokens.reducedMotion; ColorAnimation { duration: Motion.short } }
            }
            HoverHandler { id: cardHover }

            Item {
                id: handle
                objectName: "dragHandle"
                x: 4
                width: 20
                height: parent.height
                enabled: root.enabled
                Accessible.ignored: true
                PentadDragHandle {
                    anchors.centerIn: parent
                    engaged: handleArea.containsMouse || card.dragging
                    opacity: handleArea.containsMouse || card.dragging || cardHover.hovered || card.activeFocus ? 1 : 0.45
                }
                MouseArea {
                    id: handleArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: card.dragging ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                    property real pressX: 0
                    property real pressY: 0
                    onPressed: function(mouse) {
                        card.forceActiveFocus();
                        const point = mapToItem(root, mouse.x, mouse.y);
                        pressX = point.x;
                        pressY = point.y;
                        card.dragging = true;
                    }
                    onPositionChanged: function(mouse) {
                        if (!card.dragging) return;
                        const point = mapToItem(root, mouse.x, mouse.y);
                        card.dx = point.x - pressX;
                        card.dy = point.y - pressY;
                    }
                    onReleased: {
                        const centerX = root.cellX(card.index) + card.dx + card.width / 2;
                        const centerY = root.cellY(card.index) + card.dy + card.height / 2;
                        const target = root.indexAt(centerX, centerY);
                        card.dragging = false;
                        card.dx = 0;
                        card.dy = 0;
                        if (target !== card.index) root.move(card.index, target);
                    }
                    onCanceled: { card.dragging = false; card.dx = 0; card.dy = 0; }
                }
            }

            SettingsPlacementArt {
                id: art
                objectName: "pentadGlyph"
                x: handle.x + handle.width + 4
                anchors.verticalCenter: parent.verticalCenter
                zones: card.modelData.zones || []
                dimmed: !card.widgetEnabled
                accessibleName: card.modelData.label
            }

            Item {
                id: body
                x: art.x + art.width + 12
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: Math.max(0, actions.x - x - 10)
                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width
                    PentadText {
                        objectName: "widgetName"
                        width: parent.width
                        text: card.modelData.label
                        textFormat: Text.PlainText
                        solid: true
                        font.weight: Font.Medium
                        color: card.widgetEnabled ? Theme.tokens.text : Theme.tokens.textMuted
                        elide: Text.ElideRight
                        wrapMode: Text.NoWrap
                    }
                    PentadText {
                        objectName: "widgetModule"
                        width: parent.width
                        visible: card.modelData.moduleId !== undefined && card.modelData.moduleId !== card.modelData.label
                        text: card.modelData.moduleId || ""
                        textFormat: Text.PlainText
                        solid: true
                        role: "caption"
                        color: Theme.tokens.textMuted
                        elide: Text.ElideMiddle
                        wrapMode: Text.NoWrap
                    }
                    PentadText {
                        objectName: "widgetZones"
                        width: parent.width
                        visible: text !== ""
                        text: card.widgetEnabled ? (card.modelData.zoneLabel || "") : root.offLabel
                        textFormat: Text.PlainText
                        solid: true
                        role: "caption"
                        font.weight: Font.Medium
                        color: Theme.tokens.textMuted
                        elide: Text.ElideRight
                        wrapMode: Text.NoWrap
                    }
                }
                MouseArea {
                    anchors.fill: parent
                    enabled: card.configurable && root.enabled
                    cursorShape: Qt.PointingHandCursor
                    onClicked: { card.forceActiveFocus(); root.configure(card.modelData.id); }
                }
            }

            Column {
                id: actions
                anchors.right: parent.right
                anchors.rightMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                spacing: 4
                PentadToggle {
                    objectName: "enableToggle"
                    anchors.right: parent.right
                    implicitHeight: Metrics.controlSmall
                    checked: card.widgetEnabled
                    accessibleName: root.enableLabel + " " + card.modelData.label
                    requestedEnabled: root.enabled
                    onToggled: {
                        root.toggled(card.modelData.id, checked);
                        checked = Qt.binding(function() { return card.widgetEnabled; });
                    }
                }
                Row {
                    anchors.right: parent.right
                    spacing: 0
                    GhostButton {
                        objectName: "configureButton"
                        visible: card.configurable
                        iconSource: Qt.resolvedUrl("../../assets/icons/material/controls/settings-symbolic.svg")
                        accessibleName: root.configureLabel + " " + card.modelData.label
                        requestedEnabled: root.enabled
                        onClicked: root.configure(card.modelData.id)
                    }
                    GhostButton {
                        objectName: "removeButton"
                        iconSource: Qt.resolvedUrl("../../assets/icons/material/close-symbolic.svg")
                        accessibleName: root.removeLabel + " " + card.modelData.label
                        requestedEnabled: root.enabled
                        onClicked: root.removed(card.modelData.id)
                    }
                }
            }
        }
    }

    Control {
        id: addCard
        objectName: "widgetAddCard"
        visible: root.addable
        x: root.cellX(root.count)
        y: root.cellY(root.count)
        width: root.cardWidth
        height: root.cardHeight
        activeFocusOnTab: visible
        Accessible.role: Accessible.Button
        Accessible.name: root.addLabel
        Accessible.onPressAction: root.added()
        Keys.onPressed: function(event) {
            if (event.key === Qt.Key_Space || event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                root.added();
                event.accepted = true;
            }
        }
        // A quieter tonal card than the widgets: a place to add, not an item.
        Rectangle {
            anchors.fill: parent
            radius: Metrics.radiusCard
            color: addHover.hovered || addTap.pressed ? Qt.alpha(Theme.tokens.text, 0.06) : Qt.alpha(Theme.tokens.text, 0.03)
            border.width: addCard.visualFocus ? 2 : 0
            border.color: Theme.tokens.accent
            Behavior on color { enabled: !Theme.tokens.reducedMotion; ColorAnimation { duration: Motion.short } }
        }
        Row {
            anchors.centerIn: parent
            spacing: 12
            Rectangle {
                width: Metrics.controlMedium
                height: Metrics.controlMedium
                radius: width / 2
                color: addHover.hovered ? Qt.tint(Theme.tokens.surfaceOverlay, Qt.alpha(Theme.tokens.text, 0.05)) : Theme.tokens.surfaceOverlay
                anchors.verticalCenter: parent.verticalCenter
                PentadIcon {
                    anchors.centerIn: parent
                    source: Qt.resolvedUrl("../../assets/icons/material/controls/add-symbolic.svg")
                    pixelSize: Metrics.statusIcon
                    color: Theme.tokens.accent
                    Accessible.ignored: true
                }
            }
            PentadText {
                anchors.verticalCenter: parent.verticalCenter
                text: root.addLabel
                textFormat: Text.PlainText
                font.weight: Font.Medium
                color: Theme.tokens.text
                wrapMode: Text.NoWrap
            }
        }
        HoverHandler { id: addHover; enabled: root.enabled; cursorShape: Qt.PointingHandCursor }
        TapHandler { id: addTap; enabled: root.enabled; onTapped: { addCard.forceActiveFocus(); root.added(); } }
    }
}
