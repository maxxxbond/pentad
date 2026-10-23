import QtQuick
import QtQuick.Shapes
import "../logic/continuous-corners.mjs" as CornerGeometry
import qs.theme

// The dashed rim of a drop target: round-capped dashes along the same continuous corner as the
// surface it sits in. Drop targets are the one outline the borderless contract allows, so a drag
// reads as "this takes it" before the release. Place it inset in the target and pass the
// concentric radius (outer extent minus the inset).
Item {
    id: root
    property real extent: Metrics.radiusCard
    // The drag is over this target: the dashes brighten and walk around the rim.
    property bool active: false
    property real strokeWidth: 2
    property real dashLength: 10
    property real gapLength: 6
    property color restColor: Qt.alpha(Theme.tokens.text, 0.22)
    property color activeColor: Qt.alpha(Theme.tokens.accent, 0.9)
    // A faint wash inside the rim, for targets that have no surface of their own (the bar).
    property color fill: "transparent"
    // Semicircular ends instead of continuous corners, for pill-shaped targets.
    property bool capsule: false
    readonly property real contourWidth: Math.max(0, width - strokeWidth)
    readonly property real contourHeight: Math.max(0, height - strokeWidth)
    readonly property real contourRadius: Math.max(0, extent - strokeWidth / 2)
    // A whole number of dashes closes the rim; the pattern below is in stroke widths, and the round
    // caps add half a stroke to each end of a dash.
    readonly property var capsuleShape: capsule ? CornerGeometry.capsuleGeometry(contourWidth, contourHeight) : null
    readonly property real period: CornerGeometry.evenDashPeriod(capsule ? capsuleShape.length
        : CornerGeometry.surfaceLength(contourWidth, contourHeight, contourRadius), dashLength + gapLength) / strokeWidth
    readonly property real dashUnits: Math.max(0.01, dashLength / strokeWidth - 1)
    property real march: 0
    visible: width > strokeWidth * 2 && height > strokeWidth * 2

    NumberAnimation on march {
        from: 0; to: -root.period
        // One dash step per three long transitions: a slow walk, not a spinner.
        duration: Motion.longDuration * 3
        loops: Animation.Infinite
        running: root.active && root.visible && !Theme.tokens.reducedMotion
        onRunningChanged: if (!running) root.march = 0
    }

    Shape {
        x: root.strokeWidth / 2
        y: root.strokeWidth / 2
        width: root.contourWidth
        height: root.contourHeight
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            fillColor: root.fill
            strokeColor: root.active ? root.activeColor : root.restColor
            strokeWidth: root.strokeWidth
            strokeStyle: ShapePath.DashLine
            capStyle: ShapePath.RoundCap
            dashPattern: [root.dashUnits, Math.max(0.01, root.period - root.dashUnits)]
            dashOffset: root.march
            PathSvg {
                path: (root.capsule ? root.capsuleShape.path
                    : CornerGeometry.surfaceGeometry(root.contourWidth, root.contourHeight, root.contourRadius).path) || "M 0 0"
            }
        }
    }
}
