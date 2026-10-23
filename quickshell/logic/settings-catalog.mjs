import { barTools, colorFormats, deeplTargets, magnifierZooms, searchEngines } from './bar-tools.mjs';
import { supportedEmojiLanguages } from './spotlight-providers.mjs';

// Display names for the emoji annotation languages Spotlight can load.
const emojiLanguageNames = Object.freeze({
  bn: ['Бенгальська', 'Bengali'], da: ['Данська', 'Danish'], de: ['Німецька', 'German'], en: ['Англійська', 'English'],
  'en-gb': ['Англійська (Британія)', 'English (UK)'], es: ['Іспанська', 'Spanish'], 'es-mx': ['Іспанська (Мексика)', 'Spanish (Mexico)'],
  et: ['Естонська', 'Estonian'], fi: ['Фінська', 'Finnish'], fr: ['Французька', 'French'], hi: ['Гінді', 'Hindi'],
  hu: ['Угорська', 'Hungarian'], it: ['Італійська', 'Italian'], ja: ['Японська', 'Japanese'], ko: ['Корейська', 'Korean'],
  lt: ['Литовська', 'Lithuanian'], ms: ['Малайська', 'Malay'], nb: ['Норвезька (букмол)', 'Norwegian Bokmål'],
  nl: ['Нідерландська', 'Dutch'], pl: ['Польська', 'Polish'], pt: ['Португальська', 'Portuguese'], ru: ['Російська', 'Russian'],
  sv: ['Шведська', 'Swedish'], th: ['Тайська', 'Thai'], uk: ['Українська', 'Ukrainian'], vi: ['В’єтнамська', 'Vietnamese'],
  zh: ['Китайська', 'Chinese'], 'zh-hant': ['Китайська (традиційна)', 'Chinese (Traditional)'],
});
export const emojiLanguageChoices = Object.freeze(supportedEmojiLanguages.map(code => {
  const names = emojiLanguageNames[code] || [code, code];
  return Object.freeze({ value: code, labelUk: names[0], labelEn: names[1] });
}));

export const groupCaptions = Object.freeze({
  personalization: { uk: 'Персоналізація', en: 'Personalization' },
  shell: { uk: 'Оболонка', en: 'Shell' },
  behavior: { uk: 'Поведінка', en: 'Behavior' },
  system: { uk: 'Система', en: 'System' },
});

const opt = (value, labelUk, labelEn) => ({ value, labelUk, labelEn });
const toggle = (key, document, path, labelUk, labelEn, def, extra = {}) =>
  Object.assign({ key, kind: 'boolean', control: 'toggle', document, path, labelUk, labelEn, default: def }, extra);
const shortcut = (key, labelUk, labelEn, keys) =>
  ({ key, kind: 'text', control: 'value', labelUk, labelEn, default: keys });

export const pages = [
  {
    id: 'appearance', group: 'personalization', icon: 'tabler/palette-symbolic.svg', labelUk: 'Вигляд', labelEn: 'Appearance',
    keywords: ['theme', 'dark', 'light', 'accent', 'font', 'motion', 'тема', 'акцент', 'шрифт', 'анімація'],
    sections: [
      { id: 'theme', labelUk: 'Тема', labelEn: 'Theme', items: [
        { key: 'appearance', kind: 'select', control: 'segmented', document: 'theme', path: 'appearance', default: 'dark',
          labelUk: 'Режим', labelEn: 'Mode', options: [opt('dark', 'Темний', 'Dark'), opt('light', 'Світлий', 'Light')] },
        { key: 'accent', kind: 'color', control: 'color', document: 'theme', path: 'accent', default: '#869677',
          labelUk: 'Акцентний колір', labelEn: 'Accent color', icon: 'material/colorize-symbolic.svg',
          helpUk: 'Колір у форматі #RRGGBB.', helpEn: 'Color in #RRGGBB format.' },
        { key: 'fontFamily', kind: 'text', control: 'font', document: 'theme', path: 'fontFamily', default: 'Geist',
          labelUk: 'Шрифт', labelEn: 'Font family',
          helpUk: 'Будь-який встановлений шрифт; список показує кожен його власним накресленням.',
          helpEn: 'Any installed font; the list previews each one in its own face.' },
      ] },
      { id: 'motion', labelUk: 'Рух', labelEn: 'Motion', items: [
        toggle('reducedMotion', 'theme', 'reducedMotion', 'Менше анімацій', 'Reduce motion', false,
          { helpUk: 'Вимикає більшість переходів в оболонці.', helpEn: 'Turns off most shell transitions.' }),
      ] },
    ],
  },
  {
    id: 'wallpaper', group: 'personalization', icon: 'tabler/photo-symbolic.svg', labelUk: 'Шпалери', labelEn: 'Wallpaper',
    keywords: ['wallpaper', 'background', 'desktop', 'image', 'picture', 'random', 'tint', 'accent',
      'шпалери', 'фон', 'тло', 'робочий стіл', 'зображення', 'випадкові', 'тонування', 'акцент'],
    sections: [
      { id: 'gallery', labelUk: 'Зображення', labelEn: 'Image', items: [
        { key: 'wallpaperPath', kind: 'text', control: 'wallpapers', document: 'wallpaper', path: 'path', default: '',
          labelUk: 'Шпалери', labelEn: 'Wallpaper' },
      ] },
      { id: 'display', labelUk: 'Відображення', labelEn: 'Display', items: [
        { key: 'wallpaperFill', kind: 'select', control: 'segmented', document: 'wallpaper', path: 'fill', default: 'crop',
          labelUk: 'Розміщення', labelEn: 'Fit',
          options: [opt('crop', 'Заповнити', 'Fill'), opt('fit', 'Вмістити', 'Fit'), opt('stretch', 'Розтягнути', 'Stretch'),
            opt('center', 'По центру', 'Center')] },
        { key: 'wallpaperTransition', kind: 'select', control: 'segmented', document: 'wallpaper', path: 'transition', default: 'fade',
          labelUk: 'Зміна', labelEn: 'Transition',
          options: [opt('fade', 'Плавна', 'Fade'), opt('none', 'Миттєва', 'Instant')] },
        { key: 'wallpaperFolder', kind: 'text', control: 'text', document: 'wallpaper', path: 'directory', default: '~/Pictures/Wallpapers',
          labelUk: 'Папка', labelEn: 'Folder',
          helpUk: 'Звідси беруться зображення для галереї, випадкових і наступних шпалер.',
          helpEn: 'The gallery, random and next wallpaper take images from here.' },
      ] },
      { id: 'colors', labelUk: 'Кольори', labelEn: 'Colors', items: [
        { key: 'wallpaperAccent', kind: 'color', control: 'swatches', document: 'theme', path: 'accent', default: '#869677',
          labelUk: 'Акцент зі шпалер', labelEn: 'Accent from wallpaper',
          helpUk: 'Кольори, знайдені на поточних шпалерах і підібрані під контраст теми. Нейтральні зображення кольорів не дають.',
          helpEn: 'Colors found in the current wallpaper, adjusted for contrast with the theme. Neutral images give none.' },
        toggle('accentFromWallpaper', 'wallpaper', 'accentFromWallpaper', 'Акцент слідує за шпалерами', 'Accent follows wallpaper', false,
          { helpUk: 'Після зміни шпалер акцент стає першим знайденим кольором.',
            helpEn: 'After a wallpaper change the accent becomes the first color found.' }),
        { key: 'wallpaperTint', kind: 'select', control: 'segmented', document: 'wallpaper', path: 'tint', default: 'none',
          labelUk: 'Тонування', labelEn: 'Tint',
          options: [opt('none', 'Оригінал', 'Original'), opt('theme', 'Під тему', 'Theme colors')],
          helpUk: 'Перефарбовує зображення в кольори теми й оновлює його разом з темою. Потрібен ImageMagick.',
          helpEn: 'Recolors the image toward the theme and follows theme changes. Requires ImageMagick.' },
      ] },
    ],
  },
  {
    id: 'language', group: 'personalization', icon: 'tabler/scale-symbolic.svg', labelUk: 'Мова', labelEn: 'Language',
    keywords: ['language', 'locale', 'ukrainian', 'english', 'мова', 'українська', 'англійська'],
    sections: [
      { id: 'interface', labelUk: 'Інтерфейс', labelEn: 'Interface', items: [
        { key: 'language', kind: 'select', control: 'segmented', document: 'interface', path: 'language', default: 'auto',
          labelUk: 'Мова інтерфейсу', labelEn: 'Interface language',
          options: [opt('auto', 'Авто', 'Auto'), opt('uk', 'Українська', 'Ukrainian'), opt('en', 'English', 'English')],
          helpUk: 'Мови емодзі налаштовуються в Spotlight.', helpEn: 'Emoji languages are set in Spotlight.' },
      ] },
    ],
  },
  {
    id: 'bar', group: 'shell', icon: 'tabler/device-desktop-symbolic.svg', labelUk: 'Панель', labelEn: 'Bar',
    keywords: ['bar', 'height', 'workspaces', 'seconds', 'clock', 'tray', 'панель', 'висота', 'простори', 'секунди', 'годинник', 'трей',
      'tools', 'toggles', 'ocr', 'text', 'translate', 'deepl', 'picker', 'eyedropper', 'color', 'image search', 'lens', 'caffeine',
      'інструменти', 'перемикачі', 'текст', 'переклад', 'піпетка', 'колір', 'пошук за зображенням', 'кава'],
    tabs: [{ id: 'layout', labelUk: 'Розташування', labelEn: 'Layout' }, { id: 'tools', labelUk: 'Інструменти', labelEn: 'Tools' }],
    sections: [
      { tab: 'layout', id: 'size', labelUk: 'Розмір', labelEn: 'Size', items: [
        { key: 'barHeight', kind: 'integer', control: 'slider', document: 'layout', path: 'barHeight', default: 40,
          min: 28, max: 40, step: 2, labelUk: 'Висота панелі', labelEn: 'Bar height' },
      ] },
      { tab: 'layout', id: 'content', labelUk: 'Вміст', labelEn: 'Content', items: [
        toggle('showActiveTitle', 'layout', 'showActiveTitle', 'Назва активного вікна', 'Active window title', true),
        toggle('showWorkspaces', 'layout', 'showWorkspaces', 'Робочі простори', 'Workspaces', true),
        toggle('showSeconds', 'layout', 'showSeconds', 'Секунди в годиннику', 'Seconds in clock', false),
        { key: 'clockLayout', kind: 'select', control: 'segmented', document: 'layout', path: 'clockLayout', default: 'stacked',
          labelUk: 'Годинник', labelEn: 'Clock',
          options: [opt('stacked', 'Два рядки', 'Two lines'), opt('emphasis', 'Великий час', 'Large time'),
            opt('inline', 'Один рядок', 'One line')] },
        { key: 'clockSize', kind: 'integer', control: 'slider', document: 'layout', path: 'clockSize', default: 18,
          min: 14, max: 22, step: 1, labelUk: 'Розмір годинника', labelEn: 'Clock size' },
        { key: 'trayIcons', kind: 'select', control: 'segmented', document: 'layout', path: 'trayIcons', default: 'soft',
          labelUk: 'Піктограми трею', labelEn: 'Tray icons',
          options: [opt('soft', "М'які", 'Soft'), opt('color', 'Кольорові', 'Color'), opt('monochrome', 'Монохромні', 'Monochrome')] },
      ] },
      { tab: 'tools', id: 'toggles', labelUk: 'Перемикачі', labelEn: 'Toggles',
        helpUk: 'Що показувати лівою пігулкою на панелі.', helpEn: 'What the left pill on the bar shows.',
        items: barTools.filter(tool => tool.kind === 'toggle').map(tool =>
          toggle('show-' + tool.id, 'layout', 'barTools.show.' + tool.id, tool.labelUk, tool.labelEn, tool.visible)) },
      { tab: 'tools', id: 'actions', labelUk: 'Інструменти', labelEn: 'Tools',
        helpUk: 'Що показувати правою пігулкою на панелі.', helpEn: 'What the right pill on the bar shows.',
        items: barTools.filter(tool => tool.kind === 'action').map(tool =>
          toggle('show-' + tool.id, 'layout', 'barTools.show.' + tool.id, tool.labelUk, tool.labelEn, tool.visible)) },
      { tab: 'tools', id: 'image-search', labelUk: 'Пошук за зображенням', labelEn: 'Image search',
        helpUk: 'Фрагмент потрапляє в буфер обміну; на сторінці пошуковика натисніть Ctrl+V.',
        helpEn: 'The snippet goes to the clipboard; press Ctrl+V on the search page.',
        items: [
          { key: 'searchMode', kind: 'select', control: 'segmented', document: 'layout', path: 'barTools.search.mode', default: 'ask',
            labelUk: 'Після вибору області', labelEn: 'After selecting an area',
            options: [opt('ask', 'Питати', 'Ask'), opt('direct', 'Шукати відразу', 'Search at once')] },
          { key: 'searchEngine', kind: 'select', control: 'dropdown', document: 'layout', path: 'barTools.search.engine', default: 'google',
            labelUk: 'Пошуковик за замовчуванням', labelEn: 'Default engine',
            options: searchEngines.map(engine => opt(engine.id, engine.name, engine.name)),
            visibleWhen: { key: 'searchMode', equals: 'direct' } },
          ...searchEngines.map(engine => toggle('engine-' + engine.id, 'layout', 'barTools.search.engines.' + engine.id,
            'Пошук: ' + engine.name, 'Search: ' + engine.name, true)),
        ] },
      { tab: 'tools', id: 'text', labelUk: 'Текст і колір', labelEn: 'Text and color', items: [
        { key: 'ocrLanguages', kind: 'text', control: 'text', document: 'layout', path: 'barTools.ocr.languages', default: 'eng',
          labelUk: 'Мови розпізнавання', labelEn: 'Recognition languages',
          helpUk: 'Коди tesseract через «+», наприклад eng+ukr. Мовні пакети мають бути встановлені.',
          helpEn: 'Tesseract codes joined by "+", for example eng+ukr. Language packs must be installed.' },
        { key: 'pickerFormat', kind: 'select', control: 'dropdown', document: 'layout', path: 'barTools.picker.format', default: 'hex',
          labelUk: 'Формат кольору', labelEn: 'Color format',
          options: colorFormats.map(format => opt(format, format.toUpperCase(), format.toUpperCase())) },
        { key: 'magnifierZoom', kind: 'select', control: 'dropdown', document: 'layout', path: 'barTools.magnifier.zoom', default: 3,
          labelUk: 'Збільшення лупи', labelEn: 'Magnifier zoom',
          options: magnifierZooms.map(zoom => opt(zoom, '×' + zoom, '×' + zoom)) },
      ] },
      { tab: 'tools', id: 'translation', labelUk: 'Переклад', labelEn: 'Translation', items: [
        { key: 'translateProvider', kind: 'select', control: 'segmented', document: 'layout', path: 'barTools.translate.provider', default: 'deepl',
          labelUk: 'Сервіс', labelEn: 'Service',
          options: [opt('deepl', 'DeepL', 'DeepL'), opt('google', 'trans', 'trans')] },
        { key: 'translateTarget', kind: 'select', control: 'dropdown', document: 'layout', path: 'barTools.translate.target', default: 'EN-US',
          labelUk: 'Мова перекладу', labelEn: 'Target language',
          options: deeplTargets.map(code => opt(code, code, code)) },
        { key: 'translateKeyFile', kind: 'text', control: 'text', document: 'layout', path: 'barTools.translate.keyFile', default: '',
          labelUk: 'Файл ключа DeepL', labelEn: 'DeepL key file',
          helpUk: 'Шлях до файлу з ключем API (наприклад ~/.config/deepl.key). Ключ не потрапляє в конфіг.',
          helpEn: 'Path to a file holding the API key (for example ~/.config/deepl.key). The key never enters the config.',
          visibleWhen: { key: 'translateProvider', equals: 'deepl' } },
      ] },
    ],
  },
  {
    id: 'control-center', group: 'shell', icon: 'material/speed-symbolic.svg', labelUk: 'Центр керування', labelEn: 'Control center',
    keywords: ['control center', 'quick settings', 'tiles', 'audio', 'центр керування', 'швидкі налаштування', 'звук'],
    sections: [
      { id: 'items', labelUk: 'Елементи', labelEn: 'Items', items: [
        { key: 'controlCenterItems', kind: 'select', control: 'options', document: 'layout', path: 'controlCenter.items',
          labelUk: 'Порядок і видимість', labelEn: 'Order and visibility',
          helpUk: 'Перетягніть, щоб змінити порядок; перемикач ховає елемент.', helpEn: 'Drag to reorder; the switch hides an item.' },
      ] },
    ],
  },
  {
    id: 'widgets', group: 'shell', icon: 'material/extension-symbolic.svg', labelUk: 'Віджети', labelEn: 'Widgets',
    keywords: ['widgets', 'modules', 'slots', 'placement', 'віджети', 'модулі', 'слоти'],
    sections: [
      { id: 'catalog', labelUk: 'Каталог', labelEn: 'Catalog',
        helpUk: 'Перемикач вмикає віджет, шестірня відкриває його налаштування, перетягування змінює порядок на панелі.',
        helpEn: 'The switch turns a widget on, the gear opens its settings, dragging changes its order on the bar.',
        items: [
        { key: 'widgets', kind: 'select', control: 'catalog', document: 'layout', path: 'widgets',
          labelUk: 'Віджети', labelEn: 'Widgets', keywords: ['add', 'enable', 'order', 'додати', 'увімкнути', 'порядок'] },
      ] },
    ],
  },
  {
    id: 'spotlight', group: 'shell', icon: 'material/radio-button-checked-symbolic.svg', labelUk: 'Spotlight', labelEn: 'Spotlight',
    keywords: ['spotlight', 'search', 'emoji', 'languages', 'пошук', 'емодзі', 'мови'],
    sections: [
      { id: 'emoji', labelUk: 'Емодзі', labelEn: 'Emoji', items: [
        { key: 'emojiLanguages', kind: 'select', control: 'chips', document: 'spotlight', path: 'emoji.languages', default: 'auto',
          labelUk: 'Мови емодзі', labelEn: 'Emoji languages', keywords: ['language', 'мова'],
          sentinel: 'auto', sentinelUk: 'Авто', sentinelEn: 'Auto', choices: emojiLanguageChoices,
          helpUk: 'Авто бере мови з розкладок клавіатури. Виберіть мови, щоб шукати емодзі за їхніми назвами.',
          helpEn: 'Auto follows your keyboard layouts. Pick languages to search emoji by their names in those languages.' },
      ] },
    ],
  },
  {
    id: 'notifications', group: 'behavior', icon: 'material/notifications-symbolic.svg', labelUk: 'Сповіщення', labelEn: 'Notifications',
    keywords: ['notifications', 'dnd', 'do not disturb', 'сповіщення', 'не турбувати'],
    sections: [
      { id: 'general', labelUk: 'Загальні', labelEn: 'General', items: [
        toggle('dnd', 'notifications', 'dnd', 'Не турбувати', 'Do not disturb', false, { icon: 'material/notifications-off-symbolic.svg' }),
      ] },
    ],
  },
  {
    id: 'screenshots', group: 'behavior', icon: 'material/screenshot-region-symbolic.svg', labelUk: 'Знімки екрана', labelEn: 'Screenshots',
    keywords: ['screenshot', 'capture', 'знімок', 'екран'],
    sections: [
      { id: 'capture', labelUk: 'Знімки', labelEn: 'Capture', items: [
        { key: 'openScreenshotSettings', kind: 'text', control: 'link', action: 'screenshots.open',
          labelUk: 'Відкрити налаштування знімків', labelEn: 'Open screenshot settings' },
      ] },
    ],
  },
  {
    id: 'session', group: 'behavior', icon: 'material/lock-symbolic.svg', labelUk: 'Сеанс', labelEn: 'Session',
    keywords: ['session', 'lock', 'media', 'weather', 'player', 'сеанс', 'блокування', 'медіа', 'погода', 'плеєр'],
    sections: [
      { id: 'lock', labelUk: 'Екран блокування', labelEn: 'Lock screen', items: [
        toggle('showMediaOnLock', 'session', 'showMediaOnLock', 'Медіа на блокуванні', 'Media on lock screen', false),
        toggle('showWeatherOnLock', 'session', 'showWeatherOnLock', 'Погода на блокуванні', 'Weather on lock screen', false),
        { key: 'preferredPlayerId', kind: 'text', control: 'text', document: 'session', path: 'preferredPlayerId', default: '',
          labelUk: 'Бажаний плеєр', labelEn: 'Preferred player',
          helpUk: 'Ідентифікатор MPRIS-плеєра; порожньо означає будь-який.', helpEn: 'MPRIS player id; empty means any.' },
      ] },
    ],
  },
  {
    id: 'shortcuts', group: 'system', icon: 'material/keyboard-symbolic.svg', labelUk: 'Скорочення', labelEn: 'Shortcuts',
    keywords: ['shortcuts', 'keys', 'hotkeys', 'скорочення', 'клавіші'],
    sections: [
      { id: 'navigation', labelUk: 'Навігація', labelEn: 'Navigation',
        helpUk: 'Лише перегляд. Це прив’язки з defaults/hyprland-quickshell.lua.',
        helpEn: 'Read only. These are the bindings in defaults/hyprland-quickshell.lua.', items: [
        shortcut('shortcutSpotlight', 'Spotlight', 'Spotlight', 'Super, Super + Space'),
        shortcut('shortcutOverview', 'Огляд', 'Overview', 'Super + Tab'),
        shortcut('shortcutSwitcher', 'Перемикач вікон', 'Window switcher', 'Alt + Tab'),
        shortcut('shortcutAppSwitcher', 'Вікна цього застосунку', 'Windows of this app', 'Alt + `'),
      ] },
    ],
  },
  {
    id: 'system', group: 'system', icon: 'material/shield-symbolic.svg', labelUk: 'Система', labelEn: 'System',
    keywords: ['system', 'checkpoint', 'restore', 'backup', 'reset', 'система', 'відновлення', 'копія'],
    sections: [
      { id: 'backup', labelUk: 'Резервні копії', labelEn: 'Backups',
        helpUk: 'Контрольна точка зберігає поточні теми й розкладку.', helpEn: 'A checkpoint saves the current theme and layout.', items: [
        { key: 'checkpoint', kind: 'text', control: 'button', action: 'config.checkpoint',
          labelUk: 'Створити контрольну точку', labelEn: 'Create checkpoint', icon: 'material/restart-symbolic.svg' },
        { key: 'restore', kind: 'text', control: 'button', action: 'config.restore',
          labelUk: 'Відновити контрольну точку', labelEn: 'Restore checkpoint' },
      ] },
    ],
  },
];
