import assert from "node:assert/strict";
import test from "node:test";
import { resolveTheme } from "../../quickshell/logic/theme.mjs";

const base = { appearance: "dark", accent: "#869677", fontFamily: "Geist", reducedMotion: false };

test("maps saved classic accents while preserving custom accents", () => {
  for (const accent of ["#CBE32B", "#C5C7C2", "#4EEBA2", "#c5c7c2"]) {
    assert.equal(resolveTheme({ ...base, accent }).accent, "#869677");
    assert.equal(resolveTheme({ ...base, appearance: "light", accent }).accent, "#3E4A37");
  }
  assert.equal(resolveTheme({ ...base, accent: "#123456" }).accent, "#123456");
});

test("resolves semantic colors and reduced motion for both appearances", () => {
  const dark = resolveTheme(base);
  const light = resolveTheme({ ...base, appearance: "light", reducedMotion: true });
  assert.deepEqual([dark.surface, dark.text, dark.success], ["#111311", "#F2F4F1", "#5BD99F"]);
  assert.deepEqual([light.surface, light.text, light.success, light.reducedMotion], ["#FAFAFA", "#171717", "#216E3A", true]);
});

test("rejects values outside the validated theme config contract", () => {
  for (const config of [
    { ...base, appearance: "system" },
    { ...base, accent: "red" },
    { ...base, fontFamily: 'Foo; background: url("file:///secret")' },
    { ...base, reducedMotion: 0 },
  ]) assert.throws(() => resolveTheme(config), TypeError);
});

test("keeps active icons and calendar dates legible for light and dark custom accents", () => {
  for (const appearance of ["dark", "light"]) {
    const darkAccent = resolveTheme({ ...base, appearance, accent: "#000000" });
    const lightAccent = resolveTheme({ ...base, appearance, accent: "#FFFFFF" });
    assert.equal(darkAccent.onAccent, appearance === "dark" ? darkAccent.text : darkAccent.surface);
    assert.equal(lightAccent.onAccent, appearance === "dark" ? lightAccent.surface : lightAccent.text);
  }
  assert.equal(resolveTheme({ ...base, appearance: "light" }).onAccent, "#171717");
});
