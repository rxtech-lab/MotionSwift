import fs from 'node:fs';
import path from 'node:path';
import {test} from 'node:test';
import assert from 'node:assert/strict';
import ts from 'typescript';
import {root,testRoot} from './common.mjs';

function check(file) {
  const options={target:ts.ScriptTarget.ES2022,module:ts.ModuleKind.ESNext,moduleResolution:ts.ModuleResolutionKind.Bundler,
    jsx:ts.JsxEmit.ReactJSX,jsxImportSource:'@motionswift/remotion',strict:true,noEmit:true,isolatedModules:true,types:['react'],typeRoots:[path.join(testRoot,'node_modules/@types')],
    esModuleInterop:true,baseUrl:testRoot,skipLibCheck:false,paths:{
      '@motionswift/remotion':['../js/remotion-shim/index.d.ts'],
      '@motionswift/remotion/jsx-runtime':['../js/remotion-shim/jsx-runtime.d.ts'],
      'remotion':['../js/remotion-shim/index.d.ts'],
      'react':['node_modules/@types/react/index.d.ts'],
      'react/jsx-runtime':['node_modules/@types/react/jsx-runtime.d.ts'],
    }};
  const program=ts.createProgram([file],options);
  return ts.getPreEmitDiagnostics(program);
}
test('supported TSX and all visual fixtures type check against the subset',()=>{
  for(const file of [path.join(testRoot,'type-fixtures/valid/core.tsx'),path.join(testRoot,'compositions/src/index.ts'),path.join(testRoot,'compiler-fixtures/svg-image/input.tsx')]) {
    const diagnostics=check(file);
    assert.equal(diagnostics.length,0,ts.formatDiagnosticsWithColorAndContext(diagnostics,{getCanonicalFileName:x=>x,getCurrentDirectory:()=>root,getNewLine:()=> '\n'}));
  }
});
for(const [file,diagnostic] of [['grid.tsx',2322],['iframe.tsx',2305],['canvas.tsx',[2339,2786]]])test(`types reject ${file}`,()=>{
  const diagnostics=check(path.join(testRoot,'type-fixtures/invalid',file));
  assert(diagnostics.length>0 && diagnostics.every(item=>(Array.isArray(diagnostic)?diagnostic:[diagnostic]).includes(item.code)),JSON.stringify(diagnostics.map(item=>item.code)));
});
