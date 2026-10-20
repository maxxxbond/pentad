export const MAX_SPOTLIGHT_QUERY_LENGTH = 256;

const MATH_OPERATORS = /^[\d\s+\-*/^%().,eE]+$/;
const HAS_OPERATOR = /[+\-*/^%]/;

export function detectIntent(query) {
  const trimmed = typeof query === 'string' ? query.trim().slice(0, MAX_SPOTLIGHT_QUERY_LENGTH) : '';
  if (!trimmed) return { mode: 'all', cleanQuery: '', isMathExpression: false };
  if (trimmed.startsWith(':')) return { mode: 'emoji', cleanQuery: trimmed.slice(1).trim(), isMathExpression: false };
  if (trimmed === 'cb' || trimmed.startsWith('cb '))
    return { mode: 'clipboard', cleanQuery: trimmed.slice(2).trim(), isMathExpression: false };
  if (trimmed === '?' || trimmed.startsWith('? '))
    return { mode: 'web', cleanQuery: trimmed.slice(1).trim(), isMathExpression: false };
  if (trimmed.startsWith('='))
    return { mode: 'calc', cleanQuery: trimmed.slice(1).trim(), isMathExpression: true };
  const math = trimmed.length >= 3 && MATH_OPERATORS.test(trimmed)
    && HAS_OPERATOR.test(trimmed) && /\d/.test(trimmed);
  return { mode: 'all', cleanQuery: trimmed, isMathExpression: math };
}
