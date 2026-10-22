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
    // Two-line clock: digits have no descenders, so the baselines sit one digit height plus 2 px
    // apart, and the stack is centred on the digits rather than on the font's ascent and descent.
    FontMetrics { id: digitMetrics; font.family: Theme.tokens.fontFamily; font.pixelSize: Metrics.textSection; font.weight: Font.Medium }
    // Reading height re-evaluates this when the font loads; the function call alone is not tracked.
    readonly property real digitHeight: digitMetrics.height > 0 ? Math.ceil(digitMetrics.tightBoundingRect('0').height) : 0
    readonly property real stackedPitch: digitHeight + 2
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
        spacing: root.stackedPitch - stackedTime.height
        // Box centre minus digit centre: the ink spans baseline - digitHeight to baseline + pitch.
        anchors.verticalCenterOffset: height / 2 - (2 * stackedTime.baselineOffset - root.digitHeight + root.stackedPitch) / 2

        PentadText {
            id: stackedTime
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.controllerReady ? controller.time : ''
            font.pixelSize: Metrics.textSection
            font.weight: Font.Medium
            font.features: { "tnum": 1 }
            wrapMode: Text.NoWrap
            renderType: Text.NativeRendering
            color: root.ink
        }

        PentadText {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.controllerReady ? controller.date : ''
            font.pixelSize: Metrics.textSection
            font.weight: Font.Medium
            font.features: { "tnum": 1 }
            wrapMode: Text.NoWrap
            renderType: Text.NativeRendering
            color: Theme.tokens.textMuted
        }
    }
}
