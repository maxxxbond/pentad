export function secondsToMicros(seconds) {
  return Math.max(0, Math.round(Number(seconds) * 1_000_000));
}

export function microsToSeconds(micros) {
  return Math.max(0, Number(micros) || 0) / 1_000_000;
}

export function mprisTrackId(value) {
  if (typeof value === "string") return value;
  if (value && typeof value.path === "string") return value.path;
  const match = String(value ?? "").match(/QDBusObjectPath\("(\/(?:[A-Za-z0-9_]+\/?)*?)"\)/);
  return match ? match[1] : "";
}

export function normalizeMprisPlayer(player, now = Date.now(), allowCommands = true) {
  if (!player) return null;
  const metadata = player.metadata || {};
  const trackId = mprisTrackId(metadata["mpris:trackid"]);
  const artist = player.trackArtist || "";
  const playbackState = String(player.playbackState);
  const playback = player.isPlaying ? "playing"
    : playbackState === "Paused" || player.playbackState === 2 ? "paused" : "stopped";
  return Object.assign({
    id: String(player.dbusName || ""),
    name: String(player.dbusName || "").replace(/^org\.mpris\.MediaPlayer2\./, ""),
    identity: player.identity || player.desktopEntry || "",
    title: player.trackTitle || "",
    artist: Array.isArray(artist) ? artist.join(", ") : String(artist),
    album: player.trackAlbum || "",
    artUrl: player.trackArtUrl || "",
    trackRevision: String(player.uniqueId ?? ""),
    playback,
    canPlayPause: allowCommands && player.canControl === true && player.canTogglePlaying === true,
    canNext: allowCommands && player.canControl === true && player.canGoNext === true,
    canPrevious: allowCommands && player.canControl === true && player.canGoPrevious === true,
    canSeek: allowCommands && player.canControl === true && player.canSeek === true && player.positionSupported === true,
  },
  trackId ? { trackId } : {},
  player.positionSupported ? { positionMicros: secondsToMicros(player.position), positionUpdatedAt: now } : {},
  player.lengthSupported ? { lengthMicros: secondsToMicros(player.length) } : {},
  typeof metadata["xesam:url"] === "string" ? { url: metadata["xesam:url"] } : {});
}

export function chooseMprisPlayer(players, selectedId = "") {
  if (selectedId) {
    const selected = players.find((player) => player.id === selectedId);
    if (selected) return selected;
  }
  return players.find((player) => player.playback === "playing")
    || players.find((player) => player.playback === "paused")
    || players[0]
    || null;
}

export const STALL_MS = 2500;

// A player that reports "playing" while its position stops moving (a browser tab
// that went offline or lost its media element) is shown as paused until it advances.
export function createStallTracker(thresholdMs = STALL_MS) {
  const seen = new Map();
  return {
    apply(player, now) {
      if (!player || player.positionMicros === undefined) return player;
      const key = `${player.id}|${player.trackId || ""}|${player.trackRevision}`;
      const last = seen.get(key);
      const moved = !last || last.positionMicros !== player.positionMicros || now - last.seenAt > thresholdMs;
      const entry = { positionMicros: player.positionMicros, changedAt: moved ? now : last.changedAt, seenAt: now };
      seen.set(key, entry);
      if (player.playback !== "playing" || now - entry.changedAt <= thresholdMs) return player;
      return Object.assign({}, player, { playback: "paused", stalled: true });
    },
    reset() { seen.clear(); },
  };
}

export function mediaValue(players, selectedId = "", now = Date.now(), allowCommands = true, tracker = null) {
  const normalized = players
    .map((player) => normalizeMprisPlayer(player, now, allowCommands))
    .map((player) => tracker ? tracker.apply(player, now) : player)
    .filter(Boolean);
  return { players: normalized, selectedId, current: chooseMprisPlayer(normalized, selectedId) };
}

export function mediaPosition(player, now = Date.now()) {
  if (!player) return 0;
  const elapsed = player.playback === "playing" ? Math.max(0, now - (player.positionUpdatedAt || now)) * 1000 : 0;
  return Math.min(player.lengthMicros || Number.MAX_SAFE_INTEGER, (player.positionMicros || 0) + elapsed);
}

export function adjacentPlayerId(players, currentId, offset) {
  if (!players || players.length < 2 || !offset) return "";
  let index = players.findIndex((player) => player.id === currentId);
  if (index < 0) index = 0;
  const step = offset < 0 ? -1 : 1;
  return players[(index + step + players.length) % players.length].id;
}
