export const attachedSurfaceGeometry = Object.freeze({
  shoulder: 32,
  radius: 32,
  rim: 4,
});

export function surfaceGeometry(width, height, radius, shoulder = 0, join = 0) {
  if (![width, height, radius, shoulder, join].every(Number.isFinite)
      || [width, height, radius, shoulder, join].some(value => value < 0)) {
    throw new TypeError("Surface geometry must contain finite nonnegative dimensions");
  }
  let r = shoulder > 0 ? radius : Math.min(radius, width / 2, height / 2);
  let s = shoulder;
  const j = Math.min(join, height);
  if (s > 0) {
    const scale = Math.min(1, width / (2 * (r + s)), (height - j) / (r + s));
    r *= scale;
    s *= scale;
  }
  if (width === 0 || height === 0) return { radius: 0, shoulder: 0, join: 0, bodyWidth: 0, path: "" };
  let d = s > 0 ? "M 0 0" : `M ${r} 0`;
  const curve = { curveTo: (...points) => { d += " C " + points.join(" "); } };
  const corner = (start, size, entry, exit) => continuousCorner(curve, start, size, entry, exit);
  if (s > 0) {
    d += ` L ${width} 0 L ${width} ${j}`;
    corner([width, j], s, [-1, 0], [0, 1]);
    d += ` L ${width - s} ${height - r}`;
    corner([width - s, height - r], r, [0, 1], [-1, 0]);
    d += ` L ${s + r} ${height}`;
    corner([s + r, height], r, [-1, 0], [0, -1]);
    d += ` L ${s} ${j + s}`;
    corner([s, j + s], s, [0, -1], [-1, 0]);
  } else {
    d += ` L ${width - r} 0`;
    corner([width - r, 0], r, [1, 0], [0, 1]);
    d += ` L ${width} ${height - r}`;
    corner([width, height - r], r, [0, 1], [-1, 0]);
    d += ` L ${r} ${height}`;
    corner([r, height], r, [-1, 0], [0, -1]);
    d += ` L 0 ${r}`;
    corner([0, r], r, [0, -1], [1, 0]);
  }
  return { radius: r, shoulder: s, join: j, bodyWidth: width - 2 * s, path: d + " Z" };
}

export function continuousCorner(context, start, radius, entry, exit) {
  if (!context || typeof context.curveTo !== "function") {
    throw new TypeError("Corner context must provide curveTo");
  }
  if (
    !Array.isArray(start) || start.length !== 2 ||
    !Array.isArray(entry) || entry.length !== 2 ||
    !Array.isArray(exit) || exit.length !== 2 ||
    ![...start, ...entry, ...exit, radius].every(Number.isFinite) || radius < 0
  ) {
    throw new TypeError("Corner geometry must contain finite coordinates and a nonnegative radius");
  }
  const point = (x, y) => [
    start[0] + radius * (entry[0] * x + exit[0] * y),
    start[1] + radius * (entry[1] * x + exit[1] * y),
  ];
  context.curveTo(...point(0.12, 0), ...point(0.56, 0), ...point(0.78, 0.22));
  context.curveTo(...point(1, 0.44), ...point(1, 0.88), ...point(1, 1));
}

// Arc length of one continuous corner of unit radius, sampled once from its two cubics.
const unitCornerLength = (() => {
  const segments = [];
  continuousCorner({ curveTo: (...points) => segments.push(points) }, [0, 0], 1, [1, 0], [0, 1]);
  let length = 0;
  let from = [0, 0];
  for (const [x1, y1, x2, y2, x3, y3] of segments) {
    const start = from;
    for (let step = 1; step <= 64; step += 1) {
      const t = step / 64, u = 1 - t;
      const point = [
        u * u * u * start[0] + 3 * u * u * t * x1 + 3 * u * t * t * x2 + t * t * t * x3,
        u * u * u * start[1] + 3 * u * u * t * y1 + 3 * u * t * t * y2 + t * t * t * y3,
      ];
      length += Math.hypot(point[0] - from[0], point[1] - from[1]);
      from = point;
    }
  }
  return length;
})();

// Perimeter of a plain surfaceGeometry contour (no shoulder), for laying dashes along it.
export function surfaceLength(width, height, radius) {
  if (!(width > 0) || !(height > 0)) return 0;
  const r = Math.max(0, Math.min(radius, width / 2, height / 2));
  return 2 * (width + height) - 8 * r + 4 * unitCornerLength * r;
}

// Stretches a dash period so a whole number of dashes closes the contour, leaving no stub at the seam.
export function evenDashPeriod(length, period) {
  if (!(length > 0) || !(period > 0)) return period;
  return length / Math.max(1, Math.round(length / period));
}

// A true capsule (semicircular ends) and its perimeter. Bar-sized pills read as rounded
// rectangles with continuous corners, so pill rims use this instead.
export function capsuleGeometry(width, height) {
  if (!(width > 0) || !(height > 0)) return { path: "", length: 0 };
  const r = Math.min(width, height) / 2;
  const length = 2 * (width + height) - 8 * r + 2 * Math.PI * r;
  if (width >= height) {
    return { length, path: `M ${r} 0 L ${width - r} 0 A ${r} ${r} 0 0 1 ${width - r} ${height}`
      + ` L ${r} ${height} A ${r} ${r} 0 0 1 ${r} 0 Z` };
  }
  return { length, path: `M ${width} ${r} L ${width} ${height - r} A ${r} ${r} 0 0 1 0 ${height - r}`
    + ` L 0 ${r} A ${r} ${r} 0 0 1 ${width} ${r} Z` };
}
