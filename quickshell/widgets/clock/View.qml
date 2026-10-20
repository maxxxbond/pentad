import QtQuick
import qs.components
import qs.theme

Item {
    id: root
    required property string instanceId
    required property var context
    required property var settings
    required property var services
    required property var controller
    readonly property bool controllerReady: controller !== null
    readonly property bool showDate: controllerReady && !context.compact
    readonly property bool stacked: showDate && controller.stacked
    readonly property color ink: Qt.alpha(Theme.tokens.text, 0.8)
    signal actionRequested(string action)

    visible: controllerReady

    implicitWidth: Math.ceil(stacked ? clockColumn.implicitWidth : clockRow.implicitWidth)
    implicitHeight: Math.ceil(stacked ? clockColumn.implicitHeight : clockRow.implicitHeight)
    MouseArea { anchors.fill: parent; onPressed: root.actionRequested('right') }

    Row {
        id: clockRow
        objectName: "clock-inline"
        visible: !root.stacked
        spacing: 6
        anchors.centerIn: parent

        PentadText {
            text: root.controllerReady ? controller.time : ''
            width: Math.ceil(implicitWidth)
            font.pixelSize: Metrics.textSection
            font.weight: Font.Normal
            renderType: Text.NativeRendering
            verticalAlignment: Text.AlignVCenter
            color: root.ink
        }

        PentadIcon {
            visible: root.showDate
            source: Qt.resolvedUrl('../../assets/icons/brand/logo-symbolic.svg')
            pixelSize: 14
            color: Theme.tokens.textMuted
            anchors.verticalCenter: parent.verticalCenter
        }

        PentadText {
            visible: root.showDate
            text: root.controllerReady ? controller.date : ''
            width: Math.ceil(implicitWidth)
            font.pixelSize: Metrics.textSection
            font.weight: Font.Normal
            renderType: Text.NativeRendering
            verticalAlignment: Text.AlignVCenter
            color: root.ink
        }
    }

    Column {
        id: clockColumn
        objectName: "clock-stacked"
        visible: root.stacked
        anchors.centerIn: parent

        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 3

            PentadText {
                id: stackedTime
                text: root.controllerReady ? controller.clockTime : ''
                font.pixelSize: Metrics.textBody
                font.weight: Font.Medium
                font.features: { "tnum": 1 }
                lineHeightMode: Text.FixedHeight
                lineHeight: 15
                renderType: Text.NativeRendering
                color: root.ink
            }

            PentadText {
                visible: text !== ''
                y: stackedTime.baselineOffset - baselineOffset
                text: root.controllerReady ? controller.meridiem : ''
                font.pixelSize: Metrics.textCaption
                font.weight: Font.Medium
                lineHeightMode: Text.FixedHeight
                lineHeight: 13
                renderType: Text.NativeRendering
                color: Theme.tokens.textMuted
            }
        }

        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 4

            PentadText {
                text: root.controllerReady ? controller.weekday : ''
                font.pixelSize: Metrics.textCaption
                font.weight: Font.Medium
                lineHeightMode: Text.FixedHeight
                lineHeight: 13
                renderType: Text.NativeRendering
                color: Theme.tokens.accent
            }

            PentadText {
                text: root.controllerReady ? controller.day : ''
                font.pixelSize: Metrics.textCaption
                font.weight: Font.Normal
                lineHeightMode: Text.FixedHeight
                lineHeight: 13
                renderType: Text.NativeRendering
                color: Theme.tokens.textMuted
            }
        }
    }
}
