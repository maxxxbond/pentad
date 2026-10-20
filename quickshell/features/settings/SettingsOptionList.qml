import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import qs.components
import qs.theme
import "../../logic/settings-list.mjs" as ListLogic

Item {
    id: root
    property var model: []
    property bool addable: false
    property bool removable: true
    property string addLabel: "Add"
    property string removeLabel: "Remove"
    property string moveHint: "Alt + arrows reorder"
    signal reordered(var ids)
    signal removed(string id)
    signal added()
    signal toggled(string id, bool visible)
    signal configure(string id)
    property string configureLabel: "Settings"

    readonly property alias repeater: rows
    readonly property int rowHeight: Metrics.settingsRowMinHeight
    readonly property int rowSpacing: 4
    implicitWidth: 320
    implicitHeight: column.implicitHeight

    function ids() {
        return (model || []).map(function(entry) { return entry.id; });
    }
    function move(from, to) {
        const list = ids();
        const next = ListLogic.moveItem(list, from, to);
        if (next.join("\u0000") === list.join("\u0000")) return false;
        reordered(next);
        return true;
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

    ColumnLayout {
        id: column
        width: parent.width
        spacing: root.rowSpacing

        Repeater {
            id: rows
            model: root.model
            delegate: Control {
                id: row
                required property int index
                required property var modelData
                property real dragOffset: 0
                property bool dragging: false
                objectName: "optionRow_" + modelData.id
                Layout.fillWidth: true
                Layout.preferredHeight: root.rowHeight
                activeFocusOnTab: true
                z: dragging ? 2 : 0
                Accessible.name: modelData.label
                Accessible.description: root.moveHint
                Accessible.role: Accessible.ListItem
                transform: Translate { y: row.dragOffset }

                function moveBy(delta) {
                    const target = Math.max(0, Math.min(rows.count - 1, index + delta));
                    if (root.move(index, target)) {
                        Qt.callLater(function() {
                            const moved = rows.itemAt(target);
                            if (moved) moved.forceActiveFocus(Qt.TabFocusReason);
                        });
                    }
                }
                Keys.onPressed: function(event) {
                    if (!(event.modifiers & Qt.AltModifier)) return;
                    if (event.key === Qt.Key_Up) { moveBy(-1); event.accepted = true; }
                    else if (event.key === Qt.Key_Down) { moveBy(1); event.accepted = true; }
                }

                ContinuousSurface {
                    anchors.fill: parent
                    fill: row.dragging ? Theme.tokens.surfaceOverlay
                        : rowHover.hovered ? Qt.alpha(Theme.tokens.text, 0.05) : Qt.alpha(Theme.tokens.text, 0.025)
                    edge: row.visualFocus ? Theme.tokens.accent : "transparent"
                    extent: Metrics.radiusMedium
                    Behavior on fill { enabled: !Theme.tokens.reducedMotion; ColorAnimation { duration: Motion.short } }
                }
                HoverHandler { id: rowHover }
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 6
                    anchors.rightMargin: 8
                    spacing: 8

                    Item {
                        id: handle
                        objectName: "dragHandle"
                        Layout.preferredWidth: Metrics.controlSmall
                        Layout.fillHeight: true
                        enabled: root.enabled
                        Accessible.ignored: true
                        PentadDragHandle {
                            anchors.centerIn: parent
                            engaged: handleArea.containsMouse || row.dragging
                        }
                        MouseArea {
                            id: handleArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: row.dragging ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                            property real startY: 0
                            onPressed: function(mouse) {
                                row.forceActiveFocus();
                                startY = mapToItem(column, mouse.x, mouse.y).y;
                                row.dragging = true;
                            }
                            onPositionChanged: function(mouse) {
                                if (!row.dragging) return;
                                const delta = mapToItem(column, mouse.x, mouse.y).y - startY;
                                const min = -row.index * (root.rowHeight + root.rowSpacing);
                                const max = (rows.count - 1 - row.index) * (root.rowHeight + root.rowSpacing);
                                row.dragOffset = Math.max(min, Math.min(max, delta));
                            }
                            onReleased: {
                                const steps = Math.round(row.dragOffset / (root.rowHeight + root.rowSpacing));
                                row.dragging = false;
                                row.dragOffset = 0;
                                if (steps !== 0) root.move(row.index, row.index + steps);
                            }
                            onCanceled: { row.dragging = false; row.dragOffset = 0; }
                        }
                    }
                    PentadText {
                        Layout.fillWidth: true
                        text: row.modelData.label
                        textFormat: Text.PlainText
                        wrapMode: Text.NoWrap
                        elide: Text.ElideRight
                        color: row.modelData.visible === false ? Theme.tokens.textMuted : Theme.tokens.text
                    }
                    SettingsPentadGlyph {
                        objectName: "pentadGlyph"
                        visible: row.modelData.zones !== undefined
                        zones: row.modelData.zones || []
                        accessibleName: row.modelData.label
                        Layout.alignment: Qt.AlignVCenter
                    }
                    GhostButton {
                        objectName: "configureButton"
                        visible: row.modelData.configurable === true
                        iconSource: Qt.resolvedUrl("../../assets/icons/material/controls/settings-symbolic.svg")
                        accessibleName: root.configureLabel + " " + row.modelData.label
                        requestedEnabled: root.enabled
                        onClicked: root.configure(row.modelData.id)
                    }
                    PentadToggle {
                        visible: row.modelData.visible !== undefined
                        implicitHeight: Metrics.controlSmall
                        checked: row.modelData.visible === true
                        accessibleName: row.modelData.label
                        requestedEnabled: root.enabled
                        onToggled: {
                            root.toggled(row.modelData.id, checked);
                            checked = Qt.binding(function() { return row.modelData.visible === true; });
                        }
                    }
                    GhostButton {
                        objectName: "removeButton"
                        visible: root.removable
                        iconSource: Qt.resolvedUrl("../../assets/icons/material/close-symbolic.svg")
                        accessibleName: root.removeLabel + " " + row.modelData.label
                        requestedEnabled: root.enabled
                        onClicked: root.removed(row.modelData.id)
                    }
                }
            }
        }

        PentadButton {
            objectName: "addButton"
            visible: root.addable
            text: "+ " + root.addLabel
            accessibleName: root.addLabel
            requestedEnabled: root.enabled
            Layout.fillWidth: true
            onClicked: root.added()
        }
    }
}
