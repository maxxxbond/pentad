import QtQuick
import qs.theme
import qs.components
import "../../logic/telemetry.mjs" as Telemetry

Item {
    id: root
    objectName: 'telemetry-widget'
    required property var services
    readonly property var availability: services.desktop.state
    readonly property var value: availability.kind === "ready" ? availability.value.telemetry : null
    readonly property bool detailsOpen: details.opened
    readonly property alias detailsPopup: details.window
    readonly property alias capsuleItem: capsule
    readonly property var detailsInputRegion: details.window.mask
    readonly property alias detailsPopover: details
    readonly property alias metricRepeater: metrics
    implicitWidth: capsule.width
    implicitHeight: 28
    FontMetrics {
        id: labelMetrics
        font.family: Theme.tokens.fontFamily
        font.pixelSize: Metrics.panelFont
        font.features: ({ tnum: 1 })
    }

    function metricRatio(name) {
        if (!value) return null;
        if (name === 'CPU') return value.cpuPercent;
        if (name === 'GPU') return value.gpuPercent;
        if (name === 'Memory') return value.memory && value.memory.total > 0
            ? value.memory.used / value.memory.total : null;
        return null;
    }
    function metricText(name) {
        if (name === 'Network') return value && Number.isFinite(value.rxBytesPerSecond)
            && Number.isFinite(value.txBytesPerSecond)
            ? Telemetry.compactByteRate(value.rxBytesPerSecond + value.txBytesPerSecond) : '—';
        const ratio = metricRatio(name);
        return Number.isFinite(ratio) ? String(Math.round(ratio * 100)) : '—';
    }
    function openDetails() {
        if (root.visible && root.enabled) details.open();
    }
    function toggleDetails() {
        if (details.opened) details.close();
        else openDetails();
    }
    onVisibleChanged: if (!visible) details.close()
    // A bar wing without room stays laid out but disabled, so leaving the bar arrives here.
    onEnabledChanged: if (!enabled) details.close()

    Rectangle {
        id: capsule
        anchors.centerIn: parent
        height: 28
        width: row.childrenRect.width + 20
        radius: Metrics.radiusPill
        color: root.detailsOpen ? details.fill : Theme.tokens.surfaceRaised
        Row {
            id: row
            width: childrenRect.width
            height: childrenRect.height
            anchors.left: parent.left
            anchors.leftMargin: 4
            anchors.verticalCenter: parent.verticalCenter
            spacing: 8
            Repeater {
                id: metrics
                model: [
                    { name: "CPU", glyph: "planner_review", fallback: Qt.resolvedUrl("../../assets/icons/tabler/cpu-symbolic.svg") },
                    { name: "GPU", glyph: "developer_board", fallback: Qt.resolvedUrl("../../assets/icons/fluent/fluent-developer-board-symbolic.svg") },
                    { name: "Network", glyph: "swap_vert", fallback: Qt.resolvedUrl("../../assets/icons/tabler/arrows-up-down-symbolic.svg") },
                    { name: "Memory", glyph: "memory", fallback: Qt.resolvedUrl("../../assets/icons/fluent/fluent-memory-symbolic.svg") }
                ]
                delegate: Row {
                    required property var modelData
                    readonly property var metricRatio: root.metricRatio(modelData.name)
                    readonly property string labelText: root.metricText(modelData.name)
                    spacing: 4
                    height: 20
                    TelemetryDisc {
                        glyph: modelData.glyph
                        fallbackSource: modelData.fallback
                        ratio: Number.isFinite(parent.metricRatio) ? parent.metricRatio : 0
                        ink: Qt.alpha(Theme.tokens.text, 0.8)
                    }
                    Text {
                        height: parent.height
                        verticalAlignment: Text.AlignVCenter
                        text: parent.labelText
                        width: Math.max(implicitWidth, Math.ceil(Math.max(labelMetrics.averageCharacterWidth,
                            labelMetrics.advanceWidth('0'))) * (modelData.name === 'Network' ? 5 : 2))
                        font.family: Theme.config.fontFamily || "Geist"
                        font.pixelSize: Metrics.panelFont
                        font.weight: Font.Normal
                        font.features: ({ tnum: 1 })
                        renderType: Text.NativeRendering
                        color: Qt.alpha(Theme.tokens.text, 0.8)
                        Accessible.name: modelData.name + ": " + parent.labelText
                    }
                }
            }
        }
        TapHandler {
            acceptedButtons: Qt.LeftButton
            onTapped: root.toggleDetails()
        }
    }

    AttachedPopover {
        id: details
        anchorItem: capsule
        pointerDismissEnabled: false
        manager: root.services.popups || null
        contentItem: TelemetryDetails {
            services: root.services
            value: root.value
        }
    }
    Accessible.name: "System telemetry"
}
