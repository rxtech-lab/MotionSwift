// Benchmark the checked-in real project with the same engine/timing/parity harness
// as the synthetic suite. Source and videos stay outside uploaded reports.
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import {fileURLToPath} from 'node:url';
import {spawnSync} from 'node:child_process';
import {sha256,testFilmChromiumOptions} from '../tools/test-film-gate.mjs';

const root=fileURLToPath(new URL('../..',import.meta.url));
const fixture=path.join(root,'tests/fixtures/test-film');
const out=path.join(root,'tests/reports/bench/test-film');
const baseline=JSON.parse(fs.readFileSync(path.join(fixture,'baseline.json')));
const options={};
for(let i=2;i<process.argv.length;i++) {
  const [key,inline]=process.argv[i].split('=',2);
  if(!['--work-dir','--frames','--engines','--allow-unavailable-hardware'].includes(key) || options[key]!==undefined)
    throw Error('Unknown/repeated Test Film benchmark option');
  options[key]=key==='--allow-unavailable-hardware'?true:(inline??process.argv[++i]);
  if(options[key]===undefined)throw Error(`Missing ${key} value`);
}
fs.rmSync(out,{recursive:true,force:true});
fs.mkdirSync(out,{recursive:true});
const parent=path.resolve(options['--work-dir']||os.tmpdir());
fs.mkdirSync(parent,{recursive:true});
const temporary=fs.mkdtempSync(path.join(parent,'motionswift-test-film-perf-'));
try {
  const archive=path.join(fixture,'project.zip');
  const archiveHash=sha256(fs.readFileSync(archive));
  const pinned=fs.readFileSync(archive+'.sha256','utf8').trim().split(/\s+/)[0];
  if(archiveHash!==pinned)throw Error('Test Film archive checksum mismatch');
  const project=path.join(temporary,'project');
  const extracted=spawnSync('unzip',['-q',archive,'-d',project],{encoding:'utf8'});
  if(extracted.error || extracted.status!==0)throw Error('Cannot extract Test Film project');
  for(const file of baseline.files) {
    if(sha256(fs.readFileSync(path.join(project,'src',file.name)))!==file.sha256)
      throw Error(`Test Film source hash mismatch: ${file.name}`);
  }
  fs.symlinkSync(path.join(root,'tests/node_modules'),path.join(project,'node_modules'),'dir');
  const {width,height,fps,durationInFrames,id}=baseline.composition;
  const frames=options['--frames']||`0-${durationInFrames-1}`;
  const match=frames.match(/^(\d+)-(\d+)$/);
  if(!match || Number(match[1])>Number(match[2]) || Number(match[2])>=durationInFrames)
    throw Error('Invalid Test Film frame range');
  const count=Number(match[2])-Number(match[1])+1;
  const config={project,entryPoint:'src/index.ts',codec:'h264',runs:1,warmup:0,minSsim:0.98,
    concurrency:8,sourceSha256:archiveHash,remotionGl:testFilmChromiumOptions.gl,
    tiers:[{id:'1080p',scale:1}],fixtures:[{id:'test-film/Main',composition:id,frames}],
    notes:`Actual bundled Remotion project: ${count.toLocaleString('en-US')} measured frames (${frames}), ${width}×${height}, ${fps} fps. Full composition: ${durationInFrames.toLocaleString('en-US')} frames / ${(durationInFrames/fps).toFixed(2)} seconds. One measured run per engine, no warmup. Each wall-clock time includes CLI startup, compilation/bundling, rendering, and H.264 encoding; archive extraction and SSIM analysis are excluded. Chrome uses pinned ${testFilmChromiumOptions.gl}. Frame count/dimensions/fps and SSIM >= 0.98 gate speedups; exact cross-engine pixel parity is not claimed.`};
  const configFile=path.join(temporary,'config.json');
  fs.writeFileSync(configFile,JSON.stringify(config,null,2));
  const args=[path.join(root,'tests/perf/bench.mjs'),'--config',configFile,'--out',out,'--work-dir',temporary];
  if(options['--engines'])args.push('--engines',options['--engines']);
  if(options['--allow-unavailable-hardware'])args.push('--allow-unavailable-hardware');
  const result=spawnSync(process.execPath,args,{cwd:root,stdio:'inherit',env:{...process.env,MOTIONSWIFT_HOME:root}});
  if(result.error)throw result.error;
  if(!fs.existsSync(path.join(out,'results.json')) || !fs.existsSync(path.join(out,'summary.md')))
    throw Error(`Test Film benchmark failed before reporting (exit ${result.status})`);
  process.exitCode=result.status??1;
} catch(error) {
  fs.writeFileSync(path.join(out,'results.json'),JSON.stringify({pass:false,error:String(error)},null,2)+'\n');
  fs.writeFileSync(path.join(out,'summary.md'),`<!-- motionswift-bench -->\n## Actual Test Film project\n\n❌ Benchmark setup failed: ${String(error)}\n`);
  console.error(error);
  process.exitCode=1;
} finally {
  fs.rmSync(temporary,{recursive:true,force:true});
}
