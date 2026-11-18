import QtQuick
import QtQuick.Window
import QtTest
import Quickshell
import Quickshell.Io
import qs.plugins

ShellRoot {
    id: root
    property TestEvent pointer: TestEvent {}
    property var checks: []
    property int serial: 0
    property bool manifestReady: false
    property var initialStreams: []

    QtObject {
        id: audio
        property bool active: true
        property bool preview: false
        property bool safeMode: false
        property var requests: []
        property var retained: ({})
        property var retainEvents: []
        property var state: ({ kind: "ready", value: { streams: [
            { id: "s1", nodeId: "41", appName: "Browser", label: "Browser", mediaName: "Music tab", icon: "", volume: 0.42, muted: false, pendingVolume: false, pendingMute: false, requestedVolume: 0.42 },
            { id: "s2", nodeId: "42", appName: "Browser", label: "Browser", mediaName: "Video tab", icon: "", volume: 0.68, muted: false, pendingVolume: false, pendingMute: false, requestedVolume: 0.68 },
            { id: "s3", nodeId: "51", appName: "Player", label: "Player", mediaName: "Local track", icon: "", volume: 0.31, muted: false, pendingVolume: false, pendingMute: false, requestedVolume: 0.31 }
        ] } })
        signal commandFinished(string requestId, var result)
        function stream(id) { return state.value.streams.find(function(item) { return item.id === id; }) || null; }
        function update(id, patch) {
            var value = Object.assign({}, state.value);
            value.streams = value.streams.map(function(item) { return item.id === id ? Object.assign({}, item, patch) : item; });
            state = { kind: state.kind, value: value };
        }
        function setStreamVolume(id, value) {
            var requestId = "mixer-" + (++root.serial);
            requests = requests.concat([{ id: id, kind: "volume", value: value, requestId: requestId }]);
            update(id, { pendingVolume: true, requestedVolume: value });
            return requestId;
        }
        function toggleStreamMute(id) {
            var requestId = "mixer-" + (++root.serial);
            requests = requests.concat([{ id: id, kind: "mute", requestId: requestId }]);
            update(id, { pendingMute: true });
            return requestId;
        }
        function retainMixer(id) {
            if (retained[id]) return;
            retained = Object.assign({}, retained, { [id]: true });
            retainEvents = retainEvents.concat(["retain:" + id]);
        }
        function releaseMixer(id) {
            if (!retained[id]) return;
            var next = Object.assign({}, retained);
            delete next[id];
            retained = next;
            retainEvents = retainEvents.concat(["release:" + id]);
        }
        function complete(requestId, ok) {
            var request = requests.find(function(item) { return item.requestId === requestId; });
            if (!request) return;
            var item = stream(request.id);
            if (item) {
                if (request.kind === "volume") update(request.id, Object.assign({ pendingVolume: false }, ok
                    ? { volume: request.value, requestedVolume: request.value } : { requestedVolume: item.volume }));
                else update(request.id, Object.assign({ pendingMute: false }, ok ? { muted: !item.muted } : {}));
            }
            commandFinished(requestId, ok ? { ok: true } : { ok: false, reason: "fixture-failure" });
        }
    }
    property QtObject fakeServices: QtObject {
        readonly property QtObject audio: audio
        function text(ukrainian, english) { return english; }
    }
    property var fakeRegistry: QtObject {
        property int revision: 0
        property var controllers: ({})
        property var entry: null
        function entryFor(id, slot) {
            if (!entry || entry.manifest.id !== id || entry.manifest.allowedSlots.indexOf(slot) < 0) return null;
            return entry;
        }
    }
    property FileView mixerManifest: FileView {
        path: Qt.resolvedUrl("widgets/audio-mixer/manifest.json")
        printErrors: false
        onLoaded: {
            try {
                root.fakeRegistry.entry = { manifest: JSON.parse(text()),
                    baseUrl: Qt.resolvedUrl("widgets/audio-mixer/"), builtin: true };
                root.fakeRegistry.revision++;
                root.manifestReady = true;
            } catch (error) { root.check("mixer-manifest-loaded", false, error.message); }
        }
    }

    function check(name, passed, detail) {
        checks = checks.concat([{ name: name, passed: passed === true, detail: detail || "" }]);
    }
    function consumerContains(fragment) {
        return Object.keys(audio.retained).some(function(id) { return id.indexOf(fragment) >= 0; });
    }
    function findNamed(item, name) {
        if (!item) return null;
        if (item.objectName === name) return item;
        for (const child of item.children || []) {
            const found = findNamed(child, name);
            if (found) return found;
        }
        return null;
    }
    function findSlider(item, name) {
        if (!item) return null;
        if (item.objectName === name && item.pressed !== undefined && item.value !== undefined) return item;
        for (const child of item.children || []) {
            const found = findSlider(child, name);
            if (found) return found;
        }
        return null;
    }
    function findText(item, value) {
        if (!item) return null;
        if (item.text === value) return item;
        for (const child of item.children || []) {
            const found = findText(child, value);
            if (found) return found;
        }
        return null;
    }
    function finish() {
        var passed = checks.length > 0 && checks.every(function(item) { return item.passed; });
        console.log("PENTAD_TEST " + JSON.stringify({ status: passed ? "pass" : "fail", checks: checks }));
        Qt.quit();
    }

    FloatingWindow {
        id: fixtureWindow
        visible: true
        implicitWidth: 900
        implicitHeight: 600
        color: "#101210"
        Rectangle {
            id: gallery
            anchors.fill: parent
            anchors.margins: 20
            radius: 22
            color: "#1b1e1b"
            Row {
                anchors.fill: parent
                anchors.margins: 20
                spacing: 28
                Column {
                    width: 180
                    spacing: 10
                    Text { text: "TOOLS · COMPACT"; color: "#b4c0b0" }
                    PluginHost {
                        id: toolsHost
                        width: 150
                        height: 58
                        instanceId: "mixer-tools-fixture"
                        moduleId: "pentad.audio-mixer"
                        context: ({ outputId: "fixture", slot: "tools", compact: true, preview: false, presented: false })
                        settings: ({})
                        services: root.fakeServices
                        registry: root.fakeRegistry
                    }
                    Text { text: "The trigger opens the shared mixer popover."; color: "#a5aaa2"; wrapMode: Text.Wrap; width: 160 }
                }
                Rectangle {
                    width: 1
                    height: parent.height
                    color: "#393e39"
                }
                Column {
                    width: 360
                    spacing: 10
                    Text { text: "SIDEBAR-RIGHT · INLINE"; color: "#b4c0b0" }
                    PluginHost {
                        id: sidebarHost
                        width: 340
                        height: 500
                        instanceId: "mixer-sidebar-fixture"
                        moduleId: "pentad.audio-mixer"
                        context: ({ outputId: "fixture", slot: "sidebar-right", compact: false, preview: false, presented: true })
                        settings: ({})
                        services: root.fakeServices
                        registry: root.fakeRegistry
                    }
                }
            }
        }
    }

    TestCase {
        id: testCase
        name: "ApplicationMixer"
        when: false

        function test_applicationMixer() {
            wait(80);
            root.initialStreams = audio.state.value.streams.map(function(item) { return Object.assign({}, item); });
            root.check("manifest-read-from-fileview-and-hosts-allowed-slots",
                root.manifestReady && toolsHost.entry !== null && sidebarHost.entry !== null,
                JSON.stringify({ ready: root.manifestReady, tools: !!toolsHost.entry, sidebar: !!sidebarHost.entry }));
            root.check("two-native-plugin-host-forms-loaded", !!toolsHost.view && !!sidebarHost.view
                && toolsHost.view.context.slot === "tools" && sidebarHost.view.context.slot === "sidebar-right");
            root.check("same-application-keeps-two-independent-stream-rows",
                audio.state.value.streams.filter(function(item) { return item.appName === "Browser"; }).length === 2
                && audio.stream("s1").id !== audio.stream("s2").id);
            root.check("passive-state-renders-without-writing", audio.requests.length === 0
                && !!root.findNamed(sidebarHost.view, "mixer-volume-s1")
                && !!root.findNamed(sidebarHost.view, "mixer-mute-s3"));
            root.check("sidebar-retains-audio-consumer-while-presented", Object.keys(audio.retained).length === 1
                && root.consumerContains("mixer-sidebar-fixture"), JSON.stringify(audio.retainEvents));

            var stableSlider = root.findSlider(sidebarHost.view, "mixer-volume-s2");
            audio.update("s1", {volume: 0.41, requestedVolume: 0.41});
            wait(30);
            root.check("passive-volume-update-preserves-other-native-slider", !!stableSlider
                && stableSlider === root.findSlider(sidebarHost.view, "mixer-volume-s2")
                && audio.requests.length === 0);

            var volume = root.findSlider(sidebarHost.view, "mixer-volume-s2");
            root.check("native-slider-found-for-second-stream", !!volume, volume ? "Qt Quick Slider" : "missing native Slider");
            if (volume) {
                var targetX = volume.width * 0.78;
                root.check("native-pointer-changes-only-the-target-stream",
                    pointer.mouseClick(volume, targetX, volume.height / 2, Qt.LeftButton, Qt.NoModifier, 0)
                    && audio.requests.length >= 1 && audio.requests.every(function(request) { return request.kind === "volume" && request.id === "s2"; })
                    && audio.stream("s1").requestedVolume === audio.stream("s1").volume
                    && audio.stream("s2").pendingVolume === true,
                    JSON.stringify(audio.requests));
                root.check("pending-volume-keeps-confirmed-value-separate", audio.stream("s2").volume === 0.68
                    && audio.stream("s2").requestedVolume > 0.68);
                const volumeRequests = audio.requests.slice();
                for (const request of volumeRequests) audio.complete(request.requestId, true);
                wait(30);
                root.check("confirmed-volume-readback-clears-pending", audio.stream("s2").volume > 0.68
                    && !audio.stream("s2").pendingVolume);
                root.check("pending-and-confirmed-updates-preserve-active-slider", volume
                    === root.findSlider(sidebarHost.view, "mixer-volume-s2"));
            }

            var mute = root.findNamed(sidebarHost.view, "mixer-mute-s3");
            root.check("native-mute-button-found-for-third-stream", !!mute);
            if (mute) {
                const beforeMute = audio.requests.length;
                pointer.mouseClick(mute, mute.width / 2, mute.height / 2, Qt.LeftButton, Qt.NoModifier, 0);
                root.check("mute-command-is-keyed-to-independent-stream", audio.requests.length === beforeMute + 1
                    && audio.requests[beforeMute].kind === "mute" && audio.requests[beforeMute].id === "s3"
                    && !audio.stream("s1").muted && !audio.stream("s2").muted && audio.stream("s3").pendingMute);
                audio.complete(audio.requests[beforeMute].requestId, true);
                wait(30);
                root.check("confirmed-mute-applies-to-only-third-stream", audio.stream("s3").muted
                    && !audio.stream("s1").muted && !audio.stream("s2").muted);
            }

            volume = root.findSlider(sidebarHost.view, "mixer-volume-s1");
            if (volume) pointer.mouseClick(volume, volume.width * 0.88, volume.height / 2, Qt.LeftButton, Qt.NoModifier, 0);
            var failedRequest = audio.requests.length ? audio.requests[audio.requests.length - 1] : null;
            if (failedRequest && failedRequest.id === "s1") audio.complete(failedRequest.requestId, false);
            wait(40);
            root.check("failed-write-shows-row-local-error", !!failedRequest && failedRequest.id === "s1"
                && !!root.findText(sidebarHost.view, "fixture-failure"), failedRequest ? failedRequest.requestId : "no request");

            var reordered = [audio.stream("s3"), audio.stream("s1"), audio.stream("s2")];
            var value = Object.assign({}, audio.state.value, { streams: reordered });
            audio.state = { kind: "ready", value: value };
            wait(30);
            var reorderedSlider = !!root.findNamed(sidebarHost.view, "mixer-volume-s1");
            var reorderedError = !!root.findText(sidebarHost.view, "fixture-failure");
            root.check("reorder-preserves-stream-ids-and-row-error", reorderedSlider && reorderedError
                && audio.state.value.streams.map(function(item) { return item.id; }).join(",") === "s3,s1,s2",
                JSON.stringify({ slider: reorderedSlider, error: reorderedError,
                    order: audio.state.value.streams.map(function(item) { return item.id; }) }));
            value = Object.assign({}, audio.state.value, { streams: [audio.stream("s3"), audio.stream("s2")] });
            audio.state = { kind: "ready", value: value };
            wait(30);
            root.check("removed-stream-disappears-without-changing-survivors", !root.findNamed(sidebarHost.view, "mixer-volume-s1")
                && !!root.findNamed(sidebarHost.view, "mixer-volume-s2") && audio.stream("s2").id === "s2");

            audio.state = { kind: "ready", value: { streams: [] } };
            wait(30);
            root.check("empty-available-state-is-rendered", !!root.findText(sidebarHost.view, "No active audio streams"));
            audio.state = { kind: "unavailable", error: "Audio service unavailable" };
            wait(30);
            root.check("unavailable-state-is-rendered", !!root.findText(sidebarHost.view, "Audio is unavailable"));
            audio.state = { kind: "ready", value: { streams: [
                Object.assign({}, root.initialStreams.find(function(item) { return item.id === "s1"; }),
                    { id: "s1-next", nodeId: "41-next", mediaName: "New process" }),
                root.initialStreams.find(function(item) { return item.id === "s2"; }),
                root.initialStreams.find(function(item) { return item.id === "s3"; })
            ] } };
            wait(30);
            root.check("removed-stream-error-does-not-leak-to-new-lifetime-token",
                !root.findNamed(sidebarHost.view, "mixer-volume-s1")
                && !!root.findNamed(sidebarHost.view, "mixer-volume-s1-next")
                && !root.findText(sidebarHost.view, "fixture-failure"));

            var dragSlider = root.findSlider(sidebarHost.view, "mixer-volume-s2");
            const beforeDrag = audio.requests.length;
            if (dragSlider) {
                pointer.mousePress(dragSlider, dragSlider.width * 0.4, dragSlider.height / 2, Qt.LeftButton, Qt.NoModifier, 0);
                wait(20);
                pointer.mouseMove(dragSlider, dragSlider.width * 0.6, dragSlider.height / 2, 0, Qt.LeftButton, Qt.NoModifier);
                wait(20);
                pointer.mouseMove(dragSlider, dragSlider.width * 0.8, dragSlider.height / 2, 0, Qt.LeftButton, Qt.NoModifier);
                pointer.mouseRelease(dragSlider, dragSlider.width * 0.8, dragSlider.height / 2, Qt.LeftButton, Qt.NoModifier, 0);
            }
            const dragRequests = audio.requests.slice(beforeDrag);
            root.check("native-drag-survives-reactive-snapshots-and-targets-one-stream", !!dragSlider
                && dragSlider === root.findSlider(sidebarHost.view, "mixer-volume-s2")
                && dragRequests.length >= 2 && dragRequests.every(function(request) { return request.id === "s2"; }),
                JSON.stringify(dragRequests));
            for (const request of dragRequests) audio.complete(request.requestId, true);

            var popup = toolsHost.view.popup;
            if (popup) popup.grabFocus = false;
            root.check("compact-popup-is-focusless-in-fixture", !!popup && popup.grabFocus === false);
            var trigger = root.findNamed(toolsHost.view, "mixer-trigger");
            root.check("compact-trigger-found", !!trigger);
            if (trigger) {
                root.check("right-click-opens-native-attached-popup", pointer.mouseClick(trigger,
                    trigger.width / 2, trigger.height / 2, Qt.RightButton, Qt.NoModifier, 0));
                wait(40);
                root.check("popup-open-and-size-is-compact", popup.opened && popup.window.surfaceWidth > 0 && popup.window.surfaceWidth < 420
                    && popup.window.surfaceHeight > 0 && popup.window.surfaceHeight <= 380,
                    JSON.stringify({ opened: popup.opened, width: popup.window.surfaceWidth, height: popup.window.surfaceHeight }));
                if (popup.opened) popup.close();
                trigger.forceActiveFocus(Qt.OtherFocusReason);
                wait(30);
                var activeFocusItem = fixtureWindow.contentItem.Window.window.activeFocusItem;
                root.check("compact-trigger-receives-real-window-focus", activeFocusItem === trigger,
                    activeFocusItem ? activeFocusItem.objectName : "no active focus item");
                root.check("space-opens-popup-from-keyboard", pointer.keyClick(Qt.Key_Space, Qt.NoModifier, 0));
                wait(40);
                root.check("keyboard-opened-popup-and-retains-consumer", popup.opened
                    && root.consumerContains("mixer-sidebar-fixture") && root.consumerContains("mixer-tools-fixture")
                    && Object.keys(audio.retained).length === 2,
                    JSON.stringify(audio.retainEvents));
            }

            var artifact = Quickshell.env("PENTAD_ARTIFACT_PATH");
            if (artifact && popup && popup.opened) {
                popup.contentItem.grabToImage(function(popupResult) {
                    root.check("native-mixer-popup-content-captured", popupResult.saveToFile(artifact + ".mixer-popover.png"));
                    gallery.grabToImage(function(galleryResult) {
                        root.check("application-mixer-gallery-captured", galleryResult.saveToFile(artifact));
                        popup.close();
                        wait(30);
                        root.check("closing-popup-releases-only-compact-consumer", !root.consumerContains("mixer-tools-fixture")
                            && root.consumerContains("mixer-sidebar-fixture"));
                        trigger.forceActiveFocus(Qt.OtherFocusReason);
                        pointer.keyClick(Qt.Key_Return, Qt.NoModifier, 0);
                        wait(30);
                        root.check("enter-opens-compact-mixer", popup.opened);
                        toolsHost.visible = false;
                        wait(30);
                        root.check("hidden-bar-host-closes-popup-and-releases-consumer", !popup.opened
                            && !root.consumerContains("mixer-tools-fixture"));
                        sidebarHost.context = Object.assign({}, sidebarHost.context, {presented: false});
                        wait(30);
                        root.check("hidden-menu-releases-last-consumer", Object.keys(audio.retained).length === 0);
                        root.finish();
                    });
                });
            } else {
                root.check("native-mixer-popup-content-captured", false, "popup or artifact path unavailable");
                root.check("application-mixer-gallery-captured", false, "artifact path unavailable");
                root.finish();
            }
        }
    }

    Timer {
        interval: 120
        running: true
        repeat: false
        onTriggered: {
            if (root.manifestReady) testCase.test_applicationMixer();
            else {
                root.check("mixer-manifest-loaded", false, "FileView did not finish loading");
                root.finish();
            }
        }
    }
}
