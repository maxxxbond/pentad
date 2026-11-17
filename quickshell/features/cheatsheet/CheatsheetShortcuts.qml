pragma ComponentBehavior: Bound
import QtQuick
import qs.components
import qs.theme

// The "Key shortcuts" strip at the top of the list: a heading, then up to four quiet tiles, each a
// combination set large over its action. The main key takes its group's hue and the "+" between
// keys stays muted, as on the group cards. Which binds it shows is keybinds.mjs keyShortcuts();
// the view shows the strip only in the list view and while no filter is on.
Item {
    id: root
    required property var services
    // keyShortcuts() tiles: [{ keys, description, groupId }].
    property var shortcuts: []
    // { [groupId]: colour } from logic/keybind-hues.mjs.
    property var hueColors: ({})
    readonly property int gap: Metrics.space2
    readonly property int pad: Metrics.space3
    // One row of tiles on a card that has room for two group columns, two per row below that.
    readonly property int columns: root.width >= 560 ? Math.max(1, root.shortcuts.length) : 2
    readonly property real tileWidth: Math.max(0, Math.floor((root.width - (root.columns - 1) * root.gap) / root.columns))
    // Every tile sets its combination at the title size when all of them fit, else at the section size.
    readonly property bool large: {
        const room = root.tileWidth - 2 * root.pad;
        for (const tile of root.shortcuts) {
            if (root.comboWidth(tile.keys, largeMetrics, largePlusMetrics) > room)
                return false;
        }
        return true;
    }
    readonly property alias title: heading

    objectName: 'cheatsheet-shortcuts'
    implicitHeight: grid.y + grid.height

    function tr(uk, en) {
        return root.services.text(uk, en);
    }
    function comboWidth(keys, keyMetrics, plusMetrics) {
        let width = 0;
        for (const key of keys)
            width += Math.ceil(keyMetrics.advanceWidth(key));
        return width + Math.max(0, keys.length - 1) * (Math.ceil(plusMetrics.advanceWidth('+')) + 2 * Metrics.space1);
    }
    function hueOf(id) {
        const color = root.hueColors[id];
        return color ? color : 'transparent';
    }

    FontMetrics {
        id: largeMetrics
        font.family: Theme.tokens.fontFamily
        font.pixelSize: Metrics.textTitle
        font.weight: Font.Bold
    }
    FontMetrics {
        id: largePlusMetrics
        font.family: Theme.tokens.fontFamily
        font.pixelSize: Metrics.textTitle
        font.weight: Font.Medium
    }

    PentadText {
        id: heading
        objectName: 'cheatsheet-shortcuts-title'
        width: root.width
        text: root.tr('Ключові', 'Key shortcuts')
        role: 'section'
        font.weight: Font.DemiBold
        wrapMode: Text.NoWrap
        elide: Text.ElideRight
        Accessible.role: Accessible.Heading
    }
    Grid {
        id: grid
        y: heading.implicitHeight + Metrics.space2
        columns: root.columns
        spacing: root.gap
        Repeater {
            model: root.shortcuts
            delegate: Item {
                id: tile
                required property var modelData
                readonly property string combo: tile.modelData.keys.join('+')
                readonly property string action: tile.modelData.description
                readonly property color hue: root.hueOf(tile.modelData.groupId)
                objectName: 'cheatsheet-shortcut'
                width: root.tileWidth
                height: lines.implicitHeight + 2 * root.pad
                Accessible.role: Accessible.StaticText
                Accessible.name: tile.modelData.keys.join(' + ') + ': ' + tile.action

                ContinuousSurface {
                    anchors.fill: parent
                    fill: tile.hue.a > 0 ? Qt.tint(Theme.tokens.surfaceRaised, Qt.alpha(tile.hue, 0.06)) : Theme.tokens.surfaceRaised
                    extent: Metrics.radiusCard
                    clipContent: false
                }
                // The combination over the action, told apart by size and colour. The large line's
                // descenders (the p of Super) need a little room above the caption.
                Column {
                    id: lines
                    spacing: Metrics.space1
                    x: root.pad
                    y: root.pad
                    width: tile.width - 2 * root.pad
                    // Only a combination too wide even at the section size reaches the edge.
                    clip: true
                    Row {
                        objectName: 'cheatsheet-shortcut-keys'
                        spacing: Metrics.space1
                        Repeater {
                            model: tile.modelData.keys
                            delegate: Row {
                                id: part
                                required property string modelData
                                required property int index
                                spacing: Metrics.space1
                                PentadText {
                                    visible: part.index > 0
                                    text: '+'
                                    textFormat: Text.PlainText
                                    role: root.large ? 'title' : 'section'
                                    solid: true
                                    font.weight: Font.Medium
                                    color: Theme.tokens.textMuted
                                    Accessible.ignored: true
                                }
                                PentadText {
                                    text: part.modelData
                                    textFormat: Text.PlainText
                                    role: root.large ? 'title' : 'section'
                                    solid: true
                                    font.weight: Font.Bold
                                    color: part.index === tile.modelData.keys.length - 1 && tile.hue.a > 0 ? tile.hue : Theme.tokens.text
                                    wrapMode: Text.NoWrap
                                    Accessible.ignored: true
                                }
                            }
                        }
                    }
                    PentadText {
                        width: lines.width
                        text: tile.action
                        textFormat: Text.PlainText
                        role: 'caption'
                        color: Theme.tokens.textMuted
                        wrapMode: Text.NoWrap
                        elide: Text.ElideRight
                        Accessible.ignored: true
                    }
                }
            }
        }
    }
}
