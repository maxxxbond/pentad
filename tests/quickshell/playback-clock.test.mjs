import assert from "node:assert/strict";
import test from "node:test";
import { createPlaybackClock } from "../../quickshell/logic/playback-clock.mjs";

const sample = (positionMicros, positionUpdatedAt, extra = {}) => ({
  id: "spotify", trackId: "/t/1", trackRevision: "1", playback: "playing",
  lengthMicros: 200_000_000, positionMicros, positionUpdatedAt, ...extra,
});

test("advances with wall time while playing and holds while paused", () => {
  const clock = createPlaybackClock();
  clock.sync(sample(10_000_000, 1000), 1000);
  assert.equal(clock.at(1500), 10_500_000);
  clock.sync(sample(10_500_000, 1500, { playback: "paused" }), 1500);
  assert.equal(clock.at(3000), 10_500_000);
});

test("eases a small lagging sample instead of stepping backwards", () => {
  const clock = createPlaybackClock();
  clock.sync(sample(10_000_000, 0), 0);
  // The player reports 200 ms less than the clock predicted.
  clock.sync(sample(10_800_000, 1000), 1000);
  let previous = clock.at(1000);
  assert.equal(previous, 11_000_000);
  for (let now = 1016; now <= 2000; now += 16) {
    const shown = clock.at(now);
    assert.ok(shown >= previous, `went backwards at ${now}`);
    previous = shown;
  }
  assert.equal(clock.at(2000), 11_800_000);
});

test("jumps on a large difference, a play state change or a new track", () => {
  const clock = createPlaybackClock();
  clock.sync(sample(10_000_000, 0), 0);
  clock.sync(sample(60_000_000, 100), 100);
  assert.equal(clock.at(100), 60_000_000);
  clock.sync(sample(60_050_000, 150, { playback: "paused" }), 150);
  assert.equal(clock.at(150), 60_050_000);
  clock.sync(sample(0, 200, { trackId: "/t/2", trackRevision: "2" }), 200);
  assert.equal(clock.at(200), 0);
});

test("shows a seek at once and ignores stale samples until confirmed", () => {
  const clock = createPlaybackClock();
  clock.sync(sample(10_000_000, 0), 0);
  clock.seek(90_000_000, 100);
  assert.equal(clock.at(100), 90_000_000);
  clock.sync(sample(10_300_000, 400), 400);
  assert.equal(clock.at(400), 90_300_000);
  clock.sync(sample(90_250_000, 500), 500);
  assert.ok(Math.abs(clock.at(500) - 90_400_000) < 1000);
  assert.equal(clock.at(1500), 91_250_000);
});

test("falls back to the player after the seek hold expires", () => {
  const clock = createPlaybackClock({ holdMs: 1000 });
  clock.sync(sample(10_000_000, 0, { playback: "paused" }), 0);
  clock.seek(90_000_000, 0);
  clock.sync(sample(10_000_000, 500, { playback: "paused" }), 500);
  assert.equal(clock.at(500), 90_000_000);
  clock.sync(sample(10_000_000, 1500, { playback: "paused" }), 1500);
  assert.equal(clock.at(1500), 10_000_000);
});

test("holds a sample stamped in the future, like mediaPosition", () => {
  const clock = createPlaybackClock();
  clock.sync(sample(13_000_000, 60_000), 0);
  assert.equal(clock.at(30_000), 13_000_000);
  assert.equal(clock.at(61_000), 14_000_000);
});

test("clamps to the track length and resets without a player", () => {
  const clock = createPlaybackClock();
  clock.sync(sample(199_900_000, 0), 0);
  assert.equal(clock.at(5000), 200_000_000);
  clock.sync(null, 6000);
  assert.equal(clock.at(7000), 0);
});
