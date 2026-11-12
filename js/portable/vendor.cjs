// The precompiled vendor graph: React, the reconciler and the Remotion shim, bundled once by
// `make compiler` (CI) and linked with project module graphs on every platform. Devices never
// run Node, npm or esbuild; they evaluate this file and resolve bare imports through it.
const runtime = require('@motionswift/remotion/jsx-runtime');
const shim = require('@motionswift/remotion');

globalThis.__ms_vendor = {
  react: require('react'),
  'react/jsx-runtime': runtime,
  'react-reconciler': require('react-reconciler'),
  scheduler: require('scheduler'),
  '@motionswift/remotion': shim,
  '@motionswift/remotion/jsx-runtime': runtime,
  remotion: shim,
  'remotion/jsx-runtime': runtime,
};
