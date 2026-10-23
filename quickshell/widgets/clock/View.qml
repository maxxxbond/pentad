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
    readonly property bool showDate: controllerReady && !context.compact && controller.showDate !== false
    readonly property bool stacked: showDate && controller.stacked
    readonly property bool emphasis: stacked && controller.emphasis
    readonly property color ink: Qt.alpha(Theme.tokens.text, 0.8)

    // Two-line clock: digits have no descenders, so the date's digits start 2 px below the time's
    // baseline, and the stack is centred on the digits rather than on the font's ascent and descent.
    readonly property int stackGap: 2
    readonly property real dateScale: emphasis ? 0.6 : 1
    // Digit height per pixel of font size, measured once at a large size.
    FontMetrics { id: referenceMetrics; font.family: Theme.tokens.fontFamily; font.pixelSize: 100; font.weight: Font.Medium }
    // Reading height re-evaluates these when the font loads; the function call alone is not tracked.
    readonly property real digitRatio: referenceMetrics.height > 0 ? referenceMetrics.tightBoundingRect('0').height / 100 : 0.75
    // The chosen size, shrunk so both lines of digits keep 4 px of bar above and below.
    readonly property int timeSize: controllerReady
        ? Math.min(controller.size, Math.floor((controller.barHeight - 8 - stackGap) / (digitRatio * (1 + dateScale)))) : 16
    readonly property int dateSize: Math.max(Metrics.textCaption - 2, Math.round(timeSize * dateScale))
    FontMetrics { id: timeMetrics; font: stackedTime.font }
    FontMetrics { id: dateMetrics; font.family: Theme.tokens.fontFamily; font.pixelSize: root.dateSize; font.weight: Font.Medium }
    readonly property real timeDigitHeight: timeMetrics.height > 0 ? Math.ceil(timeMetrics.tightBoundingRect('0').height) : 0
    readonly property real dateDigitHeight: dateMetrics.height > 0 ? Math.ceil(dateMetrics.tightBoundingRect('0').height) : 0
    // The large-time date is tracked out until it spans the time's width.
    readonly property real dateTracking: !emphasis || !controllerReady || controller.date.length < 2
        || timeMetrics.height <= 0 || dateMetrics.height <= 0 ? 0
        : Math.max(1, (timeMetrics.advanceWidth(controller.time) - dateMetrics.advanceWidth(controller.date)) / (controller.date.length - 1))
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
        objectName: root.emphasis ? "clock-emphasis" : "clock-stacked"
        visible: root.stacked
        anchors.centerIn: parent
        // Date digits begin stackGap below the time's baseline.
        spacing: root.stackGap + root.dateDigitHeight - stackedTime.height
            + stackedTime.baselineOffset - stackedDate.baselineOffset
        // Box centre minus digit centre; the digits span the time's cap line to the date's baseline.
        anchors.verticalCenterOffset: height / 2
            - (2 * stackedTime.baselineOffset - root.timeDigitHeight + root.stackGap + root.dateDigitHeight) / 2

        PentadText {
            id: stackedTime
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.controllerReady ? controller.time : ''
            font.pixelSize: root.timeSize
            font.weight: Font.Medium
            font.features: { "tnum": 1 }
            wrapMode: Text.NoWrap
            renderType: Text.NativeRendering
            color: root.ink
        }

        PentadText {
            id: stackedDate
            anchors.horizontalCenter: parent.horizontalCenter
            // Tracking also trails the last digit; shift back by half of it to stay centred.
            anchors.horizontalCenterOffset: root.dateTracking / 2
            text: root.controllerReady ? controller.date : ''
            font.pixelSize: root.dateSize
            font.weight: Font.Medium
            font.features: { "tnum": 1 }
            font.letterSpacing: root.dateTracking
            wrapMode: Text.NoWrap
            renderType: Text.NativeRendering
            color: Theme.tokens.textMuted
        }
    }
}
