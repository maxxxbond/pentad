pragma ComponentBehavior: Bound
import QtQuick
import qs.components
import qs.theme
import '../../logic/lock-screen.mjs' as LockLogic

// The password field: typed characters show as dots, never as text, unless PAM asks a question
// whose answer it marks visible. The text lives in one TextInput per screen and in auth.draft.
Item {
    id: root

    required property var context
    required property var auth
    readonly property int length: input.text.length
    readonly property bool failed: !auth.busy && auth.state.notice !== "" && (auth.state.notice !== "pam" || auth.state.pamError)
    readonly property bool visibleAnswer: auth.asking && auth.state.promptVisible
    readonly property string placeholder: auth.asking && auth.state.prompt !== "" ? auth.state.prompt
        : context.text("Пароль", "Password")

    implicitWidth: Metrics.lockCardWidth - 2 * Metrics.activityPadding * 2
    implicitHeight: Metrics.controlLarge + Metrics.statusGap

    function submit(): void {
        if (input.text.length > 0 && !root.auth.busy)
            root.auth.submit(input.text);
    }

    Connections {
        target: root.auth
        function onDraftChanged() {
            if (input.text !== root.auth.draft)
                input.text = root.auth.draft;
        }
        function onAttemptsChanged() {
            shake.restart();
        }
    }

    // The highest dot count still on screen, so removed dots can animate out.
    property int shown: 0
    // A ListModel, not an integer: a changing integer model would rebuild every dot on each key.
    ListModel {
        id: dots
    }
    onShownChanged: {
        while (dots.count < shown)
            dots.append({});
        if (dots.count > shown)
            dots.remove(shown, dots.count - shown);
    }
    onLengthChanged: {
        if (length > shown)
            shown = length;
        if (length === 0)
            settle.restart();
        else
            settle.stop();
    }
    Timer {
        id: settle
        interval: Motion.medium
        onTriggered: root.shown = root.length
    }

    readonly property real dotSize: Metrics.statusGap + 2
    readonly property real dotStep: dotSize + Metrics.statusGap

    opacity: auth.busy ? 0.6 : 1
    Behavior on opacity { NumberAnimation { duration: Motion.short } }

    transform: Translate { id: offset }
    SequentialAnimation {
        id: shake
        NumberAnimation { target: offset; property: "x"; to: -Metrics.activityPadding; duration: Motion.press }
        NumberAnimation { target: offset; property: "x"; to: Metrics.activityPadding; duration: Motion.press }
        NumberAnimation { target: offset; property: "x"; to: -Metrics.activityPadding / 2; duration: Motion.press }
        NumberAnimation { target: offset; property: "x"; to: 0; duration: Motion.press }
    }

    ContinuousSurface {
        id: field
        anchors.fill: parent
        extent: Metrics.radiusMedium
        fill: Qt.alpha(Theme.tokens.surfaceRaised, 0.86)
        // Borderless; only an error draws an edge, in the softened status red.
        edge: root.failed ? Qt.alpha(Theme.tokens.error, 0.7) : "transparent"

        TextInput {
            id: input
            // Kept on screen but invisible: an invisible item would lose keyboard focus.
            width: 1
            height: 1
            opacity: 0
            focus: true
            echoMode: root.visibleAnswer ? TextInput.Normal : TextInput.Password
            maximumLength: LockLogic.maxInputLength
            inputMethodHints: Qt.ImhSensitiveData | Qt.ImhNoPredictiveText | Qt.ImhNoAutoUppercase | Qt.ImhHiddenText
            readOnly: root.auth.busy
            selectByMouse: false
            Accessible.role: Accessible.EditableText
            Accessible.passwordEdit: !root.visibleAnswer
            Accessible.name: root.placeholder
            onTextChanged: if (text !== root.auth.draft) root.auth.draft = text
            onAccepted: root.submit()
            // The session clipboard may hold the password (copied from a password manager):
            // nothing is pasted in, and a visible answer is never copied out.
            Keys.onPressed: event => {
                if (event.matches(StandardKey.Paste) || event.matches(StandardKey.Copy) || event.matches(StandardKey.Cut))
                    event.accepted = true;
            }
            Keys.onEscapePressed: {
                if (root.auth.asking)
                    root.auth.cancel();
                else
                    root.auth.draft = "";
            }
            onActiveFocusChanged: if (!activeFocus) forceActiveFocus()
            Component.onCompleted: forceActiveFocus()
        }

        TapHandler {
            onTapped: input.forceActiveFocus()
        }

        Item {
            id: dotArea
            anchors.left: parent.left
            anchors.right: send.left
            anchors.leftMargin: Metrics.activityPadding + Metrics.statusGap
            anchors.rightMargin: Metrics.statusGap
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            clip: true
            visible: !root.visibleAnswer

            // Whole dots that fit; older ones scroll out to the left in whole steps.
            readonly property int capacity: Math.max(1, Math.floor(width / root.dotStep))

            Row {
                anchors.verticalCenter: parent.verticalCenter
                x: -Math.max(0, root.length - dotArea.capacity) * root.dotStep
                Behavior on x { NumberAnimation { duration: Motion.state; easing.type: Easing.OutCubic } }

                Repeater {
                    model: dots

                    Item {
                        id: slot
                        required property int index
                        readonly property bool on: index < root.length
                        // Starts off and follows `on` after creation so a new dot animates in.
                        property bool lit: false
                        Component.onCompleted: lit = Qt.binding(() => slot.on)
                        width: root.dotStep
                        height: root.dotSize

                        Rectangle {
                            width: root.dotSize
                            height: root.dotSize
                            radius: width / 2
                            color: Theme.tokens.text
                            opacity: slot.lit ? 1 : 0
                            scale: slot.lit ? 1 : 0.5
                            Behavior on opacity { NumberAnimation { duration: Motion.state; easing.type: Easing.OutCubic } }
                            Behavior on scale { NumberAnimation { duration: Motion.state; easing.type: Easing.OutCubic } }
                        }
                    }
                }
            }
        }

        PentadText {
            anchors.left: dotArea.left
            anchors.right: dotArea.right
            anchors.verticalCenter: parent.verticalCenter
            visible: root.visibleAnswer && root.length > 0
            role: "section"
            wrapMode: Text.NoWrap
            elide: Text.ElideLeft
            textFormat: Text.PlainText
            text: input.text
        }

        PentadText {
            anchors.left: dotArea.left
            anchors.right: dotArea.right
            anchors.verticalCenter: parent.verticalCenter
            visible: root.length === 0
            role: "section"
            wrapMode: Text.NoWrap
            elide: Text.ElideRight
            textFormat: Text.PlainText
            color: Theme.tokens.textMuted
            text: root.placeholder
        }

        PentadButton {
            id: send
            anchors.right: parent.right
            anchors.rightMargin: Metrics.capsulePadding * 2
            anchors.verticalCenter: parent.verticalCenter
            controlHeight: Metrics.controlMedium
            chevron: "right"
            focusPolicy: Qt.NoFocus
            restFill: Theme.tokens.surfaceOverlay
            requestedEnabled: root.length > 0 && !root.auth.busy
            accessibleName: root.context.text("Розблокувати", "Unlock")
            onClicked: root.submit()
        }
    }
}
