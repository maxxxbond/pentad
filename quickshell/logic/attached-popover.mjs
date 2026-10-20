import { continuousCorner } from "./continuous-corners.mjs";

export function popoverPlacement(anchor, screen, width, height, placement = "below", seamY = anchor.y + anchor.height) {
  const clamp = (value, min, max) => Math.max(min, Math.min(max, value));
  const w = Math.min(width, screen.width), h = Math.min(height, screen.height);
  let x = anchor.x + anchor.width / 2 - w / 2;
  let y = seamY;
  if (placement === "right") {
    x = anchor.x + anchor.width;
    if (x + w > screen.x + screen.width) x = anchor.x - w;
    y = anchor.y;
  }
  return { x: clamp(x, screen.x, screen.x + screen.width - w),
    y: clamp(y, screen.y, screen.y + screen.height - h), width: w, height: h };
}

export function attachedPopoverGeometry(width, height, neckCenter, neckWidth = 40, neckHeight = 12, radius = 20, shoulder = 10) {
  if (![width, height, neckCenter, neckWidth, neckHeight, radius, shoulder].every(Number.isFinite)
      || [width, height, neckWidth, neckHeight, radius, shoulder].some(value => value < 0)) {
    throw new TypeError("Popover geometry must contain finite nonnegative dimensions");
  }
  if (width === 0 || height === 0) return { path: "", neckCenter: 0, neckWidth: 0, bodyTop: 0 };

  const actualCenter = Math.max(0, Math.min(width, neckCenter));
  const actualNeckWidth = Math.min(neckWidth, 2 * actualCenter, 2 * (width - actualCenter));
  const s = Math.min(shoulder, actualNeckWidth / 2, width / 4,
    Math.max(0, (height - neckHeight) / 2), actualCenter - actualNeckWidth / 2,
    width - actualCenter - actualNeckWidth / 2);
  const bodyTop = Math.min(height, neckHeight + s);
  const r = Math.min(radius, width / 2, Math.max(0, (height - bodyTop) / 2));
  const upperLeftR = Math.min(radius, Math.max(0, actualCenter - actualNeckWidth / 2 - s));
  const upperRightR = Math.min(radius, Math.max(0, width - actualCenter - actualNeckWidth / 2 - s));
  const neckLeft = actualCenter - actualNeckWidth / 2;
  const neckRight = actualCenter + actualNeckWidth / 2;
  const curve = { path: "", curveTo(...points) { this.path += ` C ${points.join(" ")}`; } };
  const corner = (start, size, entry, exit) => {
    continuousCorner(curve, start, size, entry, exit);
    return curve.path;
  };
  let path = `M 0 ${bodyTop + upperLeftR}`;
  curve.path = "";
  corner([0, bodyTop + upperLeftR], upperLeftR, [0, -1], [1, 0]);
  path += curve.path + ` L ${neckLeft - s} ${bodyTop}`;
  path += ` C ${neckLeft - s * 0.35} ${bodyTop}, ${neckLeft} ${bodyTop - s * 0.35}, ${neckLeft} ${bodyTop - s}`;
  path += ` L ${neckLeft} 0 L ${neckRight} 0 L ${neckRight} ${bodyTop - s}`;
  path += ` C ${neckRight} ${bodyTop - s * 0.35}, ${neckRight + s * 0.35} ${bodyTop}, ${neckRight + s} ${bodyTop}`;
  path += ` L ${width - upperRightR} ${bodyTop}`;
  curve.path = "";
  corner([width - upperRightR, bodyTop], upperRightR, [1, 0], [0, 1]);
  path += curve.path + ` L ${width} ${height - r}`;
  curve.path = "";
  corner([width, height - r], r, [0, 1], [-1, 0]);
  path += curve.path + ` L ${r} ${height}`;
  curve.path = "";
  corner([r, height], r, [-1, 0], [0, -1]);
  path += curve.path + ` L 0 ${bodyTop + r} Z`;
  return { path, neckCenter: actualCenter, neckWidth: actualNeckWidth, bodyTop };
}
