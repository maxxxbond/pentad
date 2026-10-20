import { readdirSync, readFileSync } from "node:fs";
import path from "node:path";

export const CORNER_LITERAL = /\b(radius|extent):\s*(\d+(?:\.\d+)?)\b(?!\s*[*\/])/g;
export const MIN_VALUE = 3;

function collectQml(dir, files = []) {
  for (const entry of readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      if (entry.name === "tests" || entry.name === "node_modules") continue;
      collectQml(full, files);
    } else if (entry.isFile() && entry.name.endsWith(".qml")) {
      files.push(full);
    }
  }
  return files;
}

export function scanCorners(repoRoot) {
  const quickshellDir = path.join(repoRoot, "quickshell");
  const counts = {};
  for (const file of collectQml(quickshellDir).sort()) {
    const relative = path.relative(repoRoot, file).split(path.sep).join("/");
    const lines = readFileSync(file, "utf8").split(/\r?\n/);
    for (const line of lines) {
      if (line.trim().startsWith("//")) continue;
      for (const match of line.matchAll(CORNER_LITERAL)) {
        const value = Number(match[2]);
        if (value <= MIN_VALUE) continue;
        const key = `${relative}:${match[2]}`;
        counts[key] = (counts[key] ?? 0) + 1;
      }
    }
  }
  return Object.fromEntries(Object.entries(counts).sort(([a], [b]) => (a < b ? -1 : a > b ? 1 : 0)));
}
