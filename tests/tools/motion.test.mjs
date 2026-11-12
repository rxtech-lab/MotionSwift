import {test} from 'node:test';
import assert from 'node:assert/strict';
import {createRequire} from 'node:module';
import fs from 'node:fs';
import vm from 'node:vm';
const require=createRequire(import.meta.url);
const upstream=require('remotion');
// This tests the shipped shim without modifying host module resolution.
const context=vm.createContext({module:{exports:{}},require:specifier=>require(specifier)});
vm.runInContext(fs.readFileSync(new URL('../../js/remotion-shim/index.js',import.meta.url),'utf8'),context);
const shim=context.module.exports;
test('spring parity including fractional, low-fps and overdamped samples',()=>{
  for(const fps of [10,24,30,60])for(const damping of [5,10,20,35])for(const frame of [0,0.25,1,4,9.75,15,29,60]) {
    const options={frame,fps,config:{damping}};
    assert(Math.abs(shim.spring(options)-upstream.spring(options))<=1e-9,JSON.stringify(options));
  }
});
test('interpolation parity across segments and extrapolation modes',()=>{
  for(const mode of ['extend','clamp','identity','wrap'])for(const value of [-25,-2,0,5,10,15,20,25,40]) {
    const options={extrapolateLeft:mode,extrapolateRight:mode};
    assert(Math.abs(shim.interpolate(value,[0,10,20],[0,1,4],options)-upstream.interpolate(value,[0,10,20],[0,1,4],options))<1e-9,`${mode} ${value}`);
  }
});
