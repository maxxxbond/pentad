// The lock screen's PAM conversation and power actions, kept free of Qt so the rules are tested.
// The password itself never enters this module: the view keeps it and asks what to do with it.

// PamResult.Success in Quickshell. Any other value, known or not, keeps the session locked.
export const pamSuccess = 0;
export const maxInputLength = 512;
export const exitCodes = Object.freeze({ unlocked: 0, notAcquired: 1, lost: 3, noPam: 4 });

export function initialAuth() {
  return {
    phase: 'idle',      // idle | starting | verifying | prompt | unlocked
    attempts: 0,        // failed or aborted attempts; the view clears and shakes on change
    notice: '',         // a code from noticeText(), or 'pam' for the PAM text in pamNotice
    pamNotice: '',
    prompt: '',         // a follow-up question from PAM, shown verbatim as plain text
    promptVisible: false,
    secretUsed: false,
    pamError: false,
  };
}

const next = (state, changes) => Object.assign({}, state, changes);

function failed(state, notice, pamNotice = '', pamError = false) {
  return next(state, {
    phase: 'idle', attempts: state.attempts + 1, notice, pamNotice,
    prompt: '', promptVisible: false, secretUsed: false, pamError,
  });
}

// The user pressed Enter. 'start' begins a conversation with the typed password held by the view;
// 'respond' answers the PAM question on screen with the typed text.
export function submit(state, hasText) {
  if (!hasText) return { state, action: 'none' };
  if (state.phase === 'idle')
    return { state: next(state, { phase: 'starting', notice: '', pamNotice: '', secretUsed: false, pamError: false }), action: 'start' };
  if (state.phase === 'prompt')
    return { state: next(state, { phase: 'verifying', prompt: '', promptVisible: false }), action: 'respond' };
  return { state, action: 'none' };
}

// PAM sent a message. Only the first hidden prompt of a conversation gets the typed password;
// anything else (a visible prompt, a second secret such as a one-time code or a new password)
// is handed to the user, so the password never answers a question it was not typed for.
export function message(state, { text, isError, responseRequired, responseVisible }) {
  const shown = cleanPamText(text);
  if (state.phase === 'unlocked' || state.phase === 'idle') return { state, action: 'none' };
  if (!responseRequired) {
    if (shown === '') return { state, action: 'none' };
    return { state: next(state, { notice: 'pam', pamNotice: shown, pamError: isError === true }), action: 'none' };
  }
  if (state.phase === 'starting' && !state.secretUsed && !responseVisible)
    return { state: next(state, { phase: 'verifying', secretUsed: true }), action: 'respond-secret' };
  return {
    state: next(state, { phase: 'prompt', prompt: shown, promptVisible: responseVisible === true }),
    action: 'ask',
  };
}

// The conversation ended. Only an exact success unlocks.
export function completed(state, result) {
  if (state.phase === 'unlocked' || state.phase === 'idle') return state;
  if (result === pamSuccess) return next(initialAuth(), { phase: 'unlocked', attempts: state.attempts });
  // An error message from PAM (a locked account, an expired password) explains more than ours.
  if (state.notice === 'pam' && state.pamError) return failed(state, 'pam', state.pamNotice, true);
  return failed(state, result === 2 ? 'unavailable' : result === 3 ? 'tooMany' : 'wrong');
}

// PamContext.start() refused, for example because the PAM service file is missing.
export function startFailed(state) {
  return state.phase === 'starting' ? failed(state, 'unavailable') : state;
}

// Escape on a PAM question the user cannot answer: the conversation is aborted, the field returns.
export function cancelled(state) {
  return state.phase === 'prompt' ? failed(state, '') : state;
}

export function timedOut(state) {
  return state.phase === 'unlocked' || state.phase === 'idle' ? state : failed(state, 'timeout');
}

export function busy(state) {
  return state.phase === 'starting' || state.phase === 'verifying' || state.phase === 'unlocked';
}

export function noticeText(code) {
  switch (code) {
  case 'wrong': return { uk: 'Невірний пароль', en: 'Wrong password' };
  case 'unavailable': return { uk: 'Не вдалося перевірити пароль', en: 'Could not check the password' };
  case 'tooMany': return { uk: 'Забагато спроб', en: 'Too many attempts' };
  case 'timeout': return { uk: 'Перевірка не відповіла', en: 'The check did not answer' };
  default: return { uk: '', en: '' };
  }
}

// PAM text is shown as plain text in one line; control characters and runaway length are dropped.
export function cleanPamText(value) {
  return String(value || '').replace(/[\u0000-\u001f\u007f]+/g, ' ').trim().slice(0, 200);
}

// Power actions offered while locked. Only an unconditional "yes" from logind shows a button, and
// the call never asks polkit interactively: its dialog would open under the lock, out of reach.
export const powerActions = Object.freeze(['suspend', 'reboot', 'poweroff']);
const loginManager = ['busctl', '--system', '--timeout=8', '--allow-interactive-authorization=no',
  'call', 'org.freedesktop.login1', '/org/freedesktop/login1', 'org.freedesktop.login1.Manager'];
const methods = Object.freeze({ suspend: 'Suspend', reboot: 'Reboot', poweroff: 'PowerOff' });

export function powerCapabilityCommand(action) {
  return powerActions.includes(action) ? loginManager.concat(['Can' + methods[action]]) : null;
}

export function powerCommand(action) {
  return powerActions.includes(action) ? loginManager.concat([methods[action], 'b', 'false']) : null;
}

export function powerAllowed(output) {
  return /^s "yes"$/.test(String(output || '').trim());
}

// The interface language follows interface.json like the main shell: "uk", "en", or the locale.
export function ukrainian(language, localeName) {
  if (language === 'uk') return true;
  if (language === 'en') return false;
  return String(localeName || '').toLowerCase().indexOf('uk') === 0;
}
