import QtQuick
import QtQuick.Shapes
import Qt5Compat.GraphicalEffects
import qs.theme

Item {
    id: root
    required property string glyph
    required property string fallbackSource
    required property real ratio
    required property color ink
    implicitWidth: 20
    implicitHeight: 20
    readonly property bool glyphFontAvailable: Qt.fontFamilies().indexOf("Material Symbols Rounded") >= 0
    property real displayedRatio: Math.max(0, Math.min(1, ratio))
    Behavior on displayedRatio {
        enabled: !Motion.reducedMotion
        NumberAnimation { duration: Motion.medium; easing.type: Easing.OutCubic }
    }

    Shape {
        id: drawing
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            fillColor: Qt.alpha(root.ink, root.ink.a * 0.5)
            strokeColor: "transparent"
            PathAngleArc {
                centerX: 10; centerY: 10
                radiusX: 10; radiusY: 10
                startAngle: 0; sweepAngle: 360
            }
        }
        ShapePath {
            fillColor: root.displayedRatio > 0 ? root.ink : "transparent"
            strokeColor: "transparent"
            startX: 10; startY: 10
            PathLine { x: 10; y: 0.5 }
            PathAngleArc {
                centerX: 10; centerY: 10
                radiusX: 9.5; radiusY: 9.5
                startAngle: -90; sweepAngle: 360 * root.displayedRatio
                moveToStart: false
            }
            PathLine { x: 10; y: 10 }
        }
    }
    ShaderEffectSource {
        id: discTexture
        visible: false
        anchors.fill: parent
        sourceItem: drawing
        hideSource: true
        live: true
    }
    ShaderEffectSource {
        id: glyphTexture
        visible: false
        anchors.fill: parent
        sourceItem: glyphMask
        live: true
    }
    OpacityMask {
        anchors.fill: parent
        source: discTexture
        invert: true
        maskSource: glyphTexture
    }
    Item {
        id: glyphMask
        visible: false
        anchors.fill: parent
        Text {
            anchors.centerIn: parent
            visible: root.glyphFontAvailable
            text: root.glyph
            font.family: "Material Symbols Rounded"
            font.pixelSize: 16
            font.weight: Font.DemiBold
            font.variableAxes: ({ FILL: 1, wght: 600, opsz: 16, GRAD: 0 })
            renderType: Text.NativeRendering
        }
        Image {
            anchors.centerIn: parent
            visible: !root.glyphFontAvailable
            source: root.fallbackSource
            width: 16
            height: 16
            fillMode: Image.PreserveAspectFit
            smooth: true
        }
    }
}
