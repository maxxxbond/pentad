export function initialState() {
  return { pendingId: '', pendingKey: '', error: '' };
}

export function canCommit(state) {
  return !state.pendingId;
}

export function reduceCommit(state, itemKey, requestId) {
  if (!canCommit(state) || !requestId) return { state: Object.assign({}, state), accepted: false };
  return { state: { pendingId: requestId, pendingKey: itemKey, error: '' }, accepted: true };
}

export function reduceFinished(state, requestId, result) {
  if (!state.pendingId || requestId !== state.pendingId) return Object.assign({}, state);
  if (result?.ok) return initialState();
  return { pendingId: '', pendingKey: '', error: result?.message || result?.reason || 'error' };
}
