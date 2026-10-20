import QtQuick
import QtTest
import Quickshell
import Quickshell.Wayland
import qs.theme
import qs.services
import qs.shell

ShellRoot {
    id: root
    property Services services: Services { preview: true; safeMode: true }
    property int reservedTopHeight: 40
    property var checks: []
    property var closingInputRows: []
    property var preparedRightContent: null
    property var preparedActivityContent: null
    function findNamed(item, name) {
        if (!item) return null;
        if (item.objectName === name) return item;
        for (const child of item.children || []) {
            const found = findNamed(child, name);
            if (found) return found;
        }
        return null;
    }
    property TestEvent pointer: TestEvent {}
    property PopupManager managerProbe: PopupManager {}
    property QtObject childProbe: QtObject {
        property int closedCount: 0
        function close() { closedCount++; root.managerProbe.unregisterChild(this); }
    }
    function check(name, passed, detail) {
        checks.push({ name: name, passed: passed === true, detail: detail || '' });
    }
    function captureDrawer(side, afterCapture) {
        const path = Quickshell.env('PENTAD_ARTIFACT_PATH');
        if (!path) { if (afterCapture) afterCapture(); return; }
        bar.popup.focusItem.grabToImage(function(result) {
            root.check(side + '-drawer-capture', result.saveToFile(path + '.' + side + '.png'));
            if (afterCapture) afterCapture();
        });
    }
    PanelWindow {
        screen: Quickshell.screens[0]
        anchors { top: true; left: true; right: true }
        implicitHeight: root.reservedTopHeight
        exclusiveZone: root.reservedTopHeight
        color: 'transparent'
        WlrLayershell.namespace: 'pentad-test-reserved-topbar'
        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    }
    BarWindow {
        id: bar
        services: root.services
        screen: Quickshell.screens[0]
        Component.onCompleted: {
            exclusionMode = ExclusionMode.Normal;
            exclusiveZone = services.config.documents.layout.barHeight;
        }
    }
    Timer {
        interval: 360; running: true; repeat: true
        property int step: -1
        property int activityStep: 0
        property int originalActivityHeight: 0
        onTriggered: {
            step++;
            if (step === 0) {
                root.check('right-bar-hover-dispatched', root.pointer.mouseMove(bar.barFace,
                    bar.barFace.width - 2, bar.barFace.height / 2, 0, Qt.NoButton, Qt.NoModifier));
            } else if (step === 1) {
                root.check('all-menus-prepared-in-background', bar.leftPopup.leftContentStatus === Loader.Ready
                    && bar.rightPopup.rightContentStatus === Loader.Ready && bar.activityPopup.activityContentStatus === Loader.Ready
                    && !bar.popup.visible && !bar.popup.activityContent.visible);
                root.preparedActivityContent = bar.popup.activityContent;
                root.check('hover-prepares-right-menu-without-opening', bar.rightPopup.rightPrepared
                    && !!bar.rightPopup.rightContent && bar.rightPopup.rightContentStatus === Loader.Ready
                    && !bar.popup.visible && root.services.popups.surface === '');
                root.preparedRightContent = bar.rightPopup.rightContent;
                root.managerProbe.open("right", "fixture");
                root.managerProbe.registerChild(root.childProbe);
                root.managerProbe.dismissTop();
                root.check("escape-closes-child-before-parent", root.childProbe.closedCount === 1
                    && root.managerProbe.childSurface === null && root.managerProbe.surface === "right");
                root.managerProbe.dismissTop();
                root.check("second-escape-closes-parent", root.managerProbe.surface === "");
                root.managerProbe.open("right", "fixture");
                root.managerProbe.registerChild(root.childProbe);
                root.managerProbe.open("left", "fixture");
                root.check("opening-another-menu-keeps-child-and-parent", root.childProbe.closedCount === 1
                    && root.managerProbe.childSurface === root.childProbe
                    && root.managerProbe.isOpen("right", "fixture")
                    && root.managerProbe.isOpen("left", "fixture"));
                root.managerProbe.close();
                root.checks.push({ name: 'activity-facade-forwards-artwork-service', passed:
                    !!bar.activityController && bar.activityController.serviceFacade.artwork === root.services.artwork });
                root.check('right-bar-press-dispatched', root.pointer.mousePress(bar.barFace,
                    bar.barFace.width - 2, bar.barFace.height / 2, Qt.LeftButton, Qt.NoModifier, 0));
                root.check('right-menu-owner-opens-on-press', root.services.popups.surface === 'right');
            }
            else if (step === 2) {
                root.checks.push({ name: 'right-popup-visible', passed: bar.popup.visible && bar.popup.surface === 'right' });
                root.check('press-reuses-prepared-right-menu-before-release', bar.rightPopup.rightContent === root.preparedRightContent
                    && bar.rightPopup.rightContent.visible && bar.rightPopup.rightContent.width === 390);
                root.check('right-menu-has-controls-after-startup', !!bar.rightPopup.rightContent
                    && !!bar.rightPopup.rightContent.sessionHeader
                    && !!bar.rightPopup.rightContent.quickSettingsGrid
                    && !!bar.rightPopup.rightContent.audioControls
                    && bar.rightPopup.rightContent.sessionHeader.height > 0
                    && bar.rightPopup.rightContent.quickSettingsGrid.height > 0);
                root.check('right-bar-release-dispatched', root.pointer.mouseRelease(bar.barFace,
                    bar.barFace.width - 2, bar.barFace.height / 2, Qt.LeftButton, Qt.NoModifier, 0));
                root.check('right-bar-release-keeps-menu-open', root.services.popups.surface === 'right');
                const reservedTop = root.reservedTopHeight + bar.services.config.documents.layout.barHeight;
                root.check('drawer-follows-compositor-reserved-bars', bar.popup.exclusionMode === ExclusionMode.Normal
                    && bar.popup.anchors.top && bar.popup.anchors.bottom && bar.popup.margins.top === 0
                    && Math.abs(bar.popup.height + reservedTop - bar.screen.height) <= 1,
                    JSON.stringify({ topReserved: root.reservedTopHeight, pentadBar: bar.services.config.documents.layout.barHeight,
                        drawerHeight: bar.popup.height, expectedTop: reservedTop, screenHeight: bar.screen.height }));
                root.check('side-drawer-runs-from-reserved-bar-bottom-to-screen-bottom', Math.abs(bar.popup.height + reservedTop - bar.screen.height) <= 1
                    && bar.popup.width === 422 + Metrics.overlayShadowRoom && bar.popup.attachedSurface.width === 422);
                const drawerX = bar.popup.inputRegion.originX;
                const drawerY = bar.popup.inputRegion.originY;
                root.checks.push({ name: 'popup-input-region-follows-contour', passed: bar.popup.inputRegion.rows.length > 0 && bar.popup.inputRegion.containsPoint(drawerX + 100, drawerY + 70) && !bar.popup.inputRegion.containsPoint(drawerX, drawerY + bar.popup.height - 1) });
                root.checks.push({ name: 'side-drawer-slides-in', passed: bar.popup.slideProgress > 0 });
                root.captureDrawer('right', function() {
                    root.services.popups.open('activity', bar.outputId);
                    interval = 80;
                });
            } else if (step === 3) {
                const menu = bar.popup.activitySurface;
                if (activityStep === 0) {
                    root.check('activity-opens-alongside-right-menu', bar.activityPopup.visible
                        && bar.rightPopup.visible && bar.activityPopup !== bar.rightPopup
                        && root.services.popups.isOpen('right', bar.outputId));
                    root.check('activity-slides-down-inside-clipped-window', bar.popup.slideProgress > 0
                        && bar.popup.slideProgress < 1 && menu.y < 0 && menu.parent.clip);
                    root.check('activity-input-mask-follows-slide', Math.abs(bar.popup.inputRegion.originY
                        - menu.mapToItem(null, 0, 0).y) < 1);
                    interval = 360;
                } else if (activityStep === 1) {
                    root.services.popups.open('left', bar.outputId);
                    root.check('all-three-menus-have-independent-visible-windows',
                        bar.leftPopup.visible && bar.rightPopup.visible && bar.activityPopup.visible);
                    const focusWindows = root.services.popups.focusWindows;
                    root.check('shared-focus-group-includes-all-menus-and-bar',
                        [bar, bar.leftPopup, bar.rightPopup, bar.activityPopup].every(
                            function(window) { return focusWindows.includes(window); }));
                    root.services.popups.toggle('left', bar.outputId);
                    root.check('toggling-left-retains-right-and-activity',
                        !root.services.popups.isOpen('left', bar.outputId)
                        && root.services.popups.isOpen('right', bar.outputId)
                        && root.services.popups.isOpen('activity', bar.outputId));
                    root.check('activity-follows-compositor-reserved-bars', bar.popup.exclusionMode === ExclusionMode.Normal
                        && bar.popup.margins.top === 0 && bar.popup.WlrLayershell.layer === bar.WlrLayershell.layer);
                    root.check('activity-does-not-reserve-desktop-space', bar.popup.exclusiveZone === 0
                        && bar.exclusiveZone === bar.services.config.documents.layout.barHeight);
                    originalActivityHeight = bar.popup.height;
                    root.services.popups.closeSurface('right', bar.outputId);
                    root.check('activity-open-reuses-prepared-content', bar.popup.activityContent === root.preparedActivityContent);
                    const tab = root.findNamed(bar.popup.activityContent, 'activity-tab-3');
                    root.check('activity-tab-press-dispatched', !!tab && root.pointer.mousePress(tab,
                        tab.width / 2, tab.height / 2, Qt.LeftButton, Qt.NoModifier, 0));
                    root.check('activity-tab-changes-before-release', bar.popup.activityContent.currentIndex === 3);
                    root.check('activity-tab-release-dispatched', !!tab && root.pointer.mouseRelease(tab,
                        tab.width / 2, tab.height / 2, Qt.LeftButton, Qt.NoModifier, 0));
                    root.check('activity-tab-release-retains-selection', bar.popup.activityContent.currentIndex === 3);
                } else if (activityStep === 2) {
                    root.check('activity-tab-resizes-without-reserving-desktop-space', bar.popup.height !== originalActivityHeight
                        && bar.popup.exclusiveZone === 0);
                    root.services.popups.close();
                    interval = 80;
                } else if (activityStep === 3) {
                    root.check('activity-keeps-content-without-reserving-space-during-exit', bar.popup.visible
                        && !!bar.popup.shownComponent && menu.y < 0 && bar.popup.slideProgress > 0
                        && bar.popup.slideProgress < 1 && bar.popup.exclusiveZone === 0);
                    root.services.popups.open('activity', bar.outputId);
                    interval = 360;
                } else if (activityStep === 4) {
                    root.check('activity-reopen-cancels-exit', bar.popup.visible && menu.y === 0 && bar.popup.slideProgress === 1);
                    root.services.popups.close();
                } else if (activityStep === 5) {
                    root.check('activity-exit-hides-without-changing-desktop-space', !bar.popup.visible
                        && bar.popup.exclusiveZone === 0);
                    root.check('closed-activity-retains-hidden-prepared-content', bar.popup.activityContent === root.preparedActivityContent
                        && !bar.popup.activityContent.visible);
                    root.services.popups.open('activity', bar.outputId);
                } else {
                    root.check('activity-reopen-preserves-selected-tab', bar.popup.activityContent === root.preparedActivityContent
                        && bar.popup.activityContent.currentIndex === 3);
                    bar.popup.visible = false;
                }
                if (activityStep++ < 6) step--;
            } else if (step === 4) {
                root.checks.push({ name: 'native-dismissal-clears-owner', passed: root.services.popups.surface === '' });
                root.services.popups.open('left', bar.outputId);
            } else if (step === 5) {
                root.checks.push({ name: 'reopen-after-dismissal', passed: bar.popup.visible && bar.popup.surface === 'left' });
                const reservedTop = root.reservedTopHeight + bar.services.config.documents.layout.barHeight;
                root.check('left-drawer-runs-from-reserved-bar-bottom-to-screen-bottom', Math.abs(bar.popup.height + reservedTop - bar.screen.height) <= 1
                    && bar.popup.width === 422 + Metrics.overlayShadowRoom && bar.popup.attachedSurface.width === 422 && bar.popup.margins.top === 0);
                root.check('side-drawer-has-visible-focus-owner', bar.popup.focusItem.visible && bar.popup.focusItem.activeFocus);
                root.captureDrawer('left', function() {
                    root.check('escape-event-dispatched', root.pointer.keyClick(Qt.Key_Escape, Qt.NoModifier, 0));
                });
                interval = 80;
            } else if (step === 6) {
                root.check('escape-closes-drawer-owner', root.services.popups.surface === '');
                root.check('closing-keeps-content-until-animation-finishes', bar.popup.visible && !!bar.popup.shownComponent && bar.popup.slideProgress > 0 && bar.popup.slideProgress < 1);
                root.services.popups.open('left', bar.outputId);
                interval = 360;
            } else if (step === 7) {
                root.check('rapid-reopen-cancels-pending-close', bar.popup.visible && bar.popup.shownSurface === 'left' && bar.popup.slideProgress === 1);
                root.closingInputRows = bar.popup.inputRegion.rows.slice();
                root.services.popups.close();
                interval = 80;
            } else if (step === 8) {
                root.check('left-popup-anchor-stays-onscreen-during-slide', bar.popup.anchors.left && !bar.popup.anchors.right && bar.popup.attachedSurface.x < 0);
                const localX = bar.popup.attachedSurface.mapToItem(null, 0, 0).x;
                root.check('input-mask-tracks-moving-content', Math.abs(bar.popup.inputRegion.originX - localX) < 1);
                root.check('moving-input-mask-reuses-regions-during-animation', bar.popup.slideProgress > 0 && bar.popup.slideProgress < 1 && root.closingInputRows.length > 0 && bar.popup.inputRegion.rows.length === root.closingInputRows.length && bar.popup.inputRegion.rows.every(function(row, index) { return row === root.closingInputRows[index]; }));
                interval = 360;
            } else if (step === 9) {
                root.check('animated-close-hides-surface', !bar.popup.visible && !bar.popup.shownComponent);
                root.check('closed-menu-retains-prepared-content', bar.rightPopup.rightContent === root.preparedRightContent
                    && !bar.rightPopup.rightContent.visible);
                root.services.popups.open('right', bar.outputId);
                interval = 80;
            } else if (step === 10) {
                root.check('right-menu-reopen-reuses-content', bar.rightPopup.rightContent === root.preparedRightContent);
                root.check('right-popup-anchor-stays-onscreen-during-slide', bar.popup.anchors.right && !bar.popup.anchors.left && bar.popup.attachedSurface.x > 0);
                root.services.popups.disposeOutput(bar.outputId);
                interval = 360;
            } else if (step === 11) {
                root.checks.push({ name: 'output-disposal-closes-popup', passed: !bar.popup.visible && !root.services.popups.surface });
                root.checks.push({ name: 'no-preview-media-consumers', passed: root.services.media.positionConsumers.length === 0 && root.services.lyrics.consumers.length === 0 && root.services.visualizer.consumers.length === 0 });
                Theme.resolve(Object.assign({}, Theme.config, { reducedMotion: true }));
                root.services.popups.open('left', bar.outputId);
            } else if (step === 12) {
                root.check('reduced-motion-opens-without-travel', bar.popup.visible && bar.popup.slideProgress === 1 && bar.popup.attachedSurface.x === 0, JSON.stringify({ visible: bar.popup.visible, progress: bar.popup.slideProgress, x: bar.popup.attachedSurface.x, reduced: Theme.tokens.reducedMotion }));
                root.services.popups.close();
            } else if (step === 13) {
                root.check('reduced-motion-closes-without-travel', !bar.popup.visible);
                root.services.popups.open('activity', bar.outputId);
                bar.popup.activityContent.selectTab(1);
            } else if (step === 14) {
                root.check('reduced-motion-activity-opens-without-travel', bar.popup.visible
                    && bar.popup.slideProgress === 1 && bar.popup.activitySurface.y === 0);
                const surface = bar.popup.activitySurface;
                const button = root.findNamed(bar.popup.activityContent, 'activity-open-localsend');
                const origin = button.mapToItem(surface, 0, 0);
                const left = origin.x - surface.cornerGeometry.shoulder;
                const right = surface.width - surface.cornerGeometry.shoulder - origin.x - button.width;
                const bottom = surface.height - origin.y - button.height;
                root.check('localsend-button-has-equal-side-and-bottom-padding', Math.abs(left - Metrics.activityPadding) < 0.1
                    && Math.abs(right - left) < 0.1 && Math.abs(bottom - left) < 0.1,
                    JSON.stringify({ left: left, right: right, bottom: bottom }));
                root.check('localsend-button-corners-follow-inset-surface', button.background.extent === surface.cornerGeometry.radius - left);
                root.captureDrawer('localsend', function() { root.services.popups.close(); });
            } else if (step === 15) {
                root.check('reduced-motion-activity-closes-without-reserving-space', !bar.popup.visible && bar.popup.exclusiveZone === 0);
                console.log('PENTAD_TEST ' + JSON.stringify({ status: root.checks.every(function(check) { return check.passed }) ? 'pass' : 'fail', checks: root.checks }));
                stop();
                Qt.quit();
            }
        }
    }
}
