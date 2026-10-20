#!/usr/bin/env node
import { mkdir, mkdtemp, readFile, readdir, rename, rm, stat, writeFile, copyFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { validateManifest } from '../quickshell/logic/plugin-manifest.mjs';

const repo = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const args = process.argv.slice(2);
if (args.length && (args.length !== 2 || args[0] !== '--output')) {
  console.error('Usage: node scripts/build-quickshell.mjs [--output DIRECTORY]');
  process.exit(2);
}
const output = args.length ? path.resolve(args[1]) : path.join(repo, 'dist/quickshell');
const requiredDirectories = [
  'quickshell', 'quickshell/assets', 'quickshell/catalogs',
  'quickshell/defaults', 'LICENSES', 'tools',
];
const requiredFiles = ['LICENSE'];

async function isDirectory(file) {
  try { return (await stat(file)).isDirectory(); } catch { return false; }
}

async function copyTree(source, destination) {
  await mkdir(destination, { recursive: true });
  for (const entry of await readdir(source, { withFileTypes: true })) {
    if (entry.name === '__pycache__' || entry.name.endsWith('.pyc')) continue;
    if (entry.isSymbolicLink()) continue;
    const from = path.join(source, entry.name);
    const to = path.join(destination, entry.name);
    if (entry.isDirectory()) await copyTree(from, to);
    else if (entry.isFile()) {
      await mkdir(path.dirname(to), { recursive: true });
      await copyFile(from, to);
    }
  }
}

async function findManifests(directory) {
  const found = [];
  for (const entry of await readdir(directory, { withFileTypes: true })) {
    if (entry.isSymbolicLink()) continue;
    const fullPath = path.join(directory, entry.name);
    if (entry.isDirectory()) found.push(...await findManifests(fullPath));
    else if (entry.isFile() && entry.name === 'manifest.json') found.push(fullPath);
  }
  return found.sort();
}

const missing = [];
for (const relative of requiredDirectories) if (!(await isDirectory(path.join(repo, relative)))) missing.push(relative);
for (const relative of requiredFiles) {
  try { await stat(path.join(repo, relative)); } catch { missing.push(relative); }
}
if (missing.length) {
  console.error(`Quickshell build blocked; missing source paths: ${missing.join(', ')}`);
  process.exitCode = 1;
} else {
  const manifests = [];
  const widgetDirectory = path.join(repo, 'quickshell/widgets');
  const widgetManifests = await isDirectory(widgetDirectory) ? await findManifests(widgetDirectory) : [];
  for (const file of widgetManifests) {
    const manifest = JSON.parse(await readFile(file, 'utf8'));
    const validated = validateManifest(manifest);
    if (!validated.ok) throw new Error(`Invalid built-in ${path.relative(repo, file)}: ${validated.errors.join('; ')}`);
    for (const entry of [manifest.entry, manifest.controller].filter(Boolean)) {
      const source = path.join(path.dirname(file), entry);
      if (!(await stat(source)).isFile()) throw new Error(`Missing QML entry: ${source}`);
    }
    manifests.push({ id: manifest.id, path: path.relative(path.join(repo, 'quickshell'), file).replaceAll(path.sep, '/') });
  }
  manifests.sort((a, b) => (a.id < b.id ? -1 : a.id > b.id ? 1 : a.path < b.path ? -1 : a.path > b.path ? 1 : 0));
  if (new Set(manifests.map(({ id }) => id)).size !== manifests.length) throw new Error('Built-in widget manifest IDs must be unique.');

  await mkdir(path.dirname(output), { recursive: true });
  // Staged next to the output so the swap is a rename: a running shell never sees a missing tree.
  const staging = await mkdtemp(path.join(path.dirname(output), '.pentad-quickshell-build-'));
  const previous = `${staging}-old`;
  try {
    await copyTree(path.join(repo, 'quickshell'), staging);
    await copyTree(path.join(repo, 'tools'), path.join(staging, 'helpers'));
    await copyFile(path.join(repo, 'LICENSE'), path.join(staging, 'LICENSE'));
    await copyTree(path.join(repo, 'LICENSES'), path.join(staging, 'LICENSES'));
    await writeFile(path.join(staging, 'builtin-registry.json'), `${JSON.stringify(manifests, null, 2)}\n`);

    await rename(output, previous).catch(error => { if (error.code !== 'ENOENT') throw error; });
    await rename(staging, output);
    console.log(`Built ${output} (${manifests.length} built-in widgets)`);
  } finally {
    await rm(staging, { recursive: true, force: true });
    await rm(previous, { recursive: true, force: true });
  }
}
