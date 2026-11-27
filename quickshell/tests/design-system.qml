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
    property int helpActions: 0
    property int rowActivations: 0
    property int rowTrailingClicks: 0
    property int chipToggles: 0
    property int fixedChipToggles: 0
    property int emptyActions: 0
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
        implicitWidth: Math.ceil(1280 * root.galleryScale)
        implicitHeight: Math.ceil(900 * root.galleryScale)
        minimumSize: Qt.size(implicitWidth, implicitHeight)
        maximumSize: minimumSize
        color: Theme.tokens.surface
        Item {
            id: galleryContent
            width: Math.ceil(1280 * root.galleryScale)
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
            PentadRow {
                PentadSegmented {
                    id: demoRange
                    accessibleName: "Range"
                    tabList: true
                    options: [{ value: "day", label: "Day" }, { value: "week", label: "Week" },
                        { value: "month", label: "Month" }, { value: "year", label: "Year" }]
                    value: "day"
                    onActivated: function(v) { demoRange.value = v; }
                }
                PentadComboBox {
                    id: demoCombo
                    width: 200
                    accessibleName: "Engine"
                    model: ["DuckDuckGo", "Google", "Kagi", "Startpage"]
                }
            }
            PentadRow {
                PentadSmoothTabs {
                    id: demoSmoothTabs
                    width: 320
                    panelHeight: 64
                    accessibleName: "Smooth tabs example"
                    options: [{ value: "clips", label: "Clips" }, { value: "files", label: "Files" },
                        { value: "links", label: "Links" }]
                    PentadText { text: "Copied text and images, newest first."; wrapMode: Text.Wrap; padding: 12 }
                    PentadText { text: "Files you dropped here, ready to send on."; wrapMode: Text.Wrap; padding: 12 }
                    PentadText { text: "Links saved from the clipboard."; wrapMode: Text.Wrap; padding: 12 }
                }
            }
            PentadRow {
                PentadInfoButton {
                    id: demoHelp
                    accessibleName: 'About the example'
                    helpText: 'Extra guidance stays available without filling the menu.'
                }
                PentadInfoButton {
                    id: actionHelp
                    accessibleName: 'About the action example'
                    helpText: 'Variables remember something for later.'
                    helpActionText: 'Learn more'
                    onHelpActionTriggered: root.helpActions++
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
                PentadFileDrop {
                    id: demoDropZone
                    width: 220
                    height: 160
                    title: 'Drop here'
                    hint: 'files, links or text'
                }
                PentadFileDrop {
                    width: 220
                    height: 160
                    active: true
                    title: 'Release here'
                    hint: 'files, links or text'
                }
                PentadFileDrop {
                    id: demoShortDropZone
                    width: 220
                    height: 92
                    title: 'Drop files'
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
            // Lists: section headers, list rows, chips and empty states in their states.
            Column {
                id: kit
                x: 872 * root.galleryScale
                y: 24 * root.galleryScale
                width: 384
                spacing: Metrics.space4
                scale: root.galleryScale
                transformOrigin: Item.TopLeft
                PentadText { text: "Lists · header / row / chip / empty"; role: "section" }
                Column {
                    width: parent.width
                    spacing: Metrics.space3
                    PentadSectionHeader { id: plainHeader; width: parent.width; text: "Recent" }
                    PentadSectionHeader { id: countHeader; width: parent.width; text: "Recent"; count: 12 }
                    PentadSectionHeader {
                        id: trailingHeader
                        width: parent.width
                        text: "Нещодавні файли з усіх підключених пристроїв і хмарних сховищ"
                        count: 128
                        PentadButton { id: headerAction; text: "Очистити"; controlHeight: Metrics.controlSmall }
                    }
                }
                ContinuousSurface {
                    width: parent.width
                    height: rows.implicitHeight + 2 * Metrics.space1
                    fill: Theme.tokens.surfaceRaised
                    extent: Metrics.radiusCard
                    Column {
                        id: rows
                        x: Metrics.space1
                        y: Metrics.space1
                        width: parent.width - 2 * Metrics.space1
                        PentadListRow { id: plainRow; width: parent.width; title: "Plain title"; onActivated: root.rowActivations++ }
                        PentadListRow {
                            id: iconRow
                            width: parent.width
                            iconSource: Qt.resolvedUrl("assets/icons/material/wifi-symbolic.svg")
                            title: "Wi-Fi"
                            subtitle: "Connected · Home"
                            onActivated: root.rowActivations++
                            PentadToggle { id: iconRowToggle; accessibleName: "Wi-Fi"; checked: true }
                        }
                        PentadListRow {
                            id: subtitleRow
                            width: parent.width
                            title: "Downloads"
                            subtitle: "12 files"
                            onActivated: root.rowActivations++
                            PentadButton { id: subtitleRowAction; text: "Open"; controlHeight: Metrics.controlSmall; restFill: Theme.tokens.surfaceOverlay; onClicked: root.rowTrailingClicks++ }
                        }
                        PentadListRow {
                            id: longRow
                            width: parent.width
                            iconSource: Qt.resolvedUrl("assets/icons/material/headphones-symbolic.svg")
                            title: "Бездротові навушники з шумозаглушенням у вітальні на другому поверсі"
                            subtitle: "Підключено через Bluetooth · заряд 64 % · останнє з'єднання сьогодні"
                            PentadButton { id: longRowAction; text: "Від'єднати"; controlHeight: Metrics.controlSmall; restFill: Theme.tokens.surfaceOverlay }
                        }
                        PentadListRow {
                            id: mirroredRow
                            width: parent.width
                            LayoutMirroring.enabled: true
                            iconSource: Qt.resolvedUrl("assets/icons/material/bluetooth-symbolic.svg")
                            title: "RTL"
                            subtitle: "Mirrored row"
                            PentadToggle { id: mirroredRowToggle; accessibleName: "RTL" }
                        }
                    }
                }
                Flow {
                    width: parent.width
                    spacing: Metrics.space1
                    PentadChip { id: idleChip; text: "All"; onToggled: { root.chipToggles++; checked = !checked } }
                    PentadChip { text: "Images"; count: 24; checked: true; onToggled: { root.chipToggles++; checked = !checked } }
                    PentadChip { id: countChip; text: "Links"; count: 3; onToggled: { root.chipToggles++; checked = !checked } }
                    PentadChip { id: fixedChip; text: "Pinned"; checked: true; onToggled: root.fixedChipToggles++ }
                    PentadChip { id: longChip; width: 160; text: "Документи з усіх підключених пристроїв"; count: 1024 }
                }
                Row {
                    spacing: Metrics.space2
                    ContinuousSurface {
                        width: 188
                        height: Math.max(plainEmpty.implicitHeight, actionEmpty.implicitHeight)
                        fill: Theme.tokens.surfaceRaised
                        extent: Metrics.radiusCard
                        PentadEmptyState {
                            id: plainEmpty
                            anchors.fill: parent
                            iconSource: Qt.resolvedUrl("assets/icons/material/notifications-off-symbolic.svg")
                            text: "No notifications"
                        }
                    }
                    ContinuousSurface {
                        width: 188
                        height: Math.max(plainEmpty.implicitHeight, actionEmpty.implicitHeight)
                        fill: Theme.tokens.surfaceRaised
                        extent: Metrics.radiusCard
                        PentadEmptyState {
                            id: actionEmpty
                            anchors.fill: parent
                            iconSource: Qt.resolvedUrl("assets/icons/material/stash/sticky-note-2-symbolic.svg")
                            text: "Перетягніть сюди файли, посилання або текст"
                            actionText: "Додати файл"
                            onActionRequested: root.emptyActions++
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
            const helpFocusWorks = demoHelp.helpPopup.visible && !demoHelp.pinned && !demoHelp.ToolTip.visible
                && demoHelp.activeFocus;
            demoSurface.forceActiveFocus();
            demoHelp.helpPopup.close();
            root.pointer.mouseMove(demoHelp, 14, 14, 0, Qt.NoButton, Qt.NoModifier);
            const hoverArmed = demoHelp.hovered && demoHelp.helpHoverTimer.running && !demoHelp.helpPopup.visible;
            demoHelp.helpHoverTimer.triggered();
            const helpHoverWorks = hoverArmed && demoHelp.helpPopup.visible && !demoHelp.pinned
                && !demoHelp.ToolTip.visible;
            root.pointer.mouseClick(demoHelp, 14, 14, Qt.LeftButton, Qt.NoModifier, 0);
            const helpPointerWorks = demoHelp.helpPopup.visible && demoHelp.pinned
                && demoHelp.helpLabel.text === demoHelp.helpText
                && demoHelp.helpLabel.implicitHeight > 0;
            const helpTailWorks = Math.abs(demoHelp.helpPopup.x + demoHelp.helpPopup.placement.tail
                - demoHelp.width / 2) < 1;
            root.pointer.keyClick(Qt.Key_Escape, Qt.NoModifier, 0);
            const helpEscapeWorks = !demoHelp.helpPopup.visible;
            demoHelp.forceActiveFocus(Qt.TabFocusReason);
            root.pointer.keyClick(Qt.Key_Space, Qt.NoModifier, 0);
            const helpKeyboardWorks = demoHelp.helpPopup.visible && demoHelp.pinned;
            root.pointer.mouseClick(demoSurface, 125, 70, Qt.LeftButton, Qt.NoModifier, 0);
            const helpOutsideWorks = !demoHelp.helpPopup.visible;
            actionHelp.helpPopup.enter = null;
            actionHelp.helpPopup.exit = null;
            root.pointer.mouseClick(actionHelp, 12, 12, Qt.LeftButton, Qt.NoModifier, 0);
            const actionButton = actionHelp.helpAction;
            const actionShown = actionHelp.helpPopup.visible && actionButton.visible && actionButton.text === 'Learn more';
            root.pointer.mouseClick(actionButton, actionButton.width / 2, actionButton.height / 2, Qt.LeftButton, Qt.NoModifier, 0);
            const helpActionWorks = actionShown && root.helpActions === 1 && !actionHelp.helpPopup.visible;
            const beforeToggle = root.toggleRequests;
            root.pointer.mouseClick(demoToggle, 22, 18, Qt.LeftButton, Qt.NoModifier, 0);
            const pointerToggleWorks = demoToggle.checked && root.toggleRequests === beforeToggle + 1;
            // The knob is sprung: right after the flip it has not arrived yet, unless motion is reduced.
            const knobEasesInsteadOfJumping = root.reduced ? demoToggle.travel === 1 : demoToggle.travel < 1;
            demoToggle.forceActiveFocus();
            root.pointer.keyClick(Qt.Key_Space, Qt.NoModifier, 0);
            const keyboardToggleWorks = !demoToggle.checked && root.toggleRequests === beforeToggle + 2;
            const beforeDisabled = root.toggleRequests;
            root.pointer.mouseClick(pendingToggle, 22, 18, Qt.LeftButton, Qt.NoModifier, 0);
            root.pointer.mouseClick(disabledToggle, 22, 18, Qt.LeftButton, Qt.NoModifier, 0);
            const disabledToggleWorks = pendingToggle.checked && !disabledToggle.checked
                && root.toggleRequests === beforeDisabled;
            const fitsInside = (item, host) => item.mapToItem(host, 0, 0).x >= -0.5
                && item.mapToItem(host, 0, 0).x + item.width <= host.width + 0.5;
            const headerWorks = plainHeader.implicitHeight > 0 && plainHeader.implicitWidth > 0
                && countHeader.implicitWidth > plainHeader.implicitWidth
                && trailingHeader.implicitHeight >= Metrics.controlSmall
                && trailingHeader.implicitWidth > trailingHeader.width
                && trailingHeader.childrenRect.width <= trailingHeader.width + 0.5
                && fitsInside(headerAction, trailingHeader)
                && headerAction.mapToItem(trailingHeader, 0, 0).x > trailingHeader.width / 2;
            const rowsBefore = root.rowActivations;
            root.pointer.mouseClick(plainRow, plainRow.width / 2, plainRow.height / 2, Qt.LeftButton, Qt.NoModifier, 0);
            const rowClickWorks = root.rowActivations === rowsBefore + 1;
            const rowPointerHasNoRing = !plainRow.visualFocus && plainRow.background.edge.a === 0;
            // Focus moves in from elsewhere, as a Tab would: refocusing the focused row keeps the mouse reason.
            demoSurface.forceActiveFocus();
            plainRow.forceActiveFocus(Qt.TabFocusReason);
            const rowKeyboardRing = plainRow.visualFocus && plainRow.background.edge.a > 0;
            root.pointer.keyClick(Qt.Key_Space, Qt.NoModifier, 0);
            const rowSpaceWorks = root.rowActivations === rowsBefore + 2;
            root.pointer.keyClick(Qt.Key_Return, Qt.NoModifier, 0);
            root.pointer.keyClick(Qt.Key_Enter, Qt.KeypadModifier, 0);
            const rowEnterWorks = root.rowActivations === rowsBefore + 4;
            root.pointer.mouseClick(subtitleRowAction, subtitleRowAction.width / 2, subtitleRowAction.height / 2,
                Qt.LeftButton, Qt.NoModifier, 0);
            const rowTrailingKeepsClick = root.rowTrailingClicks === 1 && root.rowActivations === rowsBefore + 4;
            const rowLongStaysInside = longRow.implicitWidth > longRow.width
                && longRow.contentItem.childrenRect.width <= longRow.contentItem.width + 0.5
                && fitsInside(longRowAction, longRow);
            const rowMirrors = iconRowToggle.mapToItem(iconRow, 0, 0).x > iconRow.width / 2
                && mirroredRowToggle.mapToItem(mirroredRow, 0, 0).x + mirroredRowToggle.width < mirroredRow.width / 2;
            const chipSizesWork = [idleChip, countChip, fixedChip, longChip].every(chip => chip.implicitHeight === Metrics.controlSmall)
                && longChip.implicitWidth > longChip.width
                && longChip.contentItem.childrenRect.width <= longChip.contentItem.width + 0.5;
            const uncheckedWidth = countChip.implicitWidth;
            const chipsBefore = root.chipToggles;
            root.pointer.mouseClick(countChip, countChip.width / 2, countChip.height / 2, Qt.LeftButton, Qt.NoModifier, 0);
            const chipClickWorks = root.chipToggles === chipsBefore + 1 && countChip.checked
                && countChip.implicitWidth > uncheckedWidth && !countChip.visualFocus && countChip.background.border.width === 0;
            demoSurface.forceActiveFocus();
            countChip.forceActiveFocus(Qt.TabFocusReason);
            root.pointer.keyClick(Qt.Key_Space, Qt.NoModifier, 0);
            root.pointer.keyClick(Qt.Key_Return, Qt.NoModifier, 0);
            // Click, Space and Enter: three requests, each flipped by the host, so the chip ends checked.
            const chipKeyboardWorks = root.chipToggles === chipsBefore + 3 && countChip.checked
                && countChip.visualFocus && countChip.background.border.width > 0;
            root.pointer.mouseClick(fixedChip, fixedChip.width / 2, fixedChip.height / 2, Qt.LeftButton, Qt.NoModifier, 0);
            const chipHostOwnsChecked = root.fixedChipToggles === 1 && fixedChip.checked;
            const emptySizesWork = !plainEmpty.actionButton.visible && actionEmpty.actionButton.visible
                && plainEmpty.implicitHeight > 0 && actionEmpty.implicitHeight > plainEmpty.implicitHeight
                && actionEmpty.implicitWidth > actionEmpty.width
                && actionEmpty.childrenRect.width <= actionEmpty.width + 0.5;
            const emptyButton = actionEmpty.actionButton;
            root.pointer.mouseClick(emptyButton, emptyButton.width / 2, emptyButton.height / 2, Qt.LeftButton, Qt.NoModifier, 0);
            const emptyActionWorks = root.emptyActions === 1;
            demoSurface.forceActiveFocus();
            Theme.resolve({ appearance: "dark", accent: root.accent, fontFamily: "Geist", reducedMotion: root.reduced })
            const darkSurface = Theme.tokens.surface
            Theme.resolve({ appearance: "light", accent: root.accent, fontFamily: "Geist", reducedMotion: false })
            const lightSurface = Theme.tokens.surface
            root.applyTheme()
            const checks = [
                { name: "help-focus-shows-passive-bubble", passed: helpFocusWorks },
                { name: "help-hover-shows-bubble-not-qt-tooltip", passed: helpHoverWorks },
                { name: "help-pointer-shows-explanation", passed: helpPointerWorks },
                { name: "help-tail-points-at-trigger", passed: helpTailWorks },
                { name: "help-escape-dismisses", passed: helpEscapeWorks },
                { name: "help-action-runs-and-closes", passed: helpActionWorks },
                { name: "help-space-shows-explanation", passed: helpKeyboardWorks },
                { name: "help-outside-press-dismisses", passed: helpOutsideWorks },
                { name: "switch-pointer-toggles-once", passed: pointerToggleWorks },
                { name: "switch-space-key-toggles-once", passed: keyboardToggleWorks },
                { name: "switch-knob-eases-instead-of-jumping", passed: knobEasesInsteadOfJumping },
                { name: "switch-pending-and-disabled-reject-input", passed: disabledToggleWorks },
                { name: "switch-supports-right-to-left-position", passed: mirroredToggle.mirrored && mirroredToggle.visualPosition === 0 },
                { name: "theme-resolution-and-continuous-path", passed: darkSurface !== lightSurface && demoSurface.contour.includes(" C ") },
                { name: "reduced-motion-setting", passed: !root.reduced || Motion.short === 0 },
                { name: "marquee-and-menu-components", passed: demoMarquee.overflow > 0 && demoMenu.entries.length === 4 && demoMenu.count >= demoMenu.entries.length },
                { name: "continuous-surface-input-contour", passed: demoSurface.contains(Qt.point(125, 70)) && !demoSurface.contains(Qt.point(0, 111)) },
                { name: "side-attachments-share-bounded-shoulder-geometry", passed:
                    leftProbe.shoulder === 32 && leftProbe.panelWidth === 390 && leftProbe.contentX === 0
                    && rightProbe.shoulder === 16 && rightProbe.panelWidth === 406 && rightProbe.contentX === 16
                    && leftProbe.contains(Qt.point(10, 80)) && !leftProbe.contains(Qt.point(421, 100))
                    && rightProbe.contains(Qt.point(30, 8)) && !rightProbe.contains(Qt.point(0, 15)) },
                { name: 'file-drop-circle-fits-tall-and-steps-aside-short', passed: demoDropZone.coreSize > 0
                    && demoShortDropZone.coreSize === 0 },
                { name: 'scroll-and-spin-components', passed: demoScroll.contentHeight > demoScroll.height && demoSpinBox.value === 3 },
                { name: 'requested-typeface-available', passed: Qt.fontFamilies().includes(Theme.tokens.fontFamily) },
                { name: 'section-header-sizes-badge-and-trailing', passed: headerWorks },
                { name: 'list-row-click-activates', passed: rowClickWorks },
                { name: 'list-row-space-activates', passed: rowSpaceWorks },
                { name: 'list-row-enter-activates', passed: rowEnterWorks },
                { name: 'list-row-ring-only-from-keyboard', passed: rowPointerHasNoRing && rowKeyboardRing },
                { name: 'list-row-trailing-control-keeps-its-click', passed: rowTrailingKeepsClick },
                { name: 'list-row-long-text-stays-inside', passed: rowLongStaysInside },
                { name: 'list-row-mirrors-trailing-slot', passed: rowMirrors },
                { name: 'chip-sizes-and-elides', passed: chipSizesWork },
                { name: 'chip-click-emits-toggled', passed: chipClickWorks },
                { name: 'chip-space-and-enter-emit-toggled', passed: chipKeyboardWorks },
                { name: 'chip-host-owns-checked', passed: chipHostOwnsChecked },
                { name: 'empty-state-sizes-and-wraps-inside', passed: emptySizesWork },
                { name: 'empty-state-action-emits', passed: emptyActionWorks }
            ]
            console.log("PENTAD_TEST " + JSON.stringify({
                status: checks.every(function(check) { return check.passed; }) ? "pass" : "fail",
                checks: checks
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
