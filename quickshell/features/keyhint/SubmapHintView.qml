pragma ComponentBehavior: Bound
import QtQuick
import qs.components
import qs.theme
import '../../logic/keybind-hints.mjs' as KeybindHints

// The submap hint's content: a muted caption with the active submap's name, "+N" beside it when
// the submap has more binds than fit, then the binds as keycaps and descriptions in one to three
// columns. The binds come from services.keybinds, which reads them when a submap becomes active;
// until they are known, when the read failed or when the submap has none, only the caption shows.
// It is informational: nothing here takes focus or input.
Item {
    id: root
    required property var services
    // The widest the strip may grow; the host passes min(720, output width − 32).
    property real maxWidth: 720
    readonly property var bindState: services.keybinds ? services.keybinds.state : null
    readonly property var groups: bindState && bindState.kind === 'ready' && bindState.value ? bindState.value.groups : []
    readonly property var hint: KeybindHints.submapHint(groups, services.submap ? services.submap.name : '', {
        text: root.tr
    })
    readonly property int sideInset: Metrics.space4
    readonly property int edgeInset: Metrics.space3
    readonly property int columnGap: Metrics.space5
    readonly property int keyGap: Metrics.space3
    readonly property int keycapHeight: 24
    readonly property int minimumColumnWidth: 160
    readonly property real maxBodyWidth: Math.max(0, maxWidth - 2 * sideInset)
    // How many columns of at least minimumColumnWidth the width allows.
    readonly property int fit: Math.max(1, Math.floor((maxBodyWidth + columnGap) / (minimumColumnWidth + columnGap)))
    readonly property var columns: KeybindHints.splitColumns(hint.rows, KeybindHints.columnCount(hint.rows.length, fit))
    // Every column is as wide as the widest one needs, so the descriptions start on one line.
    readonly property real naturalColumnWidth: {
        let widest = 0;
        for (const column of root.columns) {
            let keys = root.keycapHeight;
            let text = 0;
            for (const row of column) {
                keys = Math.max(keys, root.keysWidth(row.keys));
                text = Math.max(text, Math.ceil(bodyMetrics.advanceWidth(row.description)));
            }
            widest = Math.max(widest, keys + root.keyGap + text);
        }
        return widest;
    }
    readonly property real columnWidth: columns.length ? Math.max(0, Math.min(naturalColumnWidth, Math.floor((maxBodyWidth - (columns.length - 1) * columnGap) / columns.length))) : 0
    readonly property real bodyWidth: columns.length ? columns.length * columnWidth + (columns.length - 1) * columnGap : 0
    readonly property alias captionLabel: caption
    readonly property alias overflowLabel: overflow

    implicitWidth: Math.min(maxWidth, 2 * sideInset + Math.max(header.implicitWidth, bodyWidth))
    implicitHeight: columns.length ? body.y + body.implicitHeight + edgeInset : header.y + header.height + edgeInset

    Accessible.role: Accessible.ToolTip
    Accessible.name: hint.title
    Accessible.description: hint.rows.map(function (row) {
        return row.keys.join(' + ') + ': ' + row.description;
    }).join('; ')

    function tr(uk, en) {
        return root.services.text(uk, en);
    }
    // Keycap widths come from the font, as in the cheatsheet.
    function capWidth(label) {
        return Math.max(root.keycapHeight, Math.ceil(capMetrics.advanceWidth(label)) + 2 * Metrics.space2);
    }
    function keysWidth(keys) {
        let width = 0;
        for (const key of keys)
            width += root.capWidth(key);
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

    Item {
        id: header
        x: root.sideInset
        y: root.edgeInset
        width: Math.max(0, root.width - 2 * root.sideInset)
        height: caption.implicitHeight
        implicitWidth: Math.ceil(caption.implicitWidth) + (overflow.visible ? root.keyGap + Math.ceil(overflow.implicitWidth) : 0)
        PentadText {
            id: caption
            objectName: 'submap-hint-caption'
            width: Math.max(0, Math.min(Math.ceil(implicitWidth), header.width - (overflow.visible ? root.keyGap + Math.ceil(overflow.implicitWidth) : 0)))
            text: root.hint.title
            textFormat: Text.PlainText
            role: 'caption'
            font.weight: Font.DemiBold
            color: Theme.tokens.textMuted
            wrapMode: Text.NoWrap
            elide: Text.ElideRight
        }
        PentadText {
            id: overflow
            objectName: 'submap-hint-overflow'
            anchors.right: parent.right
            visible: root.hint.overflow > 0
            text: '+' + root.hint.overflow
            role: 'caption'
            color: Theme.tokens.textMuted
            wrapMode: Text.NoWrap
            Accessible.name: root.tr('Ще ' + root.hint.overflow, root.hint.overflow + ' more')
        }
    }
    Row {
        id: body
        objectName: 'submap-hint-columns'
        x: root.sideInset
        y: header.y + header.height + Metrics.space2
        visible: root.columns.length > 0
        spacing: root.columnGap
        Repeater {
            model: root.columns
            delegate: Column {
                id: column
                required property var modelData
                // The column's widest key combination, at most 55 % of it, so the descriptions line up.
                readonly property real keyWidth: {
                    let widest = root.keycapHeight;
                    for (const row of column.modelData)
                        widest = Math.max(widest, root.keysWidth(row.keys));
                    return Math.min(widest, Math.round(column.width * 0.55));
                }
                objectName: 'submap-hint-column'
                width: root.columnWidth
                spacing: Metrics.space1
                Repeater {
                    model: column.modelData
                    delegate: HintRow {
                        required property var modelData
                        entry: modelData
                        keyWidth: column.keyWidth
                        width: column.width
                    }
                }
            }
        }
    }

    // One bind: its keycaps, then its description; a dispatcher stands in, muted, when the bind
    // has no description. The keycaps are the cheatsheet's sculpted PentadKeycap, standing on the
    // strip's surface.
    component HintRow: Item {
        id: row
        required property var entry
        property real keyWidth: 0
        objectName: 'submap-hint-row'
        implicitHeight: Math.max(caps.height, label.implicitHeight)
        height: implicitHeight
        Flow {
            id: caps
            objectName: 'submap-hint-keys'
            width: row.keyWidth
            spacing: Metrics.space1
            Repeater {
                model: row.entry.keys
                delegate: PentadKeycap {
                    required property string modelData
                    objectName: 'submap-hint-keycap'
                    readonly property string label: modelData
                    width: Math.min(row.keyWidth, root.capWidth(modelData))
                    size: root.keycapHeight
                    text: modelData
                    base: Theme.tokens.surface
                }
            }
        }
        PentadText {
            id: label
            objectName: 'submap-hint-description'
            x: row.keyWidth + root.keyGap
            width: Math.max(0, row.width - label.x)
            // Centred on the keycap's face, above its lip.
            topPadding: Math.max(0, Math.round((root.keycapHeight - 2 - bodyMetrics.height) / 2))
            text: row.entry.description
            textFormat: Text.PlainText
            color: row.entry.described ? Theme.tokens.text : Theme.tokens.textMuted
            wrapMode: Text.NoWrap
            elide: Text.ElideRight
        }
    }
}
