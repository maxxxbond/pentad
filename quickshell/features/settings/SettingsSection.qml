import QtQuick
import QtQuick.Controls.Basic
import qs.components
import qs.theme

// A 12 px uppercase caption above one raised card. Rows inside are flattened onto the card
// and separated by thin inset lines drawn by the rows themselves; the card has no outline.
Item {
    id: root
    property string title: ""
    property string helpText: ""
    property string infoAccessibleName: "About this setting"
    // Optional: the caption becomes a button with a chevron that hides the card.
    property bool collapsible: false
    property bool collapsed: false
    // `framed: false` drops the card for full-width editors that bring their own (the widget catalog).
    property bool framed: true
    default property alias content: fields.data
    readonly property bool wide: width >= 560
    readonly property bool bodyVisible: !(collapsible && collapsed)
    readonly property bool mirrored: LayoutMirroring.enabled
    readonly property real captionGap: 8
    implicitHeight: header.height + (bodyVisible && fields.implicitHeight > 0 ? captionGap + fields.implicitHeight : 0)
    Accessible.name: title
    Accessible.role: Accessible.Grouping

    Row {
        id: header
        x: root.mirrored ? root.width - width : 0
        y: 0
        height: Math.max(captionButton.height, info.visible ? info.height : 0)
        spacing: 4
        layoutDirection: root.mirrored ? Qt.RightToLeft : Qt.LeftToRight
        Button {
            id: captionButton
            objectName: "settings-section-toggle"
            enabled: root.collapsible
            focusPolicy: root.collapsible ? Qt.StrongFocus : Qt.NoFocus
            leftPadding: 4
            rightPadding: 4
            topPadding: 0
            bottomPadding: 0
            implicitHeight: 24
            implicitWidth: contentItem.implicitWidth + leftPadding + rightPadding
            anchors.verticalCenter: parent.verticalCenter
            checkable: false
            Accessible.name: root.title
            Accessible.role: root.collapsible ? Accessible.Button : Accessible.StaticText
            Accessible.description: root.collapsible ? (root.collapsed ? "Collapsed" : "Expanded") : ""
            onClicked: root.collapsed = !root.collapsed
            background: Rectangle {
                radius: Metrics.radiusTag
                color: "transparent"
                border.width: captionButton.visualFocus ? 2 : 0
                border.color: Theme.tokens.accent
            }
            contentItem: Row {
                spacing: 4
                layoutDirection: root.mirrored ? Qt.RightToLeft : Qt.LeftToRight
                PentadChevron {
                    id: chevron
                    visible: root.collapsible
                    direction: root.collapsed ? (root.mirrored ? "left" : "right") : "down"
                    shown: root.collapsible
                    engaged: captionButton.hovered || captionButton.visualFocus
                    pixelSize: Metrics.panelIcon
                    anchors.verticalCenter: parent.verticalCenter
                }
                PentadText {
                    id: titleText
                    objectName: "settings-section-title"
                    width: Math.min(implicitWidth, Math.max(0, root.width - (chevron.visible ? chevron.width + 4 : 0)
                        - (info.visible ? info.width + header.spacing : 0) - 8))
                    text: root.title
                    textFormat: Text.PlainText
                    role: "caption"
                    font.capitalization: Font.AllUppercase
                    font.letterSpacing: 1.1
                    font.weight: Font.DemiBold
                    color: captionButton.hovered && root.collapsible ? Theme.tokens.text : Theme.tokens.textMuted
                    elide: Text.ElideRight
                    wrapMode: Text.NoWrap
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
        }
        PentadInfoButton {
            id: info
            objectName: "settings-section-info"
            visible: root.helpText !== ""
            helpText: root.helpText
            accessibleName: root.infoAccessibleName
            anchors.verticalCenter: parent.verticalCenter
        }
    }

    ContinuousSurface {
        id: card
        objectName: "settings-section-card"
        visible: root.framed && root.bodyVisible && fields.implicitHeight > 0
        x: 0
        y: header.height + root.captionGap
        width: root.width
        height: fields.implicitHeight
        fill: Theme.tokens.surfaceRaised
        extent: Metrics.radiusCard
    }
    Column {
        id: fields
        objectName: "settings-section-fields"
        x: 0
        y: header.height + root.captionGap
        width: root.width
        visible: root.bodyVisible
        spacing: 0
    }
}
