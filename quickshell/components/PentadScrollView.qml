import QtQuick
import QtQuick.Controls.Basic
import qs.theme

ScrollView {
    id: control

    ScrollBar.vertical: ScrollBar {
        id: verticalBar
        x: control.mirrored ? 0 : control.width - width
        y: control.topPadding
        height: control.availableHeight
        implicitWidth: 10
        focusPolicy: Qt.TabFocus
        active: hovered || pressed
        visible: active
        Accessible.name: "Vertical scroll bar"
        Accessible.role: Accessible.ScrollBar
        background: Rectangle { color: Theme.tokens.surface }

        contentItem: Item {
            implicitWidth: 8
            implicitHeight: 36
            Rectangle {
                anchors.fill: parent
                anchors.margins: 2
                radius: Metrics.radiusPill
                color: verticalBar.pressed ? Theme.tokens.accent
                    : verticalBar.hovered || verticalBar.activeFocus
                        ? Qt.alpha(Theme.tokens.text, 0.45)
                        : Qt.alpha(Theme.tokens.text, 0.24)
                Behavior on color {
                    enabled: !Theme.tokens.reducedMotion
                    ColorAnimation { duration: Motion.short }
                }
            }
        }
    }

    ScrollBar.horizontal: ScrollBar {
        id: horizontalBar
        x: control.leftPadding
        y: control.height - height
        width: control.availableWidth
        implicitHeight: 10
        focusPolicy: Qt.TabFocus
        active: hovered || pressed
        visible: active
        Accessible.name: "Horizontal scroll bar"
        Accessible.role: Accessible.ScrollBar
        background: Rectangle { color: Theme.tokens.surface }

        contentItem: Item {
            implicitWidth: 36
            implicitHeight: 8
            Rectangle {
                anchors.fill: parent
                anchors.margins: 2
                radius: Metrics.radiusPill
                color: horizontalBar.pressed ? Theme.tokens.accent
                    : horizontalBar.hovered || horizontalBar.activeFocus
                        ? Qt.alpha(Theme.tokens.text, 0.45)
                        : Qt.alpha(Theme.tokens.text, 0.24)
                Behavior on color {
                    enabled: !Theme.tokens.reducedMotion
                    ColorAnimation { duration: Motion.short }
                }
            }
        }
    }
}
