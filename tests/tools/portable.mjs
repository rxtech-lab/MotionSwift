// Loads the generated portable resources the same way JavaScriptCore does: as plain scripts in
// a fresh global, without Node module APIs.
import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';
import {fileURLToPath} from 'node:url';

export const repo = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
export const resources = path.join(repo, 'Sources/MotionPortable/JavaScript');

export function loadPortable() {
  const context = vm.createContext({});
  vm.runInContext(fs.readFileSync(path.join(resources, 'portable.js'), 'utf8'), context);
  return context.MotionPortable;
}

export function vendorInfo() {
  return JSON.parse(fs.readFileSync(path.join(resources, 'vendor.json'), 'utf8'));
}

/** Applies a fixture case; returns {after, inverse, restored} or {error}. */
export function runEditorCase(portable, directory) {
  const before = fs.readFileSync(path.join(directory, 'before.tsx'), 'utf8');
  const op = fs.readFileSync(path.join(directory, 'op.json'), 'utf8');
  try {
    const result = JSON.parse(portable.edit(before, op));
    const restored = JSON.parse(portable.edit(result.source, JSON.stringify(result.inverse))).source;
    return {before, after: result.source, inverse: result.inverse, restored};
  } catch (error) {
    return {before, error: String(error.message)};
  }
}

// `node tests/tools/portable.mjs --update-editor-fixtures` writes after.tsx / error.txt for review.
if (process.argv[1] === fileURLToPath(import.meta.url) && process.argv.includes('--update-editor-fixtures')) {
  const portable = loadPortable();
  const root = path.join(repo, 'tests/editor-fixtures');
  for (const name of fs.readdirSync(root).filter(entry => fs.statSync(path.join(root, entry)).isDirectory()).sort()) {
    const result = runEditorCase(portable, path.join(root, name));
    for (const file of ['after.tsx', 'error.txt']) fs.rmSync(path.join(root, name, file), {force: true});
    if (result.error) fs.writeFileSync(path.join(root, name, 'error.txt'), result.error + '\n');
    else fs.writeFileSync(path.join(root, name, 'after.tsx'), result.after);
    console.log(`${name}: ${result.error ? 'error' : 'after'}`);
  }
}
