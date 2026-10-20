pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Wayland
import QtQuick.Window
import "../logic/menu-aim.mjs" as MenuAim

PanelWindow {
    id: root

    property var intent: null
    property var targetScreen: null
    property bool debugEnabled: false
    property bool debugActive: false

    screen: targetScreen
    visible: debugEnabled && debugActive
    color: "transparent"
    anchors { top: true; left: true; right: true; bottom: true }
    exclusiveZone: 0
    exclusionMode: ExclusionMode.Normal
    margins.top: intent ? -intent.topReservation : 0
    mask: Region {}
    WlrLayershell.namespace: "pentad-menu-pointer-debug"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    onDebugActiveChanged: canvas.requestPaint()

    Timer {
        interval: 40
        repeat: true
        running: root.visible && root.debugActive
        onTriggered: canvas.requestPaint()
    }

    Canvas {
        id: canvas
        anchors.fill: parent
        renderTarget: Canvas.FramebufferObject

        function localX(x) { return root.intent && root.intent.coordinateItem ? x : x - (root.targetScreen ? root.targetScreen.x : 0) }
        function localY(y) { return root.intent && root.intent.coordinateItem ? y : y - (root.targetScreen ? root.targetScreen.y : 0) }

        function drawRect(ctx, rect, stroke, fill, dashed) {
            if (!rect || rect.width <= 0 || rect.height <= 0) return
            const x = localX(rect.x), y = localY(rect.y)
            ctx.beginPath()
            ctx.rect(x, y, rect.width, rect.height)
            ctx.fillStyle = fill
            ctx.fill()
            ctx.setLineDash(dashed ? [6, 4] : [])
            ctx.lineWidth = 2
            ctx.strokeStyle = stroke
            ctx.stroke()
            ctx.setLineDash([])
        }

        onPaint: {
            const ctx = getContext("2d")
            ctx.clearRect(0, 0, width, height)
            const anchor = root.intent ? root.intent.itemRect(root.intent.anchorItem) : null
            const surface = root.intent ? root.intent.itemRect(root.intent.surfaceItem) : null
            const aimTarget = root.intent && root.intent.aimTargetItem
                ? root.intent.aimTargetItem : (root.intent ? root.intent.surfaceItem : null)
            const target = root.intent && aimTarget ? root.intent.itemRect(aimTarget) : null
            const corridor = root.intent && target
                ? root.intent.aimCorridor(aimTarget, root.intent.intentOrigin) : null
            const alpha = 0.22

            drawRect(ctx, anchor, "rgba(64, 255, 112, 0.95)", `rgba(64, 255, 112, ${alpha})`, false)
            drawRect(ctx, surface, "rgba(64, 255, 112, 0.95)", `rgba(64, 255, 112, ${alpha})`, false)

            if (corridor) {
                if (corridor.sourceRect)
                    drawRect(ctx, corridor.sourceRect, "rgba(64, 255, 112, 0.95)",
                        "rgba(64, 255, 112, 0.18)", false)
                ctx.beginPath()
                const points = corridor.points || [corridor.a, corridor.b, corridor.c, corridor.d].filter(Boolean)
                ctx.moveTo(localX(points[0].x), localY(points[0].y))
                for (let index = 1; index < points.length; index++)
                    ctx.lineTo(localX(points[index].x), localY(points[index].y))
                ctx.closePath()
                ctx.fillStyle = "rgba(64, 255, 112, 0.18)"
                ctx.fill()
                ctx.lineWidth = 2
                ctx.setLineDash([])
                ctx.strokeStyle = "rgba(64, 255, 112, 0.95)"
                ctx.stroke()
                ctx.setLineDash([])
            }
            if (target) {
                const buffer = root.intent ? root.intent.buffer : 4
                drawRect(ctx, { x: target.x - buffer, y: target.y - buffer,
                    width: target.width + 2 * buffer, height: target.height + 2 * buffer },
                    "rgba(64, 255, 112, 0.85)", "rgba(64, 255, 112, 0.04)", true)
            }

            const point = root.intent ? root.intent.lastGlobalPoint : null
            if (point) {
                const inside = (anchor && MenuAim.pointInRect(point, anchor))
                    || (surface && MenuAim.pointInRect(point, surface))
                    || (corridor && MenuAim.pointInCorridor(point, corridor))
                const color = inside ? "#40ff70" : "#ff5263"
                ctx.beginPath()
                ctx.arc(localX(point.x), localY(point.y), 6, 0, Math.PI * 2)
                ctx.fillStyle = color
                ctx.fill()
                ctx.lineWidth = 2
                ctx.strokeStyle = "white"
                ctx.stroke()
            }

            if (root.intent) {
                const insideNow = (root.intent.lastGlobalPoint && anchor
                    && MenuAim.pointInRect(root.intent.lastGlobalPoint, anchor))
                    || (root.intent.lastGlobalPoint && surface
                    && MenuAim.pointInRect(root.intent.lastGlobalPoint, surface))
                const inSafeRegion = root.intent.lastGlobalPoint && corridor
                    && MenuAim.pointInCorridor(root.intent.lastGlobalPoint, corridor)
                const elapsed = root.intent.intentStartedAt > 0
                    ? Math.max(0, Date.now() - root.intent.intentStartedAt) : 0
                const status = insideNow ? "inside anchor/menu"
                    : inSafeRegion ? "inside safe region"
                    : root.intent.intentStartedAt > 0 ? `outside · ${Math.max(0, root.intent.graceMs - elapsed)} ms`
                    : "outside"
                ctx.font = "13px sans-serif"
                ctx.fillStyle = "rgba(64, 255, 112, 0.98)"
                ctx.fillText(status, 18, 28)
            }
        }
    }
}
