import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync, readdirSync, writeFileSync, existsSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../../quickshell");
const baselinePath = fileURLToPath(new URL("./ui-contract-baseline.json", import.meta.url));

function* qmlFiles(dir) {
  for (const entry of readdirSync(dir, { withFileTypes: true })) {
    if (entry.name === "tests" || entry.name === "node_modules") continue;
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) yield* qmlFiles(full);
    else if (entry.name.endsWith(".qml")) yield full;
  }
}

const animationTypes = ["NumberAnimation", "ColorAnimation", "PropertyAnimation", "RotationAnimation", "SmoothedAnimation"];
const glyphSet = "›‹»«×✕✖✓✔✎✏▾▴▼▲▸▶◂◀●○⌄⌃♪";

function blockAfter(text, openIndex) {
  let depth = 0;
  for (let i = openIndex; i < text.length; i++) {
    if (text[i] === "{") depth++;
    else if (text[i] === "}" && --depth === 0) return text.slice(openIndex, i + 1);
  }
  return text.slice(openIndex);
}

export function scan() {
  const hits = {};
  const add = (key) => { hits[key] = (hits[key] || 0) + 1; };
  for (const file of qmlFiles(root)) {
    const rel = path.relative(root, file);
    const text = readFileSync(file, "utf8");
    const code = text.split("\n").map(line => (line.trim().startsWith("//") ? "" : line)).join("\n");

    for (const match of code.matchAll(/\bduration:\s*(\d+)/g)) add(`motion-literal:${rel}:${match[1]}`);
    for (const type of animationTypes) {
      for (const match of code.matchAll(new RegExp(`\\b${type}\\s*\\{`, "g"))) {
        const body = blockAfter(code, match.index + match[0].length - 1);
        if (!/\bduration\s*:/.test(body)) add(`motion-default:${rel}:${type}`);
      }
    }
    for (const match of code.matchAll(new RegExp(`"([${glyphSet}])"`, "g"))) add(`glyph-icon:${rel}:${match[1]}`);
    for (const match of code.matchAll(/\btext:\s*"([+−-])"/g)) add(`glyph-icon:${rel}:${match[1]}`);
    for (const match of code.matchAll(/\bSymbol\s*\{/g)) add(`font-icon:${rel}:Symbol`);
    for (const match of code.matchAll(/\bToolTip\.delay:\s*\d+/g)) add(`tooltip-delay-literal:${rel}`);
    if (rel !== path.join("components", "PentadChevron.qml") && code.includes("chevron-right-symbolic.svg")) {
      add(`chevron-source:${rel}:chevron-right-symbolic.svg`);
    }
  }
  return hits;
}

const hits = scan();

if (process.env.UI_CONTRACT_WRITE === "1" && !existsSync(baselinePath)) {
  writeFileSync(baselinePath, JSON.stringify(Object.fromEntries(Object.entries(hits).sort()), null, 2) + "\n");
}
const baseline = existsSync(baselinePath) ? JSON.parse(readFileSync(baselinePath, "utf8")) : {};

test("no new motion literal, default-duration animation, glyph icon, font icon, tooltip delay literal or stray chevron", () => {
  const added = Object.entries(hits)
    .filter(([key, count]) => count > (baseline[key] || 0))
    .map(([key, count]) => `${key} (found ${count}, allowed ${baseline[key] || 0})`);
  assert.deepEqual(added, [], "New contract violations. Use Motion tokens, SVG icons, Metrics.tooltipDelay and PentadChevron.");
});

test("baseline only shrinks: fixed violations are removed from it", () => {
  const stale = Object.entries(baseline)
    .filter(([key, count]) => (hits[key] || 0) < count)
    .map(([key]) => key);
  assert.deepEqual(stale, [], "Tighten tests/quickshell/ui-contract-baseline.json.");
});

test("shared tokens and the chevron component exist", () => {
  const motion = readFileSync(path.join(root, "theme/Motion.qml"), "utf8");
  for (const token of ["press", "state", "reveal"]) assert.match(motion, new RegExp(`readonly property int ${token}:`));
  const chevron = readFileSync(path.join(root, "components/PentadChevron.qml"), "utf8");
  assert.equal((chevron.match(/duration:\s*Motion\.reveal/g) || []).length, 2, "chevron rotation and opacity share Motion.reveal");
  assert.match(readFileSync(path.join(root, "components/qmldir"), "utf8"), /^PentadChevron 1\.0 PentadChevron\.qml$/m);
});
