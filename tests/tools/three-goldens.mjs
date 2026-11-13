// Explicit regeneration of the 3D reference stills from real Remotion + three.js (Chrome ANGLE/Metal).
// CI never regenerates references; three-visual.mjs fails when any pin or source hash changes.
import fs from 'node:fs';
import path from 'node:path';
import {selectComposition, renderStill} from '@remotion/renderer';
import {writeJSON} from './common.mjs';
import {threeManifest, threeGoldens, threePins, threeBrowser, bundleThree, sha256} from './three-common.mjs';

const browser = await threeBrowser();
const serveUrl = await bundleThree();
const frames = [];
fs.rmSync(threeGoldens, {recursive: true, force: true});
for (const fixture of threeManifest.fixtures) {
  const composition = await selectComposition({...browser, serveUrl, id: fixture.composition});
  for (const frame of fixture.frames) {
    const output = path.join(threeGoldens, fixture.id, `${frame}.png`);
    fs.mkdirSync(path.dirname(output), {recursive: true});
    const start = performance.now();
    await renderStill({...browser, serveUrl, composition, frame, output, imageFormat: 'png', logLevel: 'error'});
    frames.push({id: fixture.id, frame, sha256: sha256(fs.readFileSync(output)), remotionMs: Math.round(performance.now() - start)});
    console.log(`${fixture.id} frame ${frame}`);
  }
}
writeJSON(path.join(threeGoldens, 'metadata.json'), {schema: 1, engine: 'Remotion', ...threePins(), frames});
