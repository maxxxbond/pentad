const legacyAccents = new Set(["#CBE32B", "#C5C7C2", "#4EEBA2"]);
const colorPattern = /^#[\da-f]{6}$/i;

export function isHexColor(value) {
  return typeof value === "string" && colorPattern.test(value);
}
const forbiddenFontCharacters = /[\x00-\x1f\x7f;{}<>"'\\():]/;

function luminance(hex) {
  const channels = [1, 3, 5].map(index => {
    const value = parseInt(hex.slice(index, index + 2), 16) / 255;
    return value <= 0.04045 ? value / 12.92 : ((value + 0.055) / 1.055) ** 2.4;
  });
  return channels[0] * 0.2126 + channels[1] * 0.7152 + channels[2] * 0.0722;
}

function contrast(first, second) {
  return (Math.max(first, second) + 0.05) / (Math.min(first, second) + 0.05);
}

export function resolveTheme(config) {
  if (!config || typeof config !== "object" || Array.isArray(config)) {
    throw new TypeError("Theme config must be an object");
  }
  const { appearance, accent, fontFamily, reducedMotion } = config;
  if (appearance !== "dark" && appearance !== "light") {
    throw new TypeError("Invalid theme appearance");
  }
  if (typeof accent !== "string" || !colorPattern.test(accent)) {
    throw new TypeError("Invalid theme accent");
  }
  if (typeof fontFamily !== "string" || !fontFamily.trim() || fontFamily.length > 80
      || forbiddenFontCharacters.test(fontFamily)) {
    throw new TypeError("Invalid theme font family");
  }
  if (typeof reducedMotion !== "boolean") {
    throw new TypeError("Invalid reducedMotion setting");
  }

  const dark = appearance === "dark";
  const tokens = {
    surface: dark ? "#111311" : "#FAFAFA",
    surfaceRaised: dark ? "#191D18" : "#EFEFEF",
    surfaceOverlay: dark ? "#242A22" : "#E5E5E5",
    text: dark ? "#F2F4F1" : "#171717",
    textMuted: dark ? "#8E9689" : "#595959",
    outline: dark ? "#2E352B" : "#C9C9C9",
    accent: legacyAccents.has(accent.toUpperCase())
      ? dark ? "#869677" : "#3E4A37"
      : accent,
    success: dark ? "#5BD99F" : "#216E3A",
    warning: dark ? "#F6B865" : "#855500",
    error: dark ? "#FF786B" : "#A5231B",
    fontFamily,
    reducedMotion,
  };
  const accentLuminance = luminance(tokens.accent);
  tokens.onAccent = contrast(accentLuminance, luminance(tokens.text))
    >= contrast(accentLuminance, luminance(tokens.surface)) ? tokens.text : tokens.surface;
  return tokens;
}
