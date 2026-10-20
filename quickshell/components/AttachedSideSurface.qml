import QtQuick
import QtQuick.Shapes
import "../logic/continuous-corners.mjs" as CornerGeometry
import qs.theme

Item {
    id: root
    required property string side
    required property Component contentComponent
    property bool loadContent: true
    readonly property alias contentContainer: contentHost
    readonly property var cornerGeometry: CornerGeometry.surfaceGeometry(Math.max(0, width), Math.max(0, height), 0, Metrics.attachedShoulder)
    readonly property real shoulder: cornerGeometry.shoulder
    readonly property real panelWidth: Math.max(0, width - shoulder)
    readonly property real totalWidth: width
    readonly property real contentX: side === "left" ? 0 : shoulder
    default property alias content: contentHost.data

    implicitWidth: 390 + Metrics.attachedShoulder
    implicitHeight: 600
    containmentMask: surfaceShape
    signal contourChanged()
    onWidthChanged: contourChanged()
    onHeightChanged: contourChanged()
    onSideChanged: contourChanged()

    Shape {
        id: surfaceShape
        anchors.fill: parent
        containsMode: Shape.FillContains
        preferredRendererType: Shape.CurveRenderer
        // Only the silhouette is layered; the content sits beside it. Screen edges and the bar seam clip
        // the shadow, so it shows toward the desktop alone.
        layer.enabled: true
        layer.effect: OverlayShadowEffect {}
        ShapePath {
            id: bodyPath
            fillColor: Theme.tokens.surface
            strokeColor: "transparent"
            startX: root.side === "left" ? 0 : root.shoulder
            startY: 0
            PathLine { x: root.side === "left" ? root.panelWidth : root.totalWidth; y: 0 }
            PathLine { x: root.side === "left" ? root.panelWidth : root.totalWidth; y: root.height }
            PathLine { x: root.side === "left" ? 0 : root.shoulder; y: root.height }
            PathLine { x: root.side === "left" ? 0 : root.shoulder; y: 0 }
        }
        ShapePath {
            id: shoulderPath
            fillColor: Theme.tokens.surface
            strokeColor: "transparent"
            property var pathData: {
                let d = "";
                const c = { curveTo: (x1, y1, x2, y2, x, y) => { d += ` C ${x1} ${y1} ${x2} ${y2} ${x} ${y}`; } };
                if (root.side === "left") {
                    d = `M ${root.panelWidth} 0 L ${root.totalWidth} 0`;
                    CornerGeometry.continuousCorner(c, [root.totalWidth, 0], root.shoulder, [-1, 0], [0, 1]);
                    d += ` L ${root.panelWidth} ${root.shoulder} Z`;
                } else {
                    d = `M ${root.shoulder} 0 L 0 0`;
                    CornerGeometry.continuousCorner(c, [0, 0], root.shoulder, [1, 0], [0, 1]);
                    d += ` L ${root.shoulder} ${root.shoulder} Z`;
                }
                return d;
            }
            PathSvg { path: shoulderPath.pathData }
        }
    }

    Item {
        id: contentHost
        x: root.contentX
        width: root.panelWidth
        height: root.height
        clip: true
        Loader {
            anchors.fill: parent
            sourceComponent: root.contentComponent
            active: root.loadContent && root.visible
        }
    }
}
