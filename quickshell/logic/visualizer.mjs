export function parseCavaFrame(line, minimumBands = 32) {
  if (typeof line !== "string" || !Number.isInteger(minimumBands) || minimumBands < 1)
    return null;
  const parts = line.trim().split(";");
  if (parts[parts.length - 1] === "") parts.pop();
  if (parts.length < minimumBands || parts.some((part) => part.trim() === "")) return null;
  const raw = parts.map(Number);
  if (!raw.every(Number.isFinite)) return null;
  return raw.map((value) => Math.max(0, Math.min(1, value / 1000)));
}
