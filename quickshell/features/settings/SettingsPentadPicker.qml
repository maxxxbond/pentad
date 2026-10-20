pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import qs.components
import qs.theme
import "../../logic/pentads.mjs" as Pentads

// Checkbox group for the five sections. Cells outside `allowed` are disabled; the last active
// section cannot be cleared and a short error is shown instead.
ColumnLayout {
    id: root
    property var allowed: Pentads.zoneIds
    property var value: []
    property string accessibleName: ""
    property var services: null
    signal activated(var zones)

    readonly property var active: Pentads.normalizeZones(value, allowed)
    property string error: ""
    readonly property real inset: 3

    function t(uk, en) { return services && services.text ? services.text(uk, en) : en; }
    function toggle(id) {
        const result = Pentads.toggleZone(active, id, allowed);
        if (result.ok) { error = ""; activated(result.zones); return; }
        if (result.error === "last") {
            error = t("Потрібна принаймні одна секція.", "Keep at least one section on.");
            errorTimer.restart();
        }
    }

    spacing: 8
    Accessible.name: accessibleName
    Accessible.role: Accessible.Grouping

    Timer { id: errorTimer; interval: 3000; onTriggered: root.error = "" }

    RowLayout {
        Layout.fillWidth: true
        spacing: 8
        Repeater {
            model: Pentads.zones
            delegate: Control {
                id: cell
                required property var modelData
                readonly property bool supported: root.allowed.indexOf(modelData.id) >= 0
                readonly property bool checked: root.active.indexOf(modelData.id) >= 0
                readonly property string zoneLabel: root.t(modelData.labelUk, modelData.labelEn)
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                implicitHeight: 76
                activeFocusOnTab: supported
                Accessible.name: zoneLabel
                Accessible.role: Accessible.CheckBox
                Accessible.checkable: true
                Accessible.checked: checked
                Accessible.description: supported ? "" : root.t("Віджет не підтримує цю секцію", "This widget does not support this section")
                Keys.onPressed: function(event) {
                    if (!supported || (event.key !== Qt.Key_Space && event.key !== Qt.Key_Return && event.key !== Qt.Key_Enter)) return;
                    root.toggle(modelData.id);
                    event.accepted = true;
                }

                ContinuousSurface {
                    anchors.fill: parent
                    fill: cell.checked ? Theme.tokens.surfaceOverlay : Theme.tokens.surfaceRaised
                    edge: cell.visualFocus ? Theme.tokens.accent : "transparent"
                    extent: Metrics.radiusMedium
                    opacity: cell.supported ? 1 : 0.55
                }
                Column {
                    anchors.fill: parent
                    anchors.margins: 8
                    spacing: 6
                    opacity: cell.supported ? 1 : 0.55
                    // Mini diagram: side menus, bar with three sections.
                    Item {
                        id: diagram
                        width: parent.width
                        height: 32
                        Repeater {
                            model: Pentads.zones
                            delegate: Rectangle {
                                required property var modelData
                                readonly property bool menu: modelData.kind === "menu"
                                readonly property int slotIndex: Pentads.zoneIds.indexOf(modelData.id)
                                readonly property real barWidth: (diagram.width - 2 * menuWidth - 2 * root.inset - 2 * root.inset) / 3
                                readonly property real menuWidth: diagram.width / 6
                                x: menu ? (slotIndex === 0 ? 0 : diagram.width - menuWidth)
                                    : menuWidth + root.inset + (slotIndex - 1) * (barWidth + root.inset / 2)
                                y: 0
                                width: menu ? menuWidth : barWidth - root.inset / 2
                                height: menu ? diagram.height : diagram.height / 3
                                radius: Metrics.radiusSmall - root.inset
                                color: modelData.id === cell.modelData.id ? Theme.tokens.accent : Qt.alpha(Theme.tokens.text, 0.12)
                            }
                        }
                    }
                    PentadText {
                        width: parent.width
                        text: cell.zoneLabel
                        textFormat: Text.PlainText
                        role: "caption"
                        color: cell.checked ? Theme.tokens.text : Theme.tokens.textMuted
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.NoWrap
                        elide: Text.ElideRight
                    }
                }
                HoverHandler { enabled: cell.supported; cursorShape: Qt.PointingHandCursor }
                TapHandler {
                    enabled: cell.supported
                    onTapped: { cell.forceActiveFocus(); root.toggle(cell.modelData.id); }
                }
            }
        }
    }
    PentadText {
        objectName: "pentad-picker-error"
        Layout.fillWidth: true
        visible: root.error !== ""
        text: root.error
        textFormat: Text.PlainText
        role: "caption"
        color: Theme.tokens.error
        wrapMode: Text.Wrap
        Accessible.role: Accessible.AlertMessage
    }
}
