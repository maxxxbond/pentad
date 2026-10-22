// Reads the active keyboard layout from `hyprctl -j devices`.
// Hyprland reports the layout list per keyboard; the main keyboard is the one the user types on.
export function keyboardLayoutState(text) {
    let devices = null;
    try { devices = JSON.parse(text); } catch (error) { return null; }
    const keyboards = devices && Array.isArray(devices.keyboards)
        ? devices.keyboards.filter(item => item && typeof item === 'object') : [];
    const keyboard = keyboards.find(item => item.main === true) || keyboards[0];
    if (!keyboard) return null;
    const codes = String(keyboard.layout || '').split(',').map(code => code.trim());
    const variants = String(keyboard.variant || '').split(',').map(variant => variant.trim());
    const layouts = codes.map((code, index) => ({ index, code, variant: variants[index] || '', label: shortLabel(code, 3) }))
        .filter(layout => layout.code && layout.label);
    const index = Number(keyboard.active_layout_index);
    const name = typeof keyboard.active_keymap === 'string' ? keyboard.active_keymap : '';
    const active = layouts.find(layout => layout.index === index) || null;
    const label = active ? active.label : shortLabel(name, 2);
    if (!label) return null;
    return { label, name: name || label, index: active ? index : -1, count: layouts.length, layouts };
}

function shortLabel(text, length) {
    return String(text || '').replace(/[^A-Za-z]/g, '').slice(0, length).toUpperCase();
}

// Human names from the XKB registry (`evdev.lst`): "de" → "German", "de(us)" → "German (US)".
export function keyboardLayoutNames(text) {
    const names = {};
    let section = '';
    for (const line of String(text || '').split('\n')) {
        const header = /^!\s*(\w+)/.exec(line);
        if (header) { section = header[1]; continue; }
        const entry = /^\s+(\S+)\s+(.+?)\s*$/.exec(line);
        if (!entry) continue;
        if (section === 'layout') names[entry[1]] = entry[2];
        else if (section === 'variant') {
            const variant = /^([^:\s]+):\s*(.+)$/.exec(entry[2]);
            if (variant) names[variant[1] + '(' + entry[1] + ')'] = variant[2];
        }
    }
    return names;
}

export function keyboardLayoutName(layout, names) {
    if (!layout) return '';
    const table = names || {};
    return (layout.variant && table[layout.code + '(' + layout.variant + ')']) || table[layout.code] || layout.label;
}

// The layout reached after `steps` wheel notches; it wraps around like Hyprland's next/prev.
export function keyboardLayoutAfter(index, count, steps) {
    if (!(count > 1) || !Number.isInteger(steps) || steps === 0) return -1;
    const start = index >= 0 && index < count ? index : 0;
    return ((start + steps) % count + count) % count;
}
