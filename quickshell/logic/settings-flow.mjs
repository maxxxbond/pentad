export function createFlow(steps, draft) {
  return { steps: steps.slice(), draft: Object.assign({}, draft), index: 0, errors: [] };
}

export function setDraft(flow, patch) {
  return Object.assign({}, flow, { draft: Object.assign({}, flow.draft, patch), errors: [] });
}

function currentErrors(flow) {
  const step = flow.steps[flow.index];
  if (!step) return [];
  return step.validate(flow.draft);
}

export function canContinue(flow) {
  return flow.steps.length > 0 && currentErrors(flow).length === 0;
}

export function next(flow) {
  if (flow.steps.length === 0) return Object.assign({}, flow, { errors: [] });
  const errors = currentErrors(flow);
  if (errors.length > 0) return Object.assign({}, flow, { errors: errors.slice() });
  if (isLast(flow)) return Object.assign({}, flow, { errors: [] });
  return Object.assign({}, flow, { index: flow.index + 1, errors: [] });
}

export function back(flow) {
  return Object.assign({}, flow, { index: Math.max(0, flow.index - 1), errors: [] });
}

export function progress(flow) {
  const total = flow.steps.length;
  if (total === 0) return { index: 0, total: 0, ratio: 0 };
  const index = flow.index + 1;
  return { index, total, ratio: index / total };
}

export function isLast(flow) {
  return flow.steps.length > 0 && flow.index === flow.steps.length - 1;
}
