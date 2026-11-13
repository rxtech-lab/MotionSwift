const path = require('node:path');
const {createRequire} = require('node:module');
const deps=createRequire(path.resolve(__dirname,'../../tests/package.json'));
const ts=deps('typescript');
const root=path.resolve(__dirname,'../..');
const testRoot=path.join(root,'tests');
function check(project,entry) {
  const options={target:ts.ScriptTarget.ES2022,module:ts.ModuleKind.ESNext,moduleResolution:ts.ModuleResolutionKind.Bundler,
    jsx:ts.JsxEmit.ReactJSX,jsxImportSource:'@motionswift/remotion',strict:true,noEmit:true,isolatedModules:true,types:['react'],typeRoots:[path.join(testRoot,'node_modules/@types')],
    esModuleInterop:true,skipLibCheck:false,baseUrl:testRoot,paths:{
      '@remotion/paths':['../js/remotion-shim/remotion-paths.d.ts'],
      '@remotion/shapes':['../js/remotion-shim/remotion-shapes.d.ts'],
      '@remotion/transitions':['../js/remotion-shim/transitions.d.ts'],
      '@remotion/transitions/fade':['../js/remotion-shim/transition-fade.d.ts'],
      '@remotion/transitions/slide':['../js/remotion-shim/transition-slide.d.ts'],
      '@remotion/transitions/wipe':['../js/remotion-shim/transition-wipe.d.ts'],
      '@motionswift/remotion':['../js/remotion-shim/index.d.ts'],
      '@motionswift/remotion/jsx-runtime':['../js/remotion-shim/jsx-runtime.d.ts'],
      remotion:['../js/remotion-shim/index.d.ts'],three:['../js/remotion-shim/three.d.ts'],
      'three/addons/loaders/USDLoader.js':['../js/remotion-shim/usd-loader.d.ts'],'three/examples/jsm/loaders/USDLoader.js':['../js/remotion-shim/usd-loader.d.ts'],
      'three/addons/loaders/USDZLoader.js':['../js/remotion-shim/usd-loader.d.ts'],'three/examples/jsm/loaders/USDZLoader.js':['../js/remotion-shim/usd-loader.d.ts'],
      '@react-three/fiber':['../js/remotion-shim/fiber.d.ts'],'@remotion/three':['../js/remotion-shim/remotion-three.d.ts'],react:['node_modules/@types/react/index.d.ts'],
      'react/jsx-runtime':['node_modules/@types/react/jsx-runtime.d.ts'],
    }};
  const program=ts.createProgram([path.resolve(project,entry)],options);
  return ts.getPreEmitDiagnostics(program).map(diagnostic=>{
    const position=diagnostic.file?.getLineAndCharacterOfPosition(diagnostic.start||0);
    return {rule:`ts/${diagnostic.code}`,file:diagnostic.file?.fileName||entry,line:(position?.line||0)+1,
      col:(position?.character||0)+1,message:ts.flattenDiagnosticMessageText(diagnostic.messageText,'\n')};
  });
}
module.exports={check};
if(require.main===module)process.stdout.write(JSON.stringify(check(...process.argv.slice(2))));
