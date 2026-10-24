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
    spacing: 12

    PentadText {
        width: parent.width
        text: root.actionLabel
        role: "title"
        wrapMode: Text.WordWrap
    }
    PentadText {
        width: parent.width
        visible: !!root.session.state.error
        text: root.errorText(root.session.state.error)
        role: "body"
        color: Theme.tokens.error
        wrapMode: Text.WordWrap
    }

    function errorText(reason) {
        if (reason === "read-only") return services.text("Дії сесії вимкнені в цьому режимі.", "Session actions are disabled in this mode.");
        if (reason === "unavailable" || reason === "session-unavailable")
            return services.text("Ця дія зараз недоступна.", "This action is currently unavailable.");
        if (reason === "timeout") return services.text("Система не відповіла. Спробуйте ще раз.", "The system did not respond. Try again.");
        return services.text("Не вдалося виконати дію. Спробуйте ще раз.", "Could not perform the action. Try again.");
    }
}
