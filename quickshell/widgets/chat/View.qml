import QtQuick
import QtQuick.Controls.Basic
import qs.components
import qs.theme
import "../../logic/tool-catalog.mjs" as Tools
import "../../logic/chat.mjs" as ChatLogic

Item {
    id: root
    required property string instanceId
    required property var context
    required property var settings
    required property var services
    property var controller: null
    property var session: null
    property var unsubscribeSession: null
    property bool canAppendInput: true
    property var chatState: ({
            messages: [],
            draft: '',
            status: 'setup',
            error: ''
        })
    // The outcome of the last quick setup or "Move to Models" click, shown once.
    property string actionMessage: ''
    property bool actionFailed: false
    property bool warmedThisPresentation: false
    // Set when the user reaches for the composer (hover or focus); opening the panel alone does
    // not load a model into memory.
    property bool engaged: false
    readonly property var capabilities: services && services.capabilities ? services.capabilities : null
    readonly property var chatService: services && services.chat ? services.chat : null
    readonly property var profile: ChatLogic.chatProfile(settings)
    readonly property bool registrySource: !!profile && profile.source === 'registry'
    readonly property bool customReady: !!profile && profile.source === 'custom' && !profile.setup
    // Where the answer would come from, read before Run (R3).
    readonly property var availability: {
        if (!capabilities || !chatService || !profile || profile.setup)
            return null;
        const options = chatService.callOptions(profile, instanceId);
        if (profile.source === 'custom' && !options.provider)
            return null;
        return capabilities.available('llm.chat', options);
    }
    readonly property var disclosure: availability && availability.disclosure ? availability.disclosure : null
    // models.json that failed to parse or to read: the registry then holds defaults, so neither
    // "no model yet" nor the quick setup would be true. Null while the store has no states.
    readonly property var modelsState: services && services.config && services.config.documentStates ? services.config.documentStates.models || null : null
    readonly property bool modelsBroken: !!modelsState && (modelsState.kind === 'invalid' || modelsState.kind === 'error')
    readonly property bool needsModel: registrySource && !!availability && !availability.available && availability.reason === 'not-configured'
    readonly property bool setupBusy: !!chatService && chatService.busy[instanceId] === true
    readonly property bool streaming: chatState.status === 'sending' || chatState.status === 'streaming'
    readonly property bool effectivelyVisible: {
        let item = root;
        while (item) {
            if (!item.visible)
                return false;
            item = item.parent;
        }
        return true;
    }
    readonly property bool presented: !(context && context.presented === false) && effectivelyVisible
    readonly property bool warmWanted: presented && engaged && registrySource && !!availability && availability.available === true
    width: 350
    implicitWidth: width
    implicitHeight: content.implicitHeight

    function attach() {
        if (!chatService)
            return;
        unsubscribeSession?.();
        session?.release();
        session = chatService.acquire(instanceId, settings);
        unsubscribeSession = session.subscribe(function (value) {
            root.chatState = value;
        });
        chatState = session.read();
        if (services.toolWorkspace)
            composer.text = services.toolWorkspace.draftFor('pentad.chat') || chatState.draft || '';
    }
    function send() {
        if (!session)
            return;
        const text = composer.text;
        session.setDraft(text);
        composer.text = '';
        void session.send(text);
    }
    function applyInput(value, mode) {
        const next = mode === 'append' && composer.text ? composer.text + String(value) : String(value);
        composer.text = next;
        if (session)
            session.setDraft(next);
    }
    function acceptInput(items, choice) {
        if (!Array.isArray(items) || items.some(item => typeof item.value !== 'string'))
            return false;
        const incoming = items.map(item => item.value).join('\n');
        const next = choice === 'append' && composer.text ? composer.text + incoming : incoming;
        if (composer.text && !choice || Tools.utf8Length(next) > 16384)
            return false;
        applyInput(incoming, choice);
        return true;
    }
    // "Локально · qwen3.5:9b" / "Хмара · OpenAI · gpt-4o"
    function disclosureText() {
        if (!disclosure)
            return registrySource ? services.text('Моделі', 'Models') : (settings.model || services.text('Оберіть модель', 'Choose model'));
        if (disclosure.execution === 'local')
            return services.text('Локально', 'Local') + ' · ' + disclosure.model;
        return [services.text('Хмара', 'Cloud'), disclosure.provider, disclosure.model].filter(part => !!part).join(' · ');
    }
    function credentialStatus() {
        if (settings.provider !== 'api')
            return '';
        if (settings.apiKeyEnv)
            return services.text('Ключ API читається зі змінної ' + settings.apiKeyEnv + '.', 'The API key is read from ' + settings.apiKeyEnv + '.');
        return services.text('Ключ API не налаштовано: вкажіть змінну середовища в налаштуваннях віджета.', 'The API key is not configured: set an environment variable in widget settings.');
    }
    function helpText() {
        if (registrySource)
            return services.text('Чат бере модель із Моделей (роль «' + (profile.role === 'fast' ? 'швидка' : 'чат') + '»). Власну адресу можна вказати в налаштуваннях віджета.', 'Chat uses the model bound to the "' + profile.role + '" role in Models. Widget settings can switch it to its own endpoint.');
        const base = settings.provider === 'ollama' ? services.text('Вкажіть адресу Ollama і модель у налаштуваннях віджета.', 'Set an Ollama base URL and model in widget settings.') : services.text('Вкажіть сумісну з API адресу й модель у налаштуваннях віджета.', 'Set an API-compatible base URL and model in widget settings.');
        const credential = credentialStatus();
        return credential ? base + '\n' + credential : base;
    }
    // One caption under the header: the session error first, then what keeps the chat from running.
    function statusText() {
        if (chatState.status === 'error' && chatState.error)
            return chatState.error;
        if (actionMessage)
            return actionMessage;
        if (!profile)
            return services.text('Налаштування чату недійсні. Перевірте адресу й змінну з ключем.', 'The chat settings are not valid. Check the endpoint and the key variable.');
        if (profile.setup || chatState.status === 'setup')
            return chatState.error || services.text('Потрібне налаштування', 'Needs setup');
        if (modelsBroken && registrySource)
            return ChatLogic.documentFailureMessage({
                reason: modelsState.kind === 'invalid' ? 'document-invalid' : 'document-unreadable',
                document: 'models'
            }, services.text);
        if (availability && !availability.available && !needsModel) {
            if (availability.reason === 'denied' && disclosure && disclosure.execution === 'remote')
                return services.text('Віддалені моделі вимкнено (лише локальні).', 'Remote models are turned off (local only).');
            return ChatLogic.chatFailureMessage(availability, services.text);
        }
        return '';
    }
    function setupFailure(result) {
        return ChatLogic.chatActionFailureMessage('setup', result, services.text);
    }
    function moveFailure(result) {
        return ChatLogic.chatActionFailureMessage('move', result, services.text);
    }
    function connectLocal() {
        if (!chatService || setupBusy)
            return;
        actionMessage = '';
        chatService.connectLocalOllama(instanceId);
    }
    function moveToModels() {
        if (!chatService || setupBusy)
            return;
        actionMessage = '';
        chatService.moveToModels(instanceId, settings);
    }
    function engage() {
        engaged = true;
    }
    // R14: load the role's model once per presentation, when the user reaches for the composer
    // and ahead of the first message.
    function warmIfWanted() {
        if (!warmWanted || warmedThisPresentation)
            return;
        warmedThisPresentation = true;
        capabilities.warm('llm.chat', {
            role: profile.role
        });
    }
    onWarmWantedChanged: warmIfWanted()
    onPresentedChanged: if (!presented) {
        warmedThisPresentation = false;
        engaged = false;
    }
    Component.onCompleted: {
        attach();
        warmIfWanted();
    }
    onServicesChanged: if (services && services.chat)
        attach()
    onSettingsChanged: {
        actionMessage = '';
        attach();
    }
    Component.onDestruction: {
        unsubscribeSession?.();
        session?.release();
    }
    Connections {
        target: root.chatService
        ignoreUnknownSignals: true
        function onSetupFinished(instanceId, result) {
            if (instanceId !== root.instanceId)
                return;
            root.actionFailed = !result.ok;
            root.actionMessage = result.ok ? '' : root.setupFailure(result);
        }
        function onMoveFinished(instanceId, result) {
            if (instanceId !== root.instanceId)
                return;
            root.actionFailed = !result.ok;
            root.actionMessage = result.ok ? '' : root.moveFailure(result);
        }
    }

    Column {
        id: content
        width: root.width
        spacing: Metrics.space2
        Row {
            id: header
            width: parent.width
            spacing: Metrics.space2
            PentadText {
                id: title
                anchors.verticalCenter: parent.verticalCenter
                text: root.services.text('Чат', 'Chat')
                role: 'section'
                solid: true
            }
            PentadText {
                id: disclosureLabel
                objectName: 'chat-disclosure'
                anchors.verticalCenter: parent.verticalCenter
                text: root.disclosureText()
                role: 'caption'
                solid: true
                color: Theme.tokens.textMuted
                elide: Text.ElideRight
                wrapMode: Text.NoWrap
                textFormat: Text.PlainText
                width: Math.max(0, parent.width - title.width - (moveButton.visible ? moveButton.width + parent.spacing : 0) - chatHelp.width - 2 * parent.spacing)
            }
            PentadButton {
                id: moveButton
                restFill: Theme.tokens.surfaceOverlay
                objectName: 'chat-move-to-models'
                anchors.verticalCenter: parent.verticalCenter
                visible: root.customReady
                text: root.services.text('У Моделі', 'To Models')
                accessibleName: root.services.text('Перенести адресу в Моделі', 'Move this endpoint to Models')
                controlHeight: Metrics.controlSmall
                pending: root.setupBusy
                requestedEnabled: !root.setupBusy
                onClicked: root.moveToModels()
            }
            PentadInfoButton {
                id: chatHelp
                anchors.verticalCenter: parent.verticalCenter
                accessibleName: root.services.text('Довідка про чат', 'Chat help')
                helpText: root.helpText()
            }
        }
        PentadText {
            objectName: 'chat-status'
            width: parent.width
            visible: text !== ''
            text: root.statusText()
            color: root.chatState.status === 'error' || root.actionFailed && root.actionMessage || root.modelsBroken && root.registrySource ? Theme.tokens.error : Theme.tokens.textMuted
            role: 'caption'
            wrapMode: Text.Wrap
            textFormat: Text.PlainText
        }
        PentadEmptyState {
            id: setupCard
            objectName: 'chat-setup'
            // A broken models.json shows its message above instead of offering to write the file.
            visible: root.needsModel && !root.modelsBroken
            width: parent.width
            iconSource: Qt.resolvedUrl('../../assets/icons/material/tools/chat-bubble-symbolic.svg')
            text: root.services.text('Ще немає моделі для чату', 'No chat model yet')
            actionText: root.setupBusy ? root.services.text('Підключення…', 'Connecting…') : root.services.text('Підключити локальну Ollama', 'Connect local Ollama')
            onActionRequested: root.connectLocal()
        }
        ScrollView {
            id: historyScroll
            visible: root.chatState.messages.length > 0 && !root.needsModel
            width: parent.width
            height: Math.max(96, Math.min(220, history.implicitHeight))
            clip: true
            contentWidth: availableWidth
            Column {
                id: history
                width: historyScroll.availableWidth
                spacing: Metrics.space2
                Repeater {
                    model: root.chatState.messages
                    delegate: PentadCard {
                        required property var modelData
                        width: history.width
                        implicitHeight: label.implicitHeight + 2 * Metrics.space2
                        PentadText {
                            id: label
                            x: Metrics.space2
                            y: Metrics.space2
                            width: parent.width - 2 * Metrics.space2
                            text: (modelData.role === 'user' ? root.services.text('Ви: ', 'You: ') : root.services.text('Асистент: ', 'Assistant: ')) + (modelData.content || (modelData.status === 'partial' ? '…' : ''))
                            role: 'body'
                            wrapMode: Text.Wrap
                            textFormat: Text.PlainText
                        }
                    }
                }
            }
        }
        TextArea {
            id: composer
            objectName: 'chat-composer'
            visible: !root.needsModel
            onHoveredChanged: if (hovered)
                root.engage()
            onActiveFocusChanged: if (activeFocus)
                root.engage()
            width: parent.width
            height: 76
            placeholderText: root.services.text('Повідомлення…', 'Message…')
            wrapMode: TextEdit.Wrap
            color: Theme.tokens.text
            placeholderTextColor: Theme.tokens.textMuted
            font.family: Theme.tokens.fontFamily
            font.pixelSize: Metrics.textBody
            padding: Metrics.space2
            hoverEnabled: true
            // Borderless like PentadTextField: one elevation step above the card, tinted on hover and focus.
            background: Rectangle {
                color: composer.activeFocus ? Qt.tint(Theme.tokens.surfaceOverlay, Qt.alpha(Theme.tokens.text, 0.06)) : composer.hovered ? Qt.tint(Theme.tokens.surfaceOverlay, Qt.alpha(Theme.tokens.text, Metrics.stateHover)) : Theme.tokens.surfaceOverlay
                radius: Metrics.radiusSmall
            }
            onTextChanged: {
                if (root.session)
                    root.session.setDraft(text);
                if (root.services.toolWorkspace)
                    root.services.toolWorkspace.setDraft('pentad.chat', text);
            }
            Keys.onReturnPressed: function (event) {
                if (!event.modifiers) {
                    root.send();
                    event.accepted = true;
                }
            }
        }
        Row {
            visible: !root.needsModel
            width: parent.width
            spacing: Metrics.space2
            PentadButton {
                restFill: Theme.tokens.surfaceOverlay
                objectName: 'chat-send'
                width: (parent.width - parent.spacing) / 2
                text: root.streaming ? root.services.text('Зупинити', 'Stop') : root.services.text('Надіслати', 'Send')
                requestedEnabled: !!root.session && (root.streaming || composer.text.trim().length > 0)
                onPressed: root.streaming ? root.session.stop() : root.send()
            }
            PentadButton {
                restFill: Theme.tokens.surfaceOverlay
                width: (parent.width - parent.spacing) / 2
                text: root.services.text('Очистити', 'Clear')
                requestedEnabled: root.chatState.messages.length > 0
                onPressed: {
                    root.session.clear();
                    composer.text = '';
                }
            }
        }
    }
}
