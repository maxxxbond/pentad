export const MIN_TIMER_SECONDS = 1;
export const MAX_TIMER_SECONDS = 86400;

// Qt format patterns for the bar clock (layout.clockFormat, layout.showSeconds, layout.clockDate).
// Dates stay numeric: locale word abbreviations carry dots and vary in width.
export function timePattern(format, seconds) {
  const twelve = format === '12h';
  return (twelve ? 'h:mm' : 'HH:mm') + (seconds ? ':ss' : '') + (twelve ? ' AP' : '');
}

export function datePattern(style) {
  return style === 'hidden' ? '' : style === 'month-day' ? 'MM/dd' : 'dd.MM';
}

export function idleTimerState() {
  return { status: 'idle', durationSeconds: 0, remainingSeconds: 0 };
}

export function formatTimer(seconds) {
  const value = Math.max(0, Math.floor(Number(seconds) || 0));
  const hours = Math.floor(value / 3600);
  const minutes = Math.floor(value % 3600 / 60);
  const rest = value % 60;
  const pad = number => number < 10 ? `0${number}` : String(number);
  return hours > 0 ? `${pad(hours)}:${pad(minutes)}:${pad(rest)}` : `${pad(minutes)}:${pad(rest)}`;
}

export function createClockTimerController(scheduler) {
  if (!scheduler || typeof scheduler.now !== 'function'
      || typeof scheduler.schedule !== 'function' || typeof scheduler.cancel !== 'function')
    throw new TypeError('Clock timer requires now, schedule and cancel functions');
  let state = idleTimerState();
  let deadline = 0;
  let scheduled = null;
  let disposed = false;
  const listeners = new Set();

  function publish(next) {
    if (disposed) return;
    state = next;
    Array.from(listeners).forEach(listener => listener(state));
  }
  function cancelTick() {
    if (scheduled !== null) scheduler.cancel(scheduled);
    scheduled = null;
  }
  function remainingAt(now) {
    return Math.max(0, Math.ceil((deadline - now) / 1000));
  }
  function scheduleTick(now, remaining) {
    cancelTick();
    if (disposed || state.status !== 'running') return;
    const remainingMs = Math.max(0, deadline - now);
    const untilNextSecond = remainingMs - Math.max(0, remaining - 1) * 1000;
    scheduled = scheduler.schedule(refresh, Math.max(1, Math.min(1000, untilNextSecond || 1000)));
  }
  function refresh() {
    if (disposed || state.status !== 'running') return state;
    const now = scheduler.now();
    const remainingSeconds = remainingAt(now);
    if (remainingSeconds === 0) {
      scheduled = null;
      publish({ status: 'finished', durationSeconds: state.durationSeconds, remainingSeconds: 0 });
    } else {
      if (remainingSeconds !== state.remainingSeconds)
        publish({ status: 'running', durationSeconds: state.durationSeconds, remainingSeconds });
      scheduleTick(now, remainingSeconds);
    }
    return state;
  }

  return {
    read: () => state,
    subscribe(listener) {
      if (disposed) return () => {};
      listeners.add(listener);
      listener(state);
      return () => listeners.delete(listener);
    },
    start(durationSeconds) {
      if (disposed || !Number.isInteger(durationSeconds)
          || durationSeconds < MIN_TIMER_SECONDS || durationSeconds > MAX_TIMER_SECONDS)
        return false;
      cancelTick();
      const now = scheduler.now();
      deadline = now + durationSeconds * 1000;
      publish({ status: 'running', durationSeconds, remainingSeconds: durationSeconds });
      scheduleTick(now, durationSeconds);
      return true;
    },
    pause() {
      if (disposed || state.status !== 'running') return false;
      const remainingSeconds = remainingAt(scheduler.now());
      cancelTick();
      publish({ status: remainingSeconds === 0 ? 'finished' : 'paused',
        durationSeconds: state.durationSeconds, remainingSeconds });
      return true;
    },
    resume() {
      if (disposed || state.status !== 'paused' || state.remainingSeconds < 1) return false;
      const now = scheduler.now();
      deadline = now + state.remainingSeconds * 1000;
      publish({ status: 'running', durationSeconds: state.durationSeconds,
        remainingSeconds: state.remainingSeconds });
      scheduleTick(now, state.remainingSeconds);
      return true;
    },
    reset() {
      if (disposed) return false;
      cancelTick();
      deadline = 0;
      publish(idleTimerState());
      return true;
    },
    refresh,
    dispose() {
      if (disposed) return;
      cancelTick();
      disposed = true;
      listeners.clear();
    },
  };
}
