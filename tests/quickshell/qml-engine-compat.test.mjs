import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';

// The QML JavaScript engine is older than Node: it has no structuredClone and cannot parse
// object spread. Node tests pass either way, so guard the settings logic statically.
// (Found by running the settings fixtures in the isolated headless harness.)
const files = ['settings-bindings', 'settings-state', 'settings-shortcut', 'settings-color', 'settings-schema', 'pentads', 'widget-settings'];

test('settings logic modules avoid constructs the QML engine lacks', async () => {
  for (const name of files) {
    const source = await readFile(new URL(`../../quickshell/logic/${name}.mjs`, import.meta.url), 'utf8');
    const code = source.split('\n').filter(line => !line.trim().startsWith('//')).join('\n');
    assert.doesNotMatch(code, /structuredClone/, `${name}: structuredClone is undefined in QML`);
    assert.doesNotMatch(code, /\{\s*\.\.\.\s*[A-Za-z_]/, `${name}: object spread does not parse in QML`);
    assert.doesNotMatch(code, /,\s*\.\.\.[A-Za-z_]+\(/, `${name}: object spread of a call does not parse in QML`);
  }
});
