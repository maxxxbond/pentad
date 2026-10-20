import QtQuick
import QtQml
import Quickshell.Io
import '../logic/weather.mjs' as WeatherLogic

QtObject {
    id: root
    required property bool preview
    required property bool safeMode
    property var fetchJsonOverride: null
    signal stateChanged(string key, var state)

    readonly property var manager: WeatherLogic.createWeatherManager({
        fetchJson: function(url, cancellation) { return root.fetchJson(url, cancellation); },
        now: function() { return Date.now(); },
        language: function() { return Qt.locale().name.split('_')[0].toLowerCase(); },
        every: function(milliseconds, callback) { return root.every(milliseconds, callback); },
        changed: function(key, state) { root.stateChanged(key, state); }
    })

    function acquire(config) { return manager.acquire(config); }
    function read(handle) { return manager.read(handle); }
    function refresh(handle) { return manager.refresh(handle); }
    function release(handle) { manager.release(handle); }
    function searchCities(query, cancellation) { return manager.searchCities(query, cancellation); }

    function every(milliseconds, callback) {
        const timer = timerFactory.createObject(root, { interval: milliseconds, repeat: false });
        if (!timer) return function() {};
        timer.triggered.connect(callback);
        timer.start();
        return function() {
            timer.stop();
            timer.destroy();
        };
    }

    function fetchJson(url, cancellation) {
        if (root.fetchJsonOverride) return root.fetchJsonOverride(url, cancellation);
        return new Promise(function(resolve, reject) {
            if (root.preview || root.safeMode) {
                reject(new Error('Weather requests are disabled in preview and safe mode.'));
                return;
            }
            if (cancellation.isCancelled()) {
                reject(new Error('Weather request cancelled.'));
                return;
            }
            const worker = requestFactory.createObject(root, { url: url });
            if (!worker) {
                reject(new Error('Weather request could not start.'));
                return;
            }
            let settled = false;
            let stopCancellation = function() {};
            function settle(ok, value, message) {
                if (settled) return;
                settled = true;
                stopCancellation();
                if (ok) resolve(value);
                else reject(new Error(message || 'Weather service is unavailable.'));
            }
            worker.completed.connect(function(ok, value, message) {
                settle(ok, value, message);
            });
            stopCancellation = cancellation.subscribe(function() {
                worker.cancel();
                settle(false, null, 'Weather request cancelled.');
            });
            worker.running = true;
        });
    }

    property Component requestFactory: Component { WeatherRequest {} }
    property Component timerFactory: Component { Timer {} }
    Component.onDestruction: manager.dispose()
}
