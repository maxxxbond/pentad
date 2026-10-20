import QtQuick
import QtQuick.Effects
import QtQuick.Shapes
import qs.theme

Item {
    id: root
    required property var services
    property bool playing: false
    property color accent: Theme.tokens.accent
    property string artworkSource: ""
    property int bandCount: 12
    property var bands: []
    property var targetBands: []
    property real phase: 0
    property real previousFrameAt: 0
    property string consumerId: "media-card-default-visualizer"
    property string acquiredConsumerId: ""
    property bool consumerAcquired: false
    property bool lifecycleReady: false

    function sync() {
        if (!lifecycleReady) return;
        if (consumerAcquired && acquiredConsumerId !== consumerId) {
            services.visualizer.release(acquiredConsumerId);
            acquiredConsumerId = "";
            consumerAcquired = false;
        }
        if (visible && playing && !Theme.tokens.reducedMotion && consumerId && !consumerAcquired) {
            services.visualizer.acquire(consumerId);
            acquiredConsumerId = consumerId;
            consumerAcquired = true;
        } else if ((!visible || !playing || Theme.tokens.reducedMotion) && consumerAcquired) {
            services.visualizer.release(acquiredConsumerId);
            acquiredConsumerId = "";
            consumerAcquired = false;
        }
    }
    function updateFrame() {
        var now = Date.now();
        var dt = previousFrameAt > 0 ? Math.min(0.05, Math.max(0.001, (now - previousFrameAt) / 1000)) : 1 / 60;
        previousFrameAt = now;
        var state = services.visualizer.state;
        var raw = state && state.kind === "ready" && state.value ? state.value.values || [] : [];
        var grouped = [];
        var step = raw.length / bandCount;
        for (var b = 0; b < bandCount; b++) {
            var first = Math.floor(b * step);
            var last = Math.min(raw.length, Math.floor((b + 1) * step));
            var sum = 0;
            for (var i = first; i < last; i++) sum += Number(raw[i] || 0) * Number(raw[i] || 0);
            grouped[b] = last > first ? Math.sqrt(sum / (last - first)) : 0;
        }
        var targets = [];
        for (var n = 0; n < bandCount; n++) {
            targets[n] = grouped[n] * 0.65 + grouped[Math.max(0, n - 1)] * 0.175 + grouped[Math.min(bandCount - 1, n + 1)] * 0.175;
        }
        targetBands = targets;
        var next = [];
        var energy = 0;
        for (var j = 0; j < bandCount; j++) {
            var current = Number(bands[j] || 0);
            var target = Number(targetBands[j] || 0);
            var rate = target > current ? 34 : 14;
            next[j] = current + (target - current) * (1 - Math.exp(-dt * rate));
            energy += next[j];
        }
        bands = next;
        phase += dt * (1.8 + energy / bandCount * 2);
    }
    function hillPoints(heightScale, phaseOffset) {
        var controls = [];
        for (var i = -1; i <= bandCount; i++) {
            var ratio = i / (bandCount - 1);
            var x = ratio * width;
            var value = Number(bands[Math.max(0, Math.min(bandCount - 1, i))] || 0);
            var amplitude = Math.pow(Math.min(1, value * 1.8), 0.72);
            var rolling = 0.86 + 0.14 * Math.sin(ratio * Math.PI * 2.5 + phase + phaseOffset);
            controls.push(Qt.point(x, height - amplitude * height * 0.94 * heightScale * rolling));
        }
        var bass = ((bands[0] || 0) + (bands[1] || 0) + (bands[2] || 0)) / 3;
        var points = [Qt.point(0, height)];
        var steps = 100;
        for (var s = 0; s <= steps; s++) {
            var u = s / steps * (bandCount - 1);
            var index = Math.floor(u);
            var t = u - index;
            var p0 = controls[index];
            var p1 = controls[index + 1];
            var p2 = controls[index + 2];
            var p3 = controls[index + 3] || p2;
            var t2 = t * t;
            var t3 = t2 * t;
            var px = 0.5 * (2 * p1.x + (-p0.x + p2.x) * t + (2 * p0.x - 5 * p1.x + 4 * p2.x - p3.x) * t2 + (-p0.x + 3 * p1.x - 3 * p2.x + p3.x) * t3);
            var py = 0.5 * (2 * p1.y + (-p0.y + p2.y) * t + (2 * p0.y - 5 * p1.y + 4 * p2.y - p3.y) * t2 + (-p0.y + 3 * p1.y - 3 * p2.y + p3.y) * t3);
            var ripple = height * 0.024 * bass * heightScale * (0.7 * Math.sin(px * Math.PI * 2 / 48 - phase * 2.8 + phaseOffset) + 0.3 * Math.sin(px * Math.PI * 2 / 29 + phase * 1.7 + phaseOffset));
            points.push(Qt.point(Math.max(0, Math.min(width, px)), Math.max(0, Math.min(height, py + ripple))));
        }
        points.push(Qt.point(width, height));
        return points;
    }

    onVisibleChanged: sync()
    onPlayingChanged: sync()
    onConsumerIdChanged: sync()
    Connections { target: Theme; function onTokensChanged() { root.sync(); } }
    Component.onCompleted: { lifecycleReady = true; sync(); }
    Component.onDestruction: if (consumerAcquired) services.visualizer.release(acquiredConsumerId)

    Timer {
        interval: 16
        repeat: true
        running: root.visible && root.playing && !Theme.tokens.reducedMotion
        onTriggered: root.updateFrame()
    }
    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(root.accent.r * 0.12 + 20 / 255 * 0.88,
            root.accent.g * 0.12 + 21 / 255 * 0.88,
            root.accent.b * 0.12 + 24 / 255 * 0.88, 1)
    }
    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            strokeColor: 'transparent'
            fillGradient: LinearGradient {
                x1: 0; y1: 0; x2: root.width; y2: root.height
                GradientStop { position: 0; color: Qt.alpha(root.accent, 0.32) }
                GradientStop { position: 1; color: Qt.alpha(root.accent, 0.10) }
            }
            startX: 0; startY: 0
            PathLine { x: root.width; y: 0 }
            PathLine { x: root.width; y: root.height }
            PathLine { x: 0; y: root.height }
            PathLine { x: 0; y: 0 }
        }
    }
    Image {
        objectName: "audio-wave-artwork"
        anchors.fill: parent
        source: root.artworkSource
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: false
        sourceSize.width: 512
        sourceSize.height: 512
        visible: String(source) !== ""
        opacity: 0.42
        layer.enabled: visible
        layer.effect: MultiEffect { blurEnabled: true; blurMax: 48; blur: 0.82 }
    }
    Rectangle {
        anchors.fill: parent
        visible: root.artworkSource !== ""
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0; color: Qt.rgba(0.06, 0.07, 0.09, 0.52) }
            GradientStop { position: 0.45; color: Qt.rgba(0.06, 0.07, 0.09, 0.36) }
            GradientStop { position: 1; color: Qt.rgba(0.06, 0.07, 0.09, 0.56) }
        }
    }
    Shape {
        anchors.fill: parent
        visible: root.bands.reduce(function(sum, value) { return sum + value; }, 0) / root.bandCount >= 0.005
        preferredRendererType: Shape.CurveRenderer
        layer.enabled: true
        layer.smooth: true
        layer.effect: MultiEffect { blurEnabled: true; blurMax: 4; blur: 0.4 }
        ShapePath {
            fillGradient: LinearGradient {
                x1: 0; y1: 0; x2: 0; y2: root.height
                GradientStop { position: 0; color: Qt.alpha(root.accent, 0.16) }
                GradientStop { position: 1; color: Qt.alpha(root.accent, 0.16 * 0.45) }
            }
            strokeColor: "transparent"
            PathPolyline { path: root.hillPoints(1, 0) }
        }
        ShapePath {
            fillGradient: LinearGradient {
                x1: 0; y1: 0; x2: 0; y2: root.height
                GradientStop { position: 0; color: Qt.alpha(root.accent, 0.2) }
                GradientStop { position: 1; color: Qt.alpha(root.accent, 0.2 * 0.45) }
            }
            strokeColor: "transparent"
            PathPolyline { path: root.hillPoints(0.78, 2.1) }
        }
        ShapePath {
            fillGradient: LinearGradient {
                x1: 0; y1: 0; x2: 0; y2: root.height
                GradientStop { position: 0; color: Qt.alpha(root.accent, 0.24) }
                GradientStop { position: 1; color: Qt.alpha(root.accent, 0.24 * 0.45) }
            }
            strokeColor: "transparent"
            PathPolyline { path: root.hillPoints(0.56, 4.2) }
        }
    }
}
