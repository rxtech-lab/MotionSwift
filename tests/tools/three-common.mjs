// Shared configuration for the 3D (ThreeCanvas) fixtures: Remotion renders three.js through Chrome's
// ANGLE/Metal WebGL, MotionSwift through its native Metal renderer. Same sources, same assets.
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import {bundle} from '@remotion/bundler';
import {browserLock, browserOptions} from './browser.mjs';
import {testRoot, readJSON} from './common.mjs';

export const threeManifest = readJSON(path.join(testRoot, 'three/fixtures.json'));
export const threeProject = path.join(testRoot, threeManifest.project);
export const threeGoldens = path.join(testRoot, 'golden/three');
for (const fixture of threeManifest.fixtures) {
  if (!/^three\/[\w-]+$/.test(fixture.id) || !fixture.frames.every(Number.isInteger)) throw Error('Invalid 3D fixture: ' + fixture.id);
}

export const sha256 = data => crypto.createHash('sha256').update(data).digest('hex');
/** Hash of every source and asset the 3D fixtures read (src/, public/, tools/). */
export function threeSourceHash() {
  const hash = crypto.createHash('sha256');
  const walk = directory => fs.readdirSync(directory, {withFileTypes: true})
    .sort((a, b) => a.name.localeCompare(b.name, 'en')).forEach(entry => {
      if (entry.name.startsWith('.') || entry.name === 'node_modules') return;
      const file = path.join(directory, entry.name);
      if (entry.isDirectory()) walk(file);
      else { hash.update(path.relative(threeProject, file)); hash.update(fs.readFileSync(file)); }
    });
  for (const name of ['src', 'public', 'tools']) walk(path.join(threeProject, name));
  return hash.digest('hex');
}

const version = name => readJSON(path.join(testRoot, 'node_modules', name, 'package.json')).version;
/** Everything that changes the Remotion side of the comparison. */
export function threePins() {
  return {
    remotion: version('remotion'), remotionThree: version('@remotion/three'), three: version('three'),
    fiber: version('@react-three/fiber'), browser: browserLock, chromiumOptions: threeManifest.chromiumOptions,
    platform: process.platform, arch: process.arch,
    manifestSha256: sha256(JSON.stringify({fixtures: threeManifest.fixtures, chromiumOptions: threeManifest.chromiumOptions})),
    sourceSha256: threeSourceHash(),
  };
}

export async function threeBrowser() {
  return {...await browserOptions(), chromiumOptions: threeManifest.chromiumOptions};
}
export function bundleThree() {
  return bundle({entryPoint: path.join(threeProject, threeManifest.entryPoint), publicDir: path.join(threeProject, threeManifest.publicDir)});
}

/**
 * Cross-engine 3D metrics. Pixels count as changed when any RGBA channel differs; large deltas
 * exceed `largeDelta` levels. PSNR is over RGB. Exact equality is not expected between ANGLE's
 * translated GLSL and the native Metal port: interiors match, sub-pixel edges and derivative-based
 * flat normals can round differently.
 */
export function compare3D(expected, actual, gate = threeManifest.gate) {
  if (expected.width !== actual.width || expected.height !== actual.height) throw Error('Image dimensions differ');
  const pixels = expected.width * expected.height;
  let changed = 0, large = 0, max = 0, squared = 0;
  const diff = Buffer.alloc(pixels * 4);
  for (let pixel = 0; pixel < pixels; pixel++) {
    const offset = pixel * 4;
    let delta = 0;
    for (let channel = 0; channel < 4; channel++) {
      const d = Math.abs(expected.data[offset + channel] - actual.data[offset + channel]);
      delta = Math.max(delta, d);
      if (channel < 3) squared += d * d;
    }
    if (delta) changed++;
    if (delta > gate.largeDelta) large++;
    max = Math.max(max, delta);
    const value = delta > gate.largeDelta ? 255 : delta * 24;
    diff.set(delta ? [value, delta > gate.largeDelta ? 0 : value, delta > gate.largeDelta ? 64 : value, 255]
      : [actual.data[offset] / 4, actual.data[offset + 1] / 4, actual.data[offset + 2] / 4, 255], offset);
  }
  const mse = squared / (pixels * 3);
  const psnr = mse === 0 ? Infinity : 10 * Math.log10(255 * 255 / mse);
  const metrics = {pixels, changedRatio: changed / pixels, largeDeltaRatio: large / pixels, maxDelta: max,
    psnr: Number.isFinite(psnr) ? Number(psnr.toFixed(3)) : 'inf'};
  metrics.pass = metrics.changedRatio <= gate.maxChangedRatio && metrics.largeDeltaRatio <= gate.maxLargeDeltaRatio
    && psnr >= gate.minPSNR;
  return {metrics, diff};
}
