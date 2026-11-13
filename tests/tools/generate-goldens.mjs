import {fixtureSourceHash} from './provenance.mjs';
import {browserLock,browserOptions} from './browser.mjs';
import {openBrowser} from '@remotion/renderer';
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import {createRequire} from 'node:module';
import {bundleFixtures,still} from './remotion.mjs';
import {manifest,testRoot,outputPath,writeJSON,run,root} from './common.mjs';

const require=createRequire(import.meta.url);
const version=require('remotion/package.json').version;
const serveUrl=await bundleFixtures();
const frames=[];
const browser=await openBrowser('chrome',await browserOptions());
try {
for(const fixture of manifest.fixtures) for(const frame of fixture.frames) {
  const output=outputPath(path.join(testRoot,'golden/stills'),fixture,frame);
  fs.mkdirSync(path.dirname(output),{recursive:true});
  await still(serveUrl,fixture,frame,output,{puppeteerInstance:browser});
  frames.push({id:fixture.id,frame,sha256:crypto.createHash('sha256').update(fs.readFileSync(output)).digest('hex')});
  console.log(`${fixture.id} frame ${frame}`);
}
} finally { await browser.close({silent:true}); }
writeJSON(path.join(testRoot,'golden/metadata.json'),{schema:1,engine:'Remotion',version,browser:browserLock,platform:process.platform,arch:process.arch,
  fixtureManifestSha256:crypto.createHash('sha256').update(fs.readFileSync(path.join(testRoot,'fixtures.json'))).digest('hex'),
  sourceSha256:fixtureSourceHash(),frames});
