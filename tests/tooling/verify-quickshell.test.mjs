import test from 'node:test';
import assert from 'node:assert/strict';
import { assessScenarioReport, infrastructureBlockReason, parseArgs, rootChecks } from '../../scripts/verify-quickshell.mjs';

test('integration runner requires an explicit Quickshell binary and defaults to a private artifact path', () => {
  assert.throws(() => parseArgs([]), /--qs/);
  const options = parseArgs(['--qs', '/tmp/pinned/qs']);
  assert.equal(options.qs, '/tmp/pinned/qs');
  assert.match(options.reportDir, /artifacts[\/]migration[\/]integration-final[\/]/);
  const packageScriptArgs = parseArgs(['--', '--qs', '/tmp/pinned/qs', '--report-dir', '/tmp/report']);
  assert.equal(packageScriptArgs.reportDir, '/tmp/report');
});

test('integration runner accepts a passing report only when checks are present and true', () => {
  assert.deepEqual(assessScenarioReport({ status: 'pass', checks: [{ name: 'root', passed: true }] }), {
    status: 'pass', reason: '',
  });
  assert.equal(assessScenarioReport({ status: 'pass', checks: [] }).status, 'fail');
  assert.equal(assessScenarioReport({ status: 'pass', checks: [{ name: 'root', passed: false }] }).status, 'fail');
  assert.equal(assessScenarioReport({ status: 'pass', checks: [{ name: 'root' }] }).status, 'fail');
  assert.equal(assessScenarioReport({ status: 'pass', checks: [{ name: 'fixture', status: 'blocked' }] }).status, 'blocked');
  assert.equal(assessScenarioReport({ status: 'pass', checks: [{ name: 'outer', checks: [
    { name: 'nested assertion', status: 'failed' },
  ] }] }).status, 'fail');
});

test('combined report has explicit checks for every result and only passes on complete success', () => {
  assert.deepEqual(rootChecks([
    { name: 'one', status: 'pass' },
    { name: 'two', status: 'blocked', reason: 'display unavailable' },
  ]), [
    { name: 'one completed', passed: true, status: 'pass', detail: '' },
    { name: 'two completed', passed: false, status: 'blocked', detail: 'display unavailable' },
  ]);
});

test('runtime errors in captured output invalidate an otherwise passing native report', () => {
  const report = { status: 'pass', checks: [{ name: 'native assertion', passed: true }] };
  assert.equal(assessScenarioReport(report, 'PENTAD_TEST passed\nTypeError: stale QML callback').status, 'fail');
  assert.equal(assessScenarioReport(report, 'Cannot load controller for pentad.activity: Property value set multiple times').status, 'fail');
  assert.equal(assessScenarioReport(report,
    'Detected function "onBackendChanged" in Connections element. This is probably intended to be a signal handler but no signal of the target matches the name.').status, 'fail');
  assert.equal(assessScenarioReport(report, 'QML warning: expected fixture fallback was unavailable').status, 'pass');
  assert.equal(assessScenarioReport({ status: 'blocked', checks: [] }).status, 'blocked');
});

test('missing fixture modules and host subprocess denial are infrastructure blocks', () => {
  assert.equal(infrastructureBlockReason("QQmlApplicationEngine: module 'Quickshell.Wayland' is not installed"),
    'required module or plugin is unavailable');
  assert.equal(infrastructureBlockReason('spawnSync /usr/bin/qs EPERM'), 'host denied a fixture subprocess');
  assert.equal(infrastructureBlockReason('fixture assertion failed'), '');
});
