// Colors taken from a wallpaper: accent candidates for the theme and the luminance
// stops that recolor a wallpaper toward the theme. Works in OKLab so hue and lightness
// stay perceptual; neutral images give no candidates instead of a muddy accent.
import { isHexColor, resolveTheme } from './theme.mjs';

const clamp = (value, low, high) => Math.min(high, Math.max(low, value));
const toLinear = value => value <= 0.04045 ? value / 12.92 : ((value + 0.055) / 1.055) ** 2.4;
const toGamma = value => value <= 0.0031308 ? value * 12.92 : 1.055 * value ** (1 / 2.4) - 0.055;

export function hexToRgb(hex) {
  return [1, 3, 5].map(index => parseInt(hex.slice(index, index + 2), 16));
}

export function rgbToHex(rgb) {
  return '#' + rgb.map(value => clamp(Math.round(value), 0, 255).toString(16).padStart(2, '0')).join('').toUpperCase();
}

export function rgbToOklab([r, g, b]) {
  const [lr, lg, lb] = [r, g, b].map(value => toLinear(value / 255));
  const l = Math.cbrt(0.4122214708 * lr + 0.5363325363 * lg + 0.0514459929 * lb);
  const m = Math.cbrt(0.2119034982 * lr + 0.6806995451 * lg + 0.1073969566 * lb);
  const s = Math.cbrt(0.0883024619 * lr + 0.2817188376 * lg + 0.6299787005 * lb);
  return [
    0.2104542553 * l + 0.793617785 * m - 0.0040720468 * s,
    1.9779984951 * l - 2.428592205 * m + 0.4505937099 * s,
    0.0259040371 * l + 0.7827717662 * m - 0.808675766 * s,
  ];
}

// Linear sRGB channels in 0..1; values outside that range mean the color is out of gamut.
function oklabToLinear([L, a, b]) {
  const l = (L + 0.3963377774 * a + 0.2158037573 * b) ** 3;
  const m = (L - 0.1055613458 * a - 0.0638541728 * b) ** 3;
  const s = (L - 0.0894841775 * a - 1.291485548 * b) ** 3;
  return [
    4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
    -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
    -0.0041960863 * l - 0.7034186147 * m + 1.707614701 * s,
  ];
}

export function oklabToRgb(lab) {
  return oklabToLinear(lab).map(value => toGamma(clamp(value, 0, 1)) * 255);
}

function inGamut(lab) {
  return oklabToLinear(lab).every(value => value >= -0.0005 && value <= 1.0005);
}

function fromLch(L, C, h) {
  return [L, C * Math.cos(h), C * Math.sin(h)];
}

// Lowers chroma until the color fits sRGB, keeping lightness and hue.
function fitGamut(L, C, h) {
  let low = 0;
  let high = C;
  if (inGamut(fromLch(L, C, h))) return fromLch(L, C, h);
  for (let step = 0; step < 24; step++) {
    const mid = (low + high) / 2;
    if (inGamut(fromLch(L, mid, h))) low = mid; else high = mid;
  }
  return fromLch(L, low, h);
}

function luminance(rgb) {
  const [r, g, b] = rgb.map(value => toLinear(clamp(value, 0, 255) / 255));
  return 0.2126 * r + 0.7152 * g + 0.0722 * b;
}

export function contrastRatio(first, second) {
  const a = luminance(hexToRgb(first));
  const b = luminance(hexToRgb(second));
  return (Math.max(a, b) + 0.05) / (Math.min(a, b) + 0.05);
}

export function mixOklab(first, second, amount) {
  const a = rgbToOklab(hexToRgb(first));
  const b = rgbToOklab(hexToRgb(second));
  return rgbToHex(oklabToRgb(a.map((value, index) => value + (b[index] - value) * amount)));
}

const HUE_BINS = 36;
const NEUTRAL_CHROMA = 0.035;
const MIN_CHROMATIC_SHARE = 0.03;
const MIN_CONTRAST = 3;

function hueDistance(first, second) {
  const delta = Math.abs(first - second) % (2 * Math.PI);
  return Math.min(delta, 2 * Math.PI - delta);
}

// `pixels` is RGBA bytes (Canvas ImageData or any array-like). Returns up to `count`
// accents, each already readable against the theme surface, ordered by how much of the
// image carries that hue; an empty list means the image is neutral.
export function accentCandidates(pixels, options = {}) {
  const appearance = options.appearance === 'light' ? 'light' : 'dark';
  const count = Number.isInteger(options.count) && options.count > 0 ? options.count : 5;
  const surface = resolveTheme({ appearance, accent: '#869677', fontFamily: 'Geist', reducedMotion: false }).surface;
  const bins = Array.from({ length: HUE_BINS }, () => ({ weight: 0, L: 0, a: 0, b: 0 }));
  let total = 0;
  let chromatic = 0;
  const length = pixels && pixels.length ? pixels.length - (pixels.length % 4) : 0;
  for (let index = 0; index < length; index += 4) {
    if (pixels[index + 3] < 128) continue;
    total++;
    const [L, a, b] = rgbToOklab([pixels[index], pixels[index + 1], pixels[index + 2]]);
    const C = Math.hypot(a, b);
    if (C < NEUTRAL_CHROMA || L < 0.12 || L > 0.97) continue;
    chromatic++;
    const hue = (Math.atan2(b, a) + 2 * Math.PI) % (2 * Math.PI);
    const bin = bins[Math.floor(hue / (2 * Math.PI) * HUE_BINS) % HUE_BINS];
    // Vivid pixels count more than dull ones, so a small saturated subject can still win
    // over a large washed-out area, but area keeps mattering.
    const weight = Math.min(C, 0.2);
    bin.weight += weight;
    bin.L += L * weight;
    bin.a += a * weight;
    bin.b += b * weight;
  }
  if (!total || chromatic / total < MIN_CHROMATIC_SHARE) return [];
  const smooth = bins.map((bin, index) => bins[(index + HUE_BINS - 1) % HUE_BINS].weight + 2 * bin.weight
    + bins[(index + 1) % HUE_BINS].weight);
  const allWeight = bins.reduce((sum, bin) => sum + bin.weight, 0);
  const order = smooth.map((weight, index) => ({ weight, index })).sort((x, y) => y.weight - x.weight);
  const picked = [];
  for (const peak of order) {
    // Smoothed weights span four bin weights; a hue below ~1.5 % of the color mass is noise.
    if (picked.length >= count || peak.weight < 0.06 * allWeight) break;
    const merged = [-1, 0, 1].map(offset => bins[(peak.index + offset + HUE_BINS) % HUE_BINS])
      .reduce((sum, bin) => ({ weight: sum.weight + bin.weight, L: sum.L + bin.L, a: sum.a + bin.a, b: sum.b + bin.b }),
        { weight: 0, L: 0, a: 0, b: 0 });
    if (!merged.weight) continue;
    const hue = Math.atan2(merged.b, merged.a);
    if (picked.some(entry => hueDistance(entry.hue, hue) < Math.PI * 35 / 180)) continue;
    picked.push({ hue, L: merged.L / merged.weight, C: Math.hypot(merged.a, merged.b) / merged.weight,
      share: merged.weight / allWeight });
  }
  return picked.map(entry => ({ hex: readableAccent(entry, appearance, surface), share: Math.round(entry.share * 1000) / 1000 }))
    .filter((entry, index, list) => list.findIndex(other => other.hex === entry.hex) === index);
}

// Moves a sampled color into the band where Pentad's accents live for the appearance,
// then lightens (dark) or darkens (light) it until it reads on the surface.
function readableAccent(entry, appearance, surface) {
  const dark = appearance === 'dark';
  let L = dark ? clamp(entry.L, 0.62, 0.8) : clamp(entry.L, 0.36, 0.52);
  const C = clamp(entry.C, 0.06, 0.17);
  let hex = rgbToHex(oklabToRgb(fitGamut(L, C, entry.hue)));
  for (let step = 0; step < 30 && contrastRatio(hex, surface) < MIN_CONTRAST; step++) {
    L = clamp(L + (dark ? 0.02 : -0.02), 0, 1);
    hex = rgbToHex(oklabToRgb(fitGamut(L, C, entry.hue)));
  }
  return hex;
}

// Five luminance stops (position 0..1 -> color) mapping a grayscale wallpaper onto the
// theme: shadows sink into the surface, highlights carry the accent toward the text color.
// With the default dark theme this reproduces the Moldavite map.
export function recolorStops(theme) {
  const tokens = resolveTheme(Object.assign({ appearance: 'dark', accent: '#869677', fontFamily: 'Geist', reducedMotion: false }, theme));
  if (!isHexColor(tokens.accent)) throw new TypeError('Invalid accent');
  if (theme && theme.appearance === 'light') {
    return [
      [0, mixOklab(tokens.text, tokens.accent, 0.2)],
      [0.35, tokens.accent],
      [0.65, mixOklab(tokens.accent, tokens.surface, 0.55)],
      [0.85, tokens.surfaceRaised],
      [1, tokens.surface],
    ];
  }
  return [
    [0, tokens.surface],
    [0.2, tokens.surfaceRaised],
    [0.5, mixOklab(tokens.surface, tokens.accent, 0.42)],
    [0.75, tokens.accent],
    [1, mixOklab(tokens.text, tokens.accent, 0.08)],
  ];
}

export function stopsArgument(stops) {
  return stops.map(([position, hex]) => position + ':' + hex).join(',');
}
