import QtQuick
import QtQuick.Window
import QtQuick.Controls.Basic
import QtTest
import "../components"

TestCase {
    name: "MenuPointerIntent"

    Window {
        id: fixtureWindow
        width: 400
        height: 300
        visible: true

        Rectangle {
            id: anchor
            x: 20
            y: 130
            width: 60
            height: 40
        }

        Rectangle {
            id: surface
            x: 220
            y: 100
            width: 120
            height: 100
            Item {
                id: pointerField
                anchors.fill: parent
            }
            Item {
                id: menuContent
                parent: pointerField
                anchors.fill: parent
                Button {
                    id: menuButton
                    anchors.fill: parent
                    hoverEnabled: true
                    text: "Menu action"
                }
            }
        }

        MenuPointerIntent {
            id: intent
            anchorItem: anchor
            surfaceItem: pointerField
            active: true
        }

        MenuPointerIntent {
            id: childIntent
            parentIntent: intent
            active: false
            onDismissRequested: active = false
        }
    }

    SignalSpy {
        id: dismissSpy
        target: intent
        signalName: "dismissRequested"
    }

    SignalSpy {
        id: childDismissSpy
        target: childIntent
        signalName: "dismissRequested"
    }

    function prepare(previousOffset) {
        const target = surface.mapToGlobal(0, 0)
        const origin = { x: target.x - 120, y: target.y + surface.height / 2 }
        intent.cancelLeave()
        intent.armed = true
        intent.draggingOutside = false
        intent.anchorHovered = false
        intent.surfaceHovered = false
        intent.openChildren = 0
        intent.dismissedByPointer = false
        intent.previousPoint = { x: origin.x + previousOffset, y: origin.y }
        intent.lastPoint = origin
        childIntent.dismissedByPointer = false
        intent.graceMs = 300
        dismissSpy.clear()
        childDismissSpy.clear()
    }

    function test_leaveTowardTargetDefersClose() {
        prepare(-20)
        intent.beginLeave(surface)

        verify(intent.startedAt > 0)
        compare(intent.aimTargetItem, surface)
        compare(dismissSpy.count, 0)
    }

    function test_leaveAwayFromTargetClosesImmediately() {
        prepare(20)
        intent.beginLeave(surface)

        compare(dismissSpy.count, 1)
        compare(intent.startedAt, 0)
        compare(intent.aimTargetItem, null)
    }

    function test_childPointerDismissPropagatesWithoutAnotherGracePeriod() {
        prepare(-20)
        childIntent.active = true
        childIntent.enterChain()
        verify(childIntent.registeredParent === intent)
        compare(intent.openChildren, 1)

        childIntent.requestDismiss()

        compare(childDismissSpy.count, 1)
        compare(dismissSpy.count, 1)
        compare(intent.dismissedByPointer, true)
        compare(intent.openChildren, 0)
        compare(intent.startedAt, 0)
    }

    function test_keyboardOpenedMenuDoesNotArmPointerDismissal() {
        prepare(-20)
        intent.armed = false

        intent.leaveItem(anchor, Qt.NoButton)

        compare(intent.startedAt, 0)
        compare(dismissSpy.count, 0)
    }

    function test_stationaryGapUsesOneFixedDeadline() {
        prepare(-20)
        intent.graceMs = 60
        intent.beginLeave(surface)
        const origin = intent.lastGlobalPoint
        const surfaceGlobal = surface.mapToGlobal(0, 0)
        const outsideSurface = { x: origin.x - surfaceGlobal.x, y: origin.y - surfaceGlobal.y }
        const deadlineStartedAt = intent.startedAt
        verify(deadlineStartedAt > 0)

        const sampleStartedAt = Date.now()
        while (Date.now() - sampleStartedAt < 110 && dismissSpy.count === 0) {
            intent.observePoint(surface, outsideSurface)
            wait(10)
        }

        compare(intent.startedAt, 0)
        compare(dismissSpy.count, 1)
        wait(70)
        compare(dismissSpy.count, 1)
    }

    function test_enteringActualTargetCancelsPendingExpiry() {
        prepare(-20)
        intent.graceMs = 60
        intent.beginLeave(surface)
        verify(intent.startedAt > 0)

        intent.observePoint(surface, { x: surface.width / 2, y: surface.height / 2 })
        compare(intent.startedAt, 0)
        wait(100)

        compare(dismissSpy.count, 0)
    }

    function test_enteringMenuButtonCancelsExpiry() {
        fixtureWindow.requestActivate()
        mouseMove(anchor, anchor.width / 2, anchor.height / 2)
        tryCompare(intent, "anchorHovered", true)
        prepare(-20)
        intent.graceMs = 100
        intent.beginLeave(pointerField)
        verify(intent.startedAt > 0)
        mouseMove(menuButton, menuButton.width / 2, menuButton.height / 2)
        tryCompare(menuButton, "hovered", true)
        compare(intent.surfaceHovered, true)
        compare(intent.startedAt, 0)
        wait(150)
        compare(dismissSpy.count, 0)
    }
}
