import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import {testRoot,project} from './common.mjs';

export const sha256 = data=>crypto.createHash('sha256').update(data).digest('hex');
export function fixtureSourceHash() {
  const hash=crypto.createHash('sha256');
  const walk=directory=>fs.readdirSync(directory,{withFileTypes:true}).sort((a,b)=>a.name.localeCompare(b.name,'en')).forEach(entry=>{
    if(entry.name==='node_modules'||entry.name.startsWith('.'))return;
    const file=path.join(directory,entry.name);
    if(entry.isDirectory())walk(file);
    else if(entry.isFile()){hash.update(path.relative(project,file));hash.update(fs.readFileSync(file));}
  });
  walk(project);
  return hash.digest('hex');
}
export function assertProvenance(metadata) {
  const lock=JSON.parse(fs.readFileSync(path.join(testRoot,'package-lock.json')));
  const browser=JSON.parse(fs.readFileSync(path.join(testRoot,'browser.lock.json')));
  if(metadata.engine!=='Remotion'||metadata.version!==lock.packages['node_modules/remotion'].version)throw Error('Golden Remotion version changed; regenerate references explicitly');
  if(JSON.stringify(metadata.browser)!==JSON.stringify(browser))throw Error('Golden browser pin changed; regenerate references explicitly');
  if(metadata.platform!==process.platform||metadata.arch!==process.arch)throw Error('Golden platform does not match this runner');
  if(metadata.fixtureManifestSha256!==sha256(fs.readFileSync(path.join(testRoot,'fixtures.json'))))throw Error('Golden manifest changed; regenerate references explicitly');
  if(metadata.sourceSha256!==fixtureSourceHash())throw Error('Golden source changed; regenerate references explicitly');
}
