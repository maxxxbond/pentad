pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Effects
import qs.theme

Item {
    id: root
    property string source: ""
    property string accessibleName: ""
    property int pixelSize: Metrics.panelIcon
    property color color: Qt.alpha(Theme.tokens.text, 0.8)
    property bool symbolic: true
    property bool preserveLuminance: false
    readonly property alias imageStatus: glyphImage.status
    implicitWidth: pixelSize
    implicitHeight: pixelSize
    Accessible.name: accessibleName
    Accessible.role: Accessible.Graphic
    Image {
        id: glyphImage
        anchors.fill: parent
        source: root.source
        sourceSize.width: root.pixelSize
        sourceSize.height: root.pixelSize
        fillMode: Image.PreserveAspectFit
        smooth: true
        layer.enabled: root.symbolic
        layer.effect: root.preserveLuminance ? luminanceTint : symbolicTint
        Accessible.ignored: true
    }
    Component {
        id: symbolicTint
        MultiEffect {
            opacity: root.color.a
            brightness: 1
            colorization: 1
            colorizationColor: root.color
        }
    }
    Component {
        id: luminanceTint
        ShaderEffect {
            property var source
            property color tint: root.color
            fragmentShader: Qt.resolvedUrl('../assets/shaders/tray-tint.frag.qsb')
        }
    }
}
