pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls.Basic
import qs.components
import qs.theme
import '../../logic/keyboard-map.mjs' as KeyboardMap

// The keybind cheatsheet as a drawn 75 % keyboard: the keys bound in one modifier layer stand out,
// free keys stay quiet, and the layer's modifiers look held. Below the board one area names the
// binds of the hovered or keyboard-current key, or sums up the layer; its height is reserved so
// hovering never moves anything. The model is logic/keyboard-map.mjs. The host feeds `groups` and
// `mods` and decides what modifierToggled() and keyActivated() do.
Item {
    id: root
    required property var services
    // The cheatsheet's groups, as CheatsheetView has them before the search.
    property var groups: []
    // The selected modifier layer, as names ('Super', 'Shift').
    property var mods: []
    signal modifierToggled(string name)
    signal keyActivated(string label)

    readonly property var heldMods: KeyboardMap.normalizeMods(root.mods)
    readonly property var current: KeyboardMap.layer(root.groups, root.heldMods, root.tr)

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
    readonly property int dotSize: Metrics.space1
    // Keys tall enough for two caption lines put the legend in the corner and a second line under it.
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
    implicitHeight: root.boardHeight + Metrics.space3 + root.detailHeight

    function tr(uk, en) {
        return root.services.text(uk, en);
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
                readonly property real fillLevel: (keyItem.held ? 2 * Metrics.statePressed : keyItem.bound ? Metrics.statePressed : Metrics.stateHover)
                    + (tap.pressed ? Metrics.statePressed : keyItem.lit ? Metrics.stateHover : 0)
                readonly property real pad: root.roomy ? root.keyPad : 0
                // Only keys with the legend in the corner have room for the dot; on small keys it
                // would read as punctuation after a centred legend ("1.").
                readonly property real dotSpace: keyItem.bound && !keyItem.held && root.roomy ? root.dotSize + root.keyPad : 0
                readonly property real legendRoom: Math.max(0, keyItem.width - 2 * keyItem.pad)
                readonly property string label: keyItem.modelData.label
                readonly property string shortLabel: keyItem.modelData.short ? keyItem.modelData.short : ''
                readonly property string legendText: captionMetrics.advanceWidth(keyItem.label) <= keyItem.legendRoom || keyItem.shortLabel === '' ? keyItem.label : keyItem.shortLabel
                readonly property real secondRoom: Math.max(0, keyItem.width - 2 * root.keyPad - keyItem.dotSpace)
                readonly property bool showDescription: root.roomy && keyItem.count === 1 && keyItem.secondRoom >= 3 * Metrics.textCaption
                readonly property bool showCount: root.roomy && keyItem.count > 1

                objectName: 'cheatsheet-keyboard-key'
                x: root.keyLeft(keyItem.modelData)
                y: root.keyTop(keyItem.modelData)
                width: root.keyWidth(keyItem.modelData)
                height: root.unit

                Rectangle {
                    anchors.fill: parent
                    radius: Metrics.radiusSmall
                    color: Qt.alpha(Theme.tokens.text, keyItem.fillLevel)
                    Behavior on color {
                        enabled: !Theme.tokens.reducedMotion
                        ColorAnimation {
                            duration: Motion.short
                            easing.type: Motion.easeStandard
                        }
                    }
                }
                PentadText {
                    x: keyItem.pad
                    y: root.roomy ? root.keyPad : Math.round((keyItem.height - height) / 2)
                    width: keyItem.legendRoom
                    text: keyItem.legendText
                    textFormat: Text.PlainText
                    role: 'caption'
                    // A held modifier is selected: the strongest fill and full ink (the accent would
                    // not read on that fill).
                    color: keyItem.held || keyItem.bound || keyItem.lit ? Theme.tokens.text : Theme.tokens.textMuted
                    font.weight: keyItem.held ? Font.DemiBold : keyItem.bound ? Font.Medium : Font.Normal
                    horizontalAlignment: root.roomy ? Text.AlignLeft : Text.AlignHCenter
                    wrapMode: Text.NoWrap
                    elide: Text.ElideRight
                    maximumLineCount: 1
                    Accessible.ignored: true
                }
                PentadText {
                    visible: keyItem.showDescription || keyItem.showCount
                    x: root.keyPad
                    y: keyItem.height - root.keyPad - height
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
                // The bound mark: a small accent dot in the corner, never a filled key.
                Rectangle {
                    visible: keyItem.dotSpace > 0
                    x: keyItem.width - root.keyPad - width
                    y: keyItem.height - root.keyPad - height
                    width: root.dotSize
                    height: root.dotSize
                    radius: width / 2
                    color: Theme.tokens.accent
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

    // The binds of the active key (group, then description; at most detailMax lines), the key's combo
    // when it is free, or the layer's summary.
    Item {
        id: detail
        objectName: 'cheatsheet-keyboard-detail'
        readonly property string mode: root.detailMode
        x: map.x
        y: map.y + map.height + Metrics.space3
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
                        visible: text !== ''
                        width: Math.min(Math.ceil(implicitWidth), Math.round(line.width * 0.35))
                        text: line.modelData.group
                        textFormat: Text.PlainText
                        color: Theme.tokens.textMuted
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
