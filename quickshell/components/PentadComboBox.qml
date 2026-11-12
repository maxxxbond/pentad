pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Shapes
import qs.theme
import "../logic/spring.mjs" as SpringLogic

// A borderless capsule like PentadButton, with the chevron in a round well concentric with the
// trailing end. The only edges are the keyboard focus ring and the softened error outline.
//
// The list moves like PentadSpringDropdown, on the same springs (SpringLogic.dropdownSprings): it
// drops out on a height spring that overshoots once, the rows fall in one after another, one
// highlight stretches between rows (a stiff leading edge, a soft trailing one), a pick draws its
// check and rolls the new value into the box, and every close folds the list away during the
// popup's exit, so Escape, a press outside and a pick all animate. Reduced motion lands at once.
//
// A custom delegate leaves its background empty (the moving highlight marks the row) and takes
// the fall with `opacity: control.rowLevel(index)` and `transform: Translate { y: control.rowDrop(index) }`.
ComboBox {
    id: control
    property string accessibleName: ""
    property bool error: false
    // Resting fill; on a raised card pass the next elevation step.
    property color fill: Theme.tokens.surfaceRaised
    readonly property bool mirroredLayout: LayoutMirroring.enabled
    readonly property bool engaged: control.hovered || control.visualFocus || control.listOpen
    // The well sits `wellInset` inside the capsule, so its circle shares the capsule end's centre.
    readonly property real wellInset: 4
    readonly property real wellSize: height - 2 * wellInset
    readonly property real listPadding: Metrics.space1
    readonly property real listGap: Metrics.space1 + 2
    readonly property real listMaxHeight: 320
    // The list's full height, and how far it is shown, for hosts and tests.
    readonly property real listHeight: Math.min(options.contentHeight + listPadding * 2, listMaxHeight)
    readonly property real listLevel: listHeight > 0 ? menuSpring.value / listHeight : 0
    readonly property real rollLevel: rollSpring.value
    readonly property var highlightSpan: SpringLogic.highlightSpan(highlightTop.value, highlightBottom.value, -1e6, 1e6, 8)
    readonly property bool reducedMotion: Theme.tokens.reducedMotion
    property bool animating: false

    // Motion state; read only.
    property bool listOpen: false
    // The list keeps its height until the fold starts, which waits for the check after a pick.
    property bool listShown: false
    property bool pickPending: false
    property int exitMs: 0
    property int firstRow: 0
    property int rowTick: 0
    property var rowSprings: []
    property int shownHighlight: -1
    property int checkedIndex: currentIndex
    property int uncheckedIndex: -1
    property var slotText: ["", ""]
    property int front: 0
    property var queue: []

    function clamp01(value) {
        return Math.max(0, Math.min(1, value));
    }
    function preset(name) {
        return SpringLogic.dropdownSprings[name];
    }
    function wake() {
        animating = true;
    }
    function after(seconds, fn) {
        if (reducedMotion || seconds <= 0) {
            fn();
            return;
        }
        queue.push({ left: seconds, fn: fn });
        wake();
    }
    // How far row `index` has fallen in, 0..1; rows below the first screenful arrive in place.
    function rowLevel(index) {
        const tick = rowTick;
        const slot = index - firstRow;
        const spring = slot >= 0 && slot < rowSprings.length ? rowSprings[slot] : null;
        return spring ? clamp01(spring.value) : clamp01(fadeSpring.value * 4);
    }
    function rowDrop(index) {
        const tick = rowTick;
        const slot = index - firstRow;
        const spring = slot >= 0 && slot < rowSprings.length ? rowSprings[slot] : null;
        return spring ? (spring.value - 1) * 14 : 0;
    }
    function checkLevel(index) {
        return index === checkedIndex ? checkIn.value : index === uncheckedIndex ? checkOut.value : 0;
    }
    function setRows(open) {
        const count = rowSprings.length;
        for (let slot = 0; slot < count; slot++) {
            const spring = rowSprings[slot];
            after(SpringLogic.dropdownRowDelay(slot, count, open), () => {
                spring.target = control.listOpen ? 1 : 0;
                if (control.reducedMotion) {
                    spring.value = spring.target;
                    spring.velocity = 0;
                }
                control.rowTick++;
                control.wake();
            });
        }
    }
    function showList() {
        listOpen = true;
        listShown = true;
        pickPending = false;
        fadeSpring.target = 1;
        chevronSpring.target = 1;
        // One spring per row of the first screenful; a reopen keeps the rows where they are.
        const rows = Math.min(Math.max(1, control.count), Math.ceil(listMaxHeight / Metrics.controlMedium) + 1);
        if (rowSprings.length !== rows) {
            const springs = [];
            for (let i = 0; i < rows; i++)
                springs.push(rowSprings[i] || { value: 0, velocity: 0, target: 0 });
            rowSprings = springs;
        }
        firstRow = 0;
        shownHighlight = -1;
        highlightFade.target = 0;
        highlightFade.snap();
        setRows(true);
        Qt.callLater(placeList);
        wake();
    }
    // Once the list has its rows: scroll the current one into view, count the fall from the first
    // row on screen and put the highlight on the current row.
    function placeList() {
        if (!popup.visible || !listOpen)
            return;
        if (currentIndex >= 0)
            options.positionViewAtIndex(currentIndex, ListView.Contain);
        const first = options.indexAt(4, options.contentY + 1);
        firstRow = first >= 0 ? first : 0;
        moveHighlight(highlightedIndex >= 0 ? highlightedIndex : currentIndex, true);
    }
    function foldList() {
        if (!listOpen)
            return;
        listOpen = false;
        const delay = pickPending && !reducedMotion ? SpringLogic.dropdownTiming.closeAfterPick : 0;
        exitMs = reducedMotion ? 0 : Math.ceil((delay + SpringLogic.dropdownFoldSeconds(menuSpring.value)) * 1000) + 16;
        chevronSpring.target = 0;
        after(delay, () => {
            if (control.listOpen)
                return;
            control.listShown = false;
            fadeSpring.target = 0;
            highlightFade.target = 0;
            control.setRows(false);
        });
        wake();
    }
    function moveHighlight(index, snap) {
        const row = index >= 0 ? options.itemAtIndex(index) : null;
        if (!row) {
            highlightFade.target = 0;
            shownHighlight = -1;
            wake();
            return;
        }
        const top = row.y;
        const bottom = row.y + row.height;
        if (snap || shownHighlight < 0) {
            highlightTop.target = top;
            highlightBottom.target = bottom;
            highlightTop.jump(top);
            highlightBottom.jump(bottom);
        } else {
            const down = index > shownHighlight;
            const lead = down ? highlightBottom : highlightTop;
            const trail = down ? highlightTop : highlightBottom;
            lead.stiffness = preset("highlightLead")[0];
            lead.damping = preset("highlightLead")[1];
            trail.stiffness = preset("highlightTrail")[0];
            trail.damping = preset("highlightTrail")[1];
            highlightTop.target = top;
            highlightBottom.target = bottom;
        }
        shownHighlight = index;
        highlightFade.target = 1;
        wake();
    }
    function pressKick(level) {
        pressSpring.kick(level);
        wake();
    }

    onHighlightedIndexChanged: if (popup.visible && listOpen) moveHighlight(highlightedIndex, false)
    onListHeightChanged: if (listOpen) wake()
    Component.onCompleted: slotText = [displayText, ""]
    onActivated: {
        pickPending = true;
        rollWindow.restart();
        pressKick(SpringLogic.dropdownTiming.pressPick);
    }
    // A pick, or a change right after one, rolls the value and moves the check; a host's change
    // at rest lands at once.
    onCurrentIndexChanged: {
        const animated = popup.visible || rollWindow.running;
        if (checkedIndex !== currentIndex) {
            uncheckedIndex = animated ? checkedIndex : -1;
            checkedIndex = currentIndex;
            checkIn.target = 1;
            checkOut.target = 0;
            if (animated) {
                checkIn.jump(0);
                checkOut.jump(1);
            } else {
                checkIn.snap();
                checkOut.snap();
            }
            wake();
        }
    }
    onDisplayTextChanged: {
        if (slotText[front] === displayText)
            return;
        const slots = slotText.slice();
        if (popup.visible || rollWindow.running) {
            front = front ^ 1;
            slots[front] = displayText;
            slotText = slots;
            rollSpring.target = 1;
            rollSpring.jump(0);
            wake();
        } else {
            slots[front] = displayText;
            slotText = slots;
            rollSpring.snap();
        }
    }

    implicitHeight: Metrics.controlMedium
    implicitWidth: 160
    leftPadding: mirroredLayout ? wellSize + wellInset + 8 : 16
    rightPadding: mirroredLayout ? 16 : wellSize + wellInset + 8
    font.family: Theme.tokens.fontFamily
    font.pixelSize: Metrics.textBody
    Accessible.name: accessibleName !== "" ? accessibleName : displayText
    Accessible.role: Accessible.ComboBox
    Accessible.description: error ? "Error" : ""

    Timer {
        id: rollWindow
        interval: 1200
    }

    PentadSpring {
        id: menuSpring
        stiffness: control.preset("menu")[0]
        damping: control.preset("menu")[1]
        target: control.listShown ? control.listHeight : 0
    }
    PentadSpring {
        id: fadeSpring
        stiffness: control.preset("fade")[0]
        damping: control.preset("fade")[1]
    }
    PentadSpring {
        id: chevronSpring
        stiffness: control.preset("chevron")[0]
        damping: control.preset("chevron")[1]
    }
    PentadSpring {
        id: pressSpring
        stiffness: control.preset("press")[0]
        damping: control.preset("press")[1]
        value: 1
        target: 1
    }
    PentadSpring {
        id: rollSpring
        stiffness: control.preset("roll")[0]
        damping: control.preset("roll")[1]
        value: 1
        target: 1
    }
    PentadSpring {
        id: checkIn
        stiffness: control.preset("check")[0]
        damping: control.preset("check")[1]
        value: 1
        target: 1
    }
    PentadSpring {
        id: checkOut
        stiffness: control.preset("check")[0]
        damping: control.preset("check")[1]
    }
    PentadSpring {
        id: highlightTop
        stiffness: control.preset("highlightLead")[0]
        damping: control.preset("highlightLead")[1]
    }
    PentadSpring {
        id: highlightBottom
        stiffness: control.preset("highlightLead")[0]
        damping: control.preset("highlightLead")[1]
    }
    PentadSpring {
        id: highlightFade
        stiffness: control.preset("highlightFade")[0]
        damping: control.preset("highlightFade")[1]
    }

    // Runs only while something moves or waits; a box at rest does no work.
    FrameAnimation {
        running: control.animating
        onTriggered: {
            const dt = Math.min(frameTime, SpringLogic.maxFrame);
            const due = [];
            control.queue = control.queue.filter(item => {
                item.left -= dt;
                if (item.left <= 0) {
                    due.push(item.fn);
                    return false;
                }
                return true;
            });
            due.forEach(fn => fn());
            const springs = [menuSpring, fadeSpring, chevronSpring, pressSpring, rollSpring, checkIn, checkOut, highlightTop, highlightBottom, highlightFade];
            springs.forEach(spring => spring.advance(frameTime));
            let rowsMoving = false;
            const [k, c] = control.preset("row");
            control.rowSprings.forEach(spring => {
                if (control.reducedMotion || SpringLogic.springSettled(spring.value, spring.velocity, spring.target)) {
                    spring.value = spring.target;
                    spring.velocity = 0;
                    return;
                }
                const next = SpringLogic.stepSpring(spring.value, spring.velocity, spring.target, k, c, frameTime);
                spring.value = next.value;
                spring.velocity = next.velocity;
                rowsMoving = true;
            });
            control.rowTick++;
            control.animating = rowsMoving || control.queue.length > 0 || springs.some(spring => !spring.settled);
        }
    }

    MenuPointerIntent {
        active: control.listOpen
        anchorItem: control
        surfaceItem: control.popup.contentItem
        onDismissRequested: control.popup.close()
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onPressed: {
            control.forceActiveFocus(Qt.MouseFocusReason);
            control.pressKick(SpringLogic.dropdownTiming.pressOpen);
            if (control.listOpen)
                control.popup.close();
            else
                control.popup.open();
        }
    }

    // The press squash scales each layer about the box's centre.
    contentItem: Item {
        id: valueBox
        clip: true
        transform: Scale {
            origin.x: control.width / 2 - valueBox.x
            origin.y: control.height / 2 - valueBox.y
            xScale: pressSpring.value
            yScale: pressSpring.value
        }
        // Two slots: the one rolled in shows the value, the other rolls out above it.
        Repeater {
            model: 2
            Text {
                id: slot
                required property int index
                readonly property bool isFront: index === control.front
                readonly property real distance: Math.round(control.height * 0.4)
                width: valueBox.width
                height: valueBox.height
                y: isFront ? (1 - control.rollLevel) * distance : -control.rollLevel * distance
                opacity: control.clamp01(isFront ? control.rollLevel : 1 - control.rollLevel)
                visible: opacity > 0.001
                text: control.slotText[index]
                textFormat: Text.PlainText
                color: control.enabled ? Theme.tokens.text : Theme.tokens.textMuted
                font: control.font
                verticalAlignment: Text.AlignVCenter
                elide: Text.ElideRight
            }
        }
    }
    indicator: Rectangle {
        id: well
        x: control.mirroredLayout ? control.wellInset : control.width - width - control.wellInset
        y: control.wellInset
        width: control.wellSize
        height: control.wellSize
        radius: width / 2
        color: Qt.alpha(Theme.tokens.text, control.engaged ? 0.12 : 0.06)
        transform: Scale {
            origin.x: control.width / 2 - well.x
            origin.y: control.height / 2 - well.y
            xScale: pressSpring.value
            yScale: pressSpring.value
        }
        Behavior on color { enabled: !Theme.tokens.reducedMotion; ColorAnimation { duration: Motion.short } }
        // Points down at rest and turns over on the chevron spring; the wrapper turns it, so
        // PentadChevron's own eased turn never runs.
        Item {
            anchors.centerIn: parent
            width: Metrics.chevronIcon
            height: Metrics.chevronIcon
            rotation: 180 * chevronSpring.value
            PentadChevron {
                anchors.fill: parent
                direction: "down"
                pixelSize: Metrics.chevronIcon
                color: control.engaged ? Theme.tokens.text : Theme.tokens.textMuted
                engaged: control.engaged
            }
        }
    }
    background: Rectangle {
        id: capsule
        readonly property color statusFill: control.error ? Qt.tint(control.fill, Qt.alpha(Theme.tokens.error, 0.12)) : control.fill
        radius: Metrics.radiusPill
        color: control.listOpen || control.down || control.hovered ? Qt.tint(statusFill, Qt.alpha(Theme.tokens.text, Metrics.stateHover)) : statusFill
        border.width: control.error || control.visualFocus ? 1 : 0
        border.color: control.error ? Qt.alpha(Theme.tokens.error, 0.7) : Theme.tokens.accent
        opacity: control.enabled ? 1 : 0.55
        transform: Scale {
            origin.x: control.width / 2
            origin.y: control.height / 2
            xScale: pressSpring.value
            yScale: pressSpring.value
        }
        Behavior on color { enabled: !Theme.tokens.reducedMotion; ColorAnimation { duration: Motion.short } }
    }

    popup: Popup {
        id: list
        y: control.height + control.listGap
        width: Math.max(control.width, 180)
        x: control.mirroredLayout ? control.width - width : 0
        height: Math.max(0, menuSpring.value)
        padding: control.listPadding
        opacity: control.clamp01(fadeSpring.value)
        // The box keeps the keyboard focus, so its own Up, Down, Enter and Escape drive the open list.
        focus: false
        // A press on the box itself is left to its toggle; with CloseOnPressOutside it would close
        // the list and the same press would open it again.
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutsideParent
        // No eased transitions: the springs open the list, and the exit only keeps it on screen
        // while it folds away. `visible` turns false as soon as the close starts.
        enter: null
        exit: Transition {
            PauseAnimation {
                duration: control.exitMs
            }
        }
        onAboutToShow: control.showList()
        onAboutToHide: control.foldList()

        background: ContinuousSurface {
            id: listSurface
            fill: Theme.tokens.surfaceOverlay
            extent: Metrics.radiusPopover
            castsShadow: true
            visible: list.height >= 1
            transform: Scale {
                origin.x: listSurface.width / 2
                xScale: SpringLogic.menuWidthScale(menuSpring.value, control.listHeight)
            }
        }
        // The list keeps its full height inside a box that the height spring reveals.
        contentItem: Item {
            id: listBox
            clip: true
            transform: Scale {
                origin.x: listBox.width / 2
                xScale: SpringLogic.menuWidthScale(menuSpring.value, control.listHeight)
            }
            function itemAtIndex(index) {
                return options.itemAtIndex(index);
            }

            ListView {
                id: options
                width: parent.width
                height: Math.max(0, control.listHeight - control.listPadding * 2)
                clip: true
                spacing: 2
                model: list.visible || control.listOpen || list.height >= 1 ? control.delegateModel : null
                currentIndex: control.highlightedIndex
                highlightFollowsCurrentItem: false
                boundsBehavior: Flickable.StopAtBounds
                // One highlight for the whole list, between its two edge springs.
                highlight: Rectangle {
                    x: 0
                    width: options.width
                    y: control.highlightSpan.top
                    height: control.highlightSpan.height
                    z: 0
                    radius: Metrics.radiusPopover - control.listPadding
                    color: Qt.alpha(Theme.tokens.text, 0.08)
                    opacity: control.clamp01(highlightFade.value)
                    visible: opacity > 0.001
                }
                // The custom handle has no idle fade of its own, so the bar only exists when the list scrolls.
                ScrollBar.vertical: ScrollBar {
                    policy: options.contentHeight > options.height + 1 ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
                    implicitWidth: 6
                    contentItem: Rectangle { radius: Metrics.radiusTag; color: Qt.alpha(Theme.tokens.text, 0.24) }
                }
            }
        }
    }

    delegate: ItemDelegate {
        id: row
        required property int index
        required property var modelData
        readonly property bool current: control.currentIndex === index
        width: ListView.view ? ListView.view.width : control.width
        height: Metrics.controlMedium
        leftPadding: 12
        rightPadding: 10
        text: {
            const entry = modelData;
            const role = control.textRole;
            return role ? String(entry[role]) : String(entry);
        }
        highlighted: control.highlightedIndex === index
        opacity: control.rowLevel(index)
        transform: Translate { y: control.rowDrop(row.index) }
        Accessible.name: text
        // The moving highlight marks the row under the pointer or the keys.
        background: null
        contentItem: Item {
            Text {
                anchors.left: parent.left
                anchors.right: check.left
                anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                text: row.text
                textFormat: Text.PlainText
                color: row.current || row.highlighted || row.hovered ? Theme.tokens.text : Theme.tokens.textMuted
                font.family: Theme.tokens.fontFamily
                font.pixelSize: Metrics.textBody
                font.weight: row.current ? Font.Medium : Font.Normal
                elide: Text.ElideRight
            }
            // The check draws itself on a pick and undraws from the row it leaves.
            Shape {
                id: check
                readonly property real level: control.clamp01(control.checkLevel(row.index))
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                width: 24
                height: 24
                scale: (Metrics.panelIcon + 2) / 24
                visible: level > 0.001
                preferredRendererType: Shape.CurveRenderer
                Accessible.ignored: true
                ShapePath {
                    fillColor: "transparent"
                    strokeColor: Theme.tokens.accent
                    strokeWidth: 2.4
                    capStyle: ShapePath.RoundCap
                    joinStyle: ShapePath.RoundJoin
                    PathPolyline {
                        path: SpringLogic.partialPolyline(SpringLogic.checkPoints, check.level).map(point => Qt.point(point[0], point[1]))
                    }
                }
            }
        }

        MouseArea {
            anchors.fill: parent
            // A row folding away takes no second pick.
            enabled: control.listOpen
            cursorShape: Qt.PointingHandCursor
            onPressed: {
                control.pickPending = true;
                rollWindow.restart();
                control.currentIndex = row.index;
                control.activated(row.index);
                control.popup.close();
            }
        }
    }
}
