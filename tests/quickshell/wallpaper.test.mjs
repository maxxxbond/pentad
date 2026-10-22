import assert from "node:assert/strict";
import test from "node:test";
import {
  collapseHome, displayName, expandHome, fileUrlToPath, isImagePath, parseWallpaper, pickRandom, stepWallpaper,
  wallpaperDefaults, wallpaperFor, withWallpaper,
} from "../../quickshell/logic/wallpaper.mjs";
import { accentCandidates, contrastRatio, recolorStops, stopsArgument } from "../../quickshell/logic/wallpaper-palette.mjs";
import { parseDocument } from "../../quickshell/logic/config.mjs";

test("an empty wallpaper document resolves to defaults", () => {
  const value = parseWallpaper({});
  assert.deepEqual(value, { ...wallpaperDefaults, outputs: {} });
  assert.equal(parseDocument("wallpaper", "{}").ok, true);
});

test("rejects unsafe or malformed wallpaper fields", () => {
  for (const input of [
    { schemaVersion: 2 },
    { path: "relative/image.jpg" },
    { path: "/tmp/a\nb.jpg" },
    { directory: "" },
    { fill: "tile" },
    { transition: "spin" },
    { accentFromWallpaper: "yes" },
    { tint: "sepia" },
    { outputs: [] },
    { outputs: { "DP 1": "/a.jpg" } },
    { outputs: { "DP-1": "" } },
  ]) assert.throws(() => parseWallpaper(input), Error, JSON.stringify(input));
  assert.equal(parseDocument("wallpaper", JSON.stringify({ fill: "tile" })).ok, false);
});

test("per-screen overrides win until the screen takes the shared image", () => {
  const doc = parseWallpaper({ path: "~/a.jpg", outputs: { "DP-1": "/b.jpg" } });
  assert.equal(wallpaperFor(doc, "DP-1"), "/b.jpg");
  assert.equal(wallpaperFor(doc, "HDMI-A-1"), "~/a.jpg");
  assert.deepEqual(withWallpaper(doc, "/c.jpg", "").outputs, { "DP-1": "/b.jpg" });
  assert.equal(withWallpaper(doc, "/c.jpg", "").path, "/c.jpg");
  const single = withWallpaper(doc, "/c.jpg", "HDMI-A-1");
  assert.deepEqual(single.outputs, { "DP-1": "/b.jpg", "HDMI-A-1": "/c.jpg" });
  assert.equal(single.path, "~/a.jpg");
  // Picking the shared image for a screen drops its override instead of duplicating it.
  assert.deepEqual(withWallpaper(doc, "~/a.jpg", "DP-1").outputs, {});
});

test("home paths round-trip and file urls decode", () => {
  assert.equal(expandHome("~/Pictures/x.png", "/home/u/"), "/home/u/Pictures/x.png");
  assert.equal(expandHome("/srv/x.png", "/home/u"), "/srv/x.png");
  assert.equal(collapseHome("/home/u/Pictures/x.png", "/home/u"), "~/Pictures/x.png");
  assert.equal(collapseHome("/home/user2/x.png", "/home/u"), "/home/user2/x.png");
  assert.equal(fileUrlToPath("file:///home/u/My%20Pics/a.jpg"), "/home/u/My Pics/a.jpg");
  assert.equal(displayName("/w/macos-monterey_dark.jpg"), "macos monterey dark");
  assert.equal(isImagePath("/w/a.JPG"), true);
  assert.equal(isImagePath("/w/a.mp4"), false);
});

test("random and step never stall on the current image", () => {
  const list = ["/a.jpg", "/b.jpg", "/c.jpg", "/notes.txt"];
  assert.equal(pickRandom(list, "/a.jpg", () => 0), "/b.jpg");
  assert.equal(pickRandom(list, "/a.jpg", () => 0.999), "/c.jpg");
  assert.equal(pickRandom(["/a.jpg"], "/a.jpg", () => 0.5), "/a.jpg");
  assert.equal(pickRandom([], "", () => 0.5), "");
  assert.equal(stepWallpaper(list, "/c.jpg", 1), "/a.jpg");
  assert.equal(stepWallpaper(list, "/a.jpg", -1), "/c.jpg");
  assert.equal(stepWallpaper(list, "/missing.jpg", 1), "/a.jpg");
});

function image(colors) {
  // colors: [[rgb, pixelCount], ...] -> RGBA bytes
  const bytes = [];
  for (const [[r, g, b], count] of colors)
    for (let i = 0; i < count; i++) bytes.push(r, g, b, 255);
  return Uint8ClampedArray.from(bytes);
}

test("neutral wallpapers yield no accent candidates", () => {
  assert.deepEqual(accentCandidates(image([[[20, 20, 20], 500], [[200, 200, 200], 500], [[120, 118, 121], 400]])), []);
  assert.deepEqual(accentCandidates([]), []);
});

test("candidates follow the dominant hues and stay readable on the surface", () => {
  const pixels = image([[[30, 30, 30], 600], [[40, 120, 200], 300], [[220, 120, 40], 120], [[45, 125, 205], 50]]);
  for (const appearance of ["dark", "light"]) {
    const candidates = accentCandidates(pixels, { appearance });
    assert.ok(candidates.length >= 2, appearance);
    const surface = appearance === "dark" ? "#111311" : "#FAFAFA";
    for (const { hex } of candidates) assert.ok(contrastRatio(hex, surface) >= 3, `${appearance} ${hex}`);
    const [first, second] = candidates.map(({ hex }) => [1, 3, 5].map(i => parseInt(hex.slice(i, i + 2), 16)));
    assert.ok(first[2] > first[0], `blue leads: ${candidates[0].hex}`);
    assert.ok(second[0] > second[2], `orange second: ${candidates[1].hex}`);
    assert.ok(candidates[0].share > candidates[1].share);
  }
});

test("close hues merge into one candidate", () => {
  const pixels = image([[[200, 40, 40], 300], [[205, 60, 40], 300], [[20, 20, 20], 100]]);
  assert.equal(accentCandidates(pixels).length, 1);
});

test("recolor stops reproduce Moldavite for the default theme", () => {
  const stops = recolorStops({ appearance: "dark", accent: "#869677" });
  assert.deepEqual(stops.map(([position]) => position), [0, 0.2, 0.5, 0.75, 1]);
  assert.deepEqual([stops[0][1], stops[1][1], stops[3][1]], ["#111311", "#191D18", "#869677"]);
  // The computed midtone and highlight stay within a few steps of the hand-picked map.
  const near = (hex, target) => [1, 3, 5].every(i => Math.abs(parseInt(hex.slice(i, i + 2), 16) - parseInt(target.slice(i, i + 2), 16)) <= 12);
  assert.ok(near(stops[2][1], "#3E4B36"), stops[2][1]);
  assert.ok(near(stops[4][1], "#EBF0E6"), stops[4][1]);
  const light = recolorStops({ appearance: "light", accent: "#3E4A37" });
  assert.equal(light[4][1], "#FAFAFA");
  assert.match(stopsArgument(stops), /^0:#111311,0\.2:#191D18,0\.5:#[0-9A-F]{6},0\.75:#869677,1:#[0-9A-F]{6}$/);
});
