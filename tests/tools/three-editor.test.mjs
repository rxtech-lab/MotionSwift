import assert from 'node:assert/strict';
import test from 'node:test';
import Module, {createRequire} from 'node:module';
import {loadPortable} from './portable.mjs';

const portable = loadPortable();
const require = createRequire(import.meta.url);
const fields = require('../../js/remotion-shim/three-edit.js');
const src = 'scene.tsx:1:17';
const edit = (source, key, value) => JSON.parse(portable.edit(source, JSON.stringify({op: 'setStyle', src, key, value})));
const summary = source => JSON.parse(portable.styles(source, src));

test('3D source edits preserve vectors, materials, camera siblings and byte-exact undo', () => {
  for (const [source, key, value, expected] of [
    ['const A = () => <mesh position={[1, -2, 3]} />;', 'positionY', 4, 'position={[1, 4, 3]}'],
    ['const A = () => <mesh scale={2} />;', 'scaleX', 4, 'scale={[4,2,2]}'],
    ['const A = () => <mesh />;', 'positionZ', -5, 'position={[0,0,-5]}'],
    ['const A = () => <mesh position-x={2} />;', 'positionX', 4, 'position-x={4}'],
    ['const A = () => <meshStandardMaterial color="#ff0000" roughness={0.3} />;', 'color', '#00ff00', 'color="#00ff00"'],
    ['const A = () => <pointLight intensity={2} />;', 'intensity', 5, 'intensity={5}'],
    ['const A = () => <ThreeCanvas camera={{position: [1, 2, 3], fov: 50}} />;', 'cameraPositionZ', 8, 'position: [1, 2, 8], fov: 50'],
  ]) {
    assert.equal(summary(source).domain, 'three');
    const changed = edit(source, key, value);
    assert.ok(changed.source.includes(expected), changed.source);
    assert.equal(JSON.parse(portable.edit(changed.source, JSON.stringify(changed.inverse))).source, source);
  }
});

test('3D editing protects expressions, spreads, constructor args and quaternion rotations', () => {
  for (const [source, key] of [
    ['const A = () => <mesh position={[frame * 2, 0, 0]} />;', 'positionX'],
    ['const A = () => <mesh position={path} />;', 'positionX'],
    ['const A = () => <mesh position={[1,2,3]} {...props} />;', 'positionX'],
    ['const A = () => <pointLight args={["red", 4]} />;', 'intensity'],
    ['const A = () => <mesh quaternion={[0,0,0,1]} />;', 'rotationX'],
    ['const A = () => <ThreeCanvas />;', 'cameraFov'],
  ]) assert.throws(() => edit(source, key, 3), /refused:/, source);
  assert.throws(() => edit('const A = () => <meshStandardMaterial />;', 'roughness', 5), /supported range/);
});

test('3D keyframes animate R3F props and keep geometry attachments out of object tracks', () => {
  const source = 'const A = () => <mesh position={[1,2,3]}><boxGeometry /><meshStandardMaterial roughness={0.5}/></mesh>;';
  const tracks = JSON.parse(portable.timeline(source, 'scene.tsx'));
  assert.deepEqual(tracks.map(t => t.label), ['mesh', 'meshStandardMaterial']);
  const timing = {from: 3, duration: 20, keyframes: {positionX: [{frame: 0, value: 1, easing: 'linear'}, {frame: 10, value: 5, easing: 'hold'}]}};
  const changed = JSON.parse(portable.edit(source, JSON.stringify({op: 'setTimeline', src, key: 'timeline', value: timing})));
  assert.deepEqual(JSON.parse(portable.timeline(changed.source, 'scene.tsx'))[0].keyframes, timing.keyframes);
  const props = {position: [1,2,3]};
  fields.animate('mesh', props, 'positionX', 5);
  assert.deepEqual(props, {position: [1,2,3], 'position-x': 5});
  assert.deepEqual(fields.values('pointLight', {intensity: 4}).intensity, 4);
  const camera = {camera: {position: [0,0,8], fov: 50}};
  fields.animate('ThreeCanvas', camera, 'cameraPositionX', 2);
  assert.deepEqual(camera.camera, {position: [2,0,8], fov: 50});
});

test('editor camera keyframes include rotation and override code-aimed cameras', () => {
  const props = {camera: {position: [0, 0, 8], fov: 50}};
  fields.animate('ThreeCanvas', props, 'cameraRotationY', 0.5);
  assert.deepEqual(props.camera, {position: [0, 0, 8], fov: 50, rotation: [0, 0.5, 0]});
  // The shim resolves its React peer from the test dependencies.
  process.env.NODE_PATH = new URL('../node_modules', import.meta.url).pathname;
  Module._initPaths();
  const fiber = require('../../js/remotion-shim/fiber.js');
  const camera = fiber.__createCamera({}, 160, 90);
  // A camera rig aims the camera in an effect; editor keyframes still win at serialization.
  camera.position.set(9, 9, 9);
  camera.lookAt(0, 0, 0);
  const state = {camera, size: {width: 160, height: 90}, dpr: [1, 2], flat: false};
  const node = {type: 'ms-three', props: {'data-ms-src': src}, children: [
    {type: 'mesh', props: {'data-ms-src': 'scene.tsx:2:3'}, children: [{type: 'boxGeometry', props: {}, children: []}]}]};
  const scene = JSON.parse(fiber.__serialize(state, node, {position: [1, 2, 3], rotation: [0, Math.PI / 2, 0], fov: 40}));
  assert.deepEqual(scene.camera.position, [1, 2, 3]);
  assert.equal(scene.camera.fov, 40);
  assert.equal(scene.objects[0].source, 'scene.tsx:2:3');
  const canvas = scene.editor.find(e => e.type === 'ThreeCanvas').properties;
  assert.ok(Math.abs(canvas.cameraRotationY - Math.PI / 2) < 1e-9);
  assert.equal(JSON.parse(fiber.__serialize(state, {type: 'ms-three', props: {}, children: []})).objects.length, 0);
});

test('Add Camera writes an explicit camera that can be keyframed, with byte-exact undo', () => {
  for (const source of ['const A = () => <ThreeCanvas width={1} height={1} />;',
    'const A = () => <ThreeCanvas camera={{position: [0, 0, 11], fov: 50}} />;']) {
    assert.equal(summary(source).properties.find(p => p.key === 'cameraRotationX').kind, 'computed');
    const raw = 'camera={{position: [1, 2, 3], rotation: [0, 0.5, 0], fov: 45, near: 0.1, far: 200}}';
    const changed = JSON.parse(portable.edit(source, JSON.stringify({op: 'setThreeProperty', src, key: 'cameraFov', raw})));
    assert.ok(changed.source.includes(raw), changed.source);
    const properties = summary(changed.source).properties;
    assert.deepEqual(properties.find(p => p.key === 'cameraRotationY'), {key: 'cameraRotationY', kind: 'static', value: 0.5,
      raw: properties.find(p => p.key === 'cameraRotationY').raw});
    const timing = {from: 0, duration: null, keyframes: {cameraRotationY: [{frame: 0, value: 0.5, easing: 'linear'}]}};
    JSON.parse(portable.edit(changed.source, JSON.stringify({op: 'setTimeline', src, key: 'timeline', value: timing})));
    assert.equal(JSON.parse(portable.edit(changed.source, JSON.stringify(changed.inverse))).source, source);
  }
});

test('camera rig keys are detected and edited in place, inserted in order and undone byte-exactly', () => {
  const source = `const keys: CameraKey[] = [
  {frame: 0, position: [0, 2, 9], target: [0, 0, 0], fov: 50},
  {frame: 60, position: [4, 1, 6], target: [0, 1, 0], fov: 40, roll: 0.1},
];
const A = () => <ThreeCanvas><CameraRig frame={frame} keys={keys} /></ThreeCanvas>;`;
  const [rig] = JSON.parse(portable.cameraRigs(source, 'scene.tsx'));
  assert.equal(rig.src, 'scene.tsx:1:27');
  assert.deepEqual(rig.keys.map(k => k.frame), [0, 60]);
  assert.equal(rig.keys[1].roll, 0.1);
  const run = (text, value) => JSON.parse(portable.edit(text, JSON.stringify({op: 'setCameraRigKey', src: rig.src, key: 'cameraRig', value})));
  const moved = run(source, {frame: 60, position: [1, 2, 3], target: [0, 0.5, 0], fov: 35, roll: 0.2});
  assert.ok(moved.source.includes('{frame: 60, position: [1, 2, 3], target: [0, 0.5, 0], fov: 35, roll: 0.2}'), moved.source);
  const inserted = run(source, {frame: 30, position: [2, 2, 2], target: [0, 0, 0], fov: 45, roll: 0.05});
  assert.deepEqual(JSON.parse(portable.cameraRigs(inserted.source, 'scene.tsx'))[0].keys.map(k => k.frame), [0, 30, 60]);
  assert.ok(inserted.source.includes('},\n  {frame: 30, position: [2, 2, 2], target: [0, 0, 0], fov: 45, roll: 0.05},\n  {frame: 60'));
  const deleted = run(inserted.source, {frame: 30, delete: true});
  assert.equal(deleted.source, source);
  assert.throws(() => run(source, {frame: 0, delete: true}), /at least two keys/);
  for (const change of [moved, inserted]) {
    assert.equal(JSON.parse(portable.edit(change.source, JSON.stringify(change.inverse))).source, source);
  }
  assert.deepEqual(JSON.parse(portable.cameraRigs('const k = [{frame: f, position: [0,0,0], target: [0,0,0], fov: 1}, {frame: 2, position: [0,0,0], target: [0,0,0], fov: 1}];\nconst A = () => <R keys={k} />;', 'a.tsx')), []);
});
