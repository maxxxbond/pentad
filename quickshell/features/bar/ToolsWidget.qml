import QtQuick
import QtQuick.Controls
import qs.theme
import qs.components
import "../../logic/bar-tools.mjs" as Tools

Item {
    id: root
    objectName: "quick-tools-widget"
    required property var services
    signal activated(string action)
    readonly property var desktopState: services && services.desktop ? services.desktop.state : null
    readonly property var notificationState: services && services.notifications ? services.notifications.state : null
    readonly property var toolConfig: services && services.config ? services.config.documents.layout.barTools : null
    readonly property var shown: Tools.visibleTools(toolConfig)
    readonly property int toggleCount: shown.toggles.length
    readonly property int actionCount: shown.actions.length
    property var contextControl: null
    property var contextAction: null
    // Set while this bar waits for the area capture of an image search that asks for an engine.
    property bool awaitingSearch: false
    property string busyAction: ""
    readonly property Item barItem: {
        let item = parent;
        while (item) {
            if (item.objectName === "pentad-bar-face") return item;
            item = item.parent;
        }
        return null;
    }
    property int hoveredIndex: -1
    property int lastHoveredIndex: 0
    onHoveredIndexChanged: if (hoveredIndex >= 0) lastHoveredIndex = hoveredIndex
    readonly property int togglesWidth: toggleCount > 0 ? 2 + toggleCount * 26 : 0
    readonly property int actionsWidth: actionCount * 28
    readonly property int pillGap: toggleCount > 0 && actionCount > 0 ? 8 : 0
    function controlX(index) {
        return index < toggleCount ? 2 + index * 26 : togglesWidth + pillGap + 2 + (index - toggleCount) * 28;
    }
    function text(uk, en) { return typeof services.text === "function" ? services.text(uk, en) : en; }
    function showContext(control, action) {
        const sameTrigger = contextControl === control;
        contextControl = control;
        contextAction = action;
        if (contextMenu.opened && !sameTrigger) contextMenu.open();
        else contextMenu.toggle();
    }
    // A bar wing without room stays laid out but disabled, so leaving the bar arrives here.
    onEnabledChanged: if (!enabled) { contextMenu.close(); searchMenu.close(); }
    function actionName(id) {
        return id === "imageSearch" ? "image-search" : id === "qrScan" ? "qr-scan" : id === "audioOutput" ? "audio-output" : id;
    }
    function iconUrl(path) { return Qt.resolvedUrl("../../assets/icons/material/" + path); }
    readonly property var actions: shown.toggles.concat(shown.actions).map(function(tool) {
        return { id: tool.id, kind: tool.kind, action: root.actionName(tool.id), icon: root.iconUrl(tool.icon),
            label: root.text(tool.labelUk, tool.labelEn) };
    })
    readonly property var engines: Tools.enabledEngines(toolConfig)
    // Active, available and pending state of one tool; every source is read here so bindings follow it.
    function stateOf(action) {
        const desktop = desktopState && desktopState.value ? desktopState.value : null;
        const ready = !!desktopState && desktopState.kind === "ready" && !!desktop
            && services.preview !== true && services.safeMode !== true;
        const toolBusy = !!desktop && desktop.toolBusy === true;
        const quick = services.quickSettings ? services.quickSettings.state : null;
        const quickValue = quick && quick.kind === "ready" ? quick.value : null;
        const quickPending = function(kind) {
            return !!quickValue && quickValue.busy && !!services.quickSettings.operation
                && services.quickSettings.operation.kind === kind;
        };
        const profile = services.power ? services.power.profileState : null;
        const profileValue = profile && profile.kind === "ready" ? profile.value : null;
        if (action === "dnd") return { available: ready && !!notificationState && notificationState.status === "available",
            active: !!notificationState && notificationState.dnd === true, pending: false };
        if (action === "inhibit") return { available: ready, active: ready && desktop.inhibited === true, pending: ready && desktop.inhibitPending === true };
        if (action === "record") return { available: ready, active: ready && desktop.recording === true, pending: ready && desktop.recordPending === true };
        if (action === "focus") return { available: ready, active: ready && desktop.focus === true, pending: false };
        if (action === "night") return { available: !!quickValue && quickValue.nightAvailable === true, active: !!quickValue && quickValue.night === true, pending: quickPending("night") };
        if (action === "bluetooth") return { available: !!quickValue && quickValue.bluetoothAvailable === true, active: !!quickValue && quickValue.bluetooth === true,
            pending: quickPending("bluetooth") };
        if (action === "airplane") return { available: !!quickValue && quickValue.airplaneAvailable === true, active: !!quickValue && quickValue.airplane === true,
            pending: quickPending("airplane") };
        if (action === "saver") return { available: !!profileValue, active: !!profileValue && profileValue.actual === "power-saver",
            pending: !!profileValue && profileValue.pending === true };
        if (action === "privacy") return { available: !!services.notifications, active: !!services.notifications && services.notifications.privacy === true, pending: false };
        if (Tools.scriptActions.indexOf(action) >= 0)
            return { available: ready && !toolBusy, active: false, pending: toolBusy && root.busyAction === action };
        return { available: ready, active: false, pending: false };
    }
    function activate(action) {
        if (Tools.scriptActions.indexOf(action) >= 0) busyAction = action;
        awaitingSearch = action === "image-search" && Tools.searchPlan(toolConfig).kind === "ask";
        activated(action);
    }
    readonly property alias contextPopup: contextMenu
    readonly property alias searchPopup: searchMenu
    readonly property alias buttonRepeater: controls
    implicitWidth: row.width
    implicitHeight: 28

    Connections {
        target: root.services ? root.services.desktop : null
        ignoreUnknownSignals: true
        function onCommandFinished(requestId, result) {
            if (!root.awaitingSearch) return;
            root.awaitingSearch = false;
            if (!result.ok || result.reason !== "choose") return;
            const control = controls.itemAt(root.actions.findIndex(function(item) { return item.action === "image-search"; }));
            if (!control) return;
            root.contextControl = control;
            searchMenu.open();
        }
    }

    Item {
        id: row
        width: root.togglesWidth + root.pillGap + root.actionsWidth
        height: 28
        anchors.centerIn: parent
        Rectangle {
            objectName: "quick-tool-toggles"
            x: 0
            y: 0
            width: root.togglesWidth
            height: 28
            radius: 14
            visible: root.toggleCount > 0
            color: Theme.tokens.surfaceRaised
        }
        Rectangle {
            objectName: "quick-tool-actions"
            x: root.togglesWidth + root.pillGap
            y: 0
            width: root.actionsWidth
            height: 28
            radius: 14
            visible: root.actionCount > 0
            color: Theme.tokens.surfaceRaised
        }
        Rectangle {
            id: hoverIndicator
            objectName: "tools-hover-indicator"
            y: 2
            width: 24
            height: 24
            radius: 12
            color: Theme.tokens.surfaceOverlay
            opacity: root.hoveredIndex >= 0 ? 1 : 0
            x: root.controlX(root.lastHoveredIndex)
            property bool seen: false
            Behavior on x {
                enabled: hoverIndicator.seen && !Theme.tokens.reducedMotion
                NumberAnimation { duration: Motion.medium; easing.type: Easing.OutCubic }
            }
            Behavior on opacity { NumberAnimation { duration: Theme.tokens.reducedMotion ? 0 : 180; easing.type: Easing.OutCubic } }
            onOpacityChanged: seen = opacity > 0
        }
        Repeater {
            id: controls
            model: root.actions
            delegate: Item {
                id: control
                required property var modelData
                required property int index
                readonly property var toolState: root.stateOf(modelData.action)
                readonly property bool active: toolState.active
                width: 24
                height: 24
                x: root.controlX(index)
                y: 2
                readonly property bool actionAvailable: toolState.available || toolState.pending
                readonly property bool pending: toolState.pending
                opacity: actionAvailable ? 1 : 0.45
                Accessible.role: Accessible.Button
                Accessible.name: modelData.label + (actionAvailable ? "" : " unavailable")
                Accessible.description: pending ? "In progress" : ""
                Rectangle {
                    anchors.fill: parent
                    radius: 16
                    color: root.contextControl === control && (contextMenu.opened || searchMenu.opened) ? Theme.tokens.surface
                        : control.active
                        ? (modelData.action === 'record' ? Qt.alpha(Theme.tokens.error, 0.1) : Theme.tokens.surfaceOverlay)
                        : 'transparent'
                }
                PentadIcon {
                    anchors.centerIn: parent
                    visible: !control.pending
                    source: modelData.icon
                    pixelSize: Metrics.panelIcon
                    color: modelData.action === 'record' && control.active
                        ? Theme.tokens.error
                        : Qt.alpha(Theme.tokens.text, modelData.kind === "toggle" && !control.active
                            ? (pointer.containsMouse ? 0.65 : 0.45) : 0.8)
                    accessibleName: modelData.label
                }
                PentadText {
                    anchors.centerIn: parent
                    visible: control.pending
                    text: "…"
                    role: "caption"
                    Accessible.ignored: true
                }
                MouseArea {
                    id: pointer
                    objectName: "tools-input-" + control.modelData.action
                    anchors.fill: parent
                    focus: true
                    activeFocusOnTab: true
                    hoverEnabled: true
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    cursorShape: Qt.PointingHandCursor
                    onContainsMouseChanged: {
                        if (containsMouse) root.hoveredIndex = control.index;
                        else if (root.hoveredIndex === control.index) root.hoveredIndex = -1;
                    }
                    onPressed: function(event) {
                        if (event.button === Qt.RightButton) root.showContext(control, control.modelData);
                        else if (event.button === Qt.LeftButton && control.actionAvailable && !control.pending) root.activate(control.modelData.action);
                    }
                    Keys.onReturnPressed: if (control.actionAvailable && !control.pending) root.activate(control.modelData.action)
                    Keys.onSpacePressed: if (control.actionAvailable && !control.pending) root.activate(control.modelData.action)
                    Keys.onPressed: function(event) {
                        if (event.key === Qt.Key_Menu || (event.key === Qt.Key_F10 && (event.modifiers & Qt.ShiftModifier))) {
                            root.showContext(control, control.modelData);
                            event.accepted = true;
                        }
                    }
                }
                PentadToolTip {
                    visible: pointer.containsMouse && !(root.contextControl === control && (contextMenu.opened || searchMenu.opened))
                    text: control.modelData.label
                }
            }
        }
    }
    AttachedPopover {
        id: contextMenu
        objectName: "tool-context-menu"
        anchorItem: root.contextControl
        barItem: root.barItem
        manager: root.services.popups || null
        contentItem: Item {
            implicitHeight: contextContent.height
            implicitWidth: Math.max(192, contextLabel.implicitWidth, contextStatus.implicitWidth, colorButton.implicitWidth)
            width: implicitWidth
            Column {
                id: contextContent
                width: parent.width
                spacing: 4
                Column {
                    width: parent.width
                    PentadText {
                        id: contextLabel
                        width: parent.width
                        role: "caption"
                        solid: true
                        wrapMode: Text.NoWrap
                        elide: Text.ElideRight
                        text: root.contextAction ? root.contextAction.label : ""
                    }
                    PentadText {
                        id: contextStatus
                        width: parent.width
                        role: "caption"
                        solid: true
                        wrapMode: Text.NoWrap
                        elide: Text.ElideRight
                        color: Theme.tokens.textMuted
                        text: !root.contextControl || !root.contextControl.actionAvailable
                            ? root.text("Недоступно", "Unavailable")
                            : root.contextControl.pending ? root.text("Виконується…", "In progress…")
                            : root.contextAction && root.contextAction.action === "record"
                                ? root.text("Область · без звуку", "Area · no audio")
                            : root.contextAction && root.contextAction.action === "image-search"
                                ? root.text("Шукати в…", "Search with…")
                                : ""
                        visible: text !== ""
                    }
                }
                PentadButton {
                    visible: !!root.contextAction && root.contextAction.action === "screenshot"
                    controlHeight: 28
                    requestedEnabled: !!root.contextControl && root.contextControl.actionAvailable
                    text: root.text("Швидко скопіювати область", "Quick copy region")
                    onClicked: { contextMenu.close(); root.activated("screenshot-copy"); }
                }
                PentadButton {
                    visible: !!root.contextAction && root.contextAction.action === "screenshot"
                    controlHeight: 28
                    text: root.text("Налаштування скріншотів", "Screenshot settings")
                    onClicked: { contextMenu.close(); root.activated("screenshot-settings"); }
                }
                PentadButton {
                    id: colorButton
                    visible: !!root.contextAction && root.contextAction.action === "screenshot"
                    controlHeight: 28
                    requestedEnabled: !!root.contextControl && root.contextControl.actionAvailable && !root.contextControl.pending
                    text: root.text("Вибрати колір", "Pick color")
                    onPressed: { contextMenu.close(); root.activated("color-picker"); }
                }
                Repeater {
                    model: root.contextAction && root.contextAction.action === "inhibit"
                        && !(root.desktopState && root.desktopState.value && root.desktopState.value.inhibited) ? Tools.inhibitDurations : []
                    delegate: PentadButton {
                        required property int modelData
                        width: contextContent.width
                        controlHeight: 28
                        requestedEnabled: !!root.contextControl && root.contextControl.actionAvailable && !root.contextControl.pending
                        text: Tools.durationLabel(modelData, root.text)
                        onClicked: { contextMenu.close(); root.activated("inhibit:" + modelData); }
                    }
                }
                Repeater {
                    model: root.contextAction && root.contextAction.action === "image-search" ? root.engines : []
                    delegate: PentadButton {
                        required property var modelData
                        width: contextContent.width
                        controlHeight: 28
                        requestedEnabled: !!root.contextControl && root.contextControl.actionAvailable && !root.contextControl.pending
                        text: modelData.name
                        onClicked: { contextMenu.close(); root.activated("image-search:" + modelData.id); }
                    }
                }
            }
        }
    }
    // Opened after an area capture when image search is set to ask which engine to use.
    AttachedPopover {
        id: searchMenu
        objectName: "image-search-menu"
        // Opens after the area pick, with the cursor far from the bar: leaving must not dismiss it.
        pointerDismissEnabled: false
        anchorItem: root.contextControl
        barItem: root.barItem
        manager: root.services.popups || null
        contentItem: Item {
            implicitHeight: searchContent.height
            implicitWidth: Math.max(192, searchTitle.implicitWidth)
            width: implicitWidth
            Column {
                id: searchContent
                width: parent.width
                spacing: 4
                PentadText {
                    id: searchTitle
                    width: parent.width
                    role: "caption"
                    wrapMode: Text.NoWrap
                    elide: Text.ElideRight
                    text: root.text("Фрагмент у буфері · Ctrl+V на сторінці", "Snippet copied · Ctrl+V on the page")
                }
                Repeater {
                    model: root.engines
                    delegate: PentadButton {
                        required property var modelData
                        width: searchContent.width
                        controlHeight: 28
                        text: modelData.name
                        onClicked: { searchMenu.close(); root.activated("image-open:" + modelData.id); }
                    }
                }
            }
        }
    }
}
