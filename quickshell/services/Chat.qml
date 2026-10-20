import QtQuick
import Quickshell
import Quickshell.Io
import '../logic/chat.mjs' as ChatLogic

QtObject {
    id: root
    required property bool preview
    required property bool safeMode
    property var streamOverride: null
    signal stateChanged(string instanceId, var state)
    readonly property var manager: ChatLogic.createChatService({
        stream: function(profile, messages, key, cancellation, onDelta) {
            return root.requestStream(profile, messages, key, cancellation, onDelta);
        },
        apiKeyFor: function(environmentName) { return root.apiKeyFor(environmentName); },
        changed: function(instanceId, state) { root.stateChanged(instanceId, state); },
        preview: root.preview,
        safeMode: root.safeMode
    })
    function acquire(instanceId, settings) { return manager.acquire(instanceId, settings); }
    function apiKeyFor(environmentName) {
        if (!environmentName || !/^[A-Za-z_][A-Za-z0-9_]*$/.test(environmentName)) return Promise.resolve('');
        return Promise.resolve(Quickshell.env(environmentName) || '');
    }
    function requestStream(profile, messages, key, cancellation, onDelta) {
        if (root.streamOverride) return root.streamOverride(profile, messages, key, cancellation, onDelta);
        return new Promise(function(resolve, reject) {
            if (root.preview || root.safeMode) { reject(new Error('Chat requests are disabled in preview and safe mode.')); return; }
            if (cancellation.isCancelled()) { reject(new Error('Chat request cancelled.')); return; }
            let url = profile.baseUrl;
            if (profile.provider === 'api') url += '/chat/completions';
            else url += '/api/chat';
            const body = JSON.stringify({ model: profile.model, stream: true,
                messages: messages.map(function(message) { return { role: message.role, content: message.content }; }) });
            const worker = requestFactory.createObject(root, {
                url: url, provider: profile.provider, credential: key, body: body
            });
            if (!worker) { reject(new Error('Chat request could not start.')); return; }
            let settled = false;
            let stopCancellation = function() {};
            function settle(ok, message) {
                if (settled) return;
                settled = true;
                stopCancellation();
                if (ok) resolve(); else reject(new Error(message || 'Chat provider is unavailable.'));
            }
            worker.delta.connect(onDelta);
            worker.completed.connect(function(ok, message) { settle(ok, message); });
            stopCancellation = cancellation.subscribe(function() {
                worker.cancel();
                settle(false, 'Chat request cancelled.');
            });
            worker.running = true;
        });
    }
    property Component requestFactory: Component { ChatRequest {} }
    Component.onDestruction: manager.dispose()
}
