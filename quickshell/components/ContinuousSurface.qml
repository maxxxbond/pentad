import QtQuick
import QtQuick.Shapes
import QtQuick.Effects
import "../logic/continuous-corners.mjs" as CornerGeometry
import qs.theme

Item {
    id: root
    property color fill: Theme.tokens.surfaceRaised
    property color edge: "transparent"
    property real extent: Metrics.radiusLarge
    property real concaveShoulder: 0
    property real joinOffset: concaveShoulder
    property bool clipContent: true
    // Floating surfaces cast the shared overlay shadow; the caller keeps Metrics.overlayShadowRoom free around it.
    property bool castsShadow: false
    readonly property var cornerGeometry: CornerGeometry.surfaceGeometry(
        Math.max(0, width), Math.max(0, height), extent, concaveShoulder, joinOffset)
    // A true capsule with semicircular ends, for controls: at control height a continuous corner of
    // half the height reads as a rounded rectangle next to the buttons, which are true capsules.
    property bool capsule: false
    property string contour: capsule ? CornerGeometry.capsuleGeometry(Math.max(0, width), Math.max(0, height)).path
        : cornerGeometry.path
    default property alias content: contentHost.data
    containmentMask: surfaceShape

    // A same-colour copy of the silhouette casts the shadow, so the content mask below stays exact.
    Shape {
        anchors.fill: parent
        visible: root.castsShadow
        preferredRendererType: Shape.CurveRenderer
        layer.enabled: root.castsShadow
        layer.effect: OverlayShadowEffect {}
        ShapePath {
            fillColor: root.fill
            strokeColor: "transparent"
            PathSvg { path: root.contour || "M 0 0" }
        }
    }
    Shape {
        id: surfaceShape
        anchors.fill: parent
        containsMode: Shape.FillContains
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            fillColor: root.fill
            strokeColor: root.edge
            strokeWidth: root.edge.a === 0 ? 0 : 1
            PathSvg { path: root.contour || "M 0 0" }
        }
    }
    ShaderEffectSource {
        id: contentMask
        sourceItem: contentHost.layer.enabled ? surfaceShape : null
        visible: false
        hideSource: false
        live: contentHost.layer.enabled
    }
    Item {
        id: contentHost
        anchors.fill: parent
        layer.enabled: root.clipContent && children.length > 0
        layer.effect: MultiEffect {
            maskEnabled: true
            maskSource: contentMask
        }
    }
}
