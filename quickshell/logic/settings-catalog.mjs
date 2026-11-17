import { barTools, colorFormats, deeplTargets, magnifierZooms, searchEngines } from './bar-tools.mjs';
import { supportedEmojiLanguages, webSearchEngines } from './spotlight-providers.mjs';

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
  devices: { uk: 'Пристрої', en: 'Devices' },
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
        { key: 'wallpaperTransition', kind: 'select', control: 'dropdown', document: 'wallpaper', path: 'transition', default: 'fade',
          labelUk: 'Зміна', labelEn: 'Transition',
          options: [opt('fade', 'Плавна', 'Fade'), opt('wipe', 'Витирання', 'Wipe'), opt('disc', 'Коло', 'Disc'),
            opt('pixelate', 'Пікселі', 'Pixelate'), opt('iris', 'Діафрагма', 'Iris'), opt('random', 'Випадкова', 'Random'),
            opt('none', 'Миттєва', 'Instant')] },
        { key: 'wallpaperRotate', kind: 'select', control: 'dropdown', document: 'wallpaper', path: 'rotate', default: 'off',
          labelUk: 'Автозміна', labelEn: 'Rotate',
          options: [opt('off', 'Вимкнено', 'Off'), opt('15m', '15 хв', '15 min'), opt('30m', '30 хв', '30 min'),
            opt('1h', '1 год', '1 h'), opt('3h', '3 год', '3 h'), opt('1d', 'Щодня', 'Daily')],
          helpUk: 'Через заданий проміжок шпалери самі змінюються на випадкове зображення з папки. Потрібно щонайменше два зображення.',
          helpEn: 'After the chosen time the wallpaper changes itself to a random image from the folder. Needs at least two images.' },
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
    keywords: ['language', 'locale', 'ukrainian', 'english', 'week', 'calendar', 'мова', 'українська', 'англійська', 'тиждень', 'календар'],
    sections: [
      { id: 'interface', labelUk: 'Інтерфейс', labelEn: 'Interface', items: [
        { key: 'language', kind: 'select', control: 'segmented', document: 'interface', path: 'language', default: 'auto',
          labelUk: 'Мова інтерфейсу', labelEn: 'Interface language',
          options: [opt('auto', 'Авто', 'Auto'), opt('uk', 'Українська', 'Ukrainian'), opt('en', 'English', 'English')],
          helpUk: 'Мови емодзі налаштовуються в Spotlight.', helpEn: 'Emoji languages are set in Spotlight.' },
      ] },
      { id: 'formats', labelUk: 'Формати', labelEn: 'Formats', items: [
        { key: 'firstDayOfWeek', kind: 'select', control: 'dropdown', document: 'interface', path: 'firstDayOfWeek', default: 'auto',
          labelUk: 'Перший день тижня', labelEn: 'First day of week',
          options: [opt('auto', 'Як у системі', 'System default'), opt('monday', 'Понеділок', 'Monday'),
            opt('sunday', 'Неділя', 'Sunday'), opt('saturday', 'Субота', 'Saturday')],
          helpUk: 'Для календаря на панелі. «Як у системі» бере день із регіональних налаштувань.',
          helpEn: 'For the calendar in the panel. System default takes the day from your regional settings.' },
      ] },
    ],
  },
  {
    id: 'network', group: 'devices', icon: 'tabler/wifi-symbolic.svg', labelUk: 'Мережа', labelEn: 'Network',
    keywords: ['network', 'wifi', 'wi-fi', 'wireless', 'internet', 'password', 'ethernet', 'lan', 'cable', 'wired', 'usb', 'tethering',
      'modem', 'mobile', 'lte', '5g', 'apn', 'hotspot', 'vpn', 'wireguard', 'openvpn', 'dns', 'ip', 'dhcp', 'mac', 'metered', 'hidden',
      'мережа', 'бездротова', 'інтернет', 'пароль', 'кабель', 'дротова', 'модем', 'роздача', 'точка доступу', 'мобільний', 'днс',
      'прихована', 'лімітне'],
    sections: [
      { id: 'status', labelUk: 'Стан', labelEn: 'Status', items: [
        { key: 'networkOverview', kind: 'text', control: 'panel', panel: 'network-overview', labelUk: 'Стан мережі', labelEn: 'Network status' },
      ] },
      { id: 'wifi', labelUk: 'Wi-Fi', labelEn: 'Wi-Fi', items: [
        { key: 'wifiPanel', kind: 'text', control: 'panel', panel: 'wifi', labelUk: 'Мережі Wi-Fi', labelEn: 'Wi-Fi networks' },
      ] },
      { id: 'known', labelUk: 'Відомі мережі', labelEn: 'Known networks', items: [
        { key: 'knownWifi', kind: 'text', control: 'panel', panel: 'network-known-wifi',
          labelUk: 'Збережені мережі Wi-Fi', labelEn: 'Saved Wi-Fi networks' },
      ] },
      { id: 'ethernet', labelUk: 'Ethernet', labelEn: 'Ethernet', items: [
        { key: 'wiredPanel', kind: 'text', control: 'panel', panel: 'network-wired', labelUk: 'Дротова мережа', labelEn: 'Wired network' },
      ] },
      { id: 'tethering', labelUk: 'Інтернет із телефона', labelEn: 'Internet from a phone', items: [
        { key: 'tetheringPanel', kind: 'text', control: 'panel', panel: 'network-tethering',
          labelUk: 'USB, Bluetooth і мобільний модем', labelEn: 'USB, Bluetooth and mobile modem' },
      ] },
      { id: 'hotspot', labelUk: 'Точка доступу', labelEn: 'Hotspot', items: [
        { key: 'hotspotPanel', kind: 'text', control: 'panel', panel: 'network-hotspot',
          labelUk: 'Роздача інтернету', labelEn: 'Internet sharing' },
      ] },
      { id: 'vpn', labelUk: 'VPN', labelEn: 'VPN', items: [
        { key: 'vpnPanel', kind: 'text', control: 'panel', panel: 'network-vpn', labelUk: 'З’єднання VPN', labelEn: 'VPN connections' },
      ] },
    ],
  },
  {
    id: 'bluetooth', group: 'devices', icon: 'material/bluetooth-symbolic.svg', labelUk: 'Bluetooth', labelEn: 'Bluetooth',
    keywords: ['bluetooth', 'pair', 'headphones', 'mouse', 'keyboard', 'speaker', 'devices',
      'спарити', 'навушники', 'миша', 'клавіатура', 'колонка', 'пристрої'],
    sections: [
      { id: 'adapter', labelUk: 'Адаптер', labelEn: 'Adapter', items: [
        { key: 'bluetoothPanel', kind: 'text', control: 'panel', panel: 'bluetooth', labelUk: 'Увімкнення', labelEn: 'Power' },
      ] },
      { id: 'paired', labelUk: 'Мої пристрої', labelEn: 'My devices', items: [
        { key: 'bluetoothDevices', kind: 'text', control: 'panel', panel: 'bluetooth-devices',
          labelUk: 'Спарені пристрої', labelEn: 'Paired devices' },
      ] },
      { id: 'nearby', labelUk: 'Пристрої поруч', labelEn: 'Nearby devices',
        helpUk: 'Пошук триває, поки відкрита ця сторінка. Пристрої з PIN-кодом поки не спарюються звідси.',
        helpEn: 'Searching runs while this page is open. Devices that ask for a PIN cannot be paired from here yet.',
        items: [
        { key: 'bluetoothNearby', kind: 'text', control: 'panel', panel: 'bluetooth-nearby',
          labelUk: 'Знайдені пристрої', labelEn: 'Found devices' },
      ] },
    ],
  },
  {
    id: 'sound', group: 'devices', icon: 'tabler/volume-symbolic.svg', labelUk: 'Звук', labelEn: 'Sound',
    keywords: ['sound', 'audio', 'volume', 'speakers', 'headphones', 'microphone', 'mixer', 'apps',
      'звук', 'гучність', 'динаміки', 'навушники', 'мікрофон', 'мікшер', 'застосунки'],
    sections: [
      { id: 'devices', labelUk: 'Пристрої', labelEn: 'Devices', items: [
        { key: 'soundPanel', kind: 'text', control: 'panel', panel: 'sound', labelUk: 'Вихід і вхід', labelEn: 'Output and input' },
      ] },
      { id: 'apps', labelUk: 'Застосунки', labelEn: 'Applications', items: [
        { key: 'mixerPanel', kind: 'text', control: 'panel', panel: 'mixer', labelUk: 'Гучність застосунків', labelEn: 'Application volume' },
      ] },
      { id: 'feedback', labelUk: 'Індикатор', labelEn: 'Indicator', items: [
        toggle('levelOverlay', 'interface', 'levelOverlay', 'Показувати рівень гучності', 'Show the volume level', true,
          { helpUk: 'Коротко показує рівень після зміни гучності, мікрофона, яскравості чи розкладки клавіатури. Помилки видно завжди.',
            helpEn: 'Briefly shows the level after a volume, microphone, brightness or keyboard-layout change. Errors always show.' }),
      ] },
    ],
  },
  {
    id: 'power', group: 'devices', icon: 'tabler/battery-symbolic.svg', labelUk: 'Живлення', labelEn: 'Power',
    keywords: ['power', 'battery', 'charge', 'profile', 'performance', 'saver', 'brightness', 'display',
      'sleep', 'idle', 'screen off', 'hypridle', 'сон', 'бездіяльність', 'вимкнення екрана',
      'живлення', 'батарея', 'заряд', 'профіль', 'продуктивність', 'економія', 'яскравість', 'монітор'],
    sections: [
      { id: 'power', labelUk: 'Батарея й режим', labelEn: 'Battery and mode', items: [
        { key: 'powerPanel', kind: 'text', control: 'panel', panel: 'power', labelUk: 'Батарея й режим', labelEn: 'Battery and mode' },
      ] },
      { id: 'brightness', labelUk: 'Яскравість', labelEn: 'Brightness', items: [
        { key: 'brightnessPanel', kind: 'text', control: 'panel', panel: 'brightness', labelUk: 'Яскравість моніторів', labelEn: 'Display brightness' },
      ] },
      { id: 'idle', labelUk: 'Екран і сон', labelEn: 'Screen and sleep', items: [
        { key: 'idlePanel', kind: 'text', control: 'panel', panel: 'idle', labelUk: 'Екран і сон', labelEn: 'Screen and sleep',
          helpUk: 'Незалежні таймери бездіяльності hypridle. Блокування екрана налаштовується окремо.',
          helpEn: 'Independent hypridle inactivity timers. Screen locking is configured separately.' },
      ] },
      { id: 'bar', labelUk: 'Панель', labelEn: 'Bar', items: [
        toggle('showBatteryPercent', 'layout', 'showBatteryPercent', 'Відсоток заряду на панелі', 'Battery percentage in bar', false),
      ] },
    ],
  },
  {
    id: 'bar', group: 'shell', icon: 'tabler/device-desktop-symbolic.svg', labelUk: 'Панель', labelEn: 'Bar',
    keywords: ['bar', 'height', 'workspaces', 'seconds', 'clock', 'tray', 'панель', 'висота', 'простори', 'секунди', 'годинник', 'трей',
      'battery', 'percent', 'date', '12-hour', '24-hour', 'am', 'pm', 'батарея', 'заряд', 'відсоток', 'дата', 'формат',
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
        { key: 'workspaceCount', kind: 'integer', control: 'slider', document: 'layout', path: 'workspaceCount', default: 5,
          min: 1, max: 8, step: 1, labelUk: 'Нумеровані простори', labelEn: 'Numbered workspaces',
          helpUk: 'Скільки нумерованих просторів показувати, навіть якщо в них немає вікон. Зайняті простори видно завжди.',
          helpEn: 'How many numbered workspaces to show even without windows. Occupied workspaces always show.',
          visibleWhen: { key: 'showWorkspaces', equals: true } },
        toggle('showBatteryPercent', 'layout', 'showBatteryPercent', 'Відсоток заряду', 'Battery percentage', false,
          { helpUk: 'Показує заряд поруч зі значком батареї, якщо вона є.', helpEn: 'Shows the charge next to the battery icon, when there is one.' }),
        { key: 'trayIcons', kind: 'select', control: 'segmented', document: 'layout', path: 'trayIcons', default: 'soft',
          labelUk: 'Піктограми трею', labelEn: 'Tray icons',
          options: [opt('soft', "М'які", 'Soft'), opt('color', 'Кольорові', 'Color'), opt('monochrome', 'Монохромні', 'Monochrome')] },
      ] },
      { tab: 'layout', id: 'clock', labelUk: 'Годинник', labelEn: 'Clock', items: [
        { key: 'clockFormat', kind: 'select', control: 'segmented', document: 'layout', path: 'clockFormat', default: '24h',
          labelUk: 'Формат часу', labelEn: 'Time format',
          options: [opt('24h', '24 години', '24-hour'), opt('12h', '12 годин', '12-hour')] },
        toggle('showSeconds', 'layout', 'showSeconds', 'Секунди в годиннику', 'Seconds in clock', false),
        { key: 'clockDate', kind: 'select', control: 'segmented', document: 'layout', path: 'clockDate', default: 'day-month',
          labelUk: 'Дата', labelEn: 'Date',
          options: [opt('day-month', 'ДД.ММ', 'DD.MM'), opt('month-day', 'ММ/ДД', 'MM/DD'), opt('hidden', 'Немає', 'None')] },
        { key: 'clockLayout', kind: 'select', control: 'segmented', document: 'layout', path: 'clockLayout', default: 'stacked',
          labelUk: 'Компонування', labelEn: 'Arrangement',
          options: [opt('stacked', 'Два рядки', 'Two lines'), opt('emphasis', 'Великий час', 'Large time'),
            opt('inline', 'Один рядок', 'One line')] },
        { key: 'clockSize', kind: 'integer', control: 'slider', document: 'layout', path: 'clockSize', default: 18,
          min: 14, max: 22, step: 1, labelUk: 'Розмір годинника', labelEn: 'Clock size' },
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
    keywords: ['control center', 'quick settings', 'tiles', 'audio', 'osd', 'volume', 'brightness',
      'центр керування', 'швидкі налаштування', 'звук', 'гучність', 'яскравість'],
    sections: [
      { id: 'items', labelUk: 'Елементи', labelEn: 'Items', items: [
        { key: 'controlCenterItems', kind: 'select', control: 'options', document: 'layout', path: 'controlCenter.items',
          labelUk: 'Порядок і видимість', labelEn: 'Order and visibility',
          helpUk: 'Перетягніть, щоб змінити порядок; перемикач ховає елемент.', helpEn: 'Drag to reorder; the switch hides an item.' },
      ] },
      { id: 'indicators', labelUk: 'Індикатори', labelEn: 'Indicators', items: [
        toggle('levelOverlay', 'interface', 'levelOverlay', 'Індикатор гучності й яскравості', 'Volume and brightness popup', true,
          { helpUk: 'Коротко показує рівень після зміни гучності, мікрофона, яскравості чи розкладки клавіатури. Помилки видно завжди.',
            helpEn: 'Briefly shows the level after a volume, microphone, brightness or keyboard-layout change. Errors always show.' }),
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
    keywords: ['spotlight', 'search', 'emoji', 'languages', 'calculator', 'web', 'engine', 'пошук', 'емодзі', 'мови',
      'калькулятор', 'вебпошук', 'пошуковик', 'clipboard', 'paste', 'буфер', 'вставити'],
    sections: [
      { id: 'results', labelUk: 'Результати', labelEn: 'Results', items: [
        toggle('calculator', 'spotlight', 'calculator', 'Калькулятор', 'Calculator', true,
          { helpUk: 'Обчислює вирази на кшталт 2*(3+4) просто в рядку пошуку.', helpEn: 'Evaluates expressions such as 2*(3+4) right in the search field.' }),
        toggle('webSearch', 'spotlight', 'webSearch', 'Пошук в інтернеті', 'Web search', true,
          { helpUk: 'Додає рядок, що відкриває запит у браузері. Нічого не надсилається, доки ви його не виберете.',
            helpEn: 'Adds a row that opens the query in your browser. Nothing is sent until you choose it.' }),
        { key: 'webEngine', kind: 'select', control: 'dropdown', document: 'spotlight', path: 'webEngine', default: 'duckduckgo',
          labelUk: 'Пошуковик', labelEn: 'Search engine',
          options: webSearchEngines.map(engine => opt(engine.id, engine.name, engine.name)),
          visibleWhen: { key: 'webSearch', equals: true } },
      ] },
      { id: 'clipboard', labelUk: 'Буфер обміну', labelEn: 'Clipboard', items: [
        { key: 'clipboardEnter', kind: 'select', control: 'segmented', document: 'spotlight', path: 'clipboardEnter', default: 'paste',
          labelUk: 'Enter у буфері', labelEn: 'Enter in clipboard', keywords: ['paste', 'copy', 'вставити', 'копіювати'],
          options: [opt('paste', 'Вставити', 'Paste'), opt('copy', 'Копіювати', 'Copy')],
          helpUk: 'Вставити: копіює запис, закриває Spotlight і вставляє його у вікно, з якого ви його відкрили. Копіювати: лише кладе запис у буфер.',
          helpEn: 'Paste copies the entry, closes Spotlight and pastes it into the window you opened it from. Copy only puts the entry on the clipboard.' },
        { key: 'pasteShortcut', kind: 'select', control: 'dropdown', document: 'spotlight', path: 'pasteShortcut', default: 'auto',
          labelUk: 'Клавіші вставки', labelEn: 'Paste keys', keywords: ['shortcut', 'terminal', 'термінал', 'клавіші'],
          options: [opt('auto', 'Авто', 'Auto'), opt('ctrl-v', 'Ctrl+V', 'Ctrl+V'),
            opt('ctrl-shift-v', 'Ctrl+Shift+V', 'Ctrl+Shift+V'), opt('shift-insert', 'Shift+Insert', 'Shift+Insert')],
          helpUk: 'Авто натискає Ctrl+Shift+V у терміналах і Ctrl+V деінде.',
          helpEn: 'Auto presses Ctrl+Shift+V in terminals and Ctrl+V everywhere else.',
          visibleWhen: { key: 'clipboardEnter', equals: 'paste' } },
      ] },
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
    keywords: ['notifications', 'dnd', 'do not disturb', 'popup', 'banner', 'duration', 'сповіщення', 'не турбувати', 'спливні', 'тривалість'],
    sections: [
      { id: 'general', labelUk: 'Загальні', labelEn: 'General', items: [
        toggle('dnd', 'notifications', 'dnd', 'Не турбувати', 'Do not disturb', false, { icon: 'material/notifications-off-symbolic.svg' }),
      ] },
      { id: 'popups', labelUk: 'Спливні сповіщення', labelEn: 'Popups', items: [
        { key: 'notificationStyle', kind: 'select', control: 'dropdown', document: 'interface', path: 'notificationStyle', default: 'toast',
          labelUk: 'Стиль', labelEn: 'Style', keywords: ['look', 'card', 'вигляд', 'картка'],
          options: [opt('toast', 'Компактний', 'Compact'), opt('bold', 'Великий', 'Large'), opt('line', 'Рядок', 'One line'),
            opt('source', 'Із джерелом', 'With source')],
          helpUk: 'Вигляд сповіщень на екрані й у центрі сповіщень. «Рядок» показує все одним рядком і розгортається під курсором.',
          helpEn: 'How notifications look on screen and in the notification center. One line shows a single row and opens under the pointer.' },
        { key: 'notificationTimeout', kind: 'integer', control: 'slider', document: 'interface', path: 'notificationTimeout', default: 7,
          min: 2, max: 30, step: 1, labelUk: 'Тривалість, с', labelEn: 'Duration, s',
          helpUk: 'Скільки секунд сповіщення лишається на екрані. Застосунок може попросити інший час; важливі сповіщення не зникають самі.',
          helpEn: 'How many seconds a popup stays on screen. An app may ask for its own time; critical notifications never close by themselves.' },
        { key: 'notificationPopups', kind: 'integer', control: 'slider', document: 'interface', path: 'notificationPopups', default: 3,
          min: 1, max: 5, step: 1, labelUk: 'Одночасно на екрані', labelEn: 'On screen at once',
          helpUk: 'Старіші спливні сповіщення переходять у центр сповіщень.', helpEn: 'Older popups move to the notification center.' },
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
    id: 'datetime', group: 'system', icon: 'material/tools/schedule-symbolic.svg', labelUk: 'Дата й час', labelEn: 'Date & time',
    keywords: ['date', 'time', 'timezone', 'time zone', 'ntp', 'clock', '24-hour', 'week',
      'дата', 'час', 'часовий пояс', 'годинник', 'тиждень'],
    sections: [
      { id: 'zone', labelUk: 'Час', labelEn: 'Time', items: [
        { key: 'datetimePanel', kind: 'text', control: 'panel', panel: 'datetime', labelUk: 'Пояс і синхронізація', labelEn: 'Zone and sync' },
      ] },
      { id: 'formats', labelUk: 'Формати', labelEn: 'Formats', items: [
        { key: 'clockFormat', kind: 'select', control: 'segmented', document: 'layout', path: 'clockFormat', default: '24h',
          labelUk: 'Формат часу', labelEn: 'Time format',
          options: [opt('24h', '24 години', '24-hour'), opt('12h', '12 годин', '12-hour')] },
        { key: 'firstDayOfWeek', kind: 'select', control: 'dropdown', document: 'interface', path: 'firstDayOfWeek', default: 'auto',
          labelUk: 'Перший день тижня', labelEn: 'First day of week',
          options: [opt('auto', 'Як у системі', 'System default'), opt('monday', 'Понеділок', 'Monday'),
            opt('sunday', 'Неділя', 'Sunday'), opt('saturday', 'Субота', 'Saturday')] },
      ] },
    ],
  },
  {
    id: 'default-apps', group: 'system', icon: 'material/tools/folder-open-symbolic.svg',
    labelUk: 'Типові застосунки', labelEn: 'Default apps',
    keywords: ['default', 'apps', 'applications', 'browser', 'mail', 'open with', 'mime',
      'типові', 'застосунки', 'браузер', 'пошта', 'відкривати'],
    sections: [
      { id: 'apps', labelUk: 'Чим відкривати', labelEn: 'Open with',
        helpUk: 'Зберігається через xdg-mime, тож діє і в інших застосунках.',
        helpEn: 'Saved through xdg-mime, so other applications follow it too.', items: [
        { key: 'defaultAppsPanel', kind: 'text', control: 'panel', panel: 'default-apps', labelUk: 'Типові застосунки', labelEn: 'Default apps' },
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
        shortcut('shortcutCheatsheet', 'Шпаргалка клавіш', 'Keybind cheatsheet', 'Super + /'),
      ] },
      { id: 'keycaps', labelUk: 'Вигляд клавіш', labelEn: 'Key appearance', items: [
        { key: 'superKeyLogo', kind: 'select', control: 'dropdown', document: 'interface', path: 'superKeyLogo', default: 'pentad',
          labelUk: 'Символ клавіші Super', labelEn: 'Super key symbol', icon: 'tabler/keyboard-symbolic.svg',
          keywords: ['logo', 'tux', 'penguin', 'linux', 'meta', 'windows key', 'cheatsheet', 'submap',
            'логотип', 'пінгвін', 'шпаргалка', 'режим клавіш'],
          options: [opt('pentad', 'Логотип Pentad', 'Pentad logo'), opt('tux', 'Пінгвін Tux', 'Tux penguin'),
            opt('text', 'Слово Super', 'The word Super')],
          helpUk: 'Так клавіша Super виглядає у шпаргалці клавіш і в підказці режиму клавіш.',
          helpEn: 'How the Super key looks in the keybind cheatsheet and the submap hint.' },
      ] },
    ],
  },
  {
    id: 'system', group: 'system', icon: 'material/shield-symbolic.svg', labelUk: 'Система', labelEn: 'System',
    keywords: ['system', 'checkpoint', 'restore', 'backup', 'reset', 'performance', 'speed', 'memory', 'ram', 'menus',
      'система', 'відновлення', 'копія', 'швидкодія', 'пам’ять', 'меню'],
    sections: [
      { id: 'performance', labelUk: 'Продуктивність', labelEn: 'Performance', items: [
        { key: 'barMenus', kind: 'select', control: 'segmented', document: 'interface', path: 'barMenus', default: 'speed',
          labelUk: 'Меню бару', labelEn: 'Bar menus',
          options: [opt('speed', 'Швидкодія', 'Speed'), opt('memory', 'Економія пам’яті', 'Save memory')],
          helpUk: 'Заздалегідь будувати меню бару, щоб вони відкривалися миттєво. Займає більше оперативної пам’яті. '
            + 'Якщо перемкнути на економію пам’яті, уже побудовані меню звільняться з перезапуском оболонки.',
          helpEn: 'Build bar menus ahead of time so they open instantly. Uses more memory. '
            + 'After switching to Save memory, menus that are already built are released when the shell restarts.' },
      ] },
      { id: 'backup', labelUk: 'Резервні копії', labelEn: 'Backups',
        helpUk: 'Контрольна точка зберігає поточні теми й розкладку.', helpEn: 'A checkpoint saves the current theme and layout.', items: [
        { key: 'checkpoint', kind: 'text', control: 'button', action: 'config.checkpoint',
          labelUk: 'Створити контрольну точку', labelEn: 'Create checkpoint', icon: 'material/restart-symbolic.svg' },
        { key: 'restore', kind: 'text', control: 'button', action: 'config.restore',
          labelUk: 'Відновити контрольну точку', labelEn: 'Restore checkpoint' },
      ] },
    ],
  },
  {
    id: 'about', group: 'system', icon: 'pentad/info-symbolic.svg', labelUk: 'Про систему', labelEn: 'About',
    keywords: ['about', 'system', 'hostname', 'kernel', 'cpu', 'memory', 'version', 'uptime',
      'про систему', 'пристрій', 'ядро', 'процесор', 'пам’ять', 'версія'],
    sections: [
      { id: 'device', labelUk: 'Пристрій', labelEn: 'Device', items: [
        { key: 'aboutPanel', kind: 'text', control: 'panel', panel: 'about', labelUk: 'Відомості', labelEn: 'Details' },
      ] },
    ],
  },
];
