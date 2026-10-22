pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Dialogs
import qs.components
import qs.theme
import '../../logic/tool-catalog.mjs' as Tools
import '../../logic/file-tools.mjs' as Files

// Shared body of the sidebar file tools: files in, one action with options, results beside the originals.
Item {
    id: root
    required property string instanceId
    required property var context
    required property var settings
    required property var services
    required property string toolId
    required property var accepts
    property var controller: null
    property bool canAppendInput: true
    property var files: []
    property string actionId: ''
    property var options: ({})
    property string jobId: ''
    property var result: null
    property string message: ''
    property var languageCodes: []
    property string readRequestId: ''
    property string languageJob: ''
    readonly property bool running: !!jobId
    readonly property var actions: Files.availableActions(toolId, files)
    readonly property var action: Files.findAction(toolId, actionId)
    readonly property var check: Files.validate(action, files, options)
    readonly property var outputs: result && result.outputs ? result.outputs : []
    readonly property var handoffItems: Files.outputItems(result)
    readonly property var handoffTargets: handoffItems.length
        ? Tools.compatibleTools(Tools.toolEntries(services.plugins.catalog), handoffItems).map(entry => entry.manifest.id) : []
    readonly property var textItem: ({ kind: 'text', mimeType: 'text/plain', value: result && result.text || '', compatibleTypes: ['text/plain'] })
    readonly property var textTargets: result && result.text
        ? Tools.compatibleTools(Tools.toolEntries(services.plugins.catalog), [textItem]).map(entry => entry.manifest.id) : []
    implicitWidth: 330
    implicitHeight: content.implicitHeight

    function acceptInput(items, choice) {
        if (running) { message = 'Wait for the current job or cancel it.'; return false; }
        const merged = Files.mergeFiles(files, items, accepts, choice || '');
        if (!merged.ok) {
            if (merged.reason !== 'choose-replace-or-append') message = merged.reason;
            return false;
        }
        setFiles(merged.files);
        // A drop on a quick-action tile arrives with the action (and options) already chosen.
        const preset = services.toolWorkspace.takePreset ? services.toolWorkspace.takePreset(toolId) : null;
        if (preset) {
            if (actions.some(item => item.id === preset.actionId)) selectAction(preset.actionId);
            for (const key of Object.keys(preset.options || {})) setOption(key, preset.options[key]);
            Qt.callLater(function() { if (runButton.enabled) runButton.forceActiveFocus(Qt.OtherFocusReason); });
        }
        return true;
    }
    function setFiles(next) {
        files = next;
        result = null;
        message = '';
        selectAction(Files.pickAction(toolId, files, actionId));
    }
    function removeFile(uri) { setFiles(files.filter(item => item.uri !== uri)); }
    function selectAction(id) {
        if (id === actionId) { save(); return; }
        actionId = id;
        const defaults = Files.defaultOptions(action);
        const kept = {};
        // Options shared by several actions (format, quality) carry over; passwords never do.
        for (const key of Object.keys(defaults)) kept[key] = Object.prototype.hasOwnProperty.call(options, key) && !/password/.test(key) ? options[key] : defaults[key];
        options = kept;
        result = null;
        save();
    }
    function setOption(id, value) {
        options = Object.assign({}, options, { [id]: value });
        save();
    }
    function choicesFor(option) {
        return option.source === 'ocr-languages' ? Files.languageChoices(languageCodes) : option.choices;
    }
    function start() {
        if (!check.ok) { message = check.reason; return; }
        const request = Files.requestFor(action, files, options);
        message = '';
        result = null;
        jobId = services.fileTools.run(request.operation, request.inputs, request.options, undefined, request.timeoutMs);
        save();
    }
    function cancel() { if (jobId) services.fileTools.cancel(jobId); }
    // The desktop chooser hides the drawer and delivers through the sidebar; Qt's dialog is the fallback.
    function chooseFiles() {
        if (services.filePicker && context && context.outputId) {
            services.filePicker.pick({ title: 'Choose files', multiple: true, filters: Files.dialogFilters[toolId] || [],
                targetId: toolId, choice: files.length ? 'append' : '', outputId: context.outputId });
        } else picker.open();
    }
    readonly property bool picking: !!services.filePicker && services.filePicker.busy
    function finishJob(value) {
        jobId = '';
        if (value.ok) { result = value; message = ''; }
        else { result = null; message = value.cancelled ? value.reason : value.reason || 'The action failed.'; }
        save();
    }
    function save() {
        const stored = {};
        for (const option of (action && action.options) || []) if (option.type !== 'password') stored[option.id] = options[option.id];
        services.toolWorkspace.setDraft(toolId, { files: files, actionId: actionId, options: stored, jobId: jobId, result: result, message: message });
    }
    function restore() {
        const draft = services.toolWorkspace.draftFor(toolId);
        if (draft && typeof draft === 'object') {
            files = draft.files || [];
            actionId = draft.actionId || '';
            options = Object.assign(Files.defaultOptions(Files.findAction(toolId, actionId)), draft.options || {});
            result = draft.result || null;
            message = draft.message || '';
            const finished = draft.jobId ? services.fileTools.finished[draft.jobId] : null;
            if (finished) { jobId = draft.jobId; finishJob(finished); }
            else if (draft.jobId && services.fileTools.requests[draft.jobId]) jobId = draft.jobId;
        }
        if (!actionId) selectAction(Files.pickAction(toolId, files, ''));
        if (Files.actionsFor(toolId).some(item => (item.options || []).some(option => option.source === 'ocr-languages')))
            languageJob = services.fileTools.run('ocr.languages', [], {}, undefined, 15000);
    }
    Component.onCompleted: restore()

    Connections {
        target: root.services.fileTools
        function onJobFinished(requestId, value) {
            if (requestId === root.languageJob) {
                root.languageJob = '';
                root.languageCodes = value.ok ? value.languages || [] : [];
                if (root.languageCodes.length && root.options.language !== undefined && root.languageCodes.indexOf(root.options.language) < 0)
                    root.setOption('language', root.languageCodes[0]);
            } else if (requestId === root.jobId) root.finishJob(value);
        }
    }
    Connections {
        target: root.services.fileInput || null
        function onCommandFinished(requestId, value) {
            if (requestId !== root.readRequestId) return;
            root.readRequestId = '';
            if (!value.ok) { root.message = value.reason || 'Could not read the selected files.'; return; }
            root.acceptInput(value.items, root.files.length ? 'append' : '');
        }
    }
    FileDialog {
        id: picker
        title: 'Choose files'
        fileMode: FileDialog.OpenFiles
        nameFilters: Files.dialogFilters[root.toolId] || ['All files (*)']
        onAccepted: {
            const uris = Array.from(selectedFiles).map(value => String(value)).filter(uri => uri.startsWith('file://'));
            if (uris.length && root.services.fileInput) root.readRequestId = root.services.fileInput.readUris(uris, 262144);
        }
    }

    component Caption: PentadText { role: 'caption'; color: Theme.tokens.textMuted; wrapMode: Text.NoWrap; elide: Text.ElideRight }
    component IconButton: PentadButton {
        property string symbol: ''
        controlHeight: Metrics.controlSmall
        width: Metrics.controlSmall
        iconSource: Qt.resolvedUrl('../../assets/icons/material/' + symbol + '-symbolic.svg')
        iconSize: Metrics.panelIcon
    }
    component FileRow: Item {
        id: fileRow
        required property var entry
        property bool draggable: false
        default property alias trailingItems: trailing.data
        width: parent ? parent.width : 0
        height: 40
        FileThumb {
            id: thumb
            x: 4; width: 32; height: 32
            anchors.verticalCenter: parent.verticalCenter
            services: root.services
            uri: fileRow.entry.uri
            mimeType: fileRow.entry.mimeType || ''
            kind: fileRow.entry.kind || 'file'
            iconSize: Metrics.panelIcon
        }
        FileDragSource {
            enabled: fileRow.draggable
            anchors { left: parent.left; top: parent.top; bottom: parent.bottom; right: size.left }
            services: root.services
            uris: [fileRow.entry.uri]
            visual: thumb
            onActivated: Qt.openUrlExternally(fileRow.entry.uri)
        }
        PentadText {
            anchors { left: thumb.right; leftMargin: 12; right: size.left; rightMargin: 8; verticalCenter: parent.verticalCenter }
            text: fileRow.entry.name; wrapMode: Text.NoWrap; elide: Text.ElideMiddle
            color: Qt.alpha(Theme.tokens.text, 0.8)
        }
        Caption {
            id: size
            anchors { right: trailing.left; rightMargin: 8; verticalCenter: parent.verticalCenter }
            text: fileRow.entry.kind === 'folder' ? 'Folder · ' + Files.formatBytes(fileRow.entry.sizeBytes) : Files.formatBytes(fileRow.entry.sizeBytes)
            font.features: ({ tnum: 1 })
        }
        Row {
            id: trailing
            anchors { right: parent.right; rightMargin: 4; verticalCenter: parent.verticalCenter }
            spacing: 4
        }
    }

    Column {
        id: content
        width: root.width
        spacing: 12

        // Files
        Item {
            objectName: root.toolId + '-empty'
            visible: !root.files.length
            width: parent.width; height: 72
            ContinuousSurface { anchors.fill: parent; fill: Theme.tokens.surfaceRaised; extent: Metrics.radiusMedium }
            PentadIcon {
                x: 16; anchors.verticalCenter: parent.verticalCenter
                source: Qt.resolvedUrl('../../assets/icons/material/tools/input-symbolic.svg')
                pixelSize: Metrics.statusIcon; color: Theme.tokens.textMuted
            }
            PentadText {
                anchors { left: parent.left; leftMargin: 48; right: choose.left; rightMargin: 8; verticalCenter: parent.verticalCenter }
                text: 'Drop files here'; color: Qt.alpha(Theme.tokens.text, 0.8); wrapMode: Text.NoWrap; elide: Text.ElideRight
            }
            PentadButton {
                id: choose
                objectName: root.toolId + '-choose'
                anchors { right: parent.right; rightMargin: 16; verticalCenter: parent.verticalCenter }
                text: 'Choose'; pending: !!root.readRequestId || root.picking
                onClicked: root.chooseFiles()
            }
        }
        Column {
            visible: root.files.length > 0
            width: parent.width
            spacing: 0
            Repeater {
                model: root.files.slice(0, 6)
                delegate: FileRow {
                    id: inputRow
                    required property var modelData
                    entry: modelData
                    IconButton {
                        symbol: 'media/close'
                        accessibleName: 'Remove ' + inputRow.entry.name
                        requestedEnabled: !root.running
                        background: ContinuousSurface { fill: parent.hovered || parent.visualFocus ? Theme.tokens.surfaceOverlay : 'transparent'; extent: height / 2 }
                        onClicked: root.removeFile(inputRow.entry.uri)
                    }
                }
            }
            Item {
                width: parent.width; height: Metrics.controlMedium
                Caption {
                    anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter }
                    text: (root.files.length > 6 ? '+' + (root.files.length - 6) + ' more · ' : '')
                        + root.files.length + (root.files.length === 1 ? ' file · ' : ' files · ')
                        + Files.formatBytes(root.files.reduce((sum, item) => sum + Math.max(0, item.sizeBytes), 0))
                    font.features: ({ tnum: 1 })
                }
                Row {
                    anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                    spacing: 4
                    PentadButton { text: 'Add'; controlHeight: Metrics.controlSmall; requestedEnabled: !root.running; pending: !!root.readRequestId || root.picking; onClicked: root.chooseFiles() }
                    PentadButton { objectName: root.toolId + '-clear'; text: 'Clear'; controlHeight: Metrics.controlSmall; requestedEnabled: !root.running; onClicked: root.setFiles([]) }
                }
            }
        }

        // Action and its options
        Flow {
            objectName: root.toolId + '-actions'
            visible: root.actions.length > 1
            width: parent.width
            spacing: 8
            Repeater {
                model: root.actions
                delegate: PentadButton {
                    required property var modelData
                    objectName: root.toolId + '-action-' + modelData.id
                    text: modelData.label
                    checkable: true
                    checked: modelData.id === root.actionId
                    requestedEnabled: !root.running
                    onClicked: root.selectAction(modelData.id)
                }
            }
        }
        Repeater {
            model: root.action ? root.action.options || [] : []
            delegate: Column {
                id: optionBlock
                required property var modelData
                width: content.width
                spacing: 4
                Caption { text: optionBlock.modelData.label }
                Flow {
                    visible: optionBlock.modelData.type === 'choice'
                    width: parent.width
                    spacing: 8
                    Repeater {
                        model: optionBlock.modelData.type === 'choice' ? root.choicesFor(optionBlock.modelData) : []
                        delegate: PentadButton {
                            required property var modelData
                            objectName: root.toolId + '-option-' + optionBlock.modelData.id + '-' + modelData.id
                            text: modelData.text
                            controlHeight: Metrics.controlSmall
                            checkable: true
                            checked: root.options[optionBlock.modelData.id] === modelData.id
                            requestedEnabled: !root.running
                            onClicked: root.setOption(optionBlock.modelData.id, modelData.id)
                        }
                    }
                }
                Caption {
                    visible: optionBlock.modelData.source === 'ocr-languages' && !root.languageCodes.length && !root.languageJob
                    text: 'No OCR languages are installed'
                    color: Theme.tokens.error
                }
                PentadTextField {
                    visible: optionBlock.modelData.type !== 'choice'
                    objectName: root.toolId + '-option-' + optionBlock.modelData.id
                    width: parent.width
                    placeholderText: optionBlock.modelData.placeholder || ''
                    echoMode: optionBlock.modelData.type === 'password' ? TextInput.Password : TextInput.Normal
                    enabled: !root.running
                    text: root.options[optionBlock.modelData.id] || ''
                    onTextEdited: root.setOption(optionBlock.modelData.id, text)
                    Keys.onReturnPressed: root.start()
                    Keys.onEnterPressed: root.start()
                }
            }
        }

        // Run
        Row {
            spacing: 8
            PentadButton {
                id: runButton
                objectName: root.toolId + '-run'
                text: root.running ? 'Cancel' : Files.runLabel(root.action, root.files.length)
                requestedEnabled: root.running || root.check.ok
                onClicked: root.running ? root.cancel() : root.start()
                Keys.onReturnPressed: clicked()
                Keys.onEnterPressed: clicked()
                contentItem: Row {
                    spacing: 8
                    PentadIcon {
                        anchors.verticalCenter: parent.verticalCenter
                        source: Qt.resolvedUrl('../../assets/icons/material/' + (root.running ? 'media/close' : 'media/play-arrow') + '-symbolic.svg')
                        pixelSize: Metrics.panelIcon
                        color: runButton.enabled && !root.running ? Theme.tokens.accent : Theme.tokens.textMuted
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: runButton.text
                        color: !runButton.enabled ? Theme.tokens.textMuted : root.running ? Theme.tokens.text : Theme.tokens.accent
                        font.family: Theme.tokens.fontFamily; font.pixelSize: Metrics.textBody; font.weight: Font.Medium
                    }
                }
            }
            BusyIndicator {
                anchors.verticalCenter: parent.verticalCenter
                width: 24; height: 24
                running: root.running
                visible: running
                Accessible.name: 'Working'
            }
        }

        // Result
        Item {
            id: resultCard
            objectName: root.toolId + '-result'
            visible: root.outputs.length > 0 || !!(root.result && root.result.summary && !root.result.text)
            width: parent.width
            implicitHeight: resultColumn.implicitHeight + 16
            readonly property bool sizeChange: !!root.result && root.result.inputBytes > 0 && root.result.outputBytes > 0
                && root.result.outputBytes < root.result.inputBytes && /^(pdf\.compress|image\.compress|image\.resize|image\.convert|media\.video|image\.strip)$/.test(root.actionId)
            ContinuousSurface { anchors.fill: parent; fill: Theme.tokens.surfaceRaised; extent: Metrics.radiusCard }
            Column {
                id: resultColumn
                x: 8; y: 8
                width: parent.width - 16
                spacing: 4
                Item {
                    visible: !!(root.result && root.result.summary)
                    width: parent.width; height: 28
                    PentadText {
                        objectName: root.toolId + '-summary'
                        anchors { left: parent.left; leftMargin: 8; right: parent.right; rightMargin: 8; verticalCenter: parent.verticalCenter }
                        text: root.result && root.result.summary || ''
                        role: 'caption'; color: Theme.tokens.textMuted
                        wrapMode: Text.NoWrap; elide: Text.ElideRight
                        font.features: ({ tnum: 1 })
                    }
                }
                // Two separate lanes so before and after stay readable when they are close.
                Column {
                    visible: resultCard.sizeChange
                    x: 8; width: parent.width - 16
                    spacing: 4
                    bottomPadding: 4
                    Rectangle { width: parent.width; height: 4; radius: 2; color: Qt.alpha(Theme.tokens.text, 0.18) }
                    Rectangle {
                        width: root.result && root.result.inputBytes ? Math.max(4, parent.width * root.result.outputBytes / root.result.inputBytes) : 0
                        height: 4; radius: 2; color: Theme.tokens.accent
                        Behavior on width { enabled: !Theme.tokens.reducedMotion; NumberAnimation { duration: Motion.state } }
                    }
                }
                Column {
                    objectName: root.toolId + '-outputs'
                    visible: root.outputs.length > 0
                    width: parent.width
                    spacing: 0
                    Repeater {
                        model: root.outputs.slice(0, 8)
                        delegate: FileRow {
                            id: outputRow
                            required property var modelData
                            entry: modelData
                            draggable: true
                            PentadButton { text: 'Open'; controlHeight: Metrics.controlSmall; onClicked: Qt.openUrlExternally(outputRow.entry.uri) }
                            IconButton {
                                symbol: 'tools/folder-open'; accessibleName: 'Show in folder'
                                onClicked: Qt.openUrlExternally(Files.parentUri(outputRow.entry.uri))
                            }
                        }
                    }
                    Item {
                        visible: root.handoffTargets.length > 0
                        width: parent.width; height: Metrics.controlMedium
                        PentadButton {
                            anchors { right: parent.right; rightMargin: 4; verticalCenter: parent.verticalCenter }
                            text: 'Use in another tool'
                            controlHeight: Metrics.controlSmall
                            onClicked: root.services.toolWorkspace.receive(root.handoffItems, root.handoffTargets, '')
                        }
                    }
                }
            }
        }
        Column {
            visible: !!(root.result && root.result.text)
            width: parent.width
            spacing: 8
            PentadText {
                objectName: root.toolId + '-text-summary'
                visible: !!(root.result && root.result.summary)
                width: parent.width
                text: root.result && root.result.summary || ''
                role: 'caption'
                color: root.result && root.result.match === false ? Theme.tokens.error : root.result && root.result.match ? Theme.tokens.accent : Theme.tokens.textMuted
                wrapMode: Text.Wrap
            }
            PentadScrollView {
                width: parent.width
                height: Math.min(200, Math.max(72, resultText.implicitHeight))
                contentWidth: availableWidth
                TextArea {
                    id: resultText
                    objectName: root.toolId + '-text'
                    readOnly: true; selectByMouse: true; wrapMode: TextEdit.Wrap
                    text: root.result && root.result.text || ''
                    color: Theme.tokens.text
                    font.family: Theme.tokens.fontFamily; font.pixelSize: Metrics.textBody
                    background: Rectangle { color: Theme.tokens.surfaceRaised; radius: Metrics.radiusSmall }
                }
            }
            Row {
                spacing: 8
                PentadButton { text: 'Copy'; onClicked: { resultText.selectAll(); resultText.copy(); resultText.deselect(); } }
                PentadButton {
                    text: 'Use in another tool'
                    visible: root.textTargets.length > 0
                    onClicked: root.services.toolWorkspace.receive([root.textItem], root.textTargets, '')
                }
            }
        }
        PentadText {
            objectName: root.toolId + '-message'
            visible: !!root.message
            width: parent.width
            text: root.message
            role: 'caption'
            color: root.message === 'Cancelled' ? Theme.tokens.textMuted : Theme.tokens.error
            wrapMode: Text.Wrap
        }
    }
}
