import QtQuick
import QtQuick.Controls.Basic
import qs.components
import qs.theme

Button {
    id: control
    property string label: ""
    property string iconSource: ""
    property bool active: false
    property bool collapsed: false
    // Optional count badge (for example the number of widgets). Empty hides it.
    property string badge: ""
    text: label
    implicitHeight: collapsed ? Metrics.settingsRailItem : Metrics.settingsNavItem
    implicitWidth: collapsed ? Metrics.settingsRailItem : 200
    leftPadding: collapsed ? 0 : 12
    rightPadding: collapsed ? 0 : 12
    focusPolicy: Qt.StrongFocus
    Accessible.name: badge !== "" ? label + ", " + badge : label
    Accessible.role: Accessible.PageTab
    Accessible.selected: active

    background: ContinuousSurface {
        fill: control.active ? Qt.alpha(Theme.tokens.accent, 0.18)
            : control.down || control.hovered ? Theme.tokens.surfaceOverlay : "transparent"
        edge: control.visualFocus ? Theme.tokens.accent : "transparent"
        // Capsule (user decision, 2026-10-20); the collapsed rail item is a circle.
        extent: height / 2
        Behavior on fill { enabled: !Theme.tokens.reducedMotion; ColorAnimation { duration: Motion.short } }
    }
    contentItem: Item {
        implicitWidth: control.collapsed ? Metrics.settingsRailItem : 200
        PentadIcon {
            id: icon
            visible: control.iconSource !== ""
            source: control.iconSource
            pixelSize: Metrics.exposedIcon
            color: control.active ? Theme.tokens.accent : Theme.tokens.textMuted
            anchors.verticalCenter: parent.verticalCenter
            anchors.horizontalCenter: control.collapsed ? parent.horizontalCenter : undefined
            x: control.collapsed ? 0 : (control.mirrored ? parent.width - width : 0)
        }
        PentadText {
            id: labelText
            visible: !control.collapsed
            readonly property real iconSpace: icon.visible ? icon.width + 12 : 0
            readonly property real badgeSpace: badgeTag.visible ? badgeTag.width + 8 : 0
            x: control.mirrored ? badgeSpace : iconSpace
            width: Math.max(0, parent.width - iconSpace - badgeSpace)
            height: parent.height
            text: control.label
            textFormat: Text.PlainText
            color: control.active ? Theme.tokens.text : Theme.tokens.textMuted
            font.weight: control.active ? Font.Medium : Font.Normal
            horizontalAlignment: control.mirrored ? Text.AlignRight : Text.AlignLeft
            verticalAlignment: Text.AlignVCenter
            wrapMode: Text.NoWrap
            elide: Text.ElideRight
        }
        Rectangle {
            id: badgeTag
            objectName: "settings-nav-badge"
            visible: control.badge !== "" && !control.collapsed
            width: Math.max(20, badgeLabel.implicitWidth + 12)
            height: 20
            radius: Metrics.radiusTag
            color: Theme.tokens.surfaceOverlay
            anchors.verticalCenter: parent.verticalCenter
            x: control.mirrored ? 0 : parent.width - width
            PentadText {
                id: badgeLabel
                anchors.centerIn: parent
                text: control.badge
                textFormat: Text.PlainText
                role: "caption"
                color: Theme.tokens.textMuted
            }
        }
    }
    // Collapsed rail: the badge sits as a small marker on the icon corner.
    Rectangle {
        visible: control.badge !== "" && control.collapsed
        width: 8
        height: 8
        radius: Metrics.radiusTag
        color: Theme.tokens.accent
        x: parent ? control.width - width - 6 : 0
        y: 6
    }
    PentadHint {
        axis: "horizontal"
        text: control.label
        shown: control.collapsed && (control.hovered || control.visualFocus)
        delay: control.hovered ? Metrics.tooltipDelay : 0
    }
}
