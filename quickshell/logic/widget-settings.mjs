// Builds the settings page of one widget from its manifest: General (manifest fields + Frame)
// and Placement (sections, per-section Position and Size). Output items use the shape of the
// settings catalog (see settings-schema.mjs) so every item can go through SettingsField.
// Placement values live in placement.settings of the layout document, under reserved `_` keys
// (see pentads.mjs), so pathPrefix is e.g. `widgets.3.settings`.
import { zones, zonesForSlots, frameLimits, backgrounds, sizesFor, defaultSize, defaultBackground, resolvePlacement } from './pentads.mjs';
import { settingDefault } from './plugin-manifest.mjs';

const object = value => value !== null && typeof value === 'object' && !Array.isArray(value);
const own = (value, key) => Object.prototype.hasOwnProperty.call(value, key);

const sizeLabels = {
  icon: ['Іконка', 'Icon'], row: ['Рядок', 'Row'], tile: ['Плитка', 'Tile'], label: ['Підпис', 'Label'], full: ['Повний', 'Full'],
};
const backgroundLabels = { none: ['Немає', 'None'], subtle: ['Ледь помітний', 'Subtle'], solid: ['Суцільний', 'Solid'] };
const zeroByKind = { text: '', boolean: false, integer: 0, number: 0, color: '#000000' };

function fieldItem(field, manifest, where) {
  const text = field.label ?? field.labelKey ?? field.key;
  const item = {
    key: field.key, kind: field.kind, document: where.document, path: `${where.pathPrefix}.${field.key}`,
    labelUk: field.labelUk ?? text, labelEn: field.labelEn ?? text,
  };
  const declaredDefault = settingDefault(manifest, field);
  item.default = declaredDefault !== undefined ? declaredDefault
    : field.kind === 'select' ? field.options?.[0]?.value : zeroByKind[field.kind];
  if (field.kind === 'boolean') item.control = 'toggle';
  else if (field.kind === 'select') {
    item.control = field.options.length <= 3 ? 'segmented' : 'dropdown';
    item.options = field.options.map(option => ({ value: option.value, labelUk: option.labelUk ?? option.label, labelEn: option.labelEn ?? option.label }));
  } else if (field.kind === 'integer' || field.kind === 'number') {
    item.control = 'stepper';
    item.min = typeof field.min === 'number' ? field.min : -2147483647;
    item.max = typeof field.max === 'number' ? field.max : 2147483647;
    item.step = typeof field.step === 'number' && field.step > 0 ? field.step : field.kind === 'integer' ? 1 : 0.1;
  } else item.control = field.kind === 'color' ? 'color' : 'text';
  if (field.helpUk !== undefined || field.helpEn !== undefined || field.help !== undefined) {
    item.helpUk = field.helpUk ?? field.help; item.helpEn = field.helpEn ?? field.help;
  }
  if (object(field.showWhen) && typeof field.showWhen.key === 'string' && own(field.showWhen, 'equals')) item.visibleWhen = { key: field.showWhen.key, equals: field.showWhen.equals };
  return item;
}

export function widgetSettingsPage(manifest, { document = 'layout', pathPrefix = 'settings', settings = {}, slot } = {}) {
  const where = { document, pathPrefix };
  const allowed = Array.isArray(manifest.pentads) && manifest.pentads.length ? manifest.pentads : zonesForSlots(manifest.allowedSlots);
  const resolved = resolvePlacement({ pentads: allowed }, settings, slot);
  // No object spread here: the QML JavaScript engine cannot parse it.
  const pathOf = key => `${pathPrefix}.${key}`;
  const sections = [];

  const groups = new Map();
  for (const field of Array.isArray(manifest.settingsFields) ? manifest.settingsFields : []) {
    const id = typeof field.group === 'string' && field.group ? field.group : 'settings';
    if (!groups.has(id)) groups.set(id, { id, labelUk: field.groupUk ?? field.group ?? 'Налаштування', labelEn: field.groupEn ?? field.group ?? 'Settings', items: [] });
    groups.get(id).items.push(fieldItem(field, manifest, where));
  }
  for (const group of groups.values()) sections.push({ id: `group-${group.id}`, tab: 'general', labelUk: group.labelUk, labelEn: group.labelEn, collapsible: true, items: group.items });

  sections.push({ id: 'frame', tab: 'general', labelUk: 'Рамка', labelEn: 'Frame', collapsible: true, items: [
    { key: '_framePreview', kind: 'integer', control: 'framePreview', document, path: pathOf('_margin'), default: frameLimits.margin.default,
      labelUk: 'Попередній перегляд', labelEn: 'Preview' },
    { key: '_margin', kind: 'integer', control: 'slider', document, path: pathOf('_margin'), default: frameLimits.margin.default,
      min: frameLimits.margin.min, max: frameLimits.margin.max, step: frameLimits.margin.step,
      labelUk: 'Зовнішній відступ', labelEn: 'Outer margin', helpUk: 'Простір навколо віджета, поза його поверхнею.', helpEn: 'Space around the widget, outside its surface.' },
    { key: '_padding', kind: 'integer', control: 'slider', document, path: pathOf('_padding'), default: frameLimits.padding.default,
      min: frameLimits.padding.min, max: frameLimits.padding.max, step: frameLimits.padding.step,
      labelUk: 'Внутрішній відступ', labelEn: 'Inner padding', helpUk: 'Простір між поверхнею та вмістом. Кути слідують: внутрішній радіус = радіус картки мінус відступ.', helpEn: 'Space between the surface and the content. Corners follow: inner radius = card radius minus padding.' },
    { key: '_bg', kind: 'select', control: 'segmented', document, path: pathOf('_bg'), default: defaultBackground,
      labelUk: 'Тло', labelEn: 'Background',
      options: backgrounds.map(value => ({ value, labelUk: backgroundLabels[value][0], labelEn: backgroundLabels[value][1] })) },
  ] });

  sections.push({ id: 'placement', tab: 'placement', labelUk: 'Де живе', labelEn: 'Where it lives', items: [
    { key: '_zones', kind: 'select', control: 'pentads', document, path: pathOf('_zones'), default: [allowed[0]], allowed: [...allowed],
      labelUk: 'Секції', labelEn: 'Sections', helpUk: 'Віджет живе принаймні в одній із п\'яти секцій.', helpEn: 'A widget lives in at least one of the five sections.' },
  ] });
  for (const zone of zones) {
    if (!allowed.includes(zone.id) || !resolved.zones.includes(zone.id)) continue;
    sections.push({ id: `zone-${zone.id}`, tab: 'placement', labelUk: zone.labelUk, labelEn: zone.labelEn, items: [
      { key: `_order_${zone.id}`, kind: 'integer', control: 'stepper', document, path: pathOf(`_order_${zone.id}`), default: frameLimits.position.default,
        min: frameLimits.position.min, max: frameLimits.position.max, step: frameLimits.position.step, labelUk: 'Позиція', labelEn: 'Position' },
      { key: `_size_${zone.id}`, kind: 'select', control: 'segmented', document, path: pathOf(`_size_${zone.id}`), default: defaultSize(zone.id),
        labelUk: 'Розмір', labelEn: 'Size',
        options: sizesFor(zone.id).map(value => ({ value, labelUk: sizeLabels[value][0], labelEn: sizeLabels[value][1] })) },
    ] });
  }

  return {
    id: `widget-${manifest.id}`, group: 'shell', labelUk: manifest.name, labelEn: manifest.name, keywords: [],
    tabs: [{ id: 'general', labelUk: 'Загальні', labelEn: 'General' }, { id: 'placement', labelUk: 'Розміщення', labelEn: 'Placement' }],
    sections,
  };
}
