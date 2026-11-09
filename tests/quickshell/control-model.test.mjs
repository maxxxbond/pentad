import test from "node:test";
import assert from "node:assert/strict";
import {
  addControl,
  builtinDefinitions,
  controlDefinition,
  defaultQuickMenu,
  defaultSpan,
  dropIndex,
  layoutMenu,
  menuColumns,
  minimumTemplateColumns,
  moveItem,
  rescaleMenu,
  resizePlacement,
  setItemVisible,
  supportsTemplate,
  templateForSpan,
  levelControlIds,
  withLevelControls,
  validateMenuLayout,
} from "../../quickshell/logic/control-model.mjs";

const item = (overrides = {}) => ({
  instanceId: "network-card",
  definitionId: "network",
  template: "tile",
  columnSpan: 2,
  rowSpan: 2,
  visible: true,
  ...overrides,
});

test("definitions are serializable and localized overrides do not mutate the registry", () => {
  const original = JSON.stringify(builtinDefinitions.bluetooth);
  const localized = controlDefinition("bluetooth", { label: "Bluetooth lokal", icon: "wireless" });
  assert.equal(localized.label, "Bluetooth lokal");
  assert.equal(localized.icon, "wireless");
  assert.equal(JSON.stringify(builtinDefinitions.bluetooth), original);
  assert.deepEqual(JSON.parse(JSON.stringify(localized)), localized);
  assert.equal(controlDefinition("unknown"), null);
});

test("template compatibility is explicit", () => {
  assert.equal(supportsTemplate(builtinDefinitions["audio-output"], "range-vertical"), true);
  assert.equal(supportsTemplate(builtinDefinitions.dnd, "range-horizontal"), false);
  assert.equal(supportsTemplate(builtinDefinitions.dnd, "made-up"), false);
});

test("default spans match template footprints and brightness uses normalized values", () => {
  assert.deepEqual(defaultSpan("icon"), { columnSpan: 1, rowSpan: 1 });
  assert.deepEqual(defaultSpan("compact"), { columnSpan: 2, rowSpan: 1 });
  assert.deepEqual(defaultSpan("tile"), { columnSpan: 2, rowSpan: 2 });
  assert.deepEqual(defaultSpan("row"), { columnSpan: 4, rowSpan: 1 });
  assert.deepEqual(defaultSpan("range-horizontal"), { columnSpan: 4, rowSpan: 1 });
  assert.deepEqual(defaultSpan("range-vertical"), { columnSpan: 1, rowSpan: 3 });
  assert.equal(defaultSpan("toString"), null);
  assert.deepEqual(builtinDefinitions.brightness.capabilities.range,
    { from: 0, to: 1, step: 0.01, unit: "%", scale: 100, action: "level" });
});

test("layout validation rejects incompatible templates, invalid spans, duplicate and missing IDs, and versions", () => {
  const result = validateMenuLayout({
    version: 2,
    items: [
      item({ template: "range-horizontal", columnSpan: Infinity }),
      item({ instanceId: "network-card", definitionId: "missing", rowSpan: 0 }),
    ],
  });
  assert.equal(result.ok, false);
  assert.match(result.errors.join("\n"), /version must be 1/);
  assert.match(result.errors.join("\n"), /template is incompatible/);
  assert.match(result.errors.join("\n"), /columnSpan must be an integer/);
  assert.match(result.errors.join("\n"), /instanceId is duplicated/);
  assert.match(result.errors.join("\n"), /definitionId is unknown/);
  assert.match(result.errors.join("\n"), /rowSpan must be an integer/);
});

test("validates the default menu and returns a detached value without mutating its input", () => {
  const source = JSON.parse(JSON.stringify(defaultQuickMenu));
  const before = JSON.stringify(source);
  const result = validateMenuLayout(source);
  assert.equal(result.ok, true, result.errors.join(", "));
  assert.deepEqual(source, JSON.parse(before));
  assert.notEqual(result.value, source);
  assert.notEqual(result.value.items, source.items);
});

const lineFill = (layout, columns) => {
  const filled = Array.from({ length: layout.rows }, () => 0);
  for (const entry of layout.items) filled[entry.row] += entry.displaySpan;
  return filled.map(value => Math.round(value * 1000) / 1000);
};

test("default menu fills every line of the six-column grid without stretching", () => {
  assert.equal(defaultQuickMenu.columns, 6);
  const wide = layoutMenu(defaultQuickMenu.items, 6);
  assert.equal(wide.rows, 6);
  assert.deepEqual(wide.free, []);
  assert.deepEqual(lineFill(wide, 6), [6, 6, 6, 6, 6, 6]);
  assert.deepEqual(wide.items.slice(0, 4).map(entry => [entry.definitionId, entry.template, entry.columnSpan]),
    [["network", "row", 3], ["bluetooth", "row", 3], ["vpn", "row", 3], ["energy", "row", 3]]);
  assert.ok(wide.items.slice(4, 10).every(entry => entry.template === "icon" && entry.columnSpan === 1 && entry.row === 2));
  assert.deepEqual(wide.items.slice(10).map(entry => [entry.definitionId, entry.template, entry.columnSpan, entry.row]),
    [["brightness", "range-horizontal", 6, 3], ["audio-output", "range-horizontal", 6, 4],
      ["audio-input", "range-horizontal", 6, 5]]);
  assert.equal(wide.items.some(entry => entry.definitionId === "tailscale"), false);
});

test("at rest a short line stretches proportionally, so no grid width shows a hole", () => {
  for (const columns of [3, 4, 6]) {
    const menu = rescaleMenu(defaultQuickMenu, columns);
    const resting = layoutMenu(menu.items, columns, { fill: true });
    assert.deepEqual(lineFill(resting, columns), lineFill(resting, columns).map(() => columns), `columns=${columns}`);
    assert.deepEqual(resting.free, []);
  }
  const editing = layoutMenu(rescaleMenu(defaultQuickMenu, 4).items, 4);
  assert.deepEqual(editing.free, [{ row: 3, column: 2 }, { row: 3, column: 3 }]);
  const narrow = layoutMenu(defaultQuickMenu.items, 2);
  assert.ok(narrow.items.every(entry => entry.columnSpan <= 2));
});

test("a control's size decides its presentation, like a resizable widget", () => {
  const wifi = builtinDefinitions.network;
  const energy = builtinDefinitions.energy;
  assert.equal(templateForSpan(wifi, 1, 1, 6), "icon");
  assert.equal(templateForSpan(wifi, 2, 1, 6), "icon");
  assert.equal(templateForSpan(wifi, 3, 1, 6), "row");
  assert.equal(templateForSpan(wifi, 3, 2, 6), "tile");
  assert.equal(templateForSpan(wifi, 2, 1, 4), "row");
  assert.equal(templateForSpan(wifi, 2, 1, 3), "row");
  assert.equal(templateForSpan(energy, 1, 1, 6), "row");
  const shrunk = resizePlacement(defaultQuickMenu.items[3], energy, 1, 1, 6);
  assert.deepEqual([shrunk.template, shrunk.columnSpan], ["row", 3]);
  const grown = resizePlacement(defaultQuickMenu.items[4], builtinDefinitions.airplane, 3, 9, 6);
  assert.deepEqual([grown.template, grown.columnSpan, grown.rowSpan], ["tile", 3, 3]);
  assert.equal(validateMenuLayout({ version: 1, columns: 6, items: [grown] }).ok, true);
});

test("a narrow control taller than a line stands up as a readable vertical button", () => {
  const wifi = builtinDefinitions.network;
  const energy = builtinDefinitions.energy;
  assert.equal(templateForSpan(wifi, 1, 2, 6), "vertical");
  assert.equal(templateForSpan(wifi, 2, 3, 6), "vertical");
  assert.equal(templateForSpan(wifi, 3, 2, 6), "tile");
  // A third of the line keeps the label legible: two cells on six columns, one on four or three.
  const tall = resizePlacement(defaultQuickMenu.items[4], builtinDefinitions.airplane, 1, 2, 6);
  assert.deepEqual([tall.template, tall.columnSpan, tall.rowSpan], ["vertical", 2, 2]);
  assert.deepEqual(defaultSpan("vertical"), { columnSpan: 1, rowSpan: 2 });
  assert.equal(minimumTemplateColumns("vertical", 4), 1);
  // A control without a round form (energy) can still stand up instead of being forced wide.
  const standing = resizePlacement(defaultQuickMenu.items[3], energy, 1, 2, 6);
  assert.deepEqual([standing.template, standing.columnSpan, standing.rowSpan], ["vertical", 2, 2]);
  assert.equal(validateMenuLayout({ version: 1, columns: 6, items: [tall, Object.assign({}, standing,
    { instanceId: "energy-2" })] }).ok, true);
  const tooNarrow = Object.assign({}, tall, { columnSpan: 1 });
  assert.equal(validateMenuLayout({ version: 1, columns: 6, items: [tooNarrow] }).ok, false);
  const flat = Object.assign({}, tall, { rowSpan: 1 });
  assert.equal(validateMenuLayout({ version: 1, columns: 6, items: [flat] }).ok, false);
  // Levels keep their own upright slider.
  for (const id of levelControlIds) assert.equal(builtinDefinitions[id].templates.includes("vertical"), false, id);
  const four = rescaleMenu({ version: 1, columns: 6, items: [tall] }, 4);
  assert.deepEqual([four.items[0].template, four.items[0].columnSpan, four.items[0].rowSpan], ["vertical", 1, 2]);
});

test("a level slider lies flat on one line and stands up when taller", () => {
  for (const id of levelControlIds) {
    const control = builtinDefinitions[id];
    const level = defaultQuickMenu.items.find(entry => entry.definitionId === id);
    const tall = resizePlacement(level, control, 1, 3, 6);
    assert.deepEqual([tall.template, tall.columnSpan, tall.rowSpan], ["range-vertical", 1, 3], id);
    const short = resizePlacement(tall, control, 1, 2, 6);
    assert.deepEqual([short.template, short.columnSpan, short.rowSpan], ["range-vertical", 1, 2], id);
    // Back to one line: a flat slider needs at least half the line for its label and value.
    const flat = resizePlacement(short, control, 1, 1, 6);
    assert.deepEqual([flat.template, flat.columnSpan, flat.rowSpan], ["range-horizontal", 3, 1], id);
    assert.equal(validateMenuLayout({ version: 1, columns: 6, items: [tall, short, flat].map((entry, index) =>
      Object.assign({}, entry, { instanceId: id + index })) }).ok, true, id);
  }
  const vertical = rescaleMenu({ version: 1, columns: 6, items: [
    item({ instanceId: "volume", definitionId: "audio-output", template: "range-vertical", columnSpan: 1, rowSpan: 3 }),
  ] }, 3);
  assert.deepEqual([vertical.items[0].template, vertical.items[0].columnSpan], ["range-vertical", 1]);
});

test("layouts saved before the sliders joined the grid get them, hidden ones stay hidden", () => {
  const legacy = { version: 1, columns: 4, items: [item({ template: "row", columnSpan: 2, rowSpan: 1 })] };
  const upgraded = withLevelControls(legacy);
  assert.deepEqual(upgraded.items.slice(1).map(entry => [entry.definitionId, entry.template, entry.columnSpan]),
    [["brightness", "range-horizontal", 4], ["audio-output", "range-horizontal", 4], ["audio-input", "range-horizontal", 4]]);
  assert.equal(validateMenuLayout(upgraded).ok, true, validateMenuLayout(upgraded).errors.join(", "));
  const hidden = { version: 1, columns: 6, items: setItemVisible(defaultQuickMenu.items, "audio-input", false) };
  assert.equal(withLevelControls(hidden), hidden);
});

test("overnight mode is offered by the editor but hidden on the default grid", () => {
  const overnight = defaultQuickMenu.items.find(entry => entry.definitionId === "overnight");
  assert.deepEqual(overnight, { instanceId: "overnight", definitionId: "overnight", template: "icon",
    columnSpan: 1, rowSpan: 1, visible: false });
  assert.equal(layoutMenu(defaultQuickMenu.items, 6).items.some(entry => entry.definitionId === "overnight"), false);
  assert.equal(supportsTemplate(builtinDefinitions.overnight, "icon"), true);
  assert.equal(builtinDefinitions.overnight.capabilities.toggle, "toggle");
  const shown = addControl(defaultQuickMenu.items, "overnight", 6);
  assert.equal(shown.at(-1).instanceId, "overnight");
  assert.equal(shown.at(-1).visible, true);
  assert.equal(shown.length, defaultQuickMenu.items.length);
  assert.equal(validateMenuLayout({ version: 1, columns: 6, items: shown }).ok, true);
});

test("changing the column count keeps each control's kind and round-trips", () => {
  for (const columns of [3, 4]) {
    const there = rescaleMenu(defaultQuickMenu, columns);
    assert.equal(there.columns, columns);
    assert.equal(validateMenuLayout(there).ok, true, validateMenuLayout(there).errors.join(", "));
    assert.ok(there.items.slice(0, 4).every(entry => entry.template === "row"));
    assert.ok(there.items.slice(4, 11).every(entry => entry.template === "icon" && entry.columnSpan === 1));
    assert.ok(there.items.slice(11).every(entry => entry.template === "range-horizontal" && entry.columnSpan === columns));
    assert.deepEqual(rescaleMenu(there, 6), JSON.parse(JSON.stringify(defaultQuickMenu)));
  }
  const full = rescaleMenu({ version: 1, items: [item({ template: "row", columnSpan: 4, rowSpan: 1 })] }, 6);
  assert.equal(full.items[0].columnSpan, 6);
});

test("validator accepts a column choice and checks spans against it", () => {
  assert.equal(menuColumns({ version: 1, items: [] }), 4);
  assert.equal(menuColumns({ version: 1, columns: 6, items: [] }), 6);
  const bad = validateMenuLayout({ version: 1, columns: 5, items: [] });
  assert.equal(bad.ok, false);
  assert.match(bad.errors.join("\n"), /columns must be one of 3, 4, 6/);
  const narrowRow = validateMenuLayout({ version: 1, columns: 6, items: [item({ template: "row", columnSpan: 2, rowSpan: 1 })] });
  assert.match(narrowRow.errors.join("\n"), /columnSpan is too small for row/);
  const wide = validateMenuLayout({ version: 1, columns: 6, items: [item({ template: "row", columnSpan: 6, rowSpan: 1 })] });
  assert.equal(wide.ok, true);
  assert.equal(wide.value.columns, 6);
});

test("editor moves, hides and adds controls without touching other placements", () => {
  const items = defaultQuickMenu.items;
  const placed = layoutMenu(items, 6).items;
  const later = dropIndex(items, placed, 2, 4, 6, "airplane");
  assert.deepEqual(moveItem(items, "airplane", later).slice(4, 10).map(entry => entry.instanceId),
    ["dnd", "night", "inhibit", "appearance", "airplane", "screenshot"]);
  const earlier = dropIndex(items, placed, 0, 0, 6, "screenshot");
  assert.equal(moveItem(items, "screenshot", earlier)[0].instanceId, "screenshot");
  assert.equal(dropIndex(items, placed, 9, 0, 6, "network"), items.length - 1);

  const hidden = setItemVisible(items, "dnd", false);
  assert.equal(hidden.find(entry => entry.instanceId === "dnd").visible, false);
  assert.equal(layoutMenu(hidden, 6).items.some(entry => entry.instanceId === "dnd"), false);
  const restored = addControl(hidden, "dnd", 6);
  assert.equal(restored.at(-1).instanceId, "dnd");
  assert.equal(restored.at(-1).visible, true);
  assert.equal(restored.length, items.length);
  const fresh = addControl(items.filter(entry => entry.instanceId !== "energy"), "energy", 6);
  assert.deepEqual([fresh.at(-1).template, fresh.at(-1).columnSpan], ["row", 3]);
  assert.equal(validateMenuLayout({ version: 1, columns: 6, items: fresh }).ok, true);
});

test("template changes preserve stable instance identity", () => {
  const original = { version: 1, items: [item({ definitionId: "audio-output", template: "range-horizontal", rowSpan: 3 })] };
  const changed = structuredClone(original);
  changed.items[0].template = "range-vertical";
  const first = validateMenuLayout(original);
  const second = validateMenuLayout(changed);
  assert.equal(first.ok, true);
  assert.equal(second.ok, true);
  assert.equal(second.value.items[0].instanceId, first.value.items[0].instanceId);
  assert.equal(second.value.items[0].template, "range-vertical");
});

test("first-fit layout is responsive, ordered, clamped, and non-overlapping", () => {
  const source = [
    item({ instanceId: "a", columnSpan: 3, rowSpan: 2 }),
    item({ instanceId: "b", columnSpan: 2, rowSpan: 1 }),
    item({ instanceId: "hidden", visible: false }),
    item({ instanceId: "c", columnSpan: 1, rowSpan: 3 }),
  ];
  const narrow = layoutMenu(source, 2);
  assert.deepEqual(narrow.items.map(entry => entry.instanceId), ["a", "b", "c"]);
  assert.equal(narrow.items[0].columnSpan, 2);
  assert.deepEqual(narrow.items.map(({ column, row }) => [column, row]), [[0, 0], [0, 2], [0, 3]]);
  assert.equal(narrow.rows, 6);

  const cells = new Set();
  for (const entry of narrow.items) {
    for (let row = entry.row; row < entry.row + entry.rowSpan; row++) {
      for (let column = entry.column; column < entry.column + entry.columnSpan; column++) {
        const key = `${row}:${column}`;
        assert.equal(cells.has(key), false, `overlap at ${key}`);
        cells.add(key);
      }
    }
  }
  assert.equal(layoutMenu(source, 4).items[0].columnSpan, 3);
});

test("validator rejects non-schema properties instead of carrying executable data", () => {
  const result = validateMenuLayout({ version: 1, script: "run()", items: [item({ onClick: "run()" })] });
  assert.equal(result.ok, false);
  assert.match(result.errors.join("\n"), /script is not allowed/);
  assert.match(result.errors.join("\n"), /onClick is not allowed/);
});

test("inherited definition names are unknown", () => {
  assert.equal(controlDefinition("toString"), null);
  const result = validateMenuLayout({ version: 1, items: [item({ definitionId: "constructor" })] });
  assert.equal(result.ok, false);
  assert.match(result.errors.join("\n"), /definitionId is unknown/);
});

test("validator bounds menu size and enforces template minimum heights", () => {
  const oversized = Array.from({ length: 65 }, (_, index) => item({ instanceId: `item-${index}` }));
  const tooMany = validateMenuLayout({ version: 1, items: oversized });
  assert.equal(tooMany.ok, false);
  assert.match(tooMany.errors.join("\n"), /at most 64 items/);

  const badSpans = validateMenuLayout({ version: 1, items: [
    item({ columnSpan: 5 }),
    item({ instanceId: "bad-row", template: "row", rowSpan: 9 }),
    item({ instanceId: "short-tile", rowSpan: 1, columnSpan: 1 }),
    item({ instanceId: "short-range", definitionId: "audio-output", template: "range-vertical", columnSpan: 1, rowSpan: 1 }),
  ] });
  assert.equal(badSpans.ok, false);
  assert.match(badSpans.errors.join("\n"), /columnSpan must be an integer from 1 to 4/);
  assert.match(badSpans.errors.join("\n"), /rowSpan must be an integer from 1 to 8/);
  assert.match(badSpans.errors.join("\n"), /rowSpan is too small for tile/);
  assert.match(badSpans.errors.join("\n"), /columnSpan is too small for tile/);
  assert.match(badSpans.errors.join("\n"), /rowSpan is too small for range-vertical/);
});

test("record and timer lifecycle metadata only expose supported transitions", () => {
  assert.deepEqual(builtinDefinitions.record.lifecycle, {
    states: ["idle", "recording"],
    commands: { idle: ["record.start"], recording: ["record.stop"] },
  });
  assert.equal(builtinDefinitions.record.lifecycle.commands.recording.includes("pause"), false);
  assert.deepEqual(builtinDefinitions.timer.lifecycle.states, ["idle", "running"]);
  assert.deepEqual(builtinDefinitions.telemetry.capabilities, { details: false });
});

test("layoutMenu caps untrusted columns and spans to menu bounds", () => {
  const placements = layoutMenu([item({ columnSpan: 1e9, rowSpan: 1e9 })], 1e9);
  assert.equal(placements.items[0].columnSpan, 6);
  assert.equal(placements.items[0].rowSpan, 8);
  assert.equal(placements.items[0].column, 0);
  assert.equal(placements.rows, 8);
});
