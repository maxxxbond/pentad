// Reads the active keyboard layout from `hyprctl -j devices`.
// Hyprland reports the layout list per keyboard; the main keyboard is the one the user types on.
export function keyboardLayoutState(text) {
    let devices = null;
    try { devices = JSON.parse(text); } catch (error) { return null; }
    const keyboards = devices && Array.isArray(devices.keyboards)
        ? devices.keyboards.filter(item => item && typeof item === 'object') : [];
    const keyboard = keyboards.find(item => item.main === true) || keyboards[0];
    if (!keyboard) return null;
    const codes = String(keyboard.layout || '').split(',').map(code => code.trim()).filter(Boolean);
    const index = Number(keyboard.active_layout_index);
    const name = typeof keyboard.active_keymap === 'string' ? keyboard.active_keymap : '';
    const code = Number.isInteger(index) && index >= 0 && index < codes.length ? codes[index] : '';
    const label = (code || name).replace(/[^A-Za-z]/g, '').slice(0, code ? 3 : 2).toUpperCase();
    if (!label) return null;
    return { label, name: name || label, count: codes.length };
}
