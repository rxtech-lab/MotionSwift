// Precompiles the portable (iOS/iPadOS/macOS) JavaScript resources into SwiftPM resources:
//   vendor.js    React, react-reconciler, scheduler and the Remotion shim as one graph
//   portable.js  Sucrase TS/TSX compiler, subset inspector, source stamps and the edit service
//   vendor.json  vendor identity and the bare specifiers devices can resolve
// Built apps evaluate these inside JavaScriptCore; no Node, npm or esbuild runs on a device.
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import {execFileSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import {createRequire} from 'node:module';

const repo = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const output = process.env.MOTIONSWIFT_PORTABLE_RESOURCES
  ? path.resolve(process.env.MOTIONSWIFT_PORTABLE_RESOURCES)
  : path.join(repo, 'Sources/MotionPortable/JavaScript');
const deps = path.join(repo, 'tests/node_modules');
const require = createRequire(path.join(repo, 'tests/package.json'));
const esbuild = require.resolve(`@esbuild/darwin-${process.arch}/bin/esbuild`);
const modules = name => path.join(deps, name);
fs.mkdirSync(output, {recursive: true});

const aliases = [
  ...['react', 'react-reconciler', 'scheduler'].map(name => `--alias:${name}=${modules(name)}`),
  `--alias:@motionswift/remotion=${path.join(repo, 'js/remotion-shim')}`,
];
execFileSync(esbuild, [path.join(repo, 'js/portable/vendor.cjs'), '--bundle', '--platform=browser', '--format=iife',
  '--target=es2022', '--minify', '--define:process.env.NODE_ENV="production"', '--log-level=warning', ...aliases,
  `--outfile=${path.join(output, 'vendor.js')}`]);
execFileSync(esbuild, [path.join(repo, 'js/portable/portable.mjs'), '--bundle', '--platform=browser', '--format=iife',
  '--global-name=MotionPortable', '--target=es2022', '--minify', '--log-level=warning',
  `--alias:@babel/parser=${require.resolve('@babel/parser')}`, `--alias:sucrase=${modules('sucrase')}`,
  `--outfile=${path.join(output, 'portable.js')}`]);

const version = name => JSON.parse(fs.readFileSync(path.join(name.startsWith('/') ? name : modules(name), 'package.json'), 'utf8')).version;
const packages = {
  react: version('react'), 'react-reconciler': version('react-reconciler'), scheduler: version('scheduler'),
  '@motionswift/remotion': version(path.join(repo, 'js/remotion-shim')),
};
const vendor = fs.readFileSync(path.join(output, 'vendor.js'));
// Graphs from a Mac or the cloud link against the device's vendor graph, so both sides must agree on the
// package identities; the hash identifies the exact precompiled artifact for diagnostics.
fs.writeFileSync(path.join(output, 'vendor.json'), JSON.stringify({
  identity: Object.entries(packages).map(([name, value]) => `${name}@${value}`).join(' '),
  sha256: crypto.createHash('sha256').update(vendor).digest('hex'),
  specifiers: ['react', 'react/jsx-runtime', 'react-reconciler', 'scheduler', '@motionswift/remotion',
    '@motionswift/remotion/jsx-runtime', 'remotion', 'remotion/jsx-runtime', 'three',
    'three/addons/loaders/USDLoader.js', 'three/examples/jsm/loaders/USDLoader.js', 'three/addons/loaders/USDZLoader.js',
    'three/examples/jsm/loaders/USDZLoader.js', '@react-three/fiber', '@remotion/three'],
  compiler: {sucrase: version('sucrase'), '@babel/parser': version('@babel/parser')},
}, null, 2) + '\n');
const licenses = [['react', 'LICENSE'], ['react-reconciler', 'LICENSE'], ['scheduler', 'LICENSE'], ['sucrase', 'LICENSE'],
  ['@babel/parser', 'LICENSE']];
fs.writeFileSync(path.join(output, 'THIRD-PARTY-LICENSES.txt'), licenses.map(([name, file]) =>
  `== ${name} ==\n${fs.readFileSync(path.join(modules(name), file), 'utf8')}`).join('\n'));
