// Offline reference data. Pentad defaults: defaults/hyprland-quickshell.lua;
// contextual shortcuts: shell/SpotlightHost.qml and features/overview/OverviewWindow.qml.
// Standard application commands (no plugin mappings):
// https://neovim.io/doc/user/quickref/
// https://neovim.io/doc/user/windows/
// https://support.mozilla.org/en-US/kb/keyboard-shortcuts-perform-firefox-tasks-quickly
// https://support.google.com/chrome/answer/157179
const catalog = [
    { id: 'pentad', uk: 'Pentad', en: 'Pentad', groups: [
        ['defaults', 'Типові глобальні клавіші · можуть бути змінені', 'Default global keys · may be remapped', [
            [['Super'], 'Пошук програм після відпускання', 'Application search on release'],
            [['Super', 'Space'], 'Відкрити пошук', 'Open search'],
            [['Super', 'V'], 'Історія буфера обміну', 'Clipboard history'],
            [['Super', '.'], 'Вибір емодзі', 'Emoji picker'],
            [['Super', '/'], 'Шпаргалки', 'Cheatsheets'],
            [['Super', 'Tab'], 'Огляд вікон', 'Window overview'],
            [['Alt', 'Tab'], 'Наступне вікно', 'Next window'],
            [['Alt', 'Shift', 'Tab'], 'Попереднє вікно', 'Previous window'],
            [['Alt', 'code:49'], 'Наступне вікно програми (фізична клавіша 49)', 'Next application window (physical key 49)'],
            [['Alt', 'Shift', 'code:49'], 'Попереднє вікно програми (фізична клавіша 49)', 'Previous application window (physical key 49)'],
        ]],
        ['search', 'У пошуку Spotlight', 'Inside Spotlight search', [
            [['↓ / ↑'], 'Наступний / попередній результат', 'Next / previous result'],
            [['Enter'], 'Відкрити вибраний результат', 'Open selected result'],
            [['Ctrl', 'K'], 'Дії для результату', 'Result actions'],
            [['Ctrl', 'Space'], 'Подробиці результату', 'Result details'],
            [['Ctrl', 'Shift', 'P'], 'Закріпити результат', 'Pin result'],
            [['Alt', '1…9'], 'Відкрити результат за номером', 'Open result by number'],
            [['Ctrl', 'Delete'], 'Видалити вибраний запис буфера обміну', 'Delete selected clipboard entry'],
            [['Esc'], 'Назад або закрити пошук', 'Go back or close search'],
        ]],
        ['overview', 'В огляді вікон', 'Inside window overview', [
            [['← / ↑ / → / ↓'], 'Вибрати вікно', 'Select a window'],
            [['Enter'], 'Перейти до вибраного вікна', 'Focus selected window'],
            [['M'], 'Вибрати місце переміщення вікна', 'Choose where to move the window'],
            [['Ctrl', '← / →'], 'Попередній / наступний робочий простір', 'Previous / next workspace'],
            [['PageUp / PageDown'], 'Попередня / наступна сторінка', 'Previous / next page'],
            [['Esc'], 'Закрити огляд', 'Close overview'],
        ]],
    ]},
    { id: 'neovim', uk: 'Neovim', en: 'Neovim', groups: [
        ['modes', 'Режими · типові клавіші Neovim', 'Modes · Neovim defaults', [
            [['Esc'], 'Повернутися у звичайний режим', 'Return to Normal mode'],
            [['i / a'], 'Вставляти перед / після курсора', 'Insert before / after cursor'],
            [['o / O'], 'Новий рядок нижче / вище', 'New line below / above'],
            [['v / V'], 'Виділяти символи / рядки', 'Select characters / lines'],
            [['Ctrl', 'V'], 'Блокове виділення', 'Block selection'],
            [[':'], 'Командний рядок', 'Command line'],
        ]],
        ['motion', 'Рух · звичайний режим', 'Movement · Normal mode', [
            [['h / j / k / l'], 'Ліворуч / вниз / вгору / праворуч', 'Left / down / up / right'],
            [['w / b'], 'Наступне / попереднє слово', 'Next / previous word'],
            [['0 / $'], 'Початок / кінець рядка', 'Line start / end'],
            [['gg / G'], 'Перший / останній рядок', 'First / last line'],
            [['Ctrl', 'd / u'], 'Пів екрана вниз / вгору', 'Half screen down / up'],
            [['%'], 'Парна дужка', 'Matching bracket'],
        ]],
        ['edit', 'Редагування · звичайний режим', 'Editing · Normal mode', [
            [['x'], 'Видалити символ', 'Delete character'],
            [['dd'], 'Вирізати рядок', 'Cut line'],
            [['yy'], 'Скопіювати рядок у регістр', 'Yank line into register'],
            [['p / P'], 'Вставити після / перед', 'Put after / before'],
            [['ciw'], 'Замінити слово під курсором', 'Change word under cursor'],
            [['u'], 'Скасувати зміну', 'Undo change'],
            [['Ctrl', 'r'], 'Повторити скасовану зміну', 'Redo change'],
            [['.'], 'Повторити останню зміну', 'Repeat last change'],
        ]],
        ['find', 'Пошук · звичайний режим', 'Search · Normal mode', [
            [['/text ↵'], 'Пошук уперед', 'Search forward'],
            [['?text ↵'], 'Пошук назад', 'Search backward'],
            [['n / N'], 'Наступний / попередній збіг', 'Next / previous match'],
            [['*'], 'Шукати слово під курсором', 'Find word under cursor'],
            [[':noh ↵'], 'Прибрати підсвічування збігів', 'Clear match highlighting'],
        ]],
        ['files', 'Файли й вікна · команди завершуються Enter', 'Files and windows · finish commands with Enter', [
            [[':w'], 'Зберегти файл', 'Write file'],
            [[':q'], 'Закрити вікно, якщо немає змін', 'Close window if unchanged'],
            [[':wq'], 'Зберегти й закрити', 'Write and close'],
            [[':q!'], 'Закрити без збереження змін', 'Close and discard changes'],
            [[':e file'], 'Відкрити файл', 'Edit file'],
            [[':split / :vsplit'], 'Горизонтальний / вертикальний поділ', 'Horizontal / vertical split'],
            [['Ctrl+w', 'w'], 'Наступне вікно (послідовність)', 'Next window (sequence)'],
            [[':bn / :bp'], 'Наступний / попередній буфер', 'Next / previous buffer'],
            [[':help'], 'Вбудована довідка', 'Built-in help'],
        ]],
    ]},
    { id: 'browser', uk: 'Браузер', en: 'Browser', groups: [
        ['tabs', 'Вкладки · Firefox / Chromium у Linux', 'Tabs · Firefox / Chromium on Linux', [
            [['Ctrl', 'T'], 'Нова вкладка', 'New tab'],
            [['Ctrl', 'W'], 'Закрити вкладку', 'Close tab'],
            [['Ctrl', 'Shift', 'T'], 'Відновити закриту вкладку', 'Restore closed tab'],
            [['Ctrl', 'PageDown'], 'Вкладка праворуч', 'Tab to the right'],
            [['Ctrl', 'PageUp'], 'Вкладка ліворуч', 'Tab to the left'],
            [['Ctrl', 'N'], 'Нове вікно', 'New window'],
        ]],
        ['navigation', 'Навігація', 'Navigation', [
            [['Ctrl', 'L'], 'Адресний рядок', 'Address bar'],
            [['Alt', '← / →'], 'Назад / уперед', 'Back / forward'],
            [['Ctrl', 'R'], 'Оновити сторінку', 'Reload page'],
            [['Ctrl', 'Shift', 'R'], 'Оновити без кешу', 'Reload bypassing cache'],
            [['Esc'], 'Зупинити завантаження', 'Stop loading'],
            [['Ctrl', 'F'], 'Пошук на сторінці', 'Find on page'],
            [['Ctrl', 'G'], 'Наступний збіг', 'Next match'],
        ]],
        ['page', 'Сторінка', 'Page', [
            [['Ctrl', '+ / −'], 'Збільшити / зменшити масштаб', 'Zoom in / out'],
            [['Ctrl', '0'], 'Скинути масштаб', 'Reset zoom'],
            [['Ctrl', 'D'], 'Додати закладку', 'Bookmark page'],
            [['Ctrl', 'H'], 'Історія перегляду', 'Browsing history'],
            [['Ctrl', 'J'], 'Завантаження', 'Downloads'],
            [['Ctrl', 'P'], 'Друк', 'Print'],
            [['Ctrl', 'S'], 'Зберегти сторінку', 'Save page'],
        ]],
    ]},
    { id: 'git', uk: 'Git', en: 'Git', groups: [
        ['inspect', 'Перегляд · після git, Enter виконує', 'Inspect · after git, Enter runs', [
            [['status'], 'Стан робочих файлів та індексу', 'Working tree and staging status'],
            [['diff'], 'Непідготовлені зміни', 'Unstaged changes'],
            [['diff', '--staged'], 'Зміни, підготовлені до коміту', 'Changes staged for commit'],
            [['log', '--oneline'], 'Стисла історія комітів', 'Compact commit history'],
            [['show'], 'Останній коміт і його зміни', 'Latest commit and its changes'],
            [['branch'], 'Локальні гілки', 'Local branches'],
            [['remote', '-v'], 'Адреси віддалених репозиторіїв', 'Remote repository addresses'],
        ]],
        ['work', 'Робочі зміни · після git', 'Working changes · after git', [
            [['add', 'file'], 'Підготувати файл до коміту', 'Stage a file'],
            [['add', '-p'], 'Вибрати фрагменти для коміту', 'Choose hunks to stage'],
            [['restore', '--staged', 'file'], 'Зняти файл з індексу, зберігши зміни', 'Unstage a file, keeping edits'],
            [['commit'], 'Створити коміт підготовлених змін', 'Commit staged changes'],
            [['commit', '-s'], 'Коміт із підписом DCO', 'Commit with DCO sign-off'],
            [['stash', 'push'], 'Тимчасово сховати зміни відстежуваних файлів', 'Stash changes to tracked files'],
            [['stash', 'list'], 'Список схованих змін', 'List stashed changes'],
            [['stash', 'apply'], 'Застосувати останню схованку, зберігши її', 'Apply latest stash, retaining it'],
        ]],
        ['branches', 'Гілки й синхронізація · після git', 'Branches and sync · after git', [
            [['switch', 'branch'], 'Перейти до наявної гілки', 'Switch to an existing branch'],
            [['switch', '-c', 'name'], 'Створити гілку й перейти до неї', 'Create and switch to a branch'],
            [['fetch'], 'Отримати віддалену історію без злиття', 'Fetch remote history without merging'],
            [['pull', '--ff-only'], 'Оновити гілку лише без розходження історії', 'Update only with a fast-forward'],
            [['merge', 'branch'], 'Об’єднати вказану гілку з поточною', 'Merge named branch into current branch'],
            [['push'], 'Опублікувати коміти у налаштовану віддалену гілку', 'Publish commits to configured remote branch'],
            [['stash', 'pop'], 'Застосувати останню схованку й видалити її', 'Apply latest stash and drop it'],
            [['tag', 'name'], 'Позначити поточний коміт міткою', 'Tag the current commit'],
        ]],
        ['history', 'Історія й скасування · після git', 'History and undo · after git', [
            [['log', '--graph', '--oneline'], 'Історія гілок у вигляді графа', 'Branch history as a graph'],
            [['blame', 'file'], 'Хто востаннє змінив кожен рядок файлу', 'Who last changed each line of a file'],
            [['restore', 'file'], 'Скасувати непідготовлені зміни файлу (незворотно)', 'Discard unstaged edits to a file (irreversible)'],
            [['commit', '--amend'], 'Виправити останній коміт, поки він не опублікований', 'Amend the last commit while unpublished'],
            [['revert', 'commit'], 'Новий коміт, що скасовує вказаний', 'New commit that undoes the given one'],
            [['reset', '--soft', 'HEAD~1'], 'Скасувати останній коміт, зберігши зміни підготовленими', 'Undo the last commit, keeping changes staged'],
            [['cherry-pick', 'commit'], 'Перенести вказаний коміт у поточну гілку', 'Copy the given commit onto the current branch'],
            [['reflog'], 'Журнал переміщень HEAD для відновлення втраченого', 'HEAD movement log for recovering lost work'],
        ]],
        ['start', 'Початок роботи · після git', 'Getting started · after git', [
            [['init'], 'Створити репозиторій у поточному каталозі', 'Create a repository in the current directory'],
            [['clone', 'url'], 'Скопіювати віддалений репозиторій', 'Copy a remote repository'],
            [['config', '--global', 'user.name', 'name'], 'Задати ім’я автора комітів', 'Set the commit author name'],
            [['config', '--global', 'user.email', 'email'], 'Задати пошту автора комітів', 'Set the commit author email'],
        ]],
    ]},
    { id: 'terminal', uk: 'Термінал', en: 'Terminal', groups: [
        ['edit', 'Bash / Zsh · режим редагування Emacs', 'Bash / Zsh · Emacs editing mode', [
            [['Ctrl', 'A'], 'На початок командного рядка', 'Start of command line'],
            [['Ctrl', 'E'], 'У кінець командного рядка', 'End of command line'],
            [['Ctrl', 'B / F'], 'На символ назад / уперед', 'One character backward / forward'],
            [['Alt', 'B / F'], 'На слово назад / уперед', 'One word backward / forward'],
            [['Ctrl', 'U'], 'Bash: вирізати до початку; Zsh: увесь рядок', 'Bash: cut to start; Zsh: cut whole line'],
            [['Ctrl', 'K'], 'Вирізати до кінця рядка', 'Cut to end of line'],
            [['Ctrl', 'W'], 'Вирізати попереднє слово', 'Cut previous word'],
            [['Ctrl', 'Y'], 'Вставити вирізаний текст', 'Yank cut text'],
            [['Ctrl', 'T'], 'Поміняти місцями сусідні символи', 'Transpose adjacent characters'],
            [['Tab'], 'Доповнити команду або шлях', 'Complete command or path'],
        ]],
        ['history', 'Історія · Bash / Zsh у режимі Emacs', 'History · Bash / Zsh in Emacs mode', [
            [['↑ / ↓'], 'Попередня / наступна команда', 'Previous / next command'],
            [['Ctrl', 'R'], 'Шукати назад в історії', 'Search history backward'],
            [['Ctrl', 'G'], 'Скасувати пошук в історії', 'Cancel history search'],
            [['Ctrl', 'L'], 'Очистити видиму область і перемалювати рядок', 'Clear display and redraw line'],
        ]],
        ['process', 'Керування процесами · типовий термінал', 'Process control · typical terminal', [
            [['Ctrl', 'C'], 'Надіслати переривання активній команді', 'Interrupt foreground command'],
            [['Ctrl', 'Z'], 'Призупинити активну команду', 'Suspend foreground command'],
            [['Ctrl', 'D'], 'На порожньому рядку: EOF, зазвичай вихід', 'On empty line: EOF, usually exit'],
        ]],
        ['commands', 'Команди оболонки · завершуються Enter', 'Shell commands · finish with Enter', [
            [['jobs'], 'Список завдань поточної оболонки', 'List jobs in current shell'],
            [['fg'], 'Повернути поточне завдання на передній план', 'Resume current job in foreground'],
            [['bg'], 'Продовжити поточне завдання у фоні', 'Resume current job in background'],
            [['pwd'], 'Показати поточний каталог', 'Show current directory'],
            [['cd', '-'], 'Повернутися в попередній каталог', 'Return to previous directory'],
        ]],
    ]},
    { id: 'kitty', uk: 'kitty', en: 'kitty', groups: [
        ['clipboard', 'Буфер обміну · типові клавіші kitty', 'Clipboard · kitty defaults', [
            [['Ctrl', 'Shift', 'C'], 'Копіювати виділене', 'Copy selection'],
            [['Ctrl', 'Shift', 'V'], 'Вставити з буфера обміну', 'Paste from clipboard'],
            [['Ctrl', 'Shift', 'S'], 'Вставити виділення', 'Paste selection'],
            [['Shift', 'Insert'], 'Вставити виділення', 'Paste selection'],
        ]],
        ['scroll', 'Прокручування й історія виводу', 'Scrolling and output history', [
            [['Ctrl', 'Shift', '↑ / ↓'], 'Рядок вгору / вниз', 'Line up / down'],
            [['Ctrl', 'Shift', 'PageUp / PageDown'], 'Сторінка вгору / вниз', 'Page up / down'],
            [['Ctrl', 'Shift', 'Home / End'], 'На початок / у кінець історії', 'To the top / bottom of history'],
            [['Ctrl', 'Shift', 'Z / X'], 'Попередній / наступний рядок запрошення (потрібна інтеграція з оболонкою)', 'Previous / next prompt (needs shell integration)'],
            [['Ctrl', 'Shift', 'H'], 'Історія виводу в переглядачі', 'Scrollback in a pager'],
            [['Ctrl', 'Shift', 'G'], 'Вивід останньої команди в переглядачі (потрібна інтеграція з оболонкою)', 'Last command output in a pager (needs shell integration)'],
        ]],
        ['windows', 'Вікна й розкладки', 'Windows and layouts', [
            [['Ctrl', 'Shift', 'Enter'], 'Нове вікно в поточній вкладці', 'New window in the current tab'],
            [['Ctrl', 'Shift', 'N'], 'Нове вікно ОС', 'New OS window'],
            [['Ctrl', 'Shift', 'W'], 'Закрити вікно', 'Close window'],
            [['Ctrl', 'Shift', '] / ['], 'Наступне / попереднє вікно', 'Next / previous window'],
            [['Ctrl', 'Shift', 'F / B'], 'Посунути вікно вперед / назад', 'Move window forward / backward'],
            [['Ctrl', 'Shift', '1…9'], 'Перейти до вікна за номером', 'Go to window by number'],
            [['Ctrl', 'Shift', 'R'], 'Змінити розмір вікна клавішами', 'Resize window with keys'],
            [['Ctrl', 'Shift', 'L'], 'Наступна розкладка вікон', 'Next window layout'],
        ]],
        ['tabs', 'Вкладки', 'Tabs', [
            [['Ctrl', 'Shift', 'T'], 'Нова вкладка', 'New tab'],
            [['Ctrl', 'Shift', 'Q'], 'Закрити вкладку', 'Close tab'],
            [['Ctrl', 'Shift', '→ / ←'], 'Наступна / попередня вкладка', 'Next / previous tab'],
            [['Ctrl', 'Shift', '. / ,'], 'Посунути вкладку вперед / назад', 'Move tab forward / backward'],
            [['Ctrl', 'Shift', 'Alt', 'T'], 'Перейменувати вкладку', 'Set tab title'],
        ]],
        ['font', 'Шрифт і вікно', 'Font and window', [
            [['Ctrl', 'Shift', '+'], 'Збільшити шрифт', 'Increase font size'],
            [['Ctrl', 'Shift', '−'], 'Зменшити шрифт', 'Decrease font size'],
            [['Ctrl', 'Shift', 'Backspace'], 'Скинути розмір шрифту', 'Reset font size'],
            [['Ctrl', 'Shift', 'F11'], 'Повноекранний режим', 'Toggle fullscreen'],
            [['Ctrl', 'Shift', 'F10'], 'Розгорнути вікно', 'Toggle maximized'],
        ]],
        ['actions', 'Дії над текстом і конфігурація', 'Text actions and configuration', [
            [['Ctrl', 'Shift', 'E'], 'Вибрати посилання підказкою й відкрити', 'Pick a link by hint and open it'],
            [['Ctrl', 'Shift', 'P', 'F'], 'Вибрати шлях підказкою й вставити (послідовність)', 'Pick a path by hint and insert it (sequence)'],
            [['Ctrl', 'Shift', 'U'], 'Ввести символ Unicode', 'Enter a Unicode character'],
            [['Ctrl', 'Shift', 'Delete'], 'Очистити термінал і скинути стан', 'Clear and reset the terminal'],
            [['Ctrl', 'Shift', 'F2'], 'Відкрити kitty.conf', 'Open kitty.conf'],
            [['Ctrl', 'Shift', 'F5'], 'Перечитати kitty.conf', 'Reload kitty.conf'],
        ]],
    ]},
];

function translator(text) {
    return typeof text === 'function' ? text : function(uk, en) { return text === 'uk' ? uk : en; };
}

export function sheets(text) {
    const tr = translator(text);
    return catalog.map(function(sheet) { return { id: sheet.id, label: tr(sheet.uk, sheet.en) }; });
}

export function groupsFor(id, text) {
    const tr = translator(text);
    const sheet = catalog.find(function(item) { return item.id === id; });
    if (!sheet) return [];
    return sheet.groups.map(function(group) {
        return {
            id: sheet.id + '-' + group[0],
            label: tr(group[1], group[2]),
            search: [sheet.uk, sheet.en, group[1], group[2]].join(' ').toLowerCase(),
            binds: group[3].map(function(row) {
                return {
                    keys: row[0].slice(), description: tr(row[1], row[2]), described: true, lua: false,
                    search: [row[0].join(' '), row[0].join('+'), row[1], row[2]].join(' ').toLowerCase(),
                };
            }),
        };
    });
}
