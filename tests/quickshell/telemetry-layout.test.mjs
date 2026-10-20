import assert from "node:assert/strict";
import test from "node:test";
import { telemetryLayout } from "../../quickshell/logic/telemetry-layout.mjs";

test("four metrics use two columns; five and six fit two balanced rows", () => {
    assert.deepEqual(telemetryLayout(4).cells.map(({ x, y }) => [x, y]), [[0, 0], [88, 0], [0, 104], [88, 104]]);
    assert.deepEqual(telemetryLayout(5).cells.map(({ x, y }) => [x, y]), [[0, 0], [88, 0], [176, 0], [44, 104], [132, 104]]);
    assert.deepEqual(telemetryLayout(6).cells.map(({ x, y }) => [x, y]), [[0, 0], [88, 0], [176, 0], [0, 104], [88, 104], [176, 104]]);
    assert.deepEqual(telemetryLayout(7).cells.at(-1), { x: 88, y: 208, width: 80, height: 96 });
});

test("every row stays centered and within bounds for up to sixteen GPUs", () => {
    for (let count = 4; count <= 19; count++) {
        for (const width of [undefined, 256, 168, 80, 0]) {
            const layout = telemetryLayout(count, width);
            assert.equal(layout.cells.length, count);
            for (let first = 0; first < count; first += layout.columns) {
                const row = layout.cells.slice(first, first + layout.columns);
                assert.ok(Math.abs(row[0].x - (layout.width - row.at(-1).x - row.at(-1).width)) < 1e-8);
                for (const [index, cell] of row.entries()) {
                    assert.ok(cell.x >= -1e-8 && cell.x + cell.width <= layout.width + 1e-8);
                    assert.ok(cell.y + cell.height <= layout.height);
                    if (index) assert.ok(row[index - 1].x + row[index - 1].width <= cell.x + 1e-8);
                }
            }
        }
    }
});

test("rejects invalid dimensions", () => {
    for (const count of [0, 3, 4.5, NaN, Infinity]) assert.throws(() => telemetryLayout(count), TypeError);
    for (const width of [-1, NaN, Infinity]) assert.throws(() => telemetryLayout(4, width), TypeError);
});
