import assert from 'node:assert/strict';
import test from 'node:test';
import { readFile } from 'node:fs/promises';
import { validateManifest } from '../../quickshell/logic/plugin-manifest.mjs';
import { summarize } from '../../quickshell/logic/__NAME__.mjs';

test('__NAME__ manifest passes the v2 validator for its slot', async () => {
  const manifest = JSON.parse(await readFile(new URL('../../quickshell/widgets/__NAME__/manifest.json', import.meta.url), 'utf8'));
  const result = validateManifest(manifest, { slot: '__SLOT__' });
  assert.equal(result.ok, true, result.errors?.join('; '));
});

test('__NAME__ summary tolerates missing settings', () => {
  assert.equal(summarize(null), '');
  assert.equal(summarize({}), '');
});
