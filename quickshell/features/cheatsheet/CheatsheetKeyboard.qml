pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls.Basic
import qs.components
import qs.theme
import '../../logic/keyboard-map.mjs' as KeyboardMap
import '../../logic/keybinds.mjs' as KeybindsLogic
import '../../logic/keybind-hues.mjs' as KeybindHues

// The keybind cheatsheet as a drawn 75 % keyboard: a dark case with rounded corners, and in it one
// sculpted keycap (PentadKeycap) per key. The keys bound in one modifier layer carry the hue of
// their bind's group on their top face and legend (neutral when the binds come from several
// groups), free keys are quieter caps, and the layer's modifiers and a key held by the pointer are
// pushed down. The keys grow with the room up to 72 px (logic/keyboard-map.mjs boardMetrics); on
// small keys the action line goes first, then the sculpting. Under the case a legend names the
// groups on it; below that one area names the binds of the hovered or keyboard-current key, or sums
// up the layer; its height is reserved so hovering never moves anything. The host feeds `groups`,
// `mods`, `hueColors`, `superIcon` and `maxHeight`, and decides what modifierToggled() and
// keyActivated() do.
Item {
    id: root
    required property var services
    // The cheatsheet's groups, as CheatsheetView has them before the search.
    property var groups: []
    // The selected modifier layer, as names ('Super', 'Shift').
    property var mods: []
    // { [groupId]: colour } from logic/keybind-hues.mjs.
    property var hueColors: ({})
    // The Super key's logo; '' prints the word.
    property string superIcon: ''
    // The most the whole map (case, legend and detail) may be tall; 0 lets the width alone decide.
    property real maxHeight: 0
    signal modifierToggled(string name)
    signal keyActivated(string label)

    readonly property var heldMods: KeyboardMap.normalizeMods(root.mods)
    readonly property var current: KeyboardMap.layer(root.groups, root.heldMods, root.tr)
    readonly property var legend: KeybindHues.legendGroups(root.groups, root.current.keys)

    readonly property int captionLine: Math.ceil(captionMetrics.height)
    readonly property int lineBox: Math.ceil(bodyMetrics.height)
    // Two lines: two binds, or one and "+N" (the key itself shows "×N"). The space stays empty at
    // rest under the one-line summary, so it is kept small.
    readonly property int detailMax: 2
    readonly property int detailHeight: root.detailMax * root.lineBox + (root.detailMax - 1) * Metrics.space1
    // What sits under the case, kept out of the room for the keys: the legend's line and the detail.
    readonly property int footHeight: Metrics.space3 + root.captionLine + Metrics.space2 + root.detailHeight
    // The board for the room: key unit, gaps and the case's padding.
    readonly property var board: KeyboardMap.boardMetrics(root.width, root.maxHeight > 0 ? Math.max(1, root.maxHeight - root.footHeight) : 0)
    readonly property int unit: root.board.unit
    readonly property int gap: root.board.gap
    readonly property int pitch: root.board.pitch
    // The function row stands about a quarter key apart from the main block, as on a real board.
    readonly property int functionGap: root.board.functionGap
    readonly property int casePad: root.board.pad
    readonly property int boardWidth: root.board.boardWidth
    readonly property int boardHeight: root.board.boardHeight
    // The keycap's anatomy grows with the key: the front lip, and the side walls around the top
    // face. Small keys drop the walls and keep a plain lip.
    readonly property int inset: root.unit >= 40 ? Math.round(root.unit * 0.1) : 0
    readonly property int lip: root.unit >= 40 ? Math.round(root.unit * 0.16) : 3
    readonly property int topInset: root.inset > 0 ? Math.max(1, Math.round(root.inset / 2)) : 0
    readonly property int faceWidthLoss: 2 * root.inset
    readonly property int faceHeight: root.unit - root.topInset - root.lip
    readonly property int keyRadius: root.inset > 0 ? Metrics.radiusMedium : Metrics.radiusSmall
    // Legends grow with the key: the section size on large keys, the body size on medium ones.
    readonly property string legendRole: root.unit >= 60 ? 'section' : root.unit >= 44 ? 'body' : 'caption'
    readonly property int legendSize: root.unit >= 60 ? Metrics.textSection : root.unit >= 44 ? Metrics.textBody : Metrics.textCaption
    readonly property int keyPad: root.unit >= 56 ? Metrics.space2 : Metrics.space1
    // Keys whose face has room for the legend and an action line under it put the legend in the
    // corner; smaller ones centre it alone.
    readonly property bool roomy: root.faceHeight >= root.legendSize + Metrics.textCaption + 2 * root.keyPad + Metrics.space1
    readonly property int logoSize: root.legendSize + Metrics.space1

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

    readonly property bool dark: Theme.config.appearance === 'dark'
    // The case: a tray darker than the card that the keys sit in. Its rim catches the light; inside,
    // the top lies in the rim's shade and the floor brightens toward the front.
    readonly property color caseTone: Qt.darker(Theme.tokens.surface, root.dark ? 1.5 : 1.12)
    readonly property color caseRim: root.dark ? Qt.tint(root.caseTone, Qt.alpha(Theme.tokens.text, 0.12)) : Qt.lighter(root.caseTone, 1.08)
    readonly property color caseShade: Qt.darker(root.caseTone, root.dark ? 1.4 : 1.06)

    objectName: 'cheatsheet-keyboard'
    implicitWidth: KeyboardMap.boardMetrics(100000).width
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
    // A key's legend for its room: the name at the legend size, else the key's short name, else
    // either at the caption size, as keyboards print long names smaller; a small legend may run on
    // to the face's right edge (`wide`). { text, small }.
    function legendFor(label, shortLabel, room, wide) {
        const fits = (metrics, text, space) => text !== '' && Math.ceil(metrics.advanceWidth(text)) <= space;
        if (fits(legendMetrics, label, room))
            return { text: label, small: false };
        if (fits(legendMetrics, shortLabel, room))
            return { text: shortLabel, small: false };
        if (fits(captionMetrics, label, wide))
            return { text: label, small: true };
        return { text: shortLabel !== '' ? shortLabel : label, small: true };
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
    FontMetrics {
        id: legendMetrics
        font.family: Theme.tokens.fontFamily
        font.pixelSize: root.legendSize
        font.weight: Font.DemiBold
    }

    Rectangle {
        id: keyboardCase
        objectName: 'cheatsheet-keyboard-case'
        x: Math.max(0, Math.floor((root.width - width) / 2))
        width: root.boardWidth + 2 * root.casePad
        height: root.boardHeight + 2 * root.casePad
        // Concentric with the keys inside it.
        radius: root.keyRadius + root.casePad
        gradient: Gradient {
            GradientStop {
                position: 0
                color: root.caseRim
            }
            GradientStop {
                position: Math.min(1, 2 / Math.max(1, keyboardCase.height))
                color: root.caseShade
            }
            GradientStop {
                position: Math.min(1, root.casePad / Math.max(1, keyboardCase.height))
                color: root.caseTone
            }
            GradientStop {
                position: 1
                color: Qt.lighter(root.caseTone, root.dark ? 1.25 : 1.02)
            }
        }
    }

    // One tab stop for the whole board. A Control, so the ring shows for keyboard focus only;
    // arrows inside it count as keyboard too, as in PentadSegmented.
    Control {
        id: map
        property string cursorId: ''
        property bool keyboardEngaged: false
        readonly property bool ringVisible: map.activeFocus && (map.visualFocus || map.keyboardEngaged) && map.cursorId !== ''

        objectName: 'cheatsheet-keyboard-map'
        x: keyboardCase.x + root.casePad
        y: keyboardCase.y + root.casePad
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
                // Pushed down while held or under the pointer's press, raised when bound, else a quiet cap.
                readonly property string look: keyItem.held || tap.pressed ? 'pressed' : keyItem.bound ? 'raised' : 'quiet'
                readonly property real pad: root.roomy ? root.keyPad : 0
                readonly property real faceWidth: Math.max(0, keyItem.width - root.faceWidthLoss)
                // A corner legend keeps the padding; a centred one may use the face's width.
                readonly property real legendRoom: Math.max(0, keyItem.faceWidth - (root.roomy ? 2 * keyItem.pad : 0))
                readonly property real smallRoom: Math.max(0, keyItem.faceWidth - (root.roomy ? keyItem.pad + 1 : 0))
                readonly property string label: keyItem.modelData.label
                readonly property string shortLabel: keyItem.modelData.short ? keyItem.modelData.short : ''
                readonly property var legendFit: root.legendFor(keyItem.label, keyItem.shortLabel, keyItem.legendRoom, keyItem.smallRoom)
                // The Super key shows the chosen logo in place of its word.
                readonly property bool logo: keyItem.keyId === 'super' && root.superIcon !== ''
                readonly property real secondRoom: Math.max(0, keyItem.faceWidth - 2 * root.keyPad)
                readonly property bool showDescription: root.roomy && keyItem.count === 1 && keyItem.secondRoom >= 3 * Metrics.textCaption
                readonly property bool showCount: root.roomy && keyItem.count > 1
                // A free key is quiet until it is lit; a held modifier reads in full ink.
                readonly property color legendColor: keyItem.lit && keyItem.look === 'quiet' ? Theme.tokens.text : cap.ink

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
                    inset: root.inset
                    lifted: keyItem.lit
                    hue: keyItem.hue
                    hueTint: KeybindHues.MAP_FACE_TINT
                    hueInk: Qt.tint(keyItem.hue, Qt.alpha(Theme.tokens.text, KeybindHues.MAP_INK_LIFT))
                    base: root.caseTone
                    stateLayer: keyItem.lit && !tap.pressed ? Metrics.stateHover : 0
                    // The legends sit on the face, so they sink with it when the key is pressed.
                    PentadText {
                        objectName: 'cheatsheet-keyboard-legend-text'
                        visible: !keyItem.logo
                        x: root.roomy ? keyItem.pad : Math.round((cap.face.width - width) / 2)
                        y: root.roomy ? keyItem.pad : Math.round((cap.face.height - height) / 2)
                        width: keyItem.legendFit.small ? keyItem.smallRoom : keyItem.legendRoom
                        horizontalAlignment: root.roomy ? Text.AlignLeft : Text.AlignHCenter
                        text: keyItem.legendFit.text
                        textFormat: Text.PlainText
                        role: keyItem.legendFit.small ? 'caption' : root.legendRole
                        solid: true
                        color: keyItem.legendColor
                        font.weight: keyItem.held || cap.tinted ? Font.DemiBold : keyItem.bound ? Font.Medium : Font.Normal
                        wrapMode: Text.NoWrap
                        elide: Text.ElideRight
                        maximumLineCount: 1
                        Accessible.ignored: true
                    }
                    Loader {
                        objectName: 'cheatsheet-keyboard-logo'
                        active: keyItem.logo
                        x: root.roomy ? keyItem.pad : Math.round((cap.face.width - root.logoSize) / 2)
                        y: root.roomy ? keyItem.pad + Math.round((root.legendSize - root.logoSize) / 2) : Math.round((cap.face.height - root.logoSize) / 2)
                        width: root.logoSize
                        height: root.logoSize
                        sourceComponent: PentadIcon {
                            source: root.superIcon
                            pixelSize: root.logoSize
                            color: keyItem.legendColor
                        }
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
                        // The action in the key's own ink, quieter than its legend.
                        color: cap.tinted ? Qt.alpha(cap.ink, 0.78) : Theme.tokens.textMuted
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
            radius: root.keyRadius
            color: 'transparent'
            border.width: 2
            border.color: Theme.tokens.accent
        }
    }

    // The colour key: a dot in its hue and the name of each group that has a key in this layer.
    Flow {
        id: legendRow
        objectName: 'cheatsheet-keyboard-legend'
        x: keyboardCase.x + Metrics.space1
        y: keyboardCase.y + keyboardCase.height + Metrics.space3
        width: Math.max(0, keyboardCase.width - 2 * Metrics.space1)
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
        x: legendRow.x
        y: legendRow.visible ? legendRow.y + legendRow.height + Metrics.space2 : keyboardCase.y + keyboardCase.height + Metrics.space3
        width: legendRow.width
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
