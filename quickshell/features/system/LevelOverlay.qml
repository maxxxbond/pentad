pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.components
import qs.theme
import '../../logic/level-feedback.mjs' as Feedback

PanelWindow {
    id: root
    required property var services
    required property string outputId
    property var brightness: null
    property real topInset: 0
    property bool shown: false
    property string kind: 'output'
    property real value: 0
    property bool muted: false
    property bool known: true
    property bool failed: false
    property string message: ''
    property var previousAudio: null
    property string brightnessRequest: ''
    // The main ring shows where the wheel asked brightness to go; the thin inner ring shows the hardware.
    readonly property bool brightnessPending: !!brightnessRequest || (!!brightness && brightness.desiredValue != null)
    readonly property var audioState: services.audio.state
    readonly property string language: services.config.documents.interface.language
    readonly property bool ukrainian: language === 'uk' || (language === 'auto' && Qt.locale().name.indexOf('uk') === 0)
    readonly property bool focusedOutput: {
        const state = services.hyprland.state;
        if (state.kind !== 'ready') return true;
        return state.value.outputs.some(function(output) {
            return (output.id === root.outputId || output.name === root.outputId)
                && output.id === state.value.focusedOutputId;
        });
    }
    readonly property color ink: failed ? Theme.tokens.error : Theme.tokens.accent
    readonly property string title: failed ? tr('Помилка', 'Error')
        : kind === 'brightness' ? tr('Яскравість', 'Brightness')
        : kind === 'input' ? (muted ? tr('Мікрофон вимкнено', 'Microphone muted') : tr('Мікрофон', 'Microphone'))
        : muted ? tr('Звук вимкнено', 'Muted') : tr('Гучність', 'Volume')

    function tr(uk, en) { return ukrainian ? uk : en; }
    function present(nextKind, nextValue, nextMuted, nextMessage, duration, error) {
        kind = nextKind;
        known = Number.isFinite(nextValue);
        value = known ? Math.max(nextKind === 'brightness' ? 0.01 : 0, Math.min(1, nextValue)) : 0;
        muted = nextMuted;
        failed = error === true;
        message = nextMessage;
        shown = true;
        dismiss.interval = duration || 1500;
        dismiss.restart();
    }
    function updateAudio() {
        const next = Feedback.audioFeedback(previousAudio, audioState);
        previousAudio = audioState;
        if (!next || !focusedOutput) return;
        if (Date.now() < services.audio.contextualFeedbackUntil) return;
        const label = next.kind === 'input' ? tr('Мікрофон', 'Microphone') : tr('Вихід', 'Output');
        present(next.kind, next.value, next.muted,
            next.switched ? label + ' → ' + next.label : next.label,
            next.switched ? 2200 : 1500, false);
    }
    onAudioStateChanged: updateAudio()
    Component.onCompleted: previousAudio = audioState

    Connections {
        target: root.services.audio
        function onContextualFeedbackUntilChanged() {
            if (Date.now() < root.services.audio.contextualFeedbackUntil && root.kind !== 'brightness')
                root.shown = false;
        }
    }

    Connections {
        target: root.brightness
        ignoreUnknownSignals: true
        function onDesiredValueChanged() {
            const desired = root.brightness.desiredValue;
            if (desired != null) root.present('brightness', desired, false, root.tr('Яскравість', 'Brightness'), 1500, false);
        }
        function onOperationChanged() {
            const operation = root.brightness.operation;
            if (!operation || operation.steps === null) return;
            root.brightnessRequest = operation.requestId;
            if (operation.goal != null) return;
            const state = root.brightness.state;
            const desired = state.kind === 'ready' ? state.value + operation.steps * 0.05 : null;
            root.present('brightness', desired, false, root.tr('Яскравість', 'Brightness'), 1500, false);
        }
        function onCommandFinished(requestId, result) {
            if (requestId !== root.brightnessRequest) return;
            root.brightnessRequest = '';
            // A follow-up write is already on its way to the desired level; keep showing that.
            if (result.ok && root.brightness.desiredValue != null) return;
            root.present('brightness', result.ok ? result.value : null, false,
                result.ok ? root.tr('Яскравість', 'Brightness') : root.tr('Не вдалося змінити яскравість', 'Could not change brightness'),
                1500, !result.ok);
        }
    }
    Timer {
        id: dismiss
        interval: 1500
        onTriggered: {
            if (root.brightnessPending && root.kind === 'brightness') restart();
            else root.shown = false;
        }
    }

    anchors.top: true
    // The card keeps its place 8 px below topInset; the window adds shadow room on every side.
    margins.top: topInset + 8 - Metrics.overlayShadowRoom
    implicitWidth: 288 + 2 * Metrics.overlayShadowRoom
    implicitHeight: 72 + 2 * Metrics.overlayShadowRoom
    exclusiveZone: 0
    color: 'transparent'
    visible: shown || card.opacity > 0
    mask: Region {}
    WlrLayershell.namespace: 'pentad-level'
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    Rectangle {
        id: card
        objectName: 'level-card'
        x: Metrics.overlayShadowRoom; y: Metrics.overlayShadowRoom - (root.shown ? 0 : 8)
        width: parent.width - 2 * Metrics.overlayShadowRoom; height: 72
        radius: 22
        color: Theme.tokens.surfaceRaised
        opacity: root.shown ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Motion.short } }
        Behavior on y { NumberAnimation { duration: Motion.short; easing.type: Easing.OutCubic } }
        Rectangle {
            anchors.fill: parent
            z: -1
            radius: parent.radius
            color: parent.color
            layer.enabled: true
            layer.effect: OverlayShadowEffect {}
        }
        Item {
            id: ring
            objectName: 'level-ring'
            x: 16; width: 48; height: 48
            anchors.verticalCenter: parent.verticalCenter
            property real displayed: root.failed || root.muted || !root.known ? 0 : root.value
            // Smoothed rather than eased: each wheel step retargets mid-flight without restarting the curve.
            Behavior on displayed {
                enabled: !Motion.reducedMotion
                SmoothedAnimation { duration: Motion.reveal; velocity: -1 }
            }
            onDisplayedChanged: drawing.requestPaint()
            // The hardware level shares the same track. It trails the desired level a little slower, so
            // the gap between them reads as "still applying" and closes instead of popping in and out.
            readonly property real actualTarget: {
                const state = root.brightness ? root.brightness.state : null;
                return root.kind === 'brightness' && !root.failed && root.known && state && state.kind === 'ready'
                    ? state.value : displayed;
            }
            property real actual: actualTarget
            Behavior on actual {
                enabled: !Motion.reducedMotion && root.kind === 'brightness'
                SmoothedAnimation { duration: Motion.long; velocity: -1 }
            }
            onActualChanged: drawing.requestPaint()
            Canvas {
                id: drawing
                anchors.fill: parent
                onPaint: {
                    const ctx = getContext('2d');
                    ctx.clearRect(0, 0, width, height);
                    ctx.lineWidth = 3; ctx.lineCap = 'round';
                    ctx.strokeStyle = Qt.alpha(root.ink, 0.13);
                    ctx.beginPath(); ctx.arc(24, 24, 21, 0, Math.PI * 2); ctx.stroke();
                    // Solid: what the screen already shows. Faint: the stretch still being applied, ahead
                    // of the solid arc when brightening and behind it, still lit, when dimming.
                    const start = -Math.PI / 2;
                    const settled = Math.min(ring.displayed, ring.actual), reach = Math.max(ring.displayed, ring.actual);
                    if (reach - settled > 0.002) {
                        ctx.strokeStyle = Qt.alpha(root.ink, 0.4);
                        ctx.beginPath(); ctx.arc(24, 24, 21, start, start + reach * Math.PI * 2); ctx.stroke();
                    }
                    if (settled > 0) {
                        ctx.strokeStyle = root.ink;
                        ctx.beginPath(); ctx.arc(24, 24, 21, start, start + settled * Math.PI * 2); ctx.stroke();
                    }
                }
                Connections { target: root; function onInkChanged() { drawing.requestPaint(); } }
            }
            PentadIcon {
                anchors.centerIn: parent
                pixelSize: 22
                color: root.ink
                source: root.failed ? Quickshell.iconPath('dialog-warning-symbolic')
                    : root.kind === 'input' ? Quickshell.iconPath(root.muted ? 'microphone-disabled-symbolic' : 'microphone-sensitivity-high-symbolic')
                    : Qt.resolvedUrl('../../assets/icons/material/' + (root.kind === 'brightness' ? 'brightness' : root.muted ? 'volume-outline-off' : 'volume-outline') + '-symbolic.svg')
            }
        }
        Column {
            x: 76; width: parent.width - x - 16
            anchors.verticalCenter: parent.verticalCenter
            PentadText {
                solid: true
                wrapMode: Text.NoWrap
                width: parent.width
                text: root.failed || root.muted || !root.known ? root.title : Math.round(ring.displayed * 100) + '%'
                color: Theme.tokens.text
                font.family: Theme.tokens.fontFamily
                font.pixelSize: root.failed || root.muted || !root.known ? 14 : 24
                font.weight: Font.DemiBold
                font.features: ({ tnum: 1 })
                elide: Text.ElideRight
            }
            PentadText {
                solid: true
                wrapMode: Text.NoWrap
                width: parent.width
                text: root.message
                color: Theme.tokens.textMuted
                font.family: Theme.tokens.fontFamily
                font.pixelSize: 12
                elide: Text.ElideRight
            }
        }
    }
}
