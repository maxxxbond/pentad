import { mimeMatches } from './tool-catalog.mjs';

// Declarative actions for the sidebar file tools. Each action names an operation of
// tools/pentad_file_tool.py, which validates everything again before running a CLI.
export const LOCAL_FILE = 'application/x-pentad-local-file';
const MINUTE = 60000;
const ARCHIVES = ['application/zip', 'application/x-7z-compressed', 'application/vnd.rar', 'application/x-rar-compressed',
  'application/x-tar', 'application/gzip', 'application/x-gzip', 'application/x-xz', 'application/zstd', 'application/x-bzip2',
  'application/x-compressed-tar', 'application/x-zstd-compressed-tar', 'application/x-xz-compressed-tar', 'application/java-archive'];

const choice = (id, label, choices, value) => ({ id, label, type: 'choice', default: value, choices: choices.map(([key, text]) => ({ id: key, text })) });
const text = (id, label, placeholder, required = true, pattern = null) => ({ id, label, type: 'text', placeholder, required, pattern });
const password = (id = 'password', label = 'Password', required = true) => ({ id, label, type: 'password', placeholder: label, required });
// Object spread is unavailable in Qt's JavaScript engine, so patterns travel as parameters.
const pages = (required = true) => text('pages', 'Pages', required ? '1-3, 5, 8-' : 'All pages', required, /^(?:[\d\s,-]|z|end|last)*$/i);

const toolActions = {
  'pentad.pdf': [
    { id: 'pdf.compress', label: 'Compress', verb: 'Compress', options: [choice('level', 'Quality', [['screen', 'Small'], ['ebook', 'Balanced'], ['printer', 'High']], 'ebook')], timeoutMs: 15 * MINUTE },
    { id: 'pdf.extract', label: 'Extract pages', verb: 'Extract', max: 1, options: [pages()] },
    { id: 'pdf.delete', label: 'Delete pages', verb: 'Delete pages', max: 1, options: [pages()] },
    { id: 'pdf.merge', label: 'Merge', verb: 'Merge', min: 2, timeoutMs: 10 * MINUTE },
    { id: 'pdf.split', label: 'Split', verb: 'Split', max: 1, options: [choice('every', 'Every', [['1', 'Page'], ['2', '2 pages'], ['5', '5 pages'], ['10', '10 pages']], '1')] },
    { id: 'pdf.rotate', label: 'Rotate', verb: 'Rotate', options: [choice('angle', 'Turn', [['90', 'Right'], ['180', 'Upside down'], ['270', 'Left']], '90'), pages(false)] },
    { id: 'pdf.images', label: 'To images', verb: 'Render', max: 1, options: [choice('format', 'Format', [['png', 'PNG'], ['jpeg', 'JPEG']], 'png'), choice('dpi', 'Resolution', [['72', '72 dpi'], ['150', '150 dpi'], ['300', '300 dpi']], '150')], timeoutMs: 15 * MINUTE },
    { id: 'pdf.text', label: 'To text', verb: 'Extract text', max: 1, textResult: true },
    { id: 'pdf.unlock', label: 'Unlock', verb: 'Unlock', max: 1, options: [password()] },
    { id: 'pdf.lock', label: 'Protect', verb: 'Protect', max: 1, options: [password('password', 'New password')] },
  ],
  'pentad.images': [
    { id: 'image.convert', label: 'Convert', verb: 'Convert', options: [choice('format', 'Format', [['jpg', 'JPG'], ['png', 'PNG'], ['webp', 'WebP'], ['avif', 'AVIF'], ['heic', 'HEIC']], 'jpg')] },
    { id: 'image.resize', label: 'Resize', verb: 'Resize', options: [choice('size', 'Longest side', [['3840', '3840'], ['2560', '2560'], ['1920', '1920'], ['1280', '1280'], ['640', '640'], ['50%', 'Half']], '1920')] },
    { id: 'image.compress', label: 'Compress', verb: 'Compress', options: [choice('quality', 'Quality', [['60', 'Small'], ['75', 'Balanced'], ['85', 'High']], '75')] },
    { id: 'image.strip', label: 'Remove metadata', verb: 'Remove metadata' },
    { id: 'image.rotate', label: 'Rotate', verb: 'Rotate', options: [choice('transform', 'Turn', [['90', 'Right'], ['270', 'Left'], ['180', '180°'], ['flip-h', 'Mirror'], ['flip-v', 'Flip']], '90')] },
    { id: 'image.pdf', label: 'To PDF', verb: 'Make PDF', timeoutMs: 10 * MINUTE },
  ],
  'pentad.image-text': [
    { id: 'image.ocr', label: 'Recognize text', verb: 'Recognize', max: 20, textResult: true, options: [{ id: 'language', label: 'Language', type: 'choice', source: 'ocr-languages', default: 'eng', choices: [] }], timeoutMs: 10 * MINUTE },
    { id: 'image.barcode', label: 'Read QR code', verb: 'Read', max: 20, textResult: true },
  ],
  'pentad.media': [
    { id: 'media.video', label: 'Compress video', verb: 'Compress', accepts: ['video/*'], max: 20, options: [choice('quality', 'Quality', [['small', 'Small'], ['balanced', 'Balanced'], ['high', 'High']], 'balanced'), choice('height', 'Size', [['keep', 'Original'], ['1080', '1080p'], ['720', '720p'], ['480', '480p']], 'keep')], timeoutMs: 120 * MINUTE },
    { id: 'media.gif', label: 'To GIF', verb: 'Make GIF', accepts: ['video/*'], max: 10, options: [choice('width', 'Width', [['320', '320'], ['480', '480'], ['640', '640'], ['800', '800']], '480'), choice('fps', 'Frame rate', [['10', '10 fps'], ['15', '15 fps'], ['24', '24 fps']], '15')], timeoutMs: 30 * MINUTE },
    { id: 'media.audio', label: 'Audio', verb: 'Convert', options: [choice('format', 'Format', [['mp3', 'MP3'], ['m4a', 'M4A'], ['opus', 'Opus'], ['flac', 'FLAC'], ['wav', 'WAV']], 'mp3')], timeoutMs: 60 * MINUTE },
    { id: 'media.trim', label: 'Trim', verb: 'Trim', max: 1, options: [text('start', 'From', '0:00', false, /^[\d:.\s]*$/), text('end', 'To', 'End', false, /^[\d:.\s]*$/)], timeoutMs: 30 * MINUTE },
  ],
  'pentad.archive': [
    { id: 'archive.extract', label: 'Extract', verb: 'Extract', accepts: ARCHIVES, max: 20, options: [password('password', 'Password, if any', false)], timeoutMs: 20 * MINUTE },
    { id: 'archive.create', label: 'Compress', verb: 'Pack', options: [choice('format', 'Format', [['zip', 'ZIP'], ['7z', '7z'], ['tar.zst', 'tar.zst']], 'zip')], timeoutMs: 30 * MINUTE },
  ],
  'pentad.checksum': [
    { id: 'checksum', label: 'Checksum', verb: 'Calculate', textResult: true, options: [choice('algorithm', 'Algorithm', [['sha256', 'SHA-256'], ['sha512', 'SHA-512'], ['sha1', 'SHA-1'], ['md5', 'MD5'], ['blake2b', 'BLAKE2b']], 'sha256'), text('expected', 'Compare with', 'Expected hash (optional)', false)], timeoutMs: 20 * MINUTE },
  ],
};

export const dialogFilters = {
  'pentad.pdf': ['PDF documents (*.pdf *.PDF)'],
  'pentad.images': ['Images (*.png *.jpg *.jpeg *.webp *.avif *.heic *.heif *.gif *.bmp *.tif *.tiff *.svg *.jxl)'],
  'pentad.image-text': ['Images (*.png *.jpg *.jpeg *.webp *.avif *.heic *.gif *.bmp *.tif *.tiff)'],
  'pentad.media': ['Video and audio (*.mp4 *.mkv *.webm *.mov *.avi *.m4v *.mp3 *.m4a *.opus *.ogg *.flac *.wav *.aac)'],
  'pentad.archive': ['All files (*)'],
  'pentad.checksum': ['All files (*)'],
};

const OCR_NAMES = { eng: 'English', ukr: 'Ukrainian', rus: 'Russian', deu: 'German', fra: 'French', spa: 'Spanish',
  ita: 'Italian', pol: 'Polish', por: 'Portuguese', ces: 'Czech', nld: 'Dutch', tur: 'Turkish', jpn: 'Japanese',
  chi_sim: 'Chinese', kor: 'Korean', ara: 'Arabic', afr: 'Afrikaans', bel: 'Belarusian', heb: 'Hebrew' };

export function actionsFor(toolId) { return toolActions[toolId] || []; }

function itemTypes(item) { return item.compatibleTypes || [item.mimeType]; }

export function actionAccepts(action, items) {
  const count = (items || []).length;
  if (count < (action.min || 1) || count > (action.max || 100)) return false;
  return !action.accepts || items.every(item => itemTypes(item).some(type => mimeMatches(action.accepts, type)));
}

export function availableActions(toolId, items) {
  return actionsFor(toolId).filter(action => !(items || []).length || actionAccepts(action, items));
}

// Keeps the chosen action while it still fits; otherwise picks the first that does.
export function pickAction(toolId, items, current) {
  const available = availableActions(toolId, items);
  return (available.find(action => action.id === current) || available[0] || null)?.id || '';
}

export function findAction(toolId, id) { return actionsFor(toolId).find(action => action.id === id) || null; }

export function defaultOptions(action) {
  const options = {};
  for (const option of action?.options || []) options[option.id] = option.default ?? '';
  return options;
}

export function languageChoices(codes) {
  return (codes || []).map(code => ({ id: code, text: OCR_NAMES[code] || code }))
    .sort((a, b) => (a.id === 'eng' ? -1 : b.id === 'eng' ? 1 : a.text.localeCompare(b.text)));
}

export function validate(action, items, options) {
  if (!action) return { ok: false, reason: 'Choose an action' };
  const count = (items || []).length;
  if (!count) return { ok: false, reason: 'Add files first' };
  if (count < (action.min || 1)) return { ok: false, reason: `${action.label} needs at least ${action.min} files` };
  if (count > (action.max || 100)) return { ok: false, reason: action.max === 1 ? `${action.label} works on one file at a time` : `${action.label} takes up to ${action.max} files` };
  if (!actionAccepts(action, items)) return { ok: false, reason: `${action.label} does not support some of these files` };
  for (const option of action.options || []) {
    const value = String(options?.[option.id] ?? '');
    if (option.required && !value.trim()) return { ok: false, reason: `Enter ${option.label.toLowerCase()}` };
    if (option.pattern && !option.pattern.test(value)) return { ok: false, reason: `Check ${option.label.toLowerCase()}` };
    if (option.type === 'password' && /[\r\n]/.test(value)) return { ok: false, reason: 'The password cannot contain line breaks' };
  }
  return { ok: true };
}

export function requestFor(action, items, options) {
  const values = {};
  for (const option of action.options || []) {
    const value = options?.[option.id];
    if (value === undefined || value === null || String(value).trim() === '') continue;
    values[option.id] = option.type === 'password' ? String(value) : String(value).trim();
  }
  return { operation: action.id, inputs: items.map(item => item.uri), options: values, timeoutMs: action.timeoutMs || 5 * MINUTE };
}

// Accepts only local file references the tool understands; merges with the current list on append.
export function mergeFiles(current, incoming, accepts, choice = '') {
  const files = (incoming || []).filter(item => typeof item?.uri === 'string' && item.uri.startsWith('file://'));
  if (!files.length || files.length !== (incoming || []).length) return { ok: false, reason: 'Only local files can be used here' };
  if (files.some(item => !itemTypes(item).some(type => mimeMatches(accepts, type)))) return { ok: false, reason: 'This tool does not support some of these files' };
  if ((current || []).length && !choice) return { ok: false, reason: 'choose-replace-or-append' };
  const base = choice === 'append' ? current || [] : [];
  const seen = new Set(base.map(item => item.uri));
  const merged = base.concat(files.filter(item => !seen.has(item.uri) && seen.add(item.uri)));
  if (merged.length > 100) return { ok: false, reason: 'Up to 100 files at a time' };
  return { ok: true, files: merged.map(item => ({ kind: 'file', uri: item.uri, name: item.name || fileName(item.uri),
    mimeType: item.mimeType || 'application/octet-stream', sizeBytes: Number.isFinite(item.sizeBytes) ? item.sizeBytes : -1,
    compatibleTypes: itemTypes(item).includes(LOCAL_FILE) ? itemTypes(item) : itemTypes(item).concat([LOCAL_FILE]) })) };
}

export function fileName(uri) {
  const last = String(uri || '').replace(/\/+$/, '').split('/').pop() || '';
  try { return decodeURIComponent(last); } catch (error) { return last; }
}

export function parentUri(uri) { return String(uri || '').replace(/\/[^/]*\/?$/, '') || 'file:///'; }

export function formatBytes(bytes) {
  if (!Number.isFinite(bytes) || bytes < 0) return '';
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  let value = bytes, unit = 0;
  while (value >= 1024 && unit < units.length - 1) { value /= 1024; unit++; }
  return unit ? `${value < 10 ? value.toFixed(1) : Math.round(value)} ${units[unit]}` : `${bytes} B`;
}

export function runLabel(action, count) {
  if (!action) return 'Run';
  return count > 1 && (action.max || 100) > 1 && action.id !== 'pdf.merge' && action.id !== 'image.pdf'
    && action.id !== 'archive.create' ? `${action.verb} ${count} files` : action.verb;
}

// Published outputs become hand-off items for other tools; folders stay openable only.
export function outputItems(result) {
  return ((result && result.outputs) || []).filter(item => item.kind === 'file')
    .map(item => ({ kind: 'file', uri: item.uri, name: item.name, mimeType: item.mimeType, sizeBytes: item.sizeBytes,
      compatibleTypes: [item.mimeType, LOCAL_FILE] }));
}
