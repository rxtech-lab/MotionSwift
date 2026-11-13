import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
import path from 'node:path';
import test from 'node:test';
import {createRequire} from 'node:module';
import {root} from './common.mjs';
const require=createRequire(import.meta.url);
const svg=require('../../js/remotion-shim/svg-host.js');
const node=(type,props={},children=[])=>({type,props,children});

test('SVG host serializes a vector island and rejects unsupported elements/props',()=>{
  assert.match(svg.host(node('svg',{width:100,height:50},[node('path',{d:'M0 0L10 10',stroke:'#fff'})])).src,/stroke="#fff"/);
  for(const child of [node('foreignObject'),node('text'),node('rect',{onClick:()=>{}}),node('path',{fill:'url(https://example.com/a.svg)'}),node('path',{d:'M 0 0 L 1'}),node('g',{transform:'perspective(20)'}),node('rect',{fill:'nonsense'})])
    assert.throws(()=>svg.host(node('svg',{},[child])),/ms\/unsupported/);
  assert.throws(()=>svg.host(node('svg',{},[node('path',{opacity:NaN})])),/unsupported-svg-value/);
  for(const props of [{width:'1e999'},{r:-1},{strokeDasharray:'2 -1'},{transform:'translate(1e999)'}])
    assert.throws(()=>svg.host(node('svg',{},[node('circle',props)])),/unsupported-svg-value/);
});

test('pinned DOM-free packages expose only documented exports and preserve upstream math',()=>{
  const context=vm.createContext({console});
  vm.runInContext(fs.readFileSync(path.join(root,'Sources/MotionPortable/JavaScript/vendor.js'),'utf8'),context);
  const paths=context.__ms_vendor['@remotion/paths'], shapes=context.__ms_vendor['@remotion/shapes'];
  assert.deepEqual(Object.keys(paths).sort(),['evolvePath','getLength','scalePath','translatePath']);
  assert.deepEqual(Object.keys(shapes).sort(),['makeCircle','makeEllipse','makeRect']);
  const upstreamPaths=require('@remotion/paths'),upstreamShapes=require('@remotion/shapes');
  for(const [name,args] of [['makeCircle',{radius:30}],['makeEllipse',{rx:25,ry:15}],['makeRect',{width:60,height:40,cornerRadius:4}]]) {
    assert.equal(JSON.stringify(shapes[name](args)),JSON.stringify(upstreamShapes[name](args)));
    const d=shapes[name](args).path;
    assert.equal(paths.getLength(d),upstreamPaths.getLength(d));
    assert.equal(paths.translatePath(d,10,20),upstreamPaths.translatePath(d,10,20));
    assert.equal(paths.scalePath(d,2,0.5),upstreamPaths.scalePath(d,2,0.5));
    assert.equal(JSON.stringify(paths.evolvePath(0.4,d)),JSON.stringify(upstreamPaths.evolvePath(0.4,d)));
  }
});
