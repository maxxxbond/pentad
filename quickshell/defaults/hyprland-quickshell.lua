for _, key in ipairs({ "SUPER + SUPER_L", "SUPER + SUPER_R",
                        "Super_L", "Super_R", "Alt_L", "Alt_R",
                        "SUPER + Tab", "ALT + Tab", "ALT + SHIFT + Tab",
                        "SUPER + Space", "SUPER + V", "SUPER + Period",
                        "ALT + code:49", "ALT + SHIFT + code:49" }) do
    hl.unbind(key)
end
hl.layer_rule({
    name = "pentad-quickshell-motion",
    match = { namespace = "^pentad.*$" },
    no_anim = true,
    blur = false,
    blur_popups = false,
})
-- If the lock screen crashes, the session stays locked on a solid screen; this lets
-- `pentad lock` start hyprlock to take over that lock instead of leaving only a TTY way back.
hl.config({ misc = { allow_session_lock_restore = true } })
for key, name in pairs({ Super_L = "super-left", Super_R = "super-right",
                        Alt_L = "alt-left", Alt_R = "alt-right" }) do
    hl.bind(key, hl.dsp.global("pentad:" .. name),
        { ignore_mods = true, transparent = true })
    hl.bind(key, hl.dsp.global("pentad:" .. name),
        { ignore_mods = true, transparent = true, release = true })
end
for _, key in ipairs({ "SUPER_L", "SUPER_R" }) do
    hl.bind("SUPER + " .. key, hl.dsp.global("pentad:search-release"),
        { release = true, description = "Pentad: Search applications" })
end
hl.bind("SUPER + Space", hl.dsp.global("pentad:search"))
hl.bind("SUPER + V", hl.dsp.global("pentad:clipboard"), { description = "Pentad: Clipboard history" })
hl.bind("SUPER + Period", hl.dsp.global("pentad:emoji"), { description = "Pentad: Emoji" })
hl.bind("SUPER + Tab", hl.dsp.global("pentad:overview"))
hl.bind("ALT + Tab", hl.dsp.global("pentad:window-next"))
hl.bind("ALT + SHIFT + Tab", hl.dsp.global("pentad:window-previous"))
hl.bind("ALT + code:49", hl.dsp.global("pentad:application-next"))
hl.bind("ALT + SHIFT + code:49", hl.dsp.global("pentad:application-previous"))
