// The wallpaper document: one image for every screen, optional per-screen overrides,
// the folder the picker browses and how the image fills a screen.

export const imageExtensions = Object.freeze(['jpg', 'jpeg', 'png', 'webp', 'avif', 'bmp', 'gif', 'tif', 'tiff']);
export const fillModes = Object.freeze(['crop', 'fit', 'stretch', 'center']);
// Wipe, disc, pixelate and iris are drawn by a shader in WallpaperWindow during the change.
export const shaderTransitions = Object.freeze(['wipe', 'disc', 'pixelate', 'iris']);
export const animatedTransitions = Object.freeze(['fade'].concat(shaderTransitions));
// 'random' picks one of the animated transitions for every change.
export const transitions = Object.freeze(animatedTransitions.concat(['random', 'none']));
// 'theme' shows a copy of each image recolored toward the theme palette.
export const tints = Object.freeze(['none', 'theme']);
// How often the wallpaper changes itself; 'off' leaves it alone.
export const rotateIntervals = Object.freeze(['off', '15m', '30m', '1h', '3h', '1d']);
const rotateSecondsByInterval = Object.freeze({ off: 0, '15m': 900, '30m': 1800, '1h': 3600, '3h': 10800, '1d': 86400 });

// Seconds between automatic wallpaper changes; 0 (for 'off' or an unknown value) means never.
export function rotateSeconds(value) {
  return rotateSecondsByInterval[value] || 0;
}

export const wallpaperDefaults = Object.freeze({
  schemaVersion: 1,
  path: '',
  directory: '~/Pictures/Wallpapers',
  fill: 'crop',
  transition: 'fade',
  outputs: Object.freeze({}),
  accentFromWallpaper: false,
  tint: 'none',
  rotate: 'off',
});

const object = value => value !== null && typeof value === 'object' && !Array.isArray(value);
const MAX_PATH = 4096;
const validPath = value => typeof value === 'string' && value.length <= MAX_PATH && !/[\x00-\x1f\x7f]/.test(value);
// Stored paths are absolute or home-relative, so a config never depends on the shell's cwd.
const rootedPath = value => validPath(value) && (value === '' || value.startsWith('/') || value === '~' || value.startsWith('~/'));
const outputName = value => typeof value === 'string' && /^[\w.:+-]{1,64}$/.test(value);

export function parseWallpaper(input) {
  if (!object(input)) throw new Error('Wallpaper document must be an object');
  const value = Object.assign({}, wallpaperDefaults, input);
  if (value.schemaVersion !== 1) throw new Error('Unsupported wallpaper version');
  if (!rootedPath(value.path)) throw new Error('Invalid wallpaper path');
  if (!rootedPath(value.directory) || value.directory === '') throw new Error('Invalid wallpaper folder');
  if (!fillModes.includes(value.fill)) throw new Error('Invalid wallpaper fill');
  if (!transitions.includes(value.transition)) throw new Error('Invalid wallpaper transition');
  if (typeof value.accentFromWallpaper !== 'boolean') throw new Error('Invalid accent source');
  if (!tints.includes(value.tint)) throw new Error('Invalid wallpaper tint');
  if (!rotateIntervals.includes(value.rotate)) throw new Error('Invalid wallpaper rotation');
  if (!object(value.outputs)) throw new Error('Invalid per-screen wallpapers');
  const outputs = {};
  for (const [name, path] of Object.entries(value.outputs)) {
    if (!outputName(name) || !rootedPath(path) || path === '') throw new Error('Invalid per-screen wallpaper');
    outputs[name] = path;
  }
  return Object.assign(value, { outputs });
}

export function expandHome(path, home) {
  if (path === '~') return home;
  return typeof path === 'string' && path.startsWith('~/') ? home.replace(/\/+$/, '') + path.slice(1) : path;
}

// Keeps paths under HOME home-relative, which survives a renamed user directory.
export function collapseHome(path, home) {
  const root = String(home || '').replace(/\/+$/, '');
  if (!root || typeof path !== 'string') return path;
  if (path === root) return '~';
  return path.startsWith(root + '/') ? '~' + path.slice(root.length) : path;
}

export function fileUrlToPath(url) {
  const text = String(url || '');
  if (!text.startsWith('file://')) return text;
  return decodeURIComponent(text.slice('file://'.length).replace(/^localhost/, ''));
}

export function isImagePath(path) {
  const match = /\.([a-z0-9]+)$/i.exec(String(path || ''));
  return !!match && imageExtensions.includes(match[1].toLowerCase());
}

export function wallpaperFor(document, output) {
  const doc = object(document) ? document : wallpaperDefaults;
  const override = output && object(doc.outputs) ? doc.outputs[output] : undefined;
  return override || doc.path || '';
}

// `output` empty sets the shared image; screens with their own image keep it. Choosing the
// shared image for a screen drops that screen's override.
export function withWallpaper(document, path, output) {
  const doc = Object.assign({}, wallpaperDefaults, object(document) ? document : {});
  const outputs = Object.assign({}, doc.outputs);
  if (!output) return Object.assign(doc, { path, outputs });
  if (path === doc.path || !path) delete outputs[output];
  else outputs[output] = path;
  return Object.assign(doc, { outputs });
}

// Next image for "random": never the one already shown when there is any other choice.
export function pickRandom(paths, current, random = Math.random) {
  const list = Array.isArray(paths) ? paths.filter(isImagePath) : [];
  const others = list.filter(path => path !== current);
  const pool = others.length ? others : list;
  if (!pool.length) return '';
  return pool[Math.min(pool.length - 1, Math.floor(random() * pool.length))];
}

// The transition one change uses: the document's choice, with 'random' resolved to one of the
// animated transitions. A value this version does not know falls back to the default fade.
export function pickTransition(document, random = Math.random) {
  const choice = object(document) ? document.transition : undefined;
  if (choice !== 'random') return transitions.includes(choice) ? choice : wallpaperDefaults.transition;
  const index = Math.floor(Number(random()) * animatedTransitions.length);
  return animatedTransitions[index >= 0 && index < animatedTransitions.length ? index : 0];
}

// Where a shader transition starts: the side a wipe enters from (0 left, 1 right, 2 top,
// 3 bottom) and the centre of a disc, kept away from the screen's edges.
export function transitionOrigin(random = Math.random) {
  const unit = () => {
    const value = Number(random());
    return value >= 0 && value < 1 ? value : 0.5;
  };
  return { direction: Math.floor(unit() * 4), x: 0.2 + 0.6 * unit(), y: 0.2 + 0.6 * unit() };
}

// Next or previous image in folder order, wrapping around.
export function stepWallpaper(paths, current, direction) {
  const list = Array.isArray(paths) ? paths.filter(isImagePath) : [];
  if (!list.length) return '';
  const index = list.indexOf(current);
  if (index < 0) return direction < 0 ? list[list.length - 1] : list[0];
  return list[(index + (direction < 0 ? -1 : 1) + list.length) % list.length];
}

export function displayName(path) {
  const base = String(path || '').split('/').pop() || '';
  return base.replace(/\.[^.]+$/, '').replace(/[-_]+/g, ' ').trim() || base;
}
