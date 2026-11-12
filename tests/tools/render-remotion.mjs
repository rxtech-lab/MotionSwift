import {browserOptions} from './browser.mjs';
import path from 'node:path';
import {bundle} from '@remotion/bundler';
import {selectComposition,renderMedia} from '@remotion/renderer';
import fs from 'node:fs';
const [project,entry,id,output,range,propsFile,concurrency] = process.argv.slice(2);
const browser = await browserOptions();
const serveUrl=await bundle({entryPoint:path.join(project,entry)});
const inputProps=JSON.parse(fs.readFileSync(propsFile,'utf8'));
const composition=await selectComposition({serveUrl,id,inputProps,...browser});
await renderMedia({...browser,serveUrl,composition,outputLocation:output,codec:'h264',crf:18,x264Preset:'medium',pixelFormat:'yuv420p',inputProps,
  disableSharedMemoryCapture:true,frameRange:range.split('-').map(Number),concurrency:Number(concurrency),logLevel:'verbose'});
