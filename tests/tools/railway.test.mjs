import assert from 'node:assert/strict';
import fs from 'node:fs';
import crypto from 'node:crypto';
import path from 'node:path';
import {test} from 'node:test';
import {createRequire} from 'node:module';
import {buildSync} from 'esbuild';
import {root} from './common.mjs';
import {loadPortable, vendorInfo} from './portable.mjs';

const project = path.join(root, 'Examples/MotionShowcase/Railway');
const {outputFiles} = buildSync({entryPoints: [path.join(project, 'route.ts')], bundle: true, write: false, format: 'esm'});
const {
  journey,
  journeyFrame,
  durationInFrames,
  leadIn,
  rideFrames,
  loopEnd,
  route,
  project: projectPoint,
  stations,
  stationDistances,
  totalDistance,
} = await import('data:text/javascript;base64,' + Buffer.from(outputFiles[0].text).toString('base64'));

test('Yamanote route visits all 30 stations clockwise and closes at Tokyo', () => {
  assert.deepEqual(stations.map(x => x.name), [
    'Tokyo', 'Yurakucho', 'Shimbashi', 'Hamamatsucho', 'Tamachi', 'Takanawa Gateway',
    'Shinagawa', 'Osaki', 'Gotanda', 'Meguro', 'Ebisu', 'Shibuya', 'Harajuku', 'Yoyogi',
    'Shinjuku', 'Shin-Ōkubo', 'Takadanobaba', 'Mejiro', 'Ikebukuro', 'Otsuka', 'Sugamo',
    'Komagome', 'Tabata', 'Nishi-Nippori', 'Nippori', 'Uguisudani', 'Ueno', 'Okachimachi', 'Akihabara', 'Kanda',
  ]);
  assert.equal(new Set(stations.map(x => x.id)).size, 30);
  assert(stations.every(x => x.localName && x.id > 0));
  assert(stationDistances.every((value, index) => !index || value > stationDistances[index - 1]));
  assert.deepEqual(route[0], stations[0].point);
  assert.deepEqual(route.at(-1), stations[0].point);
  assert(stationDistances.at(-1) < totalDistance, 'Kanda → Tokyo is part of the journey');
  assert.deepEqual(projectPoint([139.685, 35.742]), [460, 158]);
});

test('train moves continuously through all 30 stations without stopping and returns to Tokyo', () => {
  assert.equal(loopEnd, leadIn + rideFrames);
  assert.equal(durationInFrames, 1500);
  const startState = journeyFrame(leadIn);
  assert.equal(startState.stopped, true);
  assert.equal(startState.progress, 0);
  assert.deepEqual(startState.point, stations[0].point);

  const visited = new Set([0]);
  let previousProgress = 0;
  let previousIndex = 0;
  for (let frame = leadIn + 1; frame < loopEnd; frame++) {
    const state = journeyFrame(frame);
    assert.equal(state.stopped, false, `train should not stop at frame ${frame}`);
    assert.ok(state.progress > previousProgress, `progress must strictly advance at frame ${frame}`);
    assert.ok(state.stationIndex >= previousIndex, `stations must advance monotonically at frame ${frame}`);
    visited.add(state.stationIndex);
    previousProgress = state.progress;
    previousIndex = state.stationIndex;
  }
  assert.equal(visited.size, 30, 'all 30 stations are passed during the continuous loop');

  for (const frame of [loopEnd, durationInFrames - 1, durationInFrames + 100]) {
    const state = journeyFrame(frame);
    assert.equal(state.complete, true);
    assert.equal(state.progress, 1);
    assert.equal(state.stopsVisited, 30);
    assert.deepEqual(state.point, stations[0].point);
  }
  assert.deepEqual(journeyFrame(-100).point, stations[0].point);
  assert.deepEqual(journeyFrame(750), journeyFrame(750), 'seeks are frame driven');
});

test('train follows the actual rail polyline with distance-based progress and clamped endpoints', () => {
  assert.deepEqual(journey(-1).point, route[0]);
  assert.deepEqual(journey(2).point, route.at(-1));
  for (const progress of [0.1, 0.25, 0.5, 0.9]) {
    const {point, distance} = journey(progress);
    assert.equal(distance, progress * totalDistance);
    const onTrack = route.slice(1).some((b, index) => {
      const a = route[index];
      return Math.abs(Math.hypot(point[0] - a[0], point[1] - a[1]) +
        Math.hypot(b[0] - point[0], b[1] - point[1]) - Math.hypot(b[0] - a[0], b[1] - a[1])) < 1e-8;
    });
    assert(onTrack, 'the train must stay on a railway segment, including bends');
  }
});

const cameraBundle = buildSync({entryPoints: [path.join(project, 'camera.ts')], bundle: true, write: false, format: 'esm'});
const {cameraFrame, overviewCenter, overviewZoom, followZoom} =
  await import('data:text/javascript;base64,' + Buffer.from(cameraBundle.outputFiles[0].text).toString('base64'));

test('camera opens on the full loop, zooms to the train, follows every leg and returns to overview', () => {
  assert.deepEqual(cameraFrame(0).center, overviewCenter);
  assert.equal(cameraFrame(0).zoom, overviewZoom);
  assert(cameraFrame(45).zoom > overviewZoom && cameraFrame(45).zoom < followZoom);
  for (let frame = 90; frame <= loopEnd; frame += 37) {
    const camera = cameraFrame(frame);
    assert.deepEqual(camera.center, journeyFrame(frame).coordinate);
    assert.equal(camera.zoom, followZoom);
  }
  assert.deepEqual(cameraFrame(durationInFrames - 1).center, overviewCenter);
  assert.equal(cameraFrame(durationInFrames - 1).zoom, overviewZoom);
  const before = cameraFrame(750);
  cameraFrame(1499); cameraFrame(0);
  assert.deepEqual(cameraFrame(750), before, 'camera seeks must be independent of previous frames');
});

test('bundled real map compiles for portable native playback and type checks', () => {
  const files = Object.fromEntries(['index.tsx', 'route.ts', 'map-data.ts', 'camera.ts']
    .map(file => [file, fs.readFileSync(path.join(project, file), 'utf8')]));
  const graph = JSON.parse(loadPortable().compile(JSON.stringify({files, entry: 'index.tsx', vendor: vendorInfo().specifiers})));
  assert.equal(graph.modules['index.tsx'].dependencies['./route'], 'route.ts');
  const {check} = createRequire(import.meta.url)('../../js/compiler/check.cjs');
  assert.deepEqual(check(project, 'index.tsx'), []);
  assert(fs.statSync(path.join(project, 'public/map.svg')).size > 10000);
});

test('prepared OSM artwork matches the source geometry, labels and recorded image hash', () => {
  const provenance = JSON.parse(fs.readFileSync(path.join(project, 'map-provenance.json')));
  assert.equal(provenance.engine, 'Remotion');
  for (const [file, expected] of Object.entries(provenance.files)) {
    const hash = crypto.createHash('sha256').update(fs.readFileSync(path.join(project, file))).digest('hex');
    assert.equal(hash, expected, `${file} changed; regenerate the railway basemap and review it`);
  }
});
