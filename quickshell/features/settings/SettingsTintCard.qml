import QtQuick
import QtQuick.Shapes
import qs.components
import qs.theme
import "../../logic/continuous-corners.mjs" as CornerGeometry

// A raised card of the Models page with depth and an optional group hue: the same continuous
// corners as ContinuousSurface, a vertical gradient from a hue-tinted top to the card colour, and
// the shared quiet shadow. No outline. Content is not clipped (keep it inside the padding).
Item {
    id: root
    property color hue: "transparent"
    // How much of the hue tints the top of the card.
    property real tint: 0.10
    property color base: Theme.tokens.surfaceRaised
    property real extent: Metrics.radiusCard
    property bool raised: true
    // A diagonal gradient (the hero strip) instead of a vertical one.
    property bool diagonal: false
    readonly property bool dark: Theme.config.appearance !== "light"
    readonly property color topColor: hue.a > 0 ? Qt.tint(base, Qt.alpha(hue, tint))
        : dark ? Qt.tint(base, Qt.alpha(Theme.tokens.text, 0.025)) : base
    readonly property string contour: CornerGeometry.surfaceGeometry(Math.max(0, width), Math.max(0, height), extent, 0, 0).path
    default property alias content: host.data

    Shape {
        anchors.fill: parent
        visible: root.raised
        preferredRendererType: Shape.CurveRenderer
        layer.enabled: root.raised
        layer.effect: OverlayShadowEffect {}
        ShapePath {
            fillColor: root.base
            strokeColor: "transparent"
            PathSvg { path: root.contour || "M 0 0" }
        }
    }
    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            strokeColor: "transparent"
            fillGradient: LinearGradient {
                x1: 0
                y1: 0
                x2: root.diagonal ? root.width : 0
                y2: root.height
                GradientStop { position: 0; color: root.topColor }
                GradientStop { position: root.diagonal ? 0.65 : 1; color: root.base }
            }
            PathSvg { path: root.contour || "M 0 0" }
        }
    }
    Item {
        id: host
        anchors.fill: parent
    }
}
