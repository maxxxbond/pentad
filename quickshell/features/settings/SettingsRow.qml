import QtQuick
import qs.components
import qs.theme

// One setting: a label (with optional icon, help and pending dot) and its control. Inside a
// SettingsSection the row lies flat on the section card and draws a thin inset separator above
// itself; on its own it draws its own card. Nothing is outlined except an error.
Item {
    id: root
    property string label: ""
    property string helpText: ""
    property string infoAccessibleName: "About this setting"
    property string reviewAccessibleName: "Reset to default"
    property string iconSource: ""
    property bool pending: false
    property bool error: false
    property string errorText: ""
    property bool requestedEnabled: true
    // True when the value differs from its default; shows the amber marker.
    property bool modified: false
    // Bare rows draw no card, separator, marker or padding: the control is the whole row
    // (used by full-width editors such as the widget catalog).
    property bool bare: false
    signal resetRequested()
    default property alias content: controlHost.data
    // Inline rows (label left, control right) stay at the 40 px minimum; stacked rows breathe more.
    readonly property real padding: bare ? 0 : stacked ? 12 : 4
    readonly property real sidePadding: bare ? 0 : 16
    // Extra room on the leading edge so the modified marker never overlaps text.
    readonly property real leadingPadding: bare ? 0 : 24
    readonly property real labelGap: 8
    readonly property real stackBreakpoint: 420
    // Wide controls (cards, lists, the section picker) always get the full row width below the label.
    property bool wideControl: false
    readonly property bool stacked: wideControl || width < stackBreakpoint
    readonly property bool hasLabelRow: label !== "" || helpText !== "" || pending
    readonly property real controlColumnWidth: Math.max(160, Math.min(280, Math.round(innerWidth * 0.45)))
    readonly property real innerWidth: Math.max(0, width - leadingPadding - sidePadding)
    readonly property bool mirrored: LayoutMirroring.enabled
    // Rows inside a SettingsSection are flattened onto the section card.
    readonly property bool embedded: !!parent && parent.objectName === "settings-section-fields"
    readonly property bool firstInSection: embedded && parent.children.length > 0 && parent.children[0] === root
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
        anchors.margins: 4
        fill: Qt.alpha(Theme.tokens.error, 0.06)
        edge: root.errorEdge
        extent: Math.max(Metrics.radiusTag, Metrics.radiusCard - 4)
    }
    Item {
        id: marker
        objectName: "settings-row-modified"
        visible: root.modified && !root.bare
        x: root.mirrored ? parent.width - width - 4 : 4
        anchors.verticalCenter: parent.verticalCenter
        width: 16
        height: 16
        Accessible.name: root.reviewAccessibleName
        Accessible.role: Accessible.Button
        Accessible.onPressAction: root.resetRequested()
        Rectangle {
            anchors.centerIn: parent
            width: 6
            height: 6
            radius: Metrics.radiusTag
            color: Theme.tokens.warning
            Rectangle {
                anchors.centerIn: parent
                width: 12
                height: 12
                radius: Metrics.radiusTag
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
        x: root.leadingPadding
        // Centered inside the row so a short control sits on the row's axis.
        y: root.bare ? 0 : Math.max(root.padding, Math.round((root.height - implicitHeight) / 2))
        width: root.innerWidth
        readonly property real labelHeight: root.hasLabelRow ? labelRow.implicitHeight : 0
        implicitHeight: root.stacked
            ? (root.hasLabelRow ? labelHeight + root.labelGap : 0) + controlHostFrame.implicitHeight
                + (errorLabel.visible ? 8 + errorLabel.implicitHeight : 0)
            : Math.max(labelHeight, controlHostFrame.implicitHeight) + (errorLabel.visible ? 8 + errorLabel.implicitHeight : 0)
        height: implicitHeight

        Row {
            id: labelRow
            visible: root.hasLabelRow
            x: root.mirrored && !root.stacked ? body.width - width : 0
            y: root.stacked ? 0 : Math.max(0, (Math.max(implicitHeight, controlHostFrame.implicitHeight) - implicitHeight) / 2)
            width: root.stacked ? body.width : Math.max(0, body.width - root.controlColumnWidth - 16)
            spacing: 8
            layoutDirection: root.mirrored ? Qt.RightToLeft : Qt.LeftToRight
            PentadIcon {
                id: leadingIcon
                visible: root.iconSource !== ""
                source: root.iconSource
                pixelSize: Metrics.panelIcon
                color: Theme.tokens.textMuted
                anchors.verticalCenter: parent.verticalCenter
            }
            PentadText {
                id: labelText
                objectName: "settings-row-label"
                width: Math.max(0, labelRow.width - reserved)
                readonly property real reserved: (leadingIcon.visible ? leadingIcon.width + labelRow.spacing : 0)
                    + (info.visible ? info.width + labelRow.spacing : 0)
                    + (pendingDot.visible ? pendingDot.width + labelRow.spacing : 0)
                text: root.label
                textFormat: Text.PlainText
                elide: Text.ElideRight
                wrapMode: Text.NoWrap
                font.weight: Font.Medium
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
            x: root.stacked ? 0 : (root.mirrored ? 0 : body.width - width)
            y: root.stacked ? (root.hasLabelRow ? body.labelHeight + root.labelGap : 0)
                : Math.max(0, (Math.max(body.labelHeight, implicitHeight) - implicitHeight) / 2)
            width: root.stacked ? body.width : root.controlColumnWidth
            implicitHeight: controlHost.implicitHeight
            height: implicitHeight
            Column {
                id: controlHost
                objectName: "settings-row-control"
                width: parent.width
                spacing: 8
                enabled: root.requestedEnabled && !root.pending
                opacity: root.requestedEnabled ? 1 : 0.55
            }
        }
        PentadText {
            id: errorLabel
            objectName: "settings-row-error"
            x: 0
            y: root.stacked ? (root.hasLabelRow ? body.labelHeight + root.labelGap : 0) + controlHostFrame.implicitHeight + 8
                : Math.max(body.labelHeight, controlHostFrame.implicitHeight) + 8
            width: parent.width
            visible: root.error && root.errorText !== ""
            text: root.errorText
            textFormat: Text.PlainText
            role: "caption"
            color: Theme.tokens.error
        }
    }
}
