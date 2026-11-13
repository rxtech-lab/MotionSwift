import {test} from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {fixtureSourceHash} from './provenance.mjs';
import {testRoot} from './common.mjs';
import {threePins} from './three-common.mjs';

test('real-content census and private staging do not invalidate visual references',t=>{
  const project=fs.mkdtempSync(path.join(os.tmpdir(),'motionswift-provenance-'));
  t.after(()=>fs.rmSync(project,{recursive:true,force:true}));
  fs.mkdirSync(path.join(project,'src'));
  fs.writeFileSync(path.join(project,'src/index.ts'),'visual source');
  const original=fixtureSourceHash(project);
  fs.mkdirSync(path.join(project,'real/local'),{recursive:true});
  fs.writeFileSync(path.join(project,'real/manifest.json'),'census');
  fs.writeFileSync(path.join(project,'real/local/scene.tsx'),'private scene');
  assert.equal(fixtureSourceHash(project),original);
  fs.writeFileSync(path.join(project,'real/manifest.json'),'updated census');
  assert.equal(fixtureSourceHash(project),original);
  fs.writeFileSync(path.join(project,'src/index.ts'),'changed visual source');
  assert.notEqual(fixtureSourceHash(project),original);
});

test('checked-in visual sources retain their reviewed golden provenance',()=>{
  const metadata=JSON.parse(fs.readFileSync(path.join(testRoot,'golden/metadata.json')));
  assert.equal(fixtureSourceHash(),metadata.sourceSha256);
});

test('checked-in 3D references retain every pinned dependency and source hash',()=>{
  const metadata=JSON.parse(fs.readFileSync(path.join(testRoot,'golden/three/metadata.json')));
  for(const [key,value] of Object.entries(threePins())) {
    assert.deepEqual(metadata[key],value,`3D golden ${key} changed; run make three-goldens and review`);
  }
});
