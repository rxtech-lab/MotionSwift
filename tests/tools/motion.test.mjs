import {test} from 'node:test';
import assert from 'node:assert/strict';
import {createRequire} from 'node:module';
import fs from 'node:fs';
import vm from 'node:vm';
const require=createRequire(import.meta.url);
const upstream=require('remotion');
// This tests the shipped shim without modifying host module resolution.
const shimRequire=createRequire(new URL('../../js/remotion-shim/index.js',import.meta.url));
const context=vm.createContext({module:{exports:{}},require:specifier=>specifier.startsWith('.') ? shimRequire(specifier) : require(specifier)});
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
test('spring duration, reverse, delay and measurement match upstream boundaries',()=>{
  for(const fps of [10,30,60])for(const damping of [5,10,20,35])for(const threshold of [0.005,0.01,0.001]) {
    const config={damping};
    assert.equal(shim.measureSpring({fps,config,threshold}),upstream.measureSpring({fps,config,threshold}),JSON.stringify({fps,damping,threshold}));
    for(const reverse of [false,true])for(const durationInFrames of [undefined,20])for(const frame of [-1,0,3,4,4.5,19,20,23,24,25,60]) {
      const options={fps,config,frame,reverse,durationInFrames,delay:4,durationRestThreshold:threshold,from:3,to:-2};
      assert(Math.abs(shim.spring(options)-upstream.spring(options))<1e-9,JSON.stringify(options));
    }
  }
});
test('Easing helpers and deterministic random match Remotion',()=>{
  for(const name of ['ease','step0','step1','bounce'])for(const x of [0,0.01,0.25,0.5,0.75,1])assert(Math.abs(shim.Easing[name](x)-upstream.Easing[name](x))<1e-7,`${name} ${x}`);
  for(const name of ['poly','back','elastic'])for(const parameter of (name === 'poly' ? [1,2,3] : [undefined,1,2,3]))for(const x of [0,0.2,0.5,0.8,1])assert(Math.abs(shim.Easing[name](parameter)(x)-upstream.Easing[name](parameter)(x))<1e-9,`${name} ${parameter} ${x}`);
  for(const seed of [0,1,42,-1,0.5,'','a','hello','中文','🌊'])assert.equal(shim.random(seed),upstream.random(seed));
  assert.throws(()=>shim.random(null));
});
test('color interpolation matches the upstream serialized channels',()=>{
  assert.throws(()=>shim.interpolateColors(0.5,[0,1],['hsl(120 50 50)','red']));
  for(const colors of [['red','blue'],['#1234','#aabbccdd'],['rgba(12, 44, 120, 0.3)','rgb(200, 60, 50)'],['hsl(210, 50%, 40%)','rebeccapurple']])for(const value of [-1,0,0.25,0.5,1,2])assert.equal(shim.interpolateColors(value,[0,1],colors),upstream.interpolateColors(value,[0,1],colors));
});
test('Series offsets, nested frames and video durations have exact boundary behavior',()=>{
  const React=require('react');
  const {renderToStaticMarkup}=require('react-dom/server');
  const local=()=>React.createElement('span',null,`${shim.useCurrentFrame()}:${shim.useVideoConfig().durationInFrames}`);
  const render=(frame,content)=>renderToStaticMarkup(React.createElement(shim.__Config.Provider,{value:{fps:30,durationInFrames:30}},React.createElement(shim.__Frame.Provider,{value:frame},content)));
  const nested=React.createElement(shim.Sequence,{from:3,durationInFrames:12,layout:'none'},React.createElement(shim.Sequence,{from:2,durationInFrames:4,layout:'none'},React.createElement(local)));
  for(const [frame,expected] of [[4,''],[5,'<span>0:4</span>'],[8,'<span>3:4</span>'],[9,'']])assert.equal(render(frame,nested),expected);
  const series=React.createElement(shim.Series,null,
    React.createElement(shim.Series.Sequence,{durationInFrames:4,offset:-2,layout:'none'},React.createElement(local)),
    React.createElement(shim.Series.Sequence,{durationInFrames:3,offset:-1,layout:'none'},React.createElement(local)));
  for(const [frame,expected] of [[0,'<span>2:4</span>'],[1,'<span>3:4</span><span>0:3</span>'],[2,'<span>1:3</span>'],[3,'<span>2:3</span>'],[4,'']])assert.equal(render(frame,series),expected);
  assert.throws(()=>render(0,React.createElement(shim.Series,null,React.createElement('div'))),/Series only accepts/);
  assert.throws(()=>render(0,React.createElement(shim.Series,null,React.createElement(shim.Series.Sequence,{durationInFrames:0}))),/duration/);
});
