pragma ComponentBehavior: Bound
import QtQuick
import qs.components
import qs.theme

Column {
    id: root
    required property var services
    readonly property var session: services.session
    readonly property string action: session.state.action
    readonly property string actionLabel: action === "logout" ? services.text("Вийти із сесії", "Log out")
        : action === "reboot" ? services.text("Перезапустити ПК", "Restart PC")
        : action === "poweroff" ? services.text("Вимкнути ПК", "Power off PC")
        : services.text("Заблокувати", "Lock")
    signal backRequested()
    spacing: 12

    PentadText {
        width: parent.width
        text: root.actionLabel
        role: "title"
        wrapMode: Text.WordWrap
    }
    PentadText {
        width: parent.width
        visible: !!root.session.state.error || !!root.session.confirmation
        text: root.session.state.error ? errorText(root.session.state.error)
            : root.services.text("Незбережені зміни можуть бути втрачені.", "Unsaved changes may be lost.")
        role: "body"
        color: root.session.state.error ? Theme.tokens.error : Theme.tokens.textMuted
        wrapMode: Text.WordWrap
    }
    Row {
        width: parent.width
        spacing: 8
        PentadButton {
            id: cancelButton
            objectName: "control-center-session-cancel"
            text: root.services.text("Скасувати", "Cancel")
            requestedEnabled: !root.session.pending
            background: Rectangle {
                radius: 12
                color: cancelButton.hovered || cancelButton.down ? Theme.tokens.surface : Theme.tokens.surfaceOverlay
                border.width: cancelButton.activeFocus ? 1 : 0
                border.color: Theme.tokens.accent
            }
            onPressed: { root.session.cancel(); root.backRequested(); }
        }
        PentadButton {
            id: confirmButton
            objectName: "control-center-session-confirm"
            visible: !!root.session.confirmation || !!root.session.pending
            text: root.actionLabel
            requestedEnabled: !!root.session.confirmation && !root.session.pending
            pending: !!root.session.pending
            background: Rectangle {
                radius: 12
                color: confirmButton.hovered || confirmButton.down ? Theme.tokens.surface : Theme.tokens.surfaceOverlay
                opacity: confirmButton.enabled ? 1 : 0.55
                border.width: confirmButton.activeFocus ? 1 : 0
                border.color: Theme.tokens.accent
            }
            onPressed: root.session.confirm()
        }
    }

    function errorText(reason) {
        if (reason === "read-only") return services.text("Дії сесії вимкнені в цьому режимі.", "Session actions are disabled in this mode.");
        if (reason === "unavailable" || reason === "session-unavailable")
            return services.text("Ця дія зараз недоступна.", "This action is currently unavailable.");
        if (reason === "timeout") return services.text("Система не відповіла. Спробуйте ще раз.", "The system did not respond. Try again.");
        return services.text("Не вдалося виконати дію. Спробуйте ще раз.", "Could not perform the action. Try again.");
    }
}
