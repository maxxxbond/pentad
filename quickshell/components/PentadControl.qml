pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls.Basic
import qs.theme

Item {
    id: root
    property var definition: ({})
    property var controlState: ({})
    property string presentation: "tile"
    property var popupManager: null
    property bool contextOpened: false
    readonly property var capabilities: definition && definition.capabilities
        ? definition.capabilities : ({})
    readonly property bool compatible: !definition
        || (Array.isArray(definition.templates) && definition.templates.includes(presentation))
    readonly property bool hasDetails: !!capabilities.details
    readonly property bool hasChoice: !!capabilities.choice
    readonly property bool rowToggleDetails: presentation === "row" && hasDetails && !!capabilities.toggle
    readonly property real radioDiameter: Math.max(0, Math.min(40, height - 8))
    readonly property real radioInset: (height - radioDiameter) / 2
    readonly property bool discIndicator: (presentation === "row" || presentation === "compact")
        && !rowToggleDetails
    readonly property bool active: !!(controlState && controlState.active)
    // A standing button: the icon over a centred label, in the tile's card with its corner arrow.
    readonly property bool upright: presentation === "vertical"
    readonly property bool card: presentation === "tile" || upright
    // A tile shows "on" by its fill, like the round toggles; rows show it on their disc.
    readonly property bool filledActive: active && card
    // Hover lays an accent tint over the disc so it reads as pressable on the raised and the hovered row alike.
    readonly property color hoverDisc: Qt.tint(Theme.tokens.surfaceOverlay, Qt.alpha(Theme.tokens.accent, 0.4))
    readonly property color ink: filledActive ? Theme.tokens.onAccent : Theme.tokens.text
    readonly property color mutedInk: filledActive ? Qt.alpha(Theme.tokens.onAccent, 0.78) : Theme.tokens.textMuted
    readonly property bool hasChoices: !!(controlState && Array.isArray(controlState.choices)
        && controlState.choices.length > 0)
    readonly property bool showChoice: hasChoice && hasChoices
        && presentation === "tile"
    readonly property bool available: !controlState || controlState.available !== false
    readonly property bool pending: !!(controlState && controlState.pending)
    // Only the labels this presentation shows count; the hidden ones have no room and always elide.
    readonly property bool textTruncated: rowToggleDetails
        ? detailsTitle.truncated || (detailsSubtitle.visible && detailsSubtitle.truncated)
        : primaryTitle.truncated || (primarySubtitle.visible && primarySubtitle.truncated)
    readonly property string fullText: label + (controlState && controlState.subtitle ? "\n" + controlState.subtitle : "")
    readonly property string label: definition && definition.label ? String(definition.label) : "Control"
    readonly property alias primaryButton: primary
    readonly property alias detailsButton: details
    readonly property alias rangeControl: rangeControl
    readonly property alias rangeSlider: rangeControl.slider
    signal commandRequested(string action, var value)
    signal detailsRequested()
    signal contextRequested()

    implicitWidth: presentation === "icon" ? Metrics.controlLarge
        : presentation === "compact" ? 150
        : presentation === "tile" ? 180
        : presentation === "row" ? 300
        : presentation === "vertical" ? 96
        : presentation === "range-horizontal" ? rangeControl.implicitWidth
            + (capabilities.toggle ? Metrics.controlLarge : 0)
            + (hasDetails ? Metrics.controlLarge : 0)
        : presentation === "range-vertical" ? rangeControl.implicitWidth : Metrics.controlLarge
    implicitHeight: presentation === "icon" ? Metrics.controlLarge
        : presentation === "compact" ? Metrics.controlLarge
        : presentation === "tile" ? 72
        : presentation === "row" ? 48
        : presentation === "vertical" ? 104
        : presentation === "range-vertical" ? rangeControl.implicitHeight
            + (capabilities.toggle ? Metrics.controlLarge : 0)
            + (hasDetails ? Metrics.controlLarge : 0) : Metrics.controlLarge
    visible: compatible
    scale: (primary.down || details.down) && presentation !== "range-horizontal" && presentation !== "range-vertical" ? 0.97 : 1
    Behavior on scale { NumberAnimation { duration: Motion.press; easing.type: Easing.OutCubic } }
    activeFocusOnTab: !primary.enabled && !details.visible
        && !(rangeControl.visible && rangeControl.slider.enabled)
    Accessible.role: Accessible.Grouping
    Accessible.name: label
    Accessible.description: controlState && controlState.unavailableReason
        ? String(controlState.unavailableReason)
        : (controlState && controlState.error ? String(controlState.error) : pending ? "In progress" : "")

    function activatePrimary() {
        if (!compatible)
            return
        const lifecycle = definition && definition.lifecycle;
        const state = controlState && controlState.lifecycleState;
        const stateCommands = lifecycle && lifecycle.commands && lifecycle.commands[state];
        const action = capabilities.toggle || (stateCommands && stateCommands[0]) || capabilities.primary || ""
        if (action === "" && capabilities.range) { rangeMenu.toggle(); return; }
        if (action === "details" || (action === "" && hasChoice)) {
            openDetails()
            return
        }
        if (!available || pending || action === "")
            return
        commandRequested(String(action), capabilities.toggle ? !Boolean(controlState && controlState.active) : undefined)
    }

    function iconUrl() {
        const icon = definition && definition.icon ? String(definition.icon) : ""
        if (icon === "" || icon.includes(":") || icon.includes("/"))
            return icon
        if (icon.endsWith(".svg"))
            return Qt.resolvedUrl("../assets/icons/material/" + icon)
        const aliases = {
            "audio-volume-high-symbolic": "volume-up-symbolic",
            "audio-input-microphone-symbolic": "mic-symbolic",
            "camera-photo-symbolic": "photo-camera-symbolic",
            "notifications-disabled-symbolic": "controls/notifications-off-symbolic",
            "system-lock-screen-symbolic": "controls/lock-symbolic",
            "night-light-symbolic": "controls/dark-mode-symbolic",
            "power-profile-balanced-symbolic": "balance-symbolic",
            "network-vpn-symbolic": "controls/vpn-key-symbolic",
            "display-brightness-symbolic": "controls/light-mode-symbolic",
            "airplane-mode-symbolic": "controls/flight-symbolic",
            "bluetooth-symbolic": "controls/bluetooth-symbolic",
            "contrast-symbolic": "controls/contrast-symbolic",
        }
        return Qt.resolvedUrl("../assets/icons/material/" + (aliases[icon] || icon) + ".svg")
    }

    function openDetails() {
        detailsRequested()
    }

    function selectedChoiceLabel() {
        if (!controlState || !Array.isArray(controlState.choices))
            return ""
        const selected = controlState.choices.find(function(choice) {
            return choice && choice.id !== undefined
                ? choice.id === controlState.selectedId : choice === controlState.selectedId
        })
        if (selected && selected.label !== undefined)
            return String(selected.label)
        return controlState.selectedId !== undefined ? String(controlState.selectedId) : ""
    }

    function compactLabel() {
        if (controlState && Number.isFinite(controlState.value)) {
            const range = capabilities.range;
            const value = range ? Math.round(controlState.value * (range.scale || 1)) + (range.unit || "") : String(controlState.value);
            return label + "  " + value;
        }
        const choice = selectedChoiceLabel()
        return choice !== "" ? label + "  " + choice : label
    }

    function openContext() {
        contextRequested()
    }

    function selectChoice(choice) {
        if (!compatible || !available || pending || !hasChoice)
            return
        const action = String(capabilities.choice)
        const value = choice && choice.id !== undefined ? choice.id : choice
        commandRequested(action, value)
    }

    ContinuousSurface {
        id: sharedSurface
        anchors.fill: parent
        visible: !root.rowToggleDetails
            && (root.card || root.presentation === "compact" || root.presentation === "row")
        fill: root.contextOpened || choiceMenu.opened || rangeMenu.opened ? Theme.tokens.surface
            : root.filledActive ? (primary.down || primary.hovered ? Qt.lighter(Theme.tokens.accent, 1.08) : Theme.tokens.accent)
            : primary.down || primary.hovered || details.down || details.hovered
            || (root.active && !root.discIndicator)
            ? Theme.tokens.surfaceOverlay : Theme.tokens.surfaceRaised
        edge: primary.activeFocus || details.activeFocus ? Theme.tokens.accent : "transparent"
        extent: root.discIndicator ? Metrics.radiusPill
            : root.card ? Metrics.radiusLarge : Metrics.radiusMedium
        Behavior on fill { ColorAnimation { duration: Motion.state } }
    }

    Rectangle {
        id: radioSurface
        anchors.fill: parent
        visible: root.rowToggleDetails
        radius: height / 2
        color: root.contextOpened ? Theme.tokens.surface
            : details.down || details.hovered ? Theme.tokens.surfaceOverlay : Theme.tokens.surfaceRaised
        border.width: details.visualFocus ? 1 : 0
        border.color: Theme.tokens.accent
        Behavior on color { ColorAnimation { duration: Motion.state } }
    }

    PentadRangeControl {
        id: rangeControl
        visible: root.presentation === "range-horizontal" || root.presentation === "range-vertical"
        x: root.presentation === "range-horizontal" && root.capabilities.toggle ? Metrics.controlLarge
            : root.presentation === "range-vertical" ? (root.width - Metrics.controlLarge) / 2 : 0
        y: root.presentation === "range-vertical" && root.capabilities.toggle ? Metrics.controlLarge : 0
        width: root.presentation === "range-horizontal"
            ? Math.max(0, root.width - (root.capabilities.toggle ? Metrics.controlLarge : 0)
                - (root.hasDetails ? Metrics.controlLarge : 0))
            : root.presentation === "range-vertical" ? Metrics.controlLarge : root.width
        height: root.presentation === "range-vertical"
            ? Math.max(0, root.height - (root.capabilities.toggle ? Metrics.controlLarge : 0)
                - (root.hasDetails ? Metrics.controlLarge : 0)) : root.height
        definition: root.definition
        controlState: root.controlState
        presentation: root.presentation
        onCommandRequested: function(action, value) { root.commandRequested(action, value) }
    }

    Button {
        id: primary
        objectName: "controlPrimary"
        visible: root.presentation === "range-horizontal" || root.presentation === "range-vertical"
            ? !!root.capabilities.toggle
            : true
        enabled: (root.available && !root.pending && (!!root.capabilities.primary || !!root.capabilities.toggle || root.hasChoice || !!root.capabilities.range)) || root.capabilities.primary === "details"
            || (!root.capabilities.toggle && root.hasChoice)
        focusPolicy: Qt.StrongFocus
        Accessible.name: root.label
        Accessible.role: root.capabilities.toggle ? Accessible.CheckBox : Accessible.Button
        Accessible.checked: root.capabilities.toggle ? !!(root.controlState && root.controlState.active) : false
        Accessible.description: root.controlState && root.controlState.unavailableReason
            ? String(root.controlState.unavailableReason)
            : (root.pending ? "In progress" : root.controlState && root.controlState.error ? String(root.controlState.error) : "")
        x: root.rowToggleDetails ? root.radioInset : root.presentation === "range-vertical"
            ? (root.width - Metrics.controlLarge) / 2 : 0
        width: root.rowToggleDetails ? root.radioDiameter
            : root.presentation === "icon" ? root.width
            : root.presentation === "range-horizontal"
            || root.presentation === "range-vertical" ? Metrics.controlLarge
            : root.presentation === "compact" || root.presentation === "row"
                ? Math.max(0, root.width - (root.hasDetails ? 34 : 0)) : root.width
        y: root.rowToggleDetails ? (root.height - height) / 2 : 0
        height: root.rowToggleDetails ? root.radioDiameter
            : root.presentation === "icon" ? root.height
            : root.presentation === "range-horizontal" || root.presentation === "range-vertical"
            ? Metrics.controlLarge
            : root.height
        z: root.rowToggleDetails ? 2 : 1
        ToolTip.visible: hovered && (root.presentation === "icon" || (root.textTruncated && !root.rowToggleDetails))
        ToolTip.delay: 500
        ToolTip.text: root.fullText
        onPressed: root.activatePrimary()
        HoverHandler { cursorShape: primary.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor }
        background: Item {
            ContinuousSurface {
                anchors.fill: parent
                visible: !root.rowToggleDetails
                    && (root.presentation === "range-horizontal" || root.presentation === "range-vertical")
                fill: root.contextOpened || choiceMenu.opened || rangeMenu.opened ? Theme.tokens.surface
                    : primary.down || primary.hovered || root.active
                    ? Theme.tokens.surfaceOverlay : Theme.tokens.surfaceRaised
                edge: primary.activeFocus ? Theme.tokens.accent : "transparent"
                extent: Metrics.radiusMedium
                opacity: primary.enabled ? 1 : 0.58
            }
            // A round toggle is a true circle or stadium, the same curve as the discs inside rows (R1).
            Rectangle {
                anchors.fill: parent
                visible: root.presentation === "icon"
                radius: Math.min(width, height) / 2
                color: root.contextOpened ? Theme.tokens.surface
                    : root.active ? (primary.down || primary.hovered ? Qt.lighter(Theme.tokens.accent, 1.08) : Theme.tokens.accent)
                    : primary.down || primary.hovered ? root.hoverDisc : Theme.tokens.surfaceRaised
                border.width: primary.visualFocus ? 1 : 0
                border.color: root.active ? Theme.tokens.onAccent : Theme.tokens.accent
                opacity: primary.enabled ? 1 : 0.58
                Behavior on color { ColorAnimation { duration: Motion.state } }
                Behavior on opacity { NumberAnimation { duration: Motion.state } }
            }
            Rectangle {
                x: root.radioInset
                y: (parent.height - height) / 2
                width: root.radioDiameter
                height: width
                visible: root.discIndicator
                radius: height / 2
                color: root.active ? Theme.tokens.accent
                    : primary.down || primary.hovered ? root.hoverDisc : Theme.tokens.surfaceOverlay
                opacity: primary.enabled ? 1 : 0.58
                Behavior on color { ColorAnimation { duration: Motion.state } }
            }
            Rectangle {
                anchors.fill: parent
                visible: root.rowToggleDetails
                radius: height / 2
                color: root.controlState && root.controlState.active ? Theme.tokens.accent
                    : primary.down || primary.hovered ? root.hoverDisc : Theme.tokens.surfaceOverlay
                border.width: primary.visualFocus ? 1 : 0
                border.color: Theme.tokens.accent
                opacity: primary.enabled ? 1 : 0.58
                Behavior on color { ColorAnimation { duration: Motion.state } }
            }
        }
        contentItem: Item {
            PentadIcon {
                id: mainIcon
                objectName: "controlIcon"
                source: root.iconUrl()
                pixelSize: Metrics.menuIcon
                color: (root.rowToggleDetails || root.discIndicator || root.presentation === "icon" || root.filledActive)
                        && root.active && !(root.controlState && root.controlState.error) ? Theme.tokens.onAccent
                    : root.controlState && root.controlState.error ? Theme.tokens.error
                    : Theme.tokens.text
                Behavior on color { ColorAnimation { duration: Motion.state } }
                // The disc is drawn on the background, which the button's padding does not shift,
                // so the icon steps back by that padding to sit in the disc's centre.
                x: root.rowToggleDetails ? (parent.width - width) / 2
                    : root.discIndicator ? root.radioInset + (root.radioDiameter - width) / 2 - primary.leftPadding
                    : root.presentation === "icon" || root.presentation === "range-vertical" || root.upright
                    ? (parent.width - width) / 2 : 12
                y: root.presentation === "tile" ? 12
                    : root.upright ? Math.max(0, (parent.height - height - 8 - primaryText.height) / 2)
                    : (parent.height - height) / 2
                Accessible.ignored: true
            }
            Column {
                id: primaryText
                objectName: "controlText"
                visible: !root.rowToggleDetails && root.presentation !== "icon" && root.presentation !== "range-horizontal"
                    && root.presentation !== "range-vertical"
                x: root.presentation === "tile" ? 12
                    : root.upright ? 0
                    : root.discIndicator ? root.radioInset + root.radioDiameter + 10
                    : mainIcon.x + mainIcon.width + 10
                y: root.presentation === "tile"
                    ? parent.height - height - (root.showChoice ? Metrics.controlMedium + 12 : 12)
                    : root.upright ? mainIcon.y + mainIcon.height + 8
                    : (parent.height - height) / 2
                width: Math.max(0, parent.width - x - (root.presentation === "tile" ? 12 : root.upright ? 0 : 8))
                PentadText {
                    id: primaryTitle
                    solid: true
                    width: parent.width
                    text: root.presentation === "compact" ? root.compactLabel() : root.label
                    color: !root.available ? root.mutedInk : root.ink
                    Behavior on color { ColorAnimation { duration: Motion.state } }
                    font.family: Theme.tokens.fontFamily
                    font.pixelSize: Metrics.textBody
                    horizontalAlignment: root.upright ? Text.AlignHCenter : Text.AlignLeft
                    elide: root.presentation === "tile" ? Text.ElideNone : Text.ElideRight
                    maximumLineCount: root.card ? 2 : 1
                    wrapMode: root.presentation === "tile" ? Text.WordWrap
                        : root.upright ? Text.WrapAtWordBoundaryOrAnywhere : Text.NoWrap
                }
                PentadText {
                    id: primarySubtitle
                    solid: true
                    visible: root.presentation !== "compact"
                        && !!(root.controlState && (root.controlState.error || root.controlState.subtitle || root.controlState.unavailableReason))
                    width: parent.width
                    text: root.controlState && root.controlState.error ? String(root.controlState.error)
                        : root.controlState && root.controlState.unavailableReason
                        ? String(root.controlState.unavailableReason) : String(root.controlState.subtitle || "")
                    color: root.mutedInk
                    font.family: Theme.tokens.fontFamily
                    font.pixelSize: Metrics.textCaption
                    horizontalAlignment: root.upright ? Text.AlignHCenter : Text.AlignLeft
                    elide: root.presentation === "tile" ? Text.ElideNone : Text.ElideRight
                    // A standing button has room for a second status line while its title fits on one.
                    maximumLineCount: root.presentation === "tile" || (root.upright && primaryTitle.lineCount < 2) ? 2 : 1
                    wrapMode: root.presentation === "tile" ? Text.WordWrap
                        : root.upright ? Text.WrapAtWordBoundaryOrAnywhere : Text.NoWrap
                }
            }
            Text {
                visible: !root.rowToggleDetails && (root.pending || !!(root.controlState && root.controlState.error))
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 6
                text: root.controlState && root.controlState.error ? "!" : "…"
                color: root.controlState && root.controlState.error ? Theme.tokens.error : Theme.tokens.textMuted
                font.pixelSize: Metrics.textBody
                Accessible.ignored: true
            }
        }
    }

    Button {
        id: details
        objectName: "controlDetails"
        visible: root.hasDetails && root.presentation !== "icon"
        enabled: true
        focusPolicy: Qt.StrongFocus
        Accessible.name: root.label + " details"
        Accessible.role: Accessible.Button
        Accessible.description: root.controlState && root.controlState.unavailableReason
            ? String(root.controlState.unavailableReason) : ""
        z: root.rowToggleDetails ? 1 : 3
        x: root.rowToggleDetails ? 0 : root.presentation === "range-vertical" ? (root.width - width) / 2
            : root.width - width - (root.card ? 4 : 0)
        y: root.presentation === "range-vertical" ? root.height - height
            : root.card ? 4 : 0
        // A standing button keeps its arrow a little smaller so it clears the centred icon at one cell wide.
        width: root.rowToggleDetails ? root.width : root.upright ? 24 : root.card ? 28
            : root.presentation === "compact" || root.presentation === "row" ? 34 : Metrics.controlLarge
        height: root.upright ? 24 : root.card ? 28
            : root.presentation === "range-vertical" ? Metrics.controlLarge
            : root.presentation === "range-horizontal" ? root.height : root.height
        ToolTip.visible: hovered && root.textTruncated && root.rowToggleDetails
        ToolTip.delay: 500
        ToolTip.text: root.fullText
        onPressed: root.openDetails()
        HoverHandler { cursorShape: Qt.PointingHandCursor }
        background: Item {
            ContinuousSurface {
                anchors.fill: parent
                visible: !root.rowToggleDetails
                    && (root.presentation === "range-horizontal" || root.presentation === "range-vertical")
                fill: details.down || details.hovered ? Theme.tokens.surfaceOverlay : Theme.tokens.surfaceRaised
                edge: details.activeFocus ? Theme.tokens.accent : "transparent"
                extent: Metrics.radiusMedium
            }
            // The arrow of a tile, compact or row control gets a round halo so it reads as its own button.
            Rectangle {
                anchors.centerIn: parent
                width: Math.min(32, parent.width, parent.height)
                height: width
                radius: width / 2
                visible: !root.rowToggleDetails && root.presentation !== "range-horizontal"
                    && root.presentation !== "range-vertical"
                color: Qt.alpha(root.ink, details.down ? 0.22 : 0.14)
                opacity: details.down || details.hovered ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: Motion.state } }
            }
        }
        contentItem: Item {
            Column {
                visible: root.rowToggleDetails
                x: primary.x + primary.width + 10
                width: Math.max(0, parent.width - x - 40)
                anchors.verticalCenter: parent.verticalCenter
                PentadText {
                    id: detailsTitle
                    solid: true
                    wrapMode: Text.NoWrap
                    width: parent.width
                    text: root.label
                    color: root.available ? Theme.tokens.text : Theme.tokens.textMuted
                    font.family: Theme.tokens.fontFamily
                    font.pixelSize: Metrics.textBody
                    elide: Text.ElideRight
                    maximumLineCount: 1
                }
                PentadText {
                    id: detailsSubtitle
                    solid: true
                    wrapMode: Text.NoWrap
                    visible: !!(root.controlState && (root.controlState.error || root.controlState.subtitle || root.controlState.unavailableReason))
                    width: parent.width
                    text: root.controlState && root.controlState.error ? String(root.controlState.error)
                        : root.controlState && root.controlState.unavailableReason
                        ? String(root.controlState.unavailableReason) : String(root.controlState.subtitle || "")
                    color: Theme.tokens.textMuted
                    font.family: Theme.tokens.fontFamily
                    font.pixelSize: Metrics.textCaption
                    elide: Text.ElideRight
                    maximumLineCount: 1
                }
            }
            PentadChevron {
                visible: root.rowToggleDetails
                anchors.right: parent.right
                anchors.rightMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                engaged: details.hovered || details.visualFocus || details.down
            }
            Text {
                visible: root.rowToggleDetails && (root.pending || !!(root.controlState && root.controlState.error))
                anchors.right: parent.right
                anchors.rightMargin: 32
                anchors.verticalCenter: parent.verticalCenter
                text: root.controlState && root.controlState.error ? "!" : "…"
                color: root.controlState && root.controlState.error ? Theme.tokens.error : Theme.tokens.textMuted
                font.pixelSize: Metrics.textBody
            }
            PentadChevron {
                visible: !root.rowToggleDetails
                anchors.centerIn: parent
                color: root.ink
                engaged: details.hovered || details.visualFocus || details.down
            }
        }
    }

    GeometryOverlay {
        anchors.fill: parent
        visible: GeometryDiagnostics.enabled && root.rowToggleDetails
        innerRect: Qt.rect(primary.x, primary.y, primary.width, primary.height)
        outerRadius: radioSurface.radius
        innerRadius: primary.height / 2
        outerCurve: "circular"
        innerCurve: "circular"
        outerContour: ""
    }

    Button {
        id: choiceButton
        objectName: "controlChoice"
        visible: root.showChoice
        enabled: root.available && !root.pending
        x: root.presentation === "tile" ? 0 : Math.max(0, primary.width - width)
        y: root.presentation === "tile" ? root.height - height : 0
        z: 2
        width: primary.width
        height: Metrics.controlMedium
        Accessible.name: root.label + " selection"
        Accessible.role: Accessible.Button
        onPressed: choiceMenu.open()
        background: ContinuousSurface {
            fill: choiceButton.down || choiceButton.hovered ? Theme.tokens.surfaceOverlay : Theme.tokens.surfaceRaised
            edge: choiceButton.activeFocus ? Theme.tokens.accent : "transparent"
            extent: Metrics.radiusMedium
        }
        contentItem: Text {
            text: root.selectedChoiceLabel() !== "" ? root.selectedChoiceLabel() + "  ⌄" : "Choose  ⌄"
            color: Theme.tokens.text
            font.family: Theme.tokens.fontFamily
            font.pixelSize: Metrics.textCaption
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
        }
    }

    AttachedPopover {
        id: rangeMenu
        anchorItem: primary
        manager: root.popupManager
        pointerDismissEnabled: false
        contentItem: PentadRangeControl {
            width: 220
            definition: root.definition
            controlState: root.controlState
            onCommandRequested: function(action, value) { root.commandRequested(action, value); }
        }
    }

    AttachedPopover {
        id: choiceMenu
        anchorItem: choiceButton
        manager: root.popupManager
        contentItem: ScrollView {
            id: choiceScroll
            width: 220
            implicitHeight: Math.min(240, choiceRows.implicitHeight)
            contentWidth: availableWidth
            contentHeight: choiceRows.implicitHeight
            clip: true
            ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
            Column {
                id: choiceRows
                width: choiceScroll.availableWidth
                spacing: 4
                Repeater {
                    model: root.controlState && Array.isArray(root.controlState.choices) ? root.controlState.choices : []
                    PentadButton {
                        required property var modelData
                        width: parent.width
                        controlHeight: 28
                        text: modelData && modelData.label !== undefined ? String(modelData.label)
                            : modelData && modelData.id !== undefined ? String(modelData.id) : String(modelData)
                        checked: root.controlState && (modelData && modelData.id !== undefined ? modelData.id : modelData)
                            === root.controlState.selectedId
                        requestedEnabled: root.available && !root.pending
                        onPressed: { root.selectChoice(modelData); choiceMenu.close(); }
                    }
                }
                }
        }
    }

    Text {
        objectName: "controlStatus"
        visible: rangeControl.visible && (root.pending || !!(root.controlState && root.controlState.error))
        x: root.presentation === "range-horizontal" ? rangeControl.x + rangeControl.width - width : 0
        y: root.presentation === "range-vertical" ? rangeControl.y : 0
        width: 18
        height: 18
        text: root.controlState && root.controlState.error ? "!" : "…"
        color: root.controlState && root.controlState.error ? Theme.tokens.error : Theme.tokens.textMuted
        font.family: Theme.tokens.fontFamily
        font.pixelSize: Metrics.textBody
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        Accessible.ignored: true
    }

    MouseArea {
        anchors.fill: parent
        z: 10
        acceptedButtons: Qt.RightButton
        hoverEnabled: false
        onPressed: root.openContext()
    }
    Keys.priority: Keys.BeforeItem
    Keys.onPressed: function(event) {
        if (event.key === Qt.Key_Menu || (event.key === Qt.Key_F10 && (event.modifiers & Qt.ShiftModifier))) {
            root.openContext()
            event.accepted = true
        }
    }
}
