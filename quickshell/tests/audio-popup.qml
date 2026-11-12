import QtQuick
import QtTest
import Quickshell
import Quickshell.Wayland
import qs.theme
import qs.services
import qs.features.bar

// The popup of the bar's volume icon: the level of the default device with its own mute, the device
// list and, for the output, what each application plays. Driven with the real pointer against a fake audio
// service that remembers every call, with the popup grabbed in the dark and the light theme.
ShellRoot {
    id: root
    property Services nativeServices: Services { preview: true; safeMode: true }
    property TestEvent pointer: TestEvent {}
    readonly property string requestedAppearance: Quickshell.env("PENTAD_GALLERY_APPEARANCE")
    readonly property bool reduced: Quickshell.env("PENTAD_GALLERY_REDUCED_MOTION") === "1"
    readonly property string capture: Quickshell.env("PENTAD_ARTIFACT_PATH")
    property string appearance: requestedAppearance === "light" ? "light" : "dark"
    property var checks: []

    function applyTheme(appearance, reducedMotion) {
        Theme.resolve({ appearance: appearance, accent: "#869677", fontFamily: "Geist", reducedMotion: reducedMotion });
    }
    function check(name, passed, detail) {
        checks.push({ name: name, passed: passed === true, detail: detail || "" });
    }
    function named(item, name) {
        if (!item) return null;
        if (item.objectName === name) return item;
        const children = item.children || [];
        for (let index = 0; index < children.length; index++) {
            const found = named(children[index], name);
            if (found) return found;
        }
        return null;
    }
    Component.onCompleted: applyTheme(appearance, reduced)

    property QtObject fakeAudio: QtObject {
        property real contextualFeedbackUntil: 0
        property var calls: []
        property bool outputMuted: false
        property real outputVolume: 0.64
        property var streamVolumes: ({ s1: 0.6, s2: 0.3 })
        property var streamMutes: ({ s1: false, s2: false })
        property string retained: ""
        signal commandFinished(string requestId, var result)
        readonly property var state: ({ kind: "ready", value: {
            output: { id: "2", label: "Speakers", volume: outputVolume, muted: outputMuted },
            input: { id: "9", label: "Headset microphone", volume: 0.4, muted: false },
            outputs: [{ id: "1", label: "Headphones", volume: 0.3, muted: false },
                { id: "2", label: "Speakers", volume: outputVolume, muted: outputMuted }],
            inputs: [{ id: "9", label: "Headset microphone", volume: 0.4, muted: false }],
            streams: [
                { id: "s1", appName: "Browser", label: "Browser", mediaName: "Lofi stream", icon: "",
                    volume: streamVolumes.s1, muted: streamMutes.s1 },
                { id: "s2", appName: "Player", label: "Player", mediaName: "", icon: "",
                    volume: streamVolumes.s2, muted: streamMutes.s2 }
            ]
        } })
        function note(call) { calls = calls.concat([call]); return "probe-" + calls.length; }
        function setDefault(kind, id) { return note("default:" + kind + ":" + id); }
        function cycleDefault(kind, steps) { return note("cycle:" + kind); }
        function setVolume(kind, value) {
            if (kind === "output") outputVolume = value;
            return note("volume:" + kind + ":" + value.toFixed(2));
        }
        function toggleMute(kind) {
            if (kind === "output") outputMuted = !outputMuted;
            return note("mute:" + kind);
        }
        function setStreamVolume(id, value) {
            streamVolumes = Object.assign({}, streamVolumes, { [id]: value });
            return note("stream-volume:" + id + ":" + value.toFixed(2));
        }
        function toggleStreamMute(id) {
            streamMutes = Object.assign({}, streamMutes, { [id]: !streamMutes[id] });
            return note("stream-mute:" + id);
        }
        function retainMixer(id) { retained = id; }
        function releaseMixer(id) { if (retained === id) retained = ""; }
    }
    property QtObject probeServices: QtObject {
        readonly property var network: root.nativeServices.network
        readonly property var power: root.nativeServices.power
        readonly property var popups: root.nativeServices.popups
        readonly property var audio: root.fakeAudio
        function text(uk, en) { return en; }
    }

    PanelWindow {
        visible: true
        anchors { top: true; left: true; right: true }
        implicitHeight: 40
        exclusiveZone: 0
        color: "transparent"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
        Item {
            objectName: "pentad-bar-face"
            anchors.fill: parent
            StatusCluster { id: cluster; x: 600; services: root.probeServices }
        }
    }

    function indicator(kind) { return named(cluster, "audio-indicator-" + kind).parent; }
    function click(item, x, y) {
        pointer.mouseClick(item, x, y, Qt.LeftButton, Qt.NoModifier, 0);
    }
    function lastCall() { return fakeAudio.calls.length ? fakeAudio.calls[fakeAudio.calls.length - 1] : ""; }

    Timer {
        id: sequence
        interval: 150
        repeat: true
        running: true
        property int step: 0
        onTriggered: {
            step++;
            const output = root.indicator("output");
            const content = output.menu.contentItem;
            if (step === 1) {
                output.openMenu();
            } else if (step === 5) {
                const level = root.named(content, "audio-level-output");
                const mute = root.named(content, "audio-mute-output");
                const apps = root.named(content, "audio-applications");
                root.check("popup-shows-level-mute-and-applications", output.menu.opened && !!level && !!mute && !!apps
                    && apps.visible && level.visible && level.valueText === "64%");
                root.check("popup-lists-both-applications", !!root.named(content, "mixer-stream-s1")
                    && !!root.named(content, "mixer-stream-s2"));
                root.check("popup-holds-the-mixer-while-open", root.fakeAudio.retained === "bar-sound-popup",
                    root.fakeAudio.retained);
                // A click on the bar sets the value under it; a press alone must not jump the volume.
                root.pointer.mousePress(level, level.width * 0.7, level.height / 2, Qt.LeftButton, Qt.NoModifier, 0);
                root.check("level-press-does-not-jump", root.fakeAudio.calls.length === 0);
                root.pointer.mouseMove(level, level.width * 0.8, level.height / 2, 0, Qt.LeftButton, Qt.NoModifier);
                root.pointer.mouseRelease(level, level.width * 0.8, level.height / 2, Qt.LeftButton, Qt.NoModifier, 0);
                root.check("level-drag-sets-output-volume", root.lastCall().indexOf("volume:output:") === 0
                    && Math.abs(root.fakeAudio.outputVolume - 0.74) < 0.03, JSON.stringify(root.fakeAudio.calls));
            } else if (step === 6) {
                const mute = root.named(content, "audio-mute-output");
                root.click(mute, mute.width / 2, mute.height / 2);
                root.check("icon-mutes-output", root.lastCall() === "mute:output" && root.fakeAudio.outputMuted);
                const stream = root.named(content, "mixer-volume-s1");
                const grab = stream.width * 0.5;
                root.pointer.mousePress(stream, grab, stream.height / 2, Qt.LeftButton, Qt.NoModifier, 0);
                root.pointer.mouseMove(stream, grab + stream.width * 0.2, stream.height / 2, 0, Qt.LeftButton, Qt.NoModifier);
                root.pointer.mouseRelease(stream, grab + stream.width * 0.2, stream.height / 2, Qt.LeftButton, Qt.NoModifier, 0);
                root.check("application-drag-sets-only-its-volume", root.lastCall().indexOf("stream-volume:s1:") === 0
                    && Math.abs(root.fakeAudio.streamVolumes.s1 - 0.8) < 0.05 && root.fakeAudio.streamVolumes.s2 === 0.3,
                    JSON.stringify(root.fakeAudio.calls));
                const streamMute = root.named(content, "mixer-mute-s2");
                root.click(streamMute, streamMute.width / 2, streamMute.height / 2);
                root.check("application-icon-mutes-its-stream", root.lastCall() === "stream-mute:s2"
                    && root.fakeAudio.streamMutes.s2 && !root.fakeAudio.streamMutes.s1);
                const options = [];
                const collect = function(item) {
                    if (!item) return;
                    if (item.objectName === "audio-device-option" && item.visible) options.push(item.text);
                    for (const child of item.children || []) collect(child);
                };
                collect(content);
                root.check("popup-still-lists-devices", options.join(" | ") === "Headphones | Speakers",
                    options.join(" | "));
            } else if (step === 9) {
                output.menu.surface.grabToImage(function(result) {
                    root.check("popup-capture", !root.capture || result.saveToFile(root.capture));
                });
            } else if (step === 12) {
                root.applyTheme(root.appearance === "dark" ? "light" : "dark", root.reduced);
            } else if (step === 16) {
                output.menu.surface.grabToImage(function(result) {
                    root.check("popup-capture-other-theme", !root.capture || result.saveToFile(root.capture + ".other-theme.png"));
                });
            } else if (step === 19) {
                output.menu.close();
            } else if (step === 22) {
                root.check("closing-releases-the-mixer", root.fakeAudio.retained === "", root.fakeAudio.retained);
                root.indicator("input").openMenu();
            } else if (step === 27) {
                const input = root.indicator("input");
                const level = root.named(input.menu.contentItem, "audio-level-input");
                const apps = root.named(input.menu.contentItem, "audio-applications");
                root.check("microphone-popup-has-level-and-no-applications", input.menu.opened && !!level
                    && level.valueText === "40%" && !!apps && !apps.visible);
                input.menu.close();
            } else if (step === 30) {
                sequence.running = false;
                root.applyTheme(root.appearance, root.reduced);
                console.log("PENTAD_TEST " + JSON.stringify({
                    status: root.checks.every(item => item.passed) ? "pass" : "fail",
                    checks: root.checks
                }));
                Qt.quit();
            }
        }
    }
}
