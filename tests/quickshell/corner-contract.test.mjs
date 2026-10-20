import assert from "node:assert/strict";
import { existsSync, readFileSync } from "node:fs";
import path from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";
import { scanCorners } from "./corner-scan.mjs";

const here = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.resolve(here, "../..");
const baselinePath = path.join(here, "corner-baseline.json");
const metricsPath = path.join(repoRoot, "quickshell/theme/Metrics.qml");

test("corner literals do not grow beyond the baseline", () => {
  assert.ok(
    existsSync(baselinePath),
    `Missing ${path.relative(repoRoot, baselinePath)}. Generate it once with: node tests/quickshell/corner-baseline.generate.mjs`,
  );
  const baseline = JSON.parse(readFileSync(baselinePath, "utf8"));
  const current = scanCorners(repoRoot);

  const added = [];
  for (const [key, count] of Object.entries(current)) {
    const allowed = baseline[key] ?? 0;
    if (count > allowed) added.push(`${key} (found ${count}, baseline ${allowed})`);
  }
  assert.deepEqual(added, [], `New corner literals; use Metrics tokens or R3 derived values:\n  ${added.join("\n  ")}`);

  const stale = [];
  for (const [key, allowed] of Object.entries(baseline)) {
    const count = current[key] ?? 0;
    if (allowed > count) stale.push(`${key} (found ${count}, baseline ${allowed})`);
  }
  assert.deepEqual(stale, [], `Baseline is stale; tighten corner-baseline.json (regenerate):\n  ${stale.join("\n  ")}`);
});

test("Metrics declares the block and row corner tokens", () => {
  const source = readFileSync(metricsPath, "utf8");
  assert.match(source, /readonly property int radiusBlock\b/);
  assert.match(source, /readonly property int radiusRow\b/);
});
