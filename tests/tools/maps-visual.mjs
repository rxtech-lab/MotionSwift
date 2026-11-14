// Compare Remotion with both native backends. Railway uses live/cached OSM tiles; synthetic fixtures are offline.
import fs from 'node:fs';
import path from 'node:path';
import {bundle} from '@remotion/bundler';
import {selectComposition, renderStill} from '@remotion/renderer';
import {PNG} from 'pngjs';
import {browserOptions} from './browser.mjs';
import {compareFiles} from './compare.mjs';
import {root, testRoot, nativeBin, run, writeJSON} from './common.mjs';

if (process.argv.slice(2).some(arg => arg !== '--railway')) throw Error('Usage: maps-visual.mjs [--railway]');
const railway = process.argv.includes('--railway');
const project = railway ? path.join(root, 'Examples/MotionShowcase/Railway') : path.join(testRoot, 'maps');
const entry = railway ? 'index.tsx' : 'src/index.tsx';
const output = path.join(testRoot, 'reports/maps', ...(railway ? ['railway'] : []));
const results = [];
let failed = false;
try {
  const browser = await browserOptions();
  const bin = nativeBin();
  const serveUrl = await bundle({entryPoint: path.join(project, entry), publicDir: path.join(project, 'public'),
    webpackOverride: config => ({...config, resolve: {...config.resolve, alias: {...config.resolve?.alias,
      '@motionswift/map': path.join(testRoot, 'tools/map-browser-reference.cjs'),
    }}}),
  });
  for (const id of railway ? ['IslandRailway'] : ['OpenStreetMapTiles', 'MapKitSnapshot']) {
    const composition = await selectComposition({...browser, serveUrl, id});
    // Seeking backwards and repeating each native frame catches state leakage.
    for (const frame of railway ? [750, 0, 1499] : [15, 0, 7]) {
      const directory = path.join(output, id, String(frame));
      fs.mkdirSync(directory, {recursive: true});
      const expected = path.join(directory, 'remotion.png');
      await renderStill({...browser, serveUrl, composition, frame, output: expected, imageFormat: 'png', logLevel: 'error'});
      const image = PNG.sync.read(fs.readFileSync(expected));
      if (railway) {
        let markerPixels = 0;
        for (let offset = 0; offset < image.data.length; offset += 4) {
          if (image.data[offset] === 255 && image.data[offset + 1] === 103 && image.data[offset + 2] === 76) markerPixels++;
        }
        if (image.width !== 1920 || image.height !== 1080 || markerPixels < 20) throw Error('Missing railway map or train marker');
      } else {
        const markerOffset = (72 * image.width + 120 + frame * 2) * 4;
        if (image.width !== 320 || image.height !== 180 ||
            !image.data.subarray(markerOffset, markerOffset + 4).equals(Buffer.from([224, 64, 64, 255]))) {
          throw Error(`${id}@${frame}: missing expected marker or wrong dimensions`);
        }
        const waterX = id === 'OpenStreetMapTiles' ? 255 - frame * 2 : 255;
        const waterOffset = (150 * image.width + waterX) * 4;
        if (!image.data.subarray(waterOffset, waterOffset + 4).equals(Buffer.from([112, 176, 208, 255]))) {
          throw Error(`${id}@${frame}: missing map imagery`);
        }
      }
      for (const backend of ['cpu', 'gpu']) {
        const actual = path.join(directory, `${backend}.png`);
        const repeat = path.join(directory, `${backend}-repeat.png`);
        for (const file of [actual, repeat]) run(bin, ['still', '--project', project, '--entry', entry, id,
          file, `--frame=${frame}`, `--backend=${backend}`]);
        const metrics = compareFiles(expected, actual, path.join(directory, backend), 0.003);
        const deterministic = compareFiles(actual, repeat, null, 0).pass;
        const pass = metrics.pass && deterministic;
        results.push({id, frame, backend, ...metrics, deterministic, pass});
        failed ||= !pass;
        console.log(`${pass ? 'PASS' : 'FAIL'} maps ${id}@${frame} [${backend}]: ${(metrics.diffRatio * 100).toFixed(4)}%`);
      }
    }
  }
} catch (error) {
  failed = true;
  results.push({error: String(error)});
  console.error(error);
}
writeJSON(path.join(output, 'results.json'), {
  scope: railway ? 'real OSM tiles and bundled Yamanote track; native tile cache and browser network required' : 'offline image compatibility; no live provider validation',
  pass: !failed, results,
});
process.exitCode = failed ? 1 : 0;
