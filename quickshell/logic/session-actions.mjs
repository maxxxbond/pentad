const actions = ['lock', 'logout', 'reboot', 'poweroff'];
const manager = ['busctl', '--system', '--timeout=8', '--allow-interactive-authorization=yes',
  'call', 'org.freedesktop.login1', '/org/freedesktop/login1', 'org.freedesktop.login1.Manager'];

export function validSessionId(value) {
  return typeof value === 'string' && /^[a-zA-Z0-9_.-]{1,128}$/.test(value);
}

export function actionCommand(action, sessionId) {
  if (action === 'lock' && validSessionId(sessionId)) return ['loginctl', 'lock-session', sessionId];
  if (action === 'logout' && validSessionId(sessionId)) return manager.concat(['TerminateSession', 's', sessionId]);
  if (action === 'reboot') return manager.concat(['Reboot', 'b', 'true']);
  if (action === 'poweroff') return manager.concat(['PowerOff', 'b', 'true']);
  return null;
}

export function parseCapability(output) {
  const match = /^s "(yes|challenge|no|na)"$/.exec(String(output || '').trim());
  return match && ['yes', 'challenge', 'no'].includes(match[1]) ? match[1] : 'unavailable';
}

export function cleanIdentity(value, limit = 128) {
  return String(value || '').replace(/[\x00-\x1f\x7f]/g, '').trim().slice(0, limit);
}

export function parseAccount(output, fallback) {
  const fields = String(output || '').trim().split(':');
  if (fields.length !== 7 || fields[0] !== fallback) return cleanIdentity(fallback);
  return cleanIdentity(fields[4].split(',')[0]) || cleanIdentity(fallback);
}

export function createSessionController(ports) {
  let state = { action: '', confirmation: '', pending: '', error: '' };
  let generation = 0, disposed = false;
  const publish = (patch) => {
    if (disposed) return;
    state = Object.assign({}, state, patch);
    if (ports.changed) ports.changed(Object.assign({}, state));
  };
  const allowed = (action) => {
    if (!actions.includes(action)) return 'unknown-action';
    if (!ports.writable()) return 'read-only';
    if (!['yes', 'challenge'].includes(ports.capabilities()[action])) return 'unavailable';
    return '';
  };
  const run = (action) => {
    const reason = allowed(action);
    if (reason) { publish({ confirmation: '', error: reason }); return false; }
    const argv = actionCommand(action, ports.sessionId());
    if (!argv) { publish({ confirmation: '', error: 'session-unavailable' }); return false; }
    const current = ++generation;
    publish({ action, confirmation: '', pending: action, error: '' });
    const complete = (ok, error) => {
      if (disposed || generation !== current || state.pending !== action) return;
      publish({ pending: '', error: ok ? '' : error || 'failed' });
      if (ports.finished) ports.finished(action, ok);
    };
    try { ports.execute(argv, complete); }
    catch (error) { complete(false, 'failed'); }
    return true;
  };
  return {
    read: () => Object.assign({}, state),
    request(action) {
      if (disposed || state.pending) return false;
      const reason = allowed(action);
      if (reason) { publish({ action, confirmation: '', error: reason }); return false; }
      if (action === 'lock') return run(action);
      publish({ action, confirmation: action, error: '' });
      return true;
    },
    confirm() {
      if (disposed || state.pending || !state.confirmation) return false;
      return run(state.confirmation);
    },
    cancel() {
      if (!disposed && !state.pending) publish({ action: '', confirmation: '', error: '' });
    },
    dispose() { disposed = true; generation++; },
  };
}
