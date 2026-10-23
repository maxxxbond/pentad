// Presentation helpers for the system pages of the settings window (Date & time, Default apps, About).

const categoryNames = Object.freeze({
  web: ['Браузер', 'Web browser'],
  mail: ['Пошта', 'Mail'],
  files: ['Файли', 'Files'],
  text: ['Текстовий редактор', 'Text editor'],
  pdf: ['Документи PDF', 'PDF documents'],
  image: ['Зображення', 'Images'],
  audio: ['Музика', 'Music'],
  video: ['Відео', 'Video'],
});
const reasons = Object.freeze({
  denied: ['Система не дозволила зміну', 'The system did not allow the change'],
  timeout: ['Немає відповіді. Можливо, запит пароля скасовано', 'No answer. The password prompt may have been dismissed'],
  'invalid-timezone': ['Невідомий часовий пояс', 'Unknown time zone'],
  'unknown-application': ['Застосунок не підтримує цей тип', 'The application does not handle this type'],
  'xdg-mime-missing': ['Потрібен xdg-utils', 'Requires xdg-utils'],
  preview: ['Лише перегляд', 'Preview only'],
  'safe-mode': ['У безпечному режимі лише читання', 'Read only in safe mode'],
});

export function categoryLabel(category, text) {
  const names = categoryNames[category];
  return names ? text(names[0], names[1]) : String(category);
}

export function systemError(reason, text) {
  const names = reasons[reason];
  return names ? text(names[0], names[1]) : text('Не вдалося', 'Failed') + ' (' + (reason || 'failed') + ')';
}

// "31,3 ГБ" / "31.3 GB" with binary units; the decimal mark follows the language.
export function formatBytes(bytes, text) {
  if (!Number.isFinite(bytes) || bytes <= 0) return text('Невідомо', 'Unknown');
  const units = [['Б', 'B'], ['КБ', 'KB'], ['МБ', 'MB'], ['ГБ', 'GB'], ['ТБ', 'TB']];
  let value = bytes;
  let unit = 0;
  while (value >= 1024 && unit < units.length - 1) { value /= 1024; unit++; }
  const number = (unit === 0 || value >= 100 ? String(Math.round(value)) : value.toFixed(1)).replace(/\.0$/, '');
  const separator = text(',', '.');
  return number.replace('.', separator) + ' ' + text(units[unit][0], units[unit][1]);
}

// "2 д 5 год" / "2 d 5 h": the two largest units, minutes only under a day.
export function formatUptime(seconds, text) {
  if (!Number.isFinite(seconds) || seconds < 0) return text('Невідомо', 'Unknown');
  const days = Math.floor(seconds / 86400);
  const hours = Math.floor(seconds % 86400 / 3600);
  const minutes = Math.floor(seconds % 3600 / 60);
  if (days > 0) return days + ' ' + text('д', 'd') + (hours ? ' ' + hours + ' ' + text('год', 'h') : '');
  if (hours > 0) return hours + ' ' + text('год', 'h') + (minutes ? ' ' + minutes + ' ' + text('хв', 'min') : '');
  return minutes + ' ' + text('хв', 'min');
}

// Dropdown options for time zones; the current zone stays selectable even if the list lacks it.
export function timezoneOptions(zones, current) {
  const list = Array.isArray(zones) ? zones.filter(zone => typeof zone === 'string' && zone !== '') : [];
  if (typeof current === 'string' && current !== '' && list.indexOf(current) < 0) list.unshift(current);
  return list.map(zone => ({ value: zone, label: zone.replace(/_/g, ' ') }));
}

// Dropdown options for one default-app category; an unknown current choice is shown by its id.
// Candidates may arrive as a Qt list (a model role), which Array.isArray rejects; any list-like is read.
export function appOptions(entry) {
  if (!entry || !entry.candidates || typeof entry.candidates.length !== 'number') return [];
  const options = Array.from(entry.candidates).map(item => ({ value: item.id, label: item.name }));
  if (entry.current && !options.some(option => option.value === entry.current))
    options.unshift({ value: entry.current, label: entry.current.replace(/\.desktop$/, '') });
  return options;
}
