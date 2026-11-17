pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls.Basic
import qs.components
import qs.theme
import '../../logic/keyboard-map.mjs' as KeyboardMap
import '../../logic/keybinds.mjs' as KeybindsLogic
import '../../logic/keybind-hues.mjs' as KeybindHues

// The keybind cheatsheet as a drawn 75 % keyboard of sculpted keys (PentadKeycap): the keys bound
// in one modifier layer stand raised in the hue of their bind's group (neutral when the binds come
// from several groups), free keys lie flat and a little sunken, and the layer's modifiers look
// pressed in. Under the board a legend names the groups on it; below that one area names the
// binds of the hovered or keyboard-current key, or sums up the layer; its height is reserved so
// hovering never moves anything. The model is logic/keyboard-map.mjs. The host feeds `groups`,
// `mods` and `hueColors` and decides what modifierToggled() and keyActivated() do.
Item {
    id: root
    required property var services
    // The cheatsheet's groups, as CheatsheetView has them before the search.
    property var groups: []
    // The selected modifier layer, as names ('Super', 'Shift').
    property var mods: []
    // { [groupId]: colour } from logic/keybind-hues.mjs.
    property var hueColors: ({})
    signal modifierToggled(string name)
    signal keyActivated(string label)

    readonly property var heldMods: KeyboardMap.normalizeMods(root.mods)
    readonly property var current: KeyboardMap.layer(root.groups, root.heldMods, root.tr)
    readonly property var legend: KeybindHues.legendGroups(root.groups, root.current.keys)

    // A key unit: the width split into UNITS keys with a gap between them.
    readonly property int gap: Metrics.space1
    readonly property int pitch: Math.max(0, Math.floor((root.width + root.gap) / KeyboardMap.UNITS))
    readonly property int unit: Math.max(0, root.pitch - root.gap)
    // The function row stands one more gap apart from the main block, as on a real board.
    readonly property int functionGap: root.gap
    readonly property int boardWidth: Math.max(0, KeyboardMap.UNITS * root.pitch - root.gap)
    readonly property int boardHeight: Math.max(0, KeyboardMap.LAYOUT.length * root.pitch - root.gap + root.functionGap)
    readonly property int captionLine: Math.ceil(captionMetrics.height)
    readonly property int lineBox: Math.ceil(bodyMetrics.height)
    readonly property int keyPad: Metrics.space1
    // A raised key's lip, inside the key's cell: a little taller than on the list's keycaps.
    readonly property int lip: 3
    // Keys tall enough for two caption lines put the legend in the corner and a second line under it
    // (the second line is solid, so the lip still leaves room for both).
    readonly property bool roomy: root.unit >= 2 * root.captionLine + 3 * root.keyPad
    // Two lines: two binds, or one and "+N" (the key itself shows "×N"). The space stays empty at
    // rest under the one-line summary, so it is kept small.
    readonly property int detailMax: 2
    readonly property int detailHeight: root.detailMax * root.lineBox + (root.detailMax - 1) * Metrics.space1

    // The hovered key, else the keyboard cursor while the map has focus; the latest input wins.
    property string hoverId: ''
    readonly property string activeId: root.hoverId !== '' ? root.hoverId : map.activeFocus ? map.cursorId : ''
    readonly property var activeKey: KeyboardMap.keyById(root.activeId)
    readonly property var activeBinds: root.activeKey ? root.bindsFor(root.activeId) : []
    readonly property bool activeHeld: !!root.activeKey && !!root.activeKey.mod && root.heldMods.indexOf(root.activeKey.mod) >= 0
    readonly property string detailMode: !root.activeKey || root.activeHeld ? 'summary' : root.activeBinds.length ? 'binds' : 'free'
    readonly property var detailRows: KeyboardMap.detailLines(root.activeBinds, root.detailMax)
    readonly property string activeCombo: root.activeKey ? KeyboardMap.comboLabel(root.heldMods, root.activeKey.label) : ''
    readonly property string summary: root.current.bound === 0 && root.current.unplaced === 0
        ? root.tr('Нічого не прив’язано', 'Nothing is bound')
        : root.tr('Прив’язано: ' + root.current.bound, root.current.bound + ' bound')
            + (root.current.unplaced > 0 ? ' · ' + root.tr('поза клавіатурою: ' + root.current.unplaced, root.current.unplaced + ' not on the keyboard') : '')
    readonly property string freeText: root.tr(root.activeCombo + ' — вільна', root.activeCombo + ' is free')
    readonly property string activeDescription: root.detailMode === 'binds'
        ? root.activeCombo + ': ' + root.activeBinds.map(function(bind) { return root.bindText(bind); }).join('; ')
        : root.detailMode === 'free' ? root.freeText : root.summary

    objectName: 'cheatsheet-keyboard'
    implicitWidth: KeyboardMap.UNITS * (Metrics.controlLarge + root.gap) - root.gap
    implicitHeight: detail.y + root.detailHeight

    function tr(uk, en) {
        return root.services.text(uk, en);
    }
    function hueOf(id) {
        const color = id ? root.hueColors[id] : '';
        return color ? color : 'transparent';
    }
    function bindsFor(id) {
        const list = root.current.keys[KeyboardMap.bindId(id)];
        return list ? list : [];
    }
    function bindText(bind) {
        return bind.lua && !bind.described ? root.tr('Функція Lua без опису', 'Lua function without a description') : bind.description;
    }
    function keyLeft(entry) {
        return Math.round(entry.x * root.pitch);
    }
    function keyTop(entry) {
        return entry.row * root.pitch + (entry.row > 0 ? root.functionGap : 0);
    }
    function keyWidth(entry) {
        return Math.max(0, Math.round((entry.x + entry.w) * root.pitch) - root.gap - root.keyLeft(entry));
    }
    // A click or Enter: a modifier key toggles its layer, a bound key is handed to the host with
    // the label its binds use (a sheet may write 'Del' for the Delete key), a free key does nothing.
    function activate(id) {
        const entry = KeyboardMap.keyById(id);
        if (!entry)
            return;
        const binds = root.bindsFor(id);
        if (entry.mod)
            root.modifierToggled(entry.mod);
        else if (binds.length)
            root.keyActivated(binds[0].label || entry.label);
    }

    FontMetrics {
        id: captionMetrics
        font.family: Theme.tokens.fontFamily
        font.pixelSize: Metrics.textCaption
        font.weight: Font.Medium
    }
    FontMetrics {
        id: bodyMetrics
        font.family: Theme.tokens.fontFamily
        font.pixelSize: Metrics.textBody
    }

    // One tab stop for the whole board. A Control, so the ring shows for keyboard focus only;
    // arrows inside it count as keyboard too, as in PentadSegmented.
    Control {
        id: map
        property string cursorId: ''
        property bool keyboardEngaged: false
        readonly property bool ringVisible: map.activeFocus && (map.visualFocus || map.keyboardEngaged) && map.cursorId !== ''

        objectName: 'cheatsheet-keyboard-map'
        x: Math.max(0, Math.floor((root.width - root.boardWidth) / 2))
        width: root.boardWidth
        height: root.boardHeight
        padding: 0
        activeFocusOnTab: true
        Accessible.role: Accessible.Grouping
        Accessible.name: root.tr('Мапа клавіш', 'Key map')
        Accessible.description: root.activeDescription

        onActiveFocusChanged: {
            if (!activeFocus)
                map.keyboardEngaged = false;
            else if (map.cursorId === '')
                map.cursorId = KeyboardMap.firstKey(root.current.keys);
        }

        // Arrows move the cursor, Enter and Space press the current key; everything else (Esc,
        // Tab, typing, shortcuts) goes on to the host.
        Keys.onPressed: function (event) {
            if (event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier))
                return;
            const from = map.cursorId !== '' ? map.cursorId : KeyboardMap.firstKey(root.current.keys);
            const direction = event.key === Qt.Key_Left ? 'left' : event.key === Qt.Key_Right ? 'right'
                : event.key === Qt.Key_Up ? 'up' : event.key === Qt.Key_Down ? 'down' : '';
            if (direction !== '') {
                map.cursorId = KeyboardMap.neighbor(from, direction);
                root.hoverId = '';
            } else if (event.key === Qt.Key_Space || event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                map.cursorId = from;
                root.activate(from);
            } else {
                return;
            }
            map.keyboardEngaged = true;
            event.accepted = true;
        }

        Repeater {
            model: KeyboardMap.KEYS
            delegate: Item {
                id: keyItem
                required property var modelData
                readonly property string keyId: keyItem.modelData.id
                readonly property var binds: root.bindsFor(keyItem.keyId)
                readonly property int count: keyItem.binds.length
                readonly property bool bound: keyItem.count > 0
                readonly property string mod: keyItem.modelData.mod ? keyItem.modelData.mod : ''
                readonly property bool held: keyItem.mod !== '' && root.heldMods.indexOf(keyItem.mod) >= 0
                readonly property bool interactive: keyItem.mod !== '' || keyItem.bound
                readonly property bool lit: keyItem.interactive && (hover.hovered || root.activeId === keyItem.keyId)
                // The group the key's binds share; binds from several groups leave the key neutral.
                readonly property string groupId: keyItem.bound ? KeybindHues.sharedGroup(keyItem.binds) : ''
                readonly property color hue: root.hueOf(keyItem.groupId)
                // Raised when bound, pressed in while held or under the pointer's press, else flat.
                readonly property string look: keyItem.held || tap.pressed ? 'pressed' : keyItem.bound ? 'raised' : 'flat'
                readonly property real pad: root.roomy ? root.keyPad : 0
                readonly property real legendRoom: Math.max(0, keyItem.width - 2 * keyItem.pad)
                readonly property string label: keyItem.modelData.label
                readonly property string shortLabel: keyItem.modelData.short ? keyItem.modelData.short : ''
                readonly property string legendText: captionMetrics.advanceWidth(keyItem.label) <= keyItem.legendRoom || keyItem.shortLabel === '' ? keyItem.label : keyItem.shortLabel
                readonly property real secondRoom: Math.max(0, keyItem.width - 2 * root.keyPad)
                readonly property bool showDescription: root.roomy && keyItem.count === 1 && keyItem.secondRoom >= 3 * Metrics.textCaption
                readonly property bool showCount: root.roomy && keyItem.count > 1

                objectName: 'cheatsheet-keyboard-key'
                x: root.keyLeft(keyItem.modelData)
                y: root.keyTop(keyItem.modelData)
                width: root.keyWidth(keyItem.modelData)
                height: root.unit

                PentadKeycap {
                    id: cap
                    objectName: 'cheatsheet-keyboard-cap'
                    anchors.fill: parent
                    look: keyItem.look
                    lip: root.lip
                    hue: keyItem.hue
                    base: Theme.tokens.surfaceRaised
                    stateLayer: keyItem.lit && !tap.pressed ? Metrics.stateHover : 0
                    // The legends sit on the face, so they sink with it when the key is pressed.
                    PentadText {
                        x: keyItem.pad
                        y: root.roomy ? root.keyPad : Math.round((cap.face.height - height) / 2)
                        width: keyItem.legendRoom
                        text: keyItem.legendText
                        textFormat: Text.PlainText
                        role: 'caption'
                        // A free key is quiet until it is lit; a held modifier reads in full ink.
                        color: keyItem.lit && keyItem.look === 'flat' ? Theme.tokens.text : cap.ink
                        font.weight: keyItem.held || cap.tinted ? Font.DemiBold : keyItem.bound ? Font.Medium : Font.Normal
                        horizontalAlignment: root.roomy ? Text.AlignLeft : Text.AlignHCenter
                        wrapMode: Text.NoWrap
                        elide: Text.ElideRight
                        maximumLineCount: 1
                        Accessible.ignored: true
                    }
                    PentadText {
                        visible: keyItem.showDescription || keyItem.showCount
                        x: root.keyPad
                        y: cap.face.height - root.keyPad - height
                        width: keyItem.secondRoom
                        text: keyItem.showCount ? '×' + keyItem.count : keyItem.showDescription ? root.bindText(keyItem.binds[0]) : ''
                        textFormat: Text.PlainText
                        role: 'caption'
                        solid: true
                        color: Theme.tokens.textMuted
                        font.features: ({
                                tnum: 1
                            })
                        wrapMode: Text.NoWrap
                        elide: Text.ElideRight
                        maximumLineCount: 1
                        Accessible.ignored: true
                    }
                }

                HoverHandler {
                    id: hover
                    cursorShape: keyItem.interactive ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onHoveredChanged: {
                        if (hovered)
                            root.hoverId = keyItem.keyId;
                        else if (root.hoverId === keyItem.keyId)
                            root.hoverId = '';
                    }
                }
                TapHandler {
                    id: tap
                    enabled: keyItem.interactive
                    onTapped: {
                        map.cursorId = keyItem.keyId;
                        map.keyboardEngaged = false;
                        root.activate(keyItem.keyId);
                    }
                }
            }
        }

        Rectangle {
            id: ring
            readonly property var entry: KeyboardMap.keyById(map.cursorId)
            objectName: 'cheatsheet-keyboard-ring'
            visible: map.ringVisible && ring.entry !== null
            x: ring.entry ? root.keyLeft(ring.entry) : 0
            y: ring.entry ? root.keyTop(ring.entry) : 0
            width: ring.entry ? root.keyWidth(ring.entry) : 0
            height: root.unit
            radius: Metrics.radiusSmall
            color: 'transparent'
            border.width: 2
            border.color: Theme.tokens.accent
        }
    }

    // The colour key: a dot in its hue and the name of each group that has a key in this layer.
    Flow {
        id: legendRow
        objectName: 'cheatsheet-keyboard-legend'
        x: map.x
        y: map.y + map.height + Metrics.space3
        width: map.width
        visible: root.legend.length > 0
        spacing: Metrics.space1
        Repeater {
            model: root.legend
            delegate: Row {
                id: entry
                required property var modelData
                readonly property string groupId: entry.modelData.id
                readonly property color hue: root.hueOf(entry.modelData.id)
                objectName: 'cheatsheet-keyboard-legend-item'
                height: root.captionLine
                spacing: Metrics.space1
                rightPadding: Metrics.space2
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: Metrics.space2
                    height: width
                    radius: width / 2
                    color: entry.hue.a > 0 ? entry.hue : Theme.tokens.textMuted
                }
                PentadText {
                    objectName: 'cheatsheet-keyboard-legend-name'
                    anchors.verticalCenter: parent.verticalCenter
                    text: KeybindsLogic.labelFor(entry.modelData.group, root.tr)
                    textFormat: Text.PlainText
                    role: 'caption'
                    color: Theme.tokens.textMuted
                    wrapMode: Text.NoWrap
                }
            }
        }
    }

    // The binds of the active key (group, then description; at most detailMax lines), the key's combo
    // when it is free, or the layer's summary.
    Item {
        id: detail
        objectName: 'cheatsheet-keyboard-detail'
        readonly property string mode: root.detailMode
        x: map.x
        y: legendRow.visible ? legendRow.y + legendRow.height + Metrics.space2 : map.y + map.height + Metrics.space3
        width: map.width
        height: root.detailHeight

        PentadText {
            visible: detail.mode !== 'binds'
            width: detail.width
            text: detail.mode === 'free' ? root.freeText : root.summary
            textFormat: Text.PlainText
            color: Theme.tokens.textMuted
            wrapMode: Text.NoWrap
            elide: Text.ElideRight
            maximumLineCount: 1
        }
        Column {
            visible: detail.mode === 'binds'
            width: detail.width
            spacing: Metrics.space1
            Repeater {
                model: detail.mode === 'binds' ? root.detailRows.binds : []
                delegate: Item {
                    id: line
                    required property var modelData
                    width: detail.width
                    height: root.lineBox
                    PentadText {
                        id: groupLabel
                        readonly property color hue: root.hueOf(line.modelData.groupId)
                        visible: text !== ''
                        width: Math.min(Math.ceil(implicitWidth), Math.round(line.width * 0.35))
                        text: line.modelData.group
                        textFormat: Text.PlainText
                        // The group's name in its hue, as on its card.
                        color: groupLabel.hue.a > 0 ? groupLabel.hue : Theme.tokens.textMuted
                        wrapMode: Text.NoWrap
                        elide: Text.ElideRight
                        maximumLineCount: 1
                    }
                    PentadText {
                        x: groupLabel.visible ? groupLabel.width + Metrics.space2 : 0
                        width: Math.max(0, line.width - x)
                        text: root.bindText(line.modelData)
                        textFormat: Text.PlainText
                        color: line.modelData.described ? Theme.tokens.text : Theme.tokens.textMuted
                        wrapMode: Text.NoWrap
                        elide: Text.ElideRight
                        maximumLineCount: 1
                    }
                }
            }
            PentadText {
                visible: root.detailRows.more > 0
                width: detail.width
                height: root.lineBox
                text: '+' + root.detailRows.more
                textFormat: Text.PlainText
                color: Theme.tokens.textMuted
                font.features: ({
                        tnum: 1
                    })
                wrapMode: Text.NoWrap
            }
        }
    }
}
