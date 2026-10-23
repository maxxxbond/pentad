pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls.Basic
import qs.theme
import qs.components
import "../../logic/screenshot.mjs" as Model
import "../../logic/screenshot-settings.mjs" as Settings
import "../../logic/screenshot-toolbar.mjs" as Dock

Item {
    id: root
    required property var services
    required property var screenshot
    property string outputId: screenshot.outputId
    property var capture: ({
            path: screenshot.imagePath,
            width: screenshot.imageWidth,
            height: screenshot.imageHeight,
            windowRegions: screenshot.windowRegions
        })
    property string mode: 'edit'
    property var initialCrop: null
    property var document: Model.createDocument(Math.max(1, capture.width), Math.max(1, capture.height))
    property string tool: 'select'
    property string color: services.config.documents.screenshots?.color || '#ff5252'
    property real strokeWidth: services.config.documents.screenshots?.strokeWidth || 4
    property real fontSize: services.config.documents.screenshots?.fontSize || 24
    property string localError: ''
    property string statusMessage: ''
    property bool copied: false
    readonly property var selectedAnnotation: document.annotations.find(function (item) {
        return item.id === canvas.selectedId;
    }) || null
    property string lastAction: ''
    property bool lastCloseAfter: false
    property bool confirmDiscard: false
    property string savedState: ''
    property string editingTextId: ''
    property var textPoint: null
    property var toolbarDock: null
    readonly property var toolbarPlacement: Dock.dockGeometry(canvas.cropView, {
            width: width,
            height: height
        }, toolbar.length, toolbar.thickness, toolbarDock || Dock.defaultDock(canvas.cropView, {
            width: width,
            height: height
        }, toolbar.length, toolbar.thickness))
    // Image search: the engine list stays beside the chosen area until Search is pressed.
    readonly property bool searchPanelWanted: mode === 'pick' && screenshot.pickEngines.length > 0
    property bool searchChoosing: false
    property var searchPanelPos: null
    readonly property var searchPanelAuto: Dock.dockGeometry(canvas.cropView, {
            width: width,
            height: height
        }, searchPanel.height, searchPanel.width, Dock.defaultSideDock(canvas.cropView, {
            width: width,
            height: height
        }, searchPanel.height, searchPanel.width))
    readonly property bool dirty: JSON.stringify(Model.exportDocument(document)) !== savedState
    readonly property bool busy: screenshot.busy || screenshot.phase === 'exporting'
    readonly property bool ready: canvas.imageReady
    focus: true

    function resetDocument() {
        document = Model.createDocument(capture.width, capture.height);
        if (initialCrop && initialCrop.width > 0 && initialCrop.height > 0)
            document = Model.setCrop(document, initialCrop);
        canvas.selecting = !initialCrop;
        searchChoosing = false;
        searchPanelPos = null;
        toolbarDock = null;
        canvas.selectedId = '';
        canvas.resetView();
        savedState = JSON.stringify(Model.exportDocument(document));
        localError = '';
        confirmDiscard = false;
        forceActiveFocus();
    }
    function edit(next) {
        document = next;
        localError = '';
        statusMessage = '';
    }
    function style(patch) {
        if (!canvas.selectedId)
            return;
        try {
            edit(Model.updateAnnotation(document, canvas.selectedId, patch));
        } catch (error) {
            localError = String(error);
        }
    }
    function rememberStyle() {
        if (services.preview || services.safeMode)
            return;
        const settings = services.config.documents.screenshots;
        if (settings.color === color && settings.strokeWidth === strokeWidth && settings.fontSize === fontSize)
            return;
        services.config.save('screenshots', Object.assign({}, settings, {
            color: color,
            strokeWidth: strokeWidth,
            fontSize: fontSize
        }));
    }
    function exportAction(action, closeAfter) {
        if (busy || canvas.selecting)
            return;
        if (textInput.visible && !commitText())
            return;
        lastAction = action;
        lastCloseAfter = closeAfter;
        localError = '';
        statusMessage = '';
        copied = false;
        if (!screenshot.exportImage(Model.exportDocument(document), action, closeAfter))
            localError = services.text('Не вдалося почати експорт. Спробуй ще раз.', 'Could not start export. Try again.');
    }
    function retry() {
        if (lastAction)
            exportAction(lastAction, lastCloseAfter);
    }
    function requestClose() {
        if (screenshot.phase === 'exporting')
            return;
        if (textInput.visible) {
            cancelText();
            return;
        }
        if (canvas.gesture) {
            canvas.cancelGesture();
            return;
        }
        if (dirty && mode !== 'pick') {
            confirmDiscard = true;
            return;
        }
        rememberStyle();
        screenshot.close();
    }
    function beginText(point, id) {
        editingTextId = id;
        textPoint = point;
        const a = id ? document.annotations.find(function (item) {
            return item.id === id;
        }) : null;
        textInput.text = a ? a.text : '';
        textInput.visible = true;
        textInput.forceActiveFocus();
    }
    function commitText() {
        if (!textInput.visible)
            return true;
        if (textInput.text.length > 4096) {
            localError = services.text('Текст може містити до 4096 символів.', 'Text can contain up to 4096 characters.');
            return false;
        }
        const value = textInput.text.replace(/\s+$/, '');
        if (value) {
            const old = editingTextId ? document.annotations.find(function (item) {
                return item.id === editingTextId;
            }) : null;
            const size = old ? old.fontSize : fontSize;
            const lines = value.split('\n');
            const bounds = {
                width: lines.reduce(function (width, line) {
                    return Math.max(width, line.length * size * 0.65);
                }, 1),
                height: lines.length * size * 1.2
            };
            try {
                if (old)
                    edit(Model.updateAnnotation(document, old.id, Object.assign({
                        text: value
                    }, bounds)));
                else
                    edit(Model.addAnnotation(document, Object.assign({
                        id: 'a-' + Date.now().toString(36) + '-' + Math.random().toString(36).slice(2, 7),
                        type: 'text',
                        x: textPoint.x,
                        y: textPoint.y,
                        points: [],
                        text: value,
                        color: color,
                        strokeWidth: strokeWidth,
                        fontSize: size
                    }, bounds)));
            } catch (error) {
                localError = String(error);
                return false;
            }
        } else if (editingTextId) {
            edit(Model.deleteAnnotation(document, editingTextId));
        }
        textInput.visible = false;
        editingTextId = '';
        textPoint = null;
        forceActiveFocus();
        return true;
    }
    function cancelText() {
        textInput.visible = false;
        editingTextId = '';
        textPoint = null;
        forceActiveFocus();
    }
    function shortcutMatches(event, spec) {
        return Settings.matchesScreenshotShortcut(event.key, event.modifiers, spec);
    }
    function handleKey(event) {
        if (textInput.visible)
            return;
        if (screenshot.phase === 'exporting')
            return;
        const keys = services.config.documents.screenshots?.localKeys || {};
        if (confirmDiscard) {
            if (event.key === Qt.Key_Escape) {
                confirmDiscard = false;
                event.accepted = true;
            }
            return;
        }
        if (canvas.gesture) {
            if (shortcutMatches(event, keys.cancel))
                canvas.cancelGesture();
            event.accepted = true;
            return;
        }
        if (shortcutMatches(event, keys.cancel)) {
            requestClose();
            event.accepted = true;
            return;
        }
        if (shortcutMatches(event, keys.undo)) {
            edit(Model.undo(document));
            event.accepted = true;
            return;
        }
        if (shortcutMatches(event, keys.redo)) {
            edit(Model.redo(document));
            event.accepted = true;
            return;
        }
        if (shortcutMatches(event, keys.delete)) {
            canvas.deleteSelected();
            event.accepted = true;
            return;
        }
        if (shortcutMatches(event, keys.copy)) {
            exportAction('copy', false);
            event.accepted = true;
            return;
        }
        if (shortcutMatches(event, keys.accept)) {
            exportAction('copy', true);
            event.accepted = true;
            return;
        }
        if (shortcutMatches(event, keys.save)) {
            exportAction('save', false);
            event.accepted = true;
            return;
        }
        for (const name of ['select', 'brush', 'line', 'arrow', 'rectangle', 'ellipse', 'text', 'highlight', 'redact', 'crop'])
            if (shortcutMatches(event, keys[name])) {
                tool = name;
                event.accepted = true;
                return;
            }
    }
    Keys.onPressed: function (event) {
        root.handleKey(event);
    }
    Component.onCompleted: resetDocument()
    Connections {
        target: root.screenshot
        function onExported(closeAfter) {
            root.localError = '';
            const result = root.screenshot.lastExport || {};
            root.statusMessage = result.saved ? root.services.text('Збережено: ', 'Saved: ') + result.path : '';
            root.copied = !!result.copied;
            if (root.copied)
                copyFeedback.restart();
            root.rememberStyle();
            if (!closeAfter)
                root.savedState = JSON.stringify(Model.exportDocument(root.document));
        }
    }

    Timer {
        id: copyFeedback
        interval: 1800
        onTriggered: root.copied = false
    }

    ScreenshotCanvas {
        id: canvas
        objectName: 'screenshot-canvas'
        anchors.fill: parent
        document: root.document
        imagePath: root.capture.path
        windowRegions: root.capture.windowRegions
        contentRegions: root.capture.contentRegions || []
        kindLabels: ({
            image: root.services.text('Зображення', 'Image'),
            text: root.services.text('Текст', 'Text'),
            panel: root.services.text('Панель', 'Panel'),
            window: root.services.text('Вікно', 'Window'),
            screen: root.services.text('Весь екран', 'Whole screen')
        })
        tool: root.tool
        color: root.color
        strokeWidth: root.strokeWidth
        fontSize: root.fontSize
        interactive: canvas.imageReady && !root.busy && !root.confirmDiscard && !textInput.visible
        onEdited: function (next) {
            root.edit(next);
        }
        onCropChosen: function (rect) {
            if (!root.screenshot.chooseOutput(root.outputId))
                return;
            // Picking hands the chosen area to another tool instead of opening the editor.
            if (root.mode === 'pick') {
                if (root.searchPanelWanted) {
                    root.searchPanelPos = null;
                    root.searchChoosing = true;
                } else
                    root.screenshot.finishPick(rect);
                return;
            }
            root.screenshot.phase = 'editing';
            if (root.mode === 'copy')
                root.exportAction('copy', true);
        }
        onTextRequested: function (point, id) {
            root.beginText(point, id);
        }
        onOperationError: function (message) {
            root.localError = message;
        }
        onImageFailed: {
            const service = root.screenshot, output = root.outputId;
            service.error = root.services.text('Не вдалося відкрити зображення скріншота.', 'Could not open the captured image.');
            service.phase = 'error';
            Qt.callLater(function () {
                service.imagePath = '';
                service.outputId = output;
                service.choosingOutput = false;
                service.frames = ({});
            });
        }
    }
    Rectangle {
        id: instruction
        visible: canvas.selecting && !root.busy && !canvas.gesture
        anchors.horizontalCenter: parent.horizontalCenter
        y: 20
        width: Math.min(parent.width - 16, message.implicitWidth + 28)
        height: 32
        radius: height / 2
        color: Qt.rgba(0.07, 0.08, 0.09, 0.78)
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.12)
        PentadText {
            id: message
            anchors.centerIn: parent
            width: Math.min(implicitWidth, parent.width - 28)
            color: 'white'
            wrapMode: Text.NoWrap
            elide: Text.ElideRight
            readonly property string cancelKey: root.services.config.documents.screenshots?.localKeys?.cancel || ''
            text: (root.mode === 'pick' && root.screenshot.pickLabel ? root.screenshot.pickLabel + ' · ' : '')
                + root.services.text('Перетягніть область або клацніть підсвічене · коліщатко — більше/менше', 'Drag an area or click what is highlighted · wheel for bigger/smaller')
                + (cancelKey ? ' · ' + cancelKey + root.services.text(' — скасувати', ' to cancel') : '')
        }
    }
    ScreenshotToolbar {
        id: toolbar
        objectName: 'screenshot-toolbar'
        visible: !canvas.selecting && root.mode !== 'pick'
        services: root.services
        tool: root.tool
        selectedType: root.selectedAnnotation ? root.selectedAnnotation.type : ''
        annotationColor: root.selectedAnnotation && root.tool === 'select' ? root.selectedAnnotation.color : root.color
        strokeWidth: root.selectedAnnotation && root.tool === 'select' ? root.selectedAnnotation.strokeWidth : root.strokeWidth
        fontSize: root.selectedAnnotation && root.tool === 'select' ? root.selectedAnnotation.fontSize : root.fontSize
        pendingAction: root.lastAction
        copied: root.copied
        busy: root.busy
        canUndo: root.document.history.length > 0
        canRedo: root.document.future.length > 0
        horizontal: root.toolbarPlacement.horizontal
        x: root.toolbarPlacement.x
        y: root.toolbarPlacement.y
        onDragged: function (x, y, grabAlong) {
            root.toolbarDock = Dock.dockFromPointer(canvas.cropView, {
                x: x,
                y: y
            }, toolbar.length, grabAlong);
        }
        onToolChosen: function (value) {
            // A pending text must be committed first; otherwise the tool changes while the input still owns the canvas.
            if (textInput.visible && !root.commitText())
                return;
            root.tool = value;
            root.forceActiveFocus();
        }
        onColorChosen: function (value) {
            root.color = value;
            root.style({
                color: value
            });
            root.forceActiveFocus();
        }
        onWidthChosen: function (value) {
            root.strokeWidth = value;
            root.style({
                strokeWidth: value
            });
        }
        onFontSizeChosen: function (value) {
            root.fontSize = value;
            root.style({
                fontSize: value
            });
        }
        onUndoRequested: root.edit(Model.undo(root.document))
        onRedoRequested: root.edit(Model.redo(root.document))
        onCopyRequested: root.exportAction('copy', false)
        onSaveRequested: root.exportAction('save', false)
        onCloseRequested: root.requestClose()
    }
    ScreenshotSearchPanel {
        id: searchPanel
        objectName: 'screenshot-search-panel'
        visible: root.searchChoosing && !canvas.selecting && !root.busy
        services: root.services
        engines: root.screenshot.pickEngines
        x: root.searchPanelPos ? root.searchPanelPos.x : root.searchPanelAuto.x
        y: root.searchPanelPos ? root.searchPanelPos.y : root.searchPanelAuto.y
        onDragged: function (x, y) {
            root.searchPanelPos = {
                x: Math.max(8, Math.min(root.width - width - 8, x)),
                y: Math.max(8, Math.min(root.height - height - 8, y))
            };
        }
        onSearchRequested: function (ids) {
            root.searchChoosing = false;
            root.screenshot.finishPick(root.document.crop, ids);
        }
    }
    ContinuousSurface {
        visible: !!root.statusMessage && !root.busy && !root.confirmDiscard
        anchors.horizontalCenter: parent.horizontalCenter
        y: Math.max(8, parent.height - height - 8)
        width: Math.min(parent.width - 16, statusText.implicitWidth + 16)
        height: statusText.contentHeight + 16
        extent: 16
        fill: Theme.tokens.surface
        PentadText {
            id: statusText
            x: 8
            y: 8
            width: parent.width - 16
            text: root.statusMessage
            wrapMode: Text.WrapAnywhere
            horizontalAlignment: Text.AlignHCenter
        }
    }
    ContinuousSurface {
        visible: !!(root.localError || root.screenshot.error)
        width: Math.min(parent.width - 16, 520)
        height: errorBody.implicitHeight + 16
        x: (parent.width - width) / 2
        y: 8
        extent: 16
        fill: Theme.tokens.surface
        Column {
            id: errorBody
            x: 8
            y: 8
            width: parent.width - 16
            spacing: 8
            Row {
                width: parent.width
                spacing: 8
                PentadIcon {
                    source: Qt.resolvedUrl('../../assets/icons/material/screenshot/error-symbolic.svg')
                    color: Theme.tokens.error
                    pixelSize: Metrics.exposedIcon
                }
                PentadText {
                    text: root.localError || root.screenshot.error
                    width: parent.width - Metrics.exposedIcon - 8
                    wrapMode: Text.WrapAnywhere
                }
            }
            ScreenshotIconButton {
                visible: !!root.lastAction
                text: root.services.text('Повторити', 'Retry')
                iconSource: Qt.resolvedUrl('../../assets/icons/material/screenshot/redo-symbolic.svg')
                onClicked: root.retry()
            }
        }
    }
    Rectangle {
        visible: root.confirmDiscard
        anchors.fill: parent
        color: '#aa000000'
        MouseArea {
            anchors.fill: parent
            onClicked: {}
        }
        ContinuousSurface {
            anchors.centerIn: parent
            width: Math.min(parent.width - 16, 350)
            height: discardBody.implicitHeight + 16
            extent: 16
            fill: Theme.tokens.surface
            Column {
                id: discardBody
                x: 8
                y: 8
                width: parent.width - 16
                spacing: 8
                PentadText {
                    width: parent.width
                    text: root.services.text('Відкинути зміни?', 'Discard changes?')
                    role: 'section'
                }
                Flow {
                    width: parent.width
                    spacing: 8
                    ScreenshotIconButton {
                        text: root.services.text('Продовжити', 'Keep editing')
                        iconSource: Qt.resolvedUrl('../../assets/icons/material/screenshot/edit-symbolic.svg')
                        onClicked: {
                            root.confirmDiscard = false;
                            root.forceActiveFocus();
                        }
                    }
                    ScreenshotIconButton {
                        text: root.services.text('Відкинути', 'Discard')
                        iconSource: Qt.resolvedUrl('../../assets/icons/material/media/close-symbolic.svg')
                        onClicked: {
                            root.rememberStyle();
                            root.screenshot.close();
                        }
                    }
                }
            }
        }
    }
    MouseArea {
        // The canvas is frozen while text is typed; clicking away keeps the text instead of silently doing nothing.
        anchors.fill: parent
        visible: textInput.visible
        z: 9
        onPressed: root.commitText()
    }
    TextArea {
        id: textInput
        visible: false
        z: 10
        x: root.textPoint ? Math.max(8, Math.min(parent.width - width - 8, canvas.viewPoint(root.textPoint).x)) : 0
        y: root.textPoint ? Math.max(8, Math.min(parent.height - height - 8, canvas.viewPoint(root.textPoint).y)) : 0
        width: Math.min(360, parent.width - 16)
        height: Math.max(54, Math.min(180, contentHeight + 16))
        color: Theme.tokens.text
        selectionColor: Theme.tokens.accent
        font.family: Theme.tokens.fontFamily
        font.pixelSize: Math.max(12, root.fontSize * canvas.imageScale)
        wrapMode: TextEdit.Wrap
        placeholderText: root.services.text('Введіть текст', 'Enter text')
        padding: 8
        background: ContinuousSurface {
            fill: textInput.activeFocus ? Qt.tint(Theme.tokens.surfaceOverlay, Qt.alpha(Theme.tokens.accent, 0.12)) : Theme.tokens.surface
            extent: 16
        }
        Keys.onPressed: function (event) {
            if (event.key === Qt.Key_Escape) {
                root.cancelText();
                event.accepted = true;
            } else if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && !(event.modifiers & Qt.ShiftModifier)) {
                root.commitText();
                event.accepted = true;
            }
        }
    }
}
