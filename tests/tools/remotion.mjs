import path from 'node:path';
import {bundle} from '@remotion/bundler';
import {selectComposition,renderStill,renderMedia} from '@remotion/renderer';
import {browserOptions} from './browser.mjs';
import {project,manifest} from './common.mjs';

export async function bundleFixtures() {
  return bundle({entryPoint:path.join(project,manifest.entryPoint),publicDir:path.join(project,'public')});
}
export async function composition(serveUrl,fixture,options={}) {
  return selectComposition({...await browserOptions(),...options,serveUrl,id:fixture.composition,inputProps:fixture.props||{}});
}
export async function still(serveUrl,fixture,frame,output,options={}) {
  return renderStill({...await browserOptions(),...options,serveUrl,composition:await composition(serveUrl,fixture,options),frame,output,
    inputProps:fixture.props||{},imageFormat:'png',logLevel:'error'});
}
export async function video(serveUrl,fixture,output,options={}) {
  const comp=await composition(serveUrl,fixture);
  const frameRange=fixture.frames ? fixture.frames.split('-').map(Number) : undefined;
  return renderMedia({...await browserOptions(),serveUrl,composition:comp,outputLocation:output,inputProps:fixture.props||{},codec:'h264',
    pixelFormat:'yuv420p',frameRange,concurrency:options.concurrency,logLevel:'error'});
}
