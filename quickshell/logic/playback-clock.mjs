import { mediaPosition } from "./media.mjs";

export const SLEW_MS = 450;
export const JUMP_MICROS = 1_000_000;
export const SEEK_HOLD_MS = 2000;
export const SEEK_CONFIRM_MICROS = 1_500_000;

function trackKey(player) {
  return `${player.id}|${player.trackId || ""}|${player.trackRevision ?? ""}`;
}

// Display clock for a media position. Samples from the player re-anchor it; small
// disagreements are eased out instead of jumping (the clock never runs backwards
// while playing), and a local seek is shown at once and protected from stale samples.
export function createPlaybackClock(options = {}) {
  const slewMs = options.slewMs ?? SLEW_MS;
  const jumpMicros = options.jumpMicros ?? JUMP_MICROS;
  const holdMs = options.holdMs ?? SEEK_HOLD_MS;
  const confirmMicros = options.confirmMicros ?? SEEK_CONFIRM_MICROS;
  let key = "";
  let playing = false;
  let lengthMicros = 0;
  let anchorMicros = 0;
  let anchorAt = 0;
  let correction = null;
  let holdUntil = 0;

  const base = (now) => anchorMicros + (playing ? Math.max(0, now - anchorAt) * 1000 : 0);
  const clamp = (micros) => Math.max(0, lengthMicros > 0 ? Math.min(lengthMicros, micros) : micros);
  function at(now) {
    let micros = base(now);
    if (correction) {
      const left = 1 - (now - correction.at) / correction.duration;
      if (left > 0) micros += correction.value * left;
      else correction = null;
    }
    return clamp(micros);
  }
  function anchor(micros, now) {
    anchorMicros = micros;
    anchorAt = now;
  }

  return {
    at,
    sync(player, now) {
      if (!player || player.positionMicros === undefined) {
        key = "";
        playing = false;
        correction = null;
        holdUntil = 0;
        anchor(0, now);
        return;
      }
      const nextKey = trackKey(player);
      const nextPlaying = player.playback === "playing";
      const sample = mediaPosition(player, now);
      // Like mediaPosition, a sample stamped in the future holds until that moment.
      const sampleAt = Math.max(now, Number(player.positionUpdatedAt || now));
      lengthMicros = Number(player.lengthMicros || 0);
      if (nextKey !== key) {
        key = nextKey;
        playing = nextPlaying;
        correction = null;
        holdUntil = 0;
        anchor(sample, sampleAt);
        return;
      }
      if (holdUntil > now && Math.abs(sample - base(now)) > confirmMicros) {
        if (nextPlaying !== playing) {
          anchor(at(now), now);
          playing = nextPlaying;
        }
        return;
      }
      holdUntil = 0;
      const shown = at(now);
      const error = shown - sample;
      if (nextPlaying !== playing || Math.abs(error) > jumpMicros) {
        correction = null;
      } else if (error !== 0) {
        // A long enough ease keeps the shown position moving forward.
        correction = { value: error, at: now, duration: Math.max(slewMs, 2 * Math.abs(error) / 1000) };
      }
      playing = nextPlaying;
      anchor(sample, sampleAt);
    },
    seek(micros, now) {
      correction = null;
      holdUntil = now + holdMs;
      anchor(clamp(micros), now);
    },
  };
}
