import path from 'node:path';
import fs from 'node:fs';
import crypto from 'node:crypto';
import {bundle} from '@remotion/bundler';
import {selectComposition, renderStill} from '@remotion/renderer';
import {browserOptions} from './browser.mjs';
import {root, testRoot} from './common.mjs';
const browser = await browserOptions();
const serveUrl = await bundle({entryPoint: path.join(testRoot, 'maps/railway-basemap.tsx')});
const composition = await selectComposition({...browser, serveUrl, id: 'RailwayBasemap'});
await renderStill({...browser, serveUrl, composition, frame: 0, imageFormat: 'png',
  output: path.join(root, 'Examples/MotionShowcase/Railway/public/map.png')});
const project = path.join(root, 'Examples/MotionShowcase/Railway');
const sha256 = file => crypto.createHash('sha256').update(fs.readFileSync(path.join(project, file))).digest('hex');
const files = ['basemap.ts', 'map-data.ts', 'route.ts', 'artwork.ts', 'public/map.png'];
fs.writeFileSync(path.join(project, 'map-provenance.json'), JSON.stringify({
  engine: 'Remotion', files: Object.fromEntries(files.map(file => [file, sha256(file)])),
}, null, 2) + '\n');
