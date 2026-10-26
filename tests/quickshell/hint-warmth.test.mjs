import test from "node:test";
import assert from "node:assert/strict";
import { hintHidden, hintShown, hintsWarm, resetHintWarmth, warmWindow } from "../../quickshell/logic/hint-warmth.mjs";

test("hints are cold until one shows, stay warm briefly after the last hides, then cool", () => {
  resetHintWarmth();
  assert.equal(hintsWarm(1000), false);
  hintShown();
  hintShown();
  hintHidden(1000);
  assert.equal(hintsWarm(5000), true, "one hint is still on screen");
  hintHidden(2000);
  assert.equal(hintsWarm(2000 + warmWindow - 1), true);
  assert.equal(hintsWarm(2000 + warmWindow), false);
});

test("an extra hide never drives the count below zero", () => {
  resetHintWarmth();
  hintHidden(100);
  hintShown();
  assert.equal(hintsWarm(1e9), true);
});
