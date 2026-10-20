import assert from "node:assert/strict";
import test from "node:test";
import { adjacentPlayerId, chooseMprisPlayer, createStallTracker, mediaPosition, mediaValue, microsToSeconds, mprisTrackId, normalizeMprisPlayer, secondsToMicros } from "../../quickshell/logic/media.mjs";

const player = (id, playback, extra = {}) => ({ id, playback, ...extra });

test("converts MPRIS seconds and absolute seek microseconds", () => {
  assert.equal(secondsToMicros(12.5), 12_500_000);
  assert.equal(microsToSeconds(15_000_000), 15);
});

test("normalizes Quickshell's QVariant-wrapped D-Bus object path", () => {
  assert.equal(mprisTrackId({ toString: () => 'QVariant(QDBusObjectPath, QDBusObjectPath("/org/example/track_1"))' }), "/org/example/track_1");
  assert.equal(mprisTrackId({ path: "/org/example/track_2" }), "/org/example/track_2");
  assert.equal(mprisTrackId("/org/example/track_3"), "/org/example/track_3");
  assert.equal(mprisTrackId({ toString: () => "not a track id" }), "");
});

test("normalizes native metadata, duration, playback and capabilities", () => {
  const result = normalizeMprisPlayer({
    dbusName: "org.mpris.MediaPlayer2.player", identity: "Player", uniqueId: 7,
    metadata: { "mpris:trackid": "/track/1" }, trackTitle: "Song", trackArtist: "A, B",
    trackAlbum: "Album", trackArtUrl: "file:///cover", position: 12.5, length: 180,
    lengthSupported: true, isPlaying: true, canTogglePlaying: true, canControl: true,
    canGoNext: true, canGoPrevious: false, canSeek: true, positionSupported: true,
  }, 1000);
  assert.equal(result.positionMicros, 12_500_000);
  assert.equal(result.lengthMicros, 180_000_000);
  assert.equal(result.artist, "A, B");
  assert.equal(result.playback, "playing");
  assert.equal(result.canNext, true);
  assert.equal(result.canPrevious, false);
  assert.equal(result.canPlayPause, true);
  assert.equal(result.canSeek, true);
  assert.equal(result.trackRevision, "7");
});

test("native capabilities require control permission and position support", () => {
  const result = normalizeMprisPlayer({
    dbusName: "org.mpris.MediaPlayer2.player", metadata: {}, canTogglePlaying: true,
    canControl: false, canSeek: true, positionSupported: true,
  });
  assert.equal(result.canPlayPause, false);
  assert.equal(result.canNext, false);
  assert.equal(result.canPrevious, false);
  assert.equal(result.canSeek, false);
});

test("keeps legacy optional duration and position absent when MPRIS lacks them", () => {
  const result = normalizeMprisPlayer({ dbusName: "org.mpris.MediaPlayer2.player", metadata: {}, playbackState: 0 });
  assert.equal(result.playback, "stopped");
  assert.equal("lengthMicros" in result, false);
  assert.equal("positionMicros" in result, false);
  assert.equal("trackId" in result, false);
});

test("read-only media exposes track metadata but disables transport and seeking", () => {
  const source = {
    dbusName: "org.mpris.MediaPlayer2.player", trackTitle: "Song", trackArtUrl: "file:///cover.png",
    canControl: true, canTogglePlaying: true, canGoNext: true, canGoPrevious: true,
    canSeek: true, positionSupported: true, position: 12, isPlaying: true,
  };
  const restricted = mediaValue([source], "", 1000, false).current;
  assert.equal(restricted.title, "Song");
  assert.equal(restricted.artUrl, "file:///cover.png");
  assert.equal(restricted.positionMicros, 12_000_000);
  for (const key of ["canPlayPause", "canNext", "canPrevious", "canSeek"]) {
    assert.equal(restricted[key], false);
    assert.equal(mediaValue([source], "", 1000, true).current[key], true);
  }
});

test("selection pins a present source, then falls back playing, paused, first", () => {
  const items = [player("idle", "stopped"), player("paused", "paused"), player("playing", "playing")];
  assert.equal(chooseMprisPlayer(items, "paused").id, "paused");
  assert.equal(chooseMprisPlayer(items, "gone").id, "playing");
  assert.equal(chooseMprisPlayer([items[0], items[1]]).id, "paused");
  assert.equal(chooseMprisPlayer([items[0]]).id, "idle");
  assert.equal(chooseMprisPlayer([], "gone"), null);
  assert.deepEqual(mediaValue([], "gone", 5), { players: [], selectedId: "gone", current: null });
});

test("position interpolates only while playing and clamps to duration", () => {
  const value = { positionMicros: 2_000_000, positionUpdatedAt: 1000, lengthMicros: 3_000_000, playback: "playing" };
  assert.equal(mediaPosition(value, 1500), 2_500_000);
  assert.equal(mediaPosition(value, 3000), 3_000_000);
  assert.equal(mediaPosition({ ...value, playback: "paused" }, 3000), 2_000_000);
});

test("a playing player whose position stops moving is shown as paused until it advances", () => {
  const source = (position) => ({ dbusName: "org.mpris.MediaPlayer2.firefox", isPlaying: true, playbackState: "Playing", positionSupported: true, position, uniqueId: 1 });
  const tracker = createStallTracker(2500);
  const at = (position, now) => mediaValue([source(position)], "", now, true, tracker).current;
  assert.equal(at(10, 0).playback, "playing");
  assert.equal(at(11, 1000).playback, "playing");
  assert.equal(at(11, 2000).playback, "playing");
  assert.equal(at(11, 3600).playback, "paused");
  assert.equal(at(11, 3600).stalled, true);
  assert.equal(at(12, 4600).playback, "playing");
  assert.equal(at(12, 20000).playback, "playing", "a gap in polling is not a stall");
  assert.equal(mediaValue([source(5)], "", 0, true).current.playback, "playing");
});

test("cycles media sources in both directions and wraps around", () => {
  const players = [player("a", "playing"), player("b", "paused"), player("c", "stopped")];
  assert.equal(adjacentPlayerId(players, "a", 1), "b");
  assert.equal(adjacentPlayerId(players, "c", 1), "a");
  assert.equal(adjacentPlayerId(players, "a", -1), "c");
  assert.equal(adjacentPlayerId(players, "missing", 1), "b");
  assert.equal(adjacentPlayerId(players.slice(0, 1), "a", 1), "");
  assert.equal(adjacentPlayerId([], "a", -1), "");
});
