import { readValue } from './settings-bindings.mjs';

const same = (a, b) => JSON.stringify(a) === JSON.stringify(b);

// An item can be reset when it is stored in a document and declares a default.
export function isResettable(item) {
  return !!item && item.document !== undefined && item.default !== undefined && item.control !== 'button' && item.control !== 'link';
}

// Resettable items of a page whose stored value differs from the default, in catalog order.
export function modifiedItems(documents, page) {
  if (!page || !Array.isArray(page.sections)) return [];
  const result = [];
  for (const section of page.sections) {
    for (const item of section.items) {
      if (isResettable(item) && !same(readValue(documents, item), item.default)) result.push(item);
    }
  }
  return result;
}

export function enabledWidgetCount(documents) {
  const widgets = documents?.layout?.widgets;
  return Array.isArray(widgets) ? widgets.filter(entry => entry && entry.enabled !== false).length : 0;
}
