pragma ComponentBehavior: Bound
import QtQuick
import qs.components
import qs.theme

Item {
    id: root
    required property var services
    required property var organizer
    property real expandedHeight: 340
    readonly property bool collapsed: organizer.document.collapsed
    readonly property string activeTab: organizer.document.tab
    implicitHeight: collapsed ? 40 : expandedHeight
    objectName: "panel-organizer"

    Behavior on height {
        enabled: !Theme.tokens.reducedMotion
        NumberAnimation { duration: Motion.medium; easing.type: Easing.InOutCubic }
    }
    function errorText() {
        if (organizer.error === "organizer-conflict") return services.text("Документ задач змінився. Повторне збереження перезапише його локальним станом.", "Organizer changed elsewhere. Retry writes your local version.");
        if (organizer.error === "organizer-save-failed") return services.text("Не вдалося зберегти. Ваші зміни залишилися тут.", "Save failed. Your changes are still here.");
        if (organizer.error === "organizer-invalid" || organizer.error === "organizer-read-failed") return services.text("Файл органайзера не прочитано. Його вміст не перезаписано.", "Organizer file is invalid or unreadable. Its contents were preserved.");
        if (organizer.error === "organizer-loading") return services.text("Органайзер завантажується.", "Organizer is still loading.");
        return "";
    }
    onCollapsedChanged: if (collapsed) Qt.callLater(function() { collapseButton.forceActiveFocus(); });

    ContinuousSurface {
        anchors.fill: parent
        fill: Theme.tokens.surfaceRaised
        extent: 20
    }
    Column {
        anchors.fill: parent
        anchors.leftMargin: 12
        anchors.rightMargin: 12
        anchors.topMargin: root.collapsed ? 2 : 12
        anchors.bottomMargin: root.collapsed ? 2 : 12
        spacing: 4
        Row {
            width: parent.width
            height: 36
            spacing: 6
            Item {
                width: Math.max(0, parent.width - collapseButton.width - 6)
                height: parent.height
                visible: !root.collapsed
                PentadSegmented {
                    objectName: "organizer-tabs"
                    width: Math.min(implicitWidth, parent.width)
                    anchors.verticalCenter: parent.verticalCenter
                    tabList: true
                    activateOnPress: true
                    segmentObjectName: "organizer-tab-"
                    accessibleName: root.services.text("Органайзер", "Organizer")
                    options: [
                        { value: "calendar", label: root.services.text("Календар", "Calendar") },
                        { value: "tasks", label: root.services.text("Завдання", "Tasks") }
                    ]
                    value: root.activeTab
                    onActivated: function(tab) { root.organizer.setTab(String(tab)); }
                }
            }
            PentadText {
                visible: root.collapsed
                width: Math.max(0, parent.width - collapseButton.width - 6)
                text: root.services.clock.date.toLocaleDateString(root.services.clock.locale, "ddd d MMMM")
                    + "  ·  " + root.services.text("Завдання: ", "Tasks: ") + root.organizer.incompleteCount
                role: "caption"
                elide: Text.ElideRight
                anchors.verticalCenter: parent.verticalCenter
            }
            PentadButton {
                id: collapseButton
                width: 36
                controlHeight: 34
                objectName: "organizer-collapse"
                chevron: root.collapsed ? "up" : "down"
                accessibleName: root.collapsed ? root.services.text("Розгорнути органайзер", "Expand organizer") : root.services.text("Згорнути органайзер", "Collapse organizer")
                onPressed: root.organizer.setCollapsed(!root.collapsed)
            }
        }
        Row {
            width: parent.width
            height: 30
            spacing: 6
            visible: !root.collapsed && !!root.organizer.error
            PentadText {
                width: Math.max(0, parent.width - retryButton.width - 6)
                text: root.errorText()
                role: "caption"
                color: Theme.tokens.error
                elide: Text.ElideRight
                anchors.verticalCenter: parent.verticalCenter
            }
            PentadButton {
                id: retryButton
                controlHeight: 28
                text: root.organizer.error === "organizer-invalid" || root.organizer.error === "organizer-read-failed"
                    ? root.services.text("Відновити", "Recover") : root.services.text("Повторити", "Retry")
                visible: ["organizer-conflict", "organizer-save-failed", "organizer-invalid", "organizer-read-failed"].includes(root.organizer.error)
                onPressed: {
                    if (root.organizer.error === "organizer-invalid" || root.organizer.error === "organizer-read-failed") root.organizer.recoverInvalidStorage();
                    else root.organizer.retrySave();
                }
            }
        }
        Item {
            id: content
            width: parent.width
            height: Math.max(0, parent.height - y)
            clip: true
            enabled: !root.collapsed && root.organizer.initialized
            visible: !root.collapsed
            PanelCalendar {
                id: calendar
                anchors.fill: parent
                organizer: root.organizer
                services: root.services
                visible: root.activeTab === "calendar"
                enabled: visible && content.enabled
            }
            TodoList {
                id: tasks
                anchors.fill: parent
                organizer: root.organizer
                services: root.services
                visible: root.activeTab === "tasks"
                enabled: visible && content.enabled
            }
            PentadText {
                anchors.centerIn: parent
                visible: !root.organizer.initialized
                text: root.services.text("Завантаження органайзера…", "Loading organizer…")
                role: "caption"
                color: Theme.tokens.textMuted
            }
        }
    }
}
