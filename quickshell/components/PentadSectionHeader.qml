import QtQuick
import qs.theme

// The one section header: a muted caption line, an optional count badge after it and optional
// trailing content (a button, a link) on the far side. Callers decide capitalisation; the label
// elides before it pushes the badge or the trailing content out of the header.
Item {
    id: root
    property string text: ""
    // A count of the section's items; -1 hides the badge.
    property int count: -1
    default property alias trailing: trailingRow.data

    readonly property bool hasCount: count >= 0
    readonly property real badgeSpace: hasCount ? Metrics.space2 + badge.width : 0
    readonly property real trailingSpace: trailingRow.implicitWidth > 0 ? Metrics.space3 + trailingRow.implicitWidth : 0

    implicitWidth: Math.ceil(labelMetrics.advanceWidth(text)) + badgeSpace + trailingSpace
    implicitHeight: Math.max(label.implicitHeight, hasCount ? badge.height : 0, trailingRow.implicitHeight)
    // Children follow the header's direction, so a mirrored header puts the trailing content on the left.
    LayoutMirroring.childrenInherit: true
    Accessible.role: Accessible.Heading
    Accessible.name: text
    Accessible.description: hasCount ? String(count) : ""

    FontMetrics {
        id: labelMetrics
        font: label.font
    }

    PentadText {
        id: label
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        width: Math.max(0, Math.min(Math.ceil(labelMetrics.advanceWidth(root.text)), root.width - root.badgeSpace - root.trailingSpace))
        text: root.text
        textFormat: Text.PlainText
        role: "caption"
        color: Theme.tokens.textMuted
        font.weight: Font.Medium
        wrapMode: Text.NoWrap
        elide: Text.ElideRight
        maximumLineCount: 1
        Accessible.ignored: true
    }
    Item {
        id: badge
        visible: root.hasCount
        anchors.left: label.right
        anchors.leftMargin: Metrics.space2
        anchors.verticalCenter: parent.verticalCenter
        height: Metrics.space4
        width: Math.max(height, countLabel.implicitWidth + 2 * Metrics.space1)
        Rectangle {
            anchors.fill: parent
            color: Theme.tokens.surfaceOverlay
            radius: Metrics.radiusPill
        }
        PentadText {
            id: countLabel
            anchors.centerIn: parent
            text: String(root.count)
            textFormat: Text.PlainText
            role: "caption"
            color: Theme.tokens.textMuted
            font.features: ({ tnum: 1 })
            wrapMode: Text.NoWrap
            Accessible.ignored: true
        }
    }
    Row {
        id: trailingRow
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: Metrics.space2
    }
}
