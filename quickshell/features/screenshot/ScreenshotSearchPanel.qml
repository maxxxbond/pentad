pragma ComponentBehavior: Bound
import QtQuick
import qs.theme
import qs.components

// Vertical list of image-search engines shown beside the chosen area; any number can be ticked.
ContinuousSurface {
    id: root
    required property var services
    property var engines: []
    property var selected: ({})
    readonly property int padding: 8
    readonly property int rowHeight: Metrics.controlSmall + 4
    readonly property var chosen: root.engines.filter(function (engine) {
        return root.selected[engine.id] === true;
    }).map(function (engine) {
        return engine.id;
    })
    readonly property real panelWidth: 216
    readonly property real panelHeight: 2 * padding + grip.height + list.height + 8 + searchButton.height
    // Wanted top-left corner of the panel in the parent's coordinates.
    signal dragged(real x, real y)
    signal searchRequested(var ids)

    function toggle(id) {
        const next = Object.assign({}, selected);
        next[id] = !next[id];
        selected = next;
    }

    width: panelWidth
    height: panelHeight
    extent: 14
    fill: Theme.tokens.surface
    edge: Qt.alpha(Theme.tokens.text, 0.08)
    clipContent: false

    Column {
        x: root.padding
        y: root.padding
        width: root.width - 2 * root.padding
        spacing: 0

        Item {
            id: grip
            width: parent.width
            height: Metrics.controlSmall
            Accessible.name: root.services.text('Перемістити панель', 'Move panel')
            Row {
                anchors.verticalCenter: parent.verticalCenter
                x: 4
                spacing: 8
                PentadIcon {
                    anchors.verticalCenter: parent.verticalCenter
                    source: Qt.resolvedUrl('../../assets/icons/material/image-search-symbolic.svg')
                    pixelSize: Metrics.exposedIcon
                    color: Theme.tokens.textMuted
                }
                PentadText {
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.services.text('Шукати в', 'Search with')
                    color: Theme.tokens.textMuted
                }
            }
            MouseArea {
                id: gripArea
                property point grab: Qt.point(0, 0)
                anchors.fill: parent
                hoverEnabled: true
                preventStealing: true
                cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                onPressed: function (mouse) {
                    grab = mapToItem(root, mouse.x, mouse.y);
                }
                onPositionChanged: function (mouse) {
                    if (!pressed || !root.parent)
                        return;
                    const p = mapToItem(root.parent, mouse.x, mouse.y);
                    root.dragged(p.x - grab.x, p.y - grab.y);
                }
            }
        }

        Column {
            id: list
            width: parent.width
            spacing: 0
            Repeater {
                model: root.engines
                delegate: Item {
                    id: row
                    required property var modelData
                    readonly property bool checked: root.selected[modelData.id] === true
                    width: list.width
                    height: root.rowHeight
                    Accessible.role: Accessible.CheckBox
                    Accessible.name: row.modelData.name
                    Accessible.checked: row.checked
                    Rectangle {
                        anchors.fill: parent
                        anchors.topMargin: 1
                        anchors.bottomMargin: 1
                        radius: height / 2
                        color: rowArea.pressed ? Theme.tokens.surfaceRaised : rowArea.containsMouse ? Theme.tokens.surfaceOverlay : 'transparent'
                    }
                    Rectangle {
                        id: box
                        x: 8
                        anchors.verticalCenter: parent.verticalCenter
                        width: 18
                        height: 18
                        radius: 6
                        color: row.checked ? Theme.tokens.accent : Theme.tokens.surfaceOverlay
                        PentadIcon {
                            anchors.centerIn: parent
                            visible: row.checked
                            source: Qt.resolvedUrl('../../assets/icons/material/controls/check-symbolic.svg')
                            pixelSize: 14
                            color: Theme.tokens.onAccent
                        }
                    }
                    PentadText {
                        anchors.verticalCenter: parent.verticalCenter
                        x: box.x + box.width + 10
                        width: parent.width - x - 8
                        text: row.modelData.name
                        elide: Text.ElideRight
                    }
                    MouseArea {
                        id: rowArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.toggle(row.modelData.id)
                    }
                }
            }
        }

        Item {
            width: parent.width
            height: 8
        }

        ScreenshotIconButton {
            id: searchButton
            width: parent.width
            enabled: root.chosen.length > 0
            emphasized: enabled
            text: root.services.text('Шукати', 'Search')
            iconSource: Qt.resolvedUrl('../../assets/icons/material/media/search-symbolic.svg')
            onClicked: root.searchRequested(root.chosen)
        }
    }
}
