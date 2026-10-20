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
                var passed = root.created === 3 && root.disposed === 2
                    && root.identities.join(",") === "fixture-A,fixture-B,fixture-A"
                    && host.outputWindows.count === 1
                    && host.outputWindows.objectAt(0).shared === root.services;
                console.log("PENTAD_TEST " + JSON.stringify({ status: passed ? "pass" : "fail",
                    checks: [{ name: "add-remove-readd", passed: passed }],
                    created: root.created, disposed: root.disposed, outputIds: root.identities }));
                Qt.quit();
            }
        }
    }
}
