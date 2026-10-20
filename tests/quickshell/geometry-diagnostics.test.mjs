import test from 'node:test';
import assert from 'node:assert/strict';
import { auditNestedGeometry } from '../../quickshell/logic/geometry-diagnostics.mjs';

const capsule = { width: 180, height: 48, radius: 24, curve: 'circular' };
const circle = { x: 2, y: 2, width: 44, height: 44, radius: 22, curve: 'circular' };

test('concentric circle audits only the three exposed sides of a long card', () => {
    const result = auditNestedGeometry(capsule, circle);
    assert.equal(result.status, 'ok');
    assert.deepEqual(result.insets, { top: 2, bottom: 2, edge: 2 });
    assert.equal(result.expectedRadius, 22);
    assert.equal(auditNestedGeometry(capsule, { ...circle, x: 134 }, 'right').status, 'ok');
});

test('previous Wi-Fi geometry reports both the radius and curve mismatch', () => {
    const result = auditNestedGeometry({ ...capsule, radius: 16, curve: 'continuous' }, circle);
    assert.equal(result.status, 'error');
    assert.equal(result.expectedRadius, 14);
    assert.deepEqual(result.issues, ['radius-mismatch', 'curve-mismatch']);
    assert.deepEqual(auditNestedGeometry({ ...capsule, curve: 'continuous' }, circle).issues,
        ['curve-mismatch']);
});

test('corrected radio row has matching circular ends and four-pixel spacing', () => {
    const result = auditNestedGeometry(capsule,
        { x: 4, y: 4, width: 40, height: 40, radius: 20, curve: 'circular' });
    assert.equal(result.status, 'ok');
    assert.equal(result.expectedRadius, 20);
    assert.deepEqual(result.insets, { top: 4, bottom: 4, edge: 4 });
});

test('unequal spacing and overflow are reported separately', () => {
    assert.deepEqual(auditNestedGeometry(capsule, { ...circle, x: 4 }).issues, ['unequal-insets']);
    assert.ok(auditNestedGeometry(capsule, { ...circle, y: -1 }).issues.includes('outside'));
    assert.equal(auditNestedGeometry(capsule, { ...circle, x: 2.4 }).status, 'ok');
    assert.equal(auditNestedGeometry(capsule, { ...circle, x: 2.6 }).status, 'error');
});

test('missing and non-finite layout data stay unverified and recover on valid input', () => {
    for (const inner of [null, {}, { ...circle, width: 0 }, { ...circle, radius: NaN }])
        assert.equal(auditNestedGeometry(capsule, inner).status, 'unverified');
    assert.equal(auditNestedGeometry({ ...capsule, curve: '' }, circle).status, 'unverified');
    assert.equal(auditNestedGeometry({ ...capsule, curve: 'unknown' }, circle).status, 'unverified');
    assert.equal(auditNestedGeometry(capsule, circle, 'center').status, 'unverified');
    assert.equal(auditNestedGeometry(capsule, circle).status, 'ok');
});
