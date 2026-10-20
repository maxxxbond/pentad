import QtQuick
import QtQuick.Controls.Basic
import qs.components
import qs.theme
import '../../logic/tool-catalog.mjs' as Tools

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
    property var chatState: ({ messages: [], draft: '', status: 'setup', error: '' })
    width: 350
    implicitWidth: width
    implicitHeight: content.implicitHeight

    function attach() {
        if (!services || !services.chat) return;
        unsubscribeSession?.();
        session?.release();
        session = services.chat.acquire(instanceId, settings);
        unsubscribeSession = session.subscribe(function(value) { root.chatState = value; });
        chatState = session.read();
        if (services.toolWorkspace) composer.text = services.toolWorkspace.draftFor('pentad.chat') || chatState.draft || '';
    }
    function send() {
        if (!session) return;
        const text = composer.text;
        session.setDraft(text);
        composer.text = '';
        void session.send(text);
    }
    function applyInput(value, mode) {
        const next = mode === 'append' && composer.text ? composer.text + String(value) : String(value);
        composer.text = next;
        if (session) session.setDraft(next);
    }
    function acceptInput(items, choice) {
        if (!Array.isArray(items) || items.some(item => typeof item.value !== 'string')) return false;
        const incoming = items.map(item => item.value).join('\n');
        const next = choice === 'append' && composer.text ? composer.text + incoming : incoming;
        if (composer.text && !choice || Tools.utf8Length(next) > 16384) return false;
        applyInput(incoming, choice);
        return true;
    }
    function credentialStatus() {
        if (settings.provider !== 'api') return '';
        if (settings.apiKeyEnv) return 'API credential is read from ' + settings.apiKeyEnv + '.';
        if (settings.credentialRef) return 'Saved credential reference is unavailable. Set an API key environment variable in widget settings.';
        return 'API credential is not configured. Set an environment variable in widget settings.';
    }
    Component.onCompleted: attach()
    onServicesChanged: if (services && services.chat) attach()
    onSettingsChanged: attach()
    Component.onDestruction: { unsubscribeSession?.(); session?.release(); }

    Column {
        id: content
        width: root.width
        spacing: 10
        Row {
            width: parent.width
            spacing: 8
            PentadText { id: providerLabel; anchors.verticalCenter: parent.verticalCenter; text: root.settings.provider === 'ollama' ? 'OLLAMA' : 'API'; role: 'section' }
            PentadText {
                anchors.verticalCenter: parent.verticalCenter
                text: root.settings.model || 'Choose model'
                role: 'caption'; color: Theme.tokens.textMuted; elide: Text.ElideRight
                wrapMode: Text.NoWrap
                width: Math.max(0, parent.width - providerLabel.width - chatHelp.width - 2 * parent.spacing)
            }
            PentadInfoButton {
                id: chatHelp
                accessibleName: 'Chat setup help'
                helpText: (root.settings.provider === 'ollama'
                    ? 'Configure an Ollama base URL and model in widget settings.'
                    : 'Configure an API-compatible base URL and model in widget settings.')
                    + (root.settings.provider === 'api' ? '\n' + root.credentialStatus() : '')
            }
        }
        PentadText {
            width: parent.width
            visible: root.chatState.status === 'setup' || root.chatState.status === 'error'
                || (root.settings.provider === 'api' && !root.settings.apiKeyEnv)
            text: root.chatState.error || (root.settings.provider === 'api' && !root.settings.apiKeyEnv ? 'API key required' : 'Needs setup')
            color: root.chatState.status === 'error' ? Theme.tokens.error : Theme.tokens.textMuted
            role: 'caption'
        }
        ScrollView {
            id: historyScroll
            visible: root.chatState.messages.length > 0
            width: parent.width
            height: Math.max(96, Math.min(220, history.implicitHeight))
            clip: true
            contentWidth: availableWidth
            Column {
                id: history
                width: historyScroll.availableWidth
                spacing: 8
                Repeater {
                    model: root.chatState.messages
                    delegate: PentadCard {
                        required property var modelData
                        width: history.width
                        implicitHeight: label.implicitHeight + 16
                        PentadText {
                            id: label
                            x: 8
                            y: 8
                            width: parent.width - 16
                            text: (modelData.role === 'user' ? 'You: ' : 'Assistant: ') + (modelData.content || (modelData.status === 'partial' ? '…' : ''))
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
            width: parent.width
            height: 76
            placeholderText: 'Message…'
            wrapMode: TextEdit.Wrap
            color: Theme.tokens.text
            placeholderTextColor: Theme.tokens.textMuted
            font.family: Theme.tokens.fontFamily
            font.pixelSize: Metrics.textBody
            padding: 10
            background: Rectangle {
                color: Theme.tokens.surfaceRaised
                radius: Metrics.radiusSmall
                border.color: composer.activeFocus ? Theme.tokens.accent : Theme.tokens.outline
            }
            onTextChanged: {
                if (root.session) root.session.setDraft(text);
                if (root.services.toolWorkspace) root.services.toolWorkspace.setDraft('pentad.chat', text);
            }
            Keys.onReturnPressed: function(event) {
                if (!event.modifiers) { root.send(); event.accepted = true; }
            }
        }
        Row {
            width: parent.width
            spacing: 8
            PentadButton {
                width: (parent.width - 8) / 2
                text: root.chatState.status === 'sending' || root.chatState.status === 'streaming' ? 'Stop' : 'Send'
                requestedEnabled: !!root.session && (text === 'Stop' || composer.text.trim().length > 0)
                onPressed: text === 'Stop' ? root.session.stop() : root.send()
            }
            PentadButton {
                width: (parent.width - 8) / 2
                text: 'Clear'
                requestedEnabled: root.chatState.messages.length > 0
                onPressed: { root.session.clear(); composer.text = ''; }
            }
        }
    }
}
