pragma ComponentBehavior: Bound
import QtQuick
import qs.theme
import "../overview" as Overview

Item {
    id: root
    required property var services
    required property var navigation
    readonly property var session: navigation?.session || null
    readonly property var candidates: session?.candidates || []
    readonly property int selectedIndex: candidates.findIndex(c => c.instanceId === navigation?.selectedWindow?.instanceId
        || c.instanceId === session?.selectedInstanceId)
    readonly property real cardWidth: Math.min(192, Math.max(128, width - 16))
    readonly property bool multipleOutputs: (navigation?.snapshot?.desktop?.outputs || []).length > 1
    implicitWidth: 608
    implicitHeight: 218
    width: parent ? parent.width : implicitWidth
    height: parent ? parent.height : implicitHeight
    Accessible.name: navigation?.mode === 'application' ? tr('Вікна застосунку', 'Application windows')
        : tr('Вікна', 'Windows')

    function tr(uk, en) { return services?.config?.documents?.interface?.language === 'uk' ? uk : en; }
    function refFor(client) { return { address: client.address, instanceId: client.instanceId }; }
    function cardInViewport(index) {
        const left = index * (cardWidth + 8);
        return left + cardWidth > strip.contentX && left < strip.contentX + strip.width;
    }
    function ensureSelectedVisible() {
        if (selectedIndex < 0) return;
        const left = selectedIndex * (cardWidth + 8);
        const right = left + cardWidth;
        if (left < strip.contentX) strip.contentX = left;
        else if (right > strip.contentX + strip.width) strip.contentX = right - strip.width;
    }
    function activate(client) {
        navigation.selectWindow(refFor(client));
        if (typeof navigation.activateSelected === 'function') navigation.activateSelected();
        else navigation.commit();
    }
    onSelectedIndexChanged: Qt.callLater(ensureSelectedVisible)
    onCandidatesChanged: Qt.callLater(ensureSelectedVisible)
    onWidthChanged: Qt.callLater(ensureSelectedVisible)

    Rectangle {
        id: panel
        objectName: 'window-switcher-panel'
        width: Math.min(root.width, root.candidates.length * root.cardWidth
            + Math.max(0, root.candidates.length - 1) * 8 + 16)
        height: root.implicitHeight
        anchors.centerIn: parent
        radius: 16
        color: Theme.tokens.surface
        MouseArea { anchors.fill: parent; onClicked: {} }
        Item {
            anchors.fill: parent; anchors.margins: 8
            Row {
                id: heading
                width: parent.width; height: 24
                Text {
                    width: parent.width - counter.width
                    height: parent.height
                    verticalAlignment: Text.AlignVCenter
                    text: root.navigation.mode === 'application'
                        ? String(root.session?.anchorApp || root.candidates[0]?.appClass || root.candidates[0]?.appId || root.tr('Застосунок', 'Application'))
                        : root.tr('Вікна', 'Windows')
                    color: Theme.tokens.text
                    font.family: Theme.tokens.fontFamily; font.pixelSize: 16
                    elide: Text.ElideRight
                }
                Text {
                    id: counter
                    width: 64; height: parent.height
                    horizontalAlignment: Text.AlignRight
                    verticalAlignment: Text.AlignVCenter
                    text: root.candidates.length ? (root.selectedIndex + 1) + ' / ' + root.candidates.length : '0 / 0'
                    color: Theme.tokens.textMuted
                    font.family: Theme.tokens.fontFamily; font.pixelSize: 12
                }
            }
            Flickable {
                id: strip
                x: 0; y: 32
                width: parent.width; height: 170
                contentWidth: Math.max(width, root.candidates.length * (root.cardWidth + 8) - 8)
                contentHeight: height
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                Row {
                    spacing: 8
                    Repeater {
                        model: root.candidates
                        delegate: Rectangle {
                            id: card
                            objectName: 'window-switcher-card-' + index
                            required property var modelData
                            required property int index
                            readonly property bool selected: index === root.selectedIndex
                            width: root.cardWidth; height: 164; radius: 8
                            color: selected ? Theme.tokens.surfaceOverlay : Theme.tokens.surfaceRaised
                            Accessible.name: String(modelData.title || modelData.appClass || '')
                            Accessible.role: Accessible.Button
                            Rectangle {
                                visible: card.selected
                                x: 3; y: 8; width: 2; height: 16; radius: 1
                                color: Theme.tokens.accent
                            }
                            Overview.WindowPreview {
                                id: preview
                                x: 8; y: 8; width: parent.width - 16; height: 112
                                client: card.modelData
                                showFallbackTitle: false
                                captureEnabled: root.navigation.revealed && root.cardInViewport(card.index)
                                    && !(root.services?.preview || root.services?.safeMode)
                                source: captureEnabled && root.services?.hyprland
                                    ? root.services.hyprland.captureSourceFor(root.refFor(card.modelData)) : null
                            }
                            Text {
                                // Title and meta sit solid, centred in the former 124–160 band.
                                x: 8; y: 129; width: parent.width - 16
                                text: String(card.modelData.title || card.modelData.appClass || '')
                                color: Theme.tokens.text
                                font.family: Theme.tokens.fontFamily; font.pixelSize: 14
                                lineHeightMode: Text.FixedHeight; lineHeight: font.pixelSize
                                elide: Text.ElideRight
                            }
                            Row {
                                x: 8; y: 143; width: parent.width - 16; height: 12; spacing: 4
                                Rectangle {
                                    visible: card.modelData.address === root.navigation.snapshot?.activeAddress
                                    width: visible ? 4 : 0; height: 4; radius: 2
                                    anchors.verticalCenter: parent.verticalCenter
                                    color: Theme.tokens.textMuted
                                }
                                Text {
                                    width: parent.width - 8; height: parent.height
                                    text: String(card.modelData.appId || card.modelData.appClass || '')
                                        + ' · ' + String(card.modelData.workspaceId || '')
                                        + (root.multipleOutputs && card.modelData.monitorId
                                            ? ' · ' + card.modelData.monitorId : '')
                                    color: Theme.tokens.textMuted
                                    font.family: Theme.tokens.fontFamily; font.pixelSize: 12
                                    lineHeightMode: Text.FixedHeight; lineHeight: font.pixelSize
                                    elide: Text.ElideRight
                                }
                            }
                            MouseArea { anchors.fill: parent; onClicked: root.activate(card.modelData) }
                        }
                    }
                }
            }
        }
    }
}
