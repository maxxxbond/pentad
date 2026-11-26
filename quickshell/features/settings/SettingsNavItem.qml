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
    // Selection is tonal elevation, never an accent fill: the capsule lifts one step, the label
    // reaches full strength and only the icon carries the accent. Hover and press lay the usual
    // state layers over it. Every state is the same ink at a different share, so the fill fades
    // from one to the next without passing through another hue.
    readonly property real stateLayer: (active ? Metrics.stateSelected : 0)
        + (down ? Metrics.statePressed : hovered ? Metrics.stateHover : 0)
    readonly property color foreground: active || hovered ? Theme.tokens.text : Theme.tokens.textMuted
    text: label
    implicitHeight: collapsed ? Metrics.settingsRailItem : Metrics.settingsNavItem
    implicitWidth: collapsed ? Metrics.settingsRailItem : 200
    leftPadding: collapsed ? 0 : Metrics.space3
    rightPadding: collapsed ? 0 : Metrics.space3
    focusPolicy: Qt.StrongFocus
    Accessible.name: badge !== "" ? label + ", " + badge : label
    Accessible.role: Accessible.PageTab
    Accessible.selected: active

    background: ContinuousSurface {
        fill: Qt.alpha(Theme.tokens.text, control.stateLayer)
        edge: control.visualFocus ? Theme.tokens.accent : "transparent"
        // Capsule (user decision, 2026-10-20); the collapsed rail item is a circle.
        extent: height / 2
        Behavior on fill {
            enabled: !Theme.tokens.reducedMotion
            ColorAnimation {
                duration: Motion.short
                easing.type: Motion.easeStandard
            }
        }
    }
    contentItem: Item {
        implicitWidth: control.collapsed ? Metrics.settingsRailItem : 200
        PentadIcon {
            id: icon
            visible: control.iconSource !== ""
            source: control.iconSource
            pixelSize: Metrics.exposedIcon
            color: control.active ? Theme.tokens.accent : control.foreground
            anchors.verticalCenter: parent.verticalCenter
            anchors.horizontalCenter: control.collapsed ? parent.horizontalCenter : undefined
            x: control.collapsed ? 0 : (control.mirrored ? parent.width - width : 0)
        }
        PentadText {
            id: labelText
            visible: !control.collapsed
            readonly property real iconSpace: icon.visible ? icon.width + Metrics.space3 : 0
            readonly property real badgeSpace: badgeTag.visible ? badgeTag.width + Metrics.space2 : 0
            x: control.mirrored ? badgeSpace : iconSpace
            width: Math.max(0, parent.width - iconSpace - badgeSpace)
            height: parent.height
            text: control.label
            textFormat: Text.PlainText
            color: control.foreground
            font.weight: control.active ? Font.Medium : Font.Normal
            horizontalAlignment: control.mirrored ? Text.AlignRight : Text.AlignLeft
            verticalAlignment: Text.AlignVCenter
            wrapMode: Text.NoWrap
            elide: Text.ElideRight
            Behavior on color {
                enabled: !Theme.tokens.reducedMotion
                ColorAnimation {
                    duration: Motion.short
                    easing.type: Motion.easeStandard
                }
            }
        }
        Rectangle {
            id: badgeTag
            objectName: "settings-nav-badge"
            visible: control.badge !== "" && !control.collapsed
            // A small tonal pill, as in PentadSectionHeader. A layer rather than a surface colour,
            // so it stays visible on the lifted capsule of the active item.
            width: Math.max(height, badgeLabel.implicitWidth + Metrics.space3)
            height: 20
            radius: height / 2
            color: Qt.alpha(Theme.tokens.text, Metrics.stateSelected)
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
        radius: width / 2
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
