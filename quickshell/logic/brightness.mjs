export function clampBrightness(value, minimum = 0.01) {
    if (!Number.isFinite(value)) return null;
    return Math.max(minimum, Math.min(1, value));
}

export function brightnessIntent(current, desired, step = 0.05) {
    if (![current, desired, step].every(Number.isFinite) || step <= 0) return null;
    const bounded = clampBrightness(desired);
    const rounded = Math.round((bounded - current) / step);
    const steps = rounded === 0 ? 0 : rounded;
    return { steps, target: clampBrightness(current + steps * step) };
}

export function isInternalOutput(outputId) {
    return /^(eDP|LVDS|DSI)-\d+$/.test(String(outputId));
}

export function parseBacklightList(text) {
    const devices = [];
    for (const line of String(text).split(/\r?\n/)) {
        const match = /^([^,]+),backlight,(\d+),(\d+)%,(\d+)\s*$/.exec(line.trim());
        if (!match || Number(match[3]) > 100 || Number(match[4]) <= 0) continue;
        devices.push({ id: match[1], value: Number(match[3]) / 100 });
    }
    return devices;
}

export function parseBacklightBrightness(text) {
    const match = /^[^,]+,backlight,\d+,(\d+)%,\d+\s*$/.exec(String(text).trim());
    const value = Number(match?.[1]);
    if (!match || value > 100) throw new Error('invalid-backlight-output');
    return value / 100;
}

export function parseDdcDetect(text) {
    const results = [];
    const blocks = String(text).split(/(?=^\s*(?:Display \d+|Invalid display)\s*$)/m);
    for (const block of blocks) {
        const bus = /^\s*I2C bus:\s+\/dev\/i2c-(\d+)\s*$/m.exec(block)?.[1];
        if (!bus) continue;
        const connector = /^\s*DRM connector:\s+(?:card\d+-)?(\S+)\s*$/m.exec(block)?.[1] ?? '';
        results.push({ bus, connector });
    }
    return results;
}

export function parseDdcBus(text, connector) {
    const normalized = String(connector).replace(/^card\d+-/, '');
    const matches = parseDdcDetect(text).filter(item => item.connector === normalized);
    if (!normalized || matches.length !== 1) return null;
    return matches[0].bus;
}

export function parseDdcBrightness(text) {
    const match = /^VCP\s+10\s+C\s+(\d+)\s+(\d+)\s*$/.exec(String(text).trim());
    const current = Number(match?.[1]), max = Number(match?.[2]);
    if (!match || max <= 0 || current > max) throw new Error('invalid-ddc-output');
    return { current, max, value: current / max };
}

export function stepsFromDelta(delta) {
    if (!Number.isFinite(delta)) return 0;
    return -Math.trunc(delta);
}
