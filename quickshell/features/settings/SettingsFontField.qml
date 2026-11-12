pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls.Basic
import qs.components
import qs.theme

// Picks one of the installed font families. The button previews the current family;
// the popover lists every family in its own face with a filter on top.
// A Control, so the focus edge follows visualFocus (keyboard only).
Control {
    id: root
    property string value: ""
    property string accessibleName: ""
    property string searchPlaceholder: "Filter fonts"
    property string emptyText: "No font matches"
    signal committed(string family)

    readonly property var families: Qt.fontFamilies().filter(function(name) {
        return typeof name === "string" && name !== "" && name[0] !== ".";
    }).sort(function(a, b) { return a.localeCompare(b); })
    property string filter: ""
    readonly property var shown: {
        const needle = filter.trim().toLowerCase();
        if (needle === "") return families;
        return families.filter(function(name) { return name.toLowerCase().indexOf(needle) >= 0; });
    }
    readonly property bool open: picker.visible
    readonly property alias popup: picker

    implicitWidth: 200
    implicitHeight: Metrics.controlMedium
    activeFocusOnTab: true
    Accessible.name: accessibleName
    Accessible.role: Accessible.ComboBox
    Accessible.description: value

    function choose(family) {
        if (family !== value) committed(family);
        picker.close();
        root.forceActiveFocus();
    }
    function toggle() { if (picker.visible) picker.close(); else picker.openFor(root); }

    Keys.onPressed: function(event) {
        if (event.key === Qt.Key_Space || event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Down) {
            toggle();
            event.accepted = true;
        }
    }

    // Drawn like PentadComboBox: a borderless capsule on the row card's next elevation step,
    // with the chevron in a round well concentric with the trailing end. The only edge is the
    // keyboard focus ring.
    Rectangle {
        id: face
        anchors.fill: parent
        radius: Metrics.radiusPill
        color: root.open || tap.pressed || hover.hovered ? Qt.tint(Theme.tokens.surfaceOverlay, Qt.alpha(Theme.tokens.text, Metrics.stateHover)) : Theme.tokens.surfaceOverlay
        border.width: root.visualFocus ? 1 : 0
        border.color: Theme.tokens.accent
        opacity: root.enabled ? 1 : 0.55
        Behavior on color { enabled: !Theme.tokens.reducedMotion; ColorAnimation { duration: Motion.short } }
    }
    PentadText {
        objectName: "fontCurrent"
        anchors.left: parent.left
        anchors.right: chevron.left
        anchors.leftMargin: 16
        anchors.rightMargin: 8
        anchors.verticalCenter: parent.verticalCenter
        text: root.value
        textFormat: Text.PlainText
        font.family: root.value !== "" ? root.value : Theme.tokens.fontFamily
        color: root.enabled ? Theme.tokens.text : Theme.tokens.textMuted
        elide: Text.ElideRight
        wrapMode: Text.NoWrap
    }
    Rectangle {
        id: chevron
        readonly property bool engaged: hover.hovered || root.visualFocus || root.open
        anchors.right: parent.right
        anchors.rightMargin: 4
        anchors.verticalCenter: parent.verticalCenter
        width: root.height - 8
        height: width
        radius: Metrics.radiusPill
        color: Qt.alpha(Theme.tokens.text, engaged ? 0.12 : 0.06)
        opacity: root.enabled ? 1 : 0.55
        PentadChevron {
            anchors.centerIn: parent
            direction: root.open ? "up" : "down"
            pixelSize: Metrics.chevronIcon
            color: chevron.engaged ? Theme.tokens.text : Theme.tokens.textMuted
            engaged: chevron.engaged
        }
    }
    HoverHandler { id: hover; enabled: root.enabled; cursorShape: Qt.PointingHandCursor }
    TapHandler {
        id: tap
        enabled: root.enabled
        onTapped: { root.forceActiveFocus(); root.toggle(); }
    }

    PentadPopup {
        id: picker
        objectName: "fontPicker"
        padding: 8
        margins: 8
        implicitWidth: Math.max(root.width, 280)
        onOpened: { root.filter = ""; filterField.text = ""; filterField.forceActiveFocus(); list.positionViewAtIndex(Math.max(0, root.shown.indexOf(root.value)), ListView.Center); }
        onClosed: root.filter = ""
        contentItem: Column {
            spacing: 8
            PentadTextField {
                id: filterField
                width: parent.width
                implicitHeight: Metrics.controlSmall + 4
                fill: Theme.tokens.surfaceOverlay
                leftPadding: 32
                placeholderText: root.searchPlaceholder
                accessibleName: root.searchPlaceholder
                onTextEdited: { root.filter = text; list.currentIndex = root.shown.length > 0 ? 0 : -1; }
                Keys.onDownPressed: { list.currentIndex = Math.max(0, list.currentIndex); list.forceActiveFocus(); }
                Keys.onReturnPressed: if (root.shown.length > 0) root.choose(root.shown[Math.max(0, list.currentIndex)])
                Keys.onEnterPressed: if (root.shown.length > 0) root.choose(root.shown[Math.max(0, list.currentIndex)])
                PentadIcon {
                    x: 10
                    anchors.verticalCenter: parent.verticalCenter
                    source: Qt.resolvedUrl("../../assets/icons/material/media/search-symbolic.svg")
                    pixelSize: Metrics.panelIcon
                    color: Theme.tokens.textMuted
                }
            }
            ListView {
                id: list
                objectName: "fontList"
                width: parent.width
                height: Math.min(288, Math.max(Metrics.controlMedium, root.shown.length * Metrics.controlMedium))
                clip: true
                model: root.shown
                currentIndex: Math.max(0, root.shown.indexOf(root.value))
                keyNavigationEnabled: true
                boundsBehavior: Flickable.StopAtBounds
                Keys.onReturnPressed: if (currentIndex >= 0) root.choose(root.shown[currentIndex])
                Keys.onEnterPressed: if (currentIndex >= 0) root.choose(root.shown[currentIndex])
                ScrollBar.vertical: ScrollBar {
                    policy: ScrollBar.AsNeeded
                    implicitWidth: 6
                    contentItem: Rectangle { radius: Metrics.radiusTag; color: Qt.alpha(Theme.tokens.text, 0.24) }
                }
                delegate: Item {
                    id: entry
                    required property int index
                    required property string modelData
                    readonly property bool current: modelData === root.value
                    readonly property bool highlighted: list.currentIndex === index
                    width: list.width
                    height: Metrics.controlMedium
                    Accessible.role: Accessible.ListItem
                    Accessible.name: modelData
                    Accessible.selected: current
                    ContinuousSurface {
                        anchors.fill: parent
                        fill: entry.highlighted || entryHover.hovered ? Theme.tokens.surfaceOverlay : "transparent"
                        extent: Metrics.radiusSmall
                    }
                    PentadText {
                        anchors.left: parent.left
                        anchors.right: mark.left
                        anchors.leftMargin: 12
                        anchors.rightMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        text: entry.modelData
                        textFormat: Text.PlainText
                        font.family: entry.modelData
                        font.weight: entry.current ? Font.Medium : Font.Normal
                        color: Theme.tokens.text
                        elide: Text.ElideRight
                        wrapMode: Text.NoWrap
                    }
                    PentadIcon {
                        id: mark
                        anchors.right: parent.right
                        anchors.rightMargin: 12
                        anchors.verticalCenter: parent.verticalCenter
                        visible: entry.current
                        source: Qt.resolvedUrl("../../assets/icons/material/controls/check-symbolic.svg")
                        pixelSize: Metrics.panelIcon
                        color: Theme.tokens.accent
                        Accessible.ignored: true
                    }
                    HoverHandler { id: entryHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: root.choose(entry.modelData) }
                }
                PentadText {
                    visible: root.shown.length === 0
                    anchors.centerIn: parent
                    text: root.emptyText
                    textFormat: Text.PlainText
                    role: "caption"
                    color: Theme.tokens.textMuted
                }
            }
        }
    }
}
