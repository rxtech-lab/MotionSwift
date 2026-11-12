import {assertProvenance,sha256} from './provenance.mjs';
import fs from 'node:fs';
import path from 'node:path';
import {compareFiles} from './compare.mjs';
import {manifest,testRoot,root,nativeBin,nativeArgs,outputPath,run,writeJSON} from './common.mjs';

// The same Remotion goldens and 0.3% allowance gate every Skia backend.
const backendArg=process.argv.slice(2).find(arg=>arg.startsWith('--backend='))?.slice('--backend='.length);
const backend=backendArg??process.env.MOTIONSWIFT_BACKEND??'cpu';
if(!['cpu','gpu'].includes(backend)||process.argv.slice(2).some(arg=>!arg.startsWith('--backend=')))throw Error('Usage: visual.mjs [--backend=cpu|gpu]');
const output=path.join(testRoot,'reports/visual',backend);
fs.mkdirSync(output,{recursive:true});
const results=[];
let failed=false;
try {
  if(manifest.maxDiffRatio!==0.003)throw Error('Visual allowance must be exactly 0.3%');
  const metadata=JSON.parse(fs.readFileSync(path.join(testRoot,'golden/metadata.json')));
  assertProvenance(metadata);
  const bin=nativeBin();
  for(const fixture of manifest.fixtures) {
    const props=path.join(output,fixture.id,'props.json');
    writeJSON(props,fixture.props||{});
    // Deliberately shuffled frames check that JS state does not depend on evaluation order.
    for(const frame of [...fixture.frames].sort((a,b)=>(a*17%31)-(b*17%31))) {
      const actual=outputPath(path.join(output,'actual'),fixture,frame);
      fs.mkdirSync(path.dirname(actual),{recursive:true});
      run(bin,nativeArgs('still',fixture,actual,[`--frame=${frame}`,`--props=${props}`,`--backend=${backend}`]));
      const expected=outputPath(path.join(testRoot,'golden/stills'),fixture,frame);
      const reference=metadata.frames.find(item=>item.id===fixture.id&&item.frame===frame);
      if(!reference||reference.sha256!==sha256(fs.readFileSync(expected)))throw Error('Golden hash mismatch: '+expected);
      const metrics=compareFiles(expected,actual,path.join(output,fixture.id,String(frame)),manifest.maxDiffRatio);
      const repeat=actual+'.repeat.png';
      run(bin,nativeArgs('still',fixture,repeat,[`--frame=${frame}`,`--props=${props}`,`--backend=${backend}`]));
      const deterministic=compareFiles(actual,repeat,null,0).pass;
      fs.unlinkSync(repeat);
      const result={id:fixture.id,composition:fixture.composition,frame,...metrics,deterministic};
      results.push(result); failed ||= !result.pass || !deterministic;
      console.log(`${result.pass && deterministic?'PASS':'FAIL'} [${backend}] ${fixture.id}@${frame}: ${(metrics.diffRatio*100).toFixed(4)}%`);
    }
  }
} catch(error) { failed=true; results.push({error:String(error)}); console.error(error); }
writeJSON(path.join(output,'results.json'),{backend,maxDiffRatio:0.003,pass:!failed,results});
const escape = value=>String(value).replaceAll('&','&amp;').replaceAll('<','&lt;').replaceAll('"','&quot;');
fs.writeFileSync(path.join(output,'index.html'),`<!doctype html><meta charset="utf-8"><title>MotionSwift pixel comparisons</title>
<style>body{background:#15181e;color:#eee;font:16px system-ui;margin:32px}section{margin-bottom:40px}img{width:320px;border:1px solid #555}figure{display:inline-block;margin:8px}figcaption{padding:4px}</style>
<h1>Visual tests (${backend}) — exact RGBA comparison, 0.3% allowance</h1>${results.map(result=>result.error?`<pre>${escape(result.error)}</pre>`:
  `<section><h2>${escape(result.id)} @ ${result.frame}: ${(result.diffRatio*100).toFixed(4)}% — ${result.pass && result.deterministic?'PASS':'FAIL'}</h2>${['expected','actual','diff'].map(name=>`<figure><img src="${escape(result.id)}/${result.frame}/${name}.png"><figcaption>${name}</figcaption></figure>`).join('')}</section>`).join('')}`);
process.exitCode=failed?1:0;
