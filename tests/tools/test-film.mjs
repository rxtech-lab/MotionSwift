// Local real-content render check. Source and output remain private/gitignored.
// node tests/tools/test-film.mjs stage|remotion|native|samples|compare [source-project]
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import os from 'node:os';
import {spawn} from 'node:child_process';
import {bundle} from '@remotion/bundler';
import {selectComposition, renderMedia, renderStill} from '@remotion/renderer';
import {PNG} from 'pngjs';
import {browserOptions, browserLock} from './browser.mjs';
import {testFilmChromiumOptions} from './test-film-gate.mjs';
import {root, testRoot, nativeBin, writeJSON, readJSON} from './common.mjs';
import {compareFiles} from './compare.mjs';

const output = path.join(testRoot, 'fixtures/test-film/local');
const project = path.join(output, 'project');
const hash = data => crypto.createHash('sha256').update(data).digest('hex');
const [mode, sourceArg] = process.argv.slice(2);
const manifestPath = path.join(output, 'source.json');
// Exercise the progressive lyrics well after the long manuscript scene enters.
const detailFrames = [1800, 2100, 2400];
const sampleFrames = source => [...new Set([...source.frames, ...detailFrames])].filter(f=>f<source.duration).sort((a,b)=>a-b);
function command(bin, args, log, cwd = root) {
  return new Promise((resolve, reject) => {
    const child = spawn(bin, args, {cwd, env:{...process.env, MOTIONSWIFT_HOME:root}});
    const stream = fs.createWriteStream(log);
    child.stdout.pipe(stream); child.stderr.pipe(stream);
    child.on('error', reject);
    child.on('close', code => stream.end(() => code === 0 ? resolve() : reject(Error(`${bin} exited ${code}; see ${log}`))));
  });
}
function stage() {
  const base = sourceArg || path.join(os.homedir(), 'Desktop/test-film/music-translator.rxfilmstudio/Remotion');
  const source = fs.existsSync(path.join(base, 'src')) ? base : path.join(base, fs.readdirSync(base).find(name => fs.existsSync(path.join(base, name, 'src'))));
  if (fs.existsSync(manifestPath)) throw Error('Already staged; use a new local output folder for a changed source');
  fs.mkdirSync(project, {recursive:true});
  fs.cpSync(path.join(source, 'src'), path.join(project, 'src'), {recursive:true});
  fs.symlinkSync(path.join(testRoot, 'node_modules'), path.join(project, 'node_modules'), 'dir');
  const files = fs.readdirSync(path.join(source, 'src')).sort().map(name => ({name, sha256:hash(fs.readFileSync(path.join(source, 'src', name)))}));
  const text = fs.readFileSync(path.join(source, 'src/Composition.tsx'), 'utf8');
  const cues = JSON.parse(text.match(/const cues=(\[.*?\]);/s)[1]);
  const duration = Number(text.match(/COMPOSITION_DURATION_IN_FRAMES\s*=\s*(\d+)/)[1]);
  const frames = [...new Set([0, ...cues.flatMap(cue => [Math.round(cue.at * 30) + 18, Math.round(cue.at * 30) + 60])])].filter(f => f < duration).sort((a,b)=>a-b);
  writeJSON(manifestPath, {source, stagedAt:new Date().toISOString(), files, duration, fps:30, width:1920, height:1080, cues, frames});
  console.log(`Staged unchanged source; ${duration} frames, ${frames.length} visual samples`);
}
async function webp(engine) {
  const frames = path.join(output, `${engine}-preview-frames`);
  fs.mkdirSync(frames, {recursive:true});
  await command('ffmpeg', ['-y','-v','error','-i',path.join(output,`${engine}.mp4`),'-vf','fps=10,scale=960:-1:flags=lanczos',path.join(frames,'%05d.png')], path.join(output,`${engine}-webp.log`));
  const files = fs.readdirSync(frames).filter(f=>f.endsWith('.png')).sort();
  await command('img2webp', ['-loop','0','-lossy','-q','80','-m','4','-d','100',...files,'-o',path.join(output,`${engine}.webp`)],path.join(output,`${engine}-webp-encode.log`),frames);
  console.log(`${engine} animated WebP: ${files.length} frames`);
  fs.rmSync(frames, {recursive:true});
}
function verifiedSource() {
  const source = readJSON(manifestPath);
  for (const file of source.files) {
    if (hash(fs.readFileSync(path.join(project,'src',file.name))) !== file.sha256) throw Error(`Staged source changed: ${file.name}`);
  }
  return source;
}
function newer(outputFile, inputs) {
  return fs.existsSync(outputFile) && inputs.every(input => fs.statSync(outputFile).mtimeMs >= fs.statSync(input).mtimeMs);
}
function contactSheets(frames) {
  const sheets = [];
  for (const [name, selected] of [['settled', frames.filter((_,i)=>i>0 && i%2===0)], ['transition', frames.filter((_,i)=>i%2===1)], ['lyrics', detailFrames]]) {
    for (let start=0; start<selected.length; start+=12) {
      const batch = selected.slice(start,start+12);
      const png = new PNG({width:1920,height:Math.ceil(batch.length/2)*270});
      png.data.fill(255);
      for (const [i,frame] of batch.entries()) {
        const pair = PNG.sync.read(fs.readFileSync(path.join(output,`pair-${frame}.png`)));
        for (let y=0;y<270;y++) pair.data.copy(png.data,((Math.floor(i/2)*270+y)*1920+(i%2)*960)*4,y*960*4,(y+1)*960*4);
      }
      const file = `${name}-${start/12+1}.png`;
      fs.writeFileSync(path.join(output,file),PNG.sync.write(png));
      sheets.push({file,frames:batch});
    }
  }
  return sheets;
}
async function renderRemotion() {
  const source = verifiedSource();
  const browser = {...await browserOptions(),chromiumOptions:testFilmChromiumOptions};
  const serveUrl = await bundle({entryPoint:path.join(project,'src/index.ts')});
  const composition = await selectComposition({...browser,serveUrl,id:'Main'});
  if (composition.durationInFrames !== source.duration) throw Error('Unexpected composition duration');
  writeJSON(path.join(output,'remotion-settings.json'), {composition, browserLock, chromiumOptions:testFilmChromiumOptions, version:JSON.parse(fs.readFileSync(path.join(testRoot,'node_modules/remotion/package.json'))).version});
  fs.mkdirSync(path.join(output,'remotion-stills'), {recursive:true});
  for (const frame of sampleFrames(source)) {
    const png = path.join(output,`remotion-stills/${frame}.png`);
    await renderStill({...browser,serveUrl,composition,frame,output:png,imageFormat:'png',logLevel:'error'});
    console.log(`Remotion still ${frame}/${source.duration - 1}`);
  }
  const start = performance.now();
  let last = -1;
  await renderMedia({...browser,serveUrl,composition,outputLocation:path.join(output,'remotion.mp4'),codec:'h264',crf:18,x264Preset:'medium',pixelFormat:'yuv420p',concurrency:8,disableSharedMemoryCapture:true,
    onProgress:({progress})=>{const step=Math.floor(progress*20); if(step>last){last=step;console.log(`Remotion video ${step*5}%`);}}});
  writeJSON(path.join(output,'remotion-timing.json'), {wallMs:performance.now()-start});
  await webp('remotion');
}
async function renderNative() {
  const source = verifiedSource(), bin = nativeBin();
  writeJSON(path.join(output,'native-settings.json'),{binarySha256:hash(fs.readFileSync(bin)),backend:'cpu',concurrency:8,encoder:'software'});
  fs.mkdirSync(path.join(output,'native-stills'), {recursive:true});
  const args = ['--project',project,'--entry','src/index.ts','Main'];
  for (const frame of sampleFrames(source)) {
    await command(bin, ['still',...args,path.join(output,`native-stills/${frame}.png`),`--frame=${frame}`,'--backend=cpu'],path.join(output,'native-still.log'));
    console.log(`Native still ${frame}/${source.duration - 1}`);
  }
  await command(bin, ['render',...args,path.join(output,'native.mp4'),'--backend=cpu','--concurrency=8',`--report-json=${path.join(output,'native-timing.json')}`],path.join(output,'native-render.log'));
  await webp('native');
}
async function compare(stillsOnly = false) {
  const source = verifiedSource(), results = [];
  for (const frame of sampleFrames(source)) {
    const expected = path.join(output,`remotion-stills/${frame}.png`), actual = path.join(output,`native-stills/${frame}.png`);
    const metrics = compareFiles(expected,actual);
    let squared = 0;
    const a = PNG.sync.read(fs.readFileSync(expected)), b = PNG.sync.read(fs.readFileSync(actual));
    for(let i=0;i<a.data.length;i++) squared += (a.data[i]-b.data[i])**2;
    const rmse = Math.sqrt(squared/a.data.length);
    results.push({frame,seconds:frame/source.fps,...metrics,rmse,expectedSha256:hash(fs.readFileSync(expected)),actualSha256:hash(fs.readFileSync(actual))});
    for (const engine of ['remotion','native']) {
      const input = path.join(output,`${engine}-stills/${frame}.png`), webp = path.join(output,`${engine}-stills/${frame}.webp`);
      if (!newer(webp,[input])) await command('cwebp',['-quiet','-lossless',input,'-o',webp],path.join(output,'still-webp.log'));
    }
    const pair = path.join(output,`pair-${frame}.png`);
    if (!newer(pair,[expected,actual])) await command('ffmpeg',['-y','-v','error','-i',expected,'-i',actual,'-filter_complex','[0:v]scale=480:270[a];[1:v]scale=480:270[b];[a][b]hstack','-frames:v','1',pair],path.join(output,'pair.log'));
  }
  const sheets = contactSheets(source.frames);
  let ssim = null;
  if (!stillsOnly) {
    for (const engine of ['remotion','native']) {
      await command('ffprobe',['-v','error','-count_frames','-show_entries','stream=codec_name,width,height,r_frame_rate,nb_read_frames,duration','-of','json',path.join(output,`${engine}.mp4`)],path.join(output,`${engine}-probe.json`));
      const video = readJSON(path.join(output,`${engine}-probe.json`)).streams[0];
      if (Number(video.nb_read_frames)!==source.duration || video.width!==source.width || video.height!==source.height || video.r_frame_rate!=='30/1') throw Error(`${engine} video metadata mismatch`);
    }
    await command('ffmpeg',['-v','info','-i',path.join(output,'remotion.mp4'),'-i',path.join(output,'native.mp4'),'-lavfi','ssim','-f','null','-'],path.join(output,'video-ssim.log'));
    ssim = Number(fs.readFileSync(path.join(output,'video-ssim.log'),'utf8').match(/All:([\d.]+)/)?.[1]);
    if (!Number.isFinite(ssim) || ssim < 0 || ssim > 1) throw Error('Missing or invalid full-video SSIM');
  }
  writeJSON(path.join(output,'comparison.json'),{generatedAt:new Date().toISOString(),strictPixelThreshold:0.003,allStrictPassed:results.every(r=>r.pass),videoSSIM:ssim,contactSheets:sheets,results});
  const cards = results.map(r=>`<article><h2>Frame ${r.frame} · ${r.seconds.toFixed(2)}s</h2><p>Exact differing pixels: ${(r.diffRatio*100).toFixed(2)}%; RMSE: ${r.rmse.toFixed(2)}; strict gate: ${r.pass?'PASS':'FAIL'}</p><div><a href="remotion-stills/${r.frame}.webp"><img src="remotion-stills/${r.frame}.webp" alt="Remotion frame ${r.frame}"></a><a href="native-stills/${r.frame}.webp"><img src="native-stills/${r.frame}.webp" alt="Native frame ${r.frame}"></a></div></article>`).join('\n');
  fs.writeFileSync(path.join(output,'index.html'),`<!doctype html><meta charset="utf-8"><title>Test Film: Remotion / MotionSwift</title><style>body{font:16px system-ui;margin:32px;background:#171717;color:#eee}div{display:flex;gap:8px}div>a{width:50%}img{width:100%}article{margin-bottom:32px}a{color:#8cf}video{width:48%}</style><h1>Remotion (left) / MotionSwift Skia CPU (right)</h1><p>Unchanged TSX; full ${source.duration}-frame 1920×1080 / 30fps silent composition. Animated WebP previews: 960×540 / 10fps. Individual WebP stills are lossless at original resolution.</p><p>Video SSIM: ${ssim}. Strict pixel gate passed ${results.filter(r=>r.pass).length}/${results.length} samples.</p><p><a href="remotion.webp">Remotion animated WebP</a> · <a href="native.webp">Native animated WebP</a> · <a href="comparison.json">Metrics</a></p><video controls src="remotion.mp4"></video><video controls src="native.mp4"></video>${cards}`);
  console.log(`Compared ${results.length} stills; strict pass ${results.filter(r=>r.pass).length}; video SSIM ${ssim}`);
}
if (mode==='stage') stage();
else if (mode==='remotion') await renderRemotion();
else if (mode==='native') await renderNative();
else if (mode==='compare') await compare();
else if (mode==='samples') await compare(true);
else if (mode==='webp-native') await webp('native');
else if (mode==='webp-remotion') await webp('remotion');
else throw Error('Usage: test-film.mjs stage|remotion|native|samples|compare [source-project]');
