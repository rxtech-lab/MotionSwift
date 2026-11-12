import {test} from 'node:test';
import assert from 'node:assert/strict';
import {assessFrame, validateBaseline, maxChannelDelta} from './test-film-gate.mjs';

const native = 'a'.repeat(64), reference = 'b'.repeat(64);
test('native snapshots and repeats are exact while known cross-engine differences are independent',()=>{
  const expected = {nativeRGBA:native,remotionRGBA:reference};
  assert.equal(assessFrame(expected,native,reference,native).pass,true);
  assert.equal(assessFrame(expected,'c'.repeat(64),reference,'c'.repeat(64)).pass,false);
  assert.equal(assessFrame(expected,native,'c'.repeat(64),native).pass,false);
  assert.equal(assessFrame(expected,native,reference,'c'.repeat(64)).pass,false);
});
test('Chrome rounding requires both the pixel-count and channel-delta bounds',()=>{
  const expected={nativeRGBA:native,remotionRGBA:reference};
  const check=metrics=>assessFrame(expected,native,'c'.repeat(64),native,metrics).pass;
  assert.equal(check({diffRatio:0.003,maxChannelDelta:1}),true);
  assert.equal(check({diffRatio:0.003001,maxChannelDelta:1}),false);
  assert.equal(check({diffRatio:0.000001,maxChannelDelta:2}),false);
  assert.equal(assessFrame(expected,'c'.repeat(64),reference,'c'.repeat(64),{diffRatio:0,maxChannelDelta:0}).pass,false);
  assert.equal(maxChannelDelta(Buffer.from([10,20,30,255]),Buffer.from([11,20,30,255])),1);
  assert.equal(maxChannelDelta(Buffer.from([10,20,30,255]),Buffer.from([12,20,30,255])),2);
  assert.throws(()=>maxChannelDelta(Buffer.from([1]),Buffer.from([1,2])));
});
test('changed provenance, unsafe source paths, and duplicate/missing samples fail before rendering',()=>{
  const pins = {remotionVersion:'1',platform:'darwin',arch:'arm64',browser:{version:'2'},chromiumOptions:{gl:'swangle'}};
  const baseline = {schema:1,backend:'cpu',...pins,composition:{durationInFrames:30},files:[{name:'index.ts',sha256:native}],
    frames:[{frame:0,nativeRGBA:native,remotionRGBA:reference}]};
  validateBaseline(baseline,pins);
  assert.throws(()=>validateBaseline(baseline,{...pins,remotionVersion:'3'}));
  assert.throws(()=>validateBaseline(baseline,{...pins,browser:{version:'3'}}));
  assert.throws(()=>validateBaseline(baseline,{...pins,chromiumOptions:{gl:'angle'}}));
  assert.throws(()=>validateBaseline({...baseline,files:[{name:'../index.ts',sha256:native}]},pins));
  assert.throws(()=>validateBaseline({...baseline,frames:[]},pins));
  assert.throws(()=>validateBaseline({...baseline,frames:[...baseline.frames,...baseline.frames]},pins));
  assert.throws(()=>validateBaseline({...baseline,frames:[{...baseline.frames[0],remotionWebP:'invalid'}]},pins));
  for (const nativeRGBA of [[], [native,native], ['not-a-hash']]) {
    assert.throws(()=>validateBaseline({...baseline,frames:[{...baseline.frames[0],nativeRGBA}]},pins));
  }
});
