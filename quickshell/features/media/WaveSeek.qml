import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Shapes
import "../../logic/lyrics.mjs" as LyricsLogic
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
        settle.restart();
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

    onPositionMicrosChanged: if (!pressed) displayRatio = duration > 0 ? Math.max(0, Math.min(1, positionMicros / duration)) : 0
    onDurationChanged: if (!pressed) displayRatio = duration > 0 ? Math.max(0, Math.min(1, positionMicros / duration)) : 0
    onMoved: scheduleSeek()
    onVisualPositionChanged: rebuildWave()
    onAvailableWidthChanged: rebuildWave()
    onAvailableHeightChanged: rebuildWave()
    onPlayerChanged: {
        settle.stop();
        pendingPlayerId = "";
        pendingTrack = "";
        pendingTrackRevision = "";
        displayRatio = duration > 0 ? Math.max(0, Math.min(1, positionMicros / duration)) : 0;
        rebuildWave();
    }
    Component.onCompleted: rebuildWave()
    Connections { target: Theme; function onTokensChanged() { root.rebuildWave(); } }
    ToolTip.visible: hovered && enabled
    ToolTip.text: {
        var targetSeconds = hoverRatio * duration / 1000000;
        var minutes = Math.floor(targetSeconds / 60);
        var seconds = Math.floor(targetSeconds % 60);
        var state = services.lyrics ? services.lyrics.state : null;
        var lyricData = state && state.kind === "ready" ? state.value : null;
        var lyric = lyricData && lyricData.lines && lyricData.lines.length
            ? LyricsLogic.previewLyric(lyricData.lines, targetSeconds, services.lyrics.offsetMs || 0) : "";
        return minutes + ":" + String(seconds).padStart(2, "0") + (lyric ? " · " + lyric : "");
    }

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
        }
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
    handle: Item {
        implicitWidth: 16
        implicitHeight: root.availableHeight
        x: root.leftPadding + root.visualPosition * (root.availableWidth - width)
        y: root.topPadding + (root.availableHeight - height) / 2
    }
}
