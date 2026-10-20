import QtQuick
import Quickshell
import qs.services

ShellRoot {
    id: root
    readonly property string fixtureHelper: Quickshell.env('XDG_CONFIG_HOME') + '/quickshell-fixture/helpers/pentad-files.py'
    property Artwork artworkService: Artwork {
        helperPath: root.fixtureHelper
        preview: false
        safeMode: false
    }
    property Artwork missingCurlService: Artwork {
        helperPath: root.fixtureHelper
        curlExecutable: '/pentad-test/does-not-exist/curl'
    }
    property Artwork missingHelperService: Artwork {
        helperPath: '/pentad-test/does-not-exist/pentad-files.py'
    }
    property var checks: []
    property bool raceRequested: false
    property bool fallbackRequested: false
    property bool cacheRemovalRequested: false
    property bool failureChecksStarted: false
    property var removedCacheId: null

    function removeCacheFile(requestId, done) {
        var worker = helperComponent.createObject(root, {
            payload: { operation: 'artwork-remove', requestId: requestId }
        });
        if (!worker) { done(false); return; }
        worker.finished.connect(function(result) { done(!!result.ok); });
        worker.running = true;
    }

    property Component helperComponent: Component {
        ArtworkRequest {
            helperPath: root.fixtureHelper
            configRoot: (Quickshell.env('XDG_CONFIG_HOME') || '') + '/pentad'
            stateRoot: (Quickshell.env('XDG_STATE_HOME') || '') + '/pentad'
            cacheRoot: Quickshell.env('XDG_CACHE_HOME') || ''
            payload: parent.payload
        }
    }

    FloatingWindow {
        visible: true
        implicitWidth: 320
        implicitHeight: 180
        Image {
            id: cover
            anchors.centerIn: parent
            width: 96
            height: 96
            source: root.artworkService.stateFor('race').source
            sourceSize.width: 512
            sourceSize.height: 512
            cache: false
        }
    }

    Timer {
        interval: 50
        repeat: true
        running: true
        onTriggered: {
            if (!root.raceRequested) {
                root.raceRequested = true;
                root.artworkService.request('race', ['https://fixture.invalid/slow'], 'track-a');
            } else if (!root.fallbackRequested) {
                root.fallbackRequested = true;
                root.artworkService.request('fallback', [
                    'https://fixture.invalid/not-found', 'https://fixture.invalid/fallback'
                ], 'fallback-track');
            } else if (root.checks.length === 0 && cover.status === Image.Ready
                    && root.artworkService.stateFor('fallback').kind === 'ready') {
                var race = root.artworkService.stateFor('race');
                var fallback = root.artworkService.stateFor('fallback');
                root.checks.push({ name: 'same-url-track-switch-cancels-stale-request', passed:
                    race.kind === 'ready' && race.requestUrl === 'https://fixture.invalid/slow'
                    && race.key === JSON.stringify({ urls: ['https://fixture.invalid/slow'], track: 'track-b' }) });
                root.checks.push({ name: 'failed-http-source-uses-next-cover', passed:
                    fallback.kind === 'ready' && fallback.requestUrl === 'https://fixture.invalid/fallback' });
                var cached = root.artworkService.cache['https://fixture.invalid/fallback'];
                if (!cached) {
                    root.checks.push({ name: 'cache-entry-created', passed: false });
                } else {
                    root.removedCacheId = cached.requestId;
                    root.checks.push({ name: 'cache-request-id-preserves-wide-integer', passed:
                        root.removedCacheId === cached.requestId && root.removedCacheId > 2147483647 });
                    root.cacheRemovalRequested = true;
                    root.removeCacheFile(root.removedCacheId, function(ok) {
                        root.checks.push({ name: 'cache-entry-removed-by-helper', passed: ok });
                        if (ok) root.artworkService.request('cache-reload',
                            ['https://fixture.invalid/fallback'], 'cache-reload-track');
                    });
                }
            } else if (root.checks.length >= 3 && !root.failureChecksStarted
                    && root.artworkService.stateFor('cache-reload').kind === 'ready') {
                var reloaded = root.artworkService.cache['https://fixture.invalid/fallback'];
                root.checks.push({ name: 'cache-refetch-allocates-distinct-wide-request-id', passed:
                    !!reloaded && reloaded.requestId > 2147483647 && reloaded.requestId !== root.removedCacheId });
                root.checks.push({ name: 'missing-cache-file-refetches-same-candidate', passed:
                    !!reloaded && reloaded.requestId !== root.removedCacheId
                    && root.artworkService.stateFor('cache-reload').requestUrl === 'https://fixture.invalid/fallback' });
                root.failureChecksStarted = true;
                root.artworkService.request('oversize', [
                    'https://fixture.invalid/oversize', 'https://fixture.invalid/fallback'
                ], 'oversize-track');
                root.missingCurlService.request('missing-curl', ['https://fixture.invalid/missing-curl'], 'missing-curl-track');
                root.missingHelperService.request('missing-helper', ['https://fixture.invalid/missing-helper'], 'missing-helper-track');
            } else if (root.failureChecksStarted
                    && root.artworkService.stateFor('oversize').kind === 'ready'
                    && root.missingCurlService.stateFor('missing-curl').kind === 'unavailable'
                    && root.missingHelperService.stateFor('missing-helper').kind === 'unavailable') {
                root.checks.push({ name: 'oversize-response-is-rejected-and-falls-back', passed:
                    root.artworkService.stateFor('oversize').requestUrl === 'https://fixture.invalid/fallback' });
                root.checks.push({ name: 'missing-curl-settles-and-cleans-request', passed:
                    !root.missingCurlService.requests['missing-curl'] });
                root.checks.push({ name: 'missing-helper-settles-and-cleans-request', passed:
                    !root.missingHelperService.requests['missing-helper'] });
                var privateSource = root.artworkService.stateFor('race').source;
                root.checks.push({ name: 'cover-decodes-from-private-file-cache', passed:
                    privateSource.indexOf('/pentad/artwork/cover-') >= 0 && cover.status === Image.Ready });
                root.artworkService.release('race');
                root.artworkService.release('fallback');
                root.artworkService.release('cache-reload');
                root.artworkService.release('oversize');
                root.missingCurlService.release('missing-curl');
                root.missingHelperService.release('missing-helper');
                root.checks.push({ name: 'consumer-release-clears-state', passed:
                    root.artworkService.stateFor('race').kind === 'unavailable' });
                console.log('PENTAD_TEST ' + JSON.stringify({ status:
                    root.checks.every(function(item) { return item.passed }) ? 'pass' : 'fail', checks: root.checks }));
                Qt.quit();
            }
        }
    }

    Timer {
        interval: 250
        running: true
        repeat: false
        onTriggered: root.artworkService.request('race', ['https://fixture.invalid/slow'], 'track-b');
    }
    Timer {
        interval: 15000
        running: true
        repeat: false
        onTriggered: {
            if (!root.checks.length || !root.checks.every(function(item) { return item.passed })) {
                console.log('PENTAD_TEST ' + JSON.stringify({ status: 'fail', name: 'artwork-timeout', checks: root.checks }));
                Qt.quit();
            }
        }
    }
    Component.onDestruction: {
        root.artworkService.release('race');
        root.artworkService.release('fallback');
        root.artworkService.release('cache-reload');
        root.artworkService.release('oversize');
        root.missingCurlService.release('missing-curl');
        root.missingHelperService.release('missing-helper');
    }
}
