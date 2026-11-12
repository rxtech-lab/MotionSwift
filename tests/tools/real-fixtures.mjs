// Phase 0 validation on real Film Studio compositions.
//
// Film Studio projects contain private user content (narration, titles, local paths) and this
// repository is public, so raw sources are staged into the gitignored
// tests/compositions/real/local/ folder. Only anonymized, hash-backed reports are written to
// tracked paths:
//   tests/compositions/real/manifest.json      per-fixture support census
//   tests/perf/baseline/film-studio.json       Remotion stage baselines
//
// Usage:
//   node tests/tools/real-fixtures.mjs stage [--source <film-studio remotion/projects dir>]
//   node tests/tools/real-fixtures.mjs check
//   node tests/tools/real-fixtures.mjs baseline --ids fs01,fs02 [--frames 0-119] [--runs 3] [--warmup 1] [--concurrency 8]
//   node tests/tools/real-fixtures.mjs summarize
import crypto from 'node:crypto';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import {testRoot,root,nativeBin,writeJSON,readJSON,parseOptions} from './common.mjs';

const realDir=path.join(testRoot,'compositions/real');
const localDir=path.join(realDir,'local');
const idMapFile=path.join(localDir,'idmap.json');
const manifestFile=path.join(realDir,'manifest.json');
const reportDir=path.join(testRoot,'reports/phase0');
const baselineFile=path.join(testRoot,'perf/baseline/film-studio.json');
const defaultSource=path.join(os.homedir(),'Library/Application Support/com.rxlab.film-workflow/remotion/projects');

const sha256=data=>crypto.createHash('sha256').update(data).digest('hex');
function sourceFiles(dir) {
  const out=[];
  const walk=d=>fs.readdirSync(d,{withFileTypes:true}).sort((a,b)=>a.name.localeCompare(b.name,'en')).forEach(e=>{
    const f=path.join(d,e.name);
    if(e.isDirectory())walk(f); else if(e.isFile()&&/\.(tsx?|json)$/.test(e.name))out.push(f);
  });
  walk(dir);
  return out;
}
function sourceHash(projectDir) {
  const hash=crypto.createHash('sha256');
  for(const f of sourceFiles(path.join(projectDir,'src'))){hash.update(path.relative(projectDir,f));hash.update(fs.readFileSync(f));}
  return hash.digest('hex');
}
function staged() {
  if(!fs.existsSync(idMapFile))throw Error('Run `stage` first');
  return readJSON(idMapFile);
}

// Static feature probe. Heuristic: counts source matches, so it can over-report (comments) but
// it is used only to label why a fixture is outside the supported subset, never to pass one.
const FEATURES={
  text:/fontSize|<(h[1-6]|p|span)[\s>]|>[^<>{}\n]*[A-Za-z]{3,}[^<>{}\n]*<\//,
  svg:/<(svg|path|circle|rect|line|g)\b/,
  gradient:/(linear|radial|conic)-gradient\(|<linearGradient|<radialGradient/,
  shadow:/boxShadow|textShadow|drop-shadow/,
  filter:/\bfilter:|backdropFilter|mixBlendMode/,
  image:/<(Img|img)\b/,
  video:/<(OffthreadVideo|Video)\b/,
  audio:/<Audio\b/,
  font:/fontFamily|loadFont/,
};
function probe(projectDir) {
  const text=sourceFiles(path.join(projectDir,'src')).map(f=>fs.readFileSync(f,'utf8')).join('\n');
  const features=Object.fromEntries(Object.entries(FEATURES).map(([k,re])=>[k,text.split('\n').filter(l=>re.test(l)).length]));
  return {lines:text.split('\n').length,features};
}

// Collapse TypeScript diagnostics to stable, path-free categories so the tracked manifest never
// contains user paths or source text.
function category(message) {
  const rules=[
    [/Module '"remotion"' has no exported member '(\w+)'/,m=>`remotion API: ${m[1]}`],
    [/Property '(\w+)' does not exist on type 'JSX\.IntrinsicElements'/,m=>`JSX element: <${m[1]}>`],
    [/'(\w+)' cannot be used as a JSX component/,m=>`JSX element: <${m[1]}>`],
    [/Property '(\w+)' does not exist on type '\{ linear/,m=>`Easing.${m[1]}`],
    [/'(\w+)' does not exist in type 'MotionCSSProperties'/,m=>`CSS property: ${m[1]}`],
    [/Object literal may only specify known properties, and '(\w+)' does not exist/,m=>`CSS property: ${m[1]}`],
    [/Type '"([^"]+)"' is not assignable to type '"center"'/,m=>`CSS value: transformOrigin ${m[1]}`],
    [/Type '"([\w-]+)"' is not assignable to type '"flex" \| "none"/,m=>`CSS value: display ${m[1]}`],
    [/Type '"([\w-]+)"' is not assignable to type '"(?:absolute|relative)/,m=>`CSS value: position ${m[1]}`],
    [/^Type 'string' is not assignable to type 'number'/,()=>'CSS value: string where only numbers are accepted'],
  ];
  for(const [re,f] of rules){const m=message.match(re);if(m)return f(m);}
  return 'other type error';
}

function stage(argv) {
  const opts=parseOptions(argv,['source']);
  const source=path.resolve(opts.source||defaultSource);
  const projects=fs.readdirSync(source).filter(n=>fs.existsSync(path.join(source,n,'src/index.ts'))).sort();
  if(!projects.length)throw Error(`No Remotion projects under ${source}`);
  fs.mkdirSync(localDir,{recursive:true});
  const map={source,stagedAt:new Date().toISOString(),fixtures:{}};
  projects.forEach((name,i)=>{
    const id=`fs${String(i+1).padStart(2,'0')}`;
    const from=path.join(source,name), to=path.join(localDir,id);
    fs.rmSync(to,{recursive:true,force:true});
    fs.mkdirSync(to,{recursive:true});
    for(const entry of ['src','public','tsconfig.json','package.json','remotion.config.ts'])
      if(fs.existsSync(path.join(from,entry)))fs.cpSync(path.join(from,entry),path.join(to,entry),{recursive:true});
    // Remotion renders use the Film Studio runtime's own pinned dependencies.
    const modules=fs.realpathSync(path.join(from,'node_modules'));
    fs.symlinkSync(modules,path.join(to,'node_modules'));
    map.fixtures[id]={origin:name,sourceSha256:sourceHash(to)};
    console.log(id,map.fixtures[id].sourceSha256.slice(0,16));
  });
  writeJSON(idMapFile,map);
}

function check() {
  const map=staged(), bin=nativeBin(), out=path.join(reportDir,'check');
  fs.mkdirSync(out,{recursive:true});
  const fixtures=[], totals={};
  for(const [id,info] of Object.entries(map.fixtures)) {
    const dir=path.join(localDir,id);
    if(sourceHash(dir)!==info.sourceSha256)throw Error(`${id} changed since staging; re-run stage`);
    const r=spawnSync(bin,['check','--project',dir,'--entry','src/index.ts'],
      {cwd:root,encoding:'utf8',maxBuffer:64*1024*1024,timeout:300000,env:{...process.env,MOTIONSWIFT_HOME:root}});
    fs.writeFileSync(path.join(out,`${id}.stdout`),r.stdout||'');fs.writeFileSync(path.join(out,`${id}.stderr`),r.stderr||'');
    let diagnostics=[];
    try{diagnostics=JSON.parse(r.stdout||'[]');}catch{/* non-JSON failure: recorded via stage */}
    const stageName=r.status===0?'passed':/Type checking failed/.test(r.stderr)?'typecheck':'compile/runtime';
    const categories={};
    for(const d of diagnostics){const c=category(d.message);categories[c]=(categories[c]||0)+1;}
    for(const c of Object.keys(categories))totals[c]=(totals[c]||0)+1;
    const still=stillProbe(bin,dir,id,out);
    fixtures.push({id,sourceSha256:info.sourceSha256,...probe(dir),
      native:{exitCode:r.status,failedAt:stageName,diagnostics:diagnostics.length,categories:Object.fromEntries(Object.entries(categories).sort((a,b)=>b[1]-a[1]))},
      still,supported:r.status===0});
    console.log(id,`exit=${r.status}`,stageName,`${diagnostics.length} diagnostics`,`still=${still.exitCode} ${still.failedAt}`);
  }
  const commit=spawnSync('git',['rev-parse','HEAD'],{cwd:root,encoding:'utf8'}).stdout.trim();
  writeJSON(manifestFile,{
    note:'Anonymized census of real Film Studio compositions. Raw sources stay in the gitignored local/ folder because they contain private user content.',
    generatedAt:new Date().toISOString(),commit,nativeBinarySha256:sha256(fs.readFileSync(bin)),
    command:'node tests/tools/real-fixtures.mjs check',
    supported:fixtures.filter(f=>f.supported).map(f=>f.id),
    stillPassed:fixtures.filter(f=>f.still.exitCode===0).map(f=>f.id),
    blockersByFixtureCount:Object.fromEntries(Object.entries(totals).sort((a,b)=>b[1]-a[1])),
    fixtures,
  });
  console.log(`supported ${fixtures.filter(f=>f.supported).length}/${fixtures.length} → ${path.relative(root,manifestFile)}`);
}

// Bypasses the type checker: renders frame 30 so runtime/compiler blockers show up even when `check` fails.
function stillProbe(bin,dir,id,out) {
  const r=spawnSync(bin,['still','--project',dir,'--entry','src/index.ts','Main',path.join(out,`${id}-f30.png`),'--frame=30'],
    {cwd:root,encoding:'utf8',maxBuffer:64*1024*1024,timeout:300000,env:{...process.env,MOTIONSWIFT_HOME:root}});
  fs.writeFileSync(path.join(out,`${id}-still.stdout`),r.stdout||'');fs.writeFileSync(path.join(out,`${id}-still.stderr`),r.stderr||'');
  if(r.status===0)return {exitCode:0,failedAt:'passed',reasons:{}};
  const reasons={};
  const text=`${r.stdout||''}${r.stderr||''}`, json=text.slice(text.indexOf('['),text.lastIndexOf(']')+1);
  try{for(const d of JSON.parse(json)){const k=`${d.rule}: ${d.message}`;reasons[k]=(reasons[k]||0)+1;}}
  catch{const line=`${r.stdout}${r.stderr}`.split('\n').find(l=>/Error|error:/.test(l))||'unknown failure';reasons[`runtime: ${line.trim().slice(0,160)}`]=1;}
  const runtime=Object.keys(reasons).every(k=>k.startsWith('runtime:'));
  return {exitCode:r.status,failedAt:runtime?'runtime':'diagnostics',reasons:Object.fromEntries(Object.entries(reasons).sort((a,b)=>b[1]-a[1]))};
}

function parseRemotionLog(text) {
  const ms=re=>{const m=text.match(re);return m?Number(m[1]):null;};
  const slowest=[...text.matchAll(/Frame (\d+) \(([\d.]+)ms\)/g)].map(m=>({frame:Number(m[1]),ms:Number(m[2])}));
  return {
    version:text.match(/remotion-v([\d.]+)-assets/)?.[1]??null,
    concurrency:ms(/Using concurrency: (\d+)/),
    bundleMs:ms(/Bundling done in (\d+)ms/),
    renderFramesMs:ms(/Rendering frames done in (\d+)ms/),
    stitchMs:ms(/Stitching done in (\d+)ms/),
    captureMs:ms(/capture => (\d+)ms/),
    slowestFrameMs:slowest[0]?.ms??null,
    wallMs:ms(/wall=([\d.]+)s/)!==null?Math.round(ms(/wall=([\d.]+)s/)*1000):null,
    ok:/rc=0 wall/.test(text),
  };
}

function baseline(argv) {
  const opts=parseOptions(argv,['ids','frames','runs','warmup','concurrency']);
  const map=staged(), ids=(opts.ids||Object.keys(map.fixtures).join(',')).split(',');
  const runs=Number(opts.runs||3), warmup=Number(opts.warmup||1), frames=opts.frames||'0-119', concurrency=opts.concurrency||'8';
  const out=path.join(reportDir,'remotion');fs.mkdirSync(out,{recursive:true});
  for(const id of ids) {
    if(!map.fixtures[id])throw Error(`Unknown fixture ${id}`);
    const dir=path.join(localDir,id);
    if(sourceHash(dir)!==map.fixtures[id].sourceSha256)throw Error(`${id} changed since staging; re-run stage`);
    for(let i=0;i<warmup+runs;i++) {
      const tag=i<warmup?`${id}-rw${i||''}`:`${id}-r${i-warmup+1}`;
      const start=performance.now();
      const r=spawnSync('npx',['--no-install','remotion','render','src/index.ts','Main',path.join(out,`${tag}.mp4`),
        `--frames=${frames}`,`--concurrency=${concurrency}`,'--log=verbose'],{cwd:dir,encoding:'utf8',maxBuffer:256*1024*1024});
      const wall=((performance.now()-start)/1000).toFixed(2);
      fs.writeFileSync(path.join(out,`${tag}.log`),`${r.stdout}${r.stderr}${tag} rc=${r.status} wall=${wall}s\n`);
      console.log(tag,`rc=${r.status}`,`${wall}s`);
    }
  }
  writeFileSettings({frames,concurrency,runs,warmup});
}
function writeFileSettings(settings){writeJSON(path.join(reportDir,'remotion/settings.json'),settings);}

function summarize() {
  const map=staged(), out=path.join(reportDir,'remotion');
  const settings=readJSON(path.join(out,'settings.json'));
  const manifest=fs.existsSync(manifestFile)?readJSON(manifestFile):{fixtures:[]};
  const median=a=>{const s=a.filter(v=>v!==null).sort((x,y)=>x-y);return s.length?s[Math.floor((s.length-1)/2)]:null;};
  const fixtures=[];
  for(const id of Object.keys(map.fixtures)) {
    const logs=fs.readdirSync(out).filter(f=>new RegExp(`^${id}-r\\d+\\.log$`).test(f)).sort();
    if(!logs.length)continue;
    const measured=logs.map(f=>parseRemotionLog(fs.readFileSync(path.join(out,f),'utf8')));
    const probe=ffprobe(path.join(out,logs[0].replace('.log','.mp4')));
    const keys=['wallMs','bundleMs','renderFramesMs','stitchMs','captureMs','slowestFrameMs'];
    fixtures.push({id,sourceSha256:map.fixtures[id].sourceSha256,output:probe,
      allRunsOk:measured.every(m=>m.ok),
      median:Object.fromEntries(keys.map(k=>[k,median(measured.map(m=>m[k]))])),
      runs:measured.map(m=>Object.fromEntries(keys.map(k=>[k,m[k]]))),
      remotionVersion:measured[0].version,concurrency:measured[0].concurrency,
      nativeSupported:manifest.fixtures.find(f=>f.id===id)?.supported??null});
  }
  const ffmpeg=spawnSync('ffmpeg',['-version'],{encoding:'utf8'}).stdout?.split('\n')[0]??null;
  writeJSON(baselineFile,{
    note:'Remotion baselines for anonymized real Film Studio compositions. Wall time includes CLI startup, bundling, browser launch, frame capture, encoding, and stitching.',
    generatedAt:new Date().toISOString(),
    command:`node tests/tools/real-fixtures.mjs baseline --frames ${settings.frames} --runs ${settings.runs} --warmup ${settings.warmup} --concurrency ${settings.concurrency}`,
    settings:{...settings,invocation:`npx --no-install remotion render src/index.ts Main <out>.mp4 --frames=${settings.frames} --concurrency=${settings.concurrency} --log=verbose (run from tests/compositions/real/local/<id>, whose node_modules links to the Film Studio runtime's pinned dependencies)`},
    machine:{platform:`${os.platform()} ${os.release()} (${os.arch()})`,cpu:os.cpus()[0]?.model,cores:os.cpus().length,memoryGB:Math.round(os.totalmem()/1024**3),node:process.version,ffmpeg},
    fixtures,
  });
  console.log(`${fixtures.length} fixtures → ${path.relative(root,baselineFile)}`);
}
function ffprobe(file) {
  if(!fs.existsSync(file))return null;
  const r=spawnSync('ffprobe',['-v','error','-select_streams','v:0','-count_frames','-show_entries','stream=width,height,r_frame_rate,nb_read_frames,codec_name','-of','json',file],{encoding:'utf8'});
  const s=JSON.parse(r.stdout||'{}').streams?.[0];
  return s?{codec:s.codec_name,width:s.width,height:s.height,fps:s.r_frame_rate,frames:Number(s.nb_read_frames)}:null;
}

const [command,...rest]=process.argv.slice(2);
const commands={stage,check,baseline,summarize};
if(!commands[command]){console.error('usage: real-fixtures.mjs stage|check|baseline|summarize');process.exit(2);}
commands[command](rest);
