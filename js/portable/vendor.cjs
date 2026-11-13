// The precompiled vendor graph: React, the reconciler and the Remotion shim (with its 3D subset), bundled once by
// `make compiler` (CI) and linked with project module graphs on every platform. Devices never
// run Node, npm or esbuild; they evaluate this file and resolve bare imports through it.
const runtime = require('@motionswift/remotion/jsx-runtime');
const shim = require('@motionswift/remotion');
const three = require('@motionswift/remotion/three');
const fiber = require('@motionswift/remotion/fiber');
const remotionThree = require('@motionswift/remotion/remotion-three');
const usd = require('@motionswift/remotion/usd-loader');

globalThis.__ms_vendor = {
  react: require('react'),
  'react/jsx-runtime': runtime,
  'react-reconciler': require('react-reconciler'),
  scheduler: require('scheduler'),
  '@motionswift/remotion': shim,
  '@motionswift/remotion/jsx-runtime': runtime,
  remotion: shim,
  'remotion/jsx-runtime': runtime,
  // 3D: a three.js subset, React Three Fiber hooks and @remotion/three, drawn by the native renderer.
  three,
  'three/addons/loaders/USDLoader.js': usd,
  'three/examples/jsm/loaders/USDLoader.js': usd,
  'three/addons/loaders/USDZLoader.js': usd,
  'three/examples/jsm/loaders/USDZLoader.js': usd,
  '@react-three/fiber': fiber,
  '@remotion/three': remotionThree,
};
