// @motionswift/map: a deterministic slippy map for video. <MapView> draws provider raster
// tiles in Web Mercator; <MapRoute> and <MapMarker> overlay geographic data. Coordinates are
// [longitude, latitude]. Every prop is editable in the MotionSwift visual editor (map-edit.js).
//
// Inside MotionSwift, tiles load through the native `motionmap://` resolver (disk cached, with
// Apple Maps through MapKit and Mapbox with a host-provided token) and road/rail routes through
// `__ms_mapRoute`. Elsewhere (a browser) OpenStreetMap/CARTO tiles load over HTTPS and routes
// that need a routing service are drawn as straight lines.
'use strict';
const React = require('react');
const {useVideoConfig} = require('./index');
const mapEdit = require('./map-edit');

const h = React.createElement;
const TILE = 256;
const MAX_LATITUDE = 85.0511287798;

// MARK: Providers
const PROVIDERS = {
  openstreetmap: {label: 'OpenStreetMap', styles: {
    standard: {label: 'Standard', maxZoom: 19, url: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
      attribution: '© OpenStreetMap contributors'},
    humanitarian: {label: 'Humanitarian', maxZoom: 19, url: 'https://a.tile.openstreetmap.fr/hot/{z}/{x}/{y}.png',
      attribution: '© OpenStreetMap contributors · Tiles: Humanitarian OSM Team'},
    topographic: {label: 'Topographic', maxZoom: 17, url: 'https://a.tile.opentopomap.org/{z}/{x}/{y}.png',
      attribution: '© OpenStreetMap contributors, SRTM · © OpenTopoMap (CC-BY-SA)'},
    // Monochrome looks derived from the standard tiles with color filters.
    light: {label: 'Light', maxZoom: 19, tiles: 'standard', filter: 'grayscale(1) brightness(1.06) contrast(0.9)',
      url: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png', attribution: '© OpenStreetMap contributors'},
    dark: {label: 'Dark', maxZoom: 19, tiles: 'standard', filter: 'grayscale(1) invert(1) brightness(0.86) contrast(0.92)',
      url: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png', attribution: '© OpenStreetMap contributors'},
  }},
  mapbox: {label: 'Mapbox', styles: Object.fromEntries([
    ['streets-v12', 'Streets'], ['outdoors-v12', 'Outdoors'], ['light-v11', 'Light'], ['dark-v11', 'Dark'],
    ['satellite-v9', 'Satellite'], ['satellite-streets-v12', 'Satellite Streets'],
  ].map(([id, label]) => [id, {label, maxZoom: 22, attribution: '© Mapbox © OpenStreetMap contributors'}]))},
  apple: {label: 'Apple Maps', styles: Object.fromEntries([
    ['standard', 'Standard'], ['muted', 'Muted'], ['dark', 'Dark'], ['satellite', 'Satellite'], ['hybrid', 'Hybrid'],
  ].map(([id, label]) => [id, {label, maxZoom: 20, attribution: 'Maps © Apple'}]))},
};

function capabilities() {
  const query = globalThis.__ms_mapCapabilities;
  if (typeof query !== 'function') return {native: false, apple: false, mapbox: false};
  try { return {native: true, ...JSON.parse(query())}; } catch { return {native: true, apple: false, mapbox: false}; }
}

/** The provider and style that will actually draw, with a note when the request fell back. */
function resolveProvider(provider = 'openstreetmap', style) {
  const caps = capabilities();
  let note = null;
  let id = PROVIDERS[provider] ? provider : 'openstreetmap';
  if (id !== provider) note = `Unknown map provider "${provider}"; using OpenStreetMap`;
  const unavailable = id === 'apple' && !caps.apple ? 'Apple Maps (MapKit) is unavailable here'
    : id === 'mapbox' && !caps.mapbox ? 'Mapbox needs an access token (MAPBOX_ACCESS_TOKEN or the editor\'s map settings)'
      : null;
  let chosen = style;
  if (unavailable) {
    // Keep the look when falling back: dark and light styles map to the filtered OSM styles.
    const tone = /dark/.test(style ?? '') ? 'dark' : /light|muted/.test(style ?? '') ? 'light' : null;
    id = 'openstreetmap';
    chosen = tone ?? 'standard';
    note = `${unavailable}; using ${PROVIDERS[id].label}`;
  }
  const styles = PROVIDERS[id].styles;
  if (!styles[chosen]) {
    const first = Object.keys(styles)[0];
    if (chosen !== undefined && !note) note = `${PROVIDERS[id].label} has no "${chosen}" style; using ${styles[first].label}`;
    chosen = first;
  }
  return {provider: id, style: chosen, definition: styles[chosen], note, native: caps.native};
}

function tileSource(resolved, z, x, y) {
  const style = resolved.definition.tiles ?? resolved.style;
  if (resolved.native) return `motionmap://tile/${resolved.provider}/${style}/${z}/${x}/${y}`;
  if (typeof globalThis.__ms_mapTileURL === 'function')
    return globalThis.__ms_mapTileURL(resolved.provider, style, z, x, y);
  return resolved.definition.url ? resolved.definition.url.replace('{z}', z).replace('{x}', x).replace('{y}', y) : null;
}

// MARK: Projection
const clampLatitude = latitude => Math.max(-MAX_LATITUDE, Math.min(MAX_LATITUDE, latitude));

/** Web Mercator world pixels at `zoom` (256 px tiles). */
function worldPixel([longitude, latitude], zoom) {
  const size = TILE * 2 ** zoom;
  const sin = Math.sin(clampLatitude(latitude) * Math.PI / 180);
  return [(longitude + 180) / 360 * size, (0.5 - Math.log((1 + sin) / (1 - sin)) / (4 * Math.PI)) * size];
}

function coordinateAt([x, y], zoom) {
  const size = TILE * 2 ** zoom;
  const n = Math.PI - 2 * Math.PI * y / size;
  return [x / size * 360 - 180, 180 / Math.PI * Math.atan(Math.sinh(n))];
}

function camera({center = [0, 0], zoom = 2, bearing = 0, width, height}) {
  const z = Math.max(0, Math.min(22, finite(zoom, 'zoom')));
  const middle = worldPixel([finite(center[0], 'center longitude'), finite(center[1], 'center latitude')], z);
  const angle = -finite(bearing, 'bearing') * Math.PI / 180;
  const cos = Math.cos(angle), sin = Math.sin(angle), world = TILE * 2 ** z;
  const project = coordinate => {
    const [x, y] = worldPixel(coordinate, z);
    let dx = x - middle[0];
    // Draw the copy of the world nearest to the camera.
    dx -= Math.round(dx / world) * world;
    const dy = y - middle[1];
    return [width / 2 + dx * cos - dy * sin, height / 2 + dx * sin + dy * cos];
  };
  const unproject = ([px, py]) => {
    const dx = px - width / 2, dy = py - height / 2;
    return coordinateAt([middle[0] + dx * cos + dy * sin, middle[1] - dx * sin + dy * cos], z);
  };
  return {zoom: z, bearing, width, height, project, unproject, center: [center[0], center[1]]};
}

function finite(value, name) {
  if (typeof value !== 'number' || !Number.isFinite(value)) throw Error(`MapView ${name} must be a finite number`);
  return value;
}

// MARK: <MapView>
const MapContext = React.createContext(null);
const useMap = () => {
  const value = React.useContext(MapContext);
  if (!value) throw Error('Map overlays must be rendered inside <MapView>');
  return value;
};

function tiles(view, resolved, width, height, bearing) {
  const maxZoom = resolved.definition.maxZoom;
  const tz = Math.max(0, Math.min(maxZoom, Math.round(view.zoom)));
  const scale = 2 ** (view.zoom - tz), count = 2 ** tz;
  const [cx, cy] = worldPixel(view.center, tz);
  // A rotated map needs tiles under the whole rotated viewport.
  const rotated = bearing % 360 !== 0, radius = Math.hypot(width, height) / 2;
  const half = rotated ? [radius / scale, radius / scale] : [width / 2 / scale, height / 2 / scale];
  const x0 = Math.floor((cx - half[0]) / TILE), x1 = Math.floor((cx + half[0]) / TILE);
  const y0 = Math.max(0, Math.floor((cy - half[1]) / TILE)), y1 = Math.min(count - 1, Math.floor((cy + half[1]) / TILE));
  const edge = (tile, centre, size) => Math.floor(size / 2 + (tile * TILE - centre) * scale);
  const overlap = rotated ? 1 : 0;
  const result = [];
  for (let ty = y0; ty <= y1; ty++) for (let tx = x0; tx <= x1; tx++) {
    const wrapped = ((tx % count) + count) % count;
    const src = tileSource(resolved, tz, wrapped, ty);
    if (!src) continue;
    const left = edge(tx, cx, width), top = edge(ty, cy, height);
    result.push(h('img', {key: `${tz}/${tx}/${ty}`, src, style: {position: 'absolute', left, top,
      width: edge(tx + 1, cx, width) - left + overlap, height: edge(ty + 1, cy, height) - top + overlap}}));
  }
  return result;
}

// Labels stay on one line: non-breaking spaces, and an explicit width (an absolutely positioned
// box is otherwise limited by its small containing block, such as a marker dot).
const unbroken = text => String(text).replace(/ /g, '\u00a0');
const textWidth = (text, size) => Math.ceil([...String(text)].reduce((width, char) =>
  width + (/[\u2e80-\uffff]/.test(char) && char !== '\u00a0' ? 1.02 : /[ilj.,:;'\|\!\u00a0 ]/.test(char) ? 0.3 : /[mwMW@]/.test(char) ? 0.86 : 0.6), 0) * size) + 2;

const corner = position => ({
  'bottom-right': {right: 0, bottom: 0}, 'bottom-left': {left: 0, bottom: 0},
  'top-right': {right: 0, top: 0}, 'top-left': {left: 0, top: 0},
}[position] ?? {right: 0, bottom: 0});

function MapView(props) {
  const config = useVideoConfig();
  const {center = [0, 0], zoom = 2, bearing = 0, provider = 'openstreetmap', mapStyle, saturation = 1, brightness = 1,
    attribution = 'bottom-right', backgroundColor = '#e8e4da', style, children} = props;
  const width = props.width ?? config?.width ?? 1280, height = props.height ?? config?.height ?? 720;
  if (!Array.isArray(center) || center.length !== 2) throw Error('MapView center must be [longitude, latitude]');
  const view = camera({center, zoom, bearing, width, height});
  const resolved = resolveProvider(provider, mapStyle);
  const filter = [resolved.definition.filter ?? '', saturation !== 1 ? `saturate(${saturation})` : '',
    brightness !== 1 ? `brightness(${brightness})` : '']
    .filter(Boolean).join(' ');
  const source = props['data-ms-src'];
  const editor = source ? JSON.stringify({type: 'MapView', properties: {
    ...mapEdit.values('MapView', props), effectiveProvider: resolved.provider, effectiveStyle: resolved.style,
    ...(resolved.note ? {providerNote: resolved.note} : {}), width, height,
  }}) : undefined;
  const fontSize = Math.max(9, Math.min(12, Math.round(height / 80)));
  return h('div', {'data-ms-src': source, 'data-ms-editor': editor,
    style: {position: 'absolute', left: 0, top: 0, width, height, overflow: 'hidden', backgroundColor, ...style}},
  h('div', {style: {position: 'absolute', left: 0, top: 0, width, height,
    ...(bearing % 360 ? {transform: `rotate(${-bearing}deg)`} : {}), ...(filter ? {filter} : {})}},
  tiles(view, resolved, width, height, bearing)),
  h(MapContext.Provider, {value: view}, children),
  h('div', {style: {position: 'absolute', ...corner(attribution), width: textWidth(resolved.definition.attribution, fontSize) + fontSize,
    boxSizing: 'border-box', paddingLeft: fontSize / 2, paddingRight: fontSize / 2,
    paddingTop: Math.round(fontSize / 4), paddingBottom: Math.round(fontSize / 4), backgroundColor: 'rgba(255,255,255,0.8)',
    color: '#30373b', fontSize, lineHeight: 1.2, whiteSpace: 'nowrap'}}, unbroken(resolved.definition.attribution)));
}
MapView.__msEditType = 'MapView';

// MARK: Route geometry
const routes = new Map();
const NATIVE_MODES = new Set(['driving', 'cycling', 'walking', 'railway', 'subway', 'tram']);

function greatCircle(a, b, steps) {
  const rad = Math.PI / 180;
  const [l1, p1, l2, p2] = [a[0] * rad, a[1] * rad, b[0] * rad, b[1] * rad];
  const d = 2 * Math.asin(Math.sqrt(Math.sin((p2 - p1) / 2) ** 2 + Math.cos(p1) * Math.cos(p2) * Math.sin((l2 - l1) / 2) ** 2));
  if (d < 1e-9) return [a, b];
  const points = [];
  for (let i = 0; i <= steps; i++) {
    const f = i / steps, A = Math.sin((1 - f) * d) / Math.sin(d), B = Math.sin(f * d) / Math.sin(d);
    const x = A * Math.cos(p1) * Math.cos(l1) + B * Math.cos(p2) * Math.cos(l2);
    const y = A * Math.cos(p1) * Math.sin(l1) + B * Math.cos(p2) * Math.sin(l2);
    const z = A * Math.sin(p1) + B * Math.sin(p2);
    let longitude = Math.atan2(y, x) / rad;
    // Keep longitudes continuous across the antimeridian.
    if (points.length) longitude += 360 * Math.round((points.at(-1)[0] - longitude) / 360);
    points.push([longitude, Math.atan2(z, Math.hypot(x, y)) / rad]);
  }
  return points;
}

function arc(a, b, steps, bend) {
  const [ax, ay] = worldPixel(a, 0), [bx0, by] = worldPixel(b, 0);
  const bx = bx0 + TILE * Math.round((ax - bx0) / TILE);
  const [mx, my] = [(ax + bx) / 2, (ay + by) / 2], length = Math.hypot(bx - ax, by - ay);
  const [cx, cy] = [mx - (by - ay) / (length || 1) * length * bend, my + (bx - ax) / (length || 1) * length * bend];
  const points = [];
  for (let i = 0; i <= steps; i++) {
    const t = i / steps, u = 1 - t;
    points.push(coordinateAt([u * u * ax + 2 * u * t * cx + t * t * bx, u * u * ay + 2 * u * t * cy + t * t * by], 0));
  }
  return points;
}

/** Route coordinates for `mode`; network modes ask the host and fall back to straight lines. */
function routeGeometry(mode, points) {
  const key = JSON.stringify([mode, points]);
  if (routes.has(key)) return routes.get(key);
  let result = null;
  if (NATIVE_MODES.has(mode)) {
    const route = globalThis.__ms_mapRoute;
    if (typeof route !== 'function') result = {status: `${mode} routing needs the MotionSwift renderer; drawing straight lines`};
    else {
      try {
        const response = JSON.parse(route(JSON.stringify({mode, points})));
        // A pending route is drawn as a placeholder and never cached; the host re-renders later.
        if (response.pending) result = {status: response.error ?? `Fetching ${mode} route…`, pending: true};
        else if (response.error) result = {status: `${response.error}; drawing straight lines`};
        else result = {coordinates: response.coordinates, status: null, source: response.source ?? null};
      } catch (error) { result = {status: `${mode} routing failed: ${error.message}; drawing straight lines`}; }
    }
  } else if (!mapEdit.ROUTE_MODES.includes(mode)) result = {status: `Unknown route mode "${mode}"; drawing straight lines`};
  if (!result?.coordinates) {
    const legs = [];
    for (let i = 1; i < points.length; i++) {
      const leg = mode === 'arc' ? arc(points[i - 1], points[i], 64, 0.18) : greatCircle(points[i - 1], points[i], 64);
      legs.push(...(i > 1 ? leg.slice(1) : leg));
    }
    result = {coordinates: legs, status: result?.status ?? null, source: null};
  }
  // Distances in zoom-0 world pixels make progress independent of the camera.
  const distances = [0];
  let previous = worldPixel(result.coordinates[0], 0);
  for (const coordinate of result.coordinates.slice(1)) {
    const next = worldPixel(coordinate, 0);
    distances.push(distances.at(-1) + Math.hypot(next[0] - previous[0], next[1] - previous[1]));
    previous = next;
  }
  result.distances = distances;
  if (routes.size > 256) routes.clear();
  if (!result.pending) routes.set(key, result);
  return result;
}

/** The route up to `progress` (0–1) and its head coordinate. */
function routeAt(route, progress) {
  const {coordinates, distances} = route;
  const total = distances.at(-1), target = Math.max(0, Math.min(1, progress)) * total;
  if (target >= total) return {coordinates, head: coordinates.at(-1)};
  let index = distances.findIndex(value => value >= target);
  index = Math.max(1, index);
  const length = distances[index] - distances[index - 1];
  const ratio = length ? (target - distances[index - 1]) / length : 0;
  const a = coordinates[index - 1], b = coordinates[index];
  const head = [a[0] + (b[0] - a[0]) * ratio, a[1] + (b[1] - a[1]) * ratio];
  return {coordinates: [...coordinates.slice(0, index), head], head};
}

function coordinate(value, name) {
  if (!Array.isArray(value) || value.length !== 2 || !value.every(Number.isFinite))
    throw Error(`${name} must be [longitude, latitude]`);
  return [value[0], value[1]];
}

/** Emits only segments that can intersect `[minX, maxX] × [minY, maxY]`, translated by `(-left, -top)`. */
function clippedPath(points, left, top, minX, minY, maxX, maxY) {
  const parts = [];
  let pen = false;
  for (let i = 1; i < points.length; i++) {
    const [x0, y0] = points[i - 1], [x1, y1] = points[i];
    if ((x0 < minX && x1 < minX) || (x0 > maxX && x1 > maxX) ||
        (y0 < minY && y1 < minY) || (y0 > maxY && y1 > maxY)) {
      pen = false;
      continue;
    }
    if (!pen) parts.push(`M${(x0 - left).toFixed(2)} ${(y0 - top).toFixed(2)}`);
    parts.push(`L${(x1 - left).toFixed(2)} ${(y1 - top).toFixed(2)}`);
    pen = true;
  }
  return parts.join(' ');
}

// MARK: <MapRoute>
function MapRoute(props) {
  const view = useMap();
  const {mode = 'straight', progress = 1, color = '#ff5a36', width = 5, outlineColor = '#ffffff', markerSize = 14,
    via = [], dashed = false} = props;
  const from = coordinate(props.from, 'MapRoute from'), to = coordinate(props.to, 'MapRoute to');
  const route = routeGeometry(mode, [from, ...via.map((point, i) => coordinate(point, `MapRoute via[${i}]`)), to]);
  const drawn = routeAt(route, progress);
  const points = drawn.coordinates.map(view.project);
  const head = view.project(drawn.head);
  const pad = Math.max(width + 4, markerSize) + 2;
  const margin = pad + 64;
  let [left, top, right, bottom] = [Infinity, Infinity, -Infinity, -Infinity];
  for (const [x, y] of [...points, view.project(from), view.project(to)]) {
    left = Math.min(left, x); top = Math.min(top, y); right = Math.max(right, x); bottom = Math.max(bottom, y);
  }
  // Keep the vector island near the viewport even when the route extends far beyond it.
  left = Math.floor(Math.max(-margin, left - pad)); top = Math.floor(Math.max(-margin, top - pad));
  right = Math.ceil(Math.min(view.width + margin, right + pad)); bottom = Math.ceil(Math.min(view.height + margin, bottom + pad));
  const boxWidth = Math.max(1, right - left), boxHeight = Math.max(1, bottom - top);
  const d = clippedPath(points, left, top, left - pad, top - pad, right + pad, bottom + pad);
  const source = props['data-ms-src'];
  const editor = source ? JSON.stringify({type: 'MapRoute', properties: {
    ...mapEdit.values('MapRoute', props), ...(route.status ? {routeStatus: route.status} : {}),
    ...(route.source ? {routeSource: route.source} : {}), ...(route.pending ? {routePending: 1} : {}),
    points: route.coordinates.length,
  }}) : undefined;
  const visible = progress > 0 && d.length > 0;
  const showHead = progress > 0 && points.length > 1 && markerSize > 0 &&
    head[0] >= left - pad && head[0] <= right + pad && head[1] >= top - pad && head[1] <= bottom + pad;
  const line = {fill: 'none', strokeLinecap: 'round', strokeLinejoin: 'round'};
  return h('svg', {'data-ms-src': source, 'data-ms-editor': editor, width: boxWidth, height: boxHeight,
    style: {position: 'absolute', left, top, width: boxWidth, height: boxHeight}},
  visible && outlineColor !== 'none' ? h('path', {d, ...line, stroke: outlineColor, strokeWidth: width + 4}) : null,
  visible ? h('path', {d, ...line, stroke: color, strokeWidth: width,
    ...(dashed ? {strokeDasharray: `${width * 2} ${width * 1.6}`} : {})}) : null,
  showHead ? h('circle', {cx: head[0] - left, cy: head[1] - top, r: markerSize / 2,
    fill: color, stroke: outlineColor === 'none' ? color : outlineColor, strokeWidth: Math.max(2, markerSize / 6)}) : null);
}
MapRoute.__msEditType = 'MapRoute';

// MARK: <MapMarker>
function MapMarker(props) {
  const view = useMap();
  const {color = '#ff5a36', size = 18, label = '', labelColor = '#1d2a30'} = props;
  const [x, y] = view.project(coordinate(props.coordinate, 'MapMarker coordinate'));
  const source = props['data-ms-src'];
  const editor = source ? JSON.stringify({type: 'MapMarker', properties: mapEdit.values('MapMarker', props)}) : undefined;
  const fontSize = Math.max(11, Math.round(size * 0.75));
  const labelWidth = label ? textWidth(label, fontSize) + 12 : 0;
  const showLabel = label && x + size + 4 + labelWidth >= 0 && x - size <= view.width &&
    y + size + fontSize >= 0 && y - size - fontSize <= view.height;
  return h('div', {'data-ms-src': source, 'data-ms-editor': editor, style: {position: 'absolute',
    left: x - size / 2, top: y - size / 2, width: size, height: size, borderRadius: size / 2, backgroundColor: color,
    boxSizing: 'border-box', borderWidth: Math.max(2, Math.round(size / 7)), borderStyle: 'solid', borderColor: '#ffffff'}},
  showLabel ? h('div', {style: {position: 'absolute', left: size + 4, top: size / 2 - fontSize * 0.85,
    width: labelWidth, boxSizing: 'border-box',
    paddingLeft: 6, paddingRight: 6, paddingTop: 2, paddingBottom: 2, borderRadius: 4,
    backgroundColor: '#ffffff', color: labelColor, fontSize, lineHeight: 1.2, whiteSpace: 'nowrap'}}, unbroken(label)) : null);
}
MapMarker.__msEditType = 'MapMarker';

module.exports = {MapView, MapRoute, MapMarker, useMap, MAP_PROVIDERS: PROVIDERS, resolveProvider,
  projectCoordinate: (coordinate, options) => camera(options).project(coordinate),
  __routeGeometry: routeGeometry, __routeAt: routeAt};
