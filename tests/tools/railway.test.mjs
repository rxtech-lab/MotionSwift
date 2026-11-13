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
const {journey, route, project: projectPoint, stations, stationDistances, totalDistance} =
  await import('data:text/javascript;base64,' + Buffer.from(outputFiles[0].text).toString('base64'));

test('real Island Line route contains seven OSM stops in eastbound order on the track', () => {
  assert.deepEqual(stations.map(x => x.name), ['Sheung Wan', 'Central', 'Admiralty', 'Wan Chai', 'Causeway Bay', 'Tin Hau', 'Fortress Hill']);
  assert.equal(new Set(stations.map(x => x.id)).size, 7);
  assert(stations.every(x => x.localName && x.id > 0));
  assert(stationDistances.every((value, index) => !index || value > stationDistances[index - 1]));
  assert.deepEqual(route[0], stations[0].point);
  assert.deepEqual(route.at(-1), stations.at(-1).point);
  assert.equal(stationDistances.at(-1), totalDistance);
  // A known WGS84 origin pins projection orientation and registration to the basemap.
  assert.deepEqual(projectPoint([114.15, 22.291]), [40, 128]);
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
test('bundled real map compiles for portable native playback and type checks', () => {
  const files = Object.fromEntries(['index.tsx', 'route.ts', 'map-data.ts', 'basemap.ts']
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
