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
    readonly property int agendaRowHeight: 36
    property int cellSize: Math.max(24, Math.min(36, Math.floor((height - 30 - 18 - 1 - 16 - agendaRowHeight
        - (organizer.sourceErrors.length > 0 ? 16 + 4 : 0)) / 6)))
    readonly property date monthDate: OrganizerLogic.parseDayKey(organizer.monthKey + "-01") || new Date()
    readonly property var dates: OrganizerLogic.monthDates(monthDate, organizer.firstDayOfWeek)
    readonly property var marks: OrganizerLogic.eventMarksByDay(organizer.events, dates)
    readonly property date selectedDate: OrganizerLogic.parseDayKey(organizer.selectedDayKey) || new Date()
    readonly property date today: services.clock.date
    readonly property string todayKey: OrganizerLogic.dayKey(today)
    readonly property var dayEvents: OrganizerLogic.eventsForDay(organizer.events, selectedDate)
    function timeText(event) {
        if (event.allDay) return services.text("Увесь день", "All day");
        const start = new Date(event.start), end = new Date(event.end);
        const from = start.toLocaleTimeString(services.clock.locale, "HH:mm");
        return OrganizerLogic.dayKey(start) === OrganizerLogic.dayKey(end)
            ? from + " – " + end.toLocaleTimeString(services.clock.locale, "HH:mm") : from;
    }
    implicitHeight: 330
    function focusSelectedDate() {
        const key = organizer.selectedDayKey;
        for (let i = 0; i < dateRepeater.count; ++i) {
            const item = dateRepeater.itemAt(i);
            if (item && item.key === key) { item.focusTarget.forceActiveFocus(Qt.TabFocusReason); return; }
        }
    }

    Column {
        anchors.fill: parent
        spacing: 4
        Row {
            width: parent.width
            height: 30
            spacing: 4
            PentadText {
                width: Math.max(0, parent.width - 3 * 28 - 3 * 4)
                // Stand-alone form: a heading reads "Жовтень", not the genitive "жовтня" of "MMMM yyyy".
                readonly property string monthName: root.services.clock.locale.standaloneMonthName(root.monthDate.getMonth(), Locale.LongFormat)
                text: monthName.charAt(0).toLocaleUpperCase() + monthName.slice(1) + " " + root.monthDate.getFullYear()
                role: "section"
                font.weight: Font.DemiBold
                wrapMode: Text.NoWrap
                elide: Text.ElideRight
                anchors.verticalCenter: parent.verticalCenter
            }
            PentadButton {
                objectName: "calendar-previous-month"; width: 28; controlHeight: 28; chevron: "left"; accessibleName: root.services.text("Попередній місяць", "Previous month")
                anchors.verticalCenter: parent.verticalCenter
                onPressed: root.organizer.setMonth(new Date(root.monthDate.getFullYear(), root.monthDate.getMonth() - 1, 1))
            }
            PentadButton {
                objectName: "calendar-today"; width: 28; controlHeight: 28; iconSize: Metrics.textSection; iconSource: Qt.resolvedUrl("../../assets/icons/material/radio-button-checked-symbolic.svg"); accessibleName: root.services.text("Сьогодні", "Today")
                anchors.verticalCenter: parent.verticalCenter
                onPressed: root.organizer.setSelectedDay(root.todayKey)
            }
            PentadButton {
                objectName: "calendar-next-month"; width: 28; controlHeight: 28; chevron: "right"; accessibleName: root.services.text("Наступний місяць", "Next month")
                anchors.verticalCenter: parent.verticalCenter
                onPressed: root.organizer.setMonth(new Date(root.monthDate.getFullYear(), root.monthDate.getMonth() + 1, 1))
            }
        }
        Row {
            width: parent.width
            height: 18
            Repeater {
                model: root.dates.slice(0, 7)
                delegate: PentadText {
                    required property var modelData
                    width: parent.width / 7
                    text: modelData.toLocaleDateString(root.services.clock.locale, "ddd")
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
                    readonly property bool isToday: key === root.todayKey
                    readonly property bool currentMonth: modelData.getMonth() === root.monthDate.getMonth()
                    readonly property var dayMarks: root.marks[key] || []
                    readonly property var focusTarget: dayButton
                    Layout.preferredWidth: monthGrid.width / 7
                    Layout.preferredHeight: root.cellSize
                    Button {
                        id: dayButton
                        anchors.centerIn: parent
                        width: Math.min(root.cellSize - 2, monthGrid.width / 7 - 2)
                        height: width
                        padding: 0
                        text: String(dateCell.modelData.getDate())
                        focusPolicy: Qt.TabFocus
                        Accessible.name: dateCell.modelData.toLocaleDateString(root.services.clock.locale, "dddd d MMMM yyyy")
                        // Selection is a neutral tonal circle; the accent only colours today's number.
                        background: Rectangle {
                            radius: width / 2
                            color: dateCell.selected ? Theme.tokens.surfaceOverlay
                                : dayButton.hovered ? Qt.alpha(Theme.tokens.surfaceOverlay, 0.5) : "transparent"
                            border.width: dayButton.visualFocus ? 1 : 0
                            border.color: Theme.tokens.accent
                        }
                        contentItem: Item {
                            Text {
                                anchors.fill: parent
                                anchors.bottomMargin: 4
                                text: dayButton.text
                                color: dateCell.isToday ? Theme.tokens.accent
                                    : dateCell.currentMonth ? Theme.tokens.text : Theme.tokens.textMuted
                                font.family: Theme.tokens.fontFamily
                                font.pixelSize: Metrics.textCaption
                                font.weight: dateCell.isToday || dateCell.selected ? Font.DemiBold : Font.Normal
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }
                            Row {
                                anchors.bottom: parent.bottom
                                anchors.horizontalCenter: parent.horizontalCenter
                                anchors.bottomMargin: root.cellSize >= 28 ? 3 : 2
                                spacing: 2
                                opacity: dateCell.currentMonth ? 1 : 0.5
                                Repeater {
                                    model: dateCell.dayMarks
                                    delegate: Rectangle {
                                        required property var modelData
                                        width: 4
                                        height: 4
                                        radius: 2
                                        color: modelData || Theme.tokens.accent
                                    }
                                }
                            }
                        }
                        onPressed: root.organizer.setSelectedDay(dateCell.key)
                        Keys.onPressed: function(event) {
                            const day = dateCell.modelData;
                            let date = new Date(day.getFullYear(), day.getMonth(), day.getDate());
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
            wrapMode: Text.NoWrap
            elide: Text.ElideRight
        }
        Flickable {
            objectName: "panel-calendar-agenda"
            width: parent.width
            height: Math.max(0, parent.height - y)
            visible: height >= root.agendaRowHeight
            clip: true
            contentHeight: agenda.implicitHeight
            boundsBehavior: Flickable.StopAtBounds
            Column {
                id: agenda
                width: parent.width
                spacing: 4
                Repeater {
                    model: root.dayEvents
                    delegate: ContinuousSurface {
                        id: eventRow
                        required property var modelData
                        readonly property color markColor: modelData.color || Theme.tokens.accent
                        width: agenda.width
                        height: root.agendaRowHeight
                        fill: Theme.tokens.surfaceOverlay
                        extent: height / 2
                        Accessible.role: Accessible.StaticText
                        Accessible.name: modelData.title + ", " + root.timeText(modelData)
                        Rectangle {
                            id: markCircle
                            x: 4
                            anchors.verticalCenter: parent.verticalCenter
                            width: 28
                            height: 28
                            radius: width / 2
                            color: Qt.alpha(eventRow.markColor, 0.18)
                            PentadIcon {
                                anchors.centerIn: parent
                                source: Qt.resolvedUrl("../../assets/icons/material/tools/schedule-symbolic.svg")
                                pixelSize: Metrics.textBody
                                color: eventRow.markColor
                                Accessible.ignored: true
                            }
                        }
                        Column {
                            anchors.left: markCircle.right
                            anchors.leftMargin: 8
                            anchors.right: parent.right
                            anchors.rightMargin: 16
                            anchors.verticalCenter: parent.verticalCenter
                            PentadText {
                                width: parent.width
                                solid: true
                                text: eventRow.modelData.title
                                textFormat: Text.PlainText
                                role: "caption"
                                font.weight: Font.DemiBold
                                wrapMode: Text.NoWrap
                                elide: Text.ElideRight
                            }
                            PentadText {
                                width: parent.width
                                solid: true
                                text: root.timeText(eventRow.modelData)
                                role: "caption"
                                color: Theme.tokens.textMuted
                                wrapMode: Text.NoWrap
                                elide: Text.ElideRight
                            }
                        }
                    }
                }
                PentadText {
                    visible: root.dayEvents.length === 0
                    width: parent.width
                    height: root.agendaRowHeight
                    text: root.services.text("Немає подій", "No events")
                    role: "caption"
                    color: Theme.tokens.textMuted
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
            }
        }
    }
}
