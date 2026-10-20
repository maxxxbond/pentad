import QtQuick
import QtQml
import Quickshell
import Quickshell.Io
import qs.services
import "../services"

ShellRoot {
    id: root
    property var checks: []
    property int phase: 0
    property string firstId: ""
    property string secondId: ""
    property var completed: ({})
    property Config store: Config { preview: false }
    property Activities activityStore: Activities { config: root.store }
    property FileView persisted: FileView { path: root.store.stateRoot + "/activity.json"; watchChanges: false; printErrors: false }

    function check(name, passed, detail) { checks.push({ name: name, passed: passed === true, detail: detail || "" }); }
    function finish() {
        const passed = checks.length > 0 && checks.every(item => item.passed);
        console.log("PENTAD_TEST " + JSON.stringify({ status: passed ? "pass" : "fail", checks: checks }));
        activityStore.dispose();
        Qt.quit();
    }

    Connections {
        target: root.activityStore
        function onCommandFinished(requestId, result) {
            root.completed[requestId] = result;
            if (root.phase === 1 && requestId === root.firstId) {
                root.check("start-settles-after-config-persist", result.ok && root.activityStore.activities.length === 1
                    && root.store.documents.activity.activities[0].id === "build", JSON.stringify(result));
                root.check("generated-request-id-correlates", /^activity-[1-9][0-9]*$/.test(requestId));
                root.firstId = root.activityStore.update("build", { progress: 0.5, detail: "Halfway", ttl: 30 });
                root.secondId = root.activityStore.start("package", "Package", { kind: "task" });
                root.check("queued-writes-do-not-publish-early", root.activityStore.activities.length === 1
                    && root.activityStore.activities[0].progress === 0);
                root.phase = 2;
            } else if (root.phase === 2 && root.completed[root.firstId] && root.completed[root.secondId]) {
                root.check("serialized-update-preserves-title-and-other-ID", root.completed[root.firstId].ok
                    && root.completed[root.secondId].ok && root.activityStore.activities.length === 2
                    && root.activityStore.activities.find(item => item.id === "build").title === "Build"
                    && root.activityStore.activities.find(item => item.id === "build").progress === 0.5
                    && root.store.documents.activity.activities.some(item => item.id === "package"));
                root.activityStore.timerState = { status: "idle" };
                root.activityStore.player = { playback: "paused" };
                root.check("task-priority-over-paused-media", root.activityStore.state.kind === "task");
                root.firstId = root.activityStore.end("build");
                root.secondId = root.activityStore.end("package");
                root.phase = 3;
            } else if (root.phase === 3 && root.completed[root.firstId] && root.completed[root.secondId]) {
                root.check("end-commits-empty-activity-document", root.completed[root.firstId].ok
                    && root.completed[root.secondId].ok && root.activityStore.activities.length === 0
                    && root.store.documents.activity.activities.length === 0);
                root.firstId = root.activityStore.start("notice", "Notice", { kind: "notification", ttl: 1 });
                root.phase = 4;
            } else if (root.phase === 4 && requestId === root.firstId) {
                root.check("notification-default-state-and-dnd-selection", result.ok
                    && root.activityStore.state.kind === "notification");
                root.activityStore.dnd = true;
                root.check("notification-respects-dnd-with-paused-media", root.activityStore.state.kind === "media");
                root.activityStore.dnd = false;
                expiryWaiter.start();
                root.phase = 5;
            }
        }
    }

    Timer {
        interval: 30
        running: true
        repeat: true
        property int ticks: 0
        onTriggered: {
            if (root.phase === 0 && root.activityStore.ready) {
                if (root.activityStore.loadError) {
                    root.check("activity-config-load", false, root.activityStore.loadError);
                    root.finish();
                    return;
                }
                root.check("missing-temp-document-loads-as-empty", root.activityStore.activities.length === 0
                    && root.activityStore.document.schemaVersion === 1 && !root.activityStore.loadError);
                root.firstId = root.activityStore.start("build", "Build", { progress: 0, ttl: 30 });
                root.check("start-does-not-optimistically-publish", root.activityStore.activities.length === 0);
                root.phase = 1;
            } else if (root.phase > 0 && ticks++ > 400) {
                root.check("activity-native-fixture-deadline", false, "phase " + root.phase);
                root.finish();
            }
        }
    }

    Timer {
        id: expiryWaiter
        interval: 30
        repeat: true
        property int ticks: 0
        onTriggered: {
            if (!root.activityStore.activities.length && !root.activityStore.expiryTimer.running
                && root.store.documents.activity.activities.length === 0) {
                stop();
                root.persisted.reload();
                diskVerify.start();
            } else if (expiryWaiter.ticks++ > 100) {
                stop();
                root.check("activity-expiry-prunes-document-and-stops-timer", false);
                root.finish();
            }
        }
    }

    Timer {
        id: diskVerify
        interval: 100
        repeat: false
        onTriggered: {
            let disk = null;
            try { disk = JSON.parse(root.persisted.text()); } catch (error) {}
            root.check("confirmed-activity-document-is-persisted-on-disk", !!disk
                && disk.schemaVersion === 1 && disk.activities.length === 0, JSON.stringify(disk));
            root.check("expiry-timer-remains-stopped-when-empty", !root.activityStore.expiryTimer.running);
            root.finish();
        }
    }

    Timer {
        interval: 20000
        running: true
        onTriggered: { root.check("activity-fixture-finished-before-timeout", false); root.finish(); }
    }
}
