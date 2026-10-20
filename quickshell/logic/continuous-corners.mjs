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
