pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls.Basic
import qs.components
import qs.theme

Item {
    id: root
    required property var services
    readonly property var session: services.session
    readonly property string displayName: session.displayName || session.userName || "—"
    // Rarely used, consequential actions live behind the power button; lock stays one click away.
    readonly property var powerActions: [
        { key: "logout", icon: "logout-symbolic.svg", label: services.text("Вийти із сесії", "Log out") },
        { key: "reboot", icon: "restart-alt-symbolic.svg", label: services.text("Перезапустити ПК", "Restart PC") },
        { key: "poweroff", icon: "power-settings-new-symbolic.svg", label: services.text("Вимкнути ПК", "Power off PC") }
    ]
    readonly property bool powerPending: ["logout", "reboot", "poweroff"].includes(session.pending)
    property bool editing: false
    property alias powerMenu: powerMenu
    signal detailsRequested(string section)
    signal editRequested()
    readonly property int controlSize: 40
    readonly property int inset: Metrics.capsulePadding
    implicitHeight: 48

    function iconUrl(name) { return Qt.resolvedUrl("../../assets/icons/material/controls/" + name); }

    function openSettings() {
        if (root.services.popups) root.services.popups.close();
        root.services.settings.openPage();
    }

    function requestAction(key) {
        powerMenu.close();
        root.session.request(key);
        if (root.session.state.error) root.detailsRequested("session");
    }

    // Holding a power action to the end of its fill is the confirmation; there is no second step.
    function commitAction(key) {
        powerMenu.close();
        if (root.session.request(key)) root.session.confirm();
        if (root.session.state.error) root.detailsRequested("session");
    }

    Rectangle {
        id: logoMark
        objectName: "control-center-logo"
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        width: root.controlSize
        height: width
        radius: height / 2
        color: Theme.tokens.accent
        Accessible.ignored: true
        PentadIcon {
            anchors.centerIn: parent
            source: Qt.resolvedUrl("../../assets/icons/brand/logo-symbolic.svg")
            pixelSize: Metrics.logo - 4
            color: Theme.tokens.onAccent
            Accessible.ignored: true
        }
    }
    Column {
        anchors.left: logoMark.right
        anchors.leftMargin: 12
        anchors.right: actionGroup.left
        anchors.rightMargin: 12
        anchors.verticalCenter: parent.verticalCenter
        PentadText {
            objectName: "control-center-user-name"
            width: parent.width
            text: root.displayName
            role: "section"
            solid: true
            font.weight: Font.DemiBold
            elide: Text.ElideRight
            wrapMode: Text.NoWrap
        }
        PentadText {
            objectName: "control-center-host-name"
            width: parent.width
            text: root.session.hostName || "—"
            role: "caption"
            solid: true
            color: Theme.tokens.textMuted
            elide: Text.ElideRight
            wrapMode: Text.NoWrap
        }
    }

    component HeaderAction: Button {
        id: action
        property url iconSource: ""
        property bool selected: false
        property bool busy: false
        width: root.controlSize - root.inset * 2
        height: width
        padding: 0
        hoverEnabled: true
        Accessible.name: text
        Accessible.role: Accessible.Button
        ToolTip.visible: hovered || visualFocus
        ToolTip.delay: 500
        ToolTip.text: text
        scale: pressed ? 0.92 : 1
        Behavior on scale { NumberAnimation { duration: Motion.press; easing.type: Easing.OutCubic } }
        background: Rectangle {
            radius: height / 2
            opacity: action.enabled ? 1 : 0.4
            color: action.selected ? Theme.tokens.accent
                : action.pressed ? Theme.tokens.outline
                : action.hovered || action.checked ? Theme.tokens.surfaceOverlay : "transparent"
            border.width: action.visualFocus ? 2 : 0
            border.color: action.selected ? Theme.tokens.onAccent : Theme.tokens.accent
            Behavior on color { ColorAnimation { duration: Motion.state } }
        }
        contentItem: Item {
            PentadIcon {
                visible: !action.busy
                anchors.centerIn: parent
                source: action.iconSource
                pixelSize: Metrics.statusIcon
                color: action.selected ? Theme.tokens.onAccent : Theme.tokens.text
                opacity: action.enabled ? (action.hovered || action.selected ? 1 : 0.88) : 0.35
                Behavior on color { ColorAnimation { duration: Motion.state } }
                Accessible.ignored: true
            }
            BusyIndicator {
                visible: action.busy && !Theme.tokens.reducedMotion
                running: visible
                anchors.centerIn: parent
                width: Metrics.statusIcon
                height: Metrics.statusIcon
                palette.dark: Theme.tokens.text
                Accessible.ignored: true
            }
        }
    }

    Rectangle {
        id: actionGroup
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        width: actionRow.width + root.inset * 2
        height: root.controlSize
        radius: height / 2
        color: Theme.tokens.surfaceRaised
        Row {
            id: actionRow
            x: root.inset
            anchors.verticalCenter: parent.verticalCenter
            spacing: 0
            HeaderAction {
                objectName: "control-center-session-edit"
                text: root.editing ? root.services.text("Готово", "Done") : root.services.text("Редагувати сітку", "Edit grid")
                iconSource: root.iconUrl(root.editing ? "check-symbolic.svg" : "edit-symbolic.svg")
                selected: root.editing
                Accessible.checked: root.editing
                onClicked: root.editRequested()
            }
            HeaderAction {
                objectName: "control-center-session-settings"
                text: root.services.text("Налаштування системи", "System settings")
                iconSource: root.iconUrl("settings-symbolic.svg")
                onClicked: root.openSettings()
            }
            HeaderAction {
                objectName: "control-center-session-lock"
                text: root.services.text("Заблокувати", "Lock")
                iconSource: root.iconUrl("lock-symbolic.svg")
                enabled: root.session.canRequest("lock")
                busy: root.session.pending === "lock"
                onPressed: root.requestAction("lock")
            }
            HeaderAction {
                id: powerButton
                objectName: "control-center-session-menu"
                text: root.services.text("Живлення", "Power")
                iconSource: root.iconUrl("power-settings-new-symbolic.svg")
                checked: powerMenu.opened
                busy: root.powerPending
                Accessible.role: Accessible.ButtonMenu
                onPressed: powerMenu.toggle()
            }
        }
    }

    AttachedPopover {
        id: powerMenu
        objectName: "control-center-power-menu"
        anchorItem: powerButton
        manager: root.services.popups || null
        contentItem: Column {
            width: 208
            spacing: 2
            Repeater {
                model: root.powerActions
                delegate: Button {
                    id: menuAction
                    required property var modelData
                    readonly property bool destructive: modelData.key === "poweroff"
                    readonly property int holdDuration: 900
                    property real holdProgress: 0
                    property bool holdHint: false
                    objectName: "control-center-session-" + modelData.key
                    width: parent.width
                    height: Metrics.controlMedium + 4
                    hoverEnabled: true
                    enabled: root.session.canRequest(modelData.key)
                    text: modelData.label
                    Accessible.name: modelData.label
                    Accessible.description: enabled ? root.services.text("Утримуйте, щоб підтвердити", "Hold to confirm")
                        : root.services.text("Дія недоступна", "Action unavailable")
                    onPressedChanged: {
                        if (pressed) {
                            holdHint = false;
                            drain.stop();
                            fill.duration = Math.max(1, (1 - holdProgress) * holdDuration);
                            fill.start();
                        } else if (holdProgress < 1) {
                            fill.stop();
                            drain.duration = Math.max(1, holdProgress * Motion.longDuration);
                            drain.start();
                            holdHint = true;
                            hintTimer.restart();
                        }
                    }
                    onVisibleChanged: if (!visible) {
                        fill.stop();
                        drain.stop();
                        holdProgress = 0;
                        holdHint = false;
                    }
                    // The fill is the safety delay itself, so it keeps its pace under reduced motion.
                    NumberAnimation {
                        id: fill
                        target: menuAction
                        property: "holdProgress"
                        to: 1
                        easing.type: Easing.InOutQuad
                        onFinished: root.commitAction(menuAction.modelData.key)
                    }
                    NumberAnimation {
                        id: drain
                        target: menuAction
                        property: "holdProgress"
                        to: 0
                        easing.type: Easing.OutCubic
                    }
                    Timer {
                        id: hintTimer
                        interval: 1600
                        onTriggered: menuAction.holdHint = false
                    }
                    background: Rectangle {
                        radius: height / 2
                        color: menuAction.destructive && (menuAction.hovered || menuAction.pressed)
                            ? Qt.alpha(Theme.tokens.error, 0.18)
                            : menuAction.hovered || menuAction.pressed ? Theme.tokens.surfaceOverlay : "transparent"
                        border.width: menuAction.visualFocus ? 1 : 0
                        border.color: Theme.tokens.accent
                        Behavior on color { ColorAnimation { duration: Motion.state } }
                        Rectangle {
                            objectName: "control-center-session-hold-fill"
                            height: parent.height
                            width: height + (parent.width - height) * menuAction.holdProgress
                            radius: height / 2
                            opacity: Math.min(1, menuAction.holdProgress * 6)
                            color: Qt.alpha(menuAction.destructive ? Theme.tokens.error : Theme.tokens.accent, 0.32)
                        }
                    }
                    contentItem: Item {
                        opacity: menuAction.enabled ? 1 : 0.45
                        PentadIcon {
                            id: menuIcon
                            x: 6
                            anchors.verticalCenter: parent.verticalCenter
                            source: root.iconUrl(menuAction.modelData.icon)
                            pixelSize: Metrics.statusIcon
                            color: menuAction.destructive && menuAction.hovered ? Theme.tokens.error : Theme.tokens.text
                            Behavior on color { ColorAnimation { duration: Motion.state } }
                        }
                        Text {
                            anchors.left: menuIcon.right
                            anchors.leftMargin: 12
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            text: menuAction.holdHint ? root.services.text("Затисніть і тримайте", "Press and hold")
                                : menuAction.modelData.label
                            color: menuAction.holdHint ? Theme.tokens.textMuted
                                : menuAction.destructive && menuAction.hovered ? Theme.tokens.error : Theme.tokens.text
                            font.family: Theme.tokens.fontFamily
                            font.pixelSize: Metrics.textBody
                            elide: Text.ElideRight
                            Behavior on color { ColorAnimation { duration: Motion.state } }
                        }
                    }
                }
            }
        }
    }

    Connections {
        target: root.session
        ignoreUnknownSignals: true
        function onActionFinished(action, ok) {
            if (!ok) root.detailsRequested("session");
            else if (action === "lock" && root.services.popups) root.services.popups.close();
        }
    }
}
