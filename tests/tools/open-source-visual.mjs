// Compare open-source MIT Remotion compositions across real Chrome Remotion and native MotionSwift.
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import {bundle} from '@remotion/bundler';
import {selectComposition, renderStill} from '@remotion/renderer';
import {PNG} from 'pngjs';
import {browserOptions} from './browser.mjs';
import {compareFiles} from './compare.mjs';
import {root, testRoot, nativeBin, readJSON, run, writeJSON} from './common.mjs';
import {measureProcess} from '../perf/memory.mjs';
import {geometricMean} from '../perf/metrics.mjs';

const allowedFlags = new Set(['--stills-only', '--write-docs', '--concurrency']);
let stillsOnly = false;
let writeDocs = false;
let concurrency = 8;
for (let i = 2; i < process.argv.length; i++) {
  const arg = process.argv[i];
  const [flag, inline] = arg.split('=', 2);
  if (!allowedFlags.has(flag)) throw Error(`Usage: open-source-visual.mjs [--stills-only] [--write-docs] [--concurrency=8]`);
  if (flag === '--stills-only') stillsOnly = true;
  else if (flag === '--write-docs') writeDocs = true;
  else if (flag === '--concurrency') concurrency = Number(inline ?? process.argv[++i]);
}
if (!Number.isInteger(concurrency) || concurrency < 1) throw Error('Invalid --concurrency');

const project = path.join(root, 'Examples/MotionShowcase/OpenSource');
const entry = 'index.tsx';
const provenance = readJSON(path.join(project, 'provenance.json'));
const outputDir = path.join(testRoot, 'reports/open-source');
const docsDir = path.join(root, 'docs/images/rendering');

const FEATURED_CLIPS = [
  {id: 'ProductDemo', range: '200-319'},
  {id: 'DynamicIsland', range: '0-149'},
  {id: 'BarChartAnim', range: '0-149'},
  {id: 'LowerThirdGlassCard', range: '0-119'},
  {id: 'BackgroundAurora', range: '0-119'},
  {id: 'ShapeCircularProgress', range: '0-89'},
];

function ffmpegMetric(reference, candidate, filter, regex) {
  const res = spawnSync(
    'ffmpeg',
    ['-hide_banner', '-i', reference, '-i', candidate, '-lavfi', `[0:v][1:v]${filter}`, '-f', 'null', '-'],
    {encoding: 'utf8', maxBuffer: 16 * 1024 * 1024}
  );
  const raw = [...(res.stderr || '').matchAll(regex)].at(-1)?.[1];
  if (res.status !== 0 || !raw) {
    throw Error(`ffmpeg ${filter} failed:\n${res.stderr || res.stdout}`);
  }
  return raw === 'inf' ? 99 : Number(raw);
}

function pixelChannelStats(expectedPath, actualPath) {
  const expected = PNG.sync.read(fs.readFileSync(expectedPath));
  const actual = PNG.sync.read(fs.readFileSync(actualPath));
  if (expected.width !== actual.width || expected.height !== actual.height) {
    throw Error(`Dimension mismatch: ${expected.width}x${expected.height} vs ${actual.width}x${actual.height}`);
  }
  const pixels = expected.width * expected.height;
  let changed = 0;
  let gt8 = 0;
  let maxDelta = 0;
  for (let i = 0; i < pixels * 4; i += 4) {
    const dr = Math.abs(expected.data[i] - actual.data[i]);
    const dg = Math.abs(expected.data[i + 1] - actual.data[i + 1]);
    const db = Math.abs(expected.data[i + 2] - actual.data[i + 2]);
    const da = Math.abs(expected.data[i + 3] - actual.data[i + 3]);
    const m = Math.max(dr, dg, db, da);
    if (m > 0) changed++;
    if (m > 8) gt8++;
    if (m > maxDelta) maxDelta = m;
  }
  return {
    pixels,
    diffRatio: changed / pixels,
    gt8Ratio: gt8 / pixels,
    maxChannelDelta: maxDelta,
  };
}

async function timedCommand(bin, args, cwd = root) {
  const begin = process.hrtime.bigint();
  const result = await measureProcess(bin, args, {cwd, env: {...process.env}});
  const elapsedMs = Number(process.hrtime.bigint() - begin) / 1e6;
  if (result.error || result.status !== 0) {
    throw Error(`${bin} ${args.join(' ')}\n${result.error || result.stderr || result.stdout}`);
  }
  return {
    elapsedSeconds: elapsedMs / 1000,
    peakRssMiB: result.memory?.peakRssBytes ? result.memory.peakRssBytes / (1024 * 1024) : null,
  };
}

const browser = await browserOptions();
const bin = nativeBin();
fs.mkdirSync(outputDir, {recursive: true});

console.log('Bundling OpenSource compositions with @remotion/bundler...');
const serveUrl = await bundle({entryPoint: path.join(project, entry), publicDir: null});

const stillResults = [];
for (const item of provenance.compositions) {
  const dir = path.join(outputDir, 'stills', item.id);
  fs.mkdirSync(dir, {recursive: true});
  const remotionPng = path.join(dir, 'remotion.png');
  const gpuPng = path.join(dir, 'gpu.png');
  const cpuPng = path.join(dir, 'cpu.png');

  const composition = await selectComposition({...browser, serveUrl, id: item.id});
  await renderStill({
    ...browser,
    serveUrl,
    composition,
    frame: item.previewFrame,
    output: remotionPng,
    imageFormat: 'png',
    logLevel: 'error',
  });

  run(bin, ['still', '--project', project, '--entry', entry, item.id, gpuPng, `--frame=${item.previewFrame}`, '--backend=gpu']);
  run(bin, ['still', '--project', project, '--entry', entry, item.id, cpuPng, `--frame=${item.previewFrame}`, '--backend=cpu']);

  const gpuStats = pixelChannelStats(remotionPng, gpuPng);
  const cpuVsGpu = compareFiles(cpuPng, gpuPng, null, 0);
  const ssim = ffmpegMetric(remotionPng, gpuPng, 'ssim', /All:([\d.]+)/g);
  const psnr = ffmpegMetric(remotionPng, gpuPng, 'psnr', /average:(inf|[\d.]+)/g);

  const record = {
    id: item.id,
    title: item.title,
    repositoryId: item.repositoryId,
    unmodified: item.unmodified,
    width: item.width,
    height: item.height,
    frame: item.previewFrame,
    ssim,
    psnrDb: psnr,
    diffRatio: gpuStats.diffRatio,
    gt8Ratio: gpuStats.gt8Ratio,
    maxChannelDelta: gpuStats.maxChannelDelta,
    cpuVsGpuDiffRatio: cpuVsGpu.diffRatio,
  };
  stillResults.push(record);
  console.log(
    `STILL ${item.id}@${item.previewFrame}: SSIM=${ssim.toFixed(4)} PSNR=${psnr.toFixed(2)}dB ` +
      `diff=${(gpuStats.diffRatio * 100).toFixed(2)}% >8lvl=${(gpuStats.gt8Ratio * 100).toFixed(2)}%`
  );
}

const videoResults = [];
const workDir = fs.mkdtempSync(path.join(os.tmpdir(), 'motionswift-opensource-'));
const emptyProps = path.join(workDir, 'props.json');
fs.writeFileSync(emptyProps, '{}\n');

if (!stillsOnly) {
  const videoDir = path.join(outputDir, 'videos');
  fs.mkdirSync(videoDir, {recursive: true});

  for (const clip of FEATURED_CLIPS) {
    const meta = provenance.compositions.find((c) => c.id === clip.id);
    const [startFrame, endFrame] = clip.range.split('-').map(Number);
    const frames = endFrame - startFrame + 1;
    const remotionMp4 = path.join(videoDir, `${clip.id}-remotion.mp4`);
    const gpuX264Mp4 = path.join(videoDir, `${clip.id}-gpu-x264.mp4`);
    const gpuSharedMp4 = path.join(videoDir, `${clip.id}-gpu-shared.mp4`);

    console.log(`VIDEO ${clip.id} (${clip.range}, ${frames}f) — Remotion...`);
    const remotionRun = await timedCommand(process.execPath, [
      path.join(root, 'tests/tools/render-remotion.mjs'),
      project,
      entry,
      clip.id,
      remotionMp4,
      clip.range,
      emptyProps,
      String(concurrency),
      '1',
    ]);

    console.log(`VIDEO ${clip.id} (${clip.range}, ${frames}f) — MotionSwift Metal + x264...`);
    const gpuX264Run = await timedCommand(bin, [
      'render',
      '--project',
      project,
      '--entry',
      entry,
      clip.id,
      gpuX264Mp4,
      '--codec=h264',
      '--backend=gpu',
      '--encoder=software',
      `--concurrency=${concurrency}`,
      `--frames=${clip.range}`,
    ]);

    console.log(`VIDEO ${clip.id} (${clip.range}, ${frames}f) — MotionSwift Metal + Shared VideoToolbox...`);
    const gpuSharedRun = await timedCommand(bin, [
      'render',
      '--project',
      project,
      '--entry',
      entry,
      clip.id,
      gpuSharedMp4,
      '--codec=h264',
      '--backend=gpu',
      '--encoder=videotoolbox-shared',
      `--concurrency=${concurrency}`,
      `--frames=${clip.range}`,
    ]);

    const ssimX264 = ffmpegMetric(remotionMp4, gpuX264Mp4, 'ssim', /All:([\d.]+)/g);
    const ssimShared = ffmpegMetric(remotionMp4, gpuSharedMp4, 'ssim', /All:([\d.]+)/g);
    const speedupX264 = remotionRun.elapsedSeconds / gpuX264Run.elapsedSeconds;
    const speedupShared = remotionRun.elapsedSeconds / gpuSharedRun.elapsedSeconds;

    const record = {
      id: clip.id,
      title: meta.title,
      repositoryId: meta.repositoryId,
      unmodified: meta.unmodified,
      resolution: `${meta.width}x${meta.height}`,
      range: clip.range,
      frames,
      remotionSeconds: remotionRun.elapsedSeconds,
      remotionPeakRssMiB: remotionRun.peakRssMiB,
      gpuX264Seconds: gpuX264Run.elapsedSeconds,
      gpuX264PeakRssMiB: gpuX264Run.peakRssMiB,
      gpuX264Speedup: speedupX264,
      gpuX264Ssim: ssimX264,
      gpuSharedSeconds: gpuSharedRun.elapsedSeconds,
      gpuSharedPeakRssMiB: gpuSharedRun.peakRssMiB,
      gpuSharedSpeedup: speedupShared,
      gpuSharedSsim: ssimShared,
    };
    videoResults.push(record);
    console.log(
      `VIDEO ${clip.id}: Remotion=${remotionRun.elapsedSeconds.toFixed(2)}s (${Math.round(remotionRun.peakRssMiB ?? 0)} MiB) | ` +
        `Metal+x264=${gpuX264Run.elapsedSeconds.toFixed(2)}s (${speedupX264.toFixed(2)}x, SSIM ${ssimX264.toFixed(4)}) | ` +
        `Metal+SharedVT=${gpuSharedRun.elapsedSeconds.toFixed(2)}s (${speedupShared.toFixed(2)}x, SSIM ${ssimShared.toFixed(4)}, ${Math.round(gpuSharedRun.peakRssMiB ?? 0)} MiB)`
    );
  }
}

if (writeDocs) {
  fs.mkdirSync(docsDir, {recursive: true});
  for (const clip of FEATURED_CLIPS) {
    const stillDir = path.join(outputDir, 'stills', clip.id);
    const remotionSrc = path.join(stillDir, 'remotion.png');
    const motionSrc = path.join(stillDir, 'gpu.png');
    const remotionOut = path.join(docsDir, `OpenSource-${clip.id}-remotion.png`);
    const motionOut = path.join(docsDir, `OpenSource-${clip.id}-motionswift.png`);
    run('ffmpeg', ['-y', '-hide_banner', '-loglevel', 'error', '-i', remotionSrc, '-vf', 'scale=640:-2:flags=lanczos', remotionOut]);
    run('ffmpeg', ['-y', '-hide_banner', '-loglevel', 'error', '-i', motionSrc, '-vf', 'scale=640:-2:flags=lanczos', motionOut]);
  }

  if (!stillsOnly) {
    const videoDir = path.join(outputDir, 'videos');
    const gifOut = path.join(docsDir, 'OpenSourceSwiftUI.gif');
    const gridInputs = ['ProductDemo', 'DynamicIsland', 'LowerThirdGlassCard', 'BackgroundAurora'].map((id) =>
      path.join(videoDir, `${id}-gpu-x264.mp4`)
    );
    const filterComplex = [
      '[0:v]trim=0.8:3.8,setpts=PTS-STARTPTS,fps=15,scale=384:216:force_original_aspect_ratio=decrease:flags=lanczos,pad=384:216:(ow-iw)/2:(oh-ih)/2:color=0x0b0f19[v0]',
      '[1:v]trim=0.8:3.8,setpts=PTS-STARTPTS,fps=15,scale=384:216:flags=lanczos[v1]',
      '[2:v]trim=0.8:3.8,setpts=PTS-STARTPTS,fps=15,scale=384:216:flags=lanczos[v2]',
      '[3:v]trim=0.8:3.8,setpts=PTS-STARTPTS,fps=15,scale=384:216:flags=lanczos[v3]',
      '[v0][v1][v2][v3]xstack=inputs=4:layout=0_0|w0_0|0_h0|w0_h0,split[s0][s1]',
      '[s0]palettegen=max_colors=128:stats_mode=diff[p]',
      '[s1][p]paletteuse=dither=bayer:bayer_scale=3',
    ].join(';');
    run('ffmpeg', [
      '-y',
      '-hide_banner',
      '-loglevel',
      'error',
      '-i',
      gridInputs[0],
      '-i',
      gridInputs[1],
      '-i',
      gridInputs[2],
      '-i',
      gridInputs[3],
      '-filter_complex',
      filterComplex,
      gifOut,
    ]);
  }
}

const summary = {
  createdAt: new Date().toISOString(),
  machine: {
    platform: `${os.platform()} ${os.release()} (${os.arch()})`,
    cpu: os.cpus()[0]?.model,
    cores: os.cpus().length,
    memoryGB: Math.round(os.totalmem() / 1024 ** 3),
  },
  concurrency,
  stills: stillResults,
  videos: videoResults,
  totals: videoResults.length
    ? {
        gpuX264GeomeanSpeedup: geometricMean(videoResults.map((v) => v.gpuX264Speedup)),
        gpuSharedGeomeanSpeedup: geometricMean(videoResults.map((v) => v.gpuSharedSpeedup)),
        minVideoSsimX264: Math.min(...videoResults.map((v) => v.gpuX264Ssim)),
        minVideoSsimShared: Math.min(...videoResults.map((v) => v.gpuSharedSsim)),
      }
    : null,
};

writeJSON(path.join(outputDir, 'results.json'), summary);
fs.rmSync(workDir, {recursive: true, force: true});
if (summary.totals) {
  console.log(
    `\nGEOMEAN SPEEDUP (6 clips): Metal+x264=${summary.totals.gpuX264GeomeanSpeedup.toFixed(2)}x, ` +
      `Metal+SharedVT=${summary.totals.gpuSharedGeomeanSpeedup.toFixed(2)}x`
  );
}
