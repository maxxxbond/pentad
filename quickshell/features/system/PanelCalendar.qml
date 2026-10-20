pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import qs.components
import qs.theme
import "../../logic/organizer.mjs" as OrganizerLogic

Item {
    id: root
    objectName: "panel-calendar"
    required property var organizer
    required property var services
    property int cellSize: Math.max(24, Math.min(36, Math.floor((height - 30 - 18 - 1 - 20 - 32
        - (organizer.sourceErrors.length > 0 ? 16 : 0)) / 6)))
    readonly property date monthDate: OrganizerLogic.parseDayKey(organizer.monthKey + "-01") || new Date()
    readonly property var dates: OrganizerLogic.monthDates(monthDate)
    readonly property date selectedDate: OrganizerLogic.parseDayKey(organizer.selectedDayKey) || new Date()
    readonly property date today: services.clock.date
    readonly property var dayEvents: OrganizerLogic.eventsForDay(organizer.events, selectedDate)
    implicitHeight: 330
    function focusSelectedDate() {
        const key = organizer.selectedDayKey;
        for (let i = 0; i < dateRepeater.count; ++i) {
            const item = dateRepeater.itemAt(i);
            if (item && item.key === key) { item.focusTarget.forceActiveFocus(); return; }
        }
    }

    Column {
        anchors.fill: parent
        spacing: 4
        Row {
            width: parent.width
            height: 30
            PentadButton {
                objectName: "calendar-previous-month"; width: 36; controlHeight: 28; chevron: "left"; accessibleName: root.services.text("Попередній місяць", "Previous month")
                onPressed: root.organizer.setMonth(new Date(root.monthDate.getFullYear(), root.monthDate.getMonth() - 1, 1))
            }
            PentadText {
                width: Math.max(0, parent.width - 116)
                text: root.monthDate.toLocaleDateString(root.services.clock.locale, "MMMM yyyy")
                role: "section"
                horizontalAlignment: Text.AlignHCenter
                anchors.verticalCenter: parent.verticalCenter
            }
            PentadButton { objectName: "calendar-next-month"; width: 36; controlHeight: 28; chevron: "right"; accessibleName: root.services.text("Наступний місяць", "Next month"); onPressed: root.organizer.setMonth(new Date(root.monthDate.getFullYear(), root.monthDate.getMonth() + 1, 1)) }
            PentadButton { objectName: "calendar-today"; width: 36; controlHeight: 28; iconSize: Metrics.textSection; iconSource: Qt.resolvedUrl("../../assets/icons/material/radio-button-checked-symbolic.svg"); accessibleName: root.services.text("Сьогодні", "Today"); onPressed: root.organizer.setSelectedDay(OrganizerLogic.dayKey(root.today)) }
        }
        Row {
            width: parent.width
            height: 18
            Repeater {
                model: Array.from({ length: 7 }, function(_, index) {
                    return new Date(2024, 0, 1 + index).toLocaleDateString(root.services.clock.locale, "ddd");
                })
                delegate: PentadText {
                    required property var modelData
                    width: parent.width / 7
                    text: modelData
                    role: "caption"
                    color: Theme.tokens.textMuted
                    horizontalAlignment: Text.AlignHCenter
                }
            }
        }
        GridLayout {
            id: monthGrid
            objectName: "panel-calendar-dates"
            width: parent.width
            height: root.cellSize * 6
            columns: 7
            rowSpacing: 0
            columnSpacing: 0
            Repeater {
                id: dateRepeater
                model: root.dates
                delegate: Item {
                    id: dateCell
                    required property var modelData
                    readonly property string key: OrganizerLogic.dayKey(modelData)
                    readonly property bool selected: key === root.organizer.selectedDayKey
                    readonly property bool isToday: key === OrganizerLogic.dayKey(root.today)
                    readonly property bool currentMonth: modelData.getMonth() === root.monthDate.getMonth()
                    readonly property var focusTarget: dayButton
                    Layout.preferredWidth: monthGrid.width / 7
                    Layout.preferredHeight: root.cellSize
                    Button {
                        id: dayButton
                        anchors.centerIn: parent
                        width: Math.min(root.cellSize - 2, monthGrid.width / 7 - 2)
                        height: width
                        text: String(modelData.getDate())
                        focusPolicy: Qt.TabFocus
                        Accessible.name: modelData.toLocaleDateString(root.services.clock.locale, "dddd d MMMM yyyy")
                        background: Rectangle {
                            radius: width / 2
                            color: dateCell.selected ? Theme.tokens.accent
                                : dateCell.isToday ? Theme.tokens.surfaceOverlay : "transparent"
                            border.width: dayButton.activeFocus ? 1 : 0
                            border.color: Theme.tokens.accent
                        }
                        contentItem: Item {
                            Text {
                                anchors.fill: parent
                                anchors.bottomMargin: root.cellSize >= 22 ? 4 : 0
                                text: dayButton.text
                                color: dateCell.selected ? Theme.tokens.onAccent
                                    : dateCell.currentMonth ? Theme.tokens.text : Theme.tokens.textMuted
                                font.family: Theme.tokens.fontFamily
                                font.pixelSize: Metrics.textCaption
                                font.weight: dateCell.isToday ? Font.DemiBold : Font.Normal
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }
                            Rectangle {
                                anchors.bottom: parent.bottom
                                anchors.horizontalCenter: parent.horizontalCenter
                                anchors.bottomMargin: 2
                                width: 4
                                height: 4
                                radius: 2
                                color: dateCell.selected ? Theme.tokens.onAccent : Theme.tokens.accent
                                visible: dateCell.isToday
                            }
                            Rectangle {
                                anchors.bottom: parent.bottom
                                anchors.horizontalCenter: parent.horizontalCenter
                                anchors.horizontalCenterOffset: 6
                                anchors.bottomMargin: 2
                                width: 4
                                height: 4
                                radius: 2
                                color: dateCell.selected ? Theme.tokens.onAccent : Theme.tokens.accent
                                visible: root.organizer.events.some(function(event) {
                                    return OrganizerLogic.eventsForDay([event], modelData).length > 0;
                                })
                            }
                        }
                        onPressed: root.organizer.setSelectedDay(dateCell.key)
                        Keys.onPressed: function(event) {
                            let date = new Date(modelData.getFullYear(), modelData.getMonth(), modelData.getDate());
                            if (event.key === Qt.Key_Left) date.setDate(date.getDate() - 1);
                            else if (event.key === Qt.Key_Right) date.setDate(date.getDate() + 1);
                            else if (event.key === Qt.Key_Up) date.setDate(date.getDate() - 7);
                            else if (event.key === Qt.Key_Down) date.setDate(date.getDate() + 7);
                            else if (event.key === Qt.Key_Home) date = new Date(root.today.getFullYear(), root.today.getMonth(), root.today.getDate());
                            else if (event.key === Qt.Key_PageUp) date = new Date(date.getFullYear(), date.getMonth() - 1, Math.min(date.getDate(), new Date(date.getFullYear(), date.getMonth(), 0).getDate()));
                            else if (event.key === Qt.Key_PageDown) date = new Date(date.getFullYear(), date.getMonth() + 1, Math.min(date.getDate(), new Date(date.getFullYear(), date.getMonth() + 2, 0).getDate()));
                            else return;
                            event.accepted = true;
                            root.organizer.setSelectedDay(OrganizerLogic.dayKey(date));
                            Qt.callLater(root.focusSelectedDate);
                        }
                    }
                }
            }
        }
        Rectangle { width: parent.width; height: 1; color: Theme.tokens.outline; opacity: 0.5 }
        PentadText {
            width: parent.width
            visible: root.organizer.sourceErrors.length > 0
            text: root.services.text("Не вдалося завантажити деякі календарі", "Some calendars could not be loaded")
            role: "caption"
            color: Theme.tokens.textMuted
        }
        Flickable {
            width: parent.width
            height: Math.max(0, parent.height - y)
            visible: height >= 16
            clip: true
            contentHeight: agenda.implicitHeight
            boundsBehavior: Flickable.StopAtBounds
            Column {
                id: agenda
                width: parent.width
                spacing: 4
                PentadText {
                    width: parent.width
                    text: root.selectedDate.toLocaleDateString(root.services.clock.locale, "dddd d MMMM")
                    role: "caption"
                    color: Theme.tokens.textMuted
                }
                Repeater {
                    model: root.dayEvents
                    delegate: Row {
                        required property var modelData
                        width: agenda.width
                        spacing: 8
                        PentadText {
                            width: 52
                            text: modelData.allDay ? root.services.text("Увесь день", "All day") : new Date(modelData.start).toLocaleTimeString(root.services.clock.locale, "HH:mm")
                            role: "caption"
                            color: Theme.tokens.textMuted
                        }
                            PentadText { width: Math.max(0, parent.width - 60); text: modelData.title; role: "caption"; elide: Text.ElideRight }
                    }
                }
                PentadText { visible: root.dayEvents.length === 0; width: parent.width; text: root.services.text("Немає подій", "No events"); role: "caption"; color: Theme.tokens.textMuted }
            }
        }
    }
}
