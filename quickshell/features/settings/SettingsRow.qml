import QtQuick
import qs.components
import qs.theme

// One setting on the settings grid: a label (with optional help and pending dot) and its control.
// The label starts on the leading line and the control ends on the trailing line; both lines sit
// Metrics.settingsRowInset inside the card, and the gutter that leaves on the leading side belongs
// to the changed marker. A control keeps its own width and hangs from the trailing line, so a
// switch, a segmented control and a field all end in the same place, and a single-line row is
// Metrics.settingsRowMinHeight tall whatever it holds.
// The control drops below the label when the two do not fit side by side, and always for wide
// editors (cards, lists, chips), which are given the whole row width there.
// Inside a SettingsSection the row lies flat on the section card and draws a thin separator above
// itself, from line to line; on its own it draws its own card. Nothing is outlined except an error.
Item {
    id: root
    property string label: ""
    property string helpText: ""
    property string infoAccessibleName: "About this setting"
    property string reviewAccessibleName: "Reset to default"
    property string iconSource: ""
    // Ink of the leading icon; a live thing (a connected device) may light it with the accent.
    property color iconColor: Theme.tokens.textMuted
    property bool pending: false
    property bool error: false
    property string errorText: ""
    property bool requestedEnabled: true
    // True when the value differs from its default; shows the amber marker.
    property bool modified: false
    // Bare rows draw no card, separator, marker or padding: the control is the whole row
    // (used by full-width editors such as the widget catalog). Such editors show their own
    // pending state, so a save neither adds a label row nor disables them (which would drop focus).
    property bool bare: false
    signal resetRequested()
    default property alias content: controlHost.data
    // Wide controls (cards, lists, the section picker) always get the full row width below the label.
    property bool wideControl: false
    // The width the control asks for beside the label; negative takes the content's implicit width.
    // Content without an implicit width (a layout that only fills its parent) has to set it.
    property real controlWidth: -1
    readonly property real sidePadding: bare ? 0 : Metrics.settingsRowInset
    // Single-line rows centre their control in the row height; stacked rows breathe more.
    readonly property real padding: bare ? 0 : stacked ? Metrics.space3 : Metrics.space2
    readonly property real labelGap: Metrics.space2
    // The least air between the label and the control when they share a line.
    readonly property real rowGap: Metrics.space4
    // A control this narrow (a switch, a short value) never leaves the label's line: a label too
    // long for the room elides instead.
    readonly property real compactControl: 3 * Metrics.space6
    readonly property real innerWidth: Math.max(0, width - 2 * sidePadding)
    readonly property real contentWidth: {
        let widest = 0;
        for (let i = 0; i < controlHost.children.length; i++) {
            const child = controlHost.children[i];
            if (child.visible) widest = Math.max(widest, child.implicitWidth);
        }
        return Math.ceil(widest);
    }
    readonly property real controlNatural: Math.min(innerWidth, controlWidth >= 0 ? controlWidth : contentWidth)
    readonly property bool hasControl: controlNatural > 0
    readonly property bool hasLabelRow: label !== "" || helpText !== "" || (pending && !bare)
    readonly property real labelNatural: !hasLabelRow ? 0 : Math.ceil(labelText.implicitWidth)
        + (leadingIcon.visible ? leadingIcon.width + labelRow.spacing : 0)
        + (info.visible ? info.width + labelRow.spacing : 0) + (pendingDot.visible ? pendingDot.width + labelRow.spacing : 0)
    readonly property bool stacked: wideControl
        || (hasLabelRow && controlNatural > compactControl && controlNatural + rowGap + labelNatural > innerWidth)
    readonly property real labelRoom: stacked || !hasControl ? innerWidth : Math.max(0, innerWidth - controlNatural - rowGap)
    readonly property bool mirrored: LayoutMirroring.enabled
    // Rows inside a SettingsSection are flattened onto the section card.
    readonly property bool embedded: !!parent && parent.objectName === "settings-section-fields"
    // In the section's column the first shown row sits at the top. Child order is not used: a
    // Repeater may stack its rows after itself, and hidden rows take no place in the column.
    readonly property bool firstInSection: embedded && y < 1
    readonly property color errorEdge: Qt.alpha(Theme.tokens.error, 0.7)
    implicitHeight: bare ? body.implicitHeight : Math.max(Metrics.settingsRowMinHeight, body.implicitHeight + 2 * padding)
    implicitWidth: 240
    Accessible.name: label
    Accessible.role: Accessible.Grouping
    Accessible.description: pending ? "In progress" : error ? errorText || "Error" : ""

    ContinuousSurface {
        id: card
        objectName: "settings-row-card"
        visible: !root.embedded && !root.bare
        anchors.fill: parent
        fill: Theme.tokens.surfaceRaised
        edge: root.error ? root.errorEdge : "transparent"
        extent: Metrics.radiusCard
        opacity: root.requestedEnabled ? 1 : 0.55
    }
    Rectangle {
        id: separator
        objectName: "settings-row-separator"
        visible: root.embedded && !root.firstInSection && !root.bare
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.leftMargin: root.sidePadding
        anchors.right: parent.right
        anchors.rightMargin: root.sidePadding
        height: 1
        color: Theme.tokens.outline
    }
    // Error on a flattened row: a concentric outline inset into the section card.
    ContinuousSurface {
        id: errorFrame
        objectName: "settings-row-error-frame"
        visible: root.embedded && root.error && !root.bare
        anchors.fill: parent
        anchors.margins: Metrics.space1
        fill: Qt.alpha(Theme.tokens.error, 0.06)
        edge: root.errorEdge
        extent: Math.max(Metrics.radiusTag, Metrics.radiusCard - Metrics.space1)
    }
    Item {
        id: marker
        objectName: "settings-row-modified"
        visible: root.modified && !root.bare
        // Centred in the leading gutter and level with the label: a 16 px target around a 6 px dot,
        // with the same air towards the card edge and towards the label.
        x: Math.round((root.sidePadding - width) / 2) + (root.mirrored ? root.width - root.sidePadding : 0)
        y: Math.round(body.y + (root.hasLabelRow ? labelRow.y + (labelRow.height - height) / 2 : (body.height - height) / 2))
        width: Metrics.space4
        height: Metrics.space4
        Accessible.name: root.reviewAccessibleName
        Accessible.role: Accessible.Button
        Accessible.onPressAction: root.resetRequested()
        Rectangle {
            anchors.centerIn: parent
            width: 6
            height: 6
            radius: width / 2
            color: Theme.tokens.warning
            Rectangle {
                anchors.centerIn: parent
                width: 12
                height: 12
                radius: width / 2
                color: Qt.alpha(Theme.tokens.warning, 0.3)
                visible: markerHover.hovered
                z: -1
            }
        }
        HoverHandler { id: markerHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: root.resetRequested() }
    }
    Item {
        id: body
        x: root.sidePadding
        // Centered inside the row so a short control sits on the row's axis.
        y: root.bare ? 0 : Math.max(root.padding, Math.round((root.height - implicitHeight) / 2))
        width: root.innerWidth
        readonly property real labelHeight: root.hasLabelRow ? labelRow.implicitHeight : 0
        readonly property real controlTop: root.stacked && root.hasLabelRow ? labelHeight + root.labelGap : 0
        readonly property real lineHeight: root.stacked ? controlTop + controlHostFrame.implicitHeight
            : Math.max(labelHeight, controlHostFrame.implicitHeight)
        implicitHeight: lineHeight + (errorLabel.visible ? Metrics.space2 + errorLabel.implicitHeight : 0)
        height: implicitHeight

        Row {
            id: labelRow
            visible: root.hasLabelRow
            x: root.mirrored ? body.width - width : 0
            y: root.stacked ? 0 : Math.max(0, (body.lineHeight - implicitHeight) / 2)
            width: Math.min(root.labelRoom, root.labelNatural)
            spacing: Metrics.space1
            layoutDirection: root.mirrored ? Qt.RightToLeft : Qt.LeftToRight
            PentadIcon {
                id: leadingIcon
                visible: root.iconSource !== ""
                source: root.iconSource
                pixelSize: Metrics.panelIcon
                color: root.iconColor
                anchors.verticalCenter: parent.verticalCenter
            }
            PentadText {
                id: labelText
                objectName: "settings-row-label"
                // The help mark follows the label; only a label too long for its room elides.
                width: Math.max(0, Math.min(implicitWidth, root.labelRoom - reserved))
                readonly property real reserved: (leadingIcon.visible ? leadingIcon.width + labelRow.spacing : 0)
                    + (info.visible ? info.width + labelRow.spacing : 0)
                    + (pendingDot.visible ? pendingDot.width + labelRow.spacing : 0)
                text: root.label
                textFormat: Text.PlainText
                elide: Text.ElideRight
                wrapMode: Text.NoWrap
                anchors.verticalCenter: parent.verticalCenter
            }
            PentadInfoButton {
                id: info
                objectName: "settings-row-info"
                visible: root.helpText !== ""
                helpText: root.helpText
                accessibleName: root.infoAccessibleName
                anchors.verticalCenter: parent.verticalCenter
            }
            Rectangle {
                id: pendingDot
                objectName: "settings-row-pending"
                visible: root.pending
                width: 8
                height: 8
                radius: Metrics.radiusTag
                color: Theme.tokens.accent
                anchors.verticalCenter: parent.verticalCenter
                SequentialAnimation on opacity {
                    running: root.pending && !Theme.tokens.reducedMotion
                    loops: Animation.Infinite
                    NumberAnimation { to: 0.35; duration: Motion.long; easing.type: Easing.InOutQuad }
                    NumberAnimation { to: 1; duration: Motion.long; easing.type: Easing.InOutQuad }
                }
            }
        }
        Item {
            id: controlHostFrame
            // On a shared line the control ends on the trailing line; below the label it starts on
            // the leading one and is given the whole width.
            x: root.stacked ? 0 : (root.mirrored ? 0 : body.width - width)
            y: root.stacked ? body.controlTop : Math.max(0, (body.lineHeight - implicitHeight) / 2)
            // Never zero: an elided text that fills a zero-wide parent reports no implicit width,
            // and the row would then never learn how wide its control wants to be.
            width: root.stacked ? body.width : Math.max(1, root.controlNatural)
            implicitHeight: controlHost.implicitHeight
            height: implicitHeight
            Column {
                id: controlHost
                objectName: "settings-row-control"
                width: parent.width
                spacing: Metrics.space2
                enabled: root.requestedEnabled && (!root.pending || root.bare)
                opacity: root.requestedEnabled ? 1 : 0.55
            }
        }
        PentadText {
            id: errorLabel
            objectName: "settings-row-error"
            x: 0
            y: body.lineHeight + Metrics.space2
            width: parent.width
            visible: root.error && root.errorText !== ""
            text: root.errorText
            textFormat: Text.PlainText
            role: "caption"
            color: Theme.tokens.error
        }
    }
}
