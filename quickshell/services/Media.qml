import QtQuick
import QtQml
import Quickshell.Services.Mpris
import "../logic/media.mjs" as MediaLogic

QtObject {
    id: root

    required property bool preview
    property bool safeMode: false
    readonly property bool writable: !preview && !safeMode
    property string preferredId: ""
    property string selectedId: preferredId
    property int serial: 0
    property var positionConsumers: []
    readonly property var stallTracker: MediaLogic.createStallTracker()
    readonly property var nativePlayers: preview || !Mpris.players ? null : Mpris.players.values
    readonly property var state: !nativePlayers
        ? ({ kind: "unavailable", reason: preview ? "preview" : "service-missing" })
        : ({ kind: "ready", value: MediaLogic.mediaValue(nativePlayers, selectedId, Date.now(), writable, positionConsumers.length > 0 ? stallTracker : null) })
    readonly property bool active: !preview && nativePlayers !== null
    signal commandFinished(string requestId, var result)

    property Timer positionTimer: Timer {
        interval: 1000
        repeat: true
        running: root.active && root.positionConsumers.length > 0 && root.nativePlayers.some(function(player) { return player && player.isPlaying; })
        onTriggered: {
            for (var i = 0; i < root.nativePlayers.length; i++) {
                var player = root.nativePlayers[i];
                if (player && player.isPlaying) player.positionChanged();
            }
        }
    }

    // Spotify applies SetPosition asynchronously and may not emit Seeked, so
    // re-read the position shortly after a seek, also while paused.
    property Timer repoll: Timer {
        interval: 250
        onTriggered: {
            for (var i = 0; root.nativePlayers && i < root.nativePlayers.length; i++)
                if (root.nativePlayers[i]) root.nativePlayers[i].positionChanged();
        }
    }

    function finish(requestId, result) {
        Qt.callLater(function() { root.commandFinished(requestId, result); });
    }

    function playerFor(id) {
        for (var i = 0; nativePlayers && i < nativePlayers.length; i++)
            if (nativePlayers[i] && nativePlayers[i].dbusName === id) return nativePlayers[i];
        return null;
    }

    function acquire(consumerId) {
        if (!consumerId || positionConsumers.indexOf(consumerId) >= 0) return;
        positionConsumers = positionConsumers.concat([consumerId]);
    }

    function release(consumerId) {
        positionConsumers = positionConsumers.filter(function(id) { return id !== consumerId; });
    }

    function selectPlayer(id) {
        var requestId = "media-" + (++serial);
        if (!playerFor(String(id))) finish(requestId, { ok: false, reason: "unavailable" });
        else {
            selectedId = String(id);
            finish(requestId, { ok: true });
        }
        return requestId;
    }

    function command(playerId, action) {
        var requestId = "media-" + (++serial);
        if (preview || safeMode) {
            finish(requestId, { ok: false, reason: preview ? "preview" : "safe-mode" });
            return requestId;
        }
        var player = playerFor(String(playerId));
        if (!player) {
            finish(requestId, { ok: false, reason: "unavailable" });
            return requestId;
        }
        if (!(action === "play-pause" && player.canControl && player.canTogglePlaying)
                && !(action === "next" && player.canControl && player.canGoNext)
                && !(action === "previous" && player.canControl && player.canGoPrevious)) {
            finish(requestId, { ok: false, reason: "denied" });
            return requestId;
        }
        try {
            if (action === "play-pause") player.togglePlaying();
            else if (action === "next") player.next();
            else player.previous();
            finish(requestId, { ok: true });
        } catch (error) {
            finish(requestId, { ok: false, reason: "unavailable", message: String(error) });
        }
        return requestId;
    }

    function seek(playerId, trackId, positionMicros, trackRevision) {
        var requestId = "media-" + (++serial);
        if (preview || safeMode) {
            finish(requestId, { ok: false, reason: preview ? "preview" : "safe-mode" });
            return requestId;
        }
        var player = playerFor(String(playerId));
        if (!player) {
            finish(requestId, { ok: false, reason: "unavailable" });
            return requestId;
        }
        var metadata = player.metadata || {};
        var currentTrackId = MediaLogic.mprisTrackId(metadata["mpris:trackid"]);
        var currentRevision = String(player.uniqueId);
        if (!player.canControl || !player.canSeek || !player.positionSupported
                || !trackId || currentTrackId !== trackId
                || (trackRevision !== undefined && currentRevision !== String(trackRevision))
                || !Number.isSafeInteger(positionMicros) || positionMicros < 0) {
            finish(requestId, { ok: false, reason: "denied" });
            return requestId;
        }
        var position = MediaLogic.microsToSeconds(positionMicros);
        if (player.lengthSupported) position = Math.min(position, player.length);
        try {
            if (playerFor(String(playerId)) !== player
                    || MediaLogic.mprisTrackId((player.metadata || {})["mpris:trackid"]) !== currentTrackId
                    || String(player.uniqueId) !== currentRevision) {
                finish(requestId, { ok: false, reason: "denied" });
                return requestId;
            }
            player.position = position;
            repoll.restart();
            finish(requestId, { ok: true });
        } catch (error) {
            finish(requestId, { ok: false, reason: "unavailable", message: String(error) });
        }
        return requestId;
    }
}
