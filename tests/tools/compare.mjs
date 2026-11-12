import fs from 'node:fs';
import path from 'node:path';
import {PNG} from 'pngjs';

export const maxDiffRatio=0.003;
// Count every pixel with any different RGBA channel. No fuzzy color tolerance or AA exclusions.
export function comparePixels(expected,actual,allowance=maxDiffRatio) {
  if(!Number.isFinite(allowance) || allowance<0 || allowance>1)throw Error('Invalid allowance');
  if(expected.width!==actual.width || expected.height!==actual.height)throw Error('Image dimensions differ');
  const pixels=expected.width*expected.height;
  if(pixels===0 || expected.data.length!==pixels*4 || actual.data.length!==pixels*4)throw Error('Invalid pixel buffer');
  const diff=new PNG({width:expected.width,height:expected.height});
  let different=0;
  for(let pixel=0;pixel<pixels;pixel++) {
    const offset=pixel*4;
    const changed=[0,1,2,3].some(channel=>expected.data[offset+channel]!==actual.data[offset+channel]);
    if(changed)different++;
    diff.data.set(changed?[255,0,128,255]:[actual.data[offset],actual.data[offset+1],actual.data[offset+2],80],offset);
  }
  return {different,pixels,diffRatio:different/pixels,pass:different<=pixels*allowance,diff};
}
export function compareFiles(expected,actual,reportDir,allowance=maxDiffRatio) {
  const result=comparePixels(PNG.sync.read(fs.readFileSync(expected)),PNG.sync.read(fs.readFileSync(actual)),allowance);
  if(reportDir) {
    fs.mkdirSync(reportDir,{recursive:true});
    fs.copyFileSync(expected,path.join(reportDir,'expected.png'));
    fs.copyFileSync(actual,path.join(reportDir,'actual.png'));
    fs.writeFileSync(path.join(reportDir,'diff.png'),PNG.sync.write(result.diff));
  }
  const {diff,...metrics}=result;
  return metrics;
}
