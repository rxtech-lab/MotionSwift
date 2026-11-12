import fs from 'node:fs';
import {spawnSync} from 'node:child_process';
import {pathToFileURL} from 'node:url';

// Exercise an actual session: listing an encoder or finding a Metal device does not
// establish media-engine access (notably on virtualized macOS runners).
export function probeHardwareEncoding(run=spawnSync) {
  const result=run('ffmpeg',[
    '-hide_banner','-loglevel','error','-f','lavfi','-i','color=c=red:s=320x180:r=24',
    '-frames:v','3','-c:v','h264_videotoolbox','-allow_sw','0','-q:v','65','-f','null','-',
  ],{encoding:'utf8',timeout:30000,maxBuffer:1024*1024});
  if(result.error||result.signal)throw Error(`Hardware probe failed: ${result.error||result.signal}`);
  if(result.status===0)return {available:true,reason:'Hardware-only H.264 session encoded three frames'};
  const stderr=result.stderr||'';
  // These session/encoder availability errors are distinct from invalid flags,
  // missing ffmpeg, conversion errors, or failures in MotionSwift itself.
  if(/Cannot create compression session:\s*-(12903|12907|12908|12915)\b/i.test(stderr)) {
    return {available:false,reason:stderr.trim().slice(0,2000)};
  }
  throw Error(`Hardware probe configuration or encode failure (exit ${result.status}): ${stderr}`);
}

if(process.argv[1]&&import.meta.url===pathToFileURL(process.argv[1]).href) {
  const result=probeHardwareEncoding();
  console.log(JSON.stringify(result,null,2));
  if(process.env.GITHUB_ENV)fs.appendFileSync(process.env.GITHUB_ENV,
    `MOTIONSWIFT_TEST_HARDWARE=${result.available?'1':'0'}\n`);
  if(process.env.GITHUB_STEP_SUMMARY)fs.appendFileSync(process.env.GITHUB_STEP_SUMMARY,
    `\n### Hardware encoder preflight\n\n${result.available?'Available: hardware tests enabled.':'Unavailable: hardware encoder tests will be skipped; this runner does not validate hardware encoding.'}\n\n\`\`\`text\n${result.reason}\n\`\`\`\n`);
  if(!result.available)console.log('::warning::Hardware H.264 session unavailable; hardware tests are skipped, not passed.');
}
