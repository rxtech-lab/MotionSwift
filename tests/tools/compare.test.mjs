import {test} from 'node:test';
import assert from 'node:assert/strict';
import {comparePixels} from './compare.mjs';

const image = () => ({width:100,height:10,data:Buffer.alloc(4000,255)});
test('0.3 percent boundary is inclusive and counts even one-channel changes',()=>{
  const expected=image(), actual=image();
  for(let i=0;i<3;i++)actual.data[i*4]--;
  assert.equal(comparePixels(expected,actual).pass,true);
  actual.data[12]--;
  assert.equal(comparePixels(expected,actual).pass,false);
});
test('alpha and antialias differences count',()=>{
  const expected=image(), actual=image(); actual.data[3]=254;
  assert.equal(comparePixels(expected,actual).different,1);
  assert.equal(comparePixels(expected,actual,0).pass,false);
});
test('dimensions, missing data and invalid allowances fail',()=>{
  assert.throws(()=>comparePixels(image(),{...image(),width:99}),/dimensions/);
  assert.throws(()=>comparePixels({...image(),data:Buffer.alloc(0)},image()),/buffer/);
  assert.throws(()=>comparePixels(image(),image(),NaN),/allowance/);
});
