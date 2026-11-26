import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import qs.components
import qs.theme
import "../../logic/settings-shortcut.mjs" as Shortcut

// Keycaps + Record. While recording, a key press is captured; Esc cancels. A modifier is
// required unless the key is F-n or Print, or `requireModifier` is off (editor-local keys).
// `compact` drops the Record button: the keycaps themselves start the recording.
// `clearable` adds a small clear button that commits "" (the action is then disabled).
FocusScope {
    id: root
    property string value: ""
    property string accessibleName: ""
    property string recordLabel: "Record"
    property string cancelLabel: "Cancel"
    property string clearLabel: "Clear"
    property string pressText: "Press keys"
    property string disabledText: "Off"
    property string modifierText: "Add a modifier, like Super or Alt."
    property string invalidText: "That key cannot be bound."
    property string errorText: ""
    property bool recording: false
    property bool requireModifier: true
    property bool compact: false
    property bool clearable: false
    readonly property var parts: Shortcut.shortcutParts(value)
    readonly property bool empty: parts.length === 0
    signal committed(string shortcut)

    // As wide as the keycaps and the buttons need, so the field ends on its row's trailing line.
    implicitWidth: row.implicitWidth
    implicitHeight: Math.max(row.implicitHeight, 0) + (hint.visible ? hint.implicitHeight + Metrics.space2 : 0)
    Accessible.name: accessibleName
    Accessible.role: Accessible.Button

    // Focus returns from the recorder by keyboard, so the ring is shown (TabFocusReason).
    function start() { errorText = ""; recording = true; capture.forceActiveFocus(); }
    function stop() { recording = false; errorText = ""; (compact ? caps : recordButton).forceActiveFocus(Qt.TabFocusReason); }
    function clear() { errorText = ""; recording = false; if (value !== "") committed(""); }
    function handleKey(qtKey, modifiers) {
        if (qtKey === Qt.Key_Escape) { stop(); return true; }
        if (Shortcut.isModifierKey(qtKey)) return true;
        const text = Shortcut.fromQtEvent(qtKey, modifiers);
        if (text === "") return true;
        const reason = Shortcut.shortcutError(text);
        if (reason === "modifier-required" && requireModifier) { errorText = modifierText; return true; }
        if (reason !== "" && reason !== "modifier-required") { errorText = invalidText; return true; }
        recording = false;
        errorText = "";
        if (text !== value) committed(text);
        (compact ? caps : recordButton).forceActiveFocus(Qt.TabFocusReason);
        return true;
    }

    FocusScope {
        id: capture
        objectName: "shortcutCapture"
        anchors.fill: parent
        focus: root.recording
        Keys.onPressed: function(event) {
            if (root.recording) event.accepted = root.handleKey(event.key, event.modifiers);
        }
    }

    RowLayout {
        id: row
        width: parent.width
        spacing: 4
        layoutDirection: LayoutMirroring.enabled ? Qt.RightToLeft : Qt.LeftToRight
        Item { Layout.fillWidth: true; visible: root.compact }
        // A Control hosts the keycaps so a compact field can take keyboard focus (visualFocus).
        Control {
            id: caps
            objectName: "shortcutCaps"
            Layout.fillWidth: !root.compact
            activeFocusOnTab: root.compact
            padding: 0
            implicitWidth: capsRow.implicitWidth
            implicitHeight: capsRow.implicitHeight
            Accessible.role: Accessible.Button
            Accessible.name: (root.recording ? root.cancelLabel : root.recordLabel) + " " + root.accessibleName
            Keys.onPressed: function(event) {
                if (!root.compact || root.recording) return;
                if (event.key === Qt.Key_Space || event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                    root.start();
                    event.accepted = true;
                }
            }
            contentItem: Row {
            id: capsRow
            spacing: 4
            Repeater {
                model: root.recording ? [root.pressText] : root.empty ? [root.disabledText] : root.parts
                delegate: Item {
                    id: cap
                    required property string modelData
                    readonly property bool placeholder: !root.recording && root.empty
                    width: Math.max(Metrics.controlSmall, label.implicitWidth + 16)
                    height: Metrics.controlSmall
                    // Keycaps are tonal plaques; recording breathes and lights the label with the accent.
                    ContinuousSurface {
                        anchors.fill: parent
                        fill: cap.placeholder && !root.recording ? Qt.alpha(Theme.tokens.text, 0.04) : Theme.tokens.surfaceOverlay
                        edge: caps.visualFocus ? Theme.tokens.accent : "transparent"
                        extent: Metrics.radiusSmall
                        SequentialAnimation on opacity {
                            running: root.recording && !Theme.tokens.reducedMotion
                            loops: Animation.Infinite
                            NumberAnimation { to: 0.55; duration: Motion.long; easing.type: Easing.InOutQuad }
                            NumberAnimation { to: 1; duration: Motion.long; easing.type: Easing.InOutQuad }
                        }
                    }
                    PentadText {
                        id: label
                        anchors.centerIn: parent
                        text: cap.modelData
                        textFormat: Text.PlainText
                        role: "caption"
                        font.weight: cap.placeholder ? Font.Normal : Font.Medium
                        color: root.recording ? Theme.tokens.accent : cap.placeholder ? Theme.tokens.textMuted : Theme.tokens.text
                        wrapMode: Text.NoWrap
                    }
                }
            }
            }
            HoverHandler { id: capsHover; enabled: root.compact && root.enabled; cursorShape: Qt.PointingHandCursor }
            TapHandler {
                enabled: root.compact && root.enabled
                onTapped: root.recording ? root.stop() : root.start()
            }
        }
        PentadButton {
            id: clearButton
            objectName: "shortcutClear"
            visible: root.clearable && !root.empty && !root.recording
            iconSource: Qt.resolvedUrl("../../assets/icons/material/close-symbolic.svg")
            iconSize: Metrics.panelIcon
            accessibleName: root.clearLabel + " " + root.accessibleName
            controlHeight: Metrics.controlSmall
            implicitWidth: Metrics.controlSmall
            requestedEnabled: root.enabled
            background: Rectangle {
                radius: height / 2
                color: clearButton.down ? Theme.tokens.surfaceOverlay
                    : clearButton.hovered ? Qt.alpha(Theme.tokens.text, 0.06) : "transparent"
                border.width: clearButton.visualFocus ? 2 : 0
                border.color: Theme.tokens.accent
            }
            onClicked: root.clear()
        }
        PentadButton {
            id: recordButton
            objectName: "shortcutRecord"
            visible: !root.compact
            // The field sits on a card, so the button takes the next elevation step to stay visible.
            restFill: Theme.tokens.surfaceOverlay
            text: root.recording ? root.cancelLabel : root.recordLabel
            accessibleName: (root.recording ? root.cancelLabel : root.recordLabel) + " " + root.accessibleName
            controlHeight: Metrics.controlSmall
            checked: root.recording
            requestedEnabled: root.enabled
            onClicked: root.recording ? root.stop() : root.start()
        }
    }
    PentadText {
        id: hint
        objectName: "shortcutError"
        anchors.top: row.bottom
        anchors.topMargin: Metrics.space2
        width: parent.width
        visible: root.errorText !== ""
        text: root.errorText
        textFormat: Text.PlainText
        role: "caption"
        color: Theme.tokens.error
    }
}
