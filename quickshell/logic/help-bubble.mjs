import { continuousCorner } from "./continuous-corners.mjs";

// Places a bubble next to its trigger in the window's content item. On the "vertical" axis it goes above the trigger,
// or below when the window has no room above; on the "horizontal" axis it goes right, or left. `tail` is where the
// tail meets the bubble edge that faces the trigger, measured along that edge, so it always points at the trigger.
export function helpBubblePlacement(anchor, area, width, height, gap = 4, margin = 8, axis = "vertical") {
  const values = [anchor.x, anchor.y, anchor.width, anchor.height, area.width, area.height, width, height, gap, margin];
  if (!values.every(Number.isFinite)) throw new TypeError("Help bubble placement must contain finite numbers");
  const clamp = (value, min, max) => Math.max(min, Math.min(Math.max(min, max), value));
  if (axis === "horizontal") {
    const middle = anchor.y + anchor.height / 2;
    const y = clamp(middle - height / 2, margin, area.height - height - margin);
    const right = anchor.x + anchor.width + gap;
    const left = anchor.x - gap - width;
    const fitsRight = right + width <= area.width - margin;
    const fitsLeft = left >= margin;
    const side = fitsRight || (!fitsLeft && area.width - right >= anchor.x) ? "right" : "left";
    return { x: side === "right" ? right : Math.max(margin, left), y, side, tail: middle - y };
  }
  const centre = anchor.x + anchor.width / 2;
  const x = clamp(centre - width / 2, margin, area.width - width - margin);
  const above = anchor.y - gap - height;
  const below = anchor.y + anchor.height + gap;
  const fitsAbove = above >= margin;
  const fitsBelow = below + height <= area.height - margin;
  const side = fitsAbove || (!fitsBelow && anchor.y > area.height - anchor.y - anchor.height) ? "above" : "below";
  const y = side === "above" ? Math.max(margin, above) : below;
  return { x, y, side, tail: centre - x };
}

// The bubble's silhouette with the tail on top (side "below"); the caller mirrors or rotates it for the other sides.
export function helpBubbleGeometry(width, height, tailX, tailWidth = 20, tailHeight = 8, radius = 16) {
  if (![width, height, tailX, tailWidth, tailHeight, radius].every(Number.isFinite)
      || [width, height, tailWidth, tailHeight, radius].some(value => value < 0)) {
    throw new TypeError("Help bubble geometry must contain finite nonnegative dimensions");
  }
  if (width === 0 || height <= tailHeight) return { path: "", tailX: 0, bodyTop: 0 };
  const top = tailHeight;
  const r = Math.min(radius, width / 2, (height - top) / 2);
  const half = Math.min(tailWidth / 2, Math.max(0, width / 2 - r));
  const tip = Math.max(r + half, Math.min(width - r - half, tailX));
  const left = tip - half, right = tip + half;
  let path = `M 0 ${top + r}`;
  const curve = { curveTo: (...points) => { path += " C " + points.join(" "); } };
  const corner = (start, size, entry, exit) => continuousCorner(curve, start, size, entry, exit);
  corner([0, top + r], r, [0, -1], [1, 0]);
  // A flared tail with a softened tip, so it reads as part of the surface rather than a pasted triangle.
  path += ` L ${left} ${top}`;
  path += ` C ${left + half * 0.55} ${top} ${tip - half * 0.3} 0 ${tip} 0`;
  path += ` C ${tip + half * 0.3} 0 ${right - half * 0.55} ${top} ${right} ${top}`;
  path += ` L ${width - r} ${top}`;
  corner([width - r, top], r, [1, 0], [0, 1]);
  path += ` L ${width} ${height - r}`;
  corner([width, height - r], r, [0, 1], [-1, 0]);
  path += ` L ${r} ${height}`;
  corner([r, height], r, [-1, 0], [0, -1]);
  path += " Z";
  return { path, tailX: tip, bodyTop: top };
}
