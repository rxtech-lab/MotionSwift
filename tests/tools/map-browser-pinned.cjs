// The railway parity render uses the native renderer's isolated tile cache.
const {staticFile} = require('remotion');
globalThis.__ms_mapTileURL = (provider, style, z, x, y) =>
  staticFile(`tile-cache/tiles/${provider}/${style}/${z}/${x}/${y}.tile`);
module.exports = require('./map-browser-reference.cjs');
