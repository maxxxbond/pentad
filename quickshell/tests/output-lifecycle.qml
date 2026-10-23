pragma ComponentBehavior: Bound
import QtQuick
import QtQml
import Quickshell
import "../services"
import "../shell"

ShellRoot {
    id: root
    property Services services: Services { preview: true }
    property int created: 0
    property int disposed: 0
    property var identities: []
    property int step: 0
    property int stashFocusRequests: 0
    property var stashResult: null
    Connections {
        target: root.services.stash
        function onFocusRequested() { root.stashFocusRequests++; }
    }
    // In 'window' mode the shortcut (toggle) focuses an open Stash window instead of hiding it;
    // in 'overlay' mode it still closes the overlay.
    function checkStashToggle() {
        const stash = root.services.stash;
        const config = root.services.config;
        const withMode = function(mode) {
            config.documents = Object.assign({}, config.documents, {
                interface: Object.assign({}, config.documents.interface, { stashWindow: mode })
            });
        };
        withMode('window');
        const windowMode = stash.mode;
        stash.show();
        stash.toggle();
        const windowKept = stash.visible && root.stashFocusRequests === 1;
        withMode('overlay');
        stash.toggle();
        const overlayHidden = !stash.visible && root.stashFocusRequests === 1;
        stash.toggle();
        const overlayShown = stash.visible && root.stashFocusRequests === 1;
        stash.hide();
        root.stashResult = { windowMode: windowMode, focusRequests: root.stashFocusRequests,
            passed: windowMode === 'window' && windowKept && overlayHidden && overlayShown };
    }
    OutputHost {
        id: host
        services: root.services
        outputs: []
        surfaceComponent: Component {
            QtObject {
                required property var modelData
                readonly property var shared: host.services
                Component.onCompleted: {
                    root.created++;
                    root.identities = root.identities.concat([modelData.name]);
                }
                Component.onDestruction: root.disposed++
            }
        }
    }
    Timer {
        interval: 30; running: true; repeat: true
        onTriggered: {
            root.step++;
            if (root.step === 1) host.outputs = [{ name: "fixture-A" }, { name: "fixture-B" }];
            if (root.step === 2) host.outputs = [];
            if (root.step === 3) host.outputs = [{ name: "fixture-A" }];
            if (root.step === 4) {
                root.checkStashToggle();
                var passed = root.created === 3 && root.disposed === 2
                    && root.identities.join(",") === "fixture-A,fixture-B,fixture-A"
                    && host.outputWindows.count === 1
                    && host.outputWindows.objectAt(0).shared === root.services;
                console.log("PENTAD_TEST " + JSON.stringify({
                    status: passed && root.stashResult.passed ? "pass" : "fail",
                    checks: [{ name: "add-remove-readd", passed: passed },
                        { name: "stash-toggle-focuses-window", passed: root.stashResult.passed }],
                    stash: root.stashResult,
                    created: root.created, disposed: root.disposed, outputIds: root.identities }));
                Qt.quit();
            }
        }
    }
}
