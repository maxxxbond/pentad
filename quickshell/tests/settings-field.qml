import QtQuick
import QtQuick.Window
import QtTest
import Quickshell
import qs.features.settings

ShellRoot {
    id: root
    property TestEvent pointer: TestEvent {}
    property var checks: []
    property var commits: []
    property var runActions: []
    property var reorders: []

    function check(name, passed, detail) {
        checks.push({ name: name, passed: passed === true, detail: detail || "" });
    }
    function finish() {
        console.log("PENTAD_TEST " + JSON.stringify({
            status: checks.length > 0 && checks.every(function(c) { return c.passed; }) ? "pass" : "fail",
            checks: checks,
        }));
        Qt.quit();
    }

    QtObject {
        id: controller
        property string pendingId: ""
        property string error: ""
        function commit(item, value) {
            root.commits = root.commits.concat([{ key: item.key, value: value }]);
            return "req-" + root.commits.length;
        }
        function runAction(name) { root.runActions = root.runActions.concat([name]); return true; }
    }

    FloatingWindow {
        id: win
        width: 480
        height: 480
        visible: true
        Column {
            anchors.fill: parent
            spacing: 8
            SettingsField {
                id: toggleField
                width: parent.width
                controller: controller
                documents: ({ notifications: { dnd: false } })
                item: ({ key: "dnd", kind: "boolean", control: "toggle", document: "notifications", path: "dnd",
                    labelUk: "Не турбувати", labelEn: "Do not disturb", default: false })
            }
            SettingsField {
                id: decimalField
                width: parent.width
                controller: controller
                documents: ({ layout: { lat: 50.5 } })
                item: ({ key: "lat", kind: "number", control: "stepper", document: "layout", path: "lat",
                    labelUk: "Широта", labelEn: "Latitude", default: 0, min: -90, max: 90, step: 0.5 })
            }
            SettingsField {
                id: cardsField
                width: parent.width
                controller: controller
                documents: ({ theme: { appearance: "dark", accent: "#869677" } })
                item: ({ key: "appearance", kind: "select", control: "cards", document: "theme", path: "appearance",
                    labelUk: "Тема", labelEn: "Theme", default: "dark",
                    options: [{ value: "dark", labelUk: "Темна", labelEn: "Dark" }, { value: "light", labelUk: "Світла", labelEn: "Light" }] })
            }
            SettingsField {
                id: colorField
                width: parent.width
                controller: controller
                documents: ({ theme: { accent: "#869677" } })
                item: ({ key: "accent", kind: "color", control: "color", document: "theme", path: "accent",
                    labelUk: "Акцент", labelEn: "Accent", default: "#869677" })
            }
            SettingsOptionList {
                id: list
                width: parent.width
                model: [{ id: "a", label: "A" }, { id: "b", label: "B" }, { id: "c", label: "C" }]
                onReordered: function(ids) { root.reorders = root.reorders.concat([ids]); }
            }
        }

        TestCase {
            id: testCase
            name: "settings-field"
            when: false
            function test_all() {
                wait(50);
                const toggle = toggleField.controlItem;
                root.check("toggle-rendered", toggle !== null && toggle.checked === false);
                toggle.click();
                root.check("toggle-commits-once", root.commits.length === 1 && root.commits[0].key === "dnd"
                    && root.commits[0].value === true, JSON.stringify(root.commits));

                controller.pendingId = "req-1";
                wait(0);
                root.check("pending-id-disables-control", toggle.enabled === false);
                controller.pendingId = "";
                wait(0);
                root.check("pending-clear-reverts-to-confirmed", toggle.checked === false && toggle.enabled === true);

                const decimal = decimalField.controlItem;
                root.check("decimal-stepper-shows-fraction", decimal.decimals === 3 && decimal.value === 50500 && decimal.realValue === 50.5
                    && decimal.textFromValue(decimal.value, Qt.locale("en_US")) === "50.500", String(decimal.value));
                decimal.value = decimal.valueFromText("12.345", Qt.locale("en_US"));
                decimal.valueModified();
                root.check("decimal-stepper-commits-fraction", root.commits.some(function(c) { return c.key === "lat" && c.value === 12.345; }),
                    JSON.stringify(root.commits));
                decimal.value = 100000;
                root.check("decimal-stepper-clamps-to-range", decimal.value === 90000 && decimal.realValue === 90, String(decimal.value));

                const cards = cardsField.controlItem;
                root.check("cards-selected", cards.currentIndex === 0);
                cards.repeater.itemAt(1).forceActiveFocus();
                root.pointer.keyClick(Qt.Key_Space, Qt.NoModifier, 0);
                root.check("cards-space-commits", root.commits.some(function(c) { return c.key === "appearance" && c.value === "light"; }), JSON.stringify(root.commits));

                const color = colorField.controlItem;
                color.input.forceActiveFocus();
                color.input.text = "red";
                root.check("color-invalid-not-committed", color.invalid === true && color.commit() === false);
                color.revert();
                root.check("color-esc-reverts", color.input.text === "#869677");

                const row = list.repeater.itemAt(0);
                row.forceActiveFocus();
                root.pointer.keyClick(Qt.Key_Down, Qt.AltModifier, 0);
                root.check("alt-down-reorders", root.reorders.length === 1
                    && root.reorders[0].join(",") === "b,a,c", JSON.stringify(root.reorders));
                list.repeater.itemAt(0).forceActiveFocus();
                root.pointer.keyClick(Qt.Key_Up, Qt.AltModifier, 0);
                root.check("alt-up-at-top-is-noop", root.reorders.length === 1);
                root.finish();
            }
        }
        Timer {
            interval: 300
            running: true
            repeat: false
            onTriggered: testCase.test_all()
        }
    }
}
