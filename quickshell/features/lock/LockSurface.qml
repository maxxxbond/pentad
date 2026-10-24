pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Effects
import qs.components
import qs.theme

// One screen of the lock: the blurred wallpaper, the clock and the card with the password field.
// It shows nothing from the session behind it: no notifications, media or window titles.
Item {
    id: root

    required property var context
    required property var auth
    property string output: ""

    // Emitted once the exit fade has finished after a successful unlock.
    signal finished

    readonly property string wallpaper: context.wallpaperFor(output)
    readonly property string notice: auth.noticeText()
    readonly property bool showNotice: notice !== "" && (auth.busy || auth.draft.length === 0)

    Component.onCompleted: enter.start()

    Connections {
        target: root.auth
        function onUnlocked() {
            leave.start();
        }
    }

    Rectangle {
        anchors.fill: parent
        color: Theme.tokens.surface
    }

    Item {
        id: backdrop
        anchors.fill: parent

        Image {
            id: picture
            anchors.fill: parent
            source: root.wallpaper !== "" ? "file://" + root.wallpaper.split("/").map(encodeURIComponent).join("/") : ""
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            cache: false
            sourceSize: Qt.size(root.width, root.height)
            visible: false
        }

        MultiEffect {
            anchors.fill: parent
            source: picture
            visible: picture.status === Image.Ready
            blurEnabled: true
            blurMax: 64
            blur: 1
        }

        Rectangle {
            anchors.fill: parent
            color: Qt.alpha(Theme.tokens.surface, 0.45)
        }
    }

    // Clock and card scale down together on short screens.
    Item {
        id: stage
        anchors.fill: parent
        scale: Math.min(1, root.height / 900)
        opacity: 0

        LockClock {
            id: clock
            context: root.context
            anchors.horizontalCenter: parent.horizontalCenter
            y: Math.round(parent.height * 0.28 - implicitHeight / 2)
        }

        ContinuousSurface {
            id: card
            width: Metrics.lockCardWidth
            height: content.implicitHeight + 2 * content.inset
            anchors.horizontalCenter: parent.horizontalCenter
            y: clock.y + clock.implicitHeight + Metrics.attachedShoulder + slide.offset
            extent: Metrics.radiusPopover
            fill: Qt.alpha(Theme.tokens.surface, 0.72)
            castsShadow: true

            QtObject {
                id: slide
                property real offset: Metrics.activityPadding * 2
            }

            Column {
                id: content
                readonly property int inset: Metrics.activityPadding * 2
                x: inset
                y: inset
                width: card.width - 2 * inset
                spacing: Metrics.activityPadding

                Item {
                    id: avatar
                    width: Metrics.attachedRadius * 2 + Metrics.activityPadding
                    height: width
                    anchors.horizontalCenter: parent.horizontalCenter

                    Rectangle {
                        id: avatarBase
                        anchors.fill: parent
                        radius: width / 2
                        color: Theme.tokens.surfaceOverlay
                        visible: face.status !== Image.Ready

                        PentadText {
                            anchors.centerIn: parent
                            role: "title"
                            wrapMode: Text.NoWrap
                            textFormat: Text.PlainText
                            color: Theme.tokens.accent
                            text: root.context.userName.length > 0 ? root.context.userName.charAt(0).toUpperCase() : "?"
                        }
                    }

                    Image {
                        id: face
                        anchors.fill: parent
                        source: root.context.hasFace ? "file://" + root.context.facePath.split("/").map(encodeURIComponent).join("/") : ""
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        cache: false
                        visible: false
                        sourceSize: Qt.size(width * 2, height * 2)
                    }

                    MultiEffect {
                        anchors.fill: parent
                        source: face
                        visible: face.status === Image.Ready
                        maskEnabled: true
                        maskSource: faceMask
                    }

                    Rectangle {
                        id: faceMask
                        anchors.fill: parent
                        radius: width / 2
                        layer.enabled: true
                        visible: false
                    }
                }

                PentadText {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    role: "title"
                    wrapMode: Text.NoWrap
                    elide: Text.ElideRight
                    textFormat: Text.PlainText
                    text: root.context.userName
                }

                LockPasswordField {
                    objectName: "lockPasswordField"
                    width: parent.width
                    context: root.context
                    auth: root.auth
                }

                // One line for the PAM question, a notice or Caps Lock; its height never jumps.
                Item {
                    width: parent.width
                    height: Metrics.textBody * 2 + Metrics.capsulePadding

                    PentadText {
                        anchors.fill: parent
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignTop
                        maximumLineCount: 2
                        elide: Text.ElideRight
                        textFormat: Text.PlainText
                        color: root.auth.state.notice === "pam" && !root.auth.state.pamError ? Theme.tokens.textMuted : Theme.tokens.error
                        visible: root.showNotice
                        text: root.notice
                        Accessible.role: Accessible.AlertMessage
                        Accessible.name: text
                    }

                    PentadText {
                        anchors.fill: parent
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignTop
                        textFormat: Text.PlainText
                        color: Theme.tokens.warning
                        visible: !root.showNotice && root.context.capsLock
                        text: root.context.text("Увімкнено Caps Lock", "Caps Lock is on")
                    }
                }

                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: Metrics.attachedShoulder + Metrics.activityPadding
                    visible: root.context.power.suspend || root.context.power.reboot || root.context.power.poweroff

                    LockPowerButton {
                        context: root.context
                        visible: root.context.power.suspend
                        iconSource: Qt.resolvedUrl("../../assets/icons/material/sleep-symbolic.svg")
                        label: root.context.text("Сон", "Sleep")
                        onConfirmed: root.context.runPower("suspend")
                    }
                    LockPowerButton {
                        context: root.context
                        visible: root.context.power.reboot
                        iconSource: Qt.resolvedUrl("../../assets/icons/material/restart-symbolic.svg")
                        label: root.context.text("Перезавантажити", "Restart")
                        onConfirmed: root.context.runPower("reboot")
                    }
                    LockPowerButton {
                        context: root.context
                        visible: root.context.power.poweroff
                        iconSource: Qt.resolvedUrl("../../assets/icons/material/power-symbolic.svg")
                        label: root.context.text("Вимкнути", "Shut down")
                        onConfirmed: root.context.runPower("poweroff")
                    }
                }
            }
        }
    }

    Row {
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: Metrics.attachedShoulder
        spacing: Metrics.statusGap
        visible: root.context.layout !== ""
        opacity: stage.opacity * 0.7

        PentadIcon {
            anchors.verticalCenter: parent.verticalCenter
            source: Qt.resolvedUrl("../../assets/icons/material/keyboard-symbolic.svg")
            pixelSize: Metrics.exposedIcon
            accessibleName: root.context.text("Розкладка клавіатури", "Keyboard layout")
        }
        PentadText {
            anchors.verticalCenter: parent.verticalCenter
            wrapMode: Text.NoWrap
            textFormat: Text.PlainText
            text: root.context.layout
        }
    }

    ParallelAnimation {
        id: enter
        NumberAnimation { target: backdrop; property: "scale"; from: 1; to: 1.06; duration: Motion.long * 4; easing.type: Easing.OutCubic }
        NumberAnimation { target: stage; property: "opacity"; from: 0; to: 1; duration: Motion.long * 2; easing.type: Easing.OutCubic }
        NumberAnimation { target: slide; property: "offset"; to: 0; duration: Motion.long * 2; easing.type: Easing.OutCubic }
    }

    SequentialAnimation {
        id: leave
        NumberAnimation { target: root; property: "opacity"; to: 0; duration: Motion.long; easing.type: Easing.InCubic }
        ScriptAction { script: root.finished() }
    }
}
