import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Shapes
import qs.theme

Slider {
    id: root
    required property var player
    required property var services
    property color accent: Theme.tokens.accent
    property real positionMicros: player ? Number(player.positionMicros || 0) : 0
    property real duration: player ? Number(player.lengthMicros || 0) : 0
    property real displayRatio: duration > 0 ? Math.max(0, Math.min(1, positionMicros / duration)) : 0
    property real hoverRatio: displayRatio
    property real phase: 0
    property var wavePoints: []
    readonly property string trackKey: player ? [player.id, player.trackId || "", revisionFor(player)].join("|") : ""
    property string dragKey: ""
    property bool dragged: false
    readonly property real chipRatio: pressed ? displayRatio : hoverRatio
    readonly property string hoverTime: {
        var total = Math.floor(chipRatio * duration / 1000000);
        return Math.floor(total / 60) + ":" + String(total % 60).padStart(2, "0");
    }
    signal seekRequested(string playerId, string trackId, real micros, string revision)
    implicitHeight: 28
    implicitWidth: 130
    from: 0
    to: 100
    stepSize: 2
    value: displayRatio * 100
    enabled: !!player && !!player.canSeek && !!player.trackId && duration > 0
    Accessible.name: "Playback position"
    focus: true

    function revisionFor(target) {
        return target && target.trackRevision !== undefined && target.trackRevision !== null
            ? String(target.trackRevision) : "";
    }
    function syncFromPlayer() {
        if (pressed || settle.running) return;
        displayRatio = duration > 0 ? Math.max(0, Math.min(1, positionMicros / duration)) : 0;
    }
    // One seek per gesture: on release for pointer drags, debounced for the keyboard.
    function requestSeek() {
        settle.stop();
        if (!enabled) return;
        var target = Math.round(Math.max(0, Math.min(1, value / 100)) * duration);
        displayRatio = target / duration;
        seekRequested(String(player.id), String(player.trackId), target, revisionFor(player));
    }
    function rebuildWave() {
        var left = 8;
        var thumb = left + Math.max(0, availableWidth - 16) * visualPosition;
        var end = Math.max(left, thumb - 6);
        var amplitude = player && player.playback === "playing" && !Theme.tokens.reducedMotion ? 2.8 : 0;
        var points = [];
        for (var x = left; x <= end; x += 2) {
            var edge = Math.max(0, Math.min(1, (x - left) / 6, (end - x) / 6));
            points.push(Qt.point(x, availableHeight / 2 + Math.sin((x - left) * Math.PI * 2 / 34 - phase) * amplitude * edge));
        }
        if (!points.length) points.push(Qt.point(left, availableHeight / 2));
        wavePoints = points;
    }

    onPositionMicrosChanged: syncFromPlayer()
    onDurationChanged: syncFromPlayer()
    onMoved: {
        displayRatio = Math.max(0, Math.min(1, value / 100));
        if (pressed) dragged = true;
        else settle.restart();
    }
    onPressedChanged: {
        if (pressed) {
            dragKey = trackKey;
            dragged = false;
        } else if (dragged && dragKey === trackKey) requestSeek();
        else syncFromPlayer();
    }
    onTrackKeyChanged: {
        settle.stop();
        syncFromPlayer();
    }
    onVisualPositionChanged: if (!waveAnimation.running) rebuildWave()
    onAvailableWidthChanged: rebuildWave()
    onAvailableHeightChanged: rebuildWave()
    Component.onCompleted: rebuildWave()
    Connections { target: Theme; function onTokensChanged() { root.rebuildWave(); } }
    FrameAnimation {
        id: waveAnimation
        running: root.visible && root.enabled && root.player.playback === "playing" && !Theme.tokens.reducedMotion
        onTriggered: { root.phase = (root.phase + frameTime * 6.25) % (Math.PI * 2); root.rebuildWave(); }
        onRunningChanged: root.rebuildWave()
    }
    Timer {
        id: settle
        interval: 250
        onTriggered: root.requestSeek()
    }
    background: Item {
        x: root.leftPadding
        y: root.topPadding + (root.availableHeight - height) / 2
        width: root.availableWidth
        height: root.availableHeight
        HoverHandler {
            onPointChanged: root.hoverRatio = Math.max(0, Math.min(1, (point.position.x - 8) / Math.max(1, parent.width - 16)))
        }
        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                fillColor: "transparent"
                strokeColor: Qt.alpha(root.accent, 0.28)
                strokeWidth: 3
                capStyle: ShapePath.RoundCap
                startX: Math.min(root.availableWidth - 8, 8 + (root.availableWidth - 16) * root.visualPosition + 6)
                startY: root.availableHeight / 2
                PathLine { x: root.availableWidth - 8; y: root.availableHeight / 2 }
            }
            ShapePath {
                fillColor: "transparent"
                strokeColor: root.accent
                strokeWidth: 3
                capStyle: ShapePath.RoundCap
                startX: 8
                startY: root.availableHeight / 2
                PathPolyline { path: root.wavePoints }
            }
            ShapePath {
                fillColor: "transparent"
                strokeColor: root.accent
                strokeWidth: 3.5
                capStyle: ShapePath.RoundCap
                startX: 8 + (root.availableWidth - 16) * root.visualPosition
                startY: root.availableHeight / 2 - 9
                PathLine { x: 8 + (root.availableWidth - 16) * root.visualPosition; y: root.availableHeight / 2 + 9 }
            }
            ShapePath {
                fillColor: Qt.alpha(root.accent, 0.34)
                strokeColor: "transparent"
                startX: root.availableWidth - 8
                startY: root.availableHeight / 2
                PathAngleArc { centerX: root.availableWidth - 8; centerY: root.availableHeight / 2; radiusX: 1.8; radiusY: 1.8; startAngle: 0; sweepAngle: 360 }
            }
        }
    }
    Rectangle {
        id: timeChip
        readonly property real centerX: root.leftPadding + 8 + (root.availableWidth - 16) * root.chipRatio
        visible: opacity > 0
        opacity: root.enabled && (root.hovered || root.pressed) ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Motion.short; easing.type: Easing.OutCubic } }
        x: Math.max(0, Math.min(root.width - width, centerX - width / 2))
        y: -height - 2
        z: 10
        width: chipText.implicitWidth + 12
        height: 20
        radius: Metrics.radiusTag
        color: Theme.tokens.surfaceOverlay
        Text {
            id: chipText
            anchors.centerIn: parent
            text: root.hoverTime
            color: Theme.tokens.text
            font.family: Theme.tokens.fontFamily
            font.pixelSize: 11
            font.weight: Font.Medium
            font.features: { "tnum": 1 }
        }
    }
    handle: Item {
        implicitWidth: 16
        implicitHeight: root.availableHeight
        x: root.leftPadding + root.visualPosition * (root.availableWidth - width)
        y: root.topPadding + (root.availableHeight - height) / 2
    }
}
