pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Shapes
import qs.theme
import "../logic/geometry-diagnostics.mjs" as Geometry

Item {
    id: root
    property rect innerRect: Qt.rect(0, 0, 0, 0)
    property real outerRadius: 0
    property real innerRadius: 0
    property string outerCurve: ""
    property string innerCurve: ""
    property string outerContour: ""
    property string side: "left"
    readonly property var audit: visible ? Geometry.auditNestedGeometry(
        { width: width, height: height, radius: outerRadius, curve: outerCurve },
        { x: innerRect.x, y: innerRect.y, width: innerRect.width, height: innerRect.height,
            radius: innerRadius, curve: innerCurve }, side) : ({ status: "unverified", issues: [] })
    readonly property color diagnosticColor: audit.status === "error" ? Theme.tokens.error
        : audit.status === "ok" ? Theme.tokens.accent : Theme.tokens.textMuted
    visible: GeometryDiagnostics.enabled
    z: 100
    Accessible.ignored: true

    function number(value) { return Number.isFinite(value) ? String(Math.round(value * 10) / 10) : "?"; }
    function issueLabel(code) {
        return ({ "radius-mismatch": "r≠", "unequal-insets": "insets≠",
            "curve-mismatch": "curve≠", "outside": "outside" })[code] || code;
    }

    Shape {
        anchors.fill: parent
        visible: root.outerContour !== ""
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            fillColor: "transparent"
            strokeColor: root.diagnosticColor
            strokeWidth: 2
            PathSvg { path: root.outerContour || "M 0 0" }
        }
    }
    Rectangle {
        anchors.fill: parent
        visible: root.outerContour === ""
        radius: root.outerRadius
        color: "transparent"
        border.width: 2
        border.color: root.diagnosticColor
    }
    Rectangle {
        x: root.innerRect.x
        y: root.innerRect.y
        width: root.innerRect.width
        height: root.innerRect.height
        radius: root.innerRadius
        color: "transparent"
        border.width: 1
        border.color: Theme.tokens.text
    }
    Rectangle {
        x: root.side === "right" ? 2 : root.innerRect.x + root.innerRect.width + 4
        anchors.verticalCenter: parent.verticalCenter
        width: Math.max(0, root.side === "right" ? root.innerRect.x - x - 4 : root.width - x - 2)
        height: Math.min(root.height, annotation.implicitHeight + 4)
        radius: 3
        color: Theme.tokens.surface
        Text {
            id: annotation
            anchors.fill: parent
            anchors.margins: 2
            text: root.number(root.width) + "×" + root.number(root.height)
                + "  Ø" + root.number(root.innerRect.width)
                + "\nr " + root.number(root.outerRadius) + "/" + root.number(root.innerRadius)
                + "→" + root.number(root.audit.expectedRadius)
                + "  p " + (root.audit.insets ? [root.audit.insets.top, root.audit.insets.bottom,
                    root.audit.insets.edge].map(root.number).join("/") : "?")
                + "\n" + root.outerCurve + "/" + root.innerCurve
                + "\n" + (root.audit.issues.length ? root.audit.issues.map(root.issueLabel).join(" · ") : root.audit.status)
            font.family: Theme.tokens.fontFamily
            font.pixelSize: 10
            color: root.diagnosticColor
            elide: Text.ElideRight
            maximumLineCount: 4
        }
    }
}
