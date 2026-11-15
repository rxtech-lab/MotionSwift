// Shared by source inspection, editing and playback: editor keys map to props of the
// @motionswift/map components (never CSS). Coordinates are [longitude, latitude] arrays.
'use strict';

const PROVIDERS = ['openstreetmap', 'mapbox', 'apple'];
const ROUTE_MODES = ['straight', 'arc', 'driving', 'cycling', 'walking', 'railway', 'subway', 'tram'];
const ATTRIBUTION = ['bottom-right', 'bottom-left', 'top-right', 'top-left'];

function fields(type) {
  const result = [];
  if (typeof type !== 'string') return result;
  const add = (key, path, fallback, range) => result.push({key, path, fallback, ...(range ? {range} : {})});
  if (type === 'MapView') {
    add('centerLongitude', ['center', 0], 0, [-180, 180]);
    add('centerLatitude', ['center', 1], 0, [-85.0511, 85.0511]);
    add('zoom', ['zoom'], 2, [0, 22]);
    add('bearing', ['bearing'], 0, [-360, 360]);
    add('provider', ['provider'], 'openstreetmap');
    add('mapStyle', ['mapStyle'], 'standard');
    add('saturation', ['saturation'], 1, [0, 2]);
    add('brightness', ['brightness'], 1, [0, 2]);
    add('attribution', ['attribution'], 'bottom-right');
  }
  if (type === 'MapRoute') {
    add('fromLongitude', ['from', 0], 0, [-180, 180]);
    add('fromLatitude', ['from', 1], 0, [-85.0511, 85.0511]);
    add('toLongitude', ['to', 0], 0, [-180, 180]);
    add('toLatitude', ['to', 1], 0, [-85.0511, 85.0511]);
    add('mode', ['mode'], 'straight');
    add('progress', ['progress'], 1, [0, 1]);
    add('color', ['color'], '#ff5a36');
    add('width', ['width'], 5, [0.5, 64]);
    add('outlineColor', ['outlineColor'], '#ffffff');
    add('markerSize', ['markerSize'], 14, [0, 96]);
  }
  if (type === 'MapMarker') {
    add('longitude', ['coordinate', 0], 0, [-180, 180]);
    add('latitude', ['coordinate', 1], 0, [-85.0511, 85.0511]);
    add('color', ['color'], '#ff5a36');
    add('size', ['size'], 18, [2, 128]);
    add('label', ['label'], '');
  }
  return result;
}

/** String-valued fields that accept one of a fixed set of values. */
const options = {provider: PROVIDERS, mode: ROUTE_MODES, attribution: ATTRIBUTION};

function values(type, props) {
  const result = {};
  for (const field of fields(type)) {
    let value = props;
    for (const part of field.path) value = value?.[part];
    if (value === undefined) value = field.fallback;
    if (typeof value === 'number' || typeof value === 'string') result[field.key] = value;
  }
  return result;
}

function animate(type, props, key, value) {
  const field = fields(type).find(field => field.key === key);
  if (!field) throw Error('Unsupported map keyframe property: ' + key);
  const [root, index] = field.path;
  if (field.path.length === 2) {
    const fallback = fields(type).filter(f => f.path[0] === root).map(f => f.fallback);
    props[root] = Array.isArray(props[root]) ? [...props[root]] : fallback;
    props[root][index] = value;
  } else props[root] = value;
}

/** Validation shared by the editor's write-back. Returns an error message or null. */
function invalid(type, key, value) {
  const field = fields(type).find(field => field.key === key);
  if (!field) return 'unsupported map property';
  if (typeof field.fallback === 'number') {
    if (typeof value !== 'number' || !Number.isFinite(value)) return 'a finite number is required';
    if (field.range && (value < field.range[0] || value > field.range[1]))
      return `${key} must be between ${field.range[0]} and ${field.range[1]}`;
    return null;
  }
  if (typeof value !== 'string') return 'a string is required';
  if (options[key] && !options[key].includes(value)) return `${key} must be one of ${options[key].join(', ')}`;
  if (key.toLowerCase().endsWith('color') && !/^#(?:[\da-fA-F]{3,4}|[\da-fA-F]{6}|[\da-fA-F]{8})$/.test(value))
    return `${key} must be a hex color`;
  return null;
}

module.exports = {fields, values, animate, invalid, options, PROVIDERS, ROUTE_MODES,
  isMap: type => fields(type).length > 0};
