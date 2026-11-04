pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.theme
import "../services"
import "../logic/wallpaper.mjs" as WallpaperLogic

// The wallpaper of one screen on the background layer. Images decode at the screen's pixel
// size, never at the file's (a 6K photo costs what the screen costs), and a new image loads
// behind the current one and is revealed only once it is ready, so a switch never flashes.
// A fade cross-fades the two image layers. Wipe, disc, pixelate and iris draw a shader over
// both layers for the length of the change only, so a settled wallpaper is a plain image.
PanelWindow {
    id: window
    required property var services
    readonly property var wallpaper: services.wallpaper
    readonly property string outputId: screen ? screen.name : ""
    readonly property string source: wallpaper.displayPathFor(outputId)
    readonly property string fill: wallpaper.document.fill
    // How the latest change is drawn: "fade", "none" or a shader transition. "random" is
    // resolved once per change; reduced motion makes every change "none".
    property string change: "none"
    readonly property bool animate: change === "fade"
    readonly property bool reducedMotion: Theme.tokens.reducedMotion
    // Longer than UI motion: a whole-screen change reads as a cut below ~half a second.
    readonly property int fadeDuration: 600
    readonly property int sweepDuration: reducedMotion ? 0 : 700
    readonly property real pixelRatio: screen && screen.devicePixelRatio ? screen.devicePixelRatio : 1
    readonly property size pixelSize: Qt.size(Math.round(width * pixelRatio), Math.round(height * pixelRatio))
    property Item front: null
    readonly property alias firstLayer: first
    readonly property alias secondLayer: second
    readonly property alias transitionOverlay: overlay
    readonly property alias transitionAnimation: sweep
    property string failedPath: ""
    // The running shader transition ("sweep"): the layers it blends, its shader and origin.
    property Item sweepFrom: null
    property Item sweepTo: null
    property string sweepKind: ""
    property real sweepProgress: 0
    property int sweepDirection: 0
    property real sweepCenterX: 0.5
    property real sweepCenterY: 0.5
    // Shader transitions that failed to load; their changes fade instead.
    property var brokenShaders: ({})

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
        if (previous === layer) { layer.shown = true; return; }
        // A change that lands during a sweep starts from the image the sweep was heading to.
        if (overlay.active) dropSweep();
        let kind = reducedMotion ? "none" : WallpaperLogic.pickTransition(wallpaper.document, Math.random);
        // The first image has nothing to sweep away, so any animated choice fades it in.
        if (!previous && kind !== "none") kind = "fade";
        if (previous && WallpaperLogic.shaderTransitions.indexOf(kind) >= 0 && !startSweep(kind, previous, layer)) kind = "fade";
        change = kind;
        layer.z = 1;
        if (previous) previous.z = 0;
        front = layer;
        layer.shown = true;
        if (!previous) return;
        if (kind === "fade") retire.restart();
        else if (kind === "none") retireBack();
        else {
            retire.stop();
            sweep.restart();
        }
    }
    // The image under the front one goes once the change has covered it.
    function retireBack() {
        const old = window.front === first ? second : first;
        old.shown = false;
        old.path = "";
    }
    // Shows the overlay for a shader transition; false when its shader cannot load.
    function startSweep(kind, from, to) {
        if (brokenShaders[kind]) return false;
        const origin = WallpaperLogic.transitionOrigin(Math.random);
        sweepKind = kind;
        sweepFrom = from;
        sweepTo = to;
        sweepDirection = origin.direction;
        sweepCenterX = origin.x;
        sweepCenterY = origin.y;
        sweepProgress = 0;
        overlay.active = true;
        // A local shader file loads while the overlay is created, so a broken one shows here.
        const effect = overlay.item ? overlay.item.effect : null;
        if (effect && effect.status !== ShaderEffect.Error) return true;
        dropSweep();
        const broken = Object.assign({}, brokenShaders);
        broken[kind] = true;
        brokenShaders = broken;
        console.warn("WallpaperWindow: the " + kind + " transition shader did not load; changes fade instead."
            + (effect && effect.log ? " " + effect.log : ""));
        return false;
    }
    // Removes the overlay without retiring a layer; the caller decides which image stays.
    function dropSweep() {
        overlay.active = false;
        sweep.stop();
        sweepFrom = null;
        sweepTo = null;
    }
    function endSweep() {
        dropSweep();
        retireBack();
    }
    onSourceChanged: load()
    Component.onCompleted: load()

    // The outgoing image stays under the incoming one until the fade has covered it.
    Timer {
        id: retire
        interval: window.fadeDuration + 100
        onTriggered: window.retireBack()
    }
    NumberAnimation {
        id: sweep
        target: window
        property: "sweepProgress"
        from: 0
        to: 1
        duration: window.sweepDuration
        easing.type: Easing.InOutCubic
        onFinished: if (overlay.active) window.endSweep()
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

    // Exists only while a sweep runs and is destroyed with its two textures afterwards, so a
    // settled wallpaper costs nothing beyond its image. Both layers stay shown underneath; the
    // backing keeps fit and center margins in the window colour meanwhile.
    Loader {
        id: overlay
        objectName: "wallpaperTransition"
        anchors.fill: parent
        z: 2
        active: false
        sourceComponent: Item {
            readonly property alias effect: sweepEffect
            Rectangle {
                anchors.fill: parent
                color: window.color
            }
            // Zero-sized, so they only provide textures. Not live: each holds the frame it took
            // when the sweep began, and an image reloading underneath cannot disturb it.
            ShaderEffectSource {
                id: fromTexture
                sourceItem: window.sweepFrom
                textureSize: window.pixelSize
                hideSource: false
                live: false
            }
            ShaderEffectSource {
                id: toTexture
                sourceItem: window.sweepTo
                textureSize: window.pixelSize
                hideSource: false
                live: false
            }
            ShaderEffect {
                id: sweepEffect
                anchors.fill: parent
                property var fromImage: fromTexture
                property var toImage: toTexture
                property real progress: window.sweepProgress
                property real aspect: height > 0 ? width / height : 1
                property real direction: window.sweepDirection
                property real centerX: window.sweepCenterX
                property real centerY: window.sweepCenterY
                fragmentShader: Qt.resolvedUrl("../assets/shaders/wallpaper-" + window.sweepKind + ".frag.qsb")
            }
        }
    }
}
