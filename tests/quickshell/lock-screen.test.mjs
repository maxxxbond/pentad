import test from 'node:test';
import assert from 'node:assert/strict';
import { busy, cancelled, cleanPamText, completed, initialAuth, message, noticeText, powerAllowed,
  powerCapabilityCommand, powerCommand, startFailed, submit, timedOut, ukrainian } from '../../quickshell/logic/lock-screen.mjs';

const secretPrompt = { text: 'Password: ', isError: false, responseRequired: true, responseVisible: false };

function started() {
  return submit(initialAuth(), true).state;
}

test('an empty submit or a submit while checking does nothing', () => {
  assert.equal(submit(initialAuth(), false).action, 'none');
  const state = started();
  assert.equal(state.phase, 'starting');
  assert.equal(busy(state), true);
  assert.equal(submit(state, true).action, 'none');
});

test('only the first hidden prompt is answered with the typed password', () => {
  const first = message(started(), secretPrompt);
  assert.equal(first.action, 'respond-secret');
  assert.equal(first.state.phase, 'verifying');
  const second = message(first.state, Object.assign({}, secretPrompt, { text: 'Verification code: ' }));
  assert.equal(second.action, 'ask');
  assert.equal(second.state.phase, 'prompt');
  assert.equal(second.state.prompt, 'Verification code:');
  assert.equal(busy(second.state), false);
  const answered = submit(second.state, true);
  assert.equal(answered.action, 'respond');
  assert.equal(answered.state.phase, 'verifying');
  const back = cancelled(second.state);
  assert.equal(back.phase, 'idle');
  assert.equal(back.prompt, '');
  assert.equal(cancelled(first.state), first.state);
});

test('a visible first prompt is never answered with the password', () => {
  const result = message(started(), { text: 'login:', isError: false, responseRequired: true, responseVisible: true });
  assert.equal(result.action, 'ask');
  assert.equal(result.state.promptVisible, true);
});

test('only an exact success unlocks; anything else counts as a failed attempt', () => {
  const verifying = message(started(), secretPrompt).state;
  assert.equal(completed(verifying, 0).phase, 'unlocked');
  for (const [result, notice] of [[1, 'wrong'], [2, 'unavailable'], [3, 'tooMany'], [7, 'wrong'], [undefined, 'wrong']]) {
    const after = completed(verifying, result);
    assert.equal(after.phase, 'idle', `result ${result}`);
    assert.equal(after.notice, notice);
    assert.equal(after.attempts, 1);
  }
});

test('an error message from PAM replaces the generic notice', () => {
  let state = message(started(), secretPrompt).state;
  state = message(state, { text: 'The account is locked due to 3 failed logins.\n(9 minutes left to unlock)',
    isError: true, responseRequired: false, responseVisible: false }).state;
  const after = completed(state, 1);
  assert.equal(after.notice, 'pam');
  assert.equal(after.pamNotice, 'The account is locked due to 3 failed logins. (9 minutes left to unlock)');
  assert.equal(after.pamError, true);
  const info = message(message(started(), secretPrompt).state,
    { text: 'Place your finger', isError: false, responseRequired: false, responseVisible: false }).state;
  assert.equal(completed(info, 1).notice, 'wrong');
});

test('late events after the outcome change nothing', () => {
  const unlocked = completed(message(started(), secretPrompt).state, 0);
  assert.equal(completed(unlocked, 1), unlocked);
  assert.equal(timedOut(unlocked), unlocked);
  assert.equal(message(unlocked, secretPrompt).action, 'none');
  const idle = initialAuth();
  assert.equal(completed(idle, 0), idle);
  assert.equal(message(idle, secretPrompt).action, 'none');
});

test('a refused start and a stalled check release the field with their own notice', () => {
  assert.equal(startFailed(started()).notice, 'unavailable');
  assert.equal(startFailed(initialAuth()).attempts, 0);
  const stalled = timedOut(message(started(), secretPrompt).state);
  assert.equal(stalled.phase, 'idle');
  assert.equal(stalled.notice, 'timeout');
});

test('notices exist in both languages', () => {
  for (const code of ['wrong', 'unavailable', 'tooMany', 'timeout']) {
    const { uk, en } = noticeText(code);
    assert.ok(uk && en && uk !== en && /[а-яіїєґ]/i.test(uk), code);
  }
});

test('PAM text is one plain line of bounded length', () => {
  assert.equal(cleanPamText('a\u0000b\r\n\tc\u007f'), 'a b c');
  assert.equal(cleanPamText(null), '');
  assert.equal(cleanPamText('x'.repeat(500)).length, 200);
});

test('power actions never ask polkit and need an unconditional yes', () => {
  assert.deepEqual(powerCommand('reboot').slice(-3), ['Reboot', 'b', 'false']);
  assert.ok(powerCommand('suspend').includes('--allow-interactive-authorization=no'));
  assert.equal(powerCapabilityCommand('poweroff').at(-1), 'CanPowerOff');
  assert.equal(powerCommand('logout'), null);
  assert.equal(powerCapabilityCommand('hibernate'), null);
  assert.equal(powerAllowed('s "yes"\n'), true);
  assert.equal(powerAllowed('s "challenge"'), false);
  assert.equal(powerAllowed(''), false);
});

test('the language rule matches the main shell', () => {
  assert.equal(ukrainian('uk', 'en_US'), true);
  assert.equal(ukrainian('en', 'uk_UA'), false);
  assert.equal(ukrainian('auto', 'uk_UA'), true);
  assert.equal(ukrainian('auto', 'de_DE'), false);
});
