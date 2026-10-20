import QtQuick
import QtQml
import Quickshell
import Quickshell.Io
import '../logic/artwork.mjs' as ArtworkLogic

QtObject {
    id: root
    required property string helperPath
    property string curlExecutable: 'curl'
    property string configRoot: (Quickshell.env('XDG_CONFIG_HOME') || Quickshell.env('HOME') + '/.config') + '/pentad'
    property string stateRoot: (Quickshell.env('XDG_STATE_HOME') || Quickshell.env('HOME') + '/.local/state') + '/pentad'
    property string cacheRoot: Quickshell.env('XDG_CACHE_HOME') || Quickshell.env('HOME') + '/.cache'
    property bool preview: false
    property bool safeMode: false
    property double serial: Date.now() * 1000 + Math.floor(Math.random() * 1000)
    property var states: ({})
    property var requests: ({})
    property var cache: ({})

    function stateFor(consumerId) {
        return states[consumerId] || { kind: 'unavailable', source: '', reason: 'not-requested' };
    }

    function isCurrent(consumerId, request) {
        var current = requests[consumerId];
        return current === request && ArtworkLogic.artworkRequestIsCurrent(
            current.generation, request.generation, current.key, request.key);
    }

    function setState(consumerId, state) {
        states = Object.assign({}, states, { [consumerId]: state });
    }

    function helper(payload, done) {
        var component = helperComponent.createObject(root, { payload: payload });
        if (!component) { done({ ok: false, reason: 'unavailable' }); return null; }
        component.finished.connect(function(result) { done(result); });
        component.running = true;
        return component;
    }

    function forgetCacheId(requestId) {
        var next = Object.assign({}, cache);
        Object.keys(next).forEach(function(url) {
            if (next[url].requestId === requestId) delete next[url];
        });
        cache = next;
    }

    function cleanup(requestId) {
        if (!requestId) return;
        helper({ operation: 'artwork-remove', requestId: requestId }, function() {});
    }

    function cancel(consumerId) {
        var old = requests[consumerId];
        var next = Object.assign({}, requests);
        delete next[consumerId];
        requests = next;
        if (!old) return;
        if (old.process) {
            var process = old.process;
            old.process = null;
            if (process.running) process.signal(9);
            process.destroy();
        }
        cleanup(old.requestId);
    }

    function release(consumerId) {
        if (!consumerId) return;
        cancel(consumerId);
        var next = Object.assign({}, states);
        delete next[consumerId];
        states = next;
    }

    function reject(consumerId, source) {
        var previous = stateFor(consumerId);
        if (previous.kind !== 'ready' || previous.source !== source) return;
        if (previous.requestUrl && cache[previous.requestUrl]) {
            var requestId = cache[previous.requestUrl].requestId;
            forgetCacheId(requestId);
            cleanup(requestId);
        }
        var candidates = previous.candidates || [];
        var nextIndex = Number(previous.candidateIndex || 0) + 1;
        if (nextIndex >= candidates.length) {
            setState(consumerId, { kind: 'unavailable', source: '', key: previous.key, reason: 'decode-failed' });
            return;
        }
        var task = { key: previous.key, generation: ++serial, index: nextIndex, requestId: 0, process: null };
        requests = Object.assign({}, requests, { [consumerId]: task });
        setState(consumerId, { kind: 'loading', source: '', key: previous.key,
            candidates: candidates, candidateIndex: nextIndex });
        loadCandidate(consumerId, candidates, task);
    }

    function safeSource(url) {
        if (typeof url !== 'string') return false;
        return /^https?:\/\/[^/?#]+(?:[/?#]|$)/i.test(url) && !/^https?:\/\/[^/?#]*@/i.test(url)
            || /^file:\/\/(?:localhost)?\/(?!\/)(?:[^?#]*)$/i.test(url);
    }

    function request(consumerId, urls, trackKey) {
        if (!consumerId) return;
        var candidates = Array.isArray(urls) ? urls.filter(safeSource) : [];
        var key = JSON.stringify({ urls: candidates, track: String(trackKey || '') });
        var previous = stateFor(consumerId);
        if (previous.key === key && (previous.kind === 'loading' || previous.kind === 'ready')) return;
        cancel(consumerId);
        if (preview || safeMode || candidates.length === 0) {
            setState(consumerId, { kind: 'unavailable', source: '', key: key,
                reason: preview ? 'preview' : safeMode ? 'safe-mode' : 'no-artwork' });
            return;
        }
        var task = { key: key, generation: ++serial, index: 0, requestId: 0, process: null };
        requests = Object.assign({}, requests, { [consumerId]: task });
        setState(consumerId, { kind: 'loading', source: '', key: key,
            candidates: candidates, candidateIndex: 0 });
        loadCandidate(consumerId, candidates, task);
    }

    function loadCandidate(consumerId, candidates, task) {
        if (!isCurrent(consumerId, task)) return;
        if (task.index >= candidates.length) {
            setState(consumerId, { kind: 'unavailable', source: '', key: task.key, reason: 'load-failed',
                candidates: candidates, candidateIndex: task.index });
            if (requests[consumerId] === task) {
                var next = Object.assign({}, requests);
                delete next[consumerId];
                requests = next;
            }
            return;
        }
        var url = candidates[task.index];
        var cached = cache[url];
        if (cached) {
            var cacheId = cached.requestId;
            helper({ operation: 'artwork-touch', requestId: cacheId }, function(result) {
                if (!isCurrent(consumerId, task)) return;
                if (result.ok) {
                    setState(consumerId, { kind: 'ready', source: cached.url, key: task.key, requestUrl: url,
                        candidates: candidates, candidateIndex: task.index });
                    return;
                }
                forgetCacheId(cacheId);
                loadCandidate(consumerId, candidates, task);
            });
            return;
        }

        var requestId = ++serial;
        task.requestId = requestId;
        var local = url.slice(0, 5).toLowerCase() === 'file:';
        task.process = helper(local
            ? { operation: 'artwork-copy-local', requestId: requestId, uri: url }
            : { operation: 'artwork-prepare', requestId: requestId }, function(prepared) {
                if (!isCurrent(consumerId, task)) { cleanup(requestId); return; }
                task.process = null;
                if (!prepared.ok || !prepared.path) {
                    cleanup(requestId);
                    task.requestId = 0;
                    task.index++;
                    loadCandidate(consumerId, candidates, task);
                    return;
                }
                if (local) finishDownload(consumerId, candidates, task, url, 0, true);
                else download(consumerId, candidates, task, url, prepared.path);
            });
    }

    function download(consumerId, candidates, task, url, stagePath) {
        if (!isCurrent(consumerId, task)) { cleanup(task.requestId); return; }
        var process = downloadComponent.createObject(root, { url: url, stagePath: stagePath });
        if (!process) {
            finishDownload(consumerId, candidates, task, url, -1, false);
            return;
        }
        task.process = process;
        process.finished.connect(function(code, status, httpStatus) {
            if (!isCurrent(consumerId, task)) { cleanup(task.requestId); return; }
            task.process = null;
            finishDownload(consumerId, candidates, task, url, code, httpStatus >= 200 && httpStatus < 300);
        });
        process.running = true;
    }

    function finishDownload(consumerId, candidates, task, url, code, ok) {
        if (!isCurrent(consumerId, task)) { cleanup(task.requestId); return; }
        if (!ok || code !== 0) {
            cleanup(task.requestId);
            task.requestId = 0;
            task.index++;
            loadCandidate(consumerId, candidates, task);
            return;
        }
        helper({ operation: 'artwork-commit', requestId: task.requestId }, function(result) {
            if (!isCurrent(consumerId, task)) { cleanup(task.requestId); return; }
            if (!result.ok || !result.path) {
                cleanup(task.requestId);
                task.requestId = 0;
                task.index++;
                loadCandidate(consumerId, candidates, task);
                return;
            }
            (result.evicted || []).forEach(forgetCacheId);
            var source = result.url || Qt.url('file://' + result.path).toString();
            var nextCache = Object.assign({}, cache, { [url]: { requestId: task.requestId, url: source } });
            cache = nextCache;
            setState(consumerId, { kind: 'ready', source: source, key: task.key, requestUrl: url,
                candidates: candidates, candidateIndex: task.index });
            task.requestId = 0;
            var next = Object.assign({}, requests);
            delete next[consumerId];
            requests = next;
        });
    }

    property Component helperComponent: Component {
        ArtworkRequest {
            helperPath: root.helperPath
            configRoot: root.configRoot
            stateRoot: root.stateRoot
            cacheRoot: root.cacheRoot
            payload: parent.payload
        }
    }

    property Component downloadComponent: Component {
        Process {
            id: transfer
            required property string url
            required property string stagePath
            property bool startedOnce: false
            property bool settled: false
            signal finished(int code, int exitStatus, int httpStatus)
            command: [root.curlExecutable, '--silent', '--show-error', '--fail', '--location',
                '--proto', '=http,https', '--proto-redir', '=http,https', '--max-time', '15',
                '--connect-timeout', '5', '--max-filesize', '4194304', '--output', stagePath,
                '--write-out', '\n%{http_code}', '--url', url]
            stdout: StdioCollector {}
            stderr: StdioCollector {}
            onStarted: startedOnce = true
            onRunningChanged: {
                if (!running && !startedOnce && !settled) {
                    settled = true;
                    finished(-1, -1, 0);
                    destroy();
                }
            }
            onExited: function(code, exitStatus) {
                if (settled) { destroy(); return; }
                settled = true;
                var footer = /\n(\d{3})$/.exec(stdout.text || '');
                finished(code, exitStatus, footer ? Number(footer[1]) : 0);
                destroy();
            }
            property Timer deadline: Timer {
                interval: 16000
                running: true
                onTriggered: {
                    if (transfer.settled) return;
                    transfer.settled = true;
                    if (transfer.running) transfer.signal(9);
                    transfer.finished(-1, -1, 0);
                    if (!transfer.running) transfer.destroy();
                }
            }
        }
    }

    Component.onDestruction: Object.keys(requests).forEach(function(id) { cancel(id); });
}
