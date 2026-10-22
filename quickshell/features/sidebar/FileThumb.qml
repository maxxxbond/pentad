import QtQuick
import qs.components
import qs.theme
import '../../logic/file-tools.mjs' as Files

// Square file preview on a tonal tile: a cached thumbnail when one exists, else a kind icon.
Item {
    id: root
    required property var services
    property string uri: ''
    property string mimeType: ''
    property string kind: 'file'
    property int iconSize: Metrics.statusIcon
    property real radius: Metrics.radiusSmall
    readonly property var info: uri && services && services.toolPreviews ? services.toolPreviews.metadata[uri] || ({}) : ({})
    readonly property string source: info.thumbnail
        || (/^image\/(?:png|jpeg|webp|gif|bmp)$/.test(mimeType) ? uri : '')
    readonly property bool ready: preview.status === Image.Ready
    implicitWidth: 40
    implicitHeight: 40
    Accessible.ignored: true
    function request() { if (uri && services && services.toolPreviews && kind === 'file') services.toolPreviews.want([uri]); }
    onUriChanged: request()
    Component.onCompleted: request()

    ContinuousSurface { anchors.fill: parent; fill: Theme.tokens.surfaceRaised; extent: root.radius }
    Image {
        id: preview
        anchors.fill: parent
        anchors.margins: 2
        source: root.source
        sourceSize: Qt.size(160, 160)
        fillMode: Image.PreserveAspectFit
        asynchronous: true
        cache: true
        opacity: root.ready ? 1 : 0
        Behavior on opacity { enabled: !Theme.tokens.reducedMotion; NumberAnimation { duration: Motion.short } }
    }
    PentadIcon {
        anchors.centerIn: parent
        visible: !root.ready
        source: Qt.resolvedUrl('../../assets/icons/material/' + Files.symbolForMime(root.mimeType, root.kind) + '-symbolic.svg')
        pixelSize: root.iconSize
        color: Theme.tokens.textMuted
    }
}
