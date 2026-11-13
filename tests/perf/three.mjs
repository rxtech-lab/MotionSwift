// 3D performance regression: Remotion (three.js in Chrome, ANGLE/Metal) vs native MotionSwift on the
// complex ThreeCanvas fixtures. Every native video must match Remotion's (frame count, SSIM) before
// its speedup counts, and each native engine must be at least `minSpeedup` times faster than Remotion.
//
//   node tests/perf/three.mjs [--out tests/reports/bench/three] [--runs 1] [--warmup 1] [--tiers 360p,1080p] [--engines remotion,cpu,gpu,gpu-shared]
//                             [--only NeonCity] [--report-only] [--allow-unavailable-hardware]
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import {root, testRoot, nativeBin, writeJSON} from '../tools/common.mjs';
import {threeManifest, threeProject, threePins} from '../tools/three-common.mjs';
import {median, geometricMean} from './metrics.mjs';

const ENGINES = {cpu: ['cpu', 'software'], gpu: ['gpu', 'software'], 'gpu-shared': ['gpu', 'videotoolbox-shared']};
const options = {out: path.join(root, 'tests/reports/bench/three'), runs: '1', warmup: '1', tiers: threeManifest.benchmark.tiers.map(tier => tier.id).join(','),
  engines: 'remotion,cpu,gpu,gpu-shared', only: threeManifest.benchmark.compositions.join(',')};
const flags = new Set();
const argv = process.argv.slice(2);
for (let index = 0; index < argv.length; index++) {
  const [key, inline] = argv[index].replace(/^--/, '').split('=', 2);
  if (['report-only', 'allow-unavailable-hardware'].includes(key)) { flags.add(key); continue; }
  if (!(key in options)) throw Error('Unknown argument: ' + argv[index]);
  options[key] = inline ?? argv[++index];
}
const runs = Number(options.runs), warmup = Number(options.warmup);
const engines = options.engines.split(',');
if (!engines.includes('remotion') || engines.some(engine => engine !== 'remotion' && !ENGINES[engine])) {
  throw Error('Engines must include remotion and any of cpu,gpu,gpu-shared');
}
const tiers = threeManifest.benchmark.tiers.filter(tier => options.tiers.split(',').includes(tier.id));
const compositions = options.only.split(',');
const out = path.resolve(options.out);
const work = fs.mkdtempSync(path.join(os.tmpdir(), 'motionswift-three-bench-'));
fs.mkdirSync(path.join(out, 'logs'), {recursive: true});
const native = nativeBin();
const {concurrency, minSSIM, minSpeedup} = threeManifest.benchmark;
const cores = Math.min(concurrency, os.availableParallelism?.() ?? os.cpus().length);

function run(bin, args, log) {
  const begin = process.hrtime.bigint();
  const result = spawnSync(bin, args, {cwd: root, encoding: 'utf8', maxBuffer: 64 * 1024 * 1024,
    env: {...process.env, MOTIONSWIFT_HOME: root}});
  const elapsed = Number(process.hrtime.bigint() - begin) / 1e6;
  fs.appendFileSync(log, `$ ${bin} ${args.join(' ')}\n${result.stdout || ''}${result.stderr || ''}\n${elapsed} ms\n`);
  if (result.error || result.status !== 0) throw Error(`${path.basename(bin)} failed (${result.error || 'exit ' + result.status}); see ${log}`);
  return elapsed;
}
function probe(video) {
  const result = spawnSync('ffprobe', ['-v', 'error', '-select_streams', 'v:0', '-count_packets', '-show_entries',
    'stream=width,height,nb_read_packets', '-of', 'json', video], {encoding: 'utf8'});
  return JSON.parse(result.stdout).streams[0];
}
function ssim(reference, candidate) {
  const result = spawnSync('ffmpeg', ['-hide_banner', '-i', reference, '-i', candidate, '-lavfi', '[0:v][1:v]ssim', '-f', 'null', '-'],
    {encoding: 'utf8', maxBuffer: 16 * 1024 * 1024});
  const value = Number([...(result.stderr || '').matchAll(/All:([\d.]+)/g)].at(-1)?.[1]);
  if (result.status !== 0 || !Number.isFinite(value)) throw Error('SSIM comparison failed');
  return value;
}

const results = [];
let failed = false;
try {
  for (const tier of tiers) {
    for (const id of compositions) {
      const record = {id, tier: tier.id, scale: tier.scale, engines: {}};
      results.push(record);
      for (const engine of engines) {
        const video = path.join(work, `${id}-${tier.id}-${engine}.mp4`);
        const log = path.join(out, 'logs', `${id}-${tier.id}-${engine}.log`);
        fs.writeFileSync(log, '');
        const args = engine === 'remotion'
          ? [path.join(testRoot, 'tools/render-remotion-three.mjs'), id, video, String(cores), String(tier.scale)]
          : ['render', '--project', threeProject, '--entry', threeManifest.entryPoint, id, video, '--codec=h264',
            `--backend=${ENGINES[engine][0]}`, `--encoder=${ENGINES[engine][1]}`, `--concurrency=${cores}`, `--scale=${tier.scale}`];
        const bin = engine === 'remotion' ? process.execPath : native;
        try {
          const times = [];
          for (let index = 0; index < warmup + runs; index++) {
            console.log(`${id} ${tier.id} ${engine} ${index < warmup ? 'warmup' : `run ${index - warmup + 1}/${runs}`}`);
            const elapsed = run(bin, args, log);
            if (index >= warmup) times.push(elapsed);
          }
          const metadata = probe(video);
          record.engines[engine] = {status: 'ok', runsMs: times, medianMs: median(times), video,
            frames: Number(metadata.nb_read_packets), width: metadata.width, height: metadata.height};
        } catch (error) {
          const unavailable = engine === 'gpu-shared' && flags.has('allow-unavailable-hardware');
          record.engines[engine] = {status: unavailable ? 'unavailable' : 'failed', error: String(error.message || error)};
          if (!unavailable) failed = true;
          console.error(`${id} ${tier.id} ${engine}: ${error.message || error}`);
        }
      }
      const reference = record.engines.remotion;
      for (const engine of engines.filter(name => name !== 'remotion')) {
        const measured = record.engines[engine];
        if (measured?.status !== 'ok' || reference?.status !== 'ok') continue;
        measured.ssim = ssim(reference.video, measured.video);
        measured.speedup = reference.medianMs / measured.medianMs;
        measured.parity = measured.frames === reference.frames && measured.width === reference.width
          && measured.height === reference.height && measured.ssim >= minSSIM;
        measured.fast = measured.speedup >= minSpeedup;
        if (!measured.parity || (!measured.fast && !flags.has('report-only'))) failed = true;
        console.log(`${id} ${tier.id} ${engine}: ${(measured.medianMs / 1000).toFixed(2)} s vs Remotion `
          + `${(reference.medianMs / 1000).toFixed(2)} s = ${measured.speedup.toFixed(2)}x, SSIM ${measured.ssim.toFixed(4)}`);
      }
    }
  }
} catch (error) {
  failed = true;
  results.push({error: String(error.stack || error)});
  console.error(error);
} finally {
  fs.rmSync(work, {recursive: true, force: true});
}

const speedups = Object.fromEntries(engines.filter(name => name !== 'remotion').map(engine => [engine,
  geometricMean(results.flatMap(record => record.engines?.[engine]?.parity ? [record.engines[engine].speedup] : []))]));
const report = {schema: 1, date: new Date().toISOString(), pins: threePins(), cores, concurrency: cores, runs, warmup,
  gate: {minSSIM, minSpeedup, enforced: !flags.has('report-only')}, machine: {platform: process.platform, arch: process.arch,
    cpu: os.cpus()[0]?.model, cores: os.cpus().length, memoryGB: Math.round(os.totalmem() / 2 ** 30)},
  pass: !failed, geometricMeanSpeedup: speedups,
  results: results.map(record => record.engines ? {...record, engines: Object.fromEntries(Object.entries(record.engines)
    .map(([name, value]) => [name, {...value, video: undefined}]))} : record)};
writeJSON(path.join(out, 'results.json'), report);
const cell = value => value?.status === 'ok' ? `${(value.medianMs / 1000).toFixed(2)} s` : (value?.status ?? '—');
const nativeEngines = engines.filter(name => name !== 'remotion');
const lines = [`## 3D benchmark — Remotion three.js vs native Metal`, '',
  `${report.machine.cpu}, ${cores} workers, ${runs} run(s) + ${warmup} warmup, gate: SSIM ≥ ${minSSIM}, speedup ≥ ${minSpeedup}× ${report.gate.enforced ? '' : '(report only)'}`, '',
  `| Fixture | Tier | Remotion | ${nativeEngines.map(name => `${name} (speedup, SSIM)`).join(' | ')} |`,
  `|---|---|---|${nativeEngines.map(() => '---').join('|')}|`,
  ...report.results.filter(record => record.engines).map(record => `| ${record.id} | ${record.tier} | ${cell(record.engines.remotion)} | ${nativeEngines.map(engine => {
    const value = record.engines[engine];
    return value?.speedup ? `${cell(value)} (${value.speedup.toFixed(2)}×, ${value.ssim.toFixed(4)}) ${value.parity && value.fast ? '✅' : '❌'}` : cell(value);
  }).join(' | ')} |`), '',
  `Geometric-mean speedup: ${nativeEngines.map(engine => `${engine} ${speedups[engine]?.toFixed(2) ?? '—'}×`).join(', ')}.`,
  report.pass ? '**PASS**' : '**FAIL**'];
fs.writeFileSync(path.join(out, 'summary.md'), lines.join('\n') + '\n');
console.log(lines.join('\n'));
process.exitCode = failed ? 1 : 0;
