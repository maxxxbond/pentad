pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls.Basic
import qs.theme
import "../logic/wheel-picker.mjs" as Wheel

// One column of the wheel picker: a drum of text rows you turn by dragging, flicking, the mouse
// wheel, a tap on a row, or the keyboard (arrows, PageUp/PageDown, Home/End). The drum is drawn
// twice: every row muted, and the same rows in full colour clipped to the selection band, so the
// chosen row lights up as it crosses the band. All maths is in logic/wheel-picker.mjs.
//
// The owner sets `selectedIndex` (a change from outside turns the drum, the short way round a
// loop) and listens to moved(index) for changes the user makes. The column never assigns
// `selectedIndex`, so the owner's binding survives.
Control {
    id: root
    property var options: []
    property bool loop: false
    property int selectedIndex: 0
    property string accessibleName: ""
    // Draw the band and its ticks; a picker with several columns draws one band behind them all.
    property bool showBand: true
    signal moved(int index)

    readonly property int count: options ? options.length : 0
    readonly property real position: spring.value
    readonly property int base: Math.round(position)
    // The row nearest the band, as an index into `options`.
    readonly property int nearest: count === 0 ? 0 : loop ? Wheel.wrapIndex(base, count) : Math.max(0, Math.min(count - 1, base))
    readonly property real half: Wheel.drumHeight / 2
    readonly property real bandInset: Metrics.space2
    readonly property color mutedInk: Qt.alpha(Theme.tokens.text, 0.4)
    readonly property bool moving: !spring.settled || dragging || wheelIdle.running
    property bool dragging: false
    // True from the first user input until the owner sets a value again; only then is moved() sent.
    property bool userDriven: false
    property bool keyboardEngaged: false
    readonly property bool ringVisible: activeFocus && (visualFocus || keyboardEngaged)
    property var tune: Wheel.settleSpring
    // False until the first frame: the value the owner starts with is shown, not travelled to.
    property bool ready: false

    function labelAt(index) {
        if (count === 0) return "";
        if (loop) return String(options[Wheel.wrapIndex(index, count)]);
        return index >= 0 && index < count ? String(options[index]) : "";
    }
    function targetIndex() {
        return count === 0 ? 0 : loop ? Wheel.wrapIndex(spring.target, count) : Math.max(0, Math.min(count - 1, Math.round(spring.target)));
    }
    // Moves the drum to an option from outside: no moved() signal, animated unless `animated` is false.
    function goTo(index, animated) {
        userDriven = false;
        tune = Wheel.settleSpring;
        const row = Math.max(0, Math.min(Math.max(0, count - 1), index));
        // Animated: the copy of the row nearest the drum, so a loop turns the short way round.
        spring.target = animated ? Wheel.nearestCycle(row, spring.target, count, loop) : row;
        if (!animated) spring.snap();
    }
    // The drum follows the pointer or the wheel exactly: no spring lag while it is held.
    function hold(pos) {
        spring.target = pos;
        spring.jump(pos);
    }
    function settle(velocity) {
        const flick = Math.abs(velocity) >= Wheel.flickThreshold;
        tune = flick ? Wheel.flickSpring : Wheel.settleSpring;
        spring.target = Wheel.releaseTarget(spring.value, velocity, count, loop);
        if (flick) spring.launch(velocity);
    }
    function step(key) {
        const target = Wheel.keyTarget(key, spring.value, count, loop);
        if (target === null || count === 0) return false;
        userDriven = true;
        tune = Wheel.settleSpring;
        spring.target = target;
        spring.snap();
        return true;
    }

    implicitWidth: 64
    implicitHeight: Wheel.drumHeight
    focusPolicy: Qt.StrongFocus
    clip: false
    Accessible.role: Accessible.SpinBox
    Accessible.name: accessibleName + (count > 0 ? ": " + labelAt(nearest) : "")
    Accessible.onIncreaseAction: root.step("down")
    Accessible.onDecreaseAction: root.step("up")

    // The owner echoing back the row the user just reached must not turn the drum again.
    onSelectedIndexChanged: {
        if (userDriven && selectedIndex === nearest) return;
        if (selectedIndex !== targetIndex()) goTo(selectedIndex, ready);
    }
    onCountChanged: goTo(selectedIndex, false)
    onNearestChanged: if (userDriven) moved(nearest)
    onActiveFocusChanged: if (!activeFocus) keyboardEngaged = false
    Component.onCompleted: {
        goTo(selectedIndex, false);
        Qt.callLater(() => ready = true);
    }

    Keys.onPressed: event => {
        const keys = {};
        keys[Qt.Key_Up] = "up";
        keys[Qt.Key_Down] = "down";
        keys[Qt.Key_PageUp] = "pageUp";
        keys[Qt.Key_PageDown] = "pageDown";
        keys[Qt.Key_Home] = "home";
        keys[Qt.Key_End] = "end";
        const key = keys[event.key];
        if (key === undefined) return;
        keyboardEngaged = true;
        event.accepted = root.step(key);
    }

    PentadSpring {
        id: spring
        stiffness: root.tune[0]
        damping: root.tune[1]
    }
    // Steps the drum only while it moves, and only while it can be seen. The spring counts as
    // settled a hair before the target; one more step parks the drum exactly on its row.
    FrameAnimation {
        running: root.visible && (root.moving || spring.value !== spring.target)
        onTriggered: spring.advance(frameTime)
    }
    // A wheel turn that stops for a moment settles on the nearest row.
    Timer {
        id: wheelIdle
        interval: Wheel.wheelIdle
        onTriggered: root.settle(0)
    }

    Rectangle {
        visible: root.showBand
        x: root.bandInset
        y: root.half - Wheel.itemHeight / 2
        width: root.width - root.bandInset * 2
        height: Wheel.itemHeight
        radius: Metrics.radiusMedium
        color: Qt.alpha(Theme.tokens.text, 0.08)
        Rectangle { x: 0; y: parent.height / 2; width: 4; height: 1; color: Qt.alpha(Theme.tokens.text, 0.3) }
        Rectangle { x: parent.width - 4; y: parent.height / 2; width: 4; height: 1; color: Qt.alpha(Theme.tokens.text, 0.3) }
    }

    // The drum, every row muted.
    Item {
        id: muted
        property color ink: root.mutedInk
        property bool heavy: false
        anchors.fill: parent
        Repeater {
            model: Wheel.windowRows * 2 + 1
            delegate: rowDelegate
        }
    }
    // The same drum in full colour, seen only through the band.
    Item {
        x: 0
        y: root.half - Wheel.itemHeight / 2
        width: root.width
        height: Wheel.itemHeight
        clip: true
        Item {
            id: lit
            property color ink: Theme.tokens.text
            property bool heavy: true
            y: -(root.half - Wheel.itemHeight / 2)
            width: root.width
            height: Wheel.drumHeight
            Repeater {
                model: Wheel.windowRows * 2 + 1
                delegate: rowDelegate
            }
        }
    }

    // The keyboard focus ring, only for keyboard focus.
    Rectangle {
        visible: root.ringVisible
        x: root.bandInset
        y: root.half - Wheel.itemHeight / 2
        width: root.width - root.bandInset * 2
        height: Wheel.itemHeight
        radius: Metrics.radiusMedium
        color: "transparent"
        border.width: 1
        border.color: Theme.tokens.accent
    }

    Component {
        id: rowDelegate
        Text {
            id: row
            required property int index
            readonly property int rowIndex: root.base + index - Wheel.windowRows
            readonly property real offset: rowIndex - root.position
            readonly property var geometry: Wheel.rowGeometry(offset)
            readonly property real centre: root.half + geometry.y
            readonly property bool real: root.loop || (rowIndex >= 0 && rowIndex < root.count)
            visible: geometry.visible && real
            text: root.labelAt(rowIndex)
            x: 0
            y: centre - height / 2
            width: root.width
            height: Wheel.itemHeight
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            color: parent.ink
            opacity: Wheel.edgeFade(centre / Wheel.drumHeight)
            font.family: Theme.tokens.fontFamily
            font.pixelSize: Metrics.textTitle
            font.weight: parent.heavy ? Font.Medium : Font.Normal
            transform: Scale {
                origin.x: row.width / 2
                origin.y: row.height / 2
                xScale: row.geometry.scaleX
                yScale: row.geometry.scaleY
            }
        }
    }

    MouseArea {
        id: pointer
        property real pressY: 0
        property real startPosition: 0
        property var samples: []
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton

        function note(y) {
            const now = Date.now() / 1000;
            samples = samples.filter(sample => now - sample.t <= Wheel.velocityWindow * 2).concat([{ t: now, y: y }]);
        }
        function finish(withVelocity) {
            const velocity = withVelocity ? Wheel.releaseVelocity(samples, Date.now() / 1000) : 0;
            root.dragging = false;
            root.settle(velocity);
        }

        onPressed: mouse => {
            root.keyboardEngaged = false;
            root.forceActiveFocus(Qt.MouseFocusReason);
            wheelIdle.stop();
            pressY = mouse.y;
            startPosition = spring.value;
            samples = [];
            note(mouse.y);
        }
        onPositionChanged: mouse => {
            if (!pressed) return;
            const travel = mouse.y - pressY;
            if (!root.dragging) {
                if (Math.abs(travel) < Wheel.tapSlop) return;
                root.dragging = true;
                root.userDriven = true;
            }
            root.hold(Wheel.dragPosition(startPosition, travel, root.count, root.loop));
            note(mouse.y);
        }
        onReleased: mouse => {
            if (root.dragging) {
                finish(true);
                return;
            }
            const row = Wheel.rowAtOffset(mouse.y - root.half);
            if (row === null || row === 0 || root.count === 0) return;
            root.userDriven = true;
            root.tune = Wheel.settleSpring;
            spring.target = Math.round(Wheel.clampPosition(Math.round(spring.value) + row, root.count, root.loop));
        }
        onCanceled: if (root.dragging) finish(false)
        onWheel: wheel => {
            if (root.count === 0) return;
            root.userDriven = true;
            root.hold(Wheel.clampPosition(spring.value + Wheel.wheelStep(wheel.angleDelta.y), root.count, root.loop, Wheel.wheelEdge));
            wheelIdle.restart();
            wheel.accepted = true;
        }
    }
}
