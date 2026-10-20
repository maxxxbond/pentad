# Fullscreen game workspaces

Pentad recognizes fullscreen games by their window class. It includes CS2, Dota 2, Elden Ring, Helldivers 2, Hades II, Apex Legends, Cyberpunk 2077, The Witcher 3, Starfield, and Steam game windows whose class is `steam_app_<id>`. Other fullscreen applications keep using their current workspace.

Each recognized game client gets an unused normal workspace on the monitor where its window is located. The focused game follows into its workspace. Background fullscreen games move without changing the current focus. These workspaces use positive IDs starting at 9000, remain visible in Pentad's overview and workspace switcher, and are not hidden or reserved by the shell.

Pentad hides the bar and side drawers on a monitor while its active workspace contains a fullscreen recognized game. Overview and window switching stay available. Leaving fullscreen keeps the game in its assigned workspace. Closing it returns to the workspace it came from only when that game workspace remains active and the same monitor still has focus. Moving a game to another workspace transfers control to the user and Pentad will not move it back automatically.
