const isObject = value => value !== null && typeof value === 'object' && !Array.isArray(value);
const clone = value => JSON.parse(JSON.stringify(value));
const flagMap = (items, pick) => { const result = {}; for (const item of items) result[item.id] = pick(item); return Object.freeze(result); };

// Bar tools live in two pills: toggles on the left, one-shot actions on the right.
// `icon` is relative to assets/icons/material/. `visible` is the default for a fresh config.
export const barTools = Object.freeze([
  { id: 'dnd', kind: 'toggle', icon: 'notifications-off-symbolic.svg', labelUk: 'Не турбувати', labelEn: 'Do not disturb', visible: true },
  { id: 'inhibit', kind: 'toggle', icon: 'coffee-symbolic.svg', labelUk: 'Не засинати', labelEn: 'Prevent sleep', visible: true },
  { id: 'night', kind: 'toggle', icon: 'controls/dark-mode-symbolic.svg', labelUk: 'Нічне світло', labelEn: 'Night light', visible: false },
  { id: 'bluetooth', kind: 'toggle', icon: 'bluetooth-symbolic.svg', labelUk: 'Bluetooth', labelEn: 'Bluetooth', visible: false },
  { id: 'airplane', kind: 'toggle', icon: 'controls/flight-symbolic.svg', labelUk: 'Режим польоту', labelEn: 'Airplane mode', visible: false },
  { id: 'saver', kind: 'toggle', icon: 'eco-symbolic.svg', labelUk: 'Економія енергії', labelEn: 'Power saver', visible: false },
  { id: 'overnight', kind: 'toggle', icon: 'moon-symbolic.svg', labelUk: 'Нічний режим', labelEn: 'Overnight mode', visible: false },
  { id: 'focus', kind: 'toggle', icon: 'focus-symbolic.svg', labelUk: 'Фокус', labelEn: 'Focus mode', visible: false },
  { id: 'privacy', kind: 'toggle', icon: 'visibility-off-symbolic.svg', labelUk: 'Приховати сповіщення', labelEn: 'Hide notification text', visible: false },
  { id: 'screenshot', kind: 'action', icon: 'screenshot-region-symbolic.svg', labelUk: 'Знімок області', labelEn: 'Area screenshot', visible: true },
  { id: 'record', kind: 'action', icon: 'videocam-symbolic.svg', labelUk: 'Запис області', labelEn: 'Record area', visible: true },
  { id: 'ocr', kind: 'action', icon: 'ocr-symbolic.svg', labelUk: 'Розпізнати текст', labelEn: 'Recognize text', visible: true },
  { id: 'picker', kind: 'action', icon: 'colorize-symbolic.svg', labelUk: 'Піпетка', labelEn: 'Color picker', visible: true },
  { id: 'translate', kind: 'action', icon: 'translate-symbolic.svg', labelUk: 'Перекласти текст', labelEn: 'Translate text', visible: true },
  { id: 'imageSearch', kind: 'action', icon: 'image-search-symbolic.svg', labelUk: 'Пошук за зображенням', labelEn: 'Search by image', visible: true },
  { id: 'qrScan', kind: 'action', icon: 'tools/qr-code-2-symbolic.svg', labelUk: 'Сканувати QR', labelEn: 'Scan QR code', visible: false },
  { id: 'audioOutput', kind: 'action', icon: 'volume-up-symbolic.svg', labelUk: 'Наступний аудіовихід', labelEn: 'Next audio output', visible: false },
  { id: 'ruler', kind: 'action', icon: 'tools/straighten-symbolic.svg', labelUk: 'Лінійка', labelEn: 'Pixel ruler', visible: false },
  { id: 'magnifier', kind: 'action', icon: 'zoom-in-symbolic.svg', labelUk: 'Лупа', labelEn: 'Magnifier', visible: false },
]);

// Actions that run a shell script and block the others until it ends.
export const scriptActions = Object.freeze(['ocr', 'translate', 'image-search', 'qr-scan', 'audio-output', 'ruler', 'magnifier']);
export const magnifierZooms = Object.freeze([2, 3, 4, 6, 8]);

// Engines that accept a pasted clipboard image on their landing page. `upload` marks the ones that also take
// the image as a plain multipart form post, so the picked area is searched without a manual paste.
export const searchEngines = Object.freeze([
  { id: 'google', name: 'Google Lens', url: 'https://lens.google.com/', upload: { url: 'https://lens.google.com/v3/upload?hl=en', field: 'encoded_image' } },
  { id: 'yandex', name: 'Yandex', url: 'https://yandex.com/images/' },
  { id: 'bing', name: 'Bing', url: 'https://www.bing.com/visualsearch' },
  { id: 'tineye', name: 'TinEye', url: 'https://tineye.com/', upload: { url: 'https://tineye.com/search', field: 'image' } },
  { id: 'baidu', name: 'Baidu', url: 'https://graph.baidu.com/pcpage/index?tpl_from=pc' },
  { id: 'sogou', name: 'Sogou', url: 'https://pic.sogou.com/' },
  { id: 'saucenao', name: 'SauceNAO', url: 'https://saucenao.com/', upload: { url: 'https://saucenao.com/search.php', field: 'file' } },
  { id: 'iqdb', name: 'IQDB', url: 'https://iqdb.org/', upload: { url: 'https://iqdb.org/', field: 'file' } },
  { id: 'ascii2d', name: 'ascii2d', url: 'https://ascii2d.net/', upload: { url: 'https://ascii2d.net/search/file', field: 'file' } },
]);

export const colorFormats = Object.freeze(['hex', 'rgb', 'hsl', 'hsv', 'cmyk']);
export const focusFile = '.cache/pentad-focus';
export const inhibitDurations = Object.freeze([0, 900, 1800, 3600, 7200]);

export const overnightEnds = Object.freeze(['07:00', '08:00', '09:00', 'none']);

const targetLanguages = Object.freeze(['UK', 'EN-US', 'EN-GB', 'DE', 'PL', 'FR', 'ES', 'IT', 'PT-PT', 'CS', 'JA', 'ZH']);
export const deeplTargets = targetLanguages;

export const barToolsDefaults = Object.freeze({
  show: flagMap(barTools, tool => tool.visible),
  search: Object.freeze({
    mode: 'ask',
    engine: 'google',
    engines: flagMap(searchEngines, () => true),
  }),
  ocr: Object.freeze({ languages: 'eng' }),
  picker: Object.freeze({ format: 'hex' }),
  magnifier: Object.freeze({ zoom: 3 }),
  translate: Object.freeze({ target: 'EN-US', provider: 'deepl', keyFile: '' }),
  overnight: Object.freeze({ end: '08:00', openrgb: Object.freeze({ start: 'Night', end: 'Day' }), commands: Object.freeze({ start: '', end: '' }) }),
});

const toolIds = new Set(barTools.map(tool => tool.id));
const engineIds = new Set(searchEngines.map(engine => engine.id));

export function parseBarTools(input) {
  if (input === undefined || input === null) return clone(barToolsDefaults);
  if (!isObject(input)) throw new Error('Invalid bar tools');
  const value = clone(barToolsDefaults);
  if (input.show !== undefined) {
    if (!isObject(input.show)) throw new Error('Invalid bar tool visibility');
    for (const [key, shown] of Object.entries(input.show)) {
      if (!toolIds.has(key)) throw new Error('Unknown bar tool: ' + key);
      if (typeof shown !== 'boolean') throw new Error('Invalid bar tool visibility');
      value.show[key] = shown;
    }
  }
  if (input.search !== undefined) {
    const search = input.search;
    if (!isObject(search)) throw new Error('Invalid image search settings');
    if (search.mode !== undefined) {
      if (!['ask', 'direct'].includes(search.mode)) throw new Error('Invalid image search mode');
      value.search.mode = search.mode;
    }
    if (search.engines !== undefined) {
      if (!isObject(search.engines)) throw new Error('Invalid image search engines');
      for (const [key, enabled] of Object.entries(search.engines)) {
        if (!engineIds.has(key)) throw new Error('Unknown image search engine: ' + key);
        if (typeof enabled !== 'boolean') throw new Error('Invalid image search engines');
        value.search.engines[key] = enabled;
      }
    }
    if (search.engine !== undefined) {
      if (!engineIds.has(search.engine)) throw new Error('Unknown image search engine: ' + search.engine);
      value.search.engine = search.engine;
    }
  }
  if (input.ocr !== undefined) {
    if (!isObject(input.ocr)) throw new Error('Invalid OCR settings');
    if (input.ocr.languages !== undefined) {
      if (typeof input.ocr.languages !== 'string' || !/^[a-z_]{3,12}(\+[a-z_]{3,12}){0,5}$/i.test(input.ocr.languages))
        throw new Error('Invalid OCR languages');
      value.ocr.languages = input.ocr.languages;
    }
  }
  if (input.magnifier !== undefined) {
    if (!isObject(input.magnifier)) throw new Error('Invalid magnifier settings');
    if (input.magnifier.zoom !== undefined) {
      if (!magnifierZooms.includes(input.magnifier.zoom)) throw new Error('Invalid magnifier zoom');
      value.magnifier.zoom = input.magnifier.zoom;
    }
  }
  if (input.picker !== undefined) {
    if (!isObject(input.picker)) throw new Error('Invalid picker settings');
    if (input.picker.format !== undefined) {
      if (!colorFormats.includes(input.picker.format)) throw new Error('Invalid color format');
      value.picker.format = input.picker.format;
    }
  }
  if (input.translate !== undefined) {
    const translate = input.translate;
    if (!isObject(translate)) throw new Error('Invalid translate settings');
    if (translate.target !== undefined) {
      if (!targetLanguages.includes(translate.target)) throw new Error('Invalid translation language');
      value.translate.target = translate.target;
    }
    if (translate.provider !== undefined) {
      if (!['deepl', 'google'].includes(translate.provider)) throw new Error('Invalid translation provider');
      value.translate.provider = translate.provider;
    }
    if (translate.keyFile !== undefined) {
      if (typeof translate.keyFile !== 'string' || translate.keyFile.length > 4096 || /[\x00-\x1f]/.test(translate.keyFile)
        || translate.keyFile !== '' && !translate.keyFile.startsWith('/') && !translate.keyFile.startsWith('~/'))
        throw new Error('Invalid API key file');
      value.translate.keyFile = translate.keyFile;
    }
  }
  if (input.overnight !== undefined) {
    const overnight = input.overnight;
    if (!isObject(overnight)) throw new Error('Invalid overnight settings');
    if (overnight.end !== undefined) {
      if (!overnightEnds.includes(overnight.end)) throw new Error('Invalid overnight end');
      value.overnight.end = overnight.end;
    }
    if (overnight.openrgb !== undefined) {
      if (!isObject(overnight.openrgb)) throw new Error('Invalid overnight OpenRGB profiles');
      for (const key of ['start', 'end']) {
        if (overnight.openrgb[key] === undefined) continue;
        if (typeof overnight.openrgb[key] !== 'string' || !/^[\w .-]{1,64}$/.test(overnight.openrgb[key])) throw new Error('Invalid OpenRGB profile');
        value.overnight.openrgb[key] = overnight.openrgb[key];
      }
    }
    if (overnight.commands !== undefined) {
      if (!isObject(overnight.commands)) throw new Error('Invalid overnight commands');
      for (const key of ['start', 'end']) {
        if (overnight.commands[key] === undefined) continue;
        if (typeof overnight.commands[key] !== 'string' || overnight.commands[key].length > 1000) throw new Error('Invalid overnight command');
        value.overnight.commands[key] = overnight.commands[key];
      }
    }
  }
  return value;
}

// The tools to draw, in catalog order: [toggles, actions]. A missing config shows the defaults.
export function visibleTools(config) {
  const show = Object.assign({}, barToolsDefaults.show, isObject(config) && isObject(config.show) ? config.show : {});
  const shown = barTools.filter(tool => show[tool.id] === true);
  return { toggles: shown.filter(tool => tool.kind === 'toggle'), actions: shown.filter(tool => tool.kind === 'action') };
}

export function enabledEngines(config) {
  const flags = Object.assign({}, barToolsDefaults.search.engines,
    isObject(config) && isObject(config.search) && isObject(config.search.engines) ? config.search.engines : {});
  return searchEngines.filter(engine => flags[engine.id] === true);
}

// Direct mode searches at once, but only while the default engine is still enabled and there is
// something to search with; otherwise it falls back to asking.
export function searchPlan(config) {
  const search = isObject(config) && isObject(config.search) ? config.search : {};
  const engines = enabledEngines(config);
  const preferred = engines.find(engine => engine.id === (search.engine || barToolsDefaults.search.engine));
  if (!engines.length) return { kind: 'none', engines };
  if (search.mode === 'direct' && preferred) return { kind: 'direct', engine: preferred, engines };
  return { kind: 'ask', engines };
}

export function searchEngine(id) {
  return searchEngines.find(engine => engine.id === id) || null;
}

export function expandHome(path, home) {
  return path.startsWith('~/') ? String(home || '').replace(/\/$/, '') + path.slice(1) : path;
}

export function focusPath(home) {
  return String(home || '').replace(/\/$/, '') + '/' + focusFile;
}

export function inhibitCommand(seconds) {
  const length = Number.isInteger(seconds) && seconds > 0 && seconds <= 86400 ? String(seconds) : 'infinity';
  return ['systemd-inhibit', '--what=idle:sleep', '--mode=block', '--who=Pentad', '--why=Pentad desktop action', 'sleep', length];
}

export function pickerCommand(format) {
  return ['hyprpicker', '-a', '-f', colorFormats.includes(format) ? format : 'hex'];
}

const languagePattern = /^[a-z_]{3,12}(\+[a-z_]{3,12}){0,5}$/i;
const safeLanguages = languages => languagePattern.test(languages) ? languages : barToolsDefaults.ocr.languages;

// The area is chosen in Pentad's own selection overlay (Screenshot service, `pick`), which hands each
// tool a cropped PNG. The scripts below receive that file as $1 and never select anything themselves.
// A missing program is reported by name instead of failing silently (exit 7).
const need = tools => `for t in ${tools.join(' ')}; do command -v "$t" >/dev/null || { notify-send -a Pentad 'Missing tool' "$t"; exit 7; }; done; `;
// Keep only the OCR languages that are installed, so a missing pack degrades to English.
const installedLanguages = languages => `want='${safeLanguages(languages)}'; langs=''; `
  + 'for l in $(printf %s "$want" | tr + \' \'); do tesseract --list-langs 2>/dev/null | grep -qx "$l" && langs="$langs+$l"; done; '
  + 'langs=${langs#+}; [ -n "$langs" ] || langs=eng; ';
const recognize = languages => `${need(['tesseract', 'wl-copy'])}${installedLanguages(languages)}text=$(tesseract "$1" stdout -l "$langs" --psm 6 2>/dev/null | sed '/^[[:space:]]*$/d') || exit 7; `
  + "[ -n \"$text\" ] || { notify-send -a Pentad 'Pentad' 'No text found'; exit 4; }; ";

// $1: the picked PNG.
export function ocrScript(languages) {
  return `${recognize(languages)}printf %s "$text" | wl-copy; notify-send -a Pentad 'Text copied' "$text"`;
}

// Decode a QR code or barcode in the picked image and copy its text. $1: the picked PNG.
export const qrScript = need(['zbarimg', 'wl-copy']) + 'text=$(zbarimg --quiet --raw "$1" 2>/dev/null); '
  + "[ -n \"$text\" ] || { notify-send -a Pentad 'Pentad' 'No code found'; exit 4; }; "
  + 'printf %s "$text" | wl-copy; notify-send -a Pentad \'Code copied\' "$text"';

// Copy the size of the picked area. $1: "WxH".
export const rulerScript = need(['wl-copy']) + 'printf %s "$1" | wl-copy; notify-send -a Pentad \'Size copied\' "$1 px"';

// What each area-picking tool asks the overlay to say, and how it enlarges the crop.
export const regionActions = Object.freeze(['ocr', 'translate', 'image-search', 'qr-scan', 'ruler', 'magnifier', 'record']);
export function pickLabel(kind, text) {
  const labels = {
    ocr: text('Розпізнати текст', 'Recognize text'),
    translate: text('Перекласти текст', 'Translate text'),
    'image-search': text('Пошук за зображенням', 'Search by image'),
    'qr-scan': text('Сканувати QR', 'Scan QR code'),
    ruler: text('Лінійка', 'Pixel ruler'),
    magnifier: text('Лупа', 'Magnifier'),
    record: text('Запис області', 'Record area'),
  };
  return labels[kind] || '';
}

// Switch the default sink to the next one and move running streams along with it.
export const audioOutputScript = need(['pactl']) + "cur=$(pactl get-default-sink); "
  + "next=$(pactl list short sinks | cut -f2 | awk -v cur=\"$cur\" '{a[NR]=$0; if ($0==cur) i=NR} END {print a[i%NR+1]}'); "
  + '[ -n "$next" ] && [ "$next" != "$cur" ] || { notify-send -a Pentad \'Audio\' \'No other output\'; exit 4; }; '
  + 'pactl set-default-sink "$next" || exit 5; '
  + 'for id in $(pactl list short sink-inputs | cut -f1); do pactl move-sink-input "$id" "$next"; done; '
  + "name=$(pactl list sinks | awk -v n=\"$next\" '$1==\"Name:\" {m=($2==n)} m && /Description:/ {sub(/^[ \\t]*Description: /, \"\"); print; exit}'); "
  + 'notify-send -a Pentad \'Audio output\' "${name:-$next}"';

// The image goes to the clipboard (Ctrl+V works on any search page) and each engine is turned into a page to open.
// $1: the picked PNG; every further argument is "landing url|upload url|upload field". Engines with an upload form
// get a local page that posts the image to them by itself; the others get their landing page. One URL per line.
export const imageCaptureScript = `${need(['wl-copy', 'base64'])}wl-copy --type image/png < "$1"; `
  + 'dir="${XDG_RUNTIME_DIR:-/tmp}/pentad-image-search"; mkdir -p "$dir" && chmod 700 "$dir"; '
  + 'find "$dir" -type f -mmin +10 -delete 2>/dev/null; b64=$(base64 -w0 "$1"); shift; n=0; '
  + 'for spec; do landing=${spec%%|*}; rest=${spec#*|}; up=${rest%%|*}; field=${rest#*|}; '
  + '[ -n "$up" ] && [ -n "$field" ] || { printf \'%s\\n\' "$landing"; continue; }; '
  + 'n=$((n+1)); f="$dir/search-$$-$n.html"; '
  + '{ printf \'<!doctype html><meta charset=utf-8><title>Searching…</title><form id=f method=post enctype=multipart/form-data action="%s"><input type=file id=i name="%s"></form><script>\' "$up" "$field"; '
  + 'printf \'const b=atob("%s"),a=new Uint8Array(b.length);for(let k=0;k<b.length;k++)a[k]=b.charCodeAt(k);\' "$b64"; '
  + 'printf \'const d=new DataTransfer();d.items.add(new File([a],"image.png",{type:"image/png"}));i.files=d.files;f.submit();</script>\'; } > "$f"; '
  + 'printf \'file://%s\\n\' "$f"; done';

// OCR, then DeepL through curl. The API key is read from a file and handed to curl on stdin,
// so it never appears in a process listing. Free keys end in ":fx" and use the free endpoint.
export function translateScript(options) {
  const target = targetLanguages.includes(options.target) ? options.target : barToolsDefaults.translate.target;
  const ocr = recognize(options.languages);
  if (options.provider === 'google')
    return `${ocr}out=$(printf %s "$text" | trans -b :${target.slice(0, 2).toLowerCase()}) || exit 5; `
      + 'printf %s "$out" | wl-copy; notify-send -a Pentad \'Translation copied\' "$out"';
  // $1: the picked PNG, $2: the file holding the DeepL key.
  return 'key=$(tr -d \'[:space:]\' < "$2" 2>/dev/null); [ -n "$key" ] || { notify-send -a Pentad \'DeepL\' \'Set an API key file in settings\'; exit 3; }; '
    + need(['curl', 'jq']) + ocr
    + 'case "$key" in *:fx) url=https://api-free.deepl.com/v2/translate;; *) url=https://api.deepl.com/v2/translate;; esac; '
    + 'out=$(printf \'header = "Authorization: DeepL-Auth-Key %s"\\n\' "$key" | '
    + `curl -sS --fail-with-body --max-time 20 -K - "$url" --data-urlencode "text=$text" -d target_lang=${target} | `
    + "jq -er '.translations[0].text') || { notify-send -a Pentad 'DeepL' 'Translation failed'; exit 5; }; "
    + 'printf %s "$out" | wl-copy; notify-send -a Pentad \'Translation copied\' "$out"';
}

export function toolLabel(tool, text) {
  return text(tool.labelUk, tool.labelEn);
}

export function durationLabel(seconds, text) {
  if (!seconds) return text('Без обмеження', 'Until turned off');
  if (seconds < 3600) return text(`${seconds / 60} хв`, `${seconds / 60} min`);
  return text(`${seconds / 3600} год`, `${seconds / 3600} h`);
}
