import QtQuick
import Quickshell
import qs.theme
import qs.features.bar

ShellRoot {
    id: root
    property string activeId: "1"
    property var state: ({ kind: "ready", value: {
        outputs: [{ id: "preview", name: "preview", activeWorkspaceId: root.activeId }],
        workspaces: Array.from({ length: 24 }, function(_, index) {
            const id = String(index + 1);
            return { id: id, name: id, monitor: "preview", special: false, active: id === root.activeId, occupied: false };
        }),
        focusedOutputId: "preview", activeTitle: "Fixture", activeClass: "fixture"
    } })
    property QtObject services: QtObject {
        readonly property QtObject hyprland: QtObject {
            readonly property var state: root.state
            function focusWorkspace(id) {}
        }
    }
    property var checks: []
    property int phase: 0

    function check(name, passed, detail) {
        checks.push({ name: name, passed: passed === true, detail: detail || "" });
    }
    function findNamedItem(item, name) {
        if (!item) return null;
        if (item.objectName === name) return item;
        const children = item.children || [];
        for (let index = 0; index < children.length; index++) {
            const found = findNamedItem(children[index], name);
            if (found) return found;
        }
        return null;
    }
    function finish() {
        const passed = checks.every(function(item) { return item.passed; });
        console.log("PENTAD_TEST " + JSON.stringify({ status: passed ? "pass" : "fail", checks: checks }));
        Qt.quit();
    }

    Component.onCompleted: Theme.resolve({ appearance: "dark", accent: "#869677", fontFamily: "Geist", reducedMotion: false });

    FloatingWindow {
        visible: true
        implicitWidth: 500
        implicitHeight: 60
        color: Theme.tokens.surface
        WorkspaceSwitcher {
            id: switcher
            objectName: "workspace-switcher"
            x: 8
            y: 10
            services: root.services
            outputId: "preview"
            barRegionHovered: false
        }
    }

    Timer {
        interval: 25
        repeat: true
        running: true
        onTriggered: {
            phase++;
            if (phase === 1) {
                switcher.barRegionHovered = true;
            } else if (phase === 2) {
                check("expansion-samples-intermediate-layout-width", switcher.width > 36 && switcher.width < 300, String(switcher.width));
                const strip = root.findNamedItem(switcher, "workspace-strip");
                check("face-crossfade-samples-intermediate-opacity", strip && strip.opacity > 0 && strip.opacity < 1,
                    strip ? String(strip.opacity) : "strip missing");
                root.activeId = "24";
            } else if (phase === 3) {
                const indicator = root.findNamedItem(switcher, "active-workspace-indicator");
                check("selection-indicator-reverses-from-current-position", indicator && indicator.x > 0 && indicator.x < 23 * switcher.slotStride,
                    indicator ? String(indicator.x) : "indicator missing");
                root.activeId = "2";
            } else if (phase === 4) {
                const indicator = root.findNamedItem(switcher, "active-workspace-indicator");
                check("selection-reversal-starts-from-current-position", indicator && indicator.x > switcher.slotStride + switcher.circleInset && indicator.x < 23 * switcher.slotStride,
                    indicator ? String(indicator.x) : "indicator missing");
            } else if (phase === 14) {
                const indicator = root.findNamedItem(switcher, "active-workspace-indicator");
                check("expanded-width-and-height-settle", switcher.width === 300 && switcher.height === 40
                    && root.findNamedItem(switcher, "workspace-capsule").height === 36);
                check("selection-reversal-settles-at-confirmed-workspace", indicator && indicator.x === switcher.slotStride + switcher.circleInset,
                    indicator ? String(indicator.x) : "indicator missing");
                check("selection-indicator-has-no-perimeter-border", indicator && indicator.border.width === 0
                    && indicator.color.toString() === Qt.alpha(Theme.tokens.text, 0.35).toString()
                    && root.findNamedItem(switcher, "workspace-capsule").border.width === 0,
                    indicator ? JSON.stringify({ border: indicator.border.width, capsuleBorder: root.findNamedItem(switcher, "workspace-capsule").border.width, color: indicator.color.toString(), expected: Qt.alpha(Theme.tokens.text, 0.35).toString() }) : "indicator missing");
                const icon = root.findNamedItem(switcher, "expanded-workspace-icon");
                check("expanded-icons-have-readable-size", icon && icon.width === 22 && icon.height === 22);
                root.activeId = "24";
            } else if (phase === 25) {
                const indicator = root.findNamedItem(switcher, "active-workspace-indicator");
                const strip = root.findNamedItem(switcher, "workspace-strip");
                check("confirmed-active-slot-settles-and-remains-visible", indicator && indicator.x === 23 * switcher.slotStride + switcher.circleInset && strip
                    && indicator.x - switcher.circleInset - strip.contentX >= 0 && indicator.x - switcher.circleInset - strip.contentX + switcher.slotSize <= strip.width,
                    indicator && strip ? JSON.stringify({ x: indicator.x, contentX: strip.contentX, width: strip.width }) : "indicator or strip missing");
                switcher.barRegionHovered = false;
            } else if (phase === 26) {
                check("reversal-samples-intermediate-width", switcher.width > 36 && switcher.width < 300, String(switcher.width));
                switcher.barRegionHovered = true;
            } else if (phase === 27) {
                check("layout-reversal-samples-intermediate-width", switcher.width > 36 && switcher.width < 300, String(switcher.width));
                switcher.presentationSuppressed = true;
            } else if (phase === 28) {
                check("suppression-overrides-hover-expansion", !switcher.expanded && switcher.width < 300);
                Theme.resolve(Object.assign({}, Theme.config, { reducedMotion: true }));
                switcher.presentationSuppressed = false;
                switcher.barRegionHovered = true;
            } else if (phase === 29) {
                check("reduced-motion-snaps-geometry-and-opacity", switcher.width === 300
                    && root.findNamedItem(switcher, "workspace-strip").opacity === 1
                    && root.findNamedItem(switcher, "collapsed-face").opacity === 0,
                    JSON.stringify({ width: switcher.width,
                        expandedOpacity: root.findNamedItem(switcher, "workspace-strip").opacity,
                        collapsedOpacity: root.findNamedItem(switcher, "collapsed-face").opacity }));
                switcher.barRegionHovered = false;
                root.findNamedItem(switcher, "workspace-capsule").forceActiveFocus();
            } else if (phase === 30) {
                check("keyboard-focus-on-capsule-expands-strip", switcher.expanded
                    && root.findNamedItem(switcher, "workspace-capsule").activeFocus
                    && root.findNamedItem(switcher, "workspace-capsule").color.toString().toLowerCase() === Theme.tokens.surfaceOverlay.toString().toLowerCase(),
                    JSON.stringify({ expanded: switcher.expanded,
                        activeFocus: root.findNamedItem(switcher, "workspace-capsule").activeFocus,
                        color: root.findNamedItem(switcher, "workspace-capsule").color.toString(),
                        expected: Theme.tokens.surfaceOverlay.toString() }));
                root.findNamedItem(switcher, "workspace-focus-target-24").forceActiveFocus();
                switcher.held = true;
            } else if (phase === 31) {
                const icon = root.findNamedItem(switcher, "expanded-workspace-icon");
                const number = root.findNamedItem(switcher, "expanded-workspace-fallback-24");
                check("super-icons-and-numbers-have-readable-size", icon && icon.width === 22 && icon.opacity < 0.5
                    && icon.anchors.horizontalCenterOffset === 0 && icon.anchors.verticalCenterOffset === 0
                    && number && number.font.pixelSize === 17 && number.opacity > 0.9
                    && number.anchors.horizontalCenterOffset === 0 && number.anchors.verticalCenterOffset === 0);
                const focusTarget = root.findNamedItem(switcher, "workspace-focus-target-24");
                const focusText = root.findNamedItem(switcher, "expanded-workspace-fallback-24");
                const focusBackground = root.findNamedItem(switcher, "workspace-slot-background-24");
                check("keyboard-focus-uses-borderless-tonal-foreground", focusTarget && focusTarget.activeFocus
                    && focusText.color.toString().toLowerCase() === Theme.tokens.text.toString().toLowerCase() && focusText.font.weight === 700
                    && Math.abs(focusBackground.color.a - 0.1) < 0.001 && focusBackground.border.width === 0,
                    JSON.stringify({ activeFocus: focusTarget && focusTarget.activeFocus,
                        textColor: focusText && focusText.color.toString(), textExpected: Theme.tokens.text.toString(),
                        weight: focusText && focusText.font.weight, background: focusBackground && focusBackground.color.toString(),
                        alpha: focusBackground && focusBackground.color.a }));
            } else if (phase === 32) {
                switcher.grabToImage(function(result) {
                    check("held-workspace-capsule-capture", result.saveToFile(Quickshell.env("PENTAD_ARTIFACT_PATH")));
                    finish();
                });
            }
        }
    }
}
