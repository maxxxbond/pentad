pragma ComponentBehavior: Bound
import QtQuick
import qs.components
import qs.theme
import '../../logic/keybinds.mjs' as KeybindsLogic

// One group of the keybind cheatsheet as a quiet card: a raised fill with its heading inside, then
// a row per bind with the keycaps in a column as wide as the group's widest combination (at most
// 55 % of the card) and the description beside them. A bind whose trigger also fires another
// action ends in a muted mark. The card's radius is radiusCard, so with its padding the keycaps
// inside (radiusSmall) stay concentric with it.
Item {
    id: block
    required property var services
    required property var group
    property int keycapHeight: 24
    readonly property int pad: Metrics.space2
    readonly property real innerWidth: Math.max(0, block.width - 2 * block.pad)
    readonly property real keyWidth: {
        let widest = block.keycapHeight;
        for (const bind of block.group.binds)
            widest = Math.max(widest, block.keysWidth(bind.keys));
        return Math.min(widest, Math.round(block.innerWidth * 0.55));
    }

    objectName: 'cheatsheet-group-' + block.group.id
    implicitHeight: content.implicitHeight + 2 * block.pad
    height: implicitHeight

    function tr(uk, en) {
        return block.services.text(uk, en);
    }
    // Keycap widths come from the font, so a group's descriptions can start on one line.
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
        fill: Theme.tokens.surfaceRaised
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
            role: 'caption'
            font.weight: Font.DemiBold
            color: Theme.tokens.textMuted
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
        objectName: 'cheatsheet-row'
        implicitHeight: Math.max(caps.height, label.implicitHeight)
        height: implicitHeight
        Flow {
            id: caps
            objectName: 'cheatsheet-keys'
            width: block.keyWidth
            spacing: Metrics.space1
            Repeater {
                model: row.bind.keys
                delegate: Rectangle {
                    id: cap
                    required property string modelData
                    objectName: 'cheatsheet-keycap'
                    readonly property string label: modelData
                    width: Math.min(block.keyWidth, block.capWidth(modelData))
                    height: Math.max(block.keycapHeight, capLabel.implicitHeight + Metrics.space2)
                    radius: Metrics.radiusSmall
                    // One step above the card, so the caps read on it in both themes.
                    color: Theme.tokens.surfaceOverlay
                    PentadText {
                        id: capLabel
                        anchors.centerIn: cap
                        // The laid-out text runs a little wider than FontMetrics measures; the
                        // slack keeps a short legend such as "Ctrl" on one line.
                        width: Math.max(0, cap.width - Metrics.space2)
                        horizontalAlignment: Text.AlignHCenter
                        text: cap.modelData
                        textFormat: Text.PlainText
                        role: 'caption'
                        font.weight: Font.Medium
                        wrapMode: Text.WrapAnywhere
                    }
                }
            }
        }
        PentadText {
            id: label
            objectName: 'cheatsheet-description'
            x: block.keyWidth + Metrics.space3
            width: Math.max(0, row.width - label.x - row.markWidth)
            topPadding: Math.max(0, Math.round((block.keycapHeight - bodyMetrics.height) / 2))
            text: row.bind.lua && !row.bind.described ? block.tr('Функція Lua без опису', 'Lua function without a description') : row.bind.description
            textFormat: Text.PlainText
            color: row.bind.described ? Theme.tokens.text : Theme.tokens.textMuted
            maximumLineCount: 3
            elide: Text.ElideRight
        }
        // The same keys also do something else: a quiet mark, named for assistive tech and on hover.
        // Only duplicate rows create it.
        Loader {
            active: row.duplicate
            x: row.width - Metrics.panelIcon
            y: Math.round((block.keycapHeight - Metrics.panelIcon) / 2)
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
