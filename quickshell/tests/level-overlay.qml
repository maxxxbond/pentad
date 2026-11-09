import QtQuick
import Quickshell
import qs.components
import qs.services
import qs.theme
import qs.features.system

ShellRoot {
    id: root
    property var checks: []
    readonly property string artifact: Quickshell.env("PENTAD_ARTIFACT_PATH") || ""

    property Services services: Services { preview: true; safeMode: true }
    property var fakeBrightness: QtObject {
        property bool active: true
        property bool safeMode: false
        property var state: ({ kind: "ready", value: 0.4 })
        property var desiredValue: null
        property var operation: null
        signal commandFinished(string requestId, var result)
        function nudge(steps) { return ""; }
        function adjust(steps) { return ""; }
    }

    // A grab of a surface stops at its own bounds, so the shared shadow is sampled on a mid-grey desktop
    // backdrop with the same room the shell windows keep.
    FloatingWindow {
        implicitWidth: 360
        implicitHeight: 200
        color: "transparent"
        Rectangle {
            id: shadowSample
            anchors.fill: parent
            color: "#7d8590"
            ContinuousSurface {
                x: Metrics.overlayShadowRoom * 2; y: Metrics.overlayShadowRoom * 2
                width: parent.width - 4 * Metrics.overlayShadowRoom
                height: parent.height - 4 * Metrics.overlayShadowRoom
                extent: Metrics.radiusCard
                fill: Theme.tokens.surfaceRaised
                castsShadow: true
            }
        }
    }
    LevelOverlay {
        id: overlay
        services: root.services
        // Audio feedback flashes only on the focused output; preview Hyprland reports its own outputs.
        outputId: root.services.hyprland.state.value.focusedOutputId || "fixture-output"
        brightness: root.fakeBrightness
    }

    function check(name, passed, detail) { checks.push({ name: name, passed: passed === true, detail: detail || "" }); }
    function find(item, name) {
        if (!item) return null;
        if (item.objectName === name) return item;
        const children = item.children || [];
        for (let i = 0; i < children.length; ++i) {
            const found = find(children[i], name);
            if (found) return found;
        }
        return null;
    }
    function ring() { return find(overlay.contentItem, "level-ring"); }
    function near(a, b) { return Math.abs(a - b) < 0.011; }
    function capture(suffix, next) {
        if (!artifact) { check("capture" + suffix, false, "no artifact path"); next(); return; }
        root.find(overlay.contentItem, "level-card").grabToImage(function(result) {
            check("capture" + (suffix || ".rising"), result.saveToFile(artifact + suffix));
            next();
        });
    }
    function finish() {
        console.log("PENTAD_TEST " + JSON.stringify({ status: checks.length > 0 && checks.every(function(item) { return item.passed; }) ? "pass" : "fail", checks: checks }));
        Qt.quit();
    }

    // Rising: the wheel asks for 70 % while the screen is still at 40 %.
    Timer {
        interval: 200; running: true
        onTriggered: { root.fakeBrightness.desiredValue = 0.7; risingSettle.start(); }
    }
    Timer {
        id: risingSettle; interval: 700
        onTriggered: {
            const r = root.ring();
            root.check("rising-shows-desired-as-main-value", overlay.shown && overlay.kind === "brightness" && root.near(r.displayed, 0.7),
                JSON.stringify({ shown: overlay.shown, kind: overlay.kind, displayed: r && r.displayed }));
            root.check("rising-keeps-actual-on-the-same-track", r && root.near(r.actual, 0.4), String(r && r.actual));
            root.capture("", function() {
                // The hardware catches up: the faint stretch closes instead of vanishing.
                root.fakeBrightness.state = { kind: "ready", value: 0.55 };
                midway.start();
            });
        }
    }
    Timer {
        id: midway; interval: 700
        onTriggered: {
            const r = root.ring();
            root.check("partial-progress-narrows-the-gap", root.near(r.actual, 0.55) && root.near(r.displayed, 0.7),
                JSON.stringify({ actual: r.actual, displayed: r.displayed }));
            root.fakeBrightness.state = { kind: "ready", value: 0.7 };
            root.fakeBrightness.desiredValue = null;
            overlay.present("brightness", 0.7, false, "Brightness", 1500, false);
            settled.start();
        }
    }
    Timer {
        id: settled; interval: 700
        onTriggered: {
            const r = root.ring();
            root.check("settled-gap-is-closed", root.near(r.actual, 0.7) && root.near(r.displayed, 0.7) && overlay.shown,
                JSON.stringify({ actual: r.actual, displayed: r.displayed, shown: overlay.shown }));
            root.capture(".settled.png", function() {
                // Dimming: the faint stretch now trails behind, still lit until the screen follows.
                root.fakeBrightness.desiredValue = 0.3;
                falling.start();
            });
        }
    }
    Timer {
        id: falling; interval: 700
        onTriggered: {
            const r = root.ring();
            root.check("falling-shows-desired-below-actual", root.near(r.displayed, 0.3) && root.near(r.actual, 0.7),
                JSON.stringify({ actual: r.actual, displayed: r.displayed }));
            root.capture(".falling.png", function() {
                shadowSample.grabToImage(function(result) {
                    root.check("capture.shadow-sample", result.saveToFile(root.artifact + ".shadow.png"));
                    // Keyboard layout: a discrete indicator with the new layout's code and name, no ring.
                    overlay.present("layout", null, false, "English (US)", 1200, false, "US");
                    layoutShown.start();
                });
            });
        }
    }
    Timer {
        id: layoutShown; interval: 300
        onTriggered: {
            const r = root.ring();
            const value = root.find(overlay.contentItem, "level-value");
            root.check("layout-shows-the-new-layout", overlay.shown && overlay.kind === "layout" && overlay.discreteText === "US",
                JSON.stringify({ shown: overlay.shown, kind: overlay.kind, label: overlay.discreteText }));
            root.check("layout-label-is-rendered", !!value && value.text === "US", value && value.text);
            root.check("layout-names-the-layout", overlay.message === "English (US)", overlay.message);
            root.check("layout-draws-no-level-ring", !!r && root.near(r.displayed, 0) && root.near(r.actual, 0),
                JSON.stringify({ displayed: r && r.displayed, actual: r && r.actual }));
            root.capture(".layout.png", function() { layoutHidden.start(); });
        }
    }
    Timer {
        id: layoutHidden; interval: 1500
        onTriggered: {
            root.check("layout-hides-after-its-timeout", overlay.shown === false, String(overlay.shown));
            // Microphone capture: a discrete warning-tinted card naming the application that started listening.
            overlay.present("capture", null, false, "Listening to the microphone", 3000, false, "Handy");
            captureShown.start();
        }
    }
    Timer {
        id: captureShown; interval: 300
        onTriggered: {
            const r = root.ring();
            const value = root.find(overlay.contentItem, "level-value");
            const message = root.find(overlay.contentItem, "level-message");
            root.check("capture-shows-a-capture-card", overlay.shown && overlay.kind === "capture",
                JSON.stringify({ shown: overlay.shown, kind: overlay.kind }));
            root.check("capture-names-the-application", !!value && value.text === "Handy", value && value.text);
            root.check("capture-says-it-is-listening", !!message && message.text === "Listening to the microphone", message && message.text);
            root.check("capture-draws-no-level-ring", !!r && root.near(r.displayed, 0), String(r && r.displayed));
            root.check("capture-uses-the-warning-ink", Qt.colorEqual(overlay.ink, Theme.tokens.warning),
                JSON.stringify({ ink: String(overlay.ink), warning: String(Theme.tokens.warning) }));
            const icon = root.find(overlay.contentItem, "level-icon");
            root.check("capture-uses-the-bundled-mic-icon", !!icon && String(icon.source).endsWith("/material/media/mic-symbolic.svg"),
                icon && String(icon.source));
            root.capture(".capture-mic.png", function() {
                // A bar click silences contextual level feedback, but not the capture warning.
                root.services.audio.contextualFeedbackUntil = Date.now() + 5000;
                captureContextual.start();
            });
        }
    }
    Timer {
        id: captureContextual; interval: 100
        onTriggered: {
            root.check("capture-survives-contextual-feedback", overlay.shown === true && overlay.kind === "capture",
                JSON.stringify({ shown: overlay.shown, kind: overlay.kind }));
            // The real review path, fed fake ready states since preview audio is unavailable.
            root.services.audio.contextualFeedbackUntil = 0;
            overlay.reviewAudio(root.audioState([], false, 0.4));
            // Zoom starts listening while the output level moves in the same update: the capture card wins.
            overlay.reviewAudio(root.audioState([{ key: "zoom", label: "Zoom", icon: "", muted: false }], false, 0.6));
            root.check("capture-wins-over-a-same-update-level-change",
                overlay.shown && overlay.kind === "capture" && overlay.discreteText === "Zoom"
                    && overlay.message === overlay.tr("Слухає мікрофон", "Listening to the microphone"),
                JSON.stringify({ shown: overlay.shown, kind: overlay.kind, label: overlay.discreteText, message: overlay.message }));
            // Muting right after: the mute confirmation replaces the capture card.
            overlay.reviewAudio(root.audioState([{ key: "zoom", label: "Zoom", icon: "", muted: true }], true, 0.6));
            root.check("later-mute-replaces-the-capture-card", overlay.shown && overlay.kind === "input" && overlay.muted === true,
                JSON.stringify({ shown: overlay.shown, kind: overlay.kind, muted: overlay.muted }));
            // Handy takes over from Zoom, then stops: only the start raises a card. A marker card goes up
            // in between, so any card the stop presented would replace it.
            overlay.reviewAudio(root.audioState([{ key: "handy", label: "Handy", icon: "", muted: false }], false, 0.6));
            const started = overlay.shown && overlay.kind === "capture" && overlay.discreteText === "Handy";
            overlay.present("layout", null, false, "Marker", 1200, false, "MK");
            overlay.reviewAudio(root.audioState([], false, 0.6));
            root.check("capture-ending-shows-no-card",
                started && overlay.kind === "layout" && overlay.discreteText === "MK" && overlay.message === "Marker",
                JSON.stringify({ started: started, kind: overlay.kind, label: overlay.discreteText, message: overlay.message }));
            root.finish();
        }
    }
    function audioState(captures, micMuted, outputVolume) {
        return {
            kind: "ready",
            value: {
                input: { id: "mic", label: "Built-in microphone", volume: 0.5, muted: micMuted },
                output: { id: "speakers", label: "Speakers", volume: outputVolume, muted: false },
                microphone: { active: captures.length > 0, muted: micMuted, apps: captures }
            }
        };
    }
    Timer {
        interval: 10000; running: true
        onTriggered: { root.check("fixture-completed-before-deadline", false, "stage timeout"); root.finish(); }
    }
}
