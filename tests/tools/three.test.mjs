import path from 'node:path';
import Module, {createRequire} from 'node:module';
import {test} from 'node:test';
import assert from 'node:assert/strict';
import {root, testRoot} from './common.mjs';
import {compare3D} from './three-common.mjs';

// The shim lives outside tests/; resolve its React peer from the test dependencies.
process.env.NODE_PATH = path.join(testRoot, 'node_modules');
Module._initPaths();
const require = createRequire(import.meta.url);
const shim = require(path.join(root, 'js/remotion-shim/three.js'));
const fiber = require(path.join(root, 'js/remotion-shim/fiber.js'));
const THREE = await import(path.join(testRoot, 'node_modules/three/build/three.module.js'));
const {check} = require(path.join(root, 'js/compiler/check.cjs'));

test('three subset colors match three.js color management bit for bit', () => {
  for (const value of ['#ff8800', '#abc', 'orange', 'rebeccapurple', 'rgb(12, 200, 99)', 'rgb(10%, 50%, 90%)', 'hsl(200, 80%, 40%)', 0x123456]) {
    assert.deepEqual(new shim.Color(value).toArray(), new THREE.Color(value).toArray(), String(value));
  }
  assert.deepEqual(new shim.Color().setHSL(0.3, 0.7, 0.5).toArray(), new THREE.Color().setHSL(0.3, 0.7, 0.5).toArray());
  assert.deepEqual(new shim.Color('#204060').lerp(new shim.Color('white'), 0.25).toArray(),
    new THREE.Color('#204060').lerp(new THREE.Color('white'), 0.25).toArray());
  assert.equal(new shim.Color('#ff8800').getHexString(), 'ff8800');
});

test('camera lookAt, Euler and quaternion math match three.js', () => {
  for (const [position, target, up] of [[[3, 4, 5], [0, 0, 0], [0, 1, 0]], [[-11, 7, 2], [1, 0, 0], [0.08, 0.99, 0]], [[0, 9, 0], [0, 0, 0], [0, 1, 0]]]) {
    const a = new shim.PerspectiveCamera(), b = new THREE.PerspectiveCamera();
    a.position.set(...position); b.position.set(...position);
    a.up.set(...up); b.up.set(...up);
    a.lookAt(...target); b.lookAt(...target);
    assert.deepEqual(a.quaternion.toArray(), b.quaternion.toArray());
    assert.deepEqual(a.rotation.toArray(), b.rotation.toArray());
  }
  for (const order of ['XYZ', 'YXZ', 'ZXY', 'ZYX', 'YZX', 'XZY']) {
    assert.deepEqual(new shim.Quaternion().setFromEuler(new shim.Euler(0.3, -1.2, 2.1, order)).toArray(),
      new THREE.Quaternion().setFromEuler(new THREE.Euler(0.3, -1.2, 2.1, order)).toArray(), order);
  }
});

const node = (type, props = {}, children = []) => ({type, props, children});
const state = (camera = {}) => ({size: {width: 320, height: 180}, dpr: [1, 2], flat: false, camera: fiber.__createCamera(camera, 320, 180)});

test('scene serialization resolves R3F defaults like three.js', () => {
  const scene = JSON.parse(fiber.__serialize(state({position: [0, 0, 6], fov: 40}), node('ms-three', {}, [
    node('color', {attach: 'background', args: ['#102030']}),
    node('fog', {attach: 'fog', args: ['#000', 2, 20]}),
    node('directionalLight', {intensity: 2}),
    node('mesh', {'position-x': 2, rotation: [0, Math.PI / 2, 0], scale: 3}, [
      node('boxGeometry', {args: [1, 2, 3]}),
      node('meshStandardMaterial', {color: 'red', transparent: true, opacity: 0.5}),
    ]),
  ])));
  assert.deepEqual(scene.background, new THREE.Color('#102030').toArray());
  assert.deepEqual(scene.fog, {type: 'linear', color: [0, 0, 0], near: 2, far: 20, density: 0});
  assert.equal(scene.camera.fov, 40);
  assert.deepEqual(scene.camera.position, [0, 0, 6]);
  const camera = new THREE.PerspectiveCamera(); camera.position.set(0, 0, 6); camera.lookAt(0, 0, 0);
  assert.deepEqual(scene.camera.quaternion, camera.quaternion.toArray());
  // Directional, hemisphere and spot lights default to Object3D.DEFAULT_UP like three.js.
  assert.deepEqual(scene.objects[0].position, [0, 1, 0]);
  const [mesh] = scene.objects.slice(1);
  assert.deepEqual(mesh.position, [2, 0, 0]);
  assert.deepEqual(mesh.scale, [3, 3, 3]);
  assert.deepEqual(mesh.quaternion, new THREE.Quaternion().setFromEuler(new THREE.Euler(0, Math.PI / 2, 0)).toArray());
  assert.deepEqual(mesh.geometry, {type: 'box', args: [1, 2, 3]});
  const material = new THREE.MeshStandardMaterial({color: 'red'});
  assert.equal(mesh.material.roughness, material.roughness);
  assert.equal(mesh.material.metalness, material.metalness);
  assert.equal(mesh.material.opacity, 0.5);
  assert.equal(mesh.material.transparent, true);
  assert.deepEqual(mesh.material.color, material.color.toArray());
  assert.deepEqual(mesh.material.specular, new THREE.MeshPhongMaterial().specular.toArray());
});

test('scene serialization rejects unsupported three.js features', () => {
  const fails = (children, pattern) => assert.throws(() => fiber.__serialize(state(), node('ms-three', {}, children)), pattern);
  fails([node('mesh', {}, [node('boxGeometry'), node('meshStandardMaterial', {map: {}})])], /property map is not supported/);
  fails([node('mesh', {geometry: {}}, [node('boxGeometry')])], /property geometry is not supported/);
  fails([node('lineSegments')], /<lineSegments> is not supported/);
  fails([node('boxGeometry')], /must be a direct child of <mesh>/);
  fails([node('directionalLight', {target: {}})], /Light targets are not supported/);
  fails([node('mesh', {position: [0, Number.NaN, 0]}, [node('boxGeometry')])], /finite/);
  assert.throws(() => fiber.useLoader(class {}, 'x.glb'), /USDLoader/);
  assert.equal(fiber.useLoader(require(path.join(root, 'js/remotion-shim/usd-loader.js')).USDLoader, 'static:a.usdz').__msModel, 'static:a.usdz');
});

test('3D gate counts changed pixels, large deltas and PSNR', () => {
  const image = fill => ({width: 10, height: 10, data: Buffer.alloc(400, fill)});
  const gate = {maxChangedRatio: 0.04, largeDelta: 8, maxLargeDeltaRatio: 0.003, minPSNR: 48};
  assert.equal(compare3D(image(10), image(10), gate).metrics.pass, true);
  const one = image(10); one.data[0] = 11;
  assert.deepEqual({...compare3D(image(10), one, gate).metrics, psnr: undefined},
    {pixels: 100, changedRatio: 0.01, largeDeltaRatio: 0, maxDelta: 1, psnr: undefined, pass: true});
  const large = image(10); large.data[0] = 60;
  assert.equal(compare3D(image(10), large, gate).metrics.pass, false);
  assert.throws(() => compare3D(image(1), {width: 5, height: 20, data: Buffer.alloc(400)}, gate), /dimensions/);
});

test('3D fixtures type check against the MotionSwift three subset', () => {
  assert.deepEqual(check(path.join(testRoot, 'three'), 'src/index.ts'), []);
});
