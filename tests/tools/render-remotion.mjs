import {browserOptions} from './browser.mjs';
import path from 'node:path';
import {bundle} from '@remotion/bundler';
import {selectComposition,renderMedia} from '@remotion/renderer';
import fs from 'node:fs';
const [project,entry,id,output,range,propsFile,concurrency,scale='1'] = process.argv.slice(2);
const browser = await browserOptions();
// Chrome's OpenGL backend. Unset keeps Remotion's default (no --use-gl flag, Chrome decides).
if(process.env.REMOTION_GL)browser.chromiumOptions={gl:process.env.REMOTION_GL};
const serveUrl=await bundle({entryPoint:path.join(project,entry)});
const inputProps=JSON.parse(fs.readFileSync(propsFile,'utf8'));
const composition=await selectComposition({serveUrl,id,inputProps,...browser});
await renderMedia({...browser,serveUrl,composition,outputLocation:output,codec:'h264',crf:18,x264Preset:'medium',pixelFormat:'yuv420p',inputProps,
  disableSharedMemoryCapture:true,frameRange:range.split('-').map(Number),concurrency:Number(concurrency),scale:Number(scale),logLevel:'verbose'});
