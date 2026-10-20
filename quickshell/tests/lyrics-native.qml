import QtQuick
import Quickshell
import "services" as Services

ShellRoot {
    id: root
    property var track: ({ id: "fixture", name: "native-lyrics", title: "SyncedSong",
        artist: "Fixture Artist", album: "Fixture Album", lengthMicros: 180000000 })
    property bool startFailureOnly: Quickshell.env("PENTAD_LYRICS_START_FAILURE") === "1"
    property QtObject media: QtObject {
        property var state: ({ kind: "ready", value: { current: root.track } })
    }
    property Services.Lyrics lyrics: Services.Lyrics {
        media: root.media
        preview: false
        safeMode: false
    }
    property var checks: []
    property int phase: 0
    property double phaseAt: 0
    property int cancelGeneration: 0

    function check(name, passed, detail) {
        checks.push({ name: name, passed: passed, detail: detail || "" });
    }
    function setTrack(title) {
        track = ({ id: "fixture", name: "native-lyrics", title: title,
            artist: "Fixture Artist", album: "Fixture Album", lengthMicros: 180000000 });
        media.state = { kind: "ready", value: { current: track } };
    }
    function finish() {
        console.log("PENTAD_LYRICS_TEST " + JSON.stringify({
            status: checks.every(function(item) { return item.passed; }) ? "pass" : "fail",
            checks: checks
        }));
        Qt.quit();
    }

    Timer {
        interval: 25
        repeat: true
        running: true
        onTriggered: {
            if (root.phase === 0) {
                if (root.startFailureOnly) root.setTrack("MissingCurlSong");
                root.lyrics.acquire("native-lyrics-fixture");
                root.phase = 1;
            } else if (root.startFailureOnly && root.phase === 1
                    && root.lyrics.state.kind === "error") {
                root.check("missing curl settles immediately as start-failed",
                    root.lyrics.state.reason === "start-failed", JSON.stringify(root.lyrics.state));
                root.finish();
                stop();
            } else if (root.phase === 1 && root.lyrics.state.kind === "ready") {
                var synced = root.lyrics.state.value;
                root.check("HTTP 200 decodes synchronized lyrics",
                    synced.lines.length === 1 && synced.lines[0].text === "Synced fixture line"
                    && synced.plain === "" && !synced.instrumental, JSON.stringify(synced));
                root.lyrics.release("native-lyrics-fixture");
                root.lyrics.acquire("native-lyrics-fixture");
                root.check("cached result is available immediately after reacquire",
                    root.lyrics.state.kind === "ready"
                    && root.lyrics.state.value.lines[0].text === "Synced fixture line");
                root.setTrack("SearchSong");
                root.phase = 2;
            } else if (root.phase === 2 && root.lyrics.state.kind === "ready") {
                root.check("exact 404 falls back to a matched search result",
                    root.lyrics.state.value.lines[0].text === "Search fixture line",
                    JSON.stringify(root.lyrics.state));
                root.setTrack("RateSong");
                root.phase = 3;
            } else if (root.phase === 3 && root.lyrics.state.reason === "rate-limited") {
                root.lyrics.release("native-lyrics-fixture");
                root.lyrics.acquire("native-lyrics-fixture");
                root.check("429 backoff blocks another request after reacquire",
                    root.lyrics.state.kind === "unavailable" && root.lyrics.state.reason === "rate-limited");
                root.lyrics.retryAfterUntil = 0;
                root.setTrack("InvalidSong");
                root.phase = 4;
            } else if (root.phase === 4 && root.lyrics.state.kind === "error") {
                root.check("invalid JSON reports invalid-response", root.lyrics.state.reason === "invalid-response");
                root.setTrack("OversizeSong");
                root.phase = 10;
            } else if (root.phase === 10 && root.lyrics.state.kind === "error") {
                root.check("oversize response is rejected", root.lyrics.state.reason === "lookup-failed");
                root.setTrack("StatusSong");
                root.phase = 11;
            } else if (root.phase === 11 && root.lyrics.state.kind === "error") {
                root.check("HTTP 500 reports lookup-failed", root.lyrics.state.reason === "lookup-failed");
                root.setTrack("InstrumentalSong");
                root.phase = 12;
            } else if (root.phase === 12 && root.lyrics.state.kind === "ready") {
                root.check("instrumental response remains explicit",
                    root.lyrics.state.value.instrumental && root.lyrics.state.value.lines.length === 0);
                root.setTrack("PlainSong");
                root.phase = 13;
            } else if (root.phase === 13 && root.lyrics.state.kind === "ready") {
                root.check("plain lyrics response remains explicit",
                    root.lyrics.state.value.plain === "Plain fixture lyrics"
                    && root.lyrics.state.value.lines.length === 0);
                root.setTrack("FailureSong");
                root.phase = 5;
            } else if (root.phase === 5 && root.lyrics.state.kind === "error") {
                root.check("curl failure reports lookup-failed", root.lyrics.state.reason === "lookup-failed");
                root.setTrack("TimeoutSong");
                root.phase = 14;
            } else if (root.phase === 14 && root.lyrics.state.kind === "error") {
                root.check("request deadline reports timeout", root.lyrics.state.reason === "timeout");
                root.setTrack("StaleSong");
                root.phaseAt = Date.now();
                root.phase = 6;
            } else if (root.phase === 6 && Date.now() - root.phaseAt >= 200) {
                root.setTrack("CurrentSong");
                root.phase = 7;
            } else if (root.phase === 7 && root.lyrics.state.kind === "ready") {
                root.check("track change ignores stale response",
                    root.lyrics.state.value.lines.length === 1
                    && root.lyrics.state.value.lines[0].text === "Current track line",
                    JSON.stringify(root.lyrics.state));
                root.setTrack("CancelSong");
                root.phaseAt = Date.now();
                root.cancelGeneration = root.lyrics.generation;
                root.phase = 8;
            } else if (root.phase === 8 && Date.now() - root.phaseAt >= 200) {
                root.lyrics.release("native-lyrics-fixture");
                root.check("last release cancels the active Process",
                    root.lyrics.consumers.length === 0 && root.lyrics.request === null
                    && root.lyrics.generation > root.cancelGeneration);
                root.phaseAt = Date.now();
                root.phase = 9;
            } else if (root.phase === 9 && Date.now() - root.phaseAt >= 900) {
                root.check("cancelled Process cannot commit a late response",
                    root.lyrics.state.kind === "starting" && root.lyrics.request === null);
                root.finish();
                stop();
            }
        }
    }
}
