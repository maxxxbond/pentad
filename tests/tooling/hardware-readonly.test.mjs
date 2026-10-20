import assert from 'node:assert/strict';
import test from 'node:test';
import { classifyRuntimeErrors } from './hardware-readonly.mjs';

test('classifies Qt Connections handlers with no matching target signal as runtime errors', () => {
  const warning = 'Detected function "onBackendChanged" in Connections element. This is probably intended to be a signal handler but no signal of the target matches the name.';
  assert.deepEqual(classifyRuntimeErrors(warning), ['qml-connections-signal-mismatch']);
});

test('does not treat legitimate optional hardware unavailability as a runtime error', () => {
  const sample = 'PENTAD_HARDWARE_READONLY {"services":{"power":{"profileAvailable":true,"batteryAvailable":false},"desktop":{"telemetryStatus":"unavailable"}}}';
  assert.deepEqual(classifyRuntimeErrors(sample), []);
});
