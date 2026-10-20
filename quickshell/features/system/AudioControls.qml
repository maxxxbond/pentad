pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls.Basic
import qs.components
import qs.theme
import "../../logic/control-model.mjs" as Controls

Item {
    id: root
    required property var services
    property bool compact: false
    property var kinds: ["output", "input"]
    readonly property bool single: kinds.length === 1
    property string presentation: "range-horizontal"
    readonly property bool vertical: presentation === "range-vertical"
    readonly property bool ranged: vertical || presentation === "range-horizontal"
    // In the control-center grid the cell owns size and presentation: the slider fills
    // `levelHeight`, errors stay inside the capsule and the appearance menu asks the grid.
    property bool layoutManaged: false
    property real levelHeight: 160
    // The device chevron needs room at the top of an upright capsule.
    readonly property bool verticalPicker: levelHeight >= 150
    property string appearanceRequest: ""
    property string appearanceError: ""
    property string contextKind: "output"
    property bool detailsExpanded: false
    property string deviceSection: ""
    property var audioState: services.audio.state
    property string error: ""
    property string outputVolumeRequest: ""
    property string outputVolumeNode: ""
    property real outputDesired: 0
    property string inputVolumeRequest: ""
    property string inputVolumeNode: ""
    property real inputDesired: 0
    property string outputMuteRequest: ""
    property string outputMuteNode: ""
    property string inputMuteRequest: ""
    property string inputMuteNode: ""
    property string outputDefaultRequest: ""
    property string outputDefaultTarget: ""
    property string inputDefaultRequest: ""
    property string inputDefaultTarget: ""
    width: parent ? parent.width : 320
    implicitHeight: card.implicitHeight
    property alias compactOutputSlider: compactOutputSlider
    property alias compactInputSlider: compactInputSlider
    signal detailsRequested(string section)
    signal presentationRequested(string value)

    function handles(kind) { return kinds.indexOf(kind) >= 0; }
    function deviceFor(kind) {
        if (audioState.kind !== "ready") return null;
        return kind === "output" ? audioState.value.output : audioState.value.input;
    }
    function devicesFor(kind) {
        if (audioState.kind !== "ready") return [];
        return kind === "output" ? audioState.value.outputs : audioState.value.inputs;
    }
    function defaultStatus(kind) {
        const request = kind === "output" ? outputDefaultRequest : inputDefaultRequest;
        if (!request) return "";
        const targetId = kind === "output" ? outputDefaultTarget : inputDefaultTarget;
        const target = devicesFor(kind).find(function(item) { return item.id === targetId; });
        const actual = deviceFor(kind);
        return `Applying ${target ? target.label : "device"} · active ${actual ? actual.label : "unavailable"}`;
    }
    function volumeRequest(kind) { return kind === "output" ? outputVolumeRequest : inputVolumeRequest; }
    function desiredVolume(kind) { return kind === "output" ? outputDesired : inputDesired; }
    function setVolumeRequest(kind, requestId, nodeId, value) {
        if (kind === "output") {
            outputVolumeRequest = requestId; outputVolumeNode = nodeId; outputDesired = value;
        } else {
            inputVolumeRequest = requestId; inputVolumeNode = nodeId; inputDesired = value;
        }
    }
    function requestVolume(kind, value) {
        const device = deviceFor(kind);
        if (!device) return;
        const requestId = services.audio.setVolume(kind, value);
        setVolumeRequest(kind, requestId, device.id, value);
    }
    function requestMute(kind) {
        const device = deviceFor(kind);
        if (!device) return;
        const requestId = services.audio.toggleMute(kind);
        if (kind === "output") { outputMuteRequest = requestId; outputMuteNode = device.id; }
        else { inputMuteRequest = requestId; inputMuteNode = device.id; }
    }
    function requestDefault(kind, index) {
        const devices = devicesFor(kind);
        if (index < 0 || index >= devices.length) return;
        const target = devices[index];
        const requestId = services.audio.setDefault(kind, target.id);
        if (kind === "output") { outputDefaultRequest = requestId; outputDefaultTarget = target.id; }
        else { inputDefaultRequest = requestId; inputDefaultTarget = target.id; }
    }
    function handleCommand(requestId, result) {
        if (requestId === outputVolumeRequest || requestId === inputVolumeRequest) {
            const kind = requestId === outputVolumeRequest ? "output" : "input";
            const expectedId = kind === "output" ? outputVolumeNode : inputVolumeNode;
            const device = deviceFor(kind);
            if (kind === "output") outputVolumeRequest = ""; else inputVolumeRequest = "";
            if (!device || device.id !== expectedId) return;
            if (kind === "output") outputDesired = device.volume; else inputDesired = device.volume;
            if (!result.ok) error = `Could not change ${kind} volume (${result.reason || "failed"})`;
            else error = "";
        } else if (requestId === outputMuteRequest || requestId === inputMuteRequest) {
            const kind = requestId === outputMuteRequest ? "output" : "input";
            const expectedId = kind === "output" ? outputMuteNode : inputMuteNode;
            const device = deviceFor(kind);
            if (kind === "output") outputMuteRequest = ""; else inputMuteRequest = "";
            if (!device || device.id !== expectedId) return;
            error = result.ok ? "" : `Could not change ${kind} mute (${result.reason || "failed"})`;
        } else if (requestId === outputDefaultRequest || requestId === inputDefaultRequest) {
            const kind = requestId === outputDefaultRequest ? "output" : "input";
            const targetId = kind === "output" ? outputDefaultTarget : inputDefaultTarget;
            const present = devicesFor(kind).some(function(item) { return item.id === targetId; });
            if (kind === "output") outputDefaultRequest = ""; else inputDefaultRequest = "";
            if (!present) return;
            error = result.ok ? "" : `Could not select ${kind} device (${result.reason || "failed"})`;
        }
    }
    function refreshState() {
        const output = deviceFor("output");
        const input = deviceFor("input");
        if (outputVolumeRequest && (!output || output.id !== outputVolumeNode)) outputVolumeRequest = "";
        if (inputVolumeRequest && (!input || input.id !== inputVolumeNode)) inputVolumeRequest = "";
        if (outputMuteRequest && (!output || output.id !== outputMuteNode)) outputMuteRequest = "";
        if (inputMuteRequest && (!input || input.id !== inputMuteNode)) inputMuteRequest = "";
        if (!outputVolumeRequest) outputDesired = output ? output.volume : 0;
        if (!inputVolumeRequest) inputDesired = input ? input.volume : 0;
    }
    onAudioStateChanged: refreshState()

    Connections {
        target: root.services.audio
        function onCommandFinished(requestId, result) { root.handleCommand(requestId, result); }
    }

    function controlStateFor(kind) {
        const device = deviceFor(kind);
        return { available: !!device && services.audio.active && !services.audio.safeMode,
            active: !!device && device.muted, pending: !!(kind === "output" ? outputMuteRequest || outputDefaultRequest : inputMuteRequest || inputDefaultRequest),
            error: error, subtitle: device ? device.label : services.text("Недоступно", "Unavailable"),
            value: volumeRequest(kind) ? desiredVolume(kind) : device ? device.volume : 0,
            confirmedValue: device ? device.volume : NaN, selectedId: device ? device.id : "",
            choices: devicesFor(kind), unavailableReason: device ? "" : services.text("Немає пристрою", "No device") };
    }
    function showContext(kind, anchor) {
        const sameTrigger = appearanceMenu.anchorItem === anchor;
        contextKind = kind;
        appearanceError = "";
        appearanceMenu.anchorItem = anchor;
        if (appearanceMenu.opened && !sameTrigger) appearanceMenu.open();
        else appearanceMenu.toggle();
    }
    function savePresentation(value) {
        if (layoutManaged) { appearanceMenu.close(); presentationRequested(value); return; }
        if (appearanceRequest || !Controls.supportsTemplate(Controls.builtinDefinitions["audio-output"], value)) return;
        appearanceRequest = services.config.save("layout", Object.assign({}, services.config.documents.layout,
            { audioPresentation: value }));
    }
    Connections {
        target: root.services.config
        function onCommandFinished(requestId, result) {
            if (requestId !== root.appearanceRequest) return;
            root.appearanceRequest = "";
            root.appearanceError = result.ok ? "" : result.message || result.reason;
            if (result.ok) appearanceMenu.close();
        }
    }
    AttachedPopover {
        id: appearanceMenu
        manager: root.services.popups || null
        contentItem: Column {
            width: 228
            spacing: 4
            PentadButton {
                width: parent.width
                text: root.services.text("Обрати пристрій", "Choose device")
                onPressed: { appearanceMenu.close(); root.detailsRequested("audio-" + root.contextKind); }
            }
            PentadText { text: root.services.text("Вигляд", "Appearance"); role: "caption" }
            Flow {
                width: parent.width
                spacing: 4
                Repeater {
                    model: [
                        { value: "range-horizontal", uk: "Горизонтально", en: "Horizontal" },
                        { value: "range-vertical", uk: "Вертикально", en: "Vertical" },
                        { value: "icon", uk: "Іконка", en: "Icon" },
                        { value: "tile", uk: "Плитка", en: "Tile" }
                    ].filter(function(option) { return !root.layoutManaged || option.value.indexOf("range-") === 0; })
                    PentadButton {
                        required property var modelData
                        text: root.services.text(modelData.uk, modelData.en)
                        controlHeight: 28
                        checked: root.presentation === modelData.value
                        requestedEnabled: !root.appearanceRequest
                        onPressed: root.savePresentation(modelData.value)
                    }
                }
            }
            PentadText { width: parent.width; text: root.appearanceError; visible: text !== ""; role: "caption"; color: Theme.tokens.error }
        }
    }

    PentadCard {
        id: card
        width: root.width
        fill: root.compact ? "transparent" : Theme.tokens.surfaceRaised
        extent: root.compact ? 0 : Metrics.radiusLarge
        clipContent: !root.compact
        implicitHeight: content.implicitHeight + (root.compact ? 0 : 24)
        Column {
            id: content
            anchors.fill: parent
            anchors.margins: root.compact ? 0 : 12
            spacing: 8

            Row {
                visible: root.compact && !root.detailsExpanded && !root.ranged
                width: content.width
                height: root.presentation === "tile" ? 104 : 48
                spacing: 8
                Repeater {
                    model: root.kinds
                    PentadControl {
                        id: alternate
                        required property string modelData
                        width: root.single ? content.width : (content.width - 8) / 2
                        height: parent.height
                        popupManager: root.services.popups || null
                        contextOpened: appearanceMenu.opened && appearanceMenu.anchorItem === alternate
                        definition: Controls.controlDefinition("audio-" + modelData, {
                            label: root.services.text(modelData === "output" ? "Гучність" : "Мікрофон", modelData === "output" ? "Volume" : "Microphone"),
                            icon: Qt.resolvedUrl("../../assets/icons/material/" + (modelData === "output" ? "volume-up-symbolic.svg" : "media/mic-symbolic.svg")).toString()
                        })
                        controlState: root.controlStateFor(modelData)
                        presentation: root.presentation
                        onCommandRequested: function(action, value) {
                            if (action === "level") root.requestVolume(modelData, value);
                            else if (action === "mute") root.requestMute(modelData);
                            else if (action === "select") {
                                const index = root.devicesFor(modelData).findIndex(function(device) { return device.id === value; });
                                if (index >= 0) root.requestDefault(modelData, index);
                            }
                        }
                        onDetailsRequested: root.detailsRequested("audio-" + modelData)
                        onContextRequested: root.showContext(modelData, alternate)
                    }
                }
            }

            Row {
                visible: root.handles("output") && root.compact && !root.detailsExpanded && root.ranged
                width: content.width
                spacing: 8
                Item {
                    id: outputSliderHost
                    Keys.onPressed: function(event) {
                        if (event.key === Qt.Key_Menu || (event.key === Qt.Key_F10 && (event.modifiers & Qt.ShiftModifier))) {
                            root.showContext("output", outputSliderHost);
                            event.accepted = true;
                        }
                    }
                    width: content.width
                    height: root.vertical ? root.levelHeight : 48
                PentadSlider {
                    id: compactOutputSlider
                    joined: appearanceMenu.opened && appearanceMenu.anchorItem === outputSliderHost
                    width: outputSliderHost.width
                    height: outputSliderHost.height
                    orientation: root.vertical ? Qt.Vertical : Qt.Horizontal
                    thick: true
                    referenceStyle: true
                    trailingInset: !root.vertical ? 44 : root.verticalPicker ? 40 : 0
                    muted: !!root.deviceFor("output") && root.deviceFor("output").muted
                    iconSource: Qt.resolvedUrl("../../assets/icons/material/" + (muted ? "volume-off-symbolic.svg" : "volume-up-symbolic.svg"))
                    from: 0
                    to: 1
                    stepSize: 0.01
                    wheelStepSize: 0.02
                    label: root.layoutManaged && root.error ? root.error : muted ? root.services.text("Без звуку", "Muted") : root.services.text("Гучність", "Volume")
                    valueKnown: !!root.deviceFor("output")
                    confirmedValue: root.deviceFor("output") ? root.deviceFor("output").volume : NaN
                    valueText: root.deviceFor("output")
                        ? `${Math.round((root.volumeRequest("output") ? root.desiredVolume("output") : root.deviceFor("output").volume) * 100)}%`
                        : "—"
                    accessibleName: root.services.text("Гучність виводу", "Output volume")
                    enabled: root.services.audio.active && !root.services.audio.safeMode && !!root.deviceFor("output")
                    onMoved: root.requestVolume("output", value)
                    Binding {
                        target: compactOutputSlider
                        property: "value"
                        value: root.volumeRequest("output") ? root.desiredVolume("output")
                            : (root.deviceFor("output") ? root.deviceFor("output").volume : 0)
                    }
                }
                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.RightButton
                    onPressed: root.showContext("output", outputSliderHost)
                }
                Button {
                    id: outputMuteButton
                    objectName: "control-center-toggle-audio-output"
                    x: root.vertical ? (outputSliderHost.width - width) / 2 : 0
                    y: root.vertical ? outputSliderHost.height - height : 0
                    width: 44
                    height: 48
                    enabled: root.services.audio.active && !root.services.audio.safeMode && !!root.deviceFor("output") && !root.outputMuteRequest
                    Accessible.name: compactOutputSlider.muted ? root.services.text("Увімкнути звук", "Unmute output")
                        : root.services.text("Вимкнути звук", "Mute output")
                    onPressed: root.requestMute("output")
                    // A round halo around the icon says it is a button of its own, on the fill and the track alike.
                    background: Item {
                        Rectangle {
                            anchors.centerIn: parent
                            width: 40
                            height: 40
                            radius: width / 2
                            color: Qt.alpha(Theme.tokens.text, outputMuteButton.pressed ? 0.22 : 0.14)
                            opacity: outputMuteButton.enabled && (outputMuteButton.hovered || outputMuteButton.pressed) ? 1 : 0
                            border.width: outputMuteButton.activeFocus ? 2 : 0
                            border.color: Theme.tokens.accent
                            Behavior on opacity { NumberAnimation { duration: Motion.state } }
                        }
                    }
                    contentItem: Item { }
                    HoverHandler { cursorShape: outputMuteButton.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor }
                }
                PentadButton {
                    id: outputPicker
                    objectName: "control-center-details-audio-output"
                    visible: !root.vertical || root.verticalPicker
                    x: root.vertical ? (outputSliderHost.width - width) / 2 : outputSliderHost.width - width
                    width: 44
                    controlHeight: root.vertical ? 44 : 48
                    text: ""
                    accessibleName: root.services.text("Обрати аудіовихід", "Choose audio output")
                    requestedEnabled: root.services.audio.active
                    contentItem: Item {
                        PentadChevron {
                            anchors.centerIn: parent
                            color: Theme.tokens.text
                            engaged: outputPicker.hovered || outputPicker.visualFocus || outputPicker.down
                        }
                    }
                    background: Item {
                        Rectangle {
                            anchors.centerIn: parent
                            width: 40
                            height: 40
                            radius: width / 2
                            color: Qt.alpha(Theme.tokens.text, outputPicker.down ? 0.22 : 0.14)
                            opacity: outputPicker.down || outputPicker.hovered ? 1 : 0
                            border.width: outputPicker.activeFocus ? 2 : 0
                            border.color: Theme.tokens.accent
                            Behavior on opacity { NumberAnimation { duration: Motion.state } }
                        }
                    }
                    HoverHandler { cursorShape: Qt.PointingHandCursor }
                    onPressed: root.detailsRequested("audio-output")
                }
                }
            }

            Row {
                visible: root.handles("input") && root.compact && !root.detailsExpanded && root.ranged
                width: content.width
                spacing: 0
                Item {
                    id: inputSliderHost
                    Keys.onPressed: function(event) {
                        if (event.key === Qt.Key_Menu || (event.key === Qt.Key_F10 && (event.modifiers & Qt.ShiftModifier))) {
                            root.showContext("input", inputSliderHost);
                            event.accepted = true;
                        }
                    }
                    width: content.width
                    height: root.vertical ? root.levelHeight : 48
                PentadSlider {
                    id: compactInputSlider
                    joined: appearanceMenu.opened && appearanceMenu.anchorItem === inputSliderHost
                    width: inputSliderHost.width
                    height: inputSliderHost.height
                    orientation: root.vertical ? Qt.Vertical : Qt.Horizontal
                    thick: true
                    referenceStyle: true
                    trailingInset: !root.vertical ? 44 : root.verticalPicker ? 40 : 0
                    muted: !!root.deviceFor("input") && root.deviceFor("input").muted
                    iconSource: Qt.resolvedUrl("../../assets/icons/material/media/" + (muted ? "mic-off-symbolic.svg" : "mic-symbolic.svg"))
                    from: 0
                    to: 1
                    stepSize: 0.01
                    wheelStepSize: 0.02
                    label: root.layoutManaged && root.error ? root.error : muted ? root.services.text("Мікрофон вимкнено", "Microphone muted") : root.services.text("Мікрофон", "Microphone")
                    valueKnown: !!root.deviceFor("input")
                    confirmedValue: root.deviceFor("input") ? root.deviceFor("input").volume : NaN
                    valueText: root.deviceFor("input")
                        ? `${Math.round((root.volumeRequest("input") ? root.desiredVolume("input") : root.deviceFor("input").volume) * 100)}%`
                        : "—"
                    accessibleName: root.services.text("Гучність мікрофона", "Microphone level")
                    enabled: root.services.audio.active && !root.services.audio.safeMode && !!root.deviceFor("input")
                    onMoved: root.requestVolume("input", value)
                    Binding {
                        target: compactInputSlider
                        property: "value"
                        value: root.volumeRequest("input") ? root.desiredVolume("input")
                            : (root.deviceFor("input") ? root.deviceFor("input").volume : 0)
                    }
                }
                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.RightButton
                    onPressed: root.showContext("input", inputSliderHost)
                }
                Button {
                    id: inputMuteButton
                    objectName: "control-center-toggle-audio-input"
                    x: root.vertical ? (inputSliderHost.width - width) / 2 : 0
                    y: root.vertical ? inputSliderHost.height - height : 0
                    width: 44
                    height: 48
                    enabled: root.services.audio.active && !root.services.audio.safeMode && !!root.deviceFor("input") && !root.inputMuteRequest
                    Accessible.name: compactInputSlider.muted ? root.services.text("Увімкнути мікрофон", "Unmute microphone")
                        : root.services.text("Вимкнути мікрофон", "Mute microphone")
                    onPressed: root.requestMute("input")
                    // A round halo around the icon says it is a button of its own, on the fill and the track alike.
                    background: Item {
                        Rectangle {
                            anchors.centerIn: parent
                            width: 40
                            height: 40
                            radius: width / 2
                            color: Qt.alpha(Theme.tokens.text, inputMuteButton.pressed ? 0.22 : 0.14)
                            opacity: inputMuteButton.enabled && (inputMuteButton.hovered || inputMuteButton.pressed) ? 1 : 0
                            border.width: inputMuteButton.activeFocus ? 2 : 0
                            border.color: Theme.tokens.accent
                            Behavior on opacity { NumberAnimation { duration: Motion.state } }
                        }
                    }
                    contentItem: Item { }
                    HoverHandler { cursorShape: inputMuteButton.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor }
                }
                PentadButton {
                    id: inputPicker
                    objectName: "control-center-details-audio-input"
                    visible: !root.vertical || root.verticalPicker
                    x: root.vertical ? (inputSliderHost.width - width) / 2 : inputSliderHost.width - width
                    width: 44
                    controlHeight: root.vertical ? 44 : 48
                    text: ""
                    accessibleName: root.services.text("Вибір мікрофона", "Choose microphone")
                    requestedEnabled: root.services.audio.active
                    contentItem: Item {
                        PentadChevron {
                            anchors.centerIn: parent
                            color: Theme.tokens.text
                            engaged: inputPicker.hovered || inputPicker.visualFocus || inputPicker.down
                        }
                    }
                    background: Item {
                        Rectangle {
                            anchors.centerIn: parent
                            width: 40
                            height: 40
                            radius: width / 2
                            color: Qt.alpha(Theme.tokens.text, inputPicker.down ? 0.22 : 0.14)
                            opacity: inputPicker.down || inputPicker.hovered ? 1 : 0
                            border.width: inputPicker.activeFocus ? 2 : 0
                            border.color: Theme.tokens.accent
                            Behavior on opacity { NumberAnimation { duration: Motion.state } }
                        }
                    }
                    HoverHandler { cursorShape: Qt.PointingHandCursor }
                    onPressed: root.detailsRequested("audio-input")
                }
                }
            }

            Repeater {
                visible: !root.compact || root.detailsExpanded
                model: (root.deviceSection === "audio-output" ? ["output"]
                    : root.deviceSection === "audio-input" ? ["input"] : ["output", "input"]).filter(function(kind) {
                        return root.handles(kind);
                    })
                delegate: Column {
                    id: section
                    required property string modelData
                    visible: !root.compact || root.detailsExpanded
                    readonly property string kind: modelData
                    readonly property var device: root.deviceFor(kind)
                    readonly property var devices: root.devicesFor(kind)
                    width: content.width
                    spacing: 6

                    PentadText {
                        visible: !root.compact
                        text: section.kind === "output" ? "Output" : "Input"
                        role: "section"
                    }
                    PentadComboBox {
                        id: selector
                        visible: !root.compact
                        width: section.width
                        model: section.devices
                        textRole: "label"
                        displayText: currentIndex >= 0 && currentIndex < section.devices.length
                            ? (section.devices[currentIndex].shortLabel || section.devices[currentIndex].label) : ""
                        currentIndex: section.devices.findIndex(function(item) {
                            return section.device && item.id === section.device.id;
                        })
                        enabled: root.services.audio.active && !root.services.audio.safeMode && section.devices.length > 0
                        Accessible.name: section.kind === "output" ? "Default audio output" : "Default audio input"
                        Accessible.description: section.device ? section.device.label : ""
                        ToolTip.text: section.device ? section.device.label : ""
                        ToolTip.visible: (hovered || activeFocus) && ToolTip.text !== ""
                        ToolTip.delay: 700
                        onActivated: function(index) { root.requestDefault(section.kind, index); }
                        delegate: ItemDelegate {
                            id: deviceOption
                            required property int index
                            required property var modelData
                            readonly property bool selected: !!section.device && modelData.id === section.device.id
                            width: selector.popup.width
                            implicitHeight: 52
                            highlighted: selector.highlightedIndex === index
                            Accessible.name: modelData.label
                            Accessible.description: selected ? root.services.text("Вибрано", "Selected") : ""
                            ToolTip.text: modelData.label
                            ToolTip.visible: hovered || activeFocus
                            ToolTip.delay: 700
                            contentItem: Row {
                                spacing: 10
                                PentadIcon {
                                    anchors.verticalCenter: parent.verticalCenter
                                    source: Qt.resolvedUrl("../../assets/icons/" + (deviceOption.modelData.icon
                                        || (section.kind === "input" ? "material/media/mic-symbolic.svg" : "material/volume-up-symbolic.svg")))
                                    pixelSize: Metrics.menuIcon
                                    color: deviceOption.selected ? Theme.tokens.accent : Theme.tokens.textMuted
                                    Accessible.ignored: true
                                }
                                Text {
                                    width: Math.max(0, parent.width - Metrics.menuIcon - 38)
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: deviceOption.modelData.shortLabel || deviceOption.modelData.label
                                    elide: Text.ElideRight
                                    color: Theme.tokens.text
                                    font.family: Theme.tokens.fontFamily
                                    font.pixelSize: Metrics.textBody
                                    Accessible.ignored: true
                                }
                                PentadIcon {
                                    anchors.verticalCenter: parent.verticalCenter
                                    visible: deviceOption.selected
                                    source: Qt.resolvedUrl("../../assets/icons/material/screenshot/check-symbolic.svg")
                                    pixelSize: Metrics.textBody
                                    color: Theme.tokens.accent
                                    Accessible.ignored: true
                                }
                            }
                            MouseArea {
                                anchors.fill: parent
                                onPressed: {
                                    selector.currentIndex = deviceOption.index;
                                    selector.activated(deviceOption.index);
                                    selector.popup.close();
                                }
                            }
                        }
                        contentItem: Text {
                            leftPadding: 10
                            rightPadding: selector.indicator.width + 8
                            text: selector.displayText || (section.kind === "output" ? "No output devices" : "No input devices")
                            color: selector.enabled ? Theme.tokens.text : Theme.tokens.textMuted
                            font.family: Theme.tokens.fontFamily
                            font.pixelSize: Metrics.textBody
                            verticalAlignment: Text.AlignVCenter
                            elide: Text.ElideRight
                        }
                        background: ContinuousSurface {
                            fill: Theme.tokens.surface
                            edge: selector.activeFocus ? Theme.tokens.accent : Theme.tokens.outline
                            extent: Metrics.radiusSmall
                        }
                    }
                    Repeater {
                        model: root.compact ? section.devices : []
                        delegate: SelectorOption {
                            required property var modelData
                            required property int index
                            width: section.width
                            text: modelData.shortLabel || modelData.label
                            tooltipText: modelData.label
                            iconSource: Qt.resolvedUrl("../../assets/icons/" + (modelData.icon
                                || (section.kind === "input" ? "material/media/mic-symbolic.svg" : "material/volume-up-symbolic.svg")))
                            selected: !!section.device && modelData.id === section.device.id
                            accessibleName: modelData.label + (section.device && modelData.id === section.device.id
                                ? root.services.text(" · вибрано", " · selected") : "")
                            enabled: !!section && root.services.audio.active && !root.services.audio.safeMode
                                && !(section.kind === "output" ? root.outputDefaultRequest : root.inputDefaultRequest)
                            onPressed: root.requestDefault(section.kind, index)
                        }
                    }
                    PentadText {
                        visible: root.compact && section.devices.length === 0
                        text: section.kind === "output"
                            ? root.services.text("Немає аудіовиходів", "No audio outputs")
                            : root.services.text("Немає мікрофонів", "No microphones")
                        role: "caption"
                        color: Theme.tokens.textMuted
                    }
                    PentadText {
                        visible: section.kind === "output" ? !!root.outputDefaultRequest : !!root.inputDefaultRequest
                        text: root.defaultStatus(section.kind)
                        color: Theme.tokens.textMuted
                        role: "caption"
                    }
                    Row {
                        id: volumeRow
                        visible: !root.compact
                        width: section.width
                        spacing: 8
                        PentadButton {
                            id: muteButton
                            text: ""
                            accessibleName: section.kind === "output" ? "Toggle output mute" : "Toggle input mute"
                            contentItem: Text {
                                text: section.kind === "output"
                                ? (section.device && section.device.muted ? "volume_off" : "volume_up")
                                : (section.device && section.device.muted ? "mic_off" : "mic")
                                color: parent.enabled ? Theme.tokens.text : Theme.tokens.textMuted
                                font.family: "Material Symbols Rounded"
                                font.pixelSize: Metrics.statusIcon
                                font.weight: Font.Medium
                                font.variableAxes: ({ FILL: 1, wght: 500, GRAD: 0, opsz: Metrics.statusIcon })
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }
                            requestedEnabled: root.services.audio.active && !root.services.audio.safeMode && !!section.device
                            pending: section.kind === "output" ? !!root.outputMuteRequest : !!root.inputMuteRequest
                            onPressed: root.requestMute(section.kind)
                        }
                        PentadSlider {
                            id: volumeSlider
                            visible: !root.compact || section.kind === "input"
                            width: visible ? Math.max(0, section.width - muteButton.width - volumeValue.width - 2 * volumeRow.spacing) : 0
                            from: 0
                            to: 1
                            stepSize: 0.01
                            wheelStepSize: 0.02
                            accessibleName: section.kind === "output" ? "Output volume" : "Input volume"
                            enabled: root.services.audio.active && !root.services.audio.safeMode && !!section.device
                            onMoved: root.requestVolume(section.kind, value)
                            Binding {
                                target: volumeSlider
                                property: "value"
                                value: root.volumeRequest(section.kind)
                                    ? root.desiredVolume(section.kind)
                                    : (section.device ? section.device.volume : 0)
                            }
                        }
                        PentadText {
                            id: volumeValue
                            visible: volumeSlider.visible
                            anchors.verticalCenter: parent.verticalCenter
                            width: 48
                            horizontalAlignment: Text.AlignRight
                            text: {
                                const actual = section.device ? Math.round(section.device.volume * 100) : 0;
                                const desired = Math.round(root.desiredVolume(section.kind) * 100);
                                return root.volumeRequest(section.kind)
                                    ? `${desired}% → ${actual}%` : `${actual}%`;
                            }
                            role: "caption"
                        }
                    }
                    Rectangle {
                        width: section.width
                        height: 1
                        color: Theme.tokens.outline
                        opacity: 0.35
                        visible: !root.compact && section.kind === "output"
                    }
                }
            }
            PentadText { text: root.error; color: Theme.tokens.error; visible: text !== "" && !root.layoutManaged; role: "caption" }
        }
    }
}
