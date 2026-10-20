import assert from 'node:assert/strict';
import { readdir, readFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import test from 'node:test';

const repo = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');

test('shell and overview components are registered in their directory import manifests', async () => {
  for (const relative of ['quickshell/shell', 'quickshell/features/overview']) {
    const directory = path.join(repo, relative);
    const manifest = await readFile(path.join(directory, 'qmldir'), 'utf8');
    const declarations = [...manifest.matchAll(/^(\w+)\s+\d+\.\d+\s+(\S+\.qml)\s*$/gm)];
    const files = (await readdir(directory)).filter(file => file.endsWith('.qml')).sort();
    assert.deepEqual(declarations.map(match => match[2]).sort(), files,
      `Every ${relative} component must be exported for directory imports to resolve it`);
    for (const [, type, file] of declarations) assert.equal(type, path.basename(file, '.qml'));
  }
});

function stripCommentsAndStrings(source) {
  let output = '';
  let state = 'code';
  for (let index = 0; index < source.length; index++) {
    const char = source[index];
    const next = source[index + 1];
    if (state === 'code') {
      if (char === '/' && next === '/') { output += '  '; index++; state = 'line'; }
      else if (char === '/' && next === '*') { output += '  '; index++; state = 'block'; }
      else if (char === '"' || char === "'" || char === '`') { output += ' '; state = char; }
      else output += char;
    } else if (state === 'line') {
      if (char === '\n') { output += '\n'; state = 'code'; }
      else output += ' ';
    } else if (state === 'block') {
      if (char === '*' && next === '/') { output += '  '; index++; state = 'code'; }
      else output += char === '\n' ? '\n' : ' ';
    } else if (char === '\\') {
      output += ' ';
      if (next !== undefined) { output += next === '\n' ? '\n' : ' '; index++; }
    } else if (char === state) {
      output += ' ';
      state = 'code';
    } else output += char === '\n' ? '\n' : ' ';
  }
  return output;
}

function selfInstantiation(file, source) {
  const type = path.basename(file, '.qml');
  return new RegExp(`\\b${type}\\s*\\{`).test(stripCommentsAndStrings(source));
}

async function qmlFiles(directory) {
  const files = [];
  for (const entry of await readdir(directory, { withFileTypes: true })) {
    const fullPath = path.join(directory, entry.name);
    if (entry.isDirectory()) files.push(...await qmlFiles(fullPath));
    else if (entry.isFile() && entry.name.endsWith('.qml')) files.push(fullPath);
  }
  return files;
}

test('QML components avoid static self-instantiation', async () => {
  assert.equal(selfInstantiation('MenuLevel.qml', 'Component { MenuLevel {} }'), true);
  assert.equal(selfInstantiation('MenuLevel.qml', 'Qt.createComponent("MenuLevel.qml")'), false);

  const recursive = [];
  for (const file of await qmlFiles(path.join(repo, 'quickshell'))) {
    if (selfInstantiation(file, await readFile(file, 'utf8'))) recursive.push(path.relative(repo, file));
  }
  assert.deepEqual(recursive, [], `static self-instantiation can fail QML type registration: ${recursive.join(', ')}`);
});
