import { surfaceGeometry } from "./continuous-corners.mjs";

export function barTooltipGeometry(width, height, shoulder = 16, radius = shoulder) {
  if (![width, height, shoulder, radius].every(Number.isFinite)
      || [width, height, shoulder, radius].some(value => value < 0)) {
    throw new TypeError("Tooltip geometry must contain finite nonnegative dimensions");
  }
  if (width === 0 || height === 0)
    return { path: "", contentLeft: 0, contentRight: 0, bodyTop: 0 };

  const surface = surfaceGeometry(width, height, radius, shoulder);
  return {
    path: surface.path,
    contentLeft: surface.shoulder, contentRight: width - surface.shoulder, bodyTop: 0,
  };
}
