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
    property string pendingPlayerId: ""
    property string pendingTrack: ""
    property string pendingTrackRevision: ""
    property real targetMicros: -1
    readonly property bool settling: pressed || settle.running || hold.running
    readonly property string hoverTime: {
        var total = Math.floor(hoverRatio * duration / 1000000);
        return Math.floor(total / 60) + ":" + String(total % 60).padStart(2, "0");
    }
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
    function scheduleSeek() {
        if (!enabled) return;
        displayRatio = Math.max(0, Math.min(1, value / 100));
        pendingPlayerId = String(player.id);
        pendingTrack = String(player.trackId);
        pendingTrackRevision = revisionFor(player);
        targetMicros = Math.round(displayRatio * duration);
        hold.stop();
        settle.restart();
    }
    function syncFromPlayer() {
        displayRatio = duration > 0 ? Math.max(0, Math.min(1, positionMicros / duration)) : 0;
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

    // Spotify reports the old position for a moment after SetPosition; keep the
    // dragged value until the player catches up with it (or the hold expires).
    onPositionMicrosChanged: {
        if (hold.running && Math.abs(positionMicros - targetMicros) < 1500000) hold.stop();
        if (!settling) syncFromPlayer();
    }
    onDurationChanged: if (!settling) syncFromPlayer()
    onMoved: scheduleSeek()
    onVisualPositionChanged: rebuildWave()
    onAvailableWidthChanged: rebuildWave()
    onAvailableHeightChanged: rebuildWave()
    onPlayerChanged: {
        settle.stop();
        hold.stop();
        pendingPlayerId = "";
        pendingTrack = "";
        pendingTrackRevision = "";
        syncFromPlayer();
        rebuildWave();
    }
    Component.onCompleted: rebuildWave()
    Connections { target: Theme; function onTokensChanged() { root.rebuildWave(); } }
    Timer {
        interval: 16
        repeat: true
        running: root.visible && root.enabled && root.player.playback === "playing" && !Theme.tokens.reducedMotion
        onTriggered: { root.phase = (root.phase + 0.10) % (Math.PI * 2); root.rebuildWave(); }
    }
    Timer {
        id: settle
        interval: 160
        onTriggered: {
            if (!root.enabled || !root.player
                    || root.pendingPlayerId !== String(root.player.id)
                    || root.pendingTrack !== String(root.player.trackId)
                    || root.pendingTrackRevision !== root.revisionFor(root.player)) return;
            var target = Math.round(Math.max(0, Math.min(root.duration, root.displayRatio * root.duration)));
            root.services.media.seek(root.pendingPlayerId, root.pendingTrack, target, root.pendingTrackRevision);
            root.pendingPlayerId = "";
            root.pendingTrack = "";
            root.pendingTrackRevision = "";
            hold.restart();
        }
    }
    Timer {
        id: hold
        interval: 1500
        onTriggered: root.syncFromPlayer()
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
        readonly property real centerX: root.leftPadding + 8 + (root.availableWidth - 16) * root.hoverRatio
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
