pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Shapes
import qs.theme
import "../logic/spring.mjs" as SpringLogic

// The animated file drop: a borderless card whose fill lifts while something is dragged over it,
// a circle that gulps the drop, a ring that fills around a percentage while the drop is taken in,
// a success flood with a check that draws itself, and two text lines that roll to their new text.
// Every movement is a spring from SpringLogic.fileDropSprings, the same stiffness and damping as
// the motion study it was drawn from.
//
// The caller owns the DropArea and the work: it drives `active` from containsDrag, `phase`
// ("idle", "working", "done") and, while working, `progress` (0..1, or -1 when it cannot be
// measured). With `activatable` a click, Enter or Space emits activated(), e.g. to open a picker.
Control {
    id: root
    // A file is held somewhere over the shell or this surface: the zone wakes up before the pointer
    // reaches it. `active` is the pointer with the file right over the zone.
    property bool awake: false
    property bool active: false
    property string phase: "idle"
    property real progress: -1
    property string title: ""
    property string hint: ""
    // An icon in place of the drawn arrow at rest; empty keeps the arrow.
    property url iconSource: ""
    property bool activatable: false
    property color fill: Theme.tokens.surfaceRaised
    property color activeFill: Theme.tokens.surfaceOverlay
    signal activated()

    readonly property bool working: phase === "working"
    readonly property bool done: phase === "done"
    readonly property bool measured: working && progress >= 0
    readonly property real shownProgress: measured ? Math.max(0, Math.min(1, progress)) : 0
    // Half while a file is held elsewhere, all of it under the file. It only sets the arrow's bob: an
    // awake zone must not look highlighted, since dropping where the pointer is would not land here.
    readonly property real lift: clamp01(hoverSpring.value)
    // Only where the drop would land: the fill lifts, the zone swells, the circle grows, rises and
    // inverts, and the arrow bobs harder.
    readonly property real hot: clamp01(hotSpring.value)
    readonly property color shownFill: mix(fill, activeFill, hot)
    readonly property real gap: Metrics.space5 - Metrics.space1
    // Without a hint the title alone is centred.
    readonly property real textHeight: titleLine.height + (hint !== "" ? Metrics.space1 + hintLine.height : 0)
    // The circle shrinks with a short zone and steps aside below 40 px, leaving the two lines.
    readonly property real coreRoom: height - Metrics.space4 * 2 - gap - textHeight
    readonly property real coreSize: coreRoom >= 40 ? Math.min(72, coreRoom) : 0
    readonly property real blockTop: Math.round((height - textHeight - (coreSize > 0 ? coreSize + gap : 0)) / 2)
    property real clock: 0
    // How far the ring and the success flood are shown, 0..1, for hosts and tests.
    readonly property color ink: Theme.tokens.text
    readonly property color page: Theme.tokens.surface
    readonly property color disc: Qt.alpha(Theme.tokens.text, 0.08)
    // The circle and its glyph, inverting as the file comes over the zone.
    readonly property color circleColor: mix(disc, ink, hot)
    readonly property color glyphColor: mix(ink, page, hot)
    readonly property real liftLevel: hoverSpring.value
    readonly property real hotLevel: hotSpring.value
    readonly property real ringLevel: ringSpring.value
    readonly property real successLevel: floodSpring.value

    function clamp01(value) {
        return Math.max(0, Math.min(1, value));
    }
    function mix(a, b, t) {
        return Qt.rgba(a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t, a.b + (b.b - a.b) * t, a.a + (b.a - a.a) * t);
    }
    function preset(name) {
        return SpringLogic.fileDropSprings[name];
    }
    // Reads `phase` itself: onPhaseChanged can run before `working` and `done` re-evaluate.
    function applyPhase(animated) {
        const nowWorking = phase === "working";
        const nowDone = phase === "done";
        arrowSpring.target = phase === "idle" ? 1 : 0;
        percentSpring.target = nowWorking && progress >= 0 ? 1 : 0;
        ringSpring.target = nowWorking ? 1 : 0;
        floodSpring.target = nowDone ? 1 : 0;
        checkSpring.target = nowDone ? 1 : 0;
        if (!animated) {
            springs.forEach(spring => spring.snap());
            return;
        }
        if (nowWorking) {
            circleSpring.kick(1.2);
            zoneSpring.kick(0.965);
        } else if (nowDone) {
            circleSpring.kick(0.84);
        }
    }

    onPhaseChanged: applyPhase(true)
    onMeasuredChanged: percentSpring.target = measured ? 1 : 0
    Component.onCompleted: applyPhase(false)

    implicitWidth: 296
    implicitHeight: 216
    padding: 0
    focusPolicy: activatable ? Qt.StrongFocus : Qt.NoFocus
    scale: zoneSpring.value * (1 + Math.min(0.025, 6 / Math.max(1, width)) * hotSpring.value)
    Accessible.role: activatable ? Accessible.Button : Accessible.StaticText
    Accessible.name: title
    Accessible.description: hint
    Keys.onPressed: event => {
        if (!activatable || event.isAutoRepeat)
            return;
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
            zoneSpring.kick(0.975);
            root.activated();
            event.accepted = true;
        }
    }

    readonly property var springs: [zoneSpring, hoverSpring, hotSpring, circleSpring, arrowSpring, percentSpring, ringSpring, floodSpring, checkSpring, titleLine.roll, hintLine.roll]
    readonly property bool moving: springs.some(spring => !spring.settled)
    readonly property bool bobbing: lift > 0.001 && !Theme.tokens.reducedMotion
    readonly property bool spinning: working && !measured && !Theme.tokens.reducedMotion

    PentadSpring { id: zoneSpring; stiffness: root.preset("zone")[0]; damping: root.preset("zone")[1]; value: 1; target: 1 }
    PentadSpring {
        id: hoverSpring
        stiffness: root.preset("hover")[0]
        damping: root.preset("hover")[1]
        target: root.phase !== "idle" ? 0 : root.active ? 1 : root.awake ? 0.5 : 0
    }
    PentadSpring {
        id: hotSpring
        stiffness: root.preset("hover")[0]
        damping: root.preset("hover")[1]
        target: root.active && root.phase === "idle" ? 1 : 0
    }
    PentadSpring { id: circleSpring; stiffness: root.preset("circle")[0]; damping: root.preset("circle")[1]; value: 1; target: 1 }
    PentadSpring { id: arrowSpring; stiffness: root.preset("arrow")[0]; damping: root.preset("arrow")[1]; value: 1; target: 1 }
    PentadSpring { id: percentSpring; stiffness: root.preset("percent")[0]; damping: root.preset("percent")[1] }
    PentadSpring { id: ringSpring; stiffness: root.preset("ring")[0]; damping: root.preset("ring")[1] }
    PentadSpring { id: floodSpring; stiffness: root.preset("flood")[0]; damping: root.preset("flood")[1] }
    PentadSpring { id: checkSpring; stiffness: root.preset("check")[0]; damping: root.preset("check")[1] }

    // Runs only while something moves; a zone at rest does no work.
    FrameAnimation {
        running: root.visible && (root.moving || root.bobbing || root.spinning)
        onTriggered: {
            root.clock = (root.clock + frameTime) % 3600;
            root.springs.forEach(spring => spring.advance(frameTime));        }
    }

    TapHandler {
        enabled: root.activatable
        onPressedChanged: if (pressed) zoneSpring.kick(0.975)
        onTapped: root.activated()
    }
    HoverHandler {
        enabled: root.activatable
        cursorShape: Qt.PointingHandCursor
    }

    background: ContinuousSurface {
        extent: Metrics.radiusBlock
        fill: root.shownFill
        edge: root.visualFocus ? Theme.tokens.text : "transparent"
    }

    contentItem: Item {
        Item {
            id: core
            visible: root.coreSize > 0
            width: root.coreSize
            height: root.coreSize
            x: Math.round((root.width - width) / 2)
            y: root.blockTop - 9 * root.hot
            scale: circleSpring.value * (1 + 0.14 * root.hot)
            readonly property real unit: width / 72
            // Under the file the circle inverts: solid ink with the glyph in the page colour. Tokens are
            // strings, so they pass through typed colours before mix() reads their channels.
            readonly property color glyph: root.glyphColor

            Rectangle {
                anchors.fill: parent
                radius: width / 2
                color: root.circleColor
            }
            Rectangle {
                anchors.fill: parent
                radius: width / 2
                color: Theme.tokens.success
                scale: Math.max(0, floodSpring.value)
                visible: scale > 0.001
            }
            Shape {
                anchors.fill: parent
                opacity: root.clamp01(ringSpring.value)
                visible: opacity > 0.001
                preferredRendererType: Shape.CurveRenderer
                ShapePath {
                    fillColor: "transparent"
                    strokeColor: Qt.alpha(Theme.tokens.text, 0.14)
                    strokeWidth: 3 * core.unit
                    PathAngleArc {
                        centerX: core.width / 2
                        centerY: core.height / 2
                        radiusX: 33 * core.unit
                        radiusY: radiusX
                        startAngle: 0
                        sweepAngle: 360
                    }
                }
                ShapePath {
                    fillColor: "transparent"
                    strokeColor: Theme.tokens.accent
                    strokeWidth: 3 * core.unit
                    capStyle: ShapePath.RoundCap
                    PathAngleArc {
                        centerX: core.width / 2
                        centerY: core.height / 2
                        radiusX: 33 * core.unit
                        radiusY: radiusX
                        // Unmeasured work shows a quarter arc running round instead of a fill.
                        startAngle: root.measured ? -90 : -90 + (root.clock * 300) % 360
                        sweepAngle: root.measured ? 360 * root.shownProgress : root.working ? 90 : 0
                    }
                }
            }
            Item {
                id: arrow
                anchors.fill: parent
                opacity: root.clamp01(arrowSpring.value)
                visible: opacity > 0.001
                readonly property real bob: -(1.5 * root.lift + 3.5 * root.hot) * (0.5 + 0.5 * Math.sin(root.clock * 7))
                transform: Translate { y: (arrow.bob + (1 - arrowSpring.value) * -12) * core.unit }
                scale: 0.6 + 0.4 * arrowSpring.value

                PentadIcon {
                    anchors.centerIn: parent
                    visible: root.iconSource.toString() !== ""
                    source: root.iconSource
                    pixelSize: Math.round(26 * core.unit)
                    color: core.glyph
                }
                Shape {
                    visible: root.iconSource.toString() === ""
                    anchors.centerIn: parent
                    width: 24
                    height: 24
                    scale: 26 * core.unit / 24
                    preferredRendererType: Shape.CurveRenderer
                    ShapePath {
                        fillColor: "transparent"
                        strokeColor: core.glyph
                        strokeWidth: 2.25
                        capStyle: ShapePath.RoundCap
                        joinStyle: ShapePath.RoundJoin
                        PathPolyline { path: [Qt.point(12, 19), Qt.point(12, 5)] }
                        PathPolyline { path: [Qt.point(5.5, 11.5), Qt.point(12, 5), Qt.point(18.5, 11.5)] }
                    }
                }
            }
            PentadText {
                anchors.centerIn: parent
                opacity: root.clamp01(percentSpring.value)
                visible: opacity > 0.001
                scale: 0.7 + 0.3 * percentSpring.value
                text: String(Math.round(root.shownProgress * 100))
                role: "title"
                font.weight: Font.DemiBold
                font.features: { "tnum": 1 }
            }
            Shape {
                anchors.centerIn: parent
                width: 24
                height: 24
                scale: 30 * core.unit / 24
                opacity: root.clamp01(checkSpring.value * 4)
                visible: opacity > 0.001
                preferredRendererType: Shape.CurveRenderer
                ShapePath {
                    fillColor: "transparent"
                    strokeColor: Theme.tokens.surface
                    strokeWidth: 2.4
                    capStyle: ShapePath.RoundCap
                    joinStyle: ShapePath.RoundJoin
                    PathPolyline {
                        path: SpringLogic.partialPolyline(SpringLogic.checkPoints, root.clamp01(checkSpring.value)).map(point => Qt.point(point[0], point[1]))
                    }
                }
            }
        }

        RollingLine {
            id: titleLine
            x: Metrics.space4
            width: root.width - Metrics.space4 * 2
            height: 24
            y: root.blockTop + (core.visible ? root.coreSize + root.gap : 0)
            text: root.title
            role: "section"
            weight: Font.DemiBold
            color: Theme.tokens.text
        }
        RollingLine {
            id: hintLine
            visible: root.hint !== ""
            x: Metrics.space4
            width: root.width - Metrics.space4 * 2
            height: 20
            y: titleLine.y + titleLine.height + Metrics.space1
            text: root.hint
            // While working the hint counts up in place; every other change rolls.
            key: root.working ? "working" : root.phase + "\n" + root.hint
            color: Theme.tokens.textMuted
        }
    }

    // A line that rolls when its key changes: the old text leaves upward while the new one rises
    // in, waiting for the old one to clear. A text change under the same key updates in place.
    component RollingLine: Item {
        id: line
        property string text: ""
        property string key: text
        property string role: "body"
        property int weight: Font.Normal
        property color color: Theme.tokens.text
        property string current: ""
        property string previous: ""
        property string shownKey: ""
        property bool ready: false
        readonly property alias roll: rollSpring
        readonly property real shift: 16

        function sync() {
            if (!ready)
                return;
            if (key === shownKey) {
                current = text;
                return;
            }
            previous = current;
            current = text;
            shownKey = key;
            rollSpring.jump(0);
        }
        onTextChanged: Qt.callLater(line.sync)
        onKeyChanged: Qt.callLater(line.sync)
        Component.onCompleted: {
            current = text;
            shownKey = key;
            ready = true;
        }
        clip: true

        PentadSpring {
            id: rollSpring
            stiffness: SpringLogic.fileDropSprings.line[0]
            damping: SpringLogic.fileDropSprings.line[1]
            value: 1
            target: 1
        }
        PentadText {
            width: line.width
            y: Math.round((line.height - height) / 2) + (1 - rollSpring.value) * line.shift
            opacity: Math.max(0, Math.min(1, (Math.max(0, Math.min(1, rollSpring.value)) - 0.35) / 0.65))
            text: line.current
            textFormat: Text.PlainText
            role: line.role
            font.weight: line.weight
            color: line.color
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.NoWrap
            elide: Text.ElideMiddle
        }
        PentadText {
            visible: line.previous !== "" && rollSpring.value < 0.985
            width: line.width
            y: Math.round((line.height - height) / 2) - rollSpring.value * line.shift
            opacity: Math.max(0, Math.min(1, 1 - Math.max(0, Math.min(1, rollSpring.value)) * 1.8))
            text: line.previous
            textFormat: Text.PlainText
            role: line.role
            font.weight: line.weight
            color: line.color
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.NoWrap
            elide: Text.ElideMiddle
        }
    }
}
