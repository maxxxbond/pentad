export function auditNestedGeometry(outer, inner, side = 'left', tolerance = 0.5) {
    const dimensions = [outer?.width, outer?.height, outer?.radius,
        inner?.x, inner?.y, inner?.width, inner?.height, inner?.radius];
    if (!dimensions.every(Number.isFinite) || outer.width <= 0 || outer.height <= 0
        || inner.width <= 0 || inner.height <= 0 || outer.radius < 0 || inner.radius < 0
        || !['left', 'right'].includes(side) || !Number.isFinite(tolerance) || tolerance < 0
        || !['circular', 'continuous'].includes(outer.curve)
        || !['circular', 'continuous'].includes(inner.curve)) {
        return { status: 'unverified', issues: ['missing-or-invalid-geometry'] };
    }
    const top = inner.y;
    const bottom = outer.height - inner.y - inner.height;
    const edge = side === 'right' ? outer.width - inner.x - inner.width : inner.x;
    const padding = (outer.height - inner.height) / 2;
    const expectedRadius = Math.max(0, outer.radius - padding);
    const issues = [];
    if (inner.x < -tolerance || inner.y < -tolerance
        || inner.x + inner.width > outer.width + tolerance
        || inner.y + inner.height > outer.height + tolerance) issues.push('outside');
    if (Math.max(top, bottom, edge) - Math.min(top, bottom, edge) > tolerance)
        issues.push('unequal-insets');
    if (Math.abs(inner.radius - expectedRadius) > tolerance) issues.push('radius-mismatch');
    if (outer.curve !== inner.curve) issues.push('curve-mismatch');
    return { status: issues.length ? 'error' : 'ok', issues,
        insets: { top, bottom, edge }, padding, expectedRadius };
}
