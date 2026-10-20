export function parseCpu(text) {
    const values = /^cpu\s+(.+)$/m.exec(text)?.[1]?.trim().split(/\s+/).slice(0, 8).map(Number);
    if (!values || values.length < 4 || values.some(value => !Number.isFinite(value) || value < 0)) return null;
    return { total: values.reduce((a, b) => a + b, 0), idle: values[3] + (values[4] || 0) };
}

export function cpuUsage(previous, next) {
    if (!previous || !next || next.total <= previous.total || next.idle < previous.idle) return null;
    return Math.max(0, Math.min(1, 1 - (next.idle - previous.idle) / (next.total - previous.total)));
}

export function memoryUsage(text) {
    const total = Number(/^MemTotal:\s+(\d+)\s+kB$/m.exec(text)?.[1]) * 1024;
    const available = Number(/^MemAvailable:\s+(\d+)\s+kB$/m.exec(text)?.[1]) * 1024;
    return Number.isFinite(total) && total > 0 && Number.isFinite(available) && available <= total
        ? { used: total - available, total } : null;
}

export function networkBytes(text) {
    let received = 0, sent = 0, count = 0;
    for (const line of text.split('\n')) {
        const match = /^\s*([^:]+):\s*(.*)$/.exec(line);
        if (!match || match[1].trim() === 'lo') continue;
        const values = match[2].trim().split(/\s+/).map(Number);
        if (values.length < 16 || values.some(value => !Number.isFinite(value) || value < 0)) continue;
        received += values[0]; sent += values[8]; count++;
    }
    return count ? { received, sent } : null;
}

export function gpuSample(id, loadText, usedText, totalText) {
    const number = text => /^\d+$/.test(String(text).trim()) ? Number(String(text).trim()) : NaN;
    const load = number(loadText), used = number(usedText), total = number(totalText);
    return {
        id,
        load: Number.isFinite(load) && load <= 100 ? load / 100 : null,
        memory: Number.isSafeInteger(used) && Number.isSafeInteger(total) && total > 0 && used <= total
            ? { used, total } : null
    };
}

export function gpuPercent(samples) {
    const loads = samples.map(sample => sample.load).filter(value => Number.isFinite(value));
    return loads.length ? Math.max(...loads) : null;
}

export function rates(previous, next, elapsedSeconds) {
    if (!previous || !next || !(elapsedSeconds > 0) || next.received < previous.received || next.sent < previous.sent) return null;
    return { rxBytesPerSecond: (next.received - previous.received) / elapsedSeconds,
        txBytesPerSecond: (next.sent - previous.sent) / elapsedSeconds };
}

export function compactByteRate(bytes) {
    if (!Number.isFinite(bytes) || bytes < 0) return '—';
    const units = ['B', 'K', 'M', 'G', 'T'];
    let value = bytes, unit = 0;
    while (value >= 999.5 && unit < units.length - 1) { value /= 1024; unit++; }
    if (value >= 1000) return '999T+';
    return `${value < 100 && unit > 0 ? value.toFixed(1) : Math.round(value)}${units[unit]}`;
}

export function compactDetailByteRate(bytes) {
    const compact = compactByteRate(bytes);
    return compact === '—' ? compact : compact.replace(/\.0(?=[KMGT]$)/, '') + '/s';
}

export function byteRate(bytes) {
    if (!Number.isFinite(bytes) || bytes < 0) return '—';
    const value = bytes >= 1024 ** 2 ? `${(bytes / 1024 ** 2).toFixed(1)} MB/s` : `${Math.round(bytes / 1024)} kB/s`;
    return value;
}
