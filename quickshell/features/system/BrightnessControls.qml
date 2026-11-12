pragma ComponentBehavior: Bound
import QtQuick
import qs.components
import qs.theme
import "../../logic/brightness.mjs" as BrightnessLogic

Item {
    id: root
    required property var brightness
    property var services: null
    property bool compact: false
    property string presentation: "range-horizontal"
    readonly property bool vertical: compact && presentation === "range-vertical"
    // In the control-center grid the cell owns size: the slider fills `levelHeight`
    // and the status line moves into the capsule label.
    property bool layoutManaged: false
    property real levelHeight: 160
    property var adapterState: brightness
        ? brightness.state : ({ kind: "unavailable", reason: "adapter-missing" })
    property string pendingRequestId: ""
    property int intentRevision: 0
    property int pendingRevision: 0
    property var desired: null
    property real lastConfirmed: NaN
    property string error: ""
    readonly property real confirmedValue: adapterState.kind === "ready" ? adapterState.value : lastConfirmed
    readonly property bool pending: desired !== null && Number.isFinite(confirmedValue)
        && Math.abs(desired - confirmedValue) > 0.001
    readonly property bool canAdjust: brightness && brightness.active && !brightness.safeMode
        && adapterState.kind === "ready"
    width: parent ? parent.width : 320
    implicitHeight: card.implicitHeight
    // The horizontal control-center row is a scrubber, like the volume rows; the upright capsule and the
    // settings card stay a PentadSlider.
    readonly property bool scrubberRow: compact && !vertical
    readonly property var brightnessSlider: scrubberRow ? scrubber : slider
    readonly property string levelLabel: layoutManaged && detailText() !== "" ? detailText() : text("Яскравість", "Brightness")
    readonly property real levelValue: adapterState.kind === "ready" ? (pending ? desired : adapterState.value) : 0.01
    readonly property url iconPath: Qt.resolvedUrl("../../assets/icons/material/controls/light-mode-symbolic.svg")

    function text(uk, en) { return services ? services.text(uk, en) : en; }

    function syncState() {
        if (adapterState.kind === "ready") lastConfirmed = adapterState.value;
        else if (!pendingRequestId) lastConfirmed = NaN;
        if (!pendingRequestId && !pending) desired = null;
    }
    function requestBrightness(value) {
        if (!canAdjust) return;
        intentRevision++;
        desired = Math.max(0.01, Math.min(1, value));
        error = "";
        sendBrightnessIntent();
    }
    function sendBrightnessIntent() {
        if (pendingRequestId || desired === null || !canAdjust) return;
        const actual = adapterState.kind === "ready" ? adapterState.value : confirmedValue;
        if (!Number.isFinite(actual)) return;
        const intent = BrightnessLogic.brightnessIntent(actual, desired);
        if (!intent) { desired = null; return; }
        desired = intent.target;
        if (!intent.steps || Math.abs(intent.target - actual) < 0.001) { desired = null; return; }
        pendingRequestId = brightness.adjust(intent.steps);
        pendingRevision = intentRevision;
    }
    function handleCommand(requestId, result) {
        if (requestId !== pendingRequestId) return;
        const wasCurrentIntent = pendingRevision === intentRevision;
        pendingRequestId = "";
        if (result.ok) {
            lastConfirmed = Number.isFinite(result.value) ? result.value
                : adapterState.kind === "ready" ? adapterState.value : lastConfirmed;
            error = "";
            if (desired !== null && Number.isFinite(lastConfirmed) && Math.abs(desired - lastConfirmed) >= 0.025)
                sendBrightnessIntent();
            else desired = null;
        } else {
            if (wasCurrentIntent) {
                desired = null;
                error = `Could not change brightness (${result.reason || "failed"})`;
            } else {
                error = "";
                Qt.callLater(sendBrightnessIntent);
            }
        }
    }
    function statusText() {
        if (error) return "—";
        if (adapterState.kind !== "ready") return "—";
        return `${Math.round((pending && desired !== null ? desired : confirmedValue) * 100)}%`;
    }
    function detailText() {
        if (error) return error;
        if (!brightness) return "Brightness unavailable";
        if (!brightness.active) return "Preview · read only";
        if (brightness.safeMode) return "Read only in safe mode";
        if (adapterState.kind !== "ready") {
            if (brightness.operation && brightness.operation.steps === null) return "Reading brightness…";
            return adapterState.reason && adapterState.reason !== "output-unavailable"
                ? `Brightness unavailable (${adapterState.reason})` : "Brightness unavailable";
        }
        return "";
    }

    onBrightnessChanged: {
        pendingRequestId = "";
        desired = null;
        lastConfirmed = NaN;
        error = "";
        Qt.callLater(syncState);
    }
    onAdapterStateChanged: syncState()

    Connections {
        target: root.brightness
        function onCommandFinished(requestId, result) { root.handleCommand(requestId, result); }
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
            spacing: 4

            Row {
                width: content.width
                spacing: root.compact ? 0 : 8
                Item {
                    visible: !root.compact
                    width: visible ? 28 : 0
                    height: 40
                    PentadIcon {
                        anchors.centerIn: parent
                        source: Qt.resolvedUrl("../../assets/icons/material/controls/light-mode-symbolic.svg")
                        pixelSize: 20
                        accessibleName: root.text("Яскравість", "Brightness")
                    }
                }
                Item {
                    id: sliderArea
                    width: Math.max(root.vertical ? 0 : 80, content.width - (root.compact ? 0 : 36))
                    height: root.vertical ? root.levelHeight : root.compact ? 48 : 40
                    PentadSlider {
                        id: slider
                        visible: !root.scrubberRow
                        anchors.fill: parent
                        from: 0.01
                        to: 1
                        stepSize: 0.01
                        wheelStepSize: 0.05
                        orientation: root.vertical ? Qt.Vertical : Qt.Horizontal
                        thick: true
                        referenceStyle: root.compact
                        iconSource: root.iconPath
                        label: root.levelLabel
                        valueText: root.statusText()
                        valueKnown: root.adapterState.kind === "ready"
                        confirmedValue: root.confirmedValue
                        accessibleName: root.text("Яскравість екрана", "Screen brightness")
                        enabled: root.canAdjust
                        onMoved: root.requestBrightness(value)
                        Binding {
                            target: slider
                            property: "value"
                            value: root.levelValue
                        }
                    }
                    // A press only grabs the bar and a click sets the value under it, as in the volume rows.
                    PentadScrubber {
                        id: scrubber
                        visible: root.scrubberRow
                        anchors.fill: parent
                        relativeDrag: true
                        from: 0.01
                        to: 1
                        stepSize: 0.01
                        wheelStepSize: 0.05
                        iconSource: root.iconPath
                        label: root.levelLabel
                        valueText: root.statusText()
                        valueKnown: root.adapterState.kind === "ready"
                        confirmedValue: root.confirmedValue
                        accessibleName: root.text("Яскравість екрана", "Screen brightness")
                        enabled: root.canAdjust
                        onMoved: function(next) { root.requestBrightness(next) }
                        Binding {
                            target: scrubber
                            property: "value"
                            value: root.levelValue
                        }
                    }
                }
            }
            PentadText {
                visible: root.detailText() !== "" && !root.layoutManaged
                text: root.detailText()
                color: root.error ? Theme.tokens.error : Theme.tokens.textMuted
                role: "caption"
            }
        }
    }
}
