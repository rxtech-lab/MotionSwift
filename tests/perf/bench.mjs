import {fixtureSourceHash,sha256} from '../tools/provenance.mjs';
import {probeHardwareEncoding} from '../tools/hardware-capabilities.mjs';
import {concurrencyFor} from './concurrency.mjs';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {spawnSync} from 'node:child_process';
import {median,stdev,geometricMean,sameMachine,parityMetadata} from './metrics.mjs';

// Keep GPU + x264 as the render-only comparison; GPU-HW changes only the encoder.
const ENGINES=['remotion','cpu','gpu','gpu-hw','gpu-shared'];
const NATIVE=['cpu','gpu','gpu-hw','gpu-shared'];
const ENCODERS={cpu:'software',gpu:'software','gpu-hw':'videotoolbox','gpu-shared':'videotoolbox-shared'};
const root=fileURLToPath(new URL('../..',import.meta.url));
function command(bin,args,cwd=root) {
  const result=spawnSync(bin,args,{cwd,encoding:'utf8',maxBuffer:128*1024*1024});
  if(result.error || result.status!==0)throw Error(`${bin}: ${result.error||result.stderr||result.stdout||result.status}`);
  return result.stdout;
}
function readJSON(file) { return JSON.parse(fs.readFileSync(file,'utf8')); }
function writeJSON(file,data) {fs.writeFileSync(file,JSON.stringify(data,null,2)+'\n');}
function parseArgs() {
  const options={};
  const allowed=['config','out','work-dir','runs','warmup','only','tiers','engines','native-bin','concurrency','baseline','regression-threshold','fail-on-regression','allow-unavailable-hardware'];
  for(let i=2;i<process.argv.length;i++) {
    const arg=process.argv[i]; const [key,inline]=arg.replace(/^--/,'').split('=',2);
    if(!arg.startsWith('--') || !allowed.includes(key) || options[key]!==undefined)throw Error(`Unknown/repeated argument: ${arg}`);
    options[key]=['fail-on-regression','allow-unavailable-hardware'].includes(key)?true:(inline??process.argv[++i]);
    if(options[key]===undefined)throw Error(`Missing --${key} value`);
  }
  return options;
}
function ssim(reference,candidate,logFile) {
  const compared=spawnSync('ffmpeg',['-hide_banner','-i',reference,'-i',candidate,'-lavfi','[0:v][1:v]ssim','-f','null','-'],
    {encoding:'utf8',maxBuffer:16*1024*1024});
  fs.writeFileSync(logFile,compared.stderr||'');
  const value=Number([...(compared.stderr||'').matchAll(/All:([\d.]+)/g)].at(-1)?.[1]);
  if(compared.status!==0||!Number.isFinite(value))throw Error('SSIM comparison failed');
  return value;
}

function main() {
const options=parseArgs();
const configFile=path.resolve(options.config||path.join(root,'tests/perf/bench.config.json'));
const config=readJSON(configFile);
const out=path.resolve(options.out||path.join(root,'tests/reports/bench'));
fs.mkdirSync(path.join(out,'logs'),{recursive:true});
const runs=Number(options.runs??config.runs),warmup=Number(options.warmup??config.warmup);
if(!Number.isInteger(runs)||runs<1||!Number.isInteger(warmup)||warmup<0)throw Error('Invalid runs/warmup');
// `native` is kept as an alias for the CPU engine used before the GPU backend existed.
const engines=[...new Set((options.engines||ENGINES.join(',')).split(',').map(engine=>engine==='native'?'cpu':engine))];
if(!engines.length||engines.some(engine=>!ENGINES.includes(engine)))throw Error(`Invalid engines; use ${ENGINES.join(',')}`);
const workerCounts=concurrencyFor(ENGINES,config,options.concurrency);
const concurrency=workerCounts.effective;
console.log(`Benchmark workers: ${JSON.stringify(concurrency)} (${workerCounts.availableCores} available cores)`);
const threshold=Number(options['regression-threshold']??0.15);
if(!Number.isFinite(threshold)||threshold<0)throw Error('Invalid regression threshold');
const tierConfig=config.tiers??[{id:'1x',scale:1,engines:ENGINES}];
const requestedTiers=options.tiers?.split(',');
const tiers=tierConfig.filter(tier=>!requestedTiers||requestedTiers.includes(tier.id));
if(!tiers.length||requestedTiers?.some(id=>!tiers.some(tier=>tier.id===id)))throw Error('No tiers or unknown --tiers ID');
for(const tier of tiers) {
  if(!/^\w+$/.test(tier.id)||!(tier.scale>0)||!(tier.engines??ENGINES).every(engine=>ENGINES.includes(engine)))throw Error(`Invalid tier ${tier.id}`);
}
const project=path.resolve(path.dirname(configFile),config.project);
const fixtureConfig=typeof config.fixtures==='string'?readJSON(path.resolve(path.dirname(configFile),config.fixtures)).fixtures:config.fixtures;
const requested=options.only?.split(',');
const fixtures=fixtureConfig.filter(f=>!requested||requested.includes(f.id));
if(!fixtures.length||requested?.some(id=>!fixtures.some(f=>f.id===id)))throw Error('No fixtures or unknown --only ID');
const machine={platform:`${os.platform()} ${os.release()} (${os.arch()})`,cpu:os.cpus()[0]?.model,
  cores:os.cpus().length,availableCores:workerCounts.availableCores,memoryGB:Math.round(os.totalmem()/1024**3),runner:process.env.RUNNER_NAME||os.hostname(),node:process.version};
const settings={runs,warmup,codec:config.codec,crf:18,preset:'medium',encoders:ENCODERS,hardwareQuality:65,concurrency,requestedConcurrency:workerCounts.requested,minSsim:config.minSsim,
  entryPoint:config.entryPoint,entrySha256:sha256(fs.readFileSync(path.resolve(project,config.entryPoint))),
  tiers:tiers.map(({id,scale,engines:tierEngines})=>({id,scale,engines:tierEngines??ENGINES})),regressionThreshold:threshold};
const baseline=options.baseline?readJSON(path.resolve(options.baseline)):null;
const sourceSha256=fixtureSourceHash();
const browserPin=readJSON(path.join(root,'tests/browser.lock.json'));
const comparableMachine=baseline?.schema===2 && baseline?.sourceSha256===sourceSha256 && JSON.stringify(baseline?.versions?.browser)===JSON.stringify(browserPin)
  && sameMachine(machine,baseline?.machine) && ['codec','crf','preset','encoders','hardwareQuality','concurrency','minSsim','tiers','entryPoint','entrySha256'].every(key=>JSON.stringify(settings[key])===JSON.stringify(baseline?.settings?.[key]));
const candidates=[options['native-bin'],process.env.MOTIONSWIFT_BIN,path.join(root,'.build/release/motionswift'),'motionswift'].filter(Boolean);
const native=candidates.find(file=>{try{return !!command(file,['--version']).trim();}catch{return false;}});
const versions={browser:browserPin,remotion:readJSON(path.join(root,'tests/node_modules/remotion/package.json')).version,
  native:native?command(native,['--version']).trim():null,ffmpeg:command('ffmpeg',['-version']).split('\n')[0]};
const comparableBaseline=comparableMachine&&baseline?.versions?.ffmpeg===versions.ffmpeg;
const workBase=path.resolve(options['work-dir']||os.tmpdir());fs.mkdirSync(workBase,{recursive:true});
const work=fs.mkdtempSync(path.join(workBase,'motionswift-bench-'));
function git(args) { try { return command('git',args).trim(); } catch { return 'uncommitted'; } }
const results={schema:2,createdAt:new Date().toISOString(),git:{sha:git(['rev-parse','HEAD']),ref:git(['branch','--show-current'])},
  machine,settings,versions,sourceSha256,baselineCompatible:comparableBaseline,fixtures:[],totals:{}};
let failed=false;
const hardware=engines.some(engine=>['gpu-hw','gpu-shared'].includes(engine))?probeHardwareEncoding():null;
results.hardwareEncoding=hardware;

function measure(record,engine,{fixture,tier,range,props,slug,expectedFrames}) {
  const times=[],logFile=`logs/${slug}-${engine}.log`,logPath=path.join(out,logFile);
  const video=path.join(work,`${slug}-${engine}.mp4`),report=path.join(work,`${slug}-${engine}-stages.json`);
  fs.writeFileSync(logPath,'');
  for(let index=0;index<warmup+runs;index++) {
    console.log(`${record.id} ${engine} ${index<warmup?'warmup':`run ${index-warmup+1}/${runs}`}`);
    const args=engine==='remotion'
      ?[path.join(root,'tests/tools/render-remotion.mjs'),project,config.entryPoint,fixture.composition,video,range,props,String(concurrency.remotion),String(tier.scale)]
      :['render','--project',project,'--entry',config.entryPoint,fixture.composition,video,'--codec=h264',`--backend=${engine.startsWith('gpu')?'gpu':engine}`,`--encoder=${ENCODERS[engine]}`,
        `--concurrency=${concurrency[engine]}`,`--scale=${tier.scale}`,`--frames=${range}`,`--props=${props}`,'--report-json',report];
    const begin=process.hrtime.bigint();
    const result=spawnSync(engine==='remotion'?process.execPath:native,args,{cwd:project,encoding:'utf8',maxBuffer:128*1024*1024});
    const elapsed=Number(process.hrtime.bigint()-begin)/1e6;
    fs.appendFileSync(logPath,`\nRun ${index}: ${elapsed} ms\n${result.stdout||''}\n${result.stderr||''}`);
    if(result.error||result.status!==0)throw Error(String(result.error||`exit ${result.status}, signal ${result.signal??'none'}`));
    if(index>=warmup)times.push(elapsed);
  }
  const metadata=JSON.parse(command('ffprobe',['-v','error','-select_streams','v:0','-count_packets','-show_entries',
    'stream=codec_name,width,height,r_frame_rate,nb_read_packets','-of','json',video])).streams[0];
  const count=Number(metadata?.nb_read_packets);
  if(count!==expectedFrames)throw Error(`Expected ${expectedFrames} frames, got ${count}`);
  const measured={status:'ok',runsMs:times,medianMs:median(times),stdevMs:stdev(times),frames:count,
    fps:count/(median(times)/1000),outputBytes:fs.statSync(video).size,metadata,logFile,video};
  if(engine!=='remotion') {
    measured.stages=readJSON(report);
    const expected=engine==='gpu-shared'?'videotoolbox-iosurface':`ffmpeg-${engine==='gpu-hw'?'h264_videotoolbox':'libx264'}-rawvideo-pipe`;
    if(measured.stages.encoder!==expected)throw Error(`Expected ${expected}, got ${measured.stages.encoder}`);
  }
  return measured;
}

try {
  for(const tier of tiers) for(const fixture of fixtures) {
    if(!/^[\w/-]+$/.test(fixture.id)||fixture.id.includes('..'))throw Error('Invalid fixture ID');
    const id=`${fixture.id}@${tier.id}`,slug=`${fixture.id.replaceAll('/','-')}-${tier.id}`;
    const range=Array.isArray(fixture.frames)?`${Math.min(...fixture.frames)}-${Math.max(...fixture.frames)}`:fixture.frames;
    if(!/^\d+-\d+$/.test(range))throw Error('Fixture needs an inclusive frame range');
    const [first,last]=range.split('-').map(Number),expectedFrames=last-first+1;
    if(expectedFrames<1)throw Error('Invalid frame range');
    const record={id,fixture:fixture.id,tier:tier.id,scale:tier.scale,composition:fixture.composition,frames:range,parity:{},speedups:{}};
    results.fixtures.push(record);
    const props=path.join(work,`${slug}-props.json`);writeJSON(props,fixture.props||{});
    const tierEngines=tier.engines??ENGINES;
    for(const engine of ENGINES) {
      if(!engines.includes(engine)||!tierEngines.includes(engine)||(engine!=='remotion'&&!native)) {record[engine]={status:'unavailable'};continue;}
      if(['gpu-hw','gpu-shared'].includes(engine)&&!hardware.available) {
        record[engine]={status:options['allow-unavailable-hardware']?'unavailable':'failed',error:hardware.reason};
        if(!options['allow-unavailable-hardware'])failed=true;
        continue;
      }
      try {record[engine]=measure(record,engine,{fixture,tier,range,props,slug,expectedFrames});}
      catch(error) {record[engine]={status:'failed',error:String(error),logFile:`logs/${slug}-${engine}.log`};failed=true;}
    }
    // Remotion is the reference when it ran; otherwise (tiers beyond Chrome's reliable scale)
    // the GPU backend is checked against the CPU backend, which is itself gated by the goldens.
    const reference=record.remotion.status==='ok'?'remotion':record.cpu.status==='ok'?'cpu':null;
    for(const engine of NATIVE) {
      if(!reference||engine===reference||record[engine].status!=='ok')continue;
      try {
        const value=ssim(record[reference].video,record[engine].video,path.join(out,'logs',`${slug}-${engine}-parity.log`));
        const pass=value>=config.minSsim&&parityMetadata(record[engine].metadata,record[reference].metadata);
        record.parity[engine]={reference,ssim:value,result:pass?'pass':'fail'};
        if(!pass)failed=true;
      } catch(error) {record.parity[engine]={reference,result:'fail',error:String(error)};failed=true;}
    }
    const passed=engine=>record[engine].status==='ok'&&(record.parity[engine]?.result==='pass'||reference===engine);
    if(passed('remotion')&&passed('cpu'))record.speedups.cpuVsRemotion=record.remotion.medianMs/record.cpu.medianMs;
    if(passed('remotion')&&passed('gpu'))record.speedups.gpuVsRemotion=record.remotion.medianMs/record.gpu.medianMs;
    if(passed('cpu')&&passed('gpu'))record.speedups.gpuVsCpu=record.cpu.medianMs/record.gpu.medianMs;
    if(passed('gpu')&&passed('gpu-hw'))record.speedups.hardwareVsSoftware=record.gpu.medianMs/record['gpu-hw'].medianMs;
    if(passed('cpu')&&passed('gpu-hw'))record.speedups.hardwareVsCpu=record.cpu.medianMs/record['gpu-hw'].medianMs;
    if(passed('gpu')&&passed('gpu-shared'))record.speedups.sharedVsSoftware=record.gpu.medianMs/record['gpu-shared'].medianMs;
    if(passed('gpu-hw')&&passed('gpu-shared'))record.speedups.sharedVsFFmpeg=record['gpu-hw'].medianMs/record['gpu-shared'].medianMs;
    if(passed('cpu')&&passed('gpu-shared'))record.speedups.sharedVsCpu=record.cpu.medianMs/record['gpu-shared'].medianMs;
    for(const engine of ENGINES)delete record[engine].video;
    const previous=baseline?.fixtures?.find(item=>item.id===record.id&&item.frames===record.frames&&item.composition===record.composition);
    if(comparableBaseline&&previous) {
      record.baseline={};
      for(const engine of NATIVE) {
        if(previous[engine]?.status!=='ok'||record[engine].status!=='ok')continue;
        const deltaPct=record[engine].medianMs/previous[engine].medianMs-1;
        record.baseline[engine]={medianMs:previous[engine].medianMs,deltaPct,regression:deltaPct>threshold};
        if(deltaPct>threshold&&options['fail-on-regression'])failed=true;
      }
    }
  }
} catch(error) {results.error=String(error);failed=true;}
finally {
  const geomean=key=>{const values=results.fixtures.map(item=>item.speedups[key]).filter(Boolean);return {geomean:geometricMean(values),fixtures:values.length};};
  results.totals={gpuVsRemotion:geomean('gpuVsRemotion'),cpuVsRemotion:geomean('cpuVsRemotion'),gpuVsCpu:geomean('gpuVsCpu'),
    hardwareVsSoftware:geomean('hardwareVsSoftware'),hardwareVsCpu:geomean('hardwareVsCpu'),
    sharedVsSoftware:geomean('sharedVsSoftware'),sharedVsFFmpeg:geomean('sharedVsFFmpeg'),sharedVsCpu:geomean('sharedVsCpu')};
  for(const tier of tiers) {
    const values=results.fixtures.filter(item=>item.tier===tier.id).map(item=>item.speedups.gpuVsCpu).filter(Boolean);
    results.totals[`gpuVsCpu@${tier.id}`]={geomean:geometricMean(values),fixtures:values.length};
    const hardware=results.fixtures.filter(item=>item.tier===tier.id).map(item=>item.speedups.hardwareVsSoftware).filter(Boolean);
    results.totals[`hardwareVsSoftware@${tier.id}`]={geomean:geometricMean(hardware),fixtures:hardware.length};
    const shared=results.fixtures.filter(item=>item.tier===tier.id).map(item=>item.speedups.sharedVsSoftware).filter(Boolean);
    results.totals[`sharedVsSoftware@${tier.id}`]={geomean:geometricMean(shared),fixtures:shared.length};
  }
  results.pass=!failed;
  writeJSON(path.join(out,'results.json'),results);
  fs.writeFileSync(path.join(out,'summary.md'),summary(results,{runs,warmup,concurrency,machine,versions,comparableMachine:comparableBaseline}));
  fs.rmSync(work,{recursive:true,force:true});
}
process.exitCode=failed?1:0;
}

function summary(results,{runs,warmup,concurrency,machine,versions,comparableMachine}) {
  const x=value=>value?`${value.toFixed(2)}×`:'—';
  const cell=record=>record.status==='ok'?`${(record.medianMs/1000).toFixed(2)} s (${record.fps.toFixed(0)} fps)`:record.status==='unavailable'?'—':`❌ ${record.status}`;
  const size=item=>{const meta=(item.gpu.metadata||item.cpu.metadata||item.remotion.metadata);return meta?`${meta.width}×${meta.height}`:'—';};
  const parity=item=>NATIVE.map(engine=>{const p=item.parity[engine];return p?`${p.ssim?.toFixed(4)??'—'} ${p.result==='pass'?'✅':'❌'}`:'—';}).join(' / ');
  const delta=item=>{const d=item.baseline?.gpu;return d?`${(d.deltaPct*100).toFixed(1)}%${d.regression?' 🔺':''}`:'—';};
  const rows=results.fixtures.map(item=>`| ${item.id} | ${size(item)} | ${cell(item.remotion)} | ${cell(item.cpu)} | ${cell(item.gpu)} | ${cell(item['gpu-hw'])} | ${cell(item['gpu-shared'])} | ${x(item.speedups.hardwareVsSoftware)} | **${x(item.speedups.sharedVsSoftware)}** | ${x(item.speedups.sharedVsFFmpeg)} | ${parity(item)} | ${delta(item)} |`);
  const totals=results.totals;
  const perTier=Object.entries(totals).filter(([key])=>key.startsWith('gpuVsCpu@')).map(([key,value])=>`${key.slice(9)} ${x(value.geomean)}`).join(', ');
  const hardwareTiers=Object.entries(totals).filter(([key])=>key.startsWith('hardwareVsSoftware@')).map(([key,value])=>`${key.split('@')[1]} ${x(value.geomean)}`).join(', ');
  const sharedTiers=Object.entries(totals).filter(([key])=>key.startsWith('sharedVsSoftware@')).map(([key,value])=>`${key.split('@')[1]} ${x(value.geomean)}`).join(', ');
  return `<!-- motionswift-bench -->\n## MotionSwift benchmark: Remotion vs native CPU vs native GPU\n\n`+
    (results.hardwareEncoding&&!results.hardwareEncoding.available
      ?`**Hardware encoding unavailable on this runner.** Hardware cells are excluded, not counted as passing or replaced with software. Session probe: ${results.hardwareEncoding.reason.split('\n')[0]}\n\n`:'')+
    `- **Shared IOSurface vs Metal + x264**: **${x(totals.sharedVsSoftware.geomean)}** over ${totals.sharedVsSoftware.fixtures} parity-passing fixture(s); by resolution: ${sharedTiers||'—'}.\n`+
    `- **Shared IOSurface vs FFmpeg VideoToolbox**: **${x(totals.sharedVsFFmpeg.geomean)}**; vs CPU + x264: **${x(totals.sharedVsCpu.geomean)}**.\n`+
    `- **Hardware vs software encoding** (both Metal rendering): **${x(totals.hardwareVsSoftware.geomean)}** over ${totals.hardwareVsSoftware.fixtures} parity-passing fixture(s); by resolution: ${hardwareTiers||'—'}.\n`+
    `- **Metal + hardware vs CPU + software**: **${x(totals.hardwareVsCpu.geomean)}** over ${totals.hardwareVsCpu.fixtures} fixture(s).\n`+
    `- **GPU vs CPU** (native Skia Metal vs Skia raster): **${x(totals.gpuVsCpu.geomean)}** geometric mean over ${totals.gpuVsCpu.fixtures} fixture(s); by resolution: ${perTier||'—'}.\n`+
    `- **GPU vs Remotion**: **${x(totals.gpuVsRemotion.geomean)}** over ${totals.gpuVsRemotion.fixtures} fixture(s) with output parity.\n`+
    `- **CPU vs Remotion**: **${x(totals.cpuVsRemotion.geomean)}** over ${totals.cpuVsRemotion.fixtures} fixture(s) with output parity.\n\n`+
    `| Fixture | Size | Remotion | CPU + x264 | Metal + x264 | FFmpeg VT | Shared IOSurface VT | FFmpeg VT vs x264 | Shared vs x264 | Shared vs FFmpeg VT | SSIM CPU / GPU / HW / Shared | GPU vs main |\n|---|---|---|---|---|---|---|---|---|---|---|---|\n${rows.join('\n')}\n\n`+
    `Machine: ${machine.cpu}; ${machine.platform}; ${machine.cores} cores (${machine.availableCores} available); ${machine.memoryGB} GB; runner ${machine.runner}. Worker counts are capped to available cores; requested: ${JSON.stringify(results.settings.requestedConcurrency)}.\n\n`+
    `Runs: ${runs}, warmups: ${warmup}. Workers: Remotion ${concurrency.remotion}, CPU ${concurrency.cpu}, GPU ${concurrency.gpu}, GPU-HW ${concurrency['gpu-hw']}, Shared ${concurrency['gpu-shared']}. Times are wall clock including startup and encoding. `+
    `Software: x264 CRF 18, medium. FFmpeg hardware: h264_videotoolbox quality 65, no software fallback; CPU readback/conversion and pipe remain. Shared: F16 -> BGRA8 GPU resolve into IOSurface, then native AVFoundation/VideoToolbox quality 0.65 with hardware required; no application CPU pixel readback or pipe. GPU completion is synchronized before submission; encoder color conversion may still occur. These quality controls are not equivalent; speedups require SSIM >= ${results.settings.minSsim}. SSIM reference is Remotion when available, otherwise CPU + x264. Output bytes and frame p50 are recorded in results.json.\n\n`+
    `Baseline ${comparableMachine?'matches this machine and settings':'unavailable or different machine/settings; deltas omitted'}.\n\n`+
    `Versions: Remotion ${versions.remotion}; ${versions.native||'native unavailable'}.\n\n`+
    `<details><summary>Raw runs and environment</summary>\n\n\`\`\`json\n${JSON.stringify(results,null,2)}\n\`\`\`\n</details>\n\n`+
    `${results.error?`Error: ${results.error}\n\n`:''}Full logs and results.json: workflow artifact **bench-results**.\n`;
}

try { main(); } catch(error) { console.error(error); process.exitCode=2; }
