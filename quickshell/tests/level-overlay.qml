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
        outputId: "fixture-output"
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
            root.finish();
        }
    }
    Timer {
        interval: 10000; running: true
        onTriggered: { root.check("fixture-completed-before-deadline", false, "stage timeout"); root.finish(); }
    }
}
