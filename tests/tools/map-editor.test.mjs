import assert from 'node:assert/strict';
import test from 'node:test';
import Module, {createRequire} from 'node:module';
import {loadPortable, vendorInfo} from './portable.mjs';

// The shim resolves react from the test dependencies, like the 3D tests.
process.env.NODE_PATH = new URL('../node_modules', import.meta.url).pathname;
Module._initPaths();

const portable = loadPortable();
const require = createRequire(import.meta.url);
const fields = require('../../js/remotion-shim/map-edit.js');
const src = 'map.tsx:1:17';
const edit = (source, key, value) => JSON.parse(portable.edit(source, JSON.stringify({op: 'setStyle', src, key, value})));
const summary = source => JSON.parse(portable.styles(source, src));
const undo = changed => JSON.parse(portable.edit(changed.source, JSON.stringify(changed.inverse))).source;

test('@motionswift/map is part of the vendor graph', () => {
  assert.ok(vendorInfo().specifiers.includes('@motionswift/map'));
});

test('map elements are stamped, tracked and classified as the map domain', () => {
  const source = 'const A = () => <MapView center={[114.16, 22.28]} zoom={13}><MapRoute from={[1, 2]} to={[3, 4]} />' +
    '<MapMarker coordinate={[5, 6]} label="Here" /></MapView>;';
  assert.match(portable.stamp(source, 'map.tsx'), /<MapView data-ms-src="map\.tsx:1:17"/);
  const tracks = JSON.parse(portable.timeline(source, 'map.tsx'));
  assert.deepEqual(tracks.map(track => track.label), ['MapView', 'MapRoute', 'MapMarker']);
  const view = summary(source);
  assert.equal(view.domain, 'map');
  assert.equal(view.type, 'MapView');
  const value = key => view.properties.find(property => property.key === key);
  assert.deepEqual([value('centerLongitude').value, value('centerLatitude').value, value('zoom').value], [114.16, 22.28, 13]);
  assert.equal(value('provider').kind, 'static');
  assert.equal(value('provider').value, 'openstreetmap');
});

test('map source edits rewrite camera, provider, route and marker literals with byte-exact undo', () => {
  for (const [source, key, value, expected] of [
    ['const A = () => <MapView center={[114.16, 22.28]} zoom={13} />;', 'centerLatitude', 22.3, 'center={[114.16, 22.3]}'],
    ['const A = () => <MapView zoom={13} />;', 'centerLongitude', 2.35, 'center={[2.35,0]}'],
    ['const A = () => <MapView zoom={13} />;', 'zoom', 15.5, 'zoom={15.5}'],
    ['const A = () => <MapView provider="openstreetmap" />;', 'provider', 'apple', 'provider="apple"'],
    ['const A = () => <MapView />;', 'mapStyle', 'dark', 'mapStyle="dark"'],
    ['const A = () => <MapMarker coordinate={[5, 6]} label="Here" />;', 'label', 'Say "hi"', 'label={"Say \\"hi\\""}'],
    ['const A = () => <MapView mapStyle={"standard"} />;', 'mapStyle', 'dark', 'mapStyle={"dark"}'],
    ['const A = () => <MapView />;', 'bearing', -30, 'bearing={-30}'],
    ['const A = () => <MapRoute from={[1, 2]} to={[3, 4]} />;', 'toLongitude', 3.5, 'to={[3.5, 4]}'],
    ['const A = () => <MapRoute from={[1, 2]} to={[3, 4]} mode="straight" />;', 'mode', 'railway', 'mode="railway"'],
    ['const A = () => <MapRoute from={[1, 2]} to={[3, 4]} />;', 'progress', 0.5, 'progress={0.5}'],
    ['const A = () => <MapMarker coordinate={[5, 6]} label="Here" />;', 'label', 'There', 'label="There"'],
    ['const A = () => <MapMarker coordinate={[5, 6]} />;', 'latitude', -7, 'coordinate={[5, -7]}'],
  ]) {
    const changed = edit(source, key, value);
    assert.ok(changed.source.includes(expected), `${key}: ${changed.source}`);
    assert.equal(changed.inverse.op, 'setMapProperty');
    assert.equal(undo(changed), source);
  }
});

test('map controls override code-controlled props with byte-exact undo while refusing invalid choices', () => {
  for (const [source, key, value, expected] of [
    ['const A = () => <MapView center={[lon, 22]} />;', 'centerLongitude', 1, 'center={[1, 22]}'],
    ['const A = () => <MapView center={home} />;', 'centerLatitude', 1, 'center={[0,1]}'],
    ['const A = () => <MapView zoom={interpolate(f, [0, 1], [3, 9])} />;', 'zoom', 1, 'zoom={1}'],
    ['const A = () => <MapView {...props} zoom={3} />;', 'provider', 'apple', '<MapView {...props} zoom={3} provider="apple" />'],
  ]) {
    const changed = edit(source, key, value);
    assert.ok(changed.source.includes(expected), `${key}: ${changed.source}`);
    assert.equal(undo(changed), source);
  }
  for (const [source, key, value, pattern] of [
    ['const A = () => <MapView zoom={3} {...props} />;', 'zoom', 5, /move \{\.\.\.spread\} before zoom/],
    ['const A = () => <MapView />;', 'zoom', 40, /between 0 and 22/],
    ['const A = () => <MapView />;', 'provider', 'bing', /must be one of/],
    ['const A = () => <MapRoute from={[1, 2]} to={[3, 4]} />;', 'mode', 'teleport', /must be one of/],
    ['const A = () => <MapRoute from={[1, 2]} to={[3, 4]} />;', 'color', 'tomato', /hex color/],
  ]) assert.throws(() => edit(source, key, value), pattern, `${key} in ${source}`);
});

test('map keyframes animate component props, including code-controlled cameras and route progress', () => {
  const source = 'const A = () => <MapView center={camera.center} zoom={camera.zoom}><MapRoute from={[1, 2]} to={[3, 4]} /></MapView>;';
  const timing = {from: 0, duration: null, keyframes: {
    zoom: [{frame: 0, value: 4, easing: 'linear'}, {frame: 60, value: 12, easing: 'linear'}],
    centerLongitude: [{frame: 0, value: 1, easing: 'linear'}, {frame: 60, value: 2, easing: 'linear'}],
  }};
  const changed = JSON.parse(portable.edit(source, JSON.stringify({op: 'setTimeline', src, key: 'timeline', value: timing})));
  assert.deepEqual(JSON.parse(portable.timeline(changed.source, 'map.tsx'))[0].keyframes, timing.keyframes);
  assert.equal(undo(changed), source);
  // A route without an authored progress prop still keyframes from its default.
  const route = JSON.parse(portable.timeline(source, 'map.tsx'))[1].src;
  const progress = {from: 0, duration: null, keyframes: {progress: [{frame: 0, value: 0, easing: 'linear'}, {frame: 30, value: 1, easing: 'linear'}]}};
  assert.doesNotThrow(() => portable.edit(source, JSON.stringify({op: 'setTimeline', src: route, key: 'timeline', value: progress})));
  assert.throws(() => portable.edit(source, JSON.stringify({
    op: 'setTimeline',
    src,
    key: 'timeline',
    value: {from: 0, duration: null, keyframes: {provider: [{frame: 0, value: 1, easing: 'linear'}]}},
  })), /refused/);

  const props = {center: [1, 2], zoom: 4};
  fields.animate('MapView', props, 'centerLatitude', 3);
  assert.deepEqual(props.center, [1, 3]);
  const empty = {};
  fields.animate('MapRoute', empty, 'toLatitude', 9);
  assert.deepEqual(empty.to, [0, 9]);
  assert.equal(fields.values('MapView', {zoom: 7}).zoom, 7);
  assert.equal(fields.values('MapView', {}).provider, 'openstreetmap');
});

test('map routes, projection and provider fallback are deterministic without a host', () => {
  const map = require('../../js/remotion-shim/map.js');
  const camera = {center: [0, 0], zoom: 1, width: 512, height: 512};
  assert.deepEqual(map.projectCoordinate([0, 0], camera), [256, 256]);
  const [x, y] = map.projectCoordinate([90, 0], camera);
  assert.ok(Math.abs(x - 384) < 1e-9 && Math.abs(y - 256) < 1e-9);
  // Bearing 90 heads east: east points up.
  const rotated = map.projectCoordinate([90, 0], {...camera, bearing: 90});
  assert.ok(Math.abs(rotated[0] - 256) < 1e-9 && Math.abs(rotated[1] - 128) < 1e-9, String(rotated));

  // Without the MotionSwift host, network modes draw straight lines and say so.
  const road = map.__routeGeometry('driving', [[0, 0], [10, 10]]);
  assert.match(road.status, /straight lines/);
  const line = map.__routeGeometry('straight', [[0, 0], [10, 0], [10, 10]]);
  assert.equal(line.status, null);
  assert.ok(line.coordinates.length > 100);
  const half = map.__routeAt(line, 0.5);
  assert.ok(half.coordinates.length < line.coordinates.length);
  assert.deepEqual(map.__routeAt(line, 1).head, line.coordinates.at(-1));
  const arc = map.__routeGeometry('arc', [[0, 0], [20, 0]]);
  assert.ok(arc.coordinates.some(([, latitude]) => Math.abs(latitude) > 1), 'arcs bend away from the straight line');

  assert.deepEqual([map.resolveProvider('apple', 'dark').provider, map.resolveProvider('apple', 'dark').style], ['openstreetmap', 'dark']);
  assert.match(map.resolveProvider('apple', 'standard').note, /Apple Maps/);
  assert.equal(map.resolveProvider('mapbox', 'satellite-v9').provider, 'openstreetmap');
  assert.equal(map.resolveProvider('openstreetmap', 'nope').style, 'standard');
  assert.match(map.resolveProvider('carto', 'voyager').note, /Unknown map provider/);
  globalThis.__ms_mapCapabilities = () => JSON.stringify({apple: true, mapbox: true});
  try {
    assert.deepEqual([map.resolveProvider('apple', 'hybrid').provider, map.resolveProvider('apple', 'hybrid').note], ['apple', null]);
  } finally { delete globalThis.__ms_mapCapabilities; }
});

test('MapView renders tiles, overlays, attribution and editor metadata', async () => {
  const React = require('react');
  const {renderToStaticMarkup} = require('react-dom/server');
  const shim = require('../../js/remotion-shim/index.js');
  const map = require('../../js/remotion-shim/map.js');
  const h = React.createElement;
  globalThis.__ms_mapCapabilities = () => JSON.stringify({apple: true, mapbox: false});
  globalThis.__ms_mapRoute = request => {
    const {mode, points} = JSON.parse(request);
    assert.equal(mode, 'railway');
    return JSON.stringify({coordinates: [points[0], [points[0][0], points[1][1]], points[1]], source: 'test'});
  };
  try {
    const html = renderToStaticMarkup(h(shim.__Config.Provider, {value: {width: 640, height: 360, fps: 30, durationInFrames: 1}},
      h(map.MapView, {center: [114.17, 22.28], zoom: 13, provider: 'apple', mapStyle: 'satellite', 'data-ms-src': 'a.tsx:1:1'},
        h(map.MapRoute, {from: [114.15, 22.28], to: [114.19, 22.29], mode: 'railway', progress: 0.5, 'data-ms-src': 'a.tsx:2:1'}),
        h(map.MapMarker, {coordinate: [114.17, 22.28], label: 'Admiralty', 'data-ms-src': 'a.tsx:2:2'}))));
    assert.match(html, /motionmap:\/\/tile\/apple\/satellite\/13\/\d+\/\d+/);
    assert.match(html, /Maps\u00a0©\u00a0Apple/);
    assert.match(html, /<path d="M/);
    assert.match(html, /Admiralty/);
    assert.match(html, /routeSource&quot;:&quot;test/);
    assert.match(html, /effectiveProvider&quot;:&quot;apple/);
  } finally {
    delete globalThis.__ms_mapCapabilities;
    delete globalThis.__ms_mapRoute;
  }
});

test('routes and markers are added to and removed from a MapView with byte-exact undo', () => {
  const run = (source, request) => JSON.parse(portable.edit(source, JSON.stringify({op: 'setMapChildren', ...request})));
  const open = 'const A = () => (\n  <MapView zoom={4}>\n    <MapMarker coordinate={[1, 2]} />\n  </MapView>\n);';
  const added = run(open, {src: 'map.tsx:2:3', key: 'insert',
    value: {type: 'MapRoute', props: {from: [1, 2], to: [3.5, 4], mode: 'driving', progress: 1}}});
  assert.equal(added.source, 'const A = () => (\n  <MapView zoom={4}>\n    <MapMarker coordinate={[1, 2]} />\n' +
    '    <MapRoute from={[1, 2]} to={[3.5, 4]} mode="driving" progress={1} />\n  </MapView>\n);');
  assert.equal(undo(added), open);
  const closed = 'const A = () => <MapView zoom={4} />;';
  const expanded = run(closed, {src, key: 'insert', value: {type: 'MapMarker', props: {coordinate: [5, 6], label: 'Café "Nord"'}}});
  assert.match(expanded.source, /<MapView zoom=\{4\}>\n  <MapMarker coordinate=\{\[5, 6\]\} label=\{"Café \\"Nord\\""\} \/>\n<\/MapView>/);
  assert.equal(undo(expanded), closed);
  const removed = run(open, {src: 'map.tsx:3:5', key: 'remove'});
  assert.equal(removed.source, 'const A = () => (\n  <MapView zoom={4}>\n  </MapView>\n);');
  assert.equal(undo(removed), open);
  assert.throws(() => run(open, {src: 'map.tsx:2:3', key: 'insert', value: {type: 'MapRoute', props: {from: [1, 2], to: [3, 4], mode: 'boat'}}}), /must be one of/);
  assert.throws(() => run(open, {src: 'map.tsx:2:3', key: 'remove'}), /only map routes and markers/);
});
