// One Remotion renderMedia() run of a 3D fixture (fresh process per measurement, like the main benchmark).
import {selectComposition, renderMedia} from '@remotion/renderer';
import {threeBrowser, bundleThree} from './three-common.mjs';

const [id, output, concurrency, scale] = process.argv.slice(2);
const browser = await threeBrowser();
const serveUrl = await bundleThree();
const composition = await selectComposition({...browser, serveUrl, id});
await renderMedia({...browser, serveUrl, composition, outputLocation: output, codec: 'h264', crf: 18, x264Preset: 'medium',
  pixelFormat: 'yuv420p', disableSharedMemoryCapture: true, concurrency: Number(concurrency), scale: Number(scale), logLevel: 'error'});
