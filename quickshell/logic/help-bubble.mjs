import { continuousCorner } from "./continuous-corners.mjs";

// Places an explanation bubble over its trigger, or under it when the window has no room above.
// Coordinates are in the window's content item; the tail always points at the trigger's centre.
export function helpBubblePlacement(anchor, area, width, height, gap = 4, margin = 8) {
  const values = [anchor.x, anchor.y, anchor.width, anchor.height, area.width, area.height, width, height, gap, margin];
  if (!values.every(Number.isFinite)) throw new TypeError("Help bubble placement must contain finite numbers");
  const centre = anchor.x + anchor.width / 2;
  const maxX = Math.max(margin, area.width - width - margin);
  const x = Math.max(margin, Math.min(maxX, centre - width / 2));
  const above = anchor.y - gap - height;
  const below = anchor.y + anchor.height + gap;
  const fitsAbove = above >= margin;
  const fitsBelow = below + height <= area.height - margin;
  const side = fitsAbove || (!fitsBelow && anchor.y > area.height - anchor.y - anchor.height) ? "above" : "below";
  const y = side === "above" ? Math.max(margin, above) : below;
  return { x, y, side, tailX: centre - x };
}

// The bubble's silhouette with the tail on top (side "below"); the caller mirrors it vertically for "above".
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
