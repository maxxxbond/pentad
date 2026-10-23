pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Window
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import "../logic/menu-aim.mjs" as MenuAim

Item {
    id: root

    property Item anchorItem: null
    property Item surfaceItem: null
    property Item coordinateItem: null
    property point coordinateOrigin: Qt.point(0, 0)
    property real topReservation: 0
    property bool useAnchorCorridor: false
    property bool debugEnabled: false
    property bool active: false
    property bool pointerDismissEnabled: true
    property int graceMs: 350
    property int buffer: 4
    property real farDismissDistance: 80
    // Outside the menu surfaces points come only from the cursor poll, so a point stays fresh
    // for two poll intervals; a shorter age would let jitter discard every gap sample.
    property int freshPointMaxAge: 2 * cursorPoll.interval
    property var parentIntent: null
    property var inputRegion: null
    property point inputRegionOrigin: Qt.point(0, 0)
    readonly property bool pointerArmed: armed
    readonly property bool aimingAtTarget: aimTargetItem !== null
        && pointInSafeRegion(lastGlobalPoint, aimTargetItem)
    readonly property var lastGlobalPoint: lastPoint
    readonly property var previousGlobalPoint: previousPoint
    readonly property double intentStartedAt: startedAt
    readonly property var debugAnchorRect: itemRect(anchorItem)
    readonly property var debugSurfaceRect: itemRect(surfaceItem)
    readonly property var debugAimCorridor: aimTargetItem && intentOrigin
        ? aimCorridor(aimTargetItem, intentOrigin) : null
    readonly property var debugAimTargetRect: aimTargetItem ? itemRect(aimTargetItem) : null
    property var debugDismissedGeometry: null

    property bool armed: false
    property bool motionObserved: false
    property bool anchorHovered: false
    property bool surfaceHovered: false
    property bool draggingOutside: false
    property bool dismissedByPointer: false
    property bool targetReached: false
    property int openChildren: 0
    property var childIntents: []
    property int legacyChildCount: 0
    property var lastPoint: null
    property var previousPoint: null
    property var lastInsidePoint: null
    property double lastObservedAt: 0
    property var intentOrigin: null
    property Item aimTargetItem: null
    property double startedAt: 0
    property var registeredParent: null
    property string cursorReplyBuffer: ""
    property bool cursorRequestInFlight: false
    property bool cursorRequestSent: false
    property int cursorGeneration: 0
    property int socketGeneration: -1
    property bool cursorAwaitingDisconnect: false
    readonly property bool samplerRoot: !parentIntent

    signal dismissRequested()
    signal aimDeferred()

    function trace(event, reason) {
        if (!root.debugEnabled) return;
        const rows = inputRegion && inputRegion.rows ? inputRegion.rows : [];
        let maskBounds = null;
        for (const row of rows) {
            if (!row) continue;
            if (!maskBounds) maskBounds = { x: row.x, y: row.y, right: row.x + row.width, bottom: row.y + row.height };
            else {
                maskBounds.x = Math.min(maskBounds.x, row.x);
                maskBounds.y = Math.min(maskBounds.y, row.y);
                maskBounds.right = Math.max(maskBounds.right, row.x + row.width);
                maskBounds.bottom = Math.max(maskBounds.bottom, row.y + row.height);
            }
        }
        if (maskBounds) {
            maskBounds.width = maskBounds.right - maskBounds.x;
            maskBounds.height = maskBounds.bottom - maskBounds.y;
            delete maskBounds.right;
            delete maskBounds.bottom;
        }
        const maskPoint = lastPoint ? { x: lastPoint.x - inputRegionOrigin.x,
            y: lastPoint.y - inputRegionOrigin.y } : null;
        console.info("PENTAD_MENU_POINTER", JSON.stringify({ event: event, reason: reason || "",
            anchorHovered: root.anchorHovered, surfaceHovered: root.surfaceHovered,
            armed: root.armed, dragging: root.draggingOutside, children: root.openChildren,
            startedAt: root.startedAt, point: root.lastPoint,
            anchor: root.itemRect(root.anchorItem), surface: root.itemRect(root.surfaceItem),
            maskRows: rows.length, maskBounds: maskBounds, maskPoint: maskPoint,
            maskContainsLastPoint: !!(maskPoint && inputRegion && inputRegion.containsPoint
                && inputRegion.containsPoint(maskPoint.x, maskPoint.y)),
            maskContains8pxBelow: !!(maskPoint && inputRegion && inputRegion.containsPoint
                && inputRegion.containsPoint(maskPoint.x, maskPoint.y + 8)) }));
    }

    function itemRect(item) {
        if (!item || !item.Window.window) return null;
        const topLeft = globalPoint(item, { x: 0, y: 0 });
        return { x: topLeft.x, y: topLeft.y, width: item.width, height: item.height };
    }

    function branchRects() {
        let rects = [];
        const anchor = itemRect(anchorItem);
        const surface = itemRect(surfaceItem);
        if (anchor) rects.push(anchor);
        if (surface) rects.push(surface);
        for (const child of childIntents || [])
            if (child && child.active && typeof child.branchRects === "function")
                rects = rects.concat(child.branchRects());
        return rects;
    }

    function rootBranchRects() {
        let rootIntent = root;
        while (rootIntent.parentIntent && rootIntent.parentIntent !== rootIntent)
            rootIntent = rootIntent.parentIntent;
        return rootIntent.branchRects();
    }

    function pointInBranch(point) {
        return branchRects().some(rect => MenuAim.pointInRect(point, rect));
    }

    function pointInDescendantCorridor(point) {
        for (const child of childIntents || []) {
            if (!child || !child.active) continue;
            if (child.pointInSafeRegion(point, child.surfaceItem)
                || child.pointInDescendantCorridor(point)) return true;
        }
        return false;
    }

    function safeRegion(targetItem, sourceItem) {
        if (targetReached) return null;
        const source = itemRect(sourceItem || (targetItem === surfaceItem ? anchorItem : surfaceItem));
        const target = itemRect(targetItem);
        return source && target ? MenuAim.safeCorridorPolygon(source, target, buffer) : null;
    }

    function pointInSafeRegion(point, targetItem, sourceItem) {
        const region = safeRegion(targetItem, sourceItem);
        return !!region && MenuAim.pointInCorridor(point, region);
    }

    function observeGlobalPoint(point, now) {
        if (!active || !pointerDismissEnabled || !point
            || !Number.isFinite(point.x) || !Number.isFinite(point.y)) return;
        const currentTime = now === undefined ? Date.now() : now;
        previousPoint = lastPoint;
        lastPoint = { x: point.x, y: point.y };
        lastObservedAt = currentTime;
        if (previousPoint && Math.hypot(point.x - previousPoint.x, point.y - previousPoint.y) > 0.5) {
            motionObserved = true;
            armed = true;
        }
        const insideOwn = [itemRect(anchorItem), itemRect(surfaceItem)]
            .some(rect => MenuAim.pointInRect(lastPoint, rect));
        anchorHovered = MenuAim.pointInRect(lastPoint, itemRect(anchorItem));
        surfaceHovered = MenuAim.pointInRect(lastPoint, itemRect(surfaceItem));
        if (surfaceHovered) targetReached = true;
        const insideBranch = pointInBranch(lastPoint);
        if (insideBranch) lastInsidePoint = lastPoint;
        if (draggingOutside) {
            closeTimer.stop();
            startedAt = 0;
        } else if (insideOwn) {
            cancelLeave();
        } else if (pointInDescendantCorridor(lastPoint)) {
            closeTimer.stop();
            startedAt = 0;
        } else if (aimTargetItem) {
            if (pointInSafeRegion(lastPoint, aimTargetItem)) {
                closeTimer.stop();
                startedAt = 0;
                syncParent();
                aimDeferred();
            } else if (insideBranch) {
                cancelLeave();
            } else if (!draggingOutside) {
                if (!(startedAt > 0)) startedAt = currentTime;
                closeTimer.interval = Math.max(0, graceMs - (currentTime - startedAt));
                if (!closeTimer.running) closeTimer.start();
                if (freshPointIsFar(lastPoint, currentTime)) requestDismiss("fresh-point-far-from-branch");
                else syncParent();
            }
        } else if (!insideBranch && !draggingOutside && armed) {
            beginLeave(surfaceItem);
        }
        for (const child of childIntents || [])
            if (child && child.active && typeof child.observeGlobalPoint === "function")
                child.observeGlobalPoint(lastPoint, currentTime);
    }

    function normalizeCursorPoint(point) {
        if (!point) return null;
        const offset = coordinateItem ? coordinateOrigin : { x: 0, y: 0 };
        return { x: point.x - offset.x, y: point.y - offset.y };
    }

    function acceptCursorReply(data, generation) {
        if (!samplerRoot || !cursorRequestInFlight || generation !== cursorGeneration
            || !active || !pointerDismissEnabled) return false;
        cursorReplyBuffer += String(data || "");
        let decoded = null;
        try { decoded = JSON.parse(cursorReplyBuffer); } catch (_) { return false; }
        const point = Array.isArray(decoded) && Number.isFinite(decoded[0]) && Number.isFinite(decoded[1])
            ? { x: decoded[0], y: decoded[1] }
            : decoded && Number.isFinite(decoded.x) && Number.isFinite(decoded.y)
                ? { x: decoded.x, y: decoded.y } : null;
        cursorRequestInFlight = false;
        cursorRequestSent = false;
        cursorReplyBuffer = "";
        requestTimeout.stop();
        if (point) observeGlobalPoint(normalizeCursorPoint(point), Date.now());
        cursorAwaitingDisconnect = cursorSocket.connected;
        cursorSocket.connected = false;
        return !!point;
    }

    function startCursorRequest() {
        if (!samplerRoot || !active || !pointerDismissEnabled || cursorRequestInFlight || cursorAwaitingDisconnect
            || !Hyprland.requestSocketPath) return;
        cursorRequestInFlight = true;
        cursorRequestSent = false;
        cursorReplyBuffer = "";
        cursorGeneration++;
        cursorSocket.connected = true;
        requestTimeout.restart();
    }

    function finishCursorRequest() {
        if (!cursorRequestInFlight) return;
        cursorRequestInFlight = false;
        cursorRequestSent = false;
        cursorReplyBuffer = "";
        cursorGeneration++;
        requestTimeout.stop();
        cursorAwaitingDisconnect = cursorSocket.connected;
        cursorSocket.connected = false;
    }

    function freshPointIsFar(point, now) {
        return MenuAim.isFreshFarFromBranch(point, rootBranchRects(), lastObservedAt,
            now === undefined ? Date.now() : now, farDismissDistance, freshPointMaxAge);
    }

    function globalPoint(item, localPoint) {
        if (!item || !localPoint) return null;
        let ancestor = item;
        while (ancestor) {
            if (ancestor.pointerGlobalOrigin !== undefined) {
                const local = item.mapToItem(ancestor, localPoint.x, localPoint.y);
                const offset = root.coordinateItem ? root.coordinateOrigin : { x: 0, y: 0 };
                return { x: ancestor.pointerGlobalOrigin.x + local.x - offset.x,
                    y: ancestor.pointerGlobalOrigin.y + local.y - offset.y };
            }
            ancestor = ancestor.parent;
        }
        const point = coordinateItem
            ? item.mapToItem(coordinateItem, localPoint.x, localPoint.y)
            : item.mapToGlobal(localPoint.x, localPoint.y);
        return { x: point.x, y: point.y };
    }

    function observePoint(item, localPoint, now, pressedButtons) {
        const point = globalPoint(item, localPoint);
        if (!point) return null;
        if (pressedButtons !== undefined) draggingOutside = pressedButtons !== Qt.NoButton;
        observeGlobalPoint(point, now);
        return point;
    }

    function pointAimingAt(targetItem, originGlobal, pointGlobal, previousGlobal, timeStarted, now, sourceItem) {
        return !!pointGlobal && pointInSafeRegion(pointGlobal, targetItem, sourceItem);
    }

    function aimCorridor(targetItem, origin, sourceItem) {
        const hull = safeRegion(targetItem, sourceItem);
        if (hull) return hull;
        if (useAnchorCorridor && (targetItem === surfaceItem || targetItem === anchorItem))
            return MenuAim.anchorMenuCorridor(itemRect(anchorItem), itemRect(surfaceItem));
        return null;
    }

    function deferToward(targetItem, originGlobal, pointGlobal, previousGlobal, timeStarted, now) {
        return pointAimingAt(targetItem, originGlobal, pointGlobal, previousGlobal, timeStarted, now);
    }

    function shouldDefer(pointGlobal, now) {
        return pointAimingAt(aimTargetItem, intentOrigin, pointGlobal, previousPoint,
            startedAt, now === undefined ? Date.now() : now);
    }

    function cancelLeave() {
        if (startedAt > 0) trace("cancel-leave");
        closeTimer.stop();
        aimTargetItem = null;
        intentOrigin = null;
        startedAt = 0;
        syncParent();
    }

    function requestDismiss(reason) {
        trace("dismiss", reason || "child-dismissed");
        debugDismissedGeometry = {
            anchor: itemRect(anchorItem),
            surface: itemRect(surfaceItem),
            corridor: aimTargetItem && intentOrigin
                ? aimCorridor(aimTargetItem, intentOrigin) : null,
            target: aimTargetItem ? itemRect(aimTargetItem) : null,
            point: lastPoint,
            buffer: buffer
        };
        dismissedByPointer = true;
        cancelLeave();
        dismissRequested();
    }

    function beginLeave(targetItem) {
        if (!active || !pointerDismissEnabled || !armed || anchorHovered || surfaceHovered) return;
        const targetRect = itemRect(targetItem);
        if (targetRect && MenuAim.pointInRect(lastPoint, targetRect)) {
            cancelLeave();
            return;
        }
        aimTargetItem = targetItem || null;
        intentOrigin = lastInsidePoint || lastPoint;
        if (draggingOutside) {
            closeTimer.stop();
            startedAt = 0;
            syncParent();
            return;
        }
        const now = Date.now();
        if (Number.isFinite(lastObservedAt) && now - lastObservedAt <= freshPointMaxAge) {
            if (pointInSafeRegion(lastPoint, aimTargetItem)) {
                startedAt = 0;
                closeTimer.stop();
            } else if (freshPointIsFar(lastPoint, now)) {
                requestDismiss("fresh-point-far-from-branch");
            } else if (!(startedAt > 0)) {
                startedAt = now;
                closeTimer.interval = Math.max(0, graceMs);
                closeTimer.start();
            }
        }
        trace("begin-leave");
        syncParent();
    }

    function enterChain() {
        if (!active || !pointerDismissEnabled) return;
        trace("enter");
        if (surfaceHovered || motionObserved) armed = true;
        cancelLeave();
        syncParent();
    }

    function leaveItem(item, pressedButtons) {
        if (item === anchorItem) anchorHovered = false;
        else if (item === surfaceItem) surfaceHovered = false;
        trace("leave", item === anchorItem ? "anchor" : "surface");
        if (pressedButtons !== undefined && pressedButtons !== Qt.NoButton) draggingOutside = true;
        if (draggingOutside) {
            aimTargetItem = item === anchorItem ? surfaceItem : anchorItem;
            intentOrigin = lastPoint;
            startedAt = 0;
            closeTimer.stop();
            syncParent();
            return;
        }
        if (!anchorHovered && !surfaceHovered)
            beginLeave(item === anchorItem ? surfaceItem : anchorItem);
    }

    function addChild(childIntent) {
        if (childIntent) {
            if (!childIntents.includes(childIntent)) childIntents = childIntents.concat([childIntent]);
        } else legacyChildCount++;
        openChildren = childIntents.length + legacyChildCount;
        cancelLeave();
        syncParent();
    }
    function removeChild(pointerDismissed, childIntent) {
        if (childIntent) childIntents = childIntents.filter(child => child !== childIntent);
        else legacyChildCount = Math.max(0, legacyChildCount - 1);
        openChildren = childIntents.length + legacyChildCount;
        if (active && armed && !anchorHovered && !surfaceHovered && openChildren === 0) {
            if (pointerDismissed) requestDismiss();
            else beginLeave(anchorItem);
        }
    }

    function syncParent() {
        const pointerBranchActive = active && pointerDismissEnabled;
        const next = pointerBranchActive && parentIntent && typeof parentIntent.addChild === "function" ? parentIntent : null;
        if (registeredParent === next) return;
        if (registeredParent && typeof registeredParent.removeChild === "function")
            registeredParent.removeChild(dismissedByPointer, root);
        registeredParent = next;
        if (registeredParent) registeredParent.addChild(root);
    }

    onActiveChanged: {
        if (active) {
            dismissedByPointer = false;
            debugDismissedGeometry = null;
            lastPoint = null;
            previousPoint = null;
            lastInsidePoint = null;
            lastObservedAt = 0;
            draggingOutside = false;
            motionObserved = false;
            targetReached = surfaceHovered;
            armed = surfaceHovered;
            syncParent();
        } else {
            armed = false;
            cancelLeave();
            syncParent();
            if (samplerRoot) finishCursorRequest();
        }
    }
    onParentIntentChanged: {
        syncParent();
        if (!samplerRoot) finishCursorRequest();
    }
    onPointerDismissEnabledChanged: {
        if (!pointerDismissEnabled) {
            cancelLeave();
            if (samplerRoot) finishCursorRequest();
        }
    }
    Component.onDestruction: {
        closeTimer.stop();
        if (registeredParent && typeof registeredParent.removeChild === "function")
            registeredParent.removeChild(dismissedByPointer, root);
    }

    width: 0
    height: 0

    HoverHandler {
        id: anchorHoverHandler
        parent: root.anchorItem
        enabled: root.active && root.pointerDismissEnabled && !!root.anchorItem
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        blocking: false
        onPointChanged: root.observePoint(root.anchorItem, point.position, undefined, point.pressedButtons)
        onHoveredChanged: {
            root.anchorHovered = hovered;
            if (hovered) root.enterChain();
            else root.leaveItem(root.anchorItem, point.pressedButtons);
        }
    }

    HoverHandler {
        id: surfaceHoverHandler
        parent: root.surfaceItem
        enabled: root.active && root.pointerDismissEnabled && !!root.surfaceItem
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        blocking: false
        onPointChanged: root.observePoint(root.surfaceItem, point.position, undefined, point.pressedButtons)
        onHoveredChanged: {
            root.surfaceHovered = hovered;
            if (hovered) root.targetReached = true;
            if (hovered) root.enterChain();
            else root.leaveItem(root.surfaceItem, point.pressedButtons);
        }
    }

    Timer {
        id: closeTimer
        repeat: false
        onTriggered: {
            if (!root.active || !root.pointerDismissEnabled || !root.armed
                || root.anchorHovered || root.surfaceHovered || root.openChildren > 0
                || root.draggingOutside) return;
            if (!root.lastPoint || Date.now() - root.lastObservedAt > root.freshPointMaxAge
                || root.pointInSafeRegion(root.lastPoint, root.aimTargetItem)) {
                root.startedAt = 0;
                return;
            }
            root.requestDismiss("grace-expired");
        }
    }

    Timer {
        id: cursorPoll
        interval: 80
        repeat: true
        running: root.samplerRoot && root.active && root.pointerDismissEnabled
        onTriggered: root.startCursorRequest()
    }

    Timer {
        id: requestTimeout
        interval: 150
        repeat: false
        onTriggered: root.finishCursorRequest()
    }

    Socket {
        id: cursorSocket
        path: Hyprland.requestSocketPath
        onConnectionStateChanged: {
            if (!connected) {
                root.cursorAwaitingDisconnect = false;
                return;
            }
            if (root.cursorRequestInFlight && !root.cursorRequestSent) {
                root.cursorRequestSent = true;
                root.socketGeneration = root.cursorGeneration;
                write("j/cursorpos");
                flush();
            }
        }
        onError: root.finishCursorRequest()
        parser: SplitParser {
            splitMarker: ""
            onRead: function(data) { root.acceptCursorReply(data, root.socketGeneration); }
        }
    }
}
