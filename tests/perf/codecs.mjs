// Reproducible codec matrix. Each cell includes startup, availability probe, rendering,
// encoding and publish. RSS includes FFmpeg/compiler descendants, sampled every 100ms.
import {measureProcess} from './memory.mjs';
import {spawnSync} from 'node:child_process';
import {mkdtempSync,readFileSync,writeFileSync,mkdirSync,rmSync,existsSync} from 'node:fs';
import {tmpdir,cpus,platform,arch} from 'node:os';
import {join,resolve} from 'node:path';
const root=resolve(import.meta.dirname,'../..');
const output=resolve(process.env.CODEC_REPORT_DIR||join(root,'tests/reports/codecs'));
const bin=process.env.MOTIONSWIFT_BIN||join(root,'.build/release/motionswift');
const budgetsPath=join(root,'tests/perf/codec-budgets.json');
const measureOnly=process.argv.includes('--measure-only');
const budgets=measureOnly?null:JSON.parse(readFileSync(budgetsPath,'utf8'));
const work=mkdtempSync(join(tmpdir(),'motionswift-codecs-'));
mkdirSync(output,{recursive:true});
const matrix=[['h264','software','cpu'],['hevc','software','cpu'],['prores','software','cpu'],['prores4444','software','cpu'],
  ['h264','videotoolbox','gpu'],['hevc','videotoolbox','gpu'],['h264','videotoolbox-shared','gpu'],['hevc','videotoolbox-shared','gpu']];
const generated=join(root,'tests/perf/long.js');
const generatedExisted=existsSync(generated);
if(budgets&&budgets.machine.cpu!==cpus()[0].model)throw Error('Codec budgets require '+budgets.machine.cpu+'; use --measure-only to establish budgets for this host');
const results=[];
let failed=false;
try {
  for(const frames of [30,300])for(const [codec,encoder,backend] of matrix) {
    const id=`${codec}/${encoder}/${frames}`;
    const file=join(work,`video.${codec.startsWith('prores')?'mov':'mp4'}`);
    const report=join(work,'stages.json');
    const args=['render','--project',join(root,'tests'),'--entry','perf/long.tsx','Layers',file,
      `--codec=${codec}`,`--encoder=${encoder}`,`--backend=${backend}`,'--scale=4','--concurrency=8',`--frames=0-${frames-1}`,'--report-json',report];
    const runs=[];
    for(let run=0;run<4;run++) {
      const begin=performance.now();
      const result=await measureProcess(bin,args,{cwd:root});
      const ms=performance.now()-begin;
      writeFileSync(join(output,`${id.replaceAll('/','-')}-${run}.log`),result.stdout+result.stderr);
      if(result.status!==0)throw Error(`${id} failed: ${result.stderr}`);
      if(run)runs.push({ms,memory:result.memory});
    }
    const probe=spawnSync('ffprobe',['-v','error','-count_frames','-show_entries','stream=codec_name,width,height,nb_read_frames','-of','json',file],{encoding:'utf8'});
    if(probe.status!==0)throw Error(probe.stderr);
    const metadata=JSON.parse(probe.stdout).streams[0];
    if(+metadata.nb_read_frames!==frames||metadata.width!==1280||metadata.height!==720||metadata.codec_name!==(codec.startsWith('prores')?'prores':codec))throw Error(`Invalid metadata: ${id}`);
    const decode=spawnSync('ffmpeg',['-v','error','-i',file,'-f','null','-'],{encoding:'utf8'});
    if(decode.status!==0)throw Error(decode.stderr);
    const medianMs=runs.map(x=>x.ms).sort((a,b)=>a-b)[1];
    const peakRssBytes=runs.every(x=>x.memory.status==='ok')?Math.max(...runs.map(x=>x.memory.peakRssBytes)):null;
    const budget=budgets?.cells[id];
    const regression=!!budgets&&(!budget||medianMs>budget.maxMs||peakRssBytes===null||peakRssBytes>budget.maxRssBytes);
    failed ||= regression;
    results.push({id,frames,codec,encoder,backend,runs,medianMs,fps:frames/(medianMs/1000),peakRssBytes,metadata,
      stages:JSON.parse(readFileSync(report,'utf8')).stages,regression});
    console.log(`${id}: ${medianMs.toFixed(1)} ms, ${(peakRssBytes/1048576).toFixed(1)} MiB${regression?' REGRESSION':''}`);
  }
} finally {
  writeFileSync(join(output,'results.json'),JSON.stringify({machine:{cpu:cpus()[0].model,platform:platform(),arch:arch()},measureOnly,results},null,2));
  rmSync(work,{recursive:true,force:true});
  if(!generatedExisted)rmSync(generated,{force:true});
}
if(failed)process.exitCode=1;
