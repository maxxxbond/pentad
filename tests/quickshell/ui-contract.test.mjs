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
    // The token ratchet, counted per file: spacing, type size and radius come from Metrics, and
    // feature views use the Pentad* kit instead of bare controls.
    const count = (rule, pattern) => {
      const found = (code.match(pattern) || []).length;
      if (found) hits[`${rule}:${rel}`] = found;
    };
    count("spacing-literal", /\b(?:spacing|[a-zA-Z]*[Mm]argins?|[a-zA-Z]*[Pp]adding):\s*[1-9]\d*\s*$/gm);
    count("font-literal", /\bpixelSize:\s*\d+\s*$/gm);
    count("radius-literal", /\b[a-zA-Z]*[Rr]adius:\s*[1-9]\d*\s*$/gm);
    if (!rel.startsWith("components" + path.sep)) {
      count("raw-control", /^\s*(?:Text|Button|Slider|ComboBox|TextField|Switch)\s*\{/gm);
    }
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
  assert.deepEqual(added, [], "New contract violations. Use Motion tokens, SVG icons, Metrics.tooltipDelay, PentadChevron, the Metrics spacing, text and radius tokens, and the Pentad* kit controls.");
});
