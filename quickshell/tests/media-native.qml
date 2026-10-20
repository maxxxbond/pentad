import QtQuick
import Quickshell.Services.Mpris
import "services" as Services

QtObject {
    id: root
    property int step: 0
    property var checks: []
    property var completions: ({})
    property var requestIds: []
    property string requestId: ""
    property string revision: ""
    property Services.Media media: Services.Media {
        preview: false
        preferredId: "org.mpris.MediaPlayer2.B"
        onCommandFinished: function(id, result) { root.completions[id] = result; }
    }

    function check(name, passed, detail) {
        checks.push({ name: name, passed: passed, detail: detail || "" });
    }
    function rememberRequest(id) {
        requestIds = requestIds.concat([id]);
        return id;
    }
    function done() {
        var passed = checks.every(function(item) { return item.passed; });
        console.log("PENTAD_TEST " + JSON.stringify({ status: passed ? "pass" : "fail", checks: checks }));
        Qt.quit();
    }
    function player(id) {
        for (var i = 0; i < Mpris.players.values.length; i++)
            if (Mpris.players.values[i].dbusName === id) return Mpris.players.values[i];
        return null;
    }
    function current() { return media.state.kind === "ready" ? media.state.value.current : null; }
    property Timer poll: Timer {
        interval: 50
        repeat: true
        running: true
        onTriggered: {
            var a = root.player("org.mpris.MediaPlayer2.A");
            var b = root.player("org.mpris.MediaPlayer2.B");
            if (root.step === 0 && a && b && root.media.state.kind === "ready") {
                var value = root.media.state.value;
                var source = value.current;
                root.check("native metadata and micros", source.id.endsWith(".B") && source.title === "Track B"
                    && source.artist === "Pentad fixture" && source.lengthMicros === 120000000
                    && source.positionMicros === 12500000 && source.trackId === "/track/B",
                    JSON.stringify(source));
                root.check("capabilities reflect MPRIS control", source.canPlayPause && source.canSeek && !source.canNext && source.canPrevious);
                root.check("preferred source pins while another plays", source.id.endsWith(".B") && a.isPlaying);
                root.check("position timer waits for a consumer", !root.media.positionTimer.running);
                root.media.acquire("native-fixture");
                root.check("position timer starts for a consumer", root.media.positionTimer.running);
                root.media.release("native-fixture");
                root.check("position timer stops after release", !root.media.positionTimer.running);
                root.requestId = root.rememberRequest(root.media.command("org.mpris.MediaPlayer2.B", "play-pause"));
                root.step = 1;
            } else if (root.step === 1 && root.completions[root.requestId]) {
                root.check("command accepted", root.completions[root.requestId].ok === true, JSON.stringify(root.completions[root.requestId]));
                root.requestId = root.rememberRequest(root.media.command("org.mpris.MediaPlayer2.B", "next"));
                root.step = 2;
            } else if (root.step === 2 && root.completions[root.requestId]) {
                root.check("capability denial", root.completions[root.requestId].ok === false && root.completions[root.requestId].reason === "denied");
                root.step = 20;
                console.log("PENTAD_MEDIA_PHASE " + JSON.stringify({ phase: "deny-control" }));
            } else if (root.step === 20 && !b.canControl) {
                var denied = root.media.state.value.current;
                root.check("native canControl denial is reflected", !denied.canPlayPause && !denied.canSeek && !denied.canNext && !denied.canPrevious);
                root.requestId = root.rememberRequest(root.media.command("org.mpris.MediaPlayer2.B", "play-pause"));
                root.step = 3;
            } else if (root.step === 3 && root.completions[root.requestId]) {
                root.check("control denial", root.completions[root.requestId].ok === false && root.completions[root.requestId].reason === "denied");
                root.step = 21;
                console.log("PENTAD_MEDIA_PHASE " + JSON.stringify({ phase: "restore-control" }));
            } else if (root.step === 21 && b.canControl) {
                root.requestId = root.rememberRequest(root.media.seek("org.mpris.MediaPlayer2.B", "/track/B", 15000000, "stale-revision"));
                root.step = 4;
            } else if (root.step === 4 && root.completions[root.requestId]) {
                root.check("stale revision denied", root.completions[root.requestId].ok === false && root.completions[root.requestId].reason === "denied");
                root.revision = String(b.uniqueId);
                root.requestId = root.rememberRequest(root.media.seek("org.mpris.MediaPlayer2.B", "/track/B", 15000000, root.revision));
                root.step = 5;
            } else if (root.step === 5 && root.completions[root.requestId]) {
                root.check("seek accepted", root.completions[root.requestId].ok === true, JSON.stringify(root.completions[root.requestId]));
                root.step = 6;
                console.log("PENTAD_MEDIA_PHASE " + JSON.stringify({ phase: "change-track" }));
            } else if (root.step === 6 && b.uniqueId !== Number(root.revision)) {
                root.check("track change advances native revision", b.trackTitle === "Changed B" && b.uniqueId !== Number(root.revision));
                root.requestId = root.rememberRequest(root.media.seek("org.mpris.MediaPlayer2.B", "/track/B2", 20000000, root.revision));
                root.step = 7;
            } else if (root.step === 7 && root.completions[root.requestId]) {
                root.check("seek from previous track revision denied", root.completions[root.requestId].ok === false && root.completions[root.requestId].reason === "denied");
                root.revision = String(b.uniqueId);
                root.requestId = root.rememberRequest(root.media.seek("org.mpris.MediaPlayer2.B", "/track/B2", 20000000, root.revision));
                root.step = 8;
            } else if (root.step === 8 && root.completions[root.requestId]) {
                root.check("seek accepted", root.completions[root.requestId].ok === true, JSON.stringify(root.completions[root.requestId]));
                root.step = 9;
                console.log("PENTAD_MEDIA_PHASE " + JSON.stringify({ phase: "drop-player" }));
            } else if (root.step === 9 && !b && root.current() && root.current().id.endsWith(".A")) {
                root.check("selected source falls back after disappearance", root.media.state.value.selectedId.endsWith(".B") && root.current().id.endsWith(".A"));
                root.step = 10;
                console.log("PENTAD_MEDIA_PHASE " + JSON.stringify({ phase: "restore-player" }));
            } else if (root.step === 10 && b && root.current() && root.current().id.endsWith(".B")) {
                root.check("cached source wins after reappearance", root.media.state.value.selectedId.endsWith(".B") && root.current().id.endsWith(".B"));
                root.requestId = root.rememberRequest(root.media.selectPlayer("org.mpris.MediaPlayer2.missing"));
                root.step = 11;
            } else if (root.step === 11 && root.completions[root.requestId]) {
                var uniqueIds = root.requestIds.filter(function(id, index, all) { return all.indexOf(id) === index; });
                root.check("request IDs are unique and consistently formed", uniqueIds.length === root.requestIds.length
                    && root.requestIds.every(function(id) { return /^media-[1-9][0-9]*$/.test(id); }));
                root.check("missing source selection reports unavailable", root.completions[root.requestId].ok === false
                    && root.completions[root.requestId].reason === "unavailable");
                root.done();
            }
        }
    }
}
