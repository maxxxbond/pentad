pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Dialogs
import qs.components
import qs.plugins
import qs.theme
import '../../logic/sidebar.mjs' as Sidebar
import '../../logic/tool-catalog.mjs' as ToolLogic
import '../../logic/drag-drop.mjs' as DropLogic
import '../../logic/file-tools.mjs' as Files

Item {
    id: root
    required property var services
    required property string outputId
    readonly property var placements: Sidebar.sidebarPlacements(root.services.config.documents.layout.widgets, root.services.plugins.catalog)
    readonly property var activePlacement: root.placements.find(item => item.moduleId === root.toolState.selectedTool) || null
    readonly property var activeInstanceId: root.activePlacement ? root.activePlacement.instanceId : 'sidebar-tool-' + root.toolState.selectedTool
    readonly property var visiblePlacements: root.placements.filter(item => item.moduleId !== root.toolState.selectedTool)
    readonly property var toolState: root.services.toolWorkspace
    readonly property var toolEntries: { root.services.plugins.revision; return ToolLogic.toolEntries(root.services.plugins.catalog); }
    readonly property string pendingTypes: root.toolState.pendingInput
        ? (root.toolState.pendingInput.value || []).map(item => item.name || item.mimeType || item.kind).join(', ')
        : ''
    readonly property var visibleTools: {
        let entries = ToolLogic.searchTools(root.toolEntries, root.toolState.searchQuery,
            { favorites: root.toolState.favorites, recent: root.toolState.recent,
              view: root.toolState.catalogView, category: root.toolState.catalogCategory });
        if (root.toolState.pendingInput && !root.toolState.pendingInput.targetId)
            entries = entries.filter(entry => root.toolState.pendingInput.compatibleIds.indexOf(entry.manifest.id) >= 0);
        return entries;
    }
    property string ingressError: ''
    property string fileReadRequestId: ''
    property string fileReadTargetId: ''
    property var fileReadOtherItems: []
    property var dragHover: ({ compatibleIds: [], mime: '' })
    property string dragSignature: ''
    // Where the last drop was released, in drawer coordinates: a refusal is explained right there.
    property point noticePoint: Qt.point(width / 2, 64)
    property bool droppedInput: false
    // A drop was released on the drawer and handled, taken or refused.
    signal dropHandled()
    readonly property bool dragOutActive: toolState.exports > 0
    readonly property var toolIds: toolEntries.map(entry => entry.manifest.id)
    width: 390
    implicitWidth: width
    implicitHeight: 760
    height: implicitHeight

    Rectangle { anchors.fill: parent; color: Theme.tokens.surface }
    // Catches drags anywhere in the drawer and switches it into drag mode: the catalog marks what
    // takes the input where it stands, and an open tool turns into one drop zone (DropActions).
    DropArea {
        id: entry
        objectName: 'sidebar-drag-mode-entry'
        anchors.fill: parent
        onEntered: function(drag) { root.offer(drag, root.generalAccepts(root.enterDrag(drag))); }
        onExited: root.leaveDrag()
        onDropped: function(drop) { root.dropOnTile(drop, null, entry); }
    }

    function tr(uk, en) { return typeof root.services.text === 'function' ? root.services.text(uk, en) : en; }
    function offer(drag, accepted) {
        drag.accepted = accepted;
        if (accepted) drag.accept(Qt.CopyAction);
    }

    function routeItems(items, targetId) {
        const compatible = ToolLogic.compatibleTools(root.toolEntries, items).map(entry => entry.manifest.id);
        if (!compatible.length) {
            ingressError = 'No available tool accepts this input.';
            root.toolState.preset = null;
            return false;
        }
        if (targetId && compatible.indexOf(targetId) < 0) {
            ingressError = 'This tool does not accept: ' + items.map(item => item.mimeType || item.kind).join(', ');
            root.toolState.preset = null;
            return false;
        }
        ingressError = '';
        if (targetId) root.toolState.selectTool(targetId, true);
        else root.toolState.selectedTool = '';
        root.toolState.receive(items, compatible, targetId || '');
        if (targetId) inputDelivery.restart();
        return true;
    }
    function dragInfo(drag) {
        const mime = DropLogic.offerMime(drag.formats);
        if (!mime || typeof drag.getDataAsString !== 'function') return { mime: mime, compatibleIds: [], items: [], quick: [] };
        const offer = DropLogic.readOffer(drag);
        if (!offer.ok && offer.reason === 'too-large') return { mime: '', compatibleIds: [], items: [], quick: [] };
        // Nothing to read yet: some sources hand their data over only on release, and the drop decides then.
        if (!offer.ok) return { mime: mime, compatibleIds: [], items: [], quick: [], deferredFileCheck: true };
        if (mime !== 'text/uri-list') {
            const item = ToolLogic.classifyText(offer.value);
            return { mime: mime, items: [item], quick: [],
                compatibleIds: ToolLogic.compatibleTools(root.toolEntries, [item]).map(entry => entry.manifest.id) };
        }
        const parsed = ToolLogic.parseUriList(offer.value);
        if (!parsed.ok) return { mime: '', compatibleIds: [], items: [], quick: [] };
        // File types are guessed from names while hovering; the reader confirms them after release.
        const items = Files.guessItems(parsed.items);
        return { mime: mime, items: items, quick: Files.quickActions(items, root.toolIds),
            compatibleIds: ToolLogic.compatibleTools(root.toolEntries, items).map(entry => entry.manifest.id),
            deferredFileCheck: parsed.items.some(item => item.kind === 'file') };
    }
    // Hover state survives moving between nested drop targets: leaving only clears it after a beat.
    // Every target under the pointer asks on every move, so the state changes only when the offer does.
    function enterDrag(drag) {
        hoverClear.stop();
        const info = dragInfo(drag);
        const signature = [info.mime, info.deferredFileCheck ? 1 : 0, info.compatibleIds.join(','),
            info.items.map(item => (item.uri || item.name || '') + ':' + String(item.value || '').length).join(',')].join('|');
        if (signature !== dragSignature || !dragHover.mime) {
            dragSignature = signature;
            dragHover = info;
        }
        return dragHover;
    }
    function leaveDrag() { hoverClear.restart(); }
    function clearDrag() {
        hoverClear.stop();
        dragSignature = '';
        dragHover = ({ compatibleIds: [], mime: '' });
    }
    Timer { id: hoverClear; interval: 120; onTriggered: root.clearDrag() }
    // Some sources hand their data over only on release. Until then nothing is known about the
    // offer, so nothing is ruled out: every tool takes it and the reader decides after the drop.
    function dragUnknown(info) { return !!info && !!info.mime && !(info.items || []).length; }
    function toolAccepts(id, info) {
        if (!info || !info.mime) return false;
        return dragUnknown(info) || (info.compatibleIds || []).indexOf(id) >= 0;
    }
    // A drop that names no tool: it lands in the catalog, which then lists what can use it.
    function generalAccepts(info) {
        return !!info && !!info.mime && (dragUnknown(info) || !!info.deferredFileCheck || (info.compatibleIds || []).length > 0);
    }
    function tileAccepts(tile, info) {
        if (!tile || !info || !info.mime) return false;
        if (tile.actionId) return (info.quick || []).some(item => item.toolId === tile.toolId && item.actionId === tile.actionId);
        return toolAccepts(tile.toolId, info);
    }
    // A drop on a tile targets its tool and, for quick actions, preselects the action and options.
    // `area` is the DropArea that took it, so a refusal can be explained where it was released.
    function dropOnTile(drop, tile, area) {
        clearDrag();
        if (area && typeof drop.x === 'number' && typeof drop.y === 'number') noticePoint = area.mapToItem(root, drop.x, drop.y);
        root.toolState.preset = tile && tile.actionId ? { toolId: tile.toolId, actionId: tile.actionId, options: tile.options || {} } : null;
        handleDrop(drop, tile ? tile.toolId : '');
    }
    // Pressing a tile opens its tool; with pending input it delivers that input, as a drop would.
    function openTile(tile) {
        const pending = root.toolState.pendingInput;
        const deliver = !!pending && pending.compatibleIds.indexOf(tile.toolId) >= 0;
        root.toolState.preset = tile.actionId ? { toolId: tile.toolId, actionId: tile.actionId, options: tile.options || {} } : null;
        root.toolState.selectTool(tile.toolId, deliver);
        ingressError = '';
        if (deliver) inputDelivery.restart();
    }
    function toolName(id) {
        const entry = root.toolEntries.find(item => item.manifest.id === id);
        return entry ? entry.manifest.name : 'Tool';
    }
    function toolPurpose(manifest) {
        const purposes = {
            'pentad.json': 'Format and validate JSON',
            'pentad.text-cleaner': 'Clean whitespace and line breaks',
            'pentad.units': 'Convert length, mass, time and temperature',
            'pentad.qr': 'Turn text or a link into a QR code',
            'pentad.chat': 'Write, ask and explore with AI',
            'pentad.pdf': 'Compress, merge, split, rotate and protect PDFs',
            'pentad.images': 'Convert, resize, compress and clean photos',
            'pentad.image-text': 'Recognize text and read QR codes in images',
            'pentad.media': 'Compress video, make GIFs, convert and trim audio',
            'pentad.archive': 'Extract archives or pack files into ZIP and 7z',
            'pentad.checksum': 'Hash files and verify downloads',
            'pentad.translate': 'Translate text online',
            'pentad.codec': 'Base64, URL, HTML, hex and JWT',
            'pentad.timestamp': 'Convert Unix time and dates',
            'pentad.color': 'Convert HEX, RGB, HSL and OKLCH',
            'pentad.text-case': 'Change case, make slugs, count words',
            'pentad.yaml': 'Convert between YAML and JSON'
        };
        return purposes[manifest.id] || manifest.tool.category;
    }
    function toolSymbol(id) {
        return ({ 'pentad.json': 'tools/data-object', 'pentad.text-cleaner': 'media/format-align-left',
            'pentad.units': 'tools/straighten', 'pentad.qr': 'tools/qr-code-2', 'pentad.chat': 'tools/chat-bubble',
            'pentad.pdf': 'tools/picture-as-pdf', 'pentad.images': 'tools/image', 'pentad.image-text': 'ocr',
            'pentad.media': 'tools/movie', 'pentad.archive': 'tools/folder-zip', 'pentad.checksum': 'tools/fingerprint',
            'pentad.translate': 'translate', 'pentad.codec': 'tools/code', 'pentad.timestamp': 'tools/schedule',
            'pentad.color': 'tools/palette', 'pentad.text-case': 'tools/match-case', 'pentad.yaml': 'tools/data-array' })[id] || 'tools/extension';
    }
    function loadUris(uris, targetId) {
        const parsed = ToolLogic.parseUriList(uris.join('\n'));
        if (!parsed.ok) { ingressError = 'The selected files could not be read.'; return false; }
        const files = parsed.items.filter(item => item.kind === 'file');
        const other = parsed.items.filter(item => item.kind !== 'file');
        if (!files.length) return routeItems(other, targetId);
        if (!root.services.fileInput) { ingressError = 'Local file reading is unavailable.'; return false; }
        if (fileReadRequestId) root.services.fileInput.cancel(fileReadRequestId);
        const entry = targetId ? root.toolEntries.find(item => item.manifest.id === targetId) : null;
        const limit = entry ? entry.manifest.tool.maxBytes : 262144;
        fileReadTargetId = targetId || '';
        fileReadOtherItems = other;
        fileReadRequestId = root.services.fileInput.readUris(files.map(item => item.uri), limit);
        return !!fileReadRequestId;
    }
    function handleDrop(drop, targetId) {
        // A new attempt: the reason of an earlier refusal no longer stands.
        ingressError = '';
        droppedInput = true;
        const accepted = takeDrop(drop, targetId);
        if (accepted) drop.accept(Qt.CopyAction);
        else drop.accepted = false;
        dropHandled();
    }
    function takeDrop(drop, targetId) {
        const offer = DropLogic.readOffer(drop);
        if (!offer.ok) {
            ingressError = offer.reason === 'too-large' ? 'The dropped input exceeds the size limit.' : 'This data type is not supported.';
            return false;
        }
        if (offer.mime !== 'text/uri-list') return root.routeItems([ToolLogic.classifyText(offer.value)], targetId);
        const parsed = ToolLogic.parseUriList(offer.value);
        if (!parsed.ok) {
            ingressError = parsed.reason === 'empty' ? root.tr('Тут нічого не було.', 'The drop was empty.')
                : 'Only local files and HTTP(S) URLs are supported.';
            return false;
        }
        if (parsed.items.some(item => item.kind === 'file'))
            return root.loadUris(parsed.items.map(item => item.kind === 'file' ? item.uri : item.value), targetId);
        return root.routeItems(parsed.items, targetId);
    }
    // A refused drop says why at the point of release, and keeps the reason in the drawer after that.
    onIngressErrorChanged: {
        if (ingressError && droppedInput) noticeHold.restart();
        else if (!ingressError) noticeHold.stop();
    }
    Timer { id: noticeHold; interval: 4000 }
    readonly property bool noticeShown: noticeHold.running && !!ingressError
    Item {
        x: root.noticePoint.x
        y: root.noticePoint.y
        width: 1; height: 1
        z: 30
        PentadHint {
            objectName: 'sidebar-drop-notice'
            text: root.ingressError
            shown: root.noticeShown
            delay: 0
        }
    }
    function applyIncoming(choice) {
        const pending = root.toolState.pendingInput;
        const id = root.toolState.selectedTool;
        // A quick action works on what was just dropped, not on files already in the tool;
        // files picked with Add join the ones already there.
        if (!choice && root.toolState.preset && root.toolState.preset.toolId === id) choice = 'replace';
        if (!choice && root.toolState.nextChoice) choice = root.toolState.nextChoice;
        root.toolState.nextChoice = '';
        if (!pending || !id || pending.compatibleIds.indexOf(id) < 0) return;
        const entry = root.toolEntries.find(item => item.manifest.id === id);
        if (ToolLogic.inputBytes(pending.value) > entry.manifest.tool.maxBytes) {
            ingressError = 'The combined input exceeds this tool’s limit.';
            return;
        }
        if (!activeTool.view || typeof activeTool.view.acceptInput !== 'function'
            || !activeTool.view.acceptInput(pending.value, choice || '')) {
            ingressError = 'This tool could not read the supplied input; its draft is unchanged.';
            root.toolState.preset = null;
            return;
        }
        root.toolState.clearIngress();
        ingressError = '';
    }

    Connections {
        target: root.services.fileInput || null
        function onCommandFinished(requestId, result) {
            if (requestId !== root.fileReadRequestId) return;
            const targetId = root.fileReadTargetId;
            const otherItems = root.fileReadOtherItems;
            root.fileReadRequestId = '';
            root.fileReadOtherItems = [];
            if (!result.ok) { root.ingressError = result.reason || 'Could not read selected files.'; return; }
            root.routeItems(result.items.concat(otherItems), targetId);
        }
    }
    Timer {
        id: inputDelivery
        interval: 0
        repeat: false
        onTriggered: {
            const pending = root.toolState.pendingInput;
            if (!pending || !root.toolState.selectedTool || pending.compatibleIds.indexOf(root.toolState.selectedTool) < 0) return;
            root.applyIncoming('');
        }
    }

    // The desktop's own chooser when available; Qt's dialog only as a fallback (fixtures, no helper).
    function chooseFiles(targetId, filters, choice) {
        const picker = root.services.filePicker;
        if (!picker) { fileDialog.open(); return; }
        picker.pick({ title: targetId ? 'Choose files for ' + toolName(targetId) : 'Choose files', multiple: true,
            filters: filters || [], targetId: targetId || '', choice: choice || '', outputId: root.outputId });
    }
    function consumePicked() {
        const picked = root.toolState.picked;
        if (!picked) return;
        root.toolState.picked = null;
        root.droppedInput = false;
        root.toolState.nextChoice = picked.targetId ? picked.choice || '' : '';
        if (!picked.targetId) root.toolState.selectedTool = '';
        root.loadUris(picked.uris, picked.targetId);
    }
    Connections {
        target: root.toolState
        function onPickedChanged() { if (root.toolState.picked) Qt.callLater(root.consumePicked); }
    }
    Component.onCompleted: Qt.callLater(root.consumePicked)
    function showCatalog() {
        root.toolState.selectedTool = '';
        root.ingressError = '';
    }
    FileDialog {
        id: fileDialog
        title: 'Choose files for a sidebar tool'
        fileMode: FileDialog.OpenFiles
        onAccepted: {
            const parsed = ToolLogic.parseUriList(Array.from(selectedFiles).map(value => String(value)).join('\n'));
            if (!parsed.ok) { root.ingressError = 'The selected files could not be read.'; return; }
            root.droppedInput = false;
            root.toolState.selectedTool = '';
            root.loadUris(parsed.items.map(item => item.uri || item.value), '');
        }
    }
    ToolCatalog {
        id: catalog
        sidebar: root
        visible: !root.toolState.selectedTool
        anchors { left: parent.left; right: parent.right; top: parent.top; bottom: widgetSection.top; margins: 16; bottomMargin: widgetSection.visible ? 16 : 20 }
    }
    Item {
        id: workspaceHeader
        visible: !!root.toolState.selectedTool
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 16 }
        height: visible ? 34 : 0
        SidebarButton {
            id: backButton
            objectName: 'sidebar-back-to-tools'
            text: ''; width: 34; accessibleName: 'Back to tools'
            background: ContinuousSurface { fill: backButton.down ? Qt.alpha(Theme.tokens.text, 0.12) : backButton.hovered || backButton.visualFocus ? Theme.tokens.surfaceOverlay : 'transparent'; extent: height / 2 }
            PentadIcon { anchors.centerIn: parent; source: Qt.resolvedUrl('../../assets/icons/material/media/arrow-back-symbolic.svg'); pixelSize: Metrics.statusIcon; color: Qt.alpha(Theme.tokens.text, 0.8) }
            onClicked: root.showCatalog()
        }
        Column {
            anchors { left: backButton.right; leftMargin: 8; right: workspaceFavorite.left; rightMargin: 8; verticalCenter: parent.verticalCenter }
            PentadText {
                width: parent.width
                text: root.toolEntries.find(entry => entry.manifest.id === root.toolState.selectedTool)?.manifest.name || 'Tool'
                role: 'section'; solid: true; font.weight: Font.Medium; wrapMode: Text.NoWrap; elide: Text.ElideRight
            }
            PentadText {
                readonly property string execution: root.toolEntries.find(entry => entry.manifest.id === root.toolState.selectedTool)?.manifest.tool.execution || 'local'
                visible: execution !== 'local'
                text: execution === 'ai' ? 'AI' : 'Web'
                role: 'caption'; solid: true; color: Theme.tokens.textMuted
            }
        }
        SidebarButton {
            id: workspaceFavorite
            readonly property bool favorite: root.toolState.favorites.indexOf(root.toolState.selectedTool) >= 0
            anchors.right: parent.right; width: 34
            text: ''
            accessibleName: favorite ? 'Unpin tool' : 'Pin tool'
            background: ContinuousSurface { fill: workspaceFavorite.down ? Qt.alpha(Theme.tokens.text, 0.12) : workspaceFavorite.hovered || workspaceFavorite.visualFocus ? Theme.tokens.surfaceOverlay : 'transparent'; extent: height / 2 }
            PentadIcon {
                anchors.centerIn: parent
                source: Qt.resolvedUrl('../../assets/icons/material/tools/star-symbolic.svg')
                pixelSize: Metrics.panelIcon
                color: workspaceFavorite.favorite ? Theme.tokens.accent : Theme.tokens.text
                opacity: workspaceFavorite.favorite ? 1 : workspaceFavorite.hovered || workspaceFavorite.visualFocus ? 0.8 : 0.35
            }
            onClicked: root.toolState.toggleFavorite(root.toolState.selectedTool)
        }
    }
    PentadScrollView {
        id: mainScroll
        visible: !!root.toolState.selectedTool
        anchors { left: parent.left; right: parent.right; top: workspaceHeader.bottom; bottom: widgetSection.top; margins: 16 }
        contentWidth: availableWidth
        contentHeight: content.implicitHeight
        Column {
            id: content
            width: mainScroll.availableWidth
            spacing: 12
            Item {
                visible: !!root.toolState.selectedTool
                width: parent.width
                implicitHeight: activeContent.implicitHeight
                Column {
                    id: activeContent
                    width: parent.width
                    spacing: 8
                    PluginHost {
                        id: activeTool
                        objectName: 'sidebar-active-tool'
                        width: parent.width
                        height: implicitHeight
                        instanceId: root.activeInstanceId
                        moduleId: root.toolState.selectedTool
                        settings: root.activePlacement ? root.activePlacement.settings : ({})
                        context: ({ slot: 'sidebar-left', outputId: root.outputId, compact: false, preview: root.services.preview })
                        services: root.services
                        registry: root.services.plugins
                        onViewChanged: inputDelivery.restart()
                    }
                    Row {
                        visible: !!root.toolState.pendingInput
                        width: parent.width; spacing: 8
                        SidebarButton { text: 'Replace'; visible: !!root.ingressError; requestedEnabled: !!root.toolState.pendingInput && root.toolState.pendingInput.compatibleIds.indexOf(root.toolState.selectedTool) >= 0; onClicked: root.applyIncoming('replace') }
                        SidebarButton { text: 'Append'; visible: !!root.ingressError && !!activeTool.view && !!activeTool.view.canAppendInput; requestedEnabled: !!root.toolState.pendingInput; onClicked: root.applyIncoming('append') }
                        SidebarButton { text: 'Cancel'; onClicked: root.toolState.clearIngress() }
                    }
                    PentadText {
                        visible: !!root.ingressError || !!root.toolState.ingressMessage
                        width: parent.width
                        text: root.ingressError || root.toolState.ingressMessage
                        role: 'caption'; color: Theme.tokens.error; wrapMode: Text.Wrap
                    }
                }
            }
        }
    }
    Column {
        id: widgetSection
        visible: root.visiblePlacements.length > 0
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom; leftMargin: 16; rightMargin: 16; bottomMargin: visible ? 16 : 0 }
        height: visible ? Math.min(root.height * 0.32, widgetColumn.implicitHeight + 40) : 0
        spacing: 12
        PentadText { text: 'Widgets'; role: 'section' }
        PentadScrollView {
            id: widgetScroll
            width: parent.width
            height: Math.max(0, widgetSection.height - 44)
            contentWidth: availableWidth
            contentHeight: widgetColumn.implicitHeight
            Column {
                id: widgetColumn
                width: widgetScroll.availableWidth
                spacing: 12
                Repeater {
                    model: root.visiblePlacements
                    delegate: PentadCard {
                        required property var modelData
                        objectName: 'sidebar-placement-' + modelData.instanceId
                        // Outer margin narrows the card; inner padding adds to the card's own 12 px inset.
                        x: modelData.frame ? modelData.frame.margin : 0
                        width: widgetColumn.width - 2 * x
                        implicitHeight: widget.implicitHeight + 24 + 2 * framePadding
                        readonly property real framePadding: modelData.frame ? modelData.frame.padding : 0
                        PluginHost {
                            id: widget
                            objectName: 'sidebar-widget-' + modelData.instanceId
                            x: 12 + framePadding; y: 12 + framePadding
                            width: parent.width - 24 - 2 * framePadding
                            height: implicitHeight
                            instanceId: modelData.instanceId
                            moduleId: modelData.moduleId
                            settings: modelData.settings
                            context: ({ slot: 'sidebar-left', outputId: root.outputId, compact: false, preview: root.services.preview,
                                placementZone: modelData.zone, placementSize: modelData.size })
                            services: root.services
                            registry: root.services.plugins
                        }
                    }
                }
            }

        }
    }
    DropActions {
        anchors { left: parent.left; right: parent.right; top: workspaceHeader.bottom; bottom: widgetSection.top; margins: 16 }
        anchors.bottomMargin: widgetSection.visible ? 16 : 20
        z: 20
        visible: !!root.dragHover.mime && !root.fileReadRequestId && !!root.toolState.selectedTool
        sidebar: root
    }
}
