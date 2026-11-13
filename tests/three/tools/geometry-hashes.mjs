// Writes tests/three/geometry-hashes.json: SHA-256 of three.js geometry buffers (float32 positions,
// float32 normals, uint32 indices) that the native Swift generators must reproduce bit for bit.
// Run after a three.js upgrade: node tests/three/tools/geometry-hashes.mjs
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
const here = path.dirname(fileURLToPath(import.meta.url));
const THREE = await import(path.join(here, '../../node_modules/three/build/three.module.js'));
const cases = [
  ['box', []], ['box', [2, 1.5, 0.7, 3, 2, 4]], ['sphere', []], ['sphere', [0.6, 24, 12, 0.3, 4, 0.2, 2]],
  ['plane', [3, 2, 4, 3]], ['cylinder', []], ['cylinder', [0.4, 0.6, 1.1, 24, 3, 0, 0.5, 4]], ['cylinder', [1, 1, 2, 8, 1, 1]],
  ['cone', [0.6, 1.1, 24]], ['torus', []], ['torus', [0.45, 0.18, 16, 48, 5]], ['torusKnot', []],
  ['torusKnot', [1.2, 0.38, 220, 28, 2, 3]], ['circle', [0.6, 6]], ['ring', [0.3, 0.6, 32, 2]],
  ['icosahedron', [1, 0]], ['icosahedron', [0.6, 2]], ['octahedron', [0.6]], ['tetrahedron', [0.65, 1]], ['dodecahedron', [0.6]],
];
const classes = {box: 'BoxGeometry', sphere: 'SphereGeometry', plane: 'PlaneGeometry', cylinder: 'CylinderGeometry',
  cone: 'ConeGeometry', torus: 'TorusGeometry', torusKnot: 'TorusKnotGeometry', circle: 'CircleGeometry', ring: 'RingGeometry',
  icosahedron: 'IcosahedronGeometry', octahedron: 'OctahedronGeometry', tetrahedron: 'TetrahedronGeometry', dodecahedron: 'DodecahedronGeometry'};
const result = cases.map(([type, args]) => {
  // R3F passes boolean args (openEnded) as booleans; MotionSwift serializes them as 0/1.
  const constructorArgs = args.map((value, index) => (type === 'cylinder' && index === 5) || (type === 'cone' && index === 4) ? !!value : value);
  const geometry = new THREE[classes[type]](...constructorArgs);
  const hash = crypto.createHash('sha256');
  const bytes = array => Buffer.from(array.buffer, array.byteOffset, array.byteLength);
  hash.update(bytes(geometry.attributes.position.array));
  hash.update(bytes(geometry.attributes.normal.array));
  if (geometry.index) hash.update(bytes(Uint32Array.from(geometry.index.array)));
  return {type, args, vertices: geometry.attributes.position.count, indices: geometry.index?.count ?? null, sha256: hash.digest('hex')};
});
fs.writeFileSync(path.join(here, '../geometry-hashes.json'), JSON.stringify({three: THREE.REVISION, geometries: result}, null, 2) + '\n');
console.log(`Wrote ${result.length} geometry hashes for three r${THREE.REVISION}`);
