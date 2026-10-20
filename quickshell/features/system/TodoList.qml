pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls.Basic
import qs.components
import qs.theme

Item {
    id: root
    required property var organizer
    required property var services
    property string editingId: ""
    property string editingText: ""
    property string pendingEditRequest: ""
    property string pendingAddRequest: ""
    property string error: ""
    implicitHeight: 230
    property alias draftField: draft
    objectName: "organizer-todo-list"

    function addTask() {
        error = "";
        pendingAddRequest = organizer.addTask(organizer.draftText);
    }
    function focusDraft() { draft.forceActiveFocus(); }
    function commitEdit(id) {
        if (!id || pendingEditRequest) return;
        error = "";
        pendingEditRequest = organizer.editTask(id, editingText);
    }
    function handleCommand(requestId, result) {
        if (requestId === pendingAddRequest) {
            pendingAddRequest = "";
            error = result.ok ? "" : result.message || "Could not add task";
        } else if (requestId === pendingEditRequest) {
            pendingEditRequest = "";
            if (result.ok) editingId = "";
            else error = result.message || "Could not update task";
        }
    }

    Connections {
        target: root.organizer
        function onCommandFinished(requestId, result) { root.handleCommand(requestId, result); }
    }
    Connections {
        target: root.organizer
        function onDraftTextChanged() {
            if (draft.text !== root.organizer.draftText) draft.text = root.organizer.draftText;
        }
    }
    Column {
        anchors.fill: parent
        spacing: 8
        Row {
            width: parent.width
            spacing: 8
            PentadTextField {
                id: draft
                width: Math.max(0, parent.width - add.width - 8)
                placeholderText: root.services.text("Додати завдання", "Add a task")
                text: root.organizer.draftText
                onTextEdited: root.organizer.setDraftText(text)
                Keys.onReturnPressed: root.addTask()
                Keys.onEnterPressed: root.addTask()
                Keys.onEscapePressed: if (root.editingId) root.editingId = "";
            }
            PentadButton {
                id: add
                objectName: "todo-add"
                iconSource: Qt.resolvedUrl("../../assets/icons/material/media/add-symbolic.svg")
                iconSize: Metrics.menuActionIcon
                controlHeight: 44
                accessibleName: root.services.text("Додати завдання", "Add task")
                requestedEnabled: root.organizer.initialized && root.organizer.draftText.trim().length > 0 && !root.pendingAddRequest
                pending: !!root.pendingAddRequest
                onPressed: root.addTask()
            }
        }
        PentadText {
            width: parent.width
            visible: !!root.error
            text: root.error
            role: "caption"
            color: Theme.tokens.error
        }
        Flickable {
            objectName: "organizer-task-list"
            width: parent.width
            height: Math.max(0, parent.height - y)
            clip: true
            contentHeight: taskColumn.implicitHeight
            boundsBehavior: Flickable.StopAtBounds
            Column {
                id: taskColumn
                width: parent.width
                spacing: 4
                Repeater {
                    model: root.organizer.orderedTasks
                    delegate: Row {
                        required property var modelData
                        width: taskColumn.width
                        height: 36
                        spacing: 6
                        PentadButton {
                            width: 36; controlHeight: 32
                            objectName: "todo-done"
                            id: doneButton
                            checked: modelData.done
                            contentItem: Item {
                                Rectangle {
                                    anchors.centerIn: parent
                                    width: Metrics.textSection
                                    height: width
                                    radius: height / 2
                                    visible: !doneButton.checked
                                    color: "transparent"
                                    border.width: 2
                                    border.color: doneButton.enabled ? Theme.tokens.textMuted : Theme.tokens.outline
                                }
                                PentadIcon {
                                    anchors.centerIn: parent
                                    visible: doneButton.checked
                                    source: Qt.resolvedUrl("../../assets/icons/material/screenshot/check-symbolic.svg")
                                    pixelSize: Metrics.statusIcon
                                    color: Theme.tokens.accent
                                    Accessible.ignored: true
                                }
                            }
                            accessibleName: root.services.text(modelData.done ? "Позначити невиконаним" : "Позначити виконаним", modelData.done ? "Mark task incomplete" : "Mark task complete")
                            requestedEnabled: root.organizer.initialized
                            onPressed: root.organizer.setDone(modelData.id, !modelData.done)
                        }
                        Item {
                            width: Math.max(0, parent.width - 36 - edit.width - remove.width - 18)
                            height: 36
                            PentadText {
                                anchors.fill: parent
                                visible: root.editingId !== modelData.id
                                text: modelData.text
                                textFormat: Text.PlainText
                                role: "body"
                                color: modelData.done ? Theme.tokens.textMuted : Theme.tokens.text
                                elide: Text.ElideRight
                                verticalAlignment: Text.AlignVCenter
                            }
                            PentadTextField {
                                anchors.fill: parent
                                visible: root.editingId === modelData.id
                                text: root.editingText
                                onTextEdited: root.editingText = text
                                Keys.onReturnPressed: root.commitEdit(modelData.id)
                                Keys.onEnterPressed: root.commitEdit(modelData.id)
                                Keys.onEscapePressed: root.editingId = ""
                                onVisibleChanged: if (visible) Qt.callLater(forceActiveFocus)
                            }
                        }
                        PentadButton {
                            id: edit
                            width: 36; controlHeight: 32
                            objectName: "todo-edit"
                            iconSource: Qt.resolvedUrl("../../assets/icons/material/screenshot/" + (root.editingId === modelData.id ? "check" : "edit") + "-symbolic.svg")
                            accessibleName: root.services.text("Редагувати завдання", "Edit task")
                            pending: !!root.pendingEditRequest && root.editingId === modelData.id
                            onPressed: {
                                if (root.editingId === modelData.id) root.commitEdit(modelData.id);
                                else { root.error = ""; root.editingId = modelData.id; root.editingText = modelData.text; }
                            }
                        }
                        PentadButton {
                            id: remove
                            width: 36; controlHeight: 32
                            objectName: "todo-remove"
                            iconSource: Qt.resolvedUrl("../../assets/icons/material/close-symbolic.svg")
                            accessibleName: root.services.text("Видалити завдання", "Delete task")
                            requestedEnabled: root.organizer.initialized && !root.pendingEditRequest
                            onPressed: root.organizer.removeTask(modelData.id)
                        }
                    }
                }
                PentadText {
                    visible: root.organizer.orderedTasks.length === 0
                    width: taskColumn.width
                    text: root.services.text("Завдань поки немає", "No tasks yet")
                    role: "caption"
                    color: Theme.tokens.textMuted
                    horizontalAlignment: Text.AlignHCenter
                }
            }
        }
    }
}
