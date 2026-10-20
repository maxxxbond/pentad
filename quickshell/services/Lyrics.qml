import QtQuick
import QtQml
import Quickshell
import Quickshell.Io
import '../logic/lyrics.mjs' as Rules

QtObject {
    id: root
    required property var media
    property string helperPath: ''
    property string cacheRoot: Quickshell.env('XDG_CACHE_HOME') || Quickshell.env('HOME') + '/.cache'
    property bool preview: false
    property bool safeMode: false
    property var consumers: []
    property var cache: ({})
    property var cacheRecords: ({})
    property var cacheKeys: []
    property var request: null
    property var helperRequests: []
    property int generation: 0
    property bool cacheLoaded: false
    property bool cacheLoading: false
    property bool cacheWritePending: false
    property bool cacheWriteDirty: false
    property int rateLimitFailures: 0
    property double retryAfterUntil: 0
    readonly property var player: media.state.kind === 'ready' ? media.state.value.current : null
    readonly property string key: player ? Rules.lyricsKey(player) : ''
    readonly property string songKey: player ? Rules.lyricsCacheKey(player) : ''
    property int offsetMs: 500
    property var state: ({ kind: 'unavailable', reason: 'no-track' })
    onOffsetMsChanged: if (key) Rules.setLyricOffset(key, offsetMs)
    onKeyChanged: offsetMs = Rules.getLyricOffset(key)
    onSongKeyChanged: refresh()

    function acquire(id) {
        if (!id || consumers.includes(id)) return;
        consumers = consumers.concat([id]);
        if (consumers.length === 1) refresh();
    }
    function release(id) {
        consumers = consumers.filter(function(item) { return item !== id });
        if (!consumers.length) cancel();
    }
    function cancel() {
        generation++;
        retryTimer.stop();
        if (request) {
            var old = request;
            request = null;
            if (old.running) old.signal(9);
            old.destroy();
        }
    }
    function refresh() {
        if (request && request.trackKey !== songKey) cancel();
        else if (!request) generation++;
        if (!player || !Rules.canLookupLyrics(player)) {
            state = { kind: 'unavailable', reason: 'no-track' };
            return;
        }
        const cached = cacheRecords[songKey];
        if (cached) {
            const valid = Rules.validateLyricsCacheEntry(cached);
            if (valid) {
                cache[songKey] = valid.value;
                state = { kind: 'ready', value: valid.value };
                return;
            }
            var expired = Object.assign({}, cacheRecords); delete expired[songKey]; cacheRecords = expired;
            var oldValues = Object.assign({}, cache); delete oldValues[songKey]; cache = oldValues;
        }
        if (preview) { state = { kind: 'unavailable', reason: 'preview' }; return; }
        if (safeMode) { state = { kind: 'unavailable', reason: 'safe-mode' }; return; }
        if (!consumers.length) return;
        if (Date.now() < retryAfterUntil) {
            state = { kind: 'unavailable', reason: 'rate-limited' };
            scheduleRetry();
            return;
        }
        if (!cacheLoaded) {
            state = { kind: 'starting' };
            loadPersistentCache(generation, songKey);
            return;
        }
        if (request && request.trackKey === songKey) return;
        state = { kind: 'starting' };
        lookup(false, generation, songKey, player);
    }
    function loadPersistentCache(token, requestedKey) {
        if (cacheLoading || !helperPath || preview || safeMode) {
            if (!cacheLoading) { cacheLoaded = true; lookup(false, token, requestedKey, player); }
            return;
        }
        cacheLoading = true;
        helper({ operation: 'lyrics-cache-read' }, function(result) {
            cacheLoading = false;
            cacheLoaded = true;
            if (result && result.ok && result.entries && typeof result.entries === 'object') {
                const now = Date.now();
                const records = {};
                const values = {};
                const keys = Object.keys(result.entries);
                for (let i = 0; i < keys.length; i++) {
                    const valid = Rules.validateLyricsCacheEntry(result.entries[keys[i]], now);
                    if (valid) { records[keys[i]] = valid; values[keys[i]] = valid.value; }
                }
                cacheRecords = records;
                cache = values;
                cacheKeys = Object.keys(records);
            }
            if (consumers.length) {
                if (token === generation && requestedKey === songKey) refresh();
                else refresh();
            }
        });
    }
    function helper(payload, done) {
        if (!helperPath) { done({ ok: false, reason: 'unavailable' }); return null; }
        const worker = cacheHelperComponent.createObject(root, { payload: payload });
        if (!worker) { done({ ok: false, reason: 'unavailable' }); return null; }
        helperRequests = helperRequests.concat([worker]);
        worker.finished.connect(function(result) {
            helperRequests = helperRequests.filter(function(item) { return item !== worker; });
            done(result);
        });
        worker.running = true;
        return worker;
    }
    function persistCache() {
        if (!helperPath || preview || safeMode) return;
        if (cacheWritePending) { cacheWriteDirty = true; return; }
        cacheWritePending = true;
        helper({ operation: 'lyrics-cache-write', entries: cacheRecords }, function() {
            cacheWritePending = false;
            if (cacheWriteDirty) { cacheWriteDirty = false; persistCache(); }
        });
    }
    function scheduleRetry() {
        if (!consumers.length || preview || safeMode || retryAfterUntil <= Date.now()) return;
        retryTimer.interval = Math.max(1, Math.min(2147483000, retryAfterUntil - Date.now()));
        retryTimer.start();
    }
    function lookup(search, token, trackKey, track) {
        var query = 'track_name=' + encodeURIComponent(track.title) + '&artist_name=' + encodeURIComponent(track.artist);
        if (!search && track.album) query += '&album_name=' + encodeURIComponent(track.album);
        if (!search && track.lengthMicros) query += '&duration=' + Math.round(track.lengthMicros / 1000000);
        request = workerComponent.createObject(root, {
            token: token, trackKey: trackKey, track: track, search: search,
            url: 'https://lrclib.net/api/' + (search ? 'search?' : 'get?') + query
        });
        if (request) request.running = true;
        else state = { kind: 'error', reason: 'unavailable' };
    }
    function completed(worker, code, timedOut, failedToStart) {
        if (worker.settled) return;
        worker.settled = true;
        var token = worker.token;
        var trackKey = worker.trackKey;
        var track = worker.track;
        var search = worker.search;
        var output = worker.stdout.text;
        var headers = worker.stderr.text;
        if (request === worker) request = null;
        worker.destroy();
        if (token !== generation || trackKey !== songKey || !consumers.length) return;
        if (failedToStart) {
            state = { kind: 'error', reason: 'start-failed' };
            return;
        }
        var footer = /\n(\d{3})$/.exec(output);
        var status = footer ? Number(footer[1]) : 0;
        if (status === 429) {
            rateLimitFailures++;
            var retryDelay = Rules.retryAfterDelay(headers, Date.now());
            if (retryDelay === null) retryDelay = Rules.lyricsBackoffDelay(rateLimitFailures - 1);
            retryDelay = Math.max(1000, retryDelay);
            retryAfterUntil = Date.now() + retryDelay;
            state = { kind: 'unavailable', reason: 'rate-limited' };
            scheduleRetry();
            return;
        }
        if (status === 404 && !search && !timedOut) { lookup(true, token, trackKey, track); return; }
        if (timedOut || code !== 0 || status !== 200 || output.length > 1048580) {
            state = { kind: 'error', reason: timedOut ? 'timeout' : 'lookup-failed',
                exitCode: code, httpStatus: status };
            return;
        }
        try {
            var payload = JSON.parse(output.slice(0, footer.index));
            var matchedRecord = search ? Rules.matchLyricsRecord(payload, track) : payload;
            var result = matchedRecord ? Rules.decodeLyrics(matchedRecord) : { lines: [], plain: '', instrumental: false };
            rateLimitFailures = 0;
            retryAfterUntil = 0;
            retryTimer.stop();
            var now = Date.now();
            var cacheRecord = { savedAt: now, negative: !result.instrumental && !result.lines.length && !result.plain.trim(), value: result };
            cache = Object.assign({}, cache, { [trackKey]: result });
            cacheRecords = Object.assign({}, cacheRecords, { [trackKey]: cacheRecord });
            cacheKeys = cacheKeys.filter(function(item) { return item !== trackKey; }).concat([trackKey]);
            while (cacheKeys.length > 64) {
                var expiredKey = cacheKeys.shift();
                var records = Object.assign({}, cacheRecords); delete records[expiredKey]; cacheRecords = records;
                var values = Object.assign({}, cache); delete values[expiredKey]; cache = values;
            }
            persistCache();
            state = { kind: 'ready', value: result };
        } catch (error) { state = { kind: 'error', reason: 'invalid-response' }; }
    }
    property Timer retryTimer: Timer {
        repeat: false
        onTriggered: {
            if (Date.now() < root.retryAfterUntil) root.scheduleRetry();
            else if (root.consumers.length) root.refresh();
        }
    }
    property Component cacheHelperComponent: Component {
        LyricsCacheRequest {
            helperPath: root.helperPath
            cacheRoot: root.cacheRoot
            payload: parent.payload
        }
    }
    property Component workerComponent: Component {
        Process {
            id: worker
            required property int token
            required property string trackKey
            required property var track
            required property bool search
            required property string url
            property bool settled: false
            property bool startedOnce: false
            command: ['curl', '--silent', '--show-error', '--proto', '=https', '--max-time', '12',
                '--connect-timeout', '5', '--max-filesize', '1048576', '--dump-header', '/dev/stderr',
                '--write-out', '\n%{http_code}',
                '--user-agent', 'Pentad/2 (desktop lyrics)', '--url', url]
            stdout: StdioCollector {}
            stderr: StdioCollector {}
            onStarted: startedOnce = true
            onRunningChanged: {
                if (!running && !startedOnce && !settled)
                    root.completed(worker, -1, false, true);
            }
            onExited: function(code, status) { root.completed(worker, code, false, false) }
            property Timer deadline: Timer {
                interval: 14000; running: true
                onTriggered: {
                    if (worker.running) worker.signal(9);
                    root.completed(worker, -1, true);
                }
            }
        }
    }
    Component.onDestruction: {
        cancel();
        helperRequests.slice().forEach(function(worker) {
            if (worker.running) worker.signal(9);
            worker.destroy();
        });
        helperRequests = [];
    }
}
