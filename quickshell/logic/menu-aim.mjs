const EPSILON = 1e-9;

function validPoint(point) {
    return point !== null && typeof point === "object"
        && Number.isFinite(point.x) && Number.isFinite(point.y);
}

function validRect(rect) {
    return rect !== null && typeof rect === "object"
        && Number.isFinite(rect.x) && Number.isFinite(rect.y)
        && Number.isFinite(rect.width) && Number.isFinite(rect.height)
        && rect.width > 0 && rect.height > 0
        && Number.isFinite(rect.x + rect.width) && Number.isFinite(rect.y + rect.height);
}

function validBuffer(buffer) {
    return Number.isFinite(buffer) && buffer >= 0;
}

function expandedRect(rect, buffer) {
    return {
        x: rect.x - buffer,
        y: rect.y - buffer,
        width: rect.width + 2 * buffer,
        height: rect.height + 2 * buffer,
    };
}

function pointToRectDistance(point, rect) {
    const dx = Math.max(rect.x - point.x, 0, point.x - (rect.x + rect.width));
    const dy = Math.max(rect.y - point.y, 0, point.y - (rect.y + rect.height));
    return Math.hypot(dx, dy);
}

export function pointInRect(point, rect, buffer = 0) {
    if (!validPoint(point) || !validRect(rect) || !validBuffer(buffer)) return false;
    const bounds = expandedRect(rect, buffer);
    if (!validRect(bounds)) return false;
    return point.x >= bounds.x && point.x <= bounds.x + bounds.width
        && point.y >= bounds.y && point.y <= bounds.y + bounds.height;
}

export function nearestEdgeTriangle(origin, rect, buffer = 4) {
    if (!validPoint(origin) || !validRect(rect) || !validBuffer(buffer)) return null;
    const bounds = expandedRect(rect, buffer);
    if (!validRect(bounds)) return null;
    const left = bounds.x;
    const right = bounds.x + bounds.width;
    const top = bounds.y;
    const bottom = bounds.y + bounds.height;
    const clamp = (value, min, max) => Math.max(min, Math.min(max, value));
    const edges = [
        { distance: Math.hypot(origin.x - left, origin.y - clamp(origin.y, top, bottom)), b: { x: left, y: top }, c: { x: left, y: bottom } },
        { distance: Math.hypot(origin.x - right, origin.y - clamp(origin.y, top, bottom)), b: { x: right, y: top }, c: { x: right, y: bottom } },
        { distance: Math.hypot(origin.x - clamp(origin.x, left, right), origin.y - top), b: { x: left, y: top }, c: { x: right, y: top } },
        { distance: Math.hypot(origin.x - clamp(origin.x, left, right), origin.y - bottom), b: { x: left, y: bottom }, c: { x: right, y: bottom } },
    ];
    let nearest = edges[0];
    for (let index = 1; index < edges.length; index++)
        if (edges[index].distance < nearest.distance) nearest = edges[index];
    return { a: { x: origin.x, y: origin.y }, b: nearest.b, c: nearest.c };
}

export function pointInTriangle(point, triangle) {
    if (!validPoint(point) || !triangle || !validPoint(triangle.a)
        || !validPoint(triangle.b) || !validPoint(triangle.c)) return false;
    const { a, b, c } = triangle;
    const area = (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x);
    if (!Number.isFinite(area) || Math.abs(area) <= EPSILON) return false;
    const ab = (b.x - a.x) * (point.y - a.y) - (b.y - a.y) * (point.x - a.x);
    const bc = (c.x - b.x) * (point.y - b.y) - (c.y - b.y) * (point.x - b.x);
    const ca = (a.x - c.x) * (point.y - c.y) - (a.y - c.y) * (point.x - c.x);
    if (![ab, bc, ca].every(Number.isFinite)) return false;
    return (ab >= -EPSILON && bc >= -EPSILON && ca >= -EPSILON)
        || (ab <= EPSILON && bc <= EPSILON && ca <= EPSILON);
}

export function anchorMenuCorridor(anchorRect, menuRect, buffer = 0) {
    if (!validRect(anchorRect) || !validRect(menuRect) || !validBuffer(buffer)
        || menuRect.y <= anchorRect.y) return null;
    const target = expandedRect(menuRect, buffer);
    if (!validRect(target) || target.y <= anchorRect.y) return null;
    return {
        a: { x: anchorRect.x, y: anchorRect.y },
        b: { x: anchorRect.x + anchorRect.width, y: anchorRect.y },
        c: { x: target.x + target.width, y: target.y },
        d: { x: target.x, y: target.y },
    };
}

function rectGap(a, b, axis) {
    const aEnd = a[axis] + a[axis === "x" ? "width" : "height"];
    const bEnd = b[axis] + b[axis === "x" ? "width" : "height"];
    return Math.max(b[axis] - aEnd, a[axis] - bEnd, 0);
}

function rectCorners(rect, buffer) {
    const bounds = expandedRect(rect, buffer);
    if (!validRect(bounds)) return [];
    return [
        { x: bounds.x, y: bounds.y },
        { x: bounds.x + bounds.width, y: bounds.y },
        { x: bounds.x + bounds.width, y: bounds.y + bounds.height },
        { x: bounds.x, y: bounds.y + bounds.height },
    ];
}

function cross(origin, a, b) {
    return (a.x - origin.x) * (b.y - origin.y) - (a.y - origin.y) * (b.x - origin.x);
}

export function safeCorridorPolygon(sourceRect, targetRect, buffer = 4) {
    if (!validRect(sourceRect) || !validRect(targetRect) || !validBuffer(buffer)) return null;
    const points = rectCorners(sourceRect, buffer).concat(rectCorners(targetRect, buffer));
    if (points.length !== 8) return null;
    points.sort((a, b) => a.x - b.x || a.y - b.y);
    const lower = [];
    for (const point of points) {
        while (lower.length >= 2 && cross(lower[lower.length - 2], lower[lower.length - 1], point) <= EPSILON)
            lower.pop();
        lower.push(point);
    }
    const upper = [];
    for (let index = points.length - 1; index >= 0; index--) {
        const point = points[index];
        while (upper.length >= 2 && cross(upper[upper.length - 2], upper[upper.length - 1], point) <= EPSILON)
            upper.pop();
        upper.push(point);
    }
    lower.pop();
    upper.pop();
    const hull = lower.concat(upper);
    if (hull.length < 4) return null;
    return { points: hull, sourceRect, targetRect, buffer };
}

export function facingEdgeTriangle(sourceRect, targetRect, origin, buffer = 4) {
    if (!validRect(sourceRect) || !validRect(targetRect) || !validPoint(origin) || !validBuffer(buffer)) return null;
    const target = expandedRect(targetRect, buffer);
    if (!validRect(target)) return null;
    const sourceCenter = { x: sourceRect.x + sourceRect.width / 2, y: sourceRect.y + sourceRect.height / 2 };
    const targetCenter = { x: targetRect.x + targetRect.width / 2, y: targetRect.y + targetRect.height / 2 };
    const gapX = rectGap(sourceRect, targetRect, "x");
    const gapY = rectGap(sourceRect, targetRect, "y");
    let horizontal;
    if (gapX > 0 && gapY === 0) horizontal = true;
    else if (gapY > 0 && gapX === 0) horizontal = false;
    else {
        const normalizedX = Math.abs(targetCenter.x - sourceCenter.x) / (sourceRect.width + targetRect.width);
        const normalizedY = Math.abs(targetCenter.y - sourceCenter.y) / (sourceRect.height + targetRect.height);
        horizontal = normalizedX >= normalizedY;
    }

    let b, c;
    if (horizontal) {
        const edgeX = targetCenter.x >= sourceCenter.x ? target.x : target.x + target.width;
        b = { x: edgeX, y: target.y };
        c = { x: edgeX, y: target.y + target.height };
    } else {
        const edgeY = targetCenter.y >= sourceCenter.y ? target.y : target.y + target.height;
        b = { x: target.x, y: edgeY };
        c = { x: target.x + target.width, y: edgeY };
    }

    const clamp = (value, low, high) => Math.max(low, Math.min(high, value));
    let a = { x: clamp(origin.x, sourceRect.x, sourceRect.x + sourceRect.width),
        y: clamp(origin.y, sourceRect.y, sourceRect.y + sourceRect.height) };
    const area = (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x);
    if (!Number.isFinite(area)) return null;
    if (Math.abs(area) <= EPSILON) {
        const corners = [
            { x: sourceRect.x, y: sourceRect.y },
            { x: sourceRect.x + sourceRect.width, y: sourceRect.y },
            { x: sourceRect.x, y: sourceRect.y + sourceRect.height },
            { x: sourceRect.x + sourceRect.width, y: sourceRect.y + sourceRect.height },
        ];
        const edgeMid = { x: (b.x + c.x) / 2, y: (b.y + c.y) / 2 };
        a = corners.reduce((best, corner) => Math.hypot(corner.x - edgeMid.x, corner.y - edgeMid.y)
            > Math.hypot(best.x - edgeMid.x, best.y - edgeMid.y) ? corner : best);
    }
    return { a, b, c, sourceRect };
}

export function pointDistanceToRects(point, rects) {
    if (!validPoint(point) || !Array.isArray(rects)) return Infinity;
    let distance = Infinity;
    for (const rect of rects)
        if (validRect(rect)) distance = Math.min(distance, pointToRectDistance(point, rect));
    return distance;
}

export function isFreshFarFromBranch(point, rects, observedAt, now, threshold = 80, maxAge = 120) {
    const distance = pointDistanceToRects(point, rects);
    return validPoint(point) && Array.isArray(rects) && Number.isFinite(distance)
        && Number.isFinite(observedAt) && Number.isFinite(now)
        && Number.isFinite(threshold) && threshold >= 0
        && Number.isFinite(maxAge) && maxAge >= 0
        && now >= observedAt && now - observedAt <= maxAge
        && distance > threshold;
}

export function pointInCorridor(point, corridor) {
    if (!corridor) return false;
    if (Array.isArray(corridor.points)) {
        if (!validPoint(point) || corridor.points.length < 3
            || !corridor.points.every(validPoint)) return false;
        return corridor.points.every((vertex, index) =>
            cross(vertex, corridor.points[(index + 1) % corridor.points.length], point) >= -EPSILON);
    }
    if (corridor.d === undefined)
        return (corridor.sourceRect && pointInRect(point, corridor.sourceRect))
            || pointInTriangle(point, corridor);
    if (![corridor.a, corridor.b, corridor.c, corridor.d].every(validPoint)) return false;
    return pointInTriangle(point, { a: corridor.a, b: corridor.b, c: corridor.c })
        || pointInTriangle(point, { a: corridor.a, b: corridor.c, c: corridor.d });
}

export function shouldDeferClose(options = {}) {
    if (!options || typeof options !== "object") return false;
    const {
        origin, targetRect, point, previousPoint = origin,
        startedAt, now, graceMs = 300, buffer = 4, corridor,
    } = options;
    if (!validPoint(origin) || !validPoint(point) || !validPoint(previousPoint)
        || !validRect(targetRect) || !validBuffer(buffer)
        || !Number.isFinite(startedAt) || !Number.isFinite(now)
        || !Number.isFinite(graceMs) || graceMs < 0
        || now < startedAt || now - startedAt >= graceMs) return false;
    if (pointInRect(point, targetRect)) return false;
    const region = corridor === undefined ? nearestEdgeTriangle(origin, targetRect, buffer) : corridor;
    if (!region || (!pointInCorridor(point, region) && !pointInRect(point, targetRect, buffer))) return false;
    const pointDistance = pointToRectDistance(point, targetRect);
    const previousDistance = pointToRectDistance(previousPoint, targetRect);
    return Number.isFinite(pointDistance) && Number.isFinite(previousDistance)
        && pointDistance <= previousDistance + buffer;
}
