import { defaults, parseDocument } from './config.mjs';

const segments = (path) => String(path).split('.');
const isObject = (value) => value !== null && typeof value === 'object';

export function readValue(documents, item) {
  let node = documents && documents[item.document];
  for (const segment of segments(item.path)) {
    if (!isObject(node)) { node = undefined; break; }
    node = node[segment];
  }
  return node === undefined ? item.default : node;
}

// JSON clone: the QML JavaScript engine has no structuredClone, and documents are plain JSON.
const clone = value => value === undefined ? undefined : JSON.parse(JSON.stringify(value));

export function writeValue(documents, item, value) {
  const name = item.document;
  const source = documents && isObject(documents[name]) ? documents[name] : defaults[name];
  const document = isObject(source) ? clone(source) : {};
  const parts = segments(item.path);
  let node = document;
  for (const part of parts.slice(0, -1)) {
    if (!isObject(node[part])) node[part] = {};
    node = node[part];
  }
  node[parts[parts.length - 1]] = clone(value);
  return { name, document };
}

export function commitCheck(documents, item, value) {
  const { name, document } = writeValue(documents, item, value);
  const parsed = parseDocument(name, JSON.stringify(document));
  return parsed.ok ? { ok: true, name, document } : { ok: false, message: parsed.message };
}
