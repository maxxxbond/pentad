pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.theme
import "../services"

// The wallpaper of one screen on the background layer. Images decode at the screen's pixel
// size, never at the file's (a 6K photo costs what the screen costs), and a new image loads
// behind the current one and fades in only once it is ready, so a switch never flashes.
PanelWindow {
    id: window
    required property var services
    readonly property var wallpaper: services.wallpaper
    readonly property string outputId: screen ? screen.name : ""
    readonly property string source: wallpaper.displayPathFor(outputId)
    readonly property string fill: wallpaper.document.fill
    readonly property bool animate: wallpaper.document.transition === "fade" && !Theme.tokens.reducedMotion
    // Longer than UI motion: a whole-screen change reads as a cut below ~half a second.
    readonly property int fadeDuration: 600
    readonly property real pixelRatio: screen && screen.devicePixelRatio ? screen.devicePixelRatio : 1
    property Item front: null
    readonly property alias firstLayer: first
    readonly property alias secondLayer: second
    property string failedPath: ""

    visible: source !== ""
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    color: Theme.tokens.surface
    WlrLayershell.namespace: "pentad-wallpaper"
    WlrLayershell.layer: WlrLayer.Background
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    function fileUrl(path) {
        return path ? "file://" + path.split("/").map(encodeURIComponent).join("/") : "";
    }
    function load() {
        if (!source || (front && front.path === source)) return;
        const back = front === first ? second : first;
        if (back.path === source && back.status === Image.Ready) { reveal(back); return; }
        back.path = source;
    }
    function reveal(layer) {
        if (layer.path !== source) return;
        const previous = front;
        layer.z = 1;
        if (previous) previous.z = 0;
        front = layer;
        layer.shown = true;
        if (previous && previous !== layer) {
            if (animate) retire.restart();
            else { previous.shown = false; previous.path = ""; }
        }
    }
    onSourceChanged: load()
    Component.onCompleted: load()

    // The outgoing image stays under the incoming one until the fade has covered it.
    Timer {
        id: retire
        interval: window.fadeDuration + 100
        onTriggered: {
            const old = window.front === first ? second : first;
            old.shown = false;
            old.path = "";
        }
    }

    component Layer: Image {
        id: layer
        property string path: ""
        property bool shown: false
        anchors.fill: parent
        source: window.fileUrl(path)
        asynchronous: true
        cache: false
        smooth: true
        fillMode: window.fill === "fit" ? Image.PreserveAspectFit
            : window.fill === "stretch" ? Image.Stretch
            : window.fill === "center" ? Image.Pad : Image.PreserveAspectCrop
        sourceSize: window.fill === "center" ? undefined
            : Qt.size(Math.round(window.width * window.pixelRatio), Math.round(window.height * window.pixelRatio))
        opacity: shown ? 1 : 0
        visible: opacity > 0
        Behavior on opacity {
            enabled: window.animate
            NumberAnimation { duration: window.fadeDuration; easing.type: Easing.OutCubic }
        }
        onStatusChanged: {
            if (status === Image.Ready) window.reveal(layer);
            else if (status === Image.Error && path === window.source) {
                window.failedPath = path;
                window.wallpaper.error = "Cannot open " + path;
            }
        }
    }
    Layer { id: first; objectName: "wallpaperLayerA" }
    Layer { id: second; objectName: "wallpaperLayerB" }
}
