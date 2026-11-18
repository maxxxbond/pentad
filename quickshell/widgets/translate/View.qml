pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls.Basic
import qs.components
import qs.theme
import "../../logic/tool-catalog.mjs" as Tools

// Sends text for translation only when Translate is pressed, through the text.translate
// capability: the registry's translate model when one is bound, else translate-shell.
Item {
    id: root
    required property string instanceId
    required property var context
    required property var settings
    required property var services
    property var controller: null
    property bool canAppendInput: true
    property string result: ''
    property string message: ''
    property bool messageMuted: false
    property string jobId: ''
    // true while jobId belongs to services.fileTools (no capability service to ask).
    property bool viaFileTools: false
    property string target: 'uk'
    readonly property var capabilities: services && services.capabilities ? services.capabilities : null
    readonly property var languages: [
        {
            id: 'uk',
            uk: 'Українська',
            en: 'Ukrainian'
        },
        {
            id: 'en',
            uk: 'Англійська',
            en: 'English'
        },
        {
            id: 'de',
            uk: 'Німецька',
            en: 'German'
        },
        {
            id: 'pl',
            uk: 'Польська',
            en: 'Polish'
        },
        {
            id: 'fr',
            uk: 'Французька',
            en: 'French'
        },
        {
            id: 'es',
            uk: 'Іспанська',
            en: 'Spanish'
        }
    ]
    readonly property var resultItem: ({
            kind: 'text',
            mimeType: 'text/plain',
            value: root.result,
            compatibleTypes: ['text/plain']
        })
    readonly property var resultTargets: Tools.compatibleTools(Tools.toolEntries(root.services.plugins.catalog), [root.resultItem]).map(entry => entry.manifest.id)
    implicitWidth: 330
    implicitHeight: content.implicitHeight
    function acceptInput(items, choice) {
        const merged = Tools.mergeTextInput(source.text, items, choice, 65536, '\n');
        if (!merged.ok) {
            if (merged.reason === 'too-large') {
                root.messageMuted = false;
                root.message = root.services.text('Текст обмежено до 64 КіБ.', 'Text is limited to 64 KiB.');
            }
            return false;
        }
        source.text = merged.value;
        root.message = '';
        return true;
    }
    function showMessage(text, muted) {
        message = text;
        messageMuted = muted === true;
    }
    function failureText(value) {
        const reason = value && value.reason ? value.reason : 'io';
        const detail = value && typeof value.message === 'string' ? value.message : '';
        if (reason === 'safe-mode')
            return services.text('У безпечному режимі переклад вимкнено: він надсилає текст у мережу.', 'Translation is off in safe mode: it sends the text over the network.');
        if (reason === 'denied')
            return services.text('Віддалений переклад вимкнено (лише локальні моделі).', 'Remote translation is turned off (local models only).');
        if (reason === 'timeout')
            return services.text('Переклад не завершився вчасно.', 'The translation did not finish in time.');
        if (reason === 'busy')
            return services.text('Служба перекладу зайнята. Спробуйте трохи згодом.', 'The translation service is busy. Try again shortly.');
        if (reason === 'unavailable' || reason === 'service-missing' || reason === 'service-stopped')
            return services.text('Переклад недоступний', 'Translation is unavailable') + (detail ? ': ' + detail : '.');
        return detail || services.text('Переклад не вдався.', 'Translation failed.');
    }
    // translate-shell through the file tool, when the capability route is translate-shell and the
    // worker that would run it is down. A bound translate model is never replaced by a network service.
    function fileToolFallback() {
        if (!services.fileTools || services.safeMode)
            return false;
        if (!capabilities)
            return true;
        const availability = capabilities.available('text.translate');
        return !availability.available && (availability.reason === 'unavailable' || availability.reason === 'service-missing') && !!availability.disclosure && availability.disclosure.provider === 'translate-shell';
    }
    function translate() {
        if (!source.text.trim()) {
            showMessage(services.text('Спершу введіть текст.', 'Enter text first.'), false);
            return;
        }
        if (Tools.utf8Length(source.text) > 65536) {
            showMessage(services.text('Текст обмежено до 64 КіБ.', 'Text is limited to 64 KiB.'), false);
            return;
        }
        message = '';
        result = '';
        if (fileToolFallback()) {
            viaFileTools = true;
            jobId = services.fileTools.run('text.translate', [], {
                target: target
            }, source.text, 60000);
            return;
        }
        if (!capabilities) {
            showMessage(failureText({
                reason: services.safeMode ? 'safe-mode' : 'service-missing'
            }), false);
            return;
        }
        viaFileTools = false;
        jobId = capabilities.call('text.translate', {
            text: source.text,
            target: target
        }, {
            instanceId: instanceId
        });
    }
    function cancel() {
        if (viaFileTools)
            services.fileTools.cancel(jobId);
        else if (capabilities)
            capabilities.cancel(jobId);
    }
    function finish(value) {
        jobId = '';
        if (value && value.ok) {
            const text = viaFileTools ? value.text : value.value && value.value.text;
            result = typeof text === 'string' ? text : '';
        } else if (value && value.reason === 'cancelled')
            showMessage(services.text('Скасовано', 'Cancelled'), true);
        else
            showMessage(viaFileTools ? value && value.reason || services.text('Переклад не вдався.', 'Translation failed.') : failureText(value), false);
    }
    Connections {
        target: root.capabilities
        ignoreUnknownSignals: true
        function onCommandFinished(requestId, value) {
            if (requestId === root.jobId && !root.viaFileTools)
                root.finish(value);
        }
    }
    Connections {
        target: root.services.fileTools || null
        ignoreUnknownSignals: true
        function onJobFinished(requestId, value) {
            if (requestId === root.jobId && root.viaFileTools)
                root.finish(value);
        }
    }
    Column {
        id: content
        width: root.width
        spacing: Metrics.space3
        TextArea {
            id: source
            objectName: 'translate-tool-source'
            width: parent.width
            height: 112
            wrapMode: TextEdit.Wrap
            placeholderText: root.services.text('Текст для перекладу', 'Text to translate')
            text: root.services.toolWorkspace.draftFor('pentad.translate')
            color: Theme.tokens.text
            placeholderTextColor: Theme.tokens.textMuted
            font.family: Theme.tokens.fontFamily
            font.pixelSize: Metrics.textBody
            onTextChanged: root.services.toolWorkspace.setDraft('pentad.translate', text)
            background: Rectangle {
                color: Theme.tokens.surfaceRaised
                radius: Metrics.radiusSmall
            }
        }
        Flow {
            width: parent.width
            spacing: Metrics.space2
            Repeater {
                model: root.languages
                delegate: PentadButton {
                    required property var modelData
                    objectName: 'translate-tool-target-' + modelData.id
                    text: root.services.text(modelData.uk, modelData.en)
                    controlHeight: Metrics.controlSmall
                    checkable: true
                    checked: root.target === modelData.id
                    onClicked: root.target = modelData.id
                }
            }
        }
        Row {
            spacing: Metrics.space2
            PentadButton {
                objectName: 'translate-tool-run'
                text: root.jobId ? root.services.text('Скасувати', 'Cancel') : root.services.text('Перекласти', 'Translate')
                onClicked: root.jobId ? root.cancel() : root.translate()
            }
            PentadButton {
                text: root.services.text('Копіювати', 'Copy')
                visible: !!root.result
                onClicked: {
                    output.selectAll();
                    output.copy();
                    output.deselect();
                }
            }
            PentadButton {
                text: root.services.text('Передати в інший інструмент', 'Use in another tool')
                visible: !!root.result && root.resultTargets.length > 0
                onClicked: root.services.toolWorkspace.receive([root.resultItem], root.resultTargets, '')
            }
        }
        TextArea {
            id: output
            objectName: 'translate-tool-output'
            visible: !!root.result
            width: parent.width
            height: Math.min(200, Math.max(72, implicitHeight))
            readOnly: true
            selectByMouse: true
            wrapMode: TextEdit.Wrap
            text: root.result
            color: Theme.tokens.text
            font.family: Theme.tokens.fontFamily
            font.pixelSize: Metrics.textBody
            background: Rectangle {
                color: Theme.tokens.surface
                radius: Metrics.radiusSmall
            }
        }
        PentadText {
            objectName: 'translate-tool-message'
            visible: !!root.message
            width: parent.width
            text: root.message
            role: 'caption'
            color: root.messageMuted ? Theme.tokens.textMuted : Theme.tokens.error
            wrapMode: Text.Wrap
        }
    }
}
