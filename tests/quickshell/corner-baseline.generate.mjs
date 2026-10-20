import { mkdirSync, writeFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { scanCorners } from "./corner-scan.mjs";

const here = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.resolve(here, "../..");
const output = path.resolve(process.argv[2] ?? path.join(here, "corner-baseline.json"));

const counts = scanCorners(repoRoot);
mkdirSync(path.dirname(output), { recursive: true });
writeFileSync(output, `${JSON.stringify(counts, null, 2)}\n`);
console.log(`wrote ${Object.keys(counts).length} keys to ${output}`);
