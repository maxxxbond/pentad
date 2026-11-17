// The bind list the cheatsheet shows in preview mode, shaped like `hyprctl binds -j` output, so
// fixtures and the showcase never run hyprctl. It mixes a traditional config (dispatchers with
// arguments, no descriptions), described binds in "Group: text" form, a submap and Lua binds.

function bind(modmask, key, dispatcher, arg, description, extra) {
    return Object.assign({
        locked: false, mouse: false, release: false, repeat: false, longPress: false, non_consuming: false,
        has_description: !!description, modmask: modmask, submap: '', key: key, keycode: 0, catch_all: false,
        description: description || '', dispatcher: dispatcher, arg: arg,
    }, extra || {});
}

const SUPER = 64, SHIFT = 1, CTRL = 4, ALT = 8;

export const SAMPLE_BINDS = [
    bind(SUPER, 'SUPER_L', 'global', 'pentad:search-release', 'Pentad: Search applications', { release: true }),
    bind(SUPER, 'SUPER_R', 'global', 'pentad:search-release', 'Pentad: Search applications', { release: true }),
    bind(SUPER, 'Space', 'global', 'pentad:search', 'Pentad: Search applications'),
    bind(SUPER, 'Tab', 'global', 'pentad:overview', 'Pentad: Workspace overview'),
    bind(SUPER, 'V', 'global', 'pentad:clipboard', 'Pentad: Clipboard history'),
    bind(SUPER, 'Period', 'global', 'pentad:emoji', 'Pentad: Emoji'),
    bind(SUPER, 'Slash', 'global', 'pentad:cheatsheet', 'Pentad: Keybind cheatsheet'),
    bind(ALT, 'Tab', 'global', 'pentad:window-next', 'Pentad: Next window'),
    bind(ALT, '', 'global', 'pentad:application-next', 'Pentad: Next window of the app', { keycode: 49 }),
    bind(SUPER, 'Print', 'global', 'pentad:screenshot', 'Screenshot: Region and editor'),
    bind(0, 'Print', 'exec', 'pentad screenshot monitor', 'Screenshot: Whole monitor'),
    bind(0, 'XF86AudioRaiseVolume', 'exec', 'wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 5%+', 'Media: Volume up', { locked: true, repeat: true }),
    bind(0, 'XF86AudioLowerVolume', 'exec', 'wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-', 'Media: Volume down', { locked: true, repeat: true }),
    bind(0, 'XF86AudioMute', 'exec', 'wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle', 'Media: Mute', { locked: true }),
    bind(0, 'XF86AudioPlay', 'exec', 'playerctl play-pause', 'Media: Play or pause', { locked: true }),
    bind(0, 'XF86MonBrightnessUp', 'exec', 'brightnessctl set 5%+', 'Media: Brighter screen', { locked: true, repeat: true }),
    bind(SUPER, 'A', '__lua', '31', 'Shell: Toggle left sidebar'),
    bind(SUPER | SHIFT, 'L', '__lua', '33', 'Shell: Lock the session'),
    bind(SUPER, 'Return', 'exec', 'foot'),
    bind(SUPER, 'E', 'exec', 'nautilus'),
    bind(SUPER, 'B', 'exec', 'firefox'),
    bind(SUPER, 'Q', 'killactive', ''),
    bind(SUPER, 'F', 'fullscreen', '0'),
    bind(SUPER | ALT, 'Space', 'togglefloating', ''),
    bind(SUPER, 'P', 'pin', ''),
    // A second bind on Super+P, added later and forgotten: the cheatsheet flags the pair.
    bind(SUPER, 'P', 'exec', 'hyprpicker -a'),
    bind(SUPER, 'Left', 'movefocus', 'l'),
    bind(SUPER, 'Right', 'movefocus', 'r'),
    bind(SUPER, 'Up', 'movefocus', 'u'),
    bind(SUPER, 'Down', 'movefocus', 'd'),
    bind(SUPER | SHIFT, 'Left', 'movewindow', 'l'),
    bind(SUPER | SHIFT, 'Right', 'movewindow', 'r'),
    bind(SUPER, 'mouse:272', 'movewindow', '', '', { mouse: true }),
    bind(SUPER, 'mouse:273', 'resizewindow', '', '', { mouse: true }),
    bind(SUPER, '1', 'workspace', '1'),
    bind(SUPER, '2', 'workspace', '2'),
    bind(SUPER, '3', 'workspace', '3'),
    bind(SUPER | SHIFT, '1', 'movetoworkspace', '1'),
    bind(SUPER | SHIFT, '2', 'movetoworkspace', '2'),
    bind(SUPER, 'mouse_down', 'workspace', 'e+1'),
    bind(SUPER, 'mouse_up', 'workspace', 'e-1'),
    bind(SUPER | CTRL, 'R', 'submap', 'resize'),
    bind(0, 'Right', 'resizeactive', '20 0', '', { submap: 'resize', repeat: true }),
    bind(0, 'Left', 'resizeactive', '-20 0', '', { submap: 'resize', repeat: true }),
    bind(0, 'Escape', 'submap', 'reset', '', { submap: 'resize' }),
    // Lua binds without a description: only a function number, hidden until "Show all".
    bind(0, 'Super_L', '__lua', '326'),
    bind(0, 'Super_L', '__lua', '328', '', { release: true }),
    bind(SUPER, 'Minus', '__lua', '36', '', { repeat: true }),
    bind(SUPER, 'Equal', '__lua', '38', '', { repeat: true }),
];
