pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Shapes
import qs.theme
import "../logic/spring.mjs" as SpringLogic

// A status picker whose menu drops out from under the trigger on a spring: its height overshoots
// once, rows fall in one after another, the hover highlight stretches between rows (a stiff
// leading edge, a soft trailing one), a pick draws its check, rolls the new value up into the
// trigger and folds the menu away. With `keepCentred` the pair lifts by half the menu so it stays
// centred where it sits. Every movement is a spring from SpringLogic.dropdownSprings, the same
// stiffness and damping as the motion study it was drawn from.
//
// `model` is an array of { text, color } (color optional: the dot's colour, a theme token).
// Keys: Enter, Space or the arrows open; the arrows move; Enter or Space picks; Escape closes.
Control {
    id: root
    property var model: []
    property int currentIndex: 0
    property string accessibleName: ""
    property bool keepCentred: false
    property color fill: Theme.tokens.surfaceRaised
    property color menuFill: Theme.tokens.surfaceOverlay
    signal activated(int index)

    // State, not inputs: read them, change them only through open(), close(), toggle(), pick().
    property bool expanded: false
    property int hoveredIndex: -1

    readonly property int count: model ? model.length : 0
    readonly property real rowHeight: Metrics.controlLarge - Metrics.space2
    readonly property real menuPadding: Metrics.space1
    readonly property real gap: Metrics.space2
    readonly property real menuHeight: menuPadding * 2 + rowHeight * count
    readonly property real rollDistance: Math.round(height * 0.4)
    readonly property real dotSize: 10
    // For hosts and tests.
    readonly property real menuLevel: menuHeight > 0 ? menuSpring.value / menuHeight : 0
    readonly property real liftOffset: liftSpring.value
    readonly property real rollLevel: rollSpring.value
    readonly property var highlight: SpringLogic.highlightSpan(highlightTop.value, highlightBottom.value, menuPadding, menuHeight)
    readonly property bool menuShown: menu.visible
    property bool animating: false

    // Which entry each of the two value slots shows; `front` is the one rolled in.
    property var slotIndex: [-1, -1]
    property int front: 0
    property int shownIndex: -1
    property var queue: []
    property int returnFocusReason: Qt.OtherFocusReason

    function clamp01(value) {
        return Math.max(0, Math.min(1, value));
    }
    function entryText(index) {
        const entry = index >= 0 && index < count ? model[index] : null;
        return entry ? String(entry.text !== undefined ? entry.text : entry) : "";
    }
    function entryColor(index) {
        const entry = index >= 0 && index < count ? model[index] : null;
        return entry && entry.color ? entry.color : Theme.tokens.textMuted;
    }
    function preset(name) {
        return SpringLogic.dropdownSprings[name];
    }
    function wake() {
        animating = true;
    }
    // Runs fn after `seconds` of frame time, so it keeps step with the springs.
    function after(seconds, fn) {
        if (Theme.tokens.reducedMotion || seconds <= 0) {
            fn();
            return;
        }
        queue.push({
            left: seconds,
            fn: fn
        });
        wake();
    }
    function allSprings() {
        const list = [menuSpring, liftSpring, chevronSpring, fadeSpring, pressSpring, rollSpring, highlightTop, highlightBottom, highlightFade];
        for (let i = 0; i < rows.count; i++) {
            const row = rows.itemAt(i);
            if (row)
                list.push(row.fall, row.check);
        }
        return list;
    }
    function rowAt(index) {
        return rows.itemAt(index);
    }

    function hover(index, snap) {
        if (index === hoveredIndex || index < 0 || index >= count)
            return;
        const top = menuPadding + index * rowHeight;
        if (snap || hoveredIndex < 0) {
            highlightTop.target = top;
            highlightBottom.target = top + rowHeight;
            highlightTop.jump(top);
            highlightBottom.jump(top + rowHeight);
        } else {
            const down = index > hoveredIndex;
            const lead = down ? highlightBottom : highlightTop;
            const trail = down ? highlightTop : highlightBottom;
            lead.stiffness = preset("highlightLead")[0];
            lead.damping = preset("highlightLead")[1];
            trail.stiffness = preset("highlightTrail")[0];
            trail.damping = preset("highlightTrail")[1];
            highlightTop.target = top;
            highlightBottom.target = top + rowHeight;
        }
        hoveredIndex = index;
        highlightFade.target = 1;
        wake();
    }
    function setOpen(value) {
        if (expanded === value || (value && count === 0))
            return;
        expanded = value;
        menuSpring.target = value ? menuHeight : 0;
        liftSpring.target = value && keepCentred ? -(gap + menuHeight) / 2 : 0;
        chevronSpring.target = value ? 1 : 0;
        fadeSpring.target = value ? 1 : 0;
        if (value) {
            menu.origin = root.mapToItem(menu.parent, 0, root.height);
            menu.open();
        }
        for (let i = 0; i < count; i++) {
            const index = i;
            after(SpringLogic.dropdownRowDelay(index, count, value), () => {
                const row = root.rowAt(index);
                if (row)
                    row.fall.target = root.expanded ? 1 : 0;
            });
        }
        if (value) {
            hover(currentIndex, true);
        } else {
            hoveredIndex = -1;
            highlightFade.target = 0;
        }
        wake();
    }
    function open() {
        setOpen(true);
    }
    function close() {
        setOpen(false);
    }
    function toggle() {
        setOpen(!expanded);
    }
    function pick(index) {
        if (index < 0 || index >= count)
            return;
        currentIndex = index;
        pressSpring.kick(SpringLogic.dropdownTiming.pressPick);
        wake();
        root.activated(index);
        after(SpringLogic.dropdownTiming.closeAfterPick, () => root.setOpen(false));
    }
    // Rolls the trigger to the current entry and moves the check, for a pick or a host's change.
    function showCurrent(animated) {
        if (currentIndex === shownIndex && animated)
            return;
        shownIndex = currentIndex;
        if (animated) {
            front = front ^ 1;
            const slots = slotIndex.slice();
            slots[front] = currentIndex;
            slotIndex = slots;
            rollSpring.target = 1;
            rollSpring.jump(0);
        } else {
            const slots = [-1, -1];
            slots[front] = currentIndex;
            slotIndex = slots;
            rollSpring.snap();
        }
        for (let i = 0; i < rows.count; i++) {
            const row = rows.itemAt(i);
            if (!row)
                continue;
            row.check.target = i === currentIndex ? 1 : 0;
            if (!animated)
                row.check.snap();
        }
        wake();
    }
    function handleKey(event) {
        const key = event.key;
        if (key === Qt.Key_Down || key === Qt.Key_Up) {
            returnFocusReason = Qt.TabFocusReason;
            if (!expanded)
                setOpen(true);
            else
                hover(hoveredIndex + (key === Qt.Key_Down ? 1 : -1));
            event.accepted = true;
        } else if (key === Qt.Key_Return || key === Qt.Key_Enter || key === Qt.Key_Space) {
            if (event.isAutoRepeat) {
                event.accepted = true;
                return;
            }
            returnFocusReason = Qt.TabFocusReason;
            if (expanded && hoveredIndex > -1) {
                pick(hoveredIndex);
            } else if (!expanded) {
                pressSpring.kick(SpringLogic.dropdownTiming.pressOpen);
                setOpen(true);
            }
            event.accepted = true;
        } else if (key === Qt.Key_Escape && expanded) {
            returnFocusReason = Qt.TabFocusReason;
            setOpen(false);
            event.accepted = true;
        }
    }

    onCurrentIndexChanged: showCurrent(true)
    onMenuHeightChanged: if (expanded) {
        menuSpring.target = menuHeight;
        liftSpring.target = keepCentred ? -(gap + menuHeight) / 2 : 0;
        Qt.callLater(showNewRows);
        wake();
    }
    // Rows added while the menu is open fall in like the rest.
    function showNewRows() {
        for (let i = 0; expanded && i < rows.count; i++) {
            const row = rows.itemAt(i);
            if (row)
                row.fall.target = 1;
        }
        wake();
    }
    // A dropdown hidden while its menu is open or folding closes at once: its frame loop stops
    // with it, and the window-wide catcher must not stay behind.
    onVisibleChanged: if (!visible && (expanded || menu.visible)) {
        expanded = false;
        hoveredIndex = -1;
        queue = [];
        allSprings().forEach(spring => {
            spring.target = spring === pressSpring || spring === rollSpring ? 1 : 0;
            spring.snap();
        });
        showCurrent(false);
        menu.close();
    }
    Component.onCompleted: showCurrent(false)

    implicitWidth: 232
    implicitHeight: Metrics.controlLarge
    padding: 0
    focusPolicy: Qt.StrongFocus
    Accessible.role: Accessible.ComboBox
    Accessible.name: accessibleName !== "" ? accessibleName : entryText(currentIndex)
    Accessible.description: accessibleName !== "" ? entryText(currentIndex) : ""
    Keys.onPressed: event => root.handleKey(event)

    PentadSpring {
        id: menuSpring
        stiffness: root.preset("menu")[0]
        damping: root.preset("menu")[1]
    }
    PentadSpring {
        id: liftSpring
        stiffness: root.preset("lift")[0]
        damping: root.preset("lift")[1]
    }
    PentadSpring {
        id: chevronSpring
        stiffness: root.preset("chevron")[0]
        damping: root.preset("chevron")[1]
    }
    PentadSpring {
        id: fadeSpring
        stiffness: root.preset("fade")[0]
        damping: root.preset("fade")[1]
    }
    PentadSpring {
        id: pressSpring
        stiffness: root.preset("press")[0]
        damping: root.preset("press")[1]
        value: 1
        target: 1
    }
    PentadSpring {
        id: rollSpring
        stiffness: root.preset("roll")[0]
        damping: root.preset("roll")[1]
        value: 1
        target: 1
    }
    PentadSpring {
        id: highlightTop
        stiffness: root.preset("highlightLead")[0]
        damping: root.preset("highlightLead")[1]
    }
    PentadSpring {
        id: highlightBottom
        stiffness: root.preset("highlightLead")[0]
        damping: root.preset("highlightLead")[1]
    }
    PentadSpring {
        id: highlightFade
        stiffness: root.preset("highlightFade")[0]
        damping: root.preset("highlightFade")[1]
    }

    // Runs only while something moves or waits; a dropdown at rest does no work.
    FrameAnimation {
        running: root.visible && root.animating
        onTriggered: {
            const dt = Math.min(frameTime, SpringLogic.maxFrame);
            const due = [];
            root.queue = root.queue.filter(item => {
                item.left -= dt;
                if (item.left <= 0) {
                    due.push(item.fn);
                    return false;
                }
                return true;
            });
            due.forEach(fn => fn());
            const springs = root.allSprings();
            springs.forEach(spring => spring.advance(frameTime));
            if (!root.expanded && menu.visible && menuSpring.value < 1)
                menu.close();
            root.animating = root.queue.length > 0 || springs.some(spring => !spring.settled);
        }
    }

    TapHandler {
        onTapped: {
            root.returnFocusReason = Qt.MouseFocusReason;
            root.forceActiveFocus(Qt.MouseFocusReason);
            pressSpring.kick(SpringLogic.dropdownTiming.pressOpen);
            root.wake();
            root.toggle();
        }
    }
    HoverHandler {
        id: triggerHover
        cursorShape: Qt.PointingHandCursor
    }

    contentItem: Item {
        transform: Translate {
            y: root.liftOffset
        }

        Item {
            id: trigger
            anchors.fill: parent
            scale: pressSpring.value

            Rectangle {
                anchors.fill: parent
                radius: Metrics.radiusPill
                color: root.expanded || triggerHover.hovered ? Qt.tint(root.fill, Qt.alpha(Theme.tokens.text, Metrics.stateHover)) : root.fill
                border.width: root.visualFocus ? 1 : 0
                border.color: Theme.tokens.accent
                opacity: root.enabled ? 1 : 0.55
                Behavior on color {
                    enabled: !Theme.tokens.reducedMotion
                    ColorAnimation {
                        duration: Motion.short
                    }
                }
            }
            // Two slots: the one rolled in shows the value, the other rolls out above it.
            Item {
                id: valueBox
                anchors.left: parent.left
                anchors.leftMargin: Metrics.space4 + 2
                anchors.right: chevron.left
                anchors.rightMargin: Metrics.space2
                height: parent.height
                clip: true
                Repeater {
                    model: 2
                    Row {
                        id: slot
                        required property int index
                        readonly property bool isFront: index === root.front
                        readonly property real level: isFront ? root.rollLevel : 1 - root.rollLevel
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.verticalCenterOffset: isFront ? (1 - root.rollLevel) * root.rollDistance : -root.rollLevel * root.rollDistance
                        width: parent.width
                        spacing: Metrics.space2 + 2
                        opacity: root.clamp01(level)
                        visible: opacity > 0.001 && root.slotIndex[index] >= 0 && root.slotIndex[index] < root.count
                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: root.dotSize
                            height: root.dotSize
                            radius: width / 2
                            color: root.entryColor(root.slotIndex[slot.index])
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - root.dotSize - parent.spacing
                            text: root.entryText(root.slotIndex[slot.index])
                            textFormat: Text.PlainText
                            elide: Text.ElideRight
                            color: root.enabled ? Theme.tokens.text : Theme.tokens.textMuted
                            font.family: Theme.tokens.fontFamily
                            font.pixelSize: Metrics.textBody
                            font.weight: Font.Medium
                        }
                    }
                }
            }
            // Points down at rest and turns over on the chevron spring as the menu opens; the
            // wrapper turns it, so PentadChevron's own eased turn never runs.
            Item {
                id: chevron
                anchors.right: parent.right
                anchors.rightMargin: Metrics.space3 + 2
                anchors.verticalCenter: parent.verticalCenter
                width: Metrics.chevronIcon
                height: Metrics.chevronIcon
                rotation: 180 * chevronSpring.value
                PentadChevron {
                    anchors.fill: parent
                    direction: "down"
                    engaged: root.expanded || triggerHover.hovered
                    color: engaged ? Theme.tokens.text : Theme.tokens.textMuted
                }
            }
        }
    }

    // The popup covers the whole window: a press anywhere outside the menu lands on the catcher and
    // folds the menu away, so the dropdown always closes itself and the animation always plays.
    Popup {
        id: menu
        // The trigger's bottom-left corner in the overlay, taken when the menu opens.
        property point origin: Qt.point(0, 0)
        parent: root.Overlay.overlay
        x: 0
        y: 0
        width: parent ? parent.width : 0
        height: parent ? parent.height : 0
        padding: 0
        modal: false
        dim: false
        focus: true
        closePolicy: Popup.NoAutoClose
        background: null
        enter: null
        exit: null
        // Qt hands focus back to the trigger on its own with a popup reason, so the reason is set
        // as well: a keyboard close keeps the focus ring, a pointer close draws none.
        onClosed: if (root.returnFocusReason !== Qt.OtherFocusReason) {
            root.forceActiveFocus(root.returnFocusReason);
            root.focusReason = root.returnFocusReason;
        }

        contentItem: Item {
            focus: true
            Keys.onPressed: event => root.handleKey(event)

            MouseArea {
                anchors.fill: parent
                enabled: root.expanded
                onPressed: {
                    root.returnFocusReason = Qt.MouseFocusReason;
                    root.setOpen(false);
                }
            }

            Item {
                id: menuBody
                x: menu.origin.x
                y: menu.origin.y + root.gap + root.liftOffset
                width: root.width
                height: Math.max(0, menuSpring.value)
                opacity: root.clamp01(fadeSpring.value)
                transform: Scale {
                    origin.x: menuBody.width / 2
                    xScale: SpringLogic.menuWidthScale(menuSpring.value, root.menuHeight)
                }
                // Presses inside the menu that miss a row stay in the menu.
                MouseArea {
                    anchors.fill: parent
                }

                ContinuousSurface {
                    anchors.fill: parent
                    visible: parent.height >= 1
                    fill: root.menuFill
                    extent: Metrics.radiusPopover
                    castsShadow: true
                }
                Item {
                    anchors.fill: parent
                    clip: true
                    Rectangle {
                        x: root.menuPadding
                        width: parent.width - root.menuPadding * 2
                        y: root.highlight.top
                        height: root.highlight.height
                        radius: Metrics.radiusPopover - root.menuPadding
                        color: Qt.alpha(Theme.tokens.text, 0.08)
                        opacity: root.clamp01(highlightFade.value) * root.clamp01(fadeSpring.value)
                        visible: opacity > 0.001
                    }
                    Repeater {
                        id: rows
                        model: root.count
                        Item {
                            id: row
                            required property int index
                            readonly property bool current: index === root.currentIndex
                            property alias fall: fallSpring
                            property alias check: checkSpring
                            x: root.menuPadding
                            y: root.menuPadding + index * root.rowHeight + (fallSpring.value - 1) * 14
                            width: parent.width - root.menuPadding * 2
                            height: root.rowHeight
                            opacity: root.clamp01(fallSpring.value)
                            Accessible.role: Accessible.ListItem
                            Accessible.name: root.entryText(index)
                            Accessible.selected: current

                            PentadSpring {
                                id: fallSpring
                                stiffness: root.preset("row")[0]
                                damping: root.preset("row")[1]
                            }
                            PentadSpring {
                                id: checkSpring
                                stiffness: root.preset("check")[0]
                                damping: root.preset("check")[1]
                                Component.onCompleted: {
                                    target = row.current ? 1 : 0;
                                    snap();
                                }
                            }

                            Rectangle {
                                id: dot
                                anchors.left: parent.left
                                anchors.leftMargin: Metrics.space3
                                anchors.verticalCenter: parent.verticalCenter
                                width: root.dotSize
                                height: root.dotSize
                                radius: width / 2
                                color: root.entryColor(row.index)
                            }
                            Text {
                                anchors.left: dot.right
                                anchors.leftMargin: Metrics.space2 + 2
                                anchors.right: tick.left
                                anchors.rightMargin: Metrics.space2
                                anchors.verticalCenter: parent.verticalCenter
                                text: root.entryText(row.index)
                                textFormat: Text.PlainText
                                elide: Text.ElideRight
                                color: row.current || root.hoveredIndex === row.index ? Theme.tokens.text : Qt.alpha(Theme.tokens.text, 0.8)
                                font.family: Theme.tokens.fontFamily
                                font.pixelSize: Metrics.textBody
                                font.weight: Font.Medium
                            }
                            Shape {
                                id: tick
                                anchors.right: parent.right
                                anchors.rightMargin: Metrics.space2 + 2
                                anchors.verticalCenter: parent.verticalCenter
                                width: 24
                                height: 24
                                scale: 18 / 24
                                visible: checkSpring.value > 0.001
                                preferredRendererType: Shape.CurveRenderer
                                ShapePath {
                                    fillColor: "transparent"
                                    strokeColor: Theme.tokens.accent
                                    strokeWidth: 2.4
                                    capStyle: ShapePath.RoundCap
                                    joinStyle: ShapePath.RoundJoin
                                    PathPolyline {
                                        path: SpringLogic.partialPolyline(SpringLogic.checkPoints, root.clamp01(checkSpring.value)).map(point => Qt.point(point[0], point[1]))
                                    }
                                }
                            }
                            HoverHandler {
                                cursorShape: Qt.PointingHandCursor
                                onHoveredChanged: if (hovered && root.expanded)
                                    root.hover(row.index)
                            }
                            TapHandler {
                                onTapped: if (root.expanded) {
                                    root.returnFocusReason = Qt.MouseFocusReason;
                                    root.pick(row.index);
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
