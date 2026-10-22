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
    property alias compactOutputSlider: outputLevel.slider
    property alias compactInputSlider: inputLevel.slider
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
        appearanceMenu.appearanceError = "";
        appearanceMenu.anchorItem = anchor;
        if (appearanceMenu.opened && !sameTrigger) appearanceMenu.open();
        else appearanceMenu.toggle();
    }
    AudioAppearanceMenu {
        id: appearanceMenu
        services: root.services
        layoutManaged: root.layoutManaged
        presentation: root.presentation
        contextKind: root.contextKind
        onDetailsRequested: function(section) { root.detailsRequested(section); }
        onPresentationRequested: function(value) { root.presentationRequested(value); }
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

            AudioLevelSlider {
                id: outputLevel
                owner: root
                menu: appearanceMenu
                kind: "output"
                visible: root.handles("output") && root.compact && !root.detailsExpanded && root.ranged
                width: content.width
            }

            AudioLevelSlider {
                id: inputLevel
                owner: root
                menu: appearanceMenu
                kind: "input"
                visible: root.handles("input") && root.compact && !root.detailsExpanded && root.ranged
                width: content.width
            }

            Repeater {
                visible: !root.compact || root.detailsExpanded
                model: (root.deviceSection === "audio-output" ? ["output"]
                    : root.deviceSection === "audio-input" ? ["input"] : ["output", "input"]).filter(function(kind) {
                        return root.handles(kind);
                    })
                delegate: AudioDeviceSection {
                    required property string modelData
                    owner: root
                    kind: modelData
                    visible: !root.compact || root.detailsExpanded
                    width: content.width
                }
            }
            PentadText { text: root.error; color: Theme.tokens.error; visible: text !== "" && !root.layoutManaged; role: "caption" }
        }
    }
}
