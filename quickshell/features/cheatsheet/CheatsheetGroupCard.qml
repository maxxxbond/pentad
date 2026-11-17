pragma ComponentBehavior: Bound
import QtQuick
import qs.components
import qs.theme
import '../../logic/keybinds.mjs' as KeybindsLogic

// One group of the keybind cheatsheet as a quiet card, faintly tinted with the group's hue: the
// heading set in the hue, then one row per bind that reads like a line of a contents page: the
// keycaps on the left, a dotted leader, the action on the right. The last keycap of a row, the
// main key, carries the hue. A long action elides; a narrow row drops the leader first. A bind
// whose trigger also fires another action ends in a muted mark. The card's radius is radiusCard,
// so with its padding the keycaps inside (radiusSmall) stay concentric with it.
Item {
    id: block
    required property var services
    required property var group
    // The group's colour from logic/keybind-hues.mjs; transparent leaves the card neutral.
    property color hue: 'transparent'
    property int keycapHeight: 24
    readonly property int pad: Metrics.space2
    readonly property real innerWidth: Math.max(0, block.width - 2 * block.pad)
    // The keycaps of a row take at most 55 % of it; a longer combination wraps inside that.
    readonly property real keyLimit: Math.round(block.innerWidth * 0.55)
    readonly property bool hued: block.hue.a > 0
    readonly property color cardTone: block.hued ? Qt.tint(Theme.tokens.surfaceRaised, Qt.alpha(block.hue, 0.06)) : Theme.tokens.surfaceRaised
    // The keycap's face, without its lip: descriptions and marks centre on it.
    readonly property int faceHeight: block.keycapHeight - 2
    // Leader dots stand on one grid across the card, so the dots of neighbouring rows line up.
    readonly property int leaderPitch: 6
    readonly property real dotAdvance: bodyMetrics.advanceWidth('.')

    objectName: 'cheatsheet-group-' + block.group.id
    implicitHeight: content.implicitHeight + 2 * block.pad
    height: implicitHeight

    function tr(uk, en) {
        return block.services.text(uk, en);
    }
    // Keycap widths come from the font, so a row knows where its keycaps end before they exist.
    function capWidth(label) {
        return Math.max(block.keycapHeight, Math.ceil(capMetrics.advanceWidth(label)) + 2 * Metrics.space2);
    }
    function keysWidth(keys) {
        let width = 0;
        for (const key of keys)
            width += block.capWidth(key);
        return width + Math.max(0, keys.length - 1) * Metrics.space1;
    }

    FontMetrics {
        id: capMetrics
        font.family: Theme.tokens.fontFamily
        font.pixelSize: Metrics.textCaption
        font.weight: Font.Medium
    }
    FontMetrics {
        id: bodyMetrics
        font.family: Theme.tokens.fontFamily
        font.pixelSize: Metrics.textBody
    }

    ContinuousSurface {
        objectName: 'cheatsheet-card-fill'
        anchors.fill: parent
        fill: block.cardTone
        extent: Metrics.radiusCard
        clipContent: false
    }
    Column {
        id: content
        x: block.pad
        y: block.pad
        width: block.innerWidth
        spacing: Metrics.space1
        PentadText {
            objectName: 'cheatsheet-group-title'
            width: content.width
            text: KeybindsLogic.labelFor(block.group, block.tr)
            role: 'section'
            font.weight: Font.DemiBold
            color: block.hued ? block.hue : Theme.tokens.text
            wrapMode: Text.NoWrap
            elide: Text.ElideRight
            bottomPadding: Metrics.space1
        }
        Repeater {
            model: block.group.binds
            delegate: BindRow {
                required property var modelData
                bind: modelData
                width: content.width
            }
        }
    }

    component BindRow: Item {
        id: row
        required property var bind
        readonly property bool duplicate: row.bind.duplicate === true
        readonly property real markWidth: row.duplicate ? Metrics.panelIcon + Metrics.space2 : 0
        readonly property real capsWidth: Math.min(block.keysWidth(row.bind.keys), block.keyLimit)
        readonly property real actionRoom: Math.max(0, row.width - row.markWidth - row.capsWidth - Metrics.space3)
        readonly property real actionWidth: Math.min(Math.ceil(actionLabel.implicitWidth), row.actionRoom)
        objectName: 'cheatsheet-row'
        implicitHeight: Math.max(caps.height, actionLabel.implicitHeight)
        height: implicitHeight
        Flow {
            id: caps
            objectName: 'cheatsheet-keys'
            width: block.keyLimit
            spacing: Metrics.space1
            Repeater {
                model: row.bind.keys
                delegate: PentadKeycap {
                    required property string modelData
                    required property int index
                    objectName: 'cheatsheet-keycap'
                    readonly property string label: modelData
                    readonly property bool main: index === row.bind.keys.length - 1
                    width: Math.min(block.keyLimit, block.capWidth(modelData))
                    size: block.keycapHeight
                    text: modelData
                    hue: main ? block.hue : 'transparent'
                    base: block.cardTone
                }
            }
        }
        // A quiet leader from the keycaps to the action: one line of dots, as long as the room and
        // ending a gap before the action. Fewer than four dots would read as an ellipsis, so a short
        // room shows none.
        PentadText {
            id: leader
            objectName: 'cheatsheet-leader'
            readonly property real start: Math.ceil((row.capsWidth + Metrics.space2) / block.leaderPitch) * block.leaderPitch
            readonly property int dots: Math.max(0, Math.floor((actionLabel.x - Metrics.space2 - leader.start - block.dotAdvance) / block.leaderPitch) + 1)
            visible: leader.dots >= 4
            x: leader.start
            anchors.baseline: actionLabel.baseline
            text: leader.visible ? '.'.repeat(leader.dots) : ''
            textFormat: Text.PlainText
            color: Qt.alpha(Theme.tokens.textMuted, 0.55)
            font.letterSpacing: block.leaderPitch - block.dotAdvance
            wrapMode: Text.NoWrap
            Accessible.ignored: true
        }
        PentadText {
            id: actionLabel
            objectName: 'cheatsheet-description'
            x: row.width - row.markWidth - row.actionWidth
            width: row.actionWidth
            topPadding: Math.max(0, Math.round((block.faceHeight - bodyMetrics.height) / 2))
            text: row.bind.lua && !row.bind.described ? block.tr('Функція Lua без опису', 'Lua function without a description') : row.bind.description
            textFormat: Text.PlainText
            color: row.bind.described ? Theme.tokens.text : Theme.tokens.textMuted
            horizontalAlignment: Text.AlignRight
            wrapMode: Text.NoWrap
            maximumLineCount: 1
            elide: Text.ElideRight
            // An elided action reads in full on hover; only elided rows create the hint.
            Loader {
                active: actionLabel.truncated
                anchors.fill: parent
                sourceComponent: Item {
                    HoverHandler {
                        id: fullHover
                    }
                    PentadHint {
                        text: actionLabel.text
                        shown: fullHover.hovered
                    }
                }
            }
        }
        // The same keys also do something else: a quiet mark, named for assistive tech and on hover.
        // Only duplicate rows create it.
        Loader {
            active: row.duplicate
            x: row.width - Metrics.panelIcon
            y: Math.round((block.faceHeight - Metrics.panelIcon) / 2)
            width: Metrics.panelIcon
            height: Metrics.panelIcon
            sourceComponent: PentadIcon {
                id: mark
                objectName: 'cheatsheet-duplicate'
                source: Qt.resolvedUrl('../../assets/icons/material/screenshot/content-copy-symbolic.svg')
                pixelSize: Metrics.panelIcon
                color: Theme.tokens.textMuted
                accessibleName: block.tr('Ці клавіші мають ще одну дію', 'These keys also do something else')
                HoverHandler {
                    id: markHover
                }
                PentadHint {
                    text: mark.accessibleName
                    shown: markHover.hovered
                }
            }
        }
    }
}
