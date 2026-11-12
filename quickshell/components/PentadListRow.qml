import QtQuick
import QtQuick.Controls.Basic
import qs.theme

// The one list row: an optional icon, a title over an optional subtitle (a solid stack told apart
// by size and colour, not air) and optional trailing content on the far side. Click, Space and
// Enter emit activated(); a trailing control that takes the press keeps it, so its click does not
// also activate the row. Long text elides inside the row. The fill is a state layer only: nothing
// at rest, the foreground at Metrics.stateHover / statePressed on hover and press.
AbstractButton {
    id: root
    property url iconSource: ""
    property string title: ""
    property string subtitle: ""
    default property alias trailing: trailingRow.data
    signal activated()

    readonly property bool hasIcon: iconSource.toString() !== ""
    readonly property bool hasSubtitle: subtitle !== ""
    readonly property bool hasTrailing: trailingRow.implicitWidth > 0
    readonly property real stackHeight: titleLabel.height + (hasSubtitle ? subtitleLabel.height : 0)
    readonly property real contentHeight: Math.max(stackHeight + 2 * Metrics.space2,
        hasIcon ? Metrics.statusIcon + 2 * Metrics.space2 : 0,
        hasTrailing ? trailingRow.implicitHeight + 2 * Metrics.space1 : 0)
    readonly property real stackWidth: Math.ceil(Math.max(titleLabel.implicitWidth, hasSubtitle ? subtitleLabel.implicitWidth : 0))

    // At least the settings row height, and on the base-4 grid when a subtitle or a tall trailing control grows it.
    implicitHeight: Math.max(Metrics.settingsRowMinHeight, Math.ceil(contentHeight / Metrics.space1) * Metrics.space1)
    implicitWidth: leftPadding + rightPadding + (hasIcon ? Metrics.statusIcon + Metrics.space3 : 0) + stackWidth
        + (hasTrailing ? Metrics.space3 + trailingRow.implicitWidth : 0)
    leftPadding: Metrics.space3
    rightPadding: Metrics.space3
    topPadding: 0
    bottomPadding: 0
    hoverEnabled: true
    focusPolicy: Qt.StrongFocus
    // Children follow the row's direction, so a mirrored row puts the icon on the right and the trailing content on the left.
    LayoutMirroring.childrenInherit: true
    Accessible.role: Accessible.Button
    Accessible.name: title
    Accessible.description: subtitle

    onClicked: activated()
    Keys.onPressed: function (event) {
        // Enter on a focused trailing control bubbles up here; it belongs to that control, not the row.
        if (!root.activeFocus)
            return;
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            root.activated();
            event.accepted = true;
        }
    }

    contentItem: Item {
        opacity: root.enabled ? 1 : Metrics.stateDisabled
        PentadIcon {
            id: icon
            visible: root.hasIcon
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            source: root.iconSource
            pixelSize: Metrics.statusIcon
            color: Theme.tokens.textMuted
            Accessible.ignored: true
        }
        Column {
            id: stack
            anchors.left: parent.left
            anchors.leftMargin: root.hasIcon ? Metrics.statusIcon + Metrics.space3 : 0
            anchors.right: parent.right
            anchors.rightMargin: root.hasTrailing ? trailingRow.implicitWidth + Metrics.space3 : 0
            anchors.verticalCenter: parent.verticalCenter
            PentadText {
                id: titleLabel
                width: parent.width
                text: root.title
                textFormat: Text.PlainText
                color: Theme.tokens.text
                wrapMode: Text.NoWrap
                elide: Text.ElideRight
                maximumLineCount: 1
                // A lone title keeps its full line box so it centres on the row's axis.
                solid: root.hasSubtitle
                Accessible.ignored: true
            }
            PentadText {
                id: subtitleLabel
                visible: root.hasSubtitle
                width: parent.width
                text: root.subtitle
                textFormat: Text.PlainText
                role: "caption"
                color: Theme.tokens.textMuted
                wrapMode: Text.NoWrap
                elide: Text.ElideRight
                maximumLineCount: 1
                solid: true
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

    // The focus edge appears only when focus came from the keyboard.
    background: ContinuousSurface {
        fill: Qt.alpha(Theme.tokens.text, root.down ? Metrics.statePressed : root.hovered ? Metrics.stateHover : 0)
        edge: root.visualFocus ? Theme.tokens.accent : "transparent"
        extent: Metrics.radiusMedium
        Behavior on fill {
            enabled: !Theme.tokens.reducedMotion
            ColorAnimation {
                duration: Motion.short
                easing.type: Motion.easeStandard
            }
        }
    }
}
