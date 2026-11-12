// Private source stays on the self-hosted runner; only reviewed WebP goldens and metadata are checked in.
// `baseline` is an explicit local operation after reviewing test-film.mjs output.
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import {spawnSync} from 'node:child_process';
import {PNG} from 'pngjs';
import {bundle} from '@remotion/bundler';
import {selectComposition, renderStill} from '@remotion/renderer';
import {browserLock, browserOptions} from './browser.mjs';
import {root, testRoot, nativeBin, readJSON, writeJSON} from './common.mjs';
import {compareFiles} from './compare.mjs';
import {sha256, pixelHash, validateBaseline, assessFrame, testFilmChromiumOptions, maxChannelDelta} from './test-film-gate.mjs';

const fixture = path.join(testRoot,'fixtures/test-film');
const baselineFile = path.join(fixture,'baseline.json');
const goldens = path.join(fixture,'golden');
const output = path.join(testRoot,'reports/test-film');
const pins = {
  remotionVersion:readJSON(path.join(testRoot,'package-lock.json')).packages['node_modules/remotion'].version,
  browser:browserLock, chromiumOptions:testFilmChromiumOptions, platform:process.platform, arch:process.arch,
};
const escape = value => String(value).replaceAll('&','&amp;').replaceAll('<','&lt;').replaceAll('"','&quot;');

function command(bin,args) {
  const result=spawnSync(bin,args,{encoding:'utf8',timeout:120000});
  if(result.error || result.status!==0) throw Error(`${bin}: ${result.error || result.stderr}`);
}
function saveGolden(frame,png) {
  fs.mkdirSync(goldens,{recursive:true});
  const file=path.join(goldens,`${frame}.webp`);
  command('cwebp',['-quiet','-lossless',png,'-o',file]);
  return sha256(fs.readFileSync(file));
}

function baseline() {
  const local = path.join(fixture,'local'), source = readJSON(path.join(local,'source.json'));
  const reviewed = readJSON(path.join(local,'comparison.json'));
  const reference = readJSON(path.join(local,'remotion-settings.json'));
  if (reference.version !== pins.remotionVersion || JSON.stringify(reference.browserLock) !== JSON.stringify(browserLock))
    throw Error('Reviewed Remotion output does not match the current pins');
  if (JSON.stringify(reference.chromiumOptions) !== JSON.stringify(pins.chromiumOptions))
    throw Error('Rerender and review Remotion with the pinned software Chromium renderer first');
  if (readJSON(path.join(local,'native-settings.json')).binarySha256 !== sha256(fs.readFileSync(nativeBin())))
    throw Error('Reviewed native output was produced by a different binary; rerender and review first');
  for (const file of source.files) {
    if (sha256(fs.readFileSync(path.join(local,'project/src',file.name))) !== file.sha256) throw Error('Reviewed source changed');
  }
  const result = {schema:1, ...pins, backend:'cpu',
    note:'Reviewed snapshots for each engine. Exact cross-engine pixel parity is reported separately and is not claimed.',
    composition:{id:'Main',width:source.width,height:source.height,fps:source.fps,durationInFrames:source.duration},
    files:source.files,
    frames:reviewed.results.map(row=>({frame:row.frame,
      remotionWebP:saveGolden(row.frame,path.join(local,`remotion-stills/${row.frame}.png`)),
      nativeRGBA:pixelHash(path.join(local,`native-stills/${row.frame}.png`),source.width,source.height),
      remotionRGBA:pixelHash(path.join(local,`remotion-stills/${row.frame}.png`),source.width,source.height)})),
  };
  validateBaseline(result,pins);
  writeJSON(baselineFile,result);
  console.log(`Recorded ${result.frames.length} reviewed frame pairs and lossless Remotion WebP goldens`);
}

function findSource() {
  const base = process.env.TEST_FILM_PROJECT || path.join(os.homedir(),'Desktop/test-film/music-translator.rxfilmstudio/Remotion');
  if (!fs.existsSync(base)) throw Error('Private Test Film source is missing; set TEST_FILM_PROJECT on the self-hosted runner');
  if (fs.existsSync(path.join(base,'src'))) return base;
  const projects = fs.readdirSync(base).map(name=>path.join(base,name)).filter(dir=>fs.existsSync(path.join(dir,'src')));
  if (projects.length !== 1) throw Error('Set TEST_FILM_PROJECT to the exact Remotion project directory');
  return projects[0];
}

// Explicit review operation only. Ordinary CI never accepts its own new output.
function baselineCI() {
  const expected = readJSON(baselineFile), report = readJSON(path.join(output,'results.json'));
  validateBaseline(expected,pins);
  if (JSON.stringify(report.pins) !== JSON.stringify(pins)
    || report.nativeBinarySha256 !== sha256(fs.readFileSync(nativeBin())) || report.error
    || report.results.length !== expected.frames.length || !report.results.every(row=>row.deterministic))
    throw Error('Review capture must be complete, deterministic, and match current renderer pins');
  for (const row of expected.frames) {
    const actual = report.results.find(result=>result.frame === row.frame);
    if (!actual) throw Error(`Missing reviewed CI frame ${row.frame}`);
    for (const [key,file] of [['nativeRGBA','native.png'],['remotionRGBA','remotion.png']]) {
      const digest = pixelHash(path.join(output,String(row.frame),file),expected.composition.width,expected.composition.height);
      const reported = key === 'remotionRGBA' ? (actual.remotionRawRGBA || actual[key]) : actual[key];
      if (digest !== reported) throw Error(`Review capture changed: ${row.frame}/${file}`);
      row[key] = digest;
      if (key === 'remotionRGBA') row.remotionWebP=saveGolden(row.frame,path.join(output,String(row.frame),file));
    }
  }
  expected.note = 'Reviewed normal-runner native CPU and pinned software Chrome snapshots. Native hashes are exact. Chrome allows at most 0.3% changed pixels with a maximum one-unit channel delta. No automatic baseline updates.';
  writeJSON(baselineFile,expected);
  console.log('Recorded explicitly reviewed CI snapshots');
}

function nativeStill(bin, project, frame, file, log) {
  const result = spawnSync(bin,['still','--project',project,'--entry','src/index.ts','Main',file,`--frame=${frame}`,'--backend=cpu'],
    {cwd:root,encoding:'utf8',maxBuffer:64*1024*1024,timeout:120000,env:{...process.env,MOTIONSWIFT_HOME:root}});
  fs.writeFileSync(log,`${result.stdout || ''}${result.stderr || ''}`);
  if (result.error || result.status !== 0) throw Error(`Native frame ${frame} failed: ${result.error || `exit ${result.status}`}; see ${log}`);
}

async function check() {
  fs.rmSync(output,{recursive:true,force:true});
  fs.mkdirSync(output,{recursive:true});
  const report = {pass:false, strictPixelThreshold:0.003, results:[]};
  let temporary;
  try {
    const expected = readJSON(baselineFile);
    validateBaseline(expected,pins);
    const source = findSource();
    temporary = fs.mkdtempSync(path.join(os.tmpdir(),'motionswift-test-film-'));
    const project = path.join(temporary,'project');
    fs.mkdirSync(path.join(project,'src'),{recursive:true});
    for (const file of expected.files) {
      const data = fs.readFileSync(path.join(source,'src',file.name));
      if (sha256(data) !== file.sha256) throw Error(`Test Film source changed: ${file.name}; review a new baseline explicitly`);
      fs.writeFileSync(path.join(project,'src',file.name),data);
    }
    fs.symlinkSync(path.join(testRoot,'node_modules'),path.join(project,'node_modules'),'dir');
    const bin = nativeBin(), browser = {...await browserOptions(),chromiumOptions:testFilmChromiumOptions};
    const serveUrl = await bundle({entryPoint:path.join(project,'src/index.ts')});
    const composition = await selectComposition({...browser,serveUrl,id:'Main'});
    for (const [key,value] of Object.entries(expected.composition)) {
      if (composition[key] !== value) throw Error(`Composition ${key} changed`);
    }
    report.pins = pins;
    report.nativeBinarySha256 = sha256(fs.readFileSync(bin));
    for (const row of expected.frames) {
      const dir = path.join(output,String(row.frame));
      fs.mkdirSync(dir,{recursive:true});
      const golden=path.join(goldens,`${row.frame}.webp`), decoded=path.join(dir,'remotion-baseline.png');
      if (!row.remotionWebP || sha256(fs.readFileSync(golden)) !== row.remotionWebP) throw Error(`Missing/changed Remotion golden: ${row.frame}`);
      command('ffmpeg',['-v','error','-y','-i',golden,'-frames:v','1','-pix_fmt','rgba',decoded]);
      if (pixelHash(decoded,composition.width,composition.height) !== row.remotionRGBA) throw Error(`Lossless golden pixel mismatch: ${row.frame}`);
      const native = path.join(dir,'native.png'), reference = path.join(dir,'remotion.png'), repeat = path.join(dir,'repeat.png');
      await renderStill({...browser,serveUrl,composition,frame:row.frame,output:reference,imageFormat:'png',logLevel:'error'});
      nativeStill(bin,project,row.frame,native,path.join(dir,'native.log'));
      nativeStill(bin,project,row.frame,repeat,path.join(dir,'repeat.log'));
      const {width,height} = composition;
      const nativeRGBA = pixelHash(native,width,height), remotionRawRGBA = pixelHash(reference,width,height);
      const remotionRGBA = remotionRawRGBA;
      const referenceComparison=compareFiles(decoded,reference,path.join(dir,'reference-comparison'),0.003);
      referenceComparison.maxChannelDelta=maxChannelDelta(PNG.sync.read(fs.readFileSync(decoded)).data,PNG.sync.read(fs.readFileSync(reference)).data);
      referenceComparison.pass &&= referenceComparison.maxChannelDelta <= 1;
      const verdict = assessFrame(row,nativeRGBA,remotionRGBA,pixelHash(repeat,width,height),referenceComparison);
      fs.unlinkSync(repeat);
      const crossEngine = compareFiles(reference,native,path.join(dir,'comparison'),0.003);
      report.results.push({frame:row.frame,...verdict,nativeRGBA,remotionRGBA,remotionRawRGBA,referenceComparison,crossEngine});
      console.log(`${verdict.pass?'PASS':'FAIL'} test-film@${row.frame}; cross-engine differing pixels ${(crossEngine.diffRatio*100).toFixed(4)}%`);
    }
    report.pass = report.results.length === expected.frames.length && report.results.every(row=>row.pass);
  } catch (error) {
    report.error = String(error);
    console.error(report.error);
  } finally {
    if (temporary) fs.rmSync(temporary,{recursive:true,force:true});
    writeJSON(path.join(output,'results.json'),report);
    const strictPassed = report.results.filter(row=>row.crossEngine.pass).length;
    const summary = `### Test Film visual regression: ${report.pass?'PASS':'FAIL'}\n\n${report.results.length} frame pairs checked: native exact pixel hashes and repeatability; Remotion lossless goldens with at most 0.3% changed pixels and a maximum one-unit channel delta.\n\nExact cross-engine parity: ${strictPassed}/${report.results.length} at the unchanged 0.3% threshold (informational; known font/raster differences).\n\n${report.error ? `Error: ${report.error}\n\n` : ''}Side-by-side frames and differences are in the **visual-results** artifact under test-film/.\n`;
    fs.writeFileSync(path.join(output,'summary.md'),summary);
    if (process.env.GITHUB_STEP_SUMMARY) fs.appendFileSync(process.env.GITHUB_STEP_SUMMARY,summary);
    fs.writeFileSync(path.join(output,'index.html'),`<!doctype html><meta charset="utf-8"><title>Test Film CI visual review</title><style>body{font:16px system-ui;background:#171717;color:#eee;margin:32px}section{margin:32px 0}img{width:32%}pre{white-space:pre-wrap}</style><h1>Test Film visual regression: ${report.pass?'PASS':'FAIL'}</h1><p>Remotion / native / difference. Regression compares each engine with its reviewed output; native is exact, Chrome allows only bounded one-unit rounding. Cross-engine pixel parity is separate.</p>${report.error?`<pre>${escape(report.error)}</pre>`:''}${report.results.map(row=>`<section><h2>Frame ${row.frame}: ${row.pass?'PASS':'FAIL'}</h2><p>Native snapshot: ${row.nativeMatch}; Remotion snapshot: ${row.referenceMatch} (changed pixels: ${(row.referenceComparison.diffRatio*100).toFixed(6)}%, max channel delta: ${row.referenceComparison.maxChannelDelta}; <a href="${row.frame}/reference-comparison/diff.png">reference diff</a>); repeatable: ${row.deterministic}; cross-engine changed pixels: ${(row.crossEngine.diffRatio*100).toFixed(4)}%</p>${['expected','actual','diff'].map(name=>`<a href="${row.frame}/comparison/${name}.png"><img src="${row.frame}/comparison/${name}.png" alt="${name} frame ${row.frame}"></a>`).join('')}</section>`).join('')}`);
    process.exitCode = report.pass ? 0 : 1;
  }
}

const mode = process.argv[2] || 'check';
if (mode === 'baseline') baseline();
else if (mode === 'baseline-ci') baselineCI();
else if (mode === 'check') await check();
else throw Error('Usage: test-film-ci.mjs check|baseline|baseline-ci');
