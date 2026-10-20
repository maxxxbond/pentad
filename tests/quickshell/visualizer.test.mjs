import assert from "node:assert/strict";
import test from "node:test";
import { parseCavaFrame } from "../../quickshell/logic/visualizer.mjs";

test("parses a complete CAVA ASCII frame and clamps normalized bands", () => {
  const values = Array.from({ length: 32 }, (_, index) => index * 40);
  const frame = parseCavaFrame(`${values.join(";")};`);
  assert.equal(frame.length, 32);
  assert.equal(frame[0], 0);
  assert.equal(frame[5], 0.2);
  assert.equal(frame[25], 1);
  assert.equal(frame[31], 1);
});

test("rejects partial, malformed and non-string frames", () => {
  assert.equal(parseCavaFrame("1;2;3;"), null);
  assert.equal(parseCavaFrame(`${Array(31).fill("1").join(";")};`), null);
  assert.equal(parseCavaFrame(`${Array(31).fill("1").join(";")};oops;`), null);
  assert.equal(parseCavaFrame(`${Array(31).fill("1").join(";")};;1;`), null);
  assert.equal(parseCavaFrame(null), null);
});
