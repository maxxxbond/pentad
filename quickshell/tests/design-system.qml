import QtQuick
import QtQuick.Controls.Basic
import QtTest
import Quickshell
import qs.theme
import qs.components

ShellRoot {
    id: root
    property TestEvent pointer: TestEvent {}
    property int toggleRequests: 0
    readonly property string requestedAppearance: Quickshell.env("PENTAD_GALLERY_APPEARANCE")
    readonly property string requestedAccent: Quickshell.env("PENTAD_GALLERY_ACCENT")
    readonly property string requestedScale: Quickshell.env("PENTAD_GALLERY_SCALE")
    readonly property string requestedReducedMotion: Quickshell.env("PENTAD_GALLERY_REDUCED_MOTION")
    property string appearance: requestedAppearance === "light" ? "light" : "dark"
    property string accent: /^#[\da-f]{6}$/i.test(requestedAccent) ? requestedAccent : "#869677"
    property bool reduced: requestedReducedMotion === "1"
    property real galleryScale: {
        const value = Number(requestedScale)
        return requestedScale && Number.isFinite(value) ? Math.max(0.75, Math.min(2, value)) : 1
    }
    readonly property bool manualGallery: Quickshell.env("PENTAD_GALLERY") === "1"

    function applyTheme() {
        Theme.resolve({ appearance: appearance, accent: accent, fontFamily: "Geist", reducedMotion: reduced })
    }
    Component.onCompleted: applyTheme()

    FloatingWindow {
        id: galleryWindow
        screen: Quickshell.screens.length > 0 ? Quickshell.screens[0] : null
        visible: true
        implicitWidth: Math.ceil(920 * root.galleryScale)
        implicitHeight: Math.ceil(900 * root.galleryScale)
        minimumSize: Qt.size(implicitWidth, implicitHeight)
        maximumSize: minimumSize
        color: Theme.tokens.surface
        Item {
            id: galleryContent
            width: Math.ceil(920 * root.galleryScale)
            height: Math.ceil(900 * root.galleryScale)
            Rectangle {
                anchors.fill: parent
                color: Theme.tokens.surface
            }
            AttachedSideSurface {
                id: leftProbe
                width: 422; height: 120
                side: "left"
                visible: false
                contentComponent: Component { Item {} }
            }
            AttachedSideSurface {
                id: rightProbe
                width: 422; height: 16
                side: "right"
                visible: false
                contentComponent: Component { Item {} }
            }
            Column {
                id: gallery
                x: 24 * root.galleryScale
                y: 24 * root.galleryScale
                width: 872
                height: 672
                spacing: 16
                scale: root.galleryScale
                transformOrigin: Item.TopLeft
            PentadRow {
                PentadText { text: "Pentad design system"; role: "title" }
                Item { width: 12; height: 1 }
                PentadButton { text: "Dark"; accessibleName: "Use dark theme"; onClicked: { root.appearance = "dark"; root.applyTheme() } }
                PentadButton { text: "Light"; accessibleName: "Use light theme"; onClicked: { root.appearance = "light"; root.applyTheme() } }
                PentadToggle { text: "Reduced motion"; accessibleName: text; checked: root.reduced; onToggled: { root.reduced = checked; root.applyTheme() } }
                PentadButton { text: "Scale −"; onClicked: root.galleryScale = Math.max(0.75, root.galleryScale - 0.25) }
                PentadText { text: Math.round(root.galleryScale * 100) + "%"; role: "caption" }
                PentadButton { text: "Scale +"; onClicked: root.galleryScale = Math.min(2, root.galleryScale + 0.25) }
            }
            PentadText { text: "Typography · caption / body / section / title"; role: "section" }
            PentadRow {
                PentadText { text: "Caption 12"; role: "caption" }
                PentadText { text: "Body 14" }
                PentadText { text: "Section 16"; role: "section" }
                PentadText { text: "Title 20"; role: "title" }
            }
            PentadText { text: "Controls · enabled / checked / disabled / pending / error"; role: "section" }
            PentadRow {
                PentadButton { text: "Button"; accessibleName: "Example button" }
                PentadButton { text: "Selected"; checked: true }
                PentadButton { text: "Unavailable"; requestedEnabled: false }
                PentadButton { text: "Working"; pending: true }
                PentadButton { text: "Problem"; error: true }
            }
            PentadRow {
                PentadToggle { text: "On"; checked: true }
                PentadToggle { id: demoToggle; text: "Off"; onToggled: root.toggleRequests++ }
                PentadToggle { id: pendingToggle; text: "Pending"; checked: true; pending: true; onToggled: root.toggleRequests++ }
                PentadToggle { id: disabledToggle; text: "Unavailable"; requestedEnabled: false; onToggled: root.toggleRequests++ }
                PentadToggle { text: "Error"; error: true }
                PentadToggle { id: mirroredToggle; text: "RTL"; checked: true; LayoutMirroring.enabled: true }
            }
            PentadRow {
                PentadSlider { accessibleName: "Example level"; from: 0; to: 100; value: 64 }
                PentadSlider { accessibleName: "Error level"; error: true; from: 0; to: 100; value: 34 }
                PentadTextField { accessibleName: "Search example"; placeholderText: "Search…" }
                PentadTextField { accessibleName: "Invalid example"; error: true; text: "Invalid value" }
            }
            PentadSegmented {
                id: demoRange
                accessibleName: "Range"
                tabList: true
                options: [{ value: "day", label: "Day" }, { value: "week", label: "Week" },
                    { value: "month", label: "Month" }, { value: "year", label: "Year" }]
                value: "day"
                onActivated: function(v) { demoRange.value = v; }
            }
            PentadRow {
                PentadInfoButton {
                    id: demoHelp
                    accessibleName: 'About the example'
                    helpText: 'Extra guidance stays available without filling the menu.'
                }
                PentadMarquee {
                    id: demoMarquee
                    width: 320
                    text: 'A long Pentad title with enough text to exercise scrolling and reduced motion'
                }
                PentadButton {
                    id: menuTrigger
                    text: 'Menu'
                    onClicked: demoMenu.openFor(menuTrigger)
                    PentadMenu {
                        id: demoMenu
                        entries: [{ text: 'Open' }, { separator: true }, { text: 'Selected', checkable: true, checked: true }, { text: 'Unavailable', enabled: false }]
                    }
                }
            }
            PentadRow {
                PentadCard { width: 250; height: 112
                    PentadText { anchors.fill: parent; anchors.margins: 16; text: "Card surface · 14 px continuous corners\nA synthetic fixture with no hardware adapters." }
                }
                ContinuousSurface {
                    id: demoSurface
                    width: 250; height: 112; extent: 18; concaveShoulder: 12
                    fill: Theme.tokens.surfaceOverlay
                    PentadText { anchors.centerIn: parent; text: "Continuous surface" }
                }
            }
            PentadRow {
                PentadDropZone {
                    id: demoDropZone
                    width: 220
                    title: 'Drop here'
                    hint: 'files, links or text'
                }
                PentadDropZone {
                    id: demoActiveDropZone
                    width: 220
                    active: true
                    title: 'Release here'
                    destinationLabel: 'Upload to'
                    destination: ['projects', 'design']
                }
                PentadDropZone {
                    width: 220
                    title: 'Drop files'
                    destinationLabel: 'Upload to'
                    destination: ['home', 'someone', 'projects', 'pentad', 'design']
                }
            }
            PentadRow {
                PentadSpinBox { id: demoSpinBox; accessibleName: 'Example count'; from: 1; to: 10; value: 3 }
                PentadScrollView {
                    id: demoScroll
                    width: 240; height: 90
                    Column {
                        Repeater {
                            model: 10
                            PentadText { required property int index; text: 'Scrollable row ' + (index + 1); height: 24 }
                        }
                    }
                }
                PentadButton {
                    id: popupTrigger
                    text: 'Popup'
                    onClicked: demoPopup.openFor(popupTrigger)
                    PentadPopup {
                        id: demoPopup
                        contentItem: PentadText { text: 'Shared popup surface'; padding: 12 }
                    }
                }
            }

            }
        }
    }

    Timer {
        running: !root.manualGallery
        interval: 250
        repeat: false
        onTriggered: {
            demoHelp.helpPopup.enter = null;
            demoHelp.helpPopup.exit = null;
            demoHelp.forceActiveFocus(Qt.TabFocusReason);
            const helpFocusWorks = demoHelp.ToolTip.visible && demoHelp.ToolTip.text === demoHelp.helpText;
            demoSurface.forceActiveFocus();
            root.pointer.mouseMove(demoHelp, 14, 14, 0, Qt.NoButton, Qt.NoModifier);
            const helpHoverWorks = demoHelp.hovered && demoHelp.ToolTip.visible;
            root.pointer.mouseClick(demoHelp, 14, 14, Qt.LeftButton, Qt.NoModifier, 0);
            const helpPointerWorks = demoHelp.helpPopup.visible
                && demoHelp.helpPopup.contentItem.text === demoHelp.helpText
                && demoHelp.helpPopup.contentItem.implicitHeight > 0;
            root.pointer.keyClick(Qt.Key_Escape, Qt.NoModifier, 0);
            const helpEscapeWorks = !demoHelp.helpPopup.visible;
            demoHelp.forceActiveFocus(Qt.TabFocusReason);
            root.pointer.keyClick(Qt.Key_Space, Qt.NoModifier, 0);
            const helpKeyboardWorks = demoHelp.helpPopup.visible;
            root.pointer.mouseClick(demoSurface, 125, 70, Qt.LeftButton, Qt.NoModifier, 0);
            const helpOutsideWorks = !demoHelp.helpPopup.visible;
            const beforeToggle = root.toggleRequests;
            root.pointer.mouseClick(demoToggle, 22, 18, Qt.LeftButton, Qt.NoModifier, 0);
            const pointerToggleWorks = demoToggle.checked && root.toggleRequests === beforeToggle + 1;
            demoToggle.forceActiveFocus();
            root.pointer.keyClick(Qt.Key_Space, Qt.NoModifier, 0);
            const keyboardToggleWorks = !demoToggle.checked && root.toggleRequests === beforeToggle + 2;
            const beforeDisabled = root.toggleRequests;
            root.pointer.mouseClick(pendingToggle, 22, 18, Qt.LeftButton, Qt.NoModifier, 0);
            root.pointer.mouseClick(disabledToggle, 22, 18, Qt.LeftButton, Qt.NoModifier, 0);
            const disabledToggleWorks = pendingToggle.checked && !disabledToggle.checked
                && root.toggleRequests === beforeDisabled;
            Theme.resolve({ appearance: "dark", accent: root.accent, fontFamily: "Geist", reducedMotion: root.reduced })
            const darkSurface = Theme.tokens.surface
            Theme.resolve({ appearance: "light", accent: root.accent, fontFamily: "Geist", reducedMotion: false })
            const lightSurface = Theme.tokens.surface
            root.applyTheme()
            const passed = Metrics.controlSmall === 28 && Metrics.controlMedium === 34
                && Metrics.controlLarge === 44 && Metrics.textCaption === 12
                && Metrics.textBody === 14 && Metrics.textSection === 16
                && Metrics.textTitle === 20 && darkSurface !== lightSurface
                && Motion.short >= 0 && Motion.short <= 160
                && root.galleryScale >= 0.75 && root.galleryScale <= 2
                && demoSurface.contour.includes(" C ")
            console.log("PENTAD_TEST " + JSON.stringify({
                status: passed ? "pass" : "fail",
                checks: [
                    { name: "help-focus-exposes-tooltip", passed: helpFocusWorks },
                    { name: "help-hover-exposes-tooltip", passed: helpHoverWorks },
                    { name: "help-pointer-shows-explanation", passed: helpPointerWorks },
                    { name: "help-escape-dismisses", passed: helpEscapeWorks },
                    { name: "help-space-shows-explanation", passed: helpKeyboardWorks },
                    { name: "help-outside-press-dismisses", passed: helpOutsideWorks },
                    { name: "switch-pointer-toggles-once", passed: pointerToggleWorks },
                    { name: "switch-space-key-toggles-once", passed: keyboardToggleWorks },
                    { name: "switch-pending-and-disabled-reject-input", passed: disabledToggleWorks },
                    { name: "switch-supports-right-to-left-position", passed: mirroredToggle.mirrored && mirroredToggle.visualPosition === 0 },
                    { name: "design-tokens-and-motion", passed },
                    { name: "configurable-gallery-scale", passed: root.galleryScale >= 0.75 && root.galleryScale <= 2 },
                    { name: "theme-resolution-and-continuous-path", passed: darkSurface !== lightSurface && demoSurface.contour.includes(" C ") },
                    { name: "reduced-motion-setting", passed: !root.reduced || Motion.short === 0 },
                    { name: "marquee-and-menu-components", passed: demoMarquee.overflow > 0 && demoMenu.entries.length === 4 && demoMenu.count >= demoMenu.entries.length },
                    { name: "continuous-surface-input-contour", passed: demoSurface.contains(Qt.point(125, 70)) && !demoSurface.contains(Qt.point(0, 111)) },
                    { name: "side-attachments-share-bounded-shoulder-geometry", passed:
                        leftProbe.shoulder === 32 && leftProbe.panelWidth === 390 && leftProbe.contentX === 0
                        && rightProbe.shoulder === 16 && rightProbe.panelWidth === 406 && rightProbe.contentX === 16
                        && leftProbe.contains(Qt.point(10, 80)) && !leftProbe.contains(Qt.point(421, 100))
                        && rightProbe.contains(Qt.point(30, 8)) && !rightProbe.contains(Qt.point(0, 15)) },
                    { name: 'drop-zone-sizes-to-its-content', passed: demoDropZone.implicitHeight > 0
                        && demoActiveDropZone.implicitHeight > demoDropZone.implicitHeight },
                    { name: 'scroll-and-spin-components', passed: demoScroll.contentHeight > demoScroll.height && demoSpinBox.value === 3 },
                    { name: 'requested-typeface-available', passed: Qt.fontFamilies().includes(Theme.tokens.fontFamily) }
                ]
            }))
            const artifactPath = Quickshell.env("PENTAD_ARTIFACT_PATH")
            if (artifactPath) galleryContent.grabToImage(function(result) {
                result.saveToFile(artifactPath)
                Qt.quit()
            })
            else Qt.quit()
        }
    }
}
