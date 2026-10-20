const gameClasses = new Set([
    'cs2', 'dota2', 'dota 2', 'dota 2 beta', 'dota', 'eldenring', 'elden ring',
    'helldivers2', 'helldivers 2', 'hades2', 'hades ii', 'r5apex', 'apex legends',
    'cyberpunk2077', 'cyberpunk 2077', 'witcher3', 'the witcher 3', 'starfield',
]);

export function isRecognizedGameClass(appClass) {
    const normalized = String(appClass || '').trim().toLocaleLowerCase();
    return /^steam_app_\d+$/.test(normalized) || gameClasses.has(normalized);
}
