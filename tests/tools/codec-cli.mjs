// Run after swift build: real CLI frame sampling, segment order, alpha and cancellation.
import assert from 'node:assert/strict';
import {spawnSync,spawn} from 'node:child_process';
import {mkdtempSync,readFileSync,writeFileSync,readdirSync,rmSync,mkdirSync,chmodSync,existsSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {resolve,join} from 'node:path';
const root=resolve(import.meta.dirname,'../..');
const bin=process.env.MOTIONSWIFT_BIN||join(root,'.build/release/motionswift');
const generated=['codec-fixture.js','long.js'].map(x=>join(root,'tests/perf',x));
const existing=generated.map(existsSync);
const dir=mkdtempSync(join(tmpdir(),'codec-cli-'));
function command(bin,args) {
 const p=spawnSync(bin,args,{maxBuffer:32*1024*1024});
 assert.equal(p.status,0,p.stderr?.toString());return p.stdout;
}
const base=['render','--project',join(root,'tests'),'--entry','perf/codec-fixture.tsx','CodecFixture'];
try {
 const file=join(dir,'alpha.mov'),report=join(dir,'stages.json');
 command(bin,[...base,file,'--codec=prores4444','--segments=4-5,0-3','--frame-step=2','--report-json',report]);
 const data=command('ffmpeg',['-v','error','-i',file,'-f','rawvideo','-pix_fmt','rgba','pipe:1']);
 assert.equal(data.length,64*64*4*3);
 // Source order 4,0,2 => black, red, blue; segment starts rebase to a continuous timeline.
 for(const [frame,rgb] of [[0,[0,0,0]],[1,[255,0,0]],[2,[0,0,255]]])for(let c=0;c<3;c++)assert.ok(Math.abs(data[frame*64*64*4+c]-rgb[c])<15);
 const metadata=JSON.parse(command('ffprobe',['-v','error','-show_entries','stream=r_frame_rate','-of','json',file]));
 assert.equal(metadata.streams[0].r_frame_rate,'12/1');
 const timestamps=JSON.parse(command('ffprobe',['-v','error','-show_frames','-show_entries','frame=best_effort_timestamp_time','-of','json',file])).frames;
 timestamps.forEach((frame,i)=>assert.ok(Math.abs(+frame.best_effort_timestamp_time-i/12)<0.00001));
 for(const codec of ['h264','hevc','prores']) {
   const target=join(dir,codec+(codec==='prores'?'.mov':'.mp4'));
   command(bin,[...base,target,`--codec=${codec}`,'--segments=4-5,0-3','--frame-step=2']);
   const frames=JSON.parse(command('ffprobe',['-v','error','-show_frames','-show_entries','frame=best_effort_timestamp_time','-of','json',target])).frames;
   assert.equal(frames.length,3);
   frames.forEach((frame,i)=>assert.ok(Math.abs(+frame.best_effort_timestamp_time-i/12)<0.00001));
   const pixels=command('ffmpeg',['-v','error','-i',target,'-f','rawvideo','-pix_fmt','rgb24','pipe:1']);
   assert.equal(pixels.length,64*64*3*3);
   assert.ok(pixels[64*64*3]>240 && pixels[2*64*64*3+2]>240);
 }

 const stages=JSON.parse(readFileSync(report)).stages;
 assert.equal(stages.segments,2);assert.equal(stages.codec,'prores4444');
 assert.equal(stages.pixelFormat,'yuva444p10le');assert.equal(stages.quality,9);assert.equal(stages.frameStep,2);
 command(bin,[...base,file,'--codec=prores4444','--frames=5-5']);
 const alpha=command('ffmpeg',['-v','error','-i',file,'-f','rawvideo','-pix_fmt','rgba','pipe:1']);
 assert.ok(Math.abs(alpha[3]-128)<=2);
 const original=readFileSync(file);
 const invalid=spawnSync(bin,[...base,file,'--codec=h264','--pixel-format=yuva444p10le']);
 assert.notEqual(invalid.status,0);assert.deepEqual(readFileSync(file),original);
 // Simulate an installed FFmpeg whose requested hardware encoder cannot start.
 const fake=join(dir,'bin');mkdirSync(fake);
 writeFileSync(join(fake,'ffmpeg'),'#!/bin/sh\nexit 73\n');chmodSync(join(fake,'ffmpeg'),0o755);
 const unavailable=spawnSync(bin,[...base,join(dir,'unavailable.mp4'),'--encoder=videotoolbox'],
   {env:{...process.env,PATH:fake+':'+process.env.PATH}});
 assert.notEqual(unavailable.status,0);
 assert.match(unavailable.stderr.toString(),/unavailable.*No software fallback/s);
 assert.ok(!readdirSync(dir).some(x=>x.startsWith('.motionswift-')));
 // A sustained export gives SIGTERM a real rendering pipeline to cancel.
 const cancelled=join(dir,'cancelled.mp4');writeFileSync(cancelled,'existing-output');
 const child=spawn(bin,['render','--project',join(root,'tests'),'--entry','perf/long.tsx','Layers',cancelled,'--frames=0-299','--scale=12','--concurrency=1'],{stdio:'ignore'});
 setTimeout(()=>child.kill('SIGTERM'),1000);
 const code=await new Promise(resolve=>child.on('close',resolve));
 assert.notEqual(code,0);assert.equal(readFileSync(cancelled,'utf8'),'existing-output');
 assert.ok(!readdirSync(dir).some(x=>x.startsWith('.motionswift-')));
 console.log('CLI frame-step, ordered concat, alpha, validation and SIGTERM cleanup passed');
} finally {rmSync(dir,{recursive:true,force:true});generated.forEach((file,i)=>{if(!existing[i])rmSync(file,{force:true});});}
