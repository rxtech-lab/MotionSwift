import {fixtureSourceHash} from '../tools/provenance.mjs';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {spawnSync} from 'node:child_process';
import {median,stdev,geometricMean,sameMachine,parityMetadata} from './metrics.mjs';

const root=fileURLToPath(new URL('../..',import.meta.url));
function command(bin,args,cwd=root) {
  const result=spawnSync(bin,args,{cwd,encoding:'utf8',maxBuffer:128*1024*1024});
  if(result.error || result.status!==0)throw Error(`${bin}: ${result.error||result.stderr||result.stdout||result.status}`);
  return result.stdout;
}
function readJSON(file) { return JSON.parse(fs.readFileSync(file,'utf8')); }
function writeJSON(file,data) {fs.writeFileSync(file,JSON.stringify(data,null,2)+'\n');}
function main() {
const options={};
const allowed=['config','out','work-dir','runs','warmup','only','engines','native-bin','concurrency','baseline','regression-threshold','fail-on-regression'];
for(let i=2;i<process.argv.length;i++) {
  const arg=process.argv[i]; const [key,inline]=arg.replace(/^--/,'').split('=',2);
  if(!arg.startsWith('--') || !allowed.includes(key) || options[key]!==undefined)throw Error(`Unknown/repeated argument: ${arg}`);
  options[key]=key==='fail-on-regression'?true:(inline??process.argv[++i]);
  if(options[key]===undefined)throw Error(`Missing --${key} value`);
}
const configFile=path.resolve(options.config||path.join(root,'tests/perf/bench.config.json'));
const config=readJSON(configFile);
const out=path.resolve(options.out||path.join(root,'tests/reports/bench'));
fs.mkdirSync(path.join(out,'logs'),{recursive:true});
const runs=Number(options.runs??config.runs),warmup=Number(options.warmup??config.warmup);
if(!Number.isInteger(runs)||runs<1||!Number.isInteger(warmup)||warmup<0)throw Error('Invalid runs/warmup');
const engines=(options.engines||'remotion,native').split(',');
if(!engines.length||engines.some(engine=>!['remotion','native'].includes(engine)))throw Error('Invalid engines');
const concurrency=Number(options.concurrency??config.concurrency??1);
if(!Number.isInteger(concurrency)||concurrency<1)throw Error('Invalid concurrency');
const threshold=Number(options['regression-threshold']??0.15);
if(!Number.isFinite(threshold)||threshold<0)throw Error('Invalid regression threshold');
const project=path.resolve(path.dirname(configFile),config.project);
const fixtureConfig=typeof config.fixtures==='string'?readJSON(path.resolve(path.dirname(configFile),config.fixtures)).fixtures:config.fixtures;
const requested=options.only?.split(',');
const fixtures=fixtureConfig.filter(f=>!requested||requested.includes(f.id));
if(!fixtures.length||requested?.some(id=>!fixtures.some(f=>f.id===id)))throw Error('No fixtures or unknown --only ID');
const machine={platform:`${os.platform()} ${os.release()} (${os.arch()})`,cpu:os.cpus()[0]?.model,
  cores:os.cpus().length,memoryGB:Math.round(os.totalmem()/1024**3),runner:process.env.RUNNER_NAME||os.hostname(),node:process.version};
const settings={runs,warmup,codec:config.codec,crf:18,preset:'medium',concurrency,minSsim:config.minSsim,regressionThreshold:threshold};
const baseline=options.baseline?readJSON(path.resolve(options.baseline)):null;
const sourceSha256=fixtureSourceHash();
const browserPin=readJSON(path.join(root,'tests/browser.lock.json'));
const comparableMachine=baseline?.sourceSha256===sourceSha256 && JSON.stringify(baseline?.versions?.browser)===JSON.stringify(browserPin) && sameMachine(machine,baseline?.machine) && ['codec','crf','preset','concurrency','minSsim'].every(key=>settings[key]===baseline?.settings?.[key]);
const candidates=[options['native-bin'],process.env.MOTIONSWIFT_BIN,path.join(root,'.build/release/motionswift'),'motionswift'].filter(Boolean);
const native=candidates.find(file=>{try{return !!command(file,['--version']).trim();}catch{return false;}});
const remotion=process.execPath;
const versions={browser:readJSON(path.join(root,'tests/browser.lock.json')),remotion:readJSON(path.join(root,'tests/node_modules/remotion/package.json')).version,
  native:native?command(native,['--version']).trim():null};
const workBase=path.resolve(options['work-dir']||os.tmpdir());fs.mkdirSync(workBase,{recursive:true});
const work=fs.mkdtempSync(path.join(workBase,'motionswift-bench-'));
function git(args) { try { return command('git',args).trim(); } catch { return 'uncommitted'; } }
const results={schema:1,createdAt:new Date().toISOString(),git:{sha:git(['rev-parse','HEAD']),ref:git(['branch','--show-current'])},
  machine,settings,versions,sourceSha256,baselineCompatible:comparableMachine,fixtures:[],totals:{}};
let failed=false;
try {
  for(const fixture of fixtures) {
    if(!/^[\w/-]+$/.test(fixture.id)||fixture.id.includes('..'))throw Error('Invalid fixture ID');
    const slug=fixture.id.replaceAll('/','-');
    const range=Array.isArray(fixture.frames)?`${Math.min(...fixture.frames)}-${Math.max(...fixture.frames)}`:fixture.frames;
    if(!/^\d+-\d+$/.test(range))throw Error('Fixture needs an inclusive frame range');
    const [first,last]=range.split('-').map(Number),expectedFrames=last-first+1;
    if(expectedFrames<1)throw Error('Invalid frame range');
    const record={id:fixture.id,composition:fixture.composition,frames:range};
    results.fixtures.push(record);
    const props=path.join(work,`${slug}-props.json`);writeJSON(props,fixture.props||{});
    for(const engine of ['remotion','native']) {
      if(!engines.includes(engine) || (engine==='native'&&!native)) {record[engine]={status:'unavailable'};continue;}
      const times=[],logFile=`logs/${slug}-${engine}.log`,logPath=path.join(out,logFile);
      const video=path.join(work,`${slug}-${engine}.mp4`),report=path.join(work,`${slug}-stages.json`);
      fs.writeFileSync(logPath,'');
      try {
        for(let index=0;index<warmup+runs;index++) {
          console.log(`${fixture.id} ${engine} ${index<warmup?'warmup':`run ${index-warmup+1}/${runs}`}`);
          const args=engine==='native'?['render','--project',project,'--entry',config.entryPoint,fixture.composition,video,
            '--codec=h264',`--concurrency=${concurrency}`,`--frames=${range}`,`--props=${props}`,'--report-json',report]:
            [path.join(root,'tests/tools/render-remotion.mjs'),project,config.entryPoint,fixture.composition,video,range,props,String(concurrency)];
          const begin=process.hrtime.bigint();
          const result=spawnSync(engine==='native'?native:remotion,args,{cwd:project,encoding:'utf8',maxBuffer:128*1024*1024});
          const elapsed=Number(process.hrtime.bigint()-begin)/1e6;
          fs.appendFileSync(logPath,`\nRun ${index}: ${elapsed} ms\n${result.stdout||''}\n${result.stderr||''}`);
          if(result.error||result.status!==0)throw Error(String(result.error||`exit ${result.status}`));
          if(index>=warmup)times.push(elapsed);
        }
        const metadata=JSON.parse(command('ffprobe',['-v','error','-select_streams','v:0','-count_packets','-show_entries',
          'stream=codec_name,width,height,r_frame_rate,nb_read_packets','-of','json',video])).streams[0];
        const count=Number(metadata?.nb_read_packets);
        if(count!==expectedFrames)throw Error(`Expected ${expectedFrames} frames, got ${count}`);
        record[engine]={status:'ok',runsMs:times,medianMs:median(times),stdevMs:stdev(times),frames:count,
          fps:count/(median(times)/1000),metadata,logFile};
        if(engine==='native'&&fs.existsSync(report))record.native.stages=readJSON(report);
      } catch(error) {record[engine]={status:'failed',error:String(error),logFile};failed=true;}
    }
    if(record.native.status==='ok'&&record.remotion.status==='ok') {
      try {
        const compared=spawnSync('ffmpeg',['-hide_banner','-i',path.join(work,`${slug}-remotion.mp4`),'-i',path.join(work,`${slug}-native.mp4`),
          '-lavfi','[0:v][1:v]ssim','-f','null','-'],{encoding:'utf8',maxBuffer:16*1024*1024});
        fs.writeFileSync(path.join(out,'logs',`${slug}-parity.log`),compared.stderr||'');
        const matches=[...(compared.stderr||'').matchAll(/All:([\d.]+)/g)];
        const ssim=Number(matches.at(-1)?.[1]);
        if(compared.status!==0||!Number.isFinite(ssim))throw Error('SSIM comparison failed');
        record.ssim=ssim;
        record.parity=ssim>=config.minSsim&&parityMetadata(record.native.metadata,record.remotion.metadata)?'pass':'fail';
        record.speedup=record.remotion.medianMs/record.native.medianMs;
        if(record.parity!=='pass')failed=true;
      } catch(error) {record.parity='fail';record.parityError=String(error);failed=true;}
    }
    const previous=baseline?.fixtures?.find(item=>item.id===record.id&&item.frames===record.frames&&item.composition===record.composition);
    if(comparableMachine && previous?.native?.status==='ok' && record.native.status==='ok') {
      const deltaPct=record.native.medianMs/previous.native.medianMs-1;
      record.baseline={nativeMedianMs:previous.native.medianMs,deltaPct,regression:deltaPct>threshold};
      if(record.baseline.regression&&options['fail-on-regression'])failed=true;
    }
  }
} catch(error) {results.error=String(error);failed=true;}
finally {
  const comparable=results.fixtures.filter(item=>item.parity==='pass');
  results.totals={comparable:comparable.length,geomeanSpeedup:geometricMean(comparable.map(item=>item.speedup))};
  results.pass=!failed;
  writeJSON(path.join(out,'results.json'),results);
  const cell=record=>record.status==='ok'?`${(record.medianMs/1000).toFixed(2)} s (${record.fps.toFixed(1)} fps)`:record.status;
  const rows=results.fixtures.map(item=>`| ${item.id} | ${item.frames} | ${cell(item.remotion)} | ${cell(item.native)} | ${item.speedup?.toFixed(2)||'—'}× | ${item.ssim?.toFixed(4)||'—'} ${item.parity||''} | ${item.baseline?`${(item.baseline.deltaPct*100).toFixed(1)}%${item.baseline.regression?' 🔺':''}`:'—'} |`);
  fs.writeFileSync(path.join(out,'summary.md'),`<!-- motionswift-bench -->\n## MotionSwift benchmark: Remotion vs native\n\n`+
    `Geometric-mean speedup: **${results.totals.geomeanSpeedup?.toFixed(2)||'unavailable'}×**, across ${comparable.length} fixture(s) with output parity.\n\n`+
    `| Fixture | Frames | Remotion median | Native median | Speedup | SSIM | Native vs main |\n|---|---|---|---|---|---|---|\n${rows.join('\n')}\n\n`+
    `Machine: ${machine.cpu}; ${machine.platform}; ${machine.cores} cores; ${machine.memoryGB} GB; runner ${machine.runner}.\n\n`+
    `Runs: ${runs}, warmups: ${warmup}, concurrency: ${concurrency}. Wall time includes startup. Native: Skia CPU, PNG sequence, ffmpeg x264.\n\n`+
    `Baseline ${comparableMachine?'matches this machine and settings':'unavailable or different machine/settings; deltas omitted'}.\n\n`+
    `Versions: Remotion ${versions.remotion}; ${versions.native||'native unavailable'}.\n\n`+
    `<details><summary>Raw runs and environment</summary>\n\n\`\`\`json\n${JSON.stringify(results,null,2)}\n\`\`\`\n</details>\n\n`+
    `${results.error?`Error: ${results.error}\n\n`:''}Full logs and results.json: workflow artifact **bench-results**.\n`);
  fs.rmSync(work,{recursive:true,force:true});
}
process.exitCode=failed?1:0;

}
try { main(); } catch(error) { console.error(error); process.exitCode=2; }
