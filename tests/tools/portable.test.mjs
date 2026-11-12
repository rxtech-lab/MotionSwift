import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';
import {loadPortable, repo, runEditorCase, vendorInfo} from './portable.mjs';

const portable = loadPortable();
const fixtures = path.join(repo, 'tests/editor-fixtures');

for (const name of fs.readdirSync(fixtures).filter(entry => fs.statSync(path.join(fixtures, entry)).isDirectory())) {
  test(`editor fixture ${name}`, () => {
    const directory = path.join(fixtures, name);
    const result = runEditorCase(portable, directory);
    const errorFile = path.join(directory, 'error.txt');
    if (fs.existsSync(errorFile)) {
      assert.equal(result.error, fs.readFileSync(errorFile, 'utf8').trimEnd());
      return;
    }
    assert.equal(result.error, undefined);
    assert.equal(result.after, fs.readFileSync(path.join(directory, 'after.tsx'), 'utf8'));
    assert.equal(result.restored, result.before, 'the inverse operation must restore before.tsx byte for byte');
  });
}

function projectFiles(root) {
  const files = {};
  const visit = directory => {
    for (const entry of fs.readdirSync(directory, {withFileTypes: true})) {
      const full = path.join(directory, entry.name);
      if (entry.isDirectory()) visit(full);
      else if (/\.(tsx?|jsx?|json)$/.test(entry.name)) files[path.relative(root, full).split(path.sep).join('/')] = fs.readFileSync(full, 'utf8');
    }
  };
  visit(path.join(root, 'src'));
  visit(path.join(root, 'visuals'));
  return files;
}

test('portable compiler builds a stamped module graph with vendor imports', () => {
  const files = projectFiles(path.join(repo, 'tests/compositions'));
  const graph = JSON.parse(portable.compile(JSON.stringify({files, entry: 'src/index.ts', stamp: true, vendor: vendorInfo().specifiers})));
  assert.deepEqual(Object.keys(graph.modules).sort(), ['src/Root.tsx', 'src/index.ts', 'visuals/Boxes.tsx']);
  assert.equal(graph.modules['src/index.ts'].dependencies['./Root'], 'src/Root.tsx');
  assert.equal(graph.modules['src/Root.tsx'].dependencies.remotion, 'vendor:remotion');
  assert.equal(graph.modules['visuals/Boxes.tsx'].dependencies['@motionswift/remotion/jsx-runtime'], 'vendor:@motionswift/remotion/jsx-runtime');
  // Host elements and AbsoluteFill carry original line:column stamps; components do not.
  assert.match(graph.modules['visuals/Boxes.tsx'].code, /'data-ms-src': "visuals\/Boxes\.tsx:6:3"/);
  assert.match(graph.modules['visuals/Boxes.tsx'].code, /'data-ms-src': "visuals\/Boxes\.tsx:4:28"/);
  assert.doesNotMatch(graph.modules['src/Root.tsx'].code, /data-ms-src/);
  const unstamped = JSON.parse(portable.compile(JSON.stringify({files, entry: 'src/index.ts', stamp: false, vendor: vendorInfo().specifiers})));
  assert.doesNotMatch(unstamped.modules['visuals/Boxes.tsx'].code, /data-ms-src/);
});

test('portable compiler rejects packages outside the vendor graph with a sync hint', () => {
  const files = {'src/index.tsx': "import confetti from 'canvas-confetti';\nconfetti();\n"};
  assert.throws(() => portable.compile(JSON.stringify({files, entry: 'src/index.tsx', vendor: vendorInfo().specifiers})),
    /ms\/unsupported-package: canvas-confetti .*motionswift graph/);
});

test('portable compiler keeps subset diagnostics and dynamic import checks', () => {
  const vendor = vendorInfo().specifiers;
  assert.throws(() => portable.compile(JSON.stringify({files: {'a.tsx': 'export const A = () => <div className="x" />;'}, entry: 'a.tsx', vendor})),
    /ms\/no-classname/);
  assert.throws(() => portable.compile(JSON.stringify({files: {'a.ts': "import('./b');"}, entry: 'a.ts', vendor})),
    /Dynamic import/);
  assert.throws(() => portable.compile(JSON.stringify({files: {'a.ts': 'const = 1;'}, entry: 'a.ts', vendor})), /a\.ts: .*\(1:7\)/);
});

test('style classification drives which properties the editor may change', () => {
  const source = fs.readFileSync(path.join(fixtures, 'refuse-animated/before.tsx'), 'utf8');
  const {properties} = JSON.parse(portable.styles(source, 'src/Title.tsx:5:10'));
  assert.deepEqual(properties.map(({key, kind}) => [key, kind]), [['position', 'static'], ['left', 'animated']]);
});

test('timeline metadata edits preserve stamps and undo byte exactly', () => {
  const before = 'export const Card = () => <div style={{left: 20, opacity: 1}} />;\n';
  const src = 'a.tsx:1:27';
  const value = {from: 5, duration: 30, keyframes: {left: [
    {frame: 0, value: 20, easing: 'hold'}, {frame: 15, value: 50, easing: 'linear'},
  ]}};
  const edit = JSON.parse(portable.edit(before, JSON.stringify({op: 'setTimeline', src, key: 'timeline', value})));
  assert.equal(JSON.parse(portable.timeline(edit.source, 'a.tsx'))[0].src, src);
  assert.equal(JSON.parse(portable.edit(edit.source, JSON.stringify(edit.inverse))).source, before);
  const updated = JSON.parse(portable.edit(edit.source, JSON.stringify({op: 'setTimeline', src, key: 'timeline', value: {...value, from: 10}})));
  assert.equal(JSON.parse(portable.edit(updated.source, JSON.stringify(updated.inverse))).source, edit.source);
});

test('timeline index resolves literal Sequence offsets and protects dynamic timing', () => {
  const source = `export const Scene = () => <Sequence from={15} durationInFrames={50}>
  <Sequence from={5}><div style={{left: 0}} /></Sequence>
  <Sequence from={dynamic}><span style={{opacity: 1}} /></Sequence>
</Sequence>;`;
  const tracks = JSON.parse(portable.timeline(source, 'a.tsx'));
  assert.equal(tracks[0].offset, 20);
  assert.equal(tracks[0].limit, 65);
  assert.equal(tracks[0].owner, 'Scene');
  assert.match(tracks[1].reason, /Computed Sequence/);
});

test('timeline refuses to replace code animations, invalid frames, or spread styles', () => {
  const src = 'a.tsx:1:17';
  for (const style of ['{left: interpolate(frame, [0, 10], [0, 20])}', '{...other, left: 10}']) {
    const source = `const A = () => <div style={${style}} />;`;
    const value = {from: 0, duration: null, keyframes: {left: [{frame: 0, value: 50, easing: 'linear'}]}};
    assert.throws(() => portable.edit(source, JSON.stringify({op: 'setTimeline', src, key: 'timeline', value})), /refused:/);
  }
  const source = 'const A = () => <div style={{left: 0}} />;';
  const value = {from: 0, duration: 20, keyframes: {left: [{frame: -1, value: 50, easing: 'linear'}]}};
  assert.throws(() => portable.edit(source, JSON.stringify({op: 'setTimeline', src, key: 'timeline', value})), /Invalid keyframe/);
});
