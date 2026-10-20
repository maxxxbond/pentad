pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls.Basic
import Quickshell
import qs.theme
import qs.components
import "../../logic/overview-layout.mjs" as Layout
import "../../logic/overview-presentation.mjs" as Presentation

Item {
    id: root
    required property var services
    required property var navigation
    property string outputId: String(navigation?.outputId || '')
    readonly property var snapshot: navigation?.snapshot || ({ desktop: { outputs: [], workspaces: [] }, clients: [] })
    readonly property var outputs: snapshot?.desktop?.outputs || []
    readonly property var workspaces: snapshot?.desktop?.workspaces || []
    readonly property var clients: snapshot?.clients || []
    readonly property var anchorOutput: outputs.find(o => String(o.id) === outputId) || outputs[0] || null
    readonly property int pageStart: Number(navigation?.pageStart) > 0 ? Number(navigation.pageStart)
        : Layout.overviewPage(Number(anchorOutput?.activeWorkspaceId)).start
    readonly property var pageIds: Layout.overviewPage(pageStart).ids
    readonly property var workspaceIds: Presentation.overviewWorkspaceIds(pageIds, workspaces, clients)
    readonly property var pinnedClients: clients.filter(c => c.pinned)
    readonly property string sceneWorkspaceId: String(navigation.selectedWindow?.workspaceId
        || navigation.selectedWorkspaceId || anchorOutput?.activeWorkspaceId || pageIds[0])
    readonly property var sceneWorkspace: workspaceFor(sceneWorkspaceId)
    readonly property var sceneClients: clientsFor(sceneWorkspaceId)
    readonly property var sceneGame: Presentation.workspaceGame(sceneWorkspace, sceneClients)
    // Each card takes the shape of what it shows: its monitor's work area, or the game window.
    readonly property var cardAreas: workspaceIds.map(id => contentAreaFor(workspaceFor(id)))
    readonly property var layout: Layout.overviewGridLayout(width, height, {
        count: workspaceIds.length, pinned: pinnedClients.length > 0,
        aspect: anchorAspect(), aspects: cardAreas.map(area => area.height / area.width)
    })
    readonly property var captureIds: captureCandidates()
    readonly property bool movedHere: navigation.moveState?.kind === 'moved'
        && navigation.selectedWindow?.instanceId === navigation.moveState.ref?.instanceId
    focus: true
    Accessible.name: tr('Огляд вікон', 'Window overview')

    function tr(uk, en) { return services.text(uk, en); }
    function workspaceFor(id) {
        return workspaces.find(w => String(w.id) === String(id)) ||
            { id: String(id), name: String(id), monitor: anchorOutput?.name || '', virtual: true };
    }
    function workspaceLabel(id) {
        const workspace = workspaceFor(id);
        const name = workspace.name && String(workspace.name) !== String(id) ? String(workspace.name) : tr('простір ', 'workspace ') + id;
        return String(workspace.monitor || '') && workspace.monitor !== anchorOutput?.name ? name + ' · ' + workspace.monitor : name;
    }
    function clientsFor(id) { return clients.filter(c => String(c.workspaceId) === String(id) && !c.pinned); }
    function workareaFor(workspace) {
        const output = outputs.find(o => o.name === workspace?.monitor) || anchorOutput;
        if (!output) return { x: 0, y: 0, width: 1920, height: 1080 };
        if (output.workarea && output.workarea.width > 0 && output.workarea.height > 0) return output.workarea;
        const r = output.reserved || {};
        const left = Number(r.left ?? r[0] ?? 0) || 0;
        const top = Number(r.top ?? r[1] ?? 0) || 0;
        const right = Number(r.right ?? r[2] ?? 0) || 0;
        const bottom = Number(r.bottom ?? r[3] ?? 0) || 0;
        return { x: (Number(output.x) || 0) + left, y: (Number(output.y) || 0) + top,
            width: Math.max(1, (Number(output.width) || 1920) - left - right),
            height: Math.max(1, (Number(output.height) || 1080) - top - bottom) };
    }
    function anchorAspect() {
        const area = workareaFor(null);
        return area.width > 0 && area.height > 0 ? area.height / area.width : 9 / 16;
    }
    // A game workspace is shown at the game window's own shape, so a 4:3 or windowed game fills its card.
    function contentAreaFor(workspace) {
        const area = workareaFor(workspace);
        const game = Presentation.workspaceGame(workspace, clientsFor(workspace?.id));
        const client = game && game.instanceId ? clients.find(c => c.instanceId === game.instanceId) : null;
        if (client && client.width > 0 && client.height > 0 && [client.x, client.y].every(Number.isFinite))
            return { x: client.x, y: client.y, width: client.width, height: client.height };
        return area;
    }
    function captureCandidates() {
        return Presentation.overviewCaptureIds(clients, sceneWorkspaceId, workspaceIds,
            navigation.selectedWindow?.instanceId, navigation.dragToken?.ref?.instanceId);
    }
    function browseWorkspace(id) {
        if (navigation.dragToken) return;
        if (navigation.pickerOpen && navigation.selectedWindow) navigation.moveSelected(id);
        else navigation.selectWorkspace(id);
    }
    function browseRelative(direction) {
        const current = workspaceIds.indexOf(sceneWorkspaceId);
        const next = Math.max(0, Math.min(workspaceIds.length - 1, current + direction));
        if (workspaceIds[next]) browseWorkspace(workspaceIds[next]);
    }
    function selectRelative(direction) {
        if (navigation.dragToken) return;
        const matches = sceneClients;
        if (!matches.length) return;
        const current = matches.findIndex(c => c.instanceId === navigation.selectedWindow?.instanceId);
        const start = current < 0 ? (direction < 0 ? 0 : -1) : current;
        const match = matches[(start + direction + matches.length) % matches.length];
        navigation.selectWindow({ address: match.address, instanceId: match.instanceId });
    }
    function activateSelection() {
        if (navigation.dragToken) return;
        if (navigation.selectedWindow || navigation.selectedWorkspaceId) {
            navigation.activateSelected();
            return;
        }
        const match = sceneClients[0];
        if (match) {
            navigation.selectWindow({ address: match.address, instanceId: match.instanceId });
            navigation.activateSelected();
        } else navigation.activateWorkspace(sceneWorkspaceId);
    }
    function matchesQuery(client) {
        const query = String(navigation.query || '').toLocaleLowerCase();
        return !!query && (String(client.title || '') + ' ' + String(client.appId || client.appClass || ''))
            .toLocaleLowerCase().includes(query);
    }
    Connections {
        target: root.navigation
        function onQueryChanged() {
            if (!root.navigation.query || root.navigation.dragToken) return;
            for (const id of root.workspaceIds) {
                const match = root.clientsFor(id).find(root.matchesQuery);
                if (match) {
                    root.navigation.selectWindow({ address: match.address, instanceId: match.instanceId });
                    return;
                }
            }
        }
        function onSelectedWindowChanged() {
            if (root.navigation.dragToken) return;
            const id = Number(root.navigation.selectedWindow?.workspaceId);
            if (Number.isSafeInteger(id) && id > 0) root.navigation.pageStart = Layout.overviewPage(id).start;
        }
        function onPageStartChanged() {
            if (root.navigation.dragToken || root.navigation.pickerOpen) return;
            const ids = Layout.overviewPage(root.navigation.pageStart).ids;
            const selected = String(root.navigation.selectedWindow?.workspaceId
                || root.navigation.selectedWorkspaceId || root.anchorOutput?.activeWorkspaceId || ids[0]);
            if (!ids.includes(selected)) root.navigation.selectWorkspace(ids[0]);
        }
    }
    Keys.onPressed: event => {
        if (event.key === Qt.Key_PageUp || event.key === Qt.Key_PageDown) {
            navigation.changePage(event.key === Qt.Key_PageUp ? -1 : 1); event.accepted = true;
        } else if (event.key === Qt.Key_Escape) {
            navigation.dismissTop(); event.accepted = true;
        } else if ((event.modifiers & Qt.ControlModifier) && (event.key === Qt.Key_Left || event.key === Qt.Key_Right)) {
            browseRelative(event.key === Qt.Key_Left ? -1 : 1); event.accepted = true;
        } else if ([Qt.Key_Up, Qt.Key_Left, Qt.Key_Down, Qt.Key_Right].includes(event.key)) {
            selectRelative(event.key === Qt.Key_Up || event.key === Qt.Key_Left ? -1 : 1); event.accepted = true;
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            activateSelection(); event.accepted = true;
        } else if (event.key === Qt.Key_M && navigation.selectedWindow) {
            navigation.openMovePicker(); event.accepted = true;

        }
    }

    OverviewCaptures {
        id: captures
        services: root.services; clients: root.clients; captureIds: root.captureIds
    }
    Item {
        id: sceneHeader
        x: root.layout.x; y: root.layout.y - root.layout.pinnedHeight - height
        width: root.layout.width; height: root.layout.headerHeight
        PentadIcon {
            visible: !!root.sceneGame
            x: 0; anchors.verticalCenter: parent.verticalCenter; pixelSize: 20
            source: Qt.resolvedUrl('../../assets/icons/spotlight/game.svg')
            color: Theme.tokens.text
        }
        PentadText {
            x: root.sceneGame ? 30 : 0
            anchors.verticalCenter: parent.verticalCenter
            width: Math.max(0, pager.x - x - 12)
            text: root.sceneGame ? root.sceneGame.title : root.sceneWorkspace.name && String(root.sceneWorkspace.name) !== root.sceneWorkspaceId
                ? String(root.sceneWorkspace.name) : root.tr('Простір ', 'Workspace ') + root.sceneWorkspaceId
            textFormat: Text.PlainText; font.pixelSize: 18; font.weight: Font.Medium
            wrapMode: Text.NoWrap; elide: Text.ElideRight
        }
        Row {
            id: pager
            x: parent.width - width
            anchors.verticalCenter: parent.verticalCenter
            spacing: 8
            Repeater {
                model: [-1, 0, 1]
                delegate: Item {
                    id: pageSlot
                    required property var modelData
                    width: modelData === 0 ? pageLabel.implicitWidth : Metrics.controlMedium
                    height: Metrics.controlMedium
                    PentadText {
                        id: pageLabel
                        visible: pageSlot.modelData === 0
                        anchors.centerIn: parent
                        text: root.pageStart + '–' + (root.pageStart + 9)
                        textFormat: Text.PlainText; font.pixelSize: 13
                        color: Qt.alpha(Theme.tokens.text, 0.55)
                    }
                    ToolButton {
                        id: pageButton
                        visible: pageSlot.modelData !== 0
                        anchors.fill: parent; focusPolicy: Qt.NoFocus
                        enabled: pageSlot.modelData > 0 || root.pageStart > 1
                        Accessible.name: pageSlot.modelData < 0 ? root.tr('Попередні простори', 'Previous workspaces')
                            : root.tr('Наступні простори', 'Next workspaces')
                        onClicked: root.navigation.changePage(pageSlot.modelData)
                        contentItem: Item {
                            PentadChevron {
                                anchors.centerIn: parent
                                direction: pageSlot.modelData < 0 ? 'left' : 'right'
                                engaged: pageButton.hovered || pageButton.down
                                color: Theme.tokens.text
                            }
                        }
                        background: Rectangle {
                            radius: height / 2
                            color: Qt.alpha(Theme.tokens.text, pageButton.down ? 0.18 : pageButton.hovered ? 0.12 : 0.06)
                            opacity: pageButton.enabled ? 1 : 0.4
                            Behavior on color { ColorAnimation { duration: Motion.short } }
                        }
                    }
                }
            }
        }
    }
    ListView {
        id: pinned
        visible: root.pinnedClients.length > 0
        x: root.layout.x; y: sceneHeader.y + sceneHeader.height
        width: root.layout.width; height: root.layout.pinnedHeight
        orientation: ListView.Horizontal; spacing: 8; clip: true
        model: root.pinnedClients
        delegate: ToolButton {
            id: pinnedButton
            required property var modelData
            width: Math.min(220, pinned.width); height: Math.max(0, pinned.height - 8); focusPolicy: Qt.NoFocus
            Accessible.name: root.tr('Закріплено: ', 'Pinned: ') + String(modelData.title || modelData.appClass || '')
            onClicked: {
                root.navigation.selectWindow({address:modelData.address,instanceId:modelData.instanceId});
                root.navigation.activateSelected();
            }
            contentItem: PentadText {
                text: String(pinnedButton.modelData.title || pinnedButton.modelData.appClass || '')
                textFormat: Text.PlainText; role: 'caption'; elide: Text.ElideRight; wrapMode: Text.NoWrap
            }
            background: ContinuousSurface { extent: 8; clipContent: false; fill: Qt.alpha(Theme.tokens.text, pinnedButton.hovered ? 0.1 : 0.05) }
        }
    }
    Item {
        id: grid
        objectName: 'overview-grid'
        x: root.layout.x; y: root.layout.y
        width: root.layout.width; height: root.layout.height
        Repeater {
            model: ScriptModel { values: root.workspaceIds }
            delegate: WorkspaceCard {
                required property var modelData
                required property int index
                cell: true
                query: root.navigation.query
                readonly property var slot: root.layout.cells[index] || ({ x: 0, y: 0, width: 0, height: 0 })
                x: slot.x; y: slot.y
                width: slot.width; height: slot.height
                highlighted: workspaceId === root.sceneWorkspaceId
                workspace: root.workspaceFor(modelData); clients: root.clientsFor(modelData)
                workarea: root.cardAreas[index] || root.contentAreaFor(workspace)
                otherOutput: String(workspace.monitor || '') !== String(root.anchorOutput?.name || '')
                services: root.services; navigation: root.navigation
                dragLayer: dragOverlay; captureIds: root.captureIds; capturePool: captures
            }
        }
    }
    PentadText {
        x: root.layout.x; y: root.layout.y + root.layout.height
        width: root.layout.width; height: root.layout.footerHeight
        verticalAlignment: Text.AlignVCenter; horizontalAlignment: Text.AlignHCenter
        text: root.navigation.error ? String(root.navigation.error)
            : root.navigation.moveState?.kind === 'moving' ? root.tr('Переміщення…', 'Moving…')
            : root.navigation.pickerOpen ? root.tr('Оберіть простір для переміщення', 'Choose a workspace to move to')
            : root.movedHere ? root.tr('Переміщено: ', 'Moved to ') + root.workspaceLabel(root.navigation.moveState.destinationId)
            : root.navigation.selectedWindow ? String(root.navigation.selectedWindow.title || root.navigation.selectedWindow.appClass || '')
            : String(root.sceneWorkspace.monitor || '')
        textFormat: Text.PlainText; elide: Text.ElideRight; wrapMode: Text.NoWrap
        font.pixelSize: 14; color: root.navigation.error ? Theme.tokens.error : Qt.alpha(Theme.tokens.text, 0.55)
    }
    Item { id: dragOverlay; anchors.fill: parent; z: 100 }
}
