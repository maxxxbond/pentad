export const templates = Object.freeze([
  "icon",
  "compact",
  "tile",
  "row",
  "vertical",
  "range-horizontal",
  "range-vertical",
]);

const maxItems = 64;
export const gridColumnChoices = Object.freeze([3, 4, 6]);
const legacyColumns = 4;
const maxColumns = 6;
const maxRowSpan = 8;
export const maxEditorRowSpan = 3;
// Text-bearing templates need at least half of the line; icons fit a single cell.
const halfLineTemplates = new Set(["compact", "tile", "row", "range-horizontal"]);
// A standing button needs a third of the line so its label stays readable under the icon.
const thirdLineTemplates = new Set(["vertical"]);
const templateMinimumRows = { tile: 2, vertical: 2, "range-vertical": 2 };
const templateSpans = {
  icon: { columnSpan: 1, rowSpan: 1 },
  compact: { columnSpan: 2, rowSpan: 1 },
  tile: { columnSpan: 2, rowSpan: 2 },
  row: { columnSpan: 4, rowSpan: 1 },
  vertical: { columnSpan: 1, rowSpan: 2 },
  "range-horizontal": { columnSpan: 4, rowSpan: 1 },
  "range-vertical": { columnSpan: 1, rowSpan: 3 },
};

export function defaultSpan(template) {
  const span = typeof template === "string" && Object.prototype.hasOwnProperty.call(templateSpans, template)
    ? templateSpans[template] : null;
  return span ? Object.assign({}, span) : null;
}

export function menuColumns(layout) {
  return layout && gridColumnChoices.includes(layout.columns) ? layout.columns : legacyColumns;
}

export function minimumTemplateColumns(template, columns = legacyColumns) {
  return halfLineTemplates.has(template) ? Math.ceil(columns / 2)
    : thirdLineTemplates.has(template) ? Math.max(1, Math.floor(columns / 3)) : 1;
}

export function minimumColumnSpan(control, columns = legacyColumns) {
  if (control && Array.isArray(control.templates)
    && (control.templates.includes("icon") || control.templates.includes("range-vertical"))) return 1;
  if (control && Array.isArray(control.templates) && control.templates.includes("vertical"))
    return minimumTemplateColumns("vertical", columns);
  return Math.min(columns, Math.ceil(columns / 2));
}

// Size decides the presentation, like a resizable launcher widget: a cell is an icon,
// half a line or more is a row, a taller half line becomes a tile and a taller narrow cell
// stands up as a vertical button.
// A level (volume, brightness) is a slider: one line lays it flat, two or more stand it up.
export function templateForSpan(control, columnSpan, rowSpan, columns = legacyColumns) {
  const supported = control && Array.isArray(control.templates) ? control.templates : [];
  if (supported.includes("range-horizontal") && supported.includes("range-vertical"))
    return rowSpan >= 2 ? "range-vertical" : "range-horizontal";
  const wide = columnSpan * 2 >= columns;
  if (wide && rowSpan >= 2 && supported.includes("tile")) return "tile";
  if (wide && supported.includes("row")) return "row";
  if (wide && supported.includes("compact")) return "compact";
  if (rowSpan >= 2 && supported.includes("vertical")) return "vertical";
  if (supported.includes("icon")) return "icon";
  return ["row", "compact", "tile"].find(template => supported.includes(template)) || null;
}

export function resizePlacement(item, control, columnSpan, rowSpan, columns = legacyColumns) {
  const width = Math.max(minimumColumnSpan(control, columns), Math.min(columns,
    Number.isFinite(columnSpan) ? Math.round(columnSpan) : 1));
  const height = Math.max(1, Math.min(maxEditorRowSpan, Number.isFinite(rowSpan) ? Math.round(rowSpan) : 1));
  const template = templateForSpan(control, width, height, columns) || item.template;
  const rows = Math.max(height, templateMinimumRows[template] || 1);
  return Object.assign({}, item, { template, columnSpan: Math.max(width, minimumTemplateColumns(template, columns)),
    rowSpan: rows });
}

export function moveItem(items, instanceId, targetIndex) {
  const list = Array.isArray(items) ? items.slice() : [];
  const from = list.findIndex(item => item.instanceId === instanceId);
  if (from < 0) return list;
  const [moved] = list.splice(from, 1);
  list.splice(Math.max(0, Math.min(list.length, targetIndex)), 0, moved);
  return list;
}

// Index in `items` that a dragged control takes when dropped on a grid cell:
// the control under the cell, otherwise the next control in reading order.
export function dropIndex(items, placed, row, column, columns, instanceId) {
  const others = placed.filter(entry => entry.instanceId !== instanceId);
  const key = entry => entry.row * columns + entry.column;
  const target = others.find(entry => row >= entry.row && row < entry.row + entry.rowSpan
    && column >= entry.column && column < entry.column + entry.columnSpan)
    || others.slice().sort((a, b) => key(a) - key(b)).find(entry => key(entry) > row * columns + column);
  const order = items.filter(item => item.instanceId !== instanceId);
  if (!target) return order.length;
  const index = order.findIndex(item => item.instanceId === target.instanceId);
  const self = placed.find(entry => entry.instanceId === instanceId);
  // Dropping onto a later neighbour places the control after it, so a short drag still swaps.
  return self && key(self) < key(target) && row * columns + column >= key(target) ? index + 1 : index;
}

export function setItemVisible(items, instanceId, visible) {
  return (Array.isArray(items) ? items : []).map(item => item.instanceId === instanceId
    ? Object.assign({}, item, { visible: visible === true }) : item);
}

const definition = (id, label, icon, capabilities, compatibleTemplates, metadata = {}) => {
  const result = { id, label, icon, capabilities, templates: compatibleTemplates };
  if (metadata.lifecycle) result.lifecycle = metadata.lifecycle;
  return result;
};

export const builtinDefinitions = {
  bluetooth: definition("bluetooth", "Bluetooth", "bluetooth-symbolic", {
    toggle: "toggle",
    choice: "select",
    details: true,
  }, ["icon", "compact", "tile", "row", "vertical"]),
  "audio-output": definition("audio-output", "Output", "audio-volume-high-symbolic", {
    toggle: "mute",
    choice: "select",
    range: { from: 0, to: 1, step: 0.02, unit: "%", scale: 100, action: "level" },
    details: true,
  }, ["icon", "compact", "tile", "row", "range-horizontal", "range-vertical"]),
  "audio-input": definition("audio-input", "Input", "audio-input-microphone-symbolic", {
    toggle: "mute",
    choice: "select",
    range: { from: 0, to: 1, step: 0.02, unit: "%", scale: 100, action: "level" },
    details: true,
  }, ["icon", "compact", "tile", "row", "range-horizontal", "range-vertical"]),
  brightness: definition("brightness", "Brightness", "display-brightness-symbolic", {
    range: { from: 0, to: 1, step: 0.01, unit: "%", scale: 100, action: "level" },
    details: false,
  }, ["compact", "tile", "row", "range-horizontal", "range-vertical"]),
  dnd: definition("dnd", "Do not disturb", "notifications-disabled-symbolic", {
    toggle: "toggle",
    details: false,
  }, ["icon", "compact", "tile", "row", "vertical"]),
  inhibit: definition("inhibit", "Keep awake", "system-lock-screen-symbolic", {
    toggle: "toggle",
    details: false,
  }, ["icon", "compact", "tile", "row", "vertical"]),
  overnight: definition("overnight", "Overnight mode", "weather-clear-night-symbolic", {
    toggle: "toggle",
    details: false,
  }, ["icon", "compact", "tile", "row", "vertical"]),
  screenshot: definition("screenshot", "Screenshot", "camera-photo-symbolic", {
    primary: "screenshot.capture",
    details: false,
  }, ["icon", "compact", "tile", "row", "vertical"]),
  appearance: definition("appearance", "Dark theme", "contrast-symbolic", {
    toggle: "toggle",
    details: false,
  }, ["icon", "compact", "tile", "row", "vertical"]),
  record: definition("record", "Screen recording", "media-record-symbolic", {
    primary: "record.start",
    details: true,
  }, ["icon", "compact", "tile", "row", "vertical"], {
    lifecycle: {
      states: ["idle", "recording"],
      commands: { idle: ["record.start"], recording: ["record.stop"] },
    },
  }),
  wifi: definition("wifi", "Wi-Fi", "network-wireless-symbolic", {
    toggle: "toggle",
    choice: "select",
    details: true,
  }, ["icon", "compact", "tile", "row", "vertical"]),
  network: definition("network", "Network", "network-wireless-symbolic", {
    toggle: "toggle",
    details: true,
  }, ["icon", "compact", "tile", "row", "vertical"]),
  tailscale: definition("tailscale", "Tailscale", "shield-symbolic", {
    primary: "tailscale.open",
    details: false,
  }, ["icon", "compact", "tile", "row", "vertical"]),
  vpn: definition("vpn", "VPN", "network-vpn-symbolic", {
    toggle: "toggle",
    details: true,
  }, ["icon", "compact", "tile", "row", "vertical"]),
  airplane: definition("airplane", "Airplane mode", "airplane-mode-symbolic", {
    toggle: "toggle",
    details: false,
  }, ["icon", "compact", "tile", "row", "vertical"]),
  "night-light": definition("night-light", "Night light", "night-light-symbolic", {
    toggle: "toggle",
    details: false,
  }, ["icon", "compact", "tile", "row", "vertical"]),
  night: definition("night", "Night light", "night-light-symbolic", {
    toggle: "toggle",
    details: false,
  }, ["icon", "compact", "tile", "row", "vertical"]),
  "power-profile": definition("power-profile", "Power profile", "power-profile-balanced-symbolic", {
    choice: "select",
    details: true,
  }, ["compact", "tile", "row", "vertical"]),
  energy: definition("energy", "Energy", "power-profile-balanced-symbolic", {
    choice: "select",
    primary: "details",
    details: true,
  }, ["compact", "tile", "row", "vertical"]),
  lock: definition("lock", "Lock screen", "system-lock-screen-symbolic", {
    primary: "session.lock",
    details: false,
  }, ["icon", "compact", "tile", "vertical"]),
  timer: definition("timer", "Timer", "alarm-symbolic", {
    primary: "start",
    details: true,
  }, ["icon", "compact", "tile", "row", "vertical"], {
    lifecycle: {
      states: ["idle", "running"],
      commands: { idle: ["start"], running: ["stop"] },
    },
  }),
  telemetry: definition("telemetry", "System status", "utilities-system-monitor-symbolic", {
    details: false,
  }, ["compact", "tile", "row", "vertical"]),
};

const quickRow = (id, columnSpan = 3) => ({
  instanceId: id, definitionId: id, template: "row", columnSpan, rowSpan: 1, visible: true,
});
const quickIcon = (id, visible = true) => ({
  instanceId: id, definitionId: id, template: "icon", columnSpan: 1, rowSpan: 1, visible,
});
const quickLevel = (id, columnSpan = 6) => ({
  instanceId: id, definitionId: id, template: "range-horizontal", columnSpan, rowSpan: 1, visible: true,
});
export const levelControlIds = Object.freeze(["brightness", "audio-output", "audio-input"]);

// Six columns: two half-width rows per line, a full line of round toggles, then the level sliders.
export const defaultQuickMenu = {
  version: 1,
  columns: 6,
  items: [
    quickRow("network"),
    quickRow("bluetooth"),
    quickRow("vpn"),
    quickRow("energy"),
    quickIcon("airplane"),
    quickIcon("dnd"),
    quickIcon("night"),
    quickIcon("inhibit"),
    quickIcon("appearance"),
    quickIcon("screenshot"),
    // Listed so the editor can offer it, hidden so the line of round toggles stays full.
    quickIcon("overnight", false),
    ...levelControlIds.map(id => quickLevel(id)),
  ],
};

// Layouts saved before the level sliders joined the grid get them appended as full lines;
// a slider the user hid stays hidden because it is still listed.
export function withLevelControls(layout) {
  const items = layout && Array.isArray(layout.items) ? layout.items : [];
  const missing = levelControlIds.filter(id => !items.some(item => item.definitionId === id));
  if (!missing.length) return layout;
  return Object.assign({}, layout, { items: items.concat(missing.map(id => quickLevel(id, menuColumns(layout)))) });
}

export function rescaleMenu(layout, columns, registry = builtinDefinitions) {
  const from = menuColumns(layout);
  const target = gridColumnChoices.includes(columns) ? columns : from;
  const items = (layout && Array.isArray(layout.items) ? layout.items : []).map(item => {
    const control = registry[item.definitionId] || null;
    const smallest = minimumTemplateColumns(item.template, from);
    // A control keeps its kind across grids: the smallest size of its kind (one cell, half
    // a line) and a full line map to the same size, everything else scales proportionally.
    const scaled = item.columnSpan >= from ? target
      : item.columnSpan <= smallest ? minimumTemplateColumns(item.template, target)
      : Math.round(item.columnSpan * target / from - 0.01);
    const span = Math.max(scaled, minimumTemplateColumns(item.template, target));
    return resizePlacement(item, control, span, item.rowSpan, target);
  });
  return { version: 1, columns: target, items };
}

export function addControl(items, definitionId, columns = legacyColumns, registry = builtinDefinitions) {
  const control = registry[definitionId];
  if (!control) return Array.isArray(items) ? items.slice() : [];
  const rest = (Array.isArray(items) ? items : []).filter(item => item.instanceId !== definitionId);
  const existing = (items || []).find(item => item.instanceId === definitionId);
  const base = existing || { instanceId: definitionId, definitionId, template: "icon", columnSpan: 1, rowSpan: 1 };
  const span = existing ? existing.columnSpan : minimumColumnSpan(control, columns);
  return rest.concat([Object.assign(resizePlacement(base, control, span, existing ? existing.rowSpan : 1, columns),
    { visible: true })]);
}

const plainObject = value => value !== null && typeof value === "object"
  && (Object.getPrototypeOf(value) === Object.prototype || Object.getPrototypeOf(value) === null);
const validId = value => typeof value === "string" && /^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$/.test(value);
export function controlDefinition(id, overrides = {}) {
  const base = typeof id === "string" && Object.prototype.hasOwnProperty.call(builtinDefinitions, id)
    ? builtinDefinitions[id] : null;
  if (!base) return null;
  const result = JSON.parse(JSON.stringify(base));
  if (plainObject(overrides)) {
    for (const key of ["label", "icon"]) {
      if (typeof overrides[key] === "string") result[key] = overrides[key];
    }
  }
  return result;
}

export function supportsTemplate(control, template) {
  return templates.includes(template) && !!control && Array.isArray(control.templates)
    && control.templates.includes(template);
}

export function validateMenuLayout(layout, registry = builtinDefinitions) {
  const errors = [];
  if (!plainObject(layout)) return { ok: false, errors: ["layout must be a plain object"] };
  const layoutKeys = new Set(["version", "columns", "items"]);
  for (const key of Object.keys(layout)) if (!layoutKeys.has(key)) errors.push(`layout.${key} is not allowed`);
  if (Object.prototype.hasOwnProperty.call(layout, "columns") && !gridColumnChoices.includes(layout.columns))
    errors.push(`layout.columns must be one of ${gridColumnChoices.join(", ")}`);
  const columns = menuColumns(layout);
  if (layout.version !== 1) errors.push("layout.version must be 1");
  if (!Array.isArray(layout.items)) errors.push("layout.items must be an array");
  else if (layout.items.length > maxItems) errors.push(`layout.items must contain at most ${maxItems} items`);

  const seen = new Set();
  const valueItems = [];
  for (const [index, item] of (Array.isArray(layout.items) ? layout.items.slice(0, maxItems) : []).entries()) {
    const path = `layout.items[${index}]`;
    if (!plainObject(item)) {
      errors.push(`${path} must be a plain object`);
      continue;
    }
    const allowed = new Set(["instanceId", "definitionId", "template", "columnSpan", "rowSpan", "visible"]);
    for (const key of Object.keys(item)) if (!allowed.has(key)) errors.push(`${path}.${key} is not allowed`);

    if (!validId(item.instanceId)) errors.push(`${path}.instanceId must be a valid ID`);
    else if (seen.has(item.instanceId)) errors.push(`${path}.instanceId is duplicated`);
    else seen.add(item.instanceId);

    if (!validId(item.definitionId)) errors.push(`${path}.definitionId must be a valid ID`);
    const control = validId(item.definitionId) && registry
      && Object.prototype.hasOwnProperty.call(registry, item.definitionId) ? registry[item.definitionId] : null;
    if (!control) errors.push(`${path}.definitionId is unknown`);
    if (!templates.includes(item.template)) errors.push(`${path}.template is invalid`);
    else if (control && !supportsTemplate(control, item.template)) errors.push(`${path}.template is incompatible with ${item.definitionId}`);
    for (const key of ["columnSpan", "rowSpan"]) {
      const limit = key === "columnSpan" ? columns : maxRowSpan;
      if (!Number.isFinite(item[key]) || !Number.isInteger(item[key]) || item[key] < 1 || item[key] > limit) {
        errors.push(`${path}.${key} must be an integer from 1 to ${limit}`);
      }
    }
    const minimumColumns = minimumTemplateColumns(item.template, columns);
    if (templates.includes(item.template) && Number.isInteger(item.columnSpan) && item.columnSpan < minimumColumns) {
      errors.push(`${path}.columnSpan is too small for ${item.template}`);
    }
    const minimumRows = Object.prototype.hasOwnProperty.call(templateMinimumRows, item.template)
      ? templateMinimumRows[item.template] : 1;
    if (templates.includes(item.template) && Number.isInteger(item.rowSpan) && item.rowSpan < minimumRows) {
      errors.push(`${path}.rowSpan is too small for ${item.template}`);
    }
    if (typeof item.visible !== "boolean") errors.push(`${path}.visible must be a boolean`);
    valueItems.push({
      instanceId: item.instanceId,
      definitionId: item.definitionId,
      template: item.template,
      columnSpan: item.columnSpan,
      rowSpan: item.rowSpan,
      visible: item.visible,
    });
  }

  if (errors.length) return { ok: false, errors };
  const value = gridColumnChoices.includes(layout.columns)
    ? { version: 1, columns: layout.columns, items: valueItems } : { version: 1, items: valueItems };
  return { ok: true, value, errors };
}

export function layoutMenu(items, columns = 4, options = {}) {
  const columnCount = Number.isFinite(columns) ? Math.max(1, Math.min(maxColumns, Math.floor(columns))) : maxColumns;
  const occupied = [];
  const placed = [];
  let rows = 0;

  for (const item of (Array.isArray(items) ? items.slice(0, maxItems) : [])) {
    if (!item || item.visible === false) continue;
    const columnSpan = Math.min(columnCount, Number.isFinite(item.columnSpan) && item.columnSpan >= 1
      ? Math.ceil(item.columnSpan) : 1);
    const rowSpan = Math.min(maxRowSpan, Number.isFinite(item.rowSpan) && item.rowSpan >= 1 ? Math.ceil(item.rowSpan) : 1);
    let row = 0;
    let column = 0;
    for (;;) {
      if (column + columnSpan > columnCount) {
        row++;
        column = 0;
        continue;
      }
      let free = true;
      for (let y = row; y < row + rowSpan && free; y++) {
        for (let x = column; x < column + columnSpan; x++) {
          if (occupied[y] && occupied[y][x]) { free = false; break; }
        }
      }
      if (free) break;
      if (++column + columnSpan > columnCount) { row++; column = 0; }
    }
    for (let y = row; y < row + rowSpan; y++) {
      if (!occupied[y]) occupied[y] = [];
      for (let x = column; x < column + columnSpan; x++) occupied[y][x] = true;
    }
    rows = Math.max(rows, row + rowSpan);
    placed.push(Object.assign({}, item, {
      column: column,
      row: row,
      columnSpan: columnSpan,
      rowSpan: rowSpan,
      displayColumn: column,
      displaySpan: columnSpan,
    }));
  }

  const free = [];
  for (let y = 0; y < rows; y++) {
    for (let x = 0; x < columnCount; x++) if (!(occupied[y] && occupied[y][x])) free.push({ row: y, column: x });
  }
  // A line of single-height controls with spare cells stretches them proportionally,
  // so the resting grid never shows holes. Lines crossed by a taller control keep their cells.
  if (options.fill === true) {
    for (let y = 0; y < rows; y++) {
      const line = placed.filter(entry => entry.row <= y && y < entry.row + entry.rowSpan);
      const used = line.reduce((sum, entry) => sum + entry.columnSpan, 0);
      if (!line.length || used >= columnCount || line.some(entry => entry.rowSpan > 1)) continue;
      const scale = columnCount / used;
      let cursor = 0;
      for (const entry of line.sort((left, right) => left.column - right.column)) {
        entry.displayColumn = cursor;
        entry.displaySpan = entry.columnSpan * scale;
        cursor += entry.displaySpan;
      }
    }
  }

  return { items: placed, rows, free: options.fill === true ? [] : free };
}
