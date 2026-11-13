// 3D visual regression: native ThreeCanvas stills (Metal 3D, composited by the selected Skia backend)
// against reviewed Remotion + three.js references. Every frame is rendered twice and must be
// bit-identical; the cross-engine comparison uses the 3D gate in tests/three/fixtures.json.
import fs from 'node:fs';
import path from 'node:path';
import {PNG} from 'pngjs';
import {testRoot, root, nativeBin, run, writeJSON, readJSON} from './common.mjs';
import {threeManifest, threeProject, threeGoldens, threePins, compare3D, sha256} from './three-common.mjs';

const backendArg = process.argv.slice(2).find(arg => arg.startsWith('--backend='))?.slice('--backend='.length);
const backend = backendArg ?? process.env.MOTIONSWIFT_BACKEND ?? 'cpu';
if (!['cpu', 'gpu'].includes(backend) || process.argv.slice(2).some(arg => !arg.startsWith('--backend='))) {
  throw Error('Usage: three-visual.mjs [--backend=cpu|gpu]');
}
const output = path.join(testRoot, 'reports/three', backend);
fs.rmSync(output, {recursive: true, force: true});
fs.mkdirSync(output, {recursive: true});
const results = [];
let failed = false;

function assertProvenance(metadata) {
  const pins = threePins();
  for (const key of Object.keys(pins)) {
    if (JSON.stringify(metadata[key]) !== JSON.stringify(pins[key])) {
      throw Error(`3D golden ${key} changed (${JSON.stringify(metadata[key])} -> ${JSON.stringify(pins[key])}); run make three-goldens and review`);
    }
  }
}

function still(bin, fixture, frame, file) {
  const start = performance.now();
  run(bin, ['still', '--project', threeProject, '--entry', threeManifest.entryPoint, fixture.composition, file,
    `--frame=${frame}`, `--backend=${backend}`], {env: {...process.env, MOTIONSWIFT_HOME: root}});
  return performance.now() - start;
}

try {
  const metadata = readJSON(path.join(threeGoldens, 'metadata.json'));
  assertProvenance(metadata);
  const bin = nativeBin();
  for (const fixture of threeManifest.fixtures) {
    // Shuffled order: no JS or GPU state may leak between frames.
    for (const frame of [...fixture.frames].sort((a, b) => (a * 17 % 31) - (b * 17 % 31))) {
      const directory = path.join(output, fixture.id, String(frame));
      fs.mkdirSync(directory, {recursive: true});
      const expectedFile = path.join(threeGoldens, fixture.id, `${frame}.png`);
      const reference = metadata.frames.find(item => item.id === fixture.id && item.frame === frame);
      if (!reference || reference.sha256 !== sha256(fs.readFileSync(expectedFile))) throw Error('3D golden hash mismatch: ' + expectedFile);
      const actualFile = path.join(directory, 'actual.png');
      const nativeMs = still(bin, fixture, frame, actualFile);
      const repeatFile = path.join(directory, 'repeat.png');
      still(bin, fixture, frame, repeatFile);
      const actual = PNG.sync.read(fs.readFileSync(actualFile));
      const deterministic = Buffer.compare(actual.data, PNG.sync.read(fs.readFileSync(repeatFile)).data) === 0;
      fs.unlinkSync(repeatFile);
      const {metrics, diff} = compare3D(PNG.sync.read(fs.readFileSync(expectedFile)), actual);
      fs.copyFileSync(expectedFile, path.join(directory, 'expected.png'));
      const diffImage = new PNG({width: actual.width, height: actual.height});
      diff.copy(diffImage.data);
      fs.writeFileSync(path.join(directory, 'diff.png'), PNG.sync.write(diffImage));
      const result = {id: fixture.id, composition: fixture.composition, frame, ...metrics, deterministic,
        nativeStillMs: Math.round(nativeMs), remotionStillMs: reference.remotionMs,
        nativeRGBA: sha256(actual.data)};
      results.push(result);
      failed ||= !metrics.pass || !deterministic;
      console.log(`${metrics.pass && deterministic ? 'PASS' : 'FAIL'} [${backend}] ${fixture.id}@${frame}: `
        + `${(metrics.changedRatio * 100).toFixed(3)}% changed, ${(metrics.largeDeltaRatio * 100).toFixed(3)}% >`
        + `${threeManifest.gate.largeDelta}, max ${metrics.maxDelta}, PSNR ${metrics.psnr} dB${deterministic ? '' : ', NOT repeatable'}`);
    }
  }
} catch (error) {
  failed = true;
  results.push({error: String(error.stack || error)});
  console.error(error);
}
writeJSON(path.join(output, 'results.json'), {backend, gate: threeManifest.gate, pass: !failed, results});
const escape = value => String(value).replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('"', '&quot;');
fs.writeFileSync(path.join(output, 'index.html'), `<!doctype html><meta charset="utf-8"><title>MotionSwift 3D comparisons</title>
<style>body{background:#15181e;color:#eee;font:15px system-ui;margin:32px}img{width:480px;border:1px solid #555}figure{display:inline-block;margin:6px}</style>
<h1>3D visual tests (${backend}) — Remotion three.js vs native Metal</h1>
<p>Gate: ≤${threeManifest.gate.maxChangedRatio * 100}% changed pixels, ≤${threeManifest.gate.maxLargeDeltaRatio * 100}% over ${threeManifest.gate.largeDelta} levels, PSNR ≥ ${threeManifest.gate.minPSNR} dB, bit-identical repeat renders.</p>
${results.map(result => result.error ? `<pre>${escape(result.error)}</pre>` : `<section><h2>${escape(result.id)} @ ${result.frame}: ${result.pass && result.deterministic ? 'PASS' : 'FAIL'} — ${(result.changedRatio * 100).toFixed(3)}% changed, max ${result.maxDelta}, PSNR ${result.psnr}</h2>
${['expected', 'actual', 'diff'].map(name => `<figure><img src="${escape(result.id)}/${result.frame}/${name}.png"><figcaption>${name}</figcaption></figure>`).join('')}</section>`).join('')}`);
process.exitCode = failed ? 1 : 0;
