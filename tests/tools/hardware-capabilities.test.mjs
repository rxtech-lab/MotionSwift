import {test} from 'node:test';
import assert from 'node:assert/strict';
import {probeHardwareEncoding} from './hardware-capabilities.mjs';

test('hardware availability requires a successful encode and never permits software fallback',()=>{
  const supported=probeHardwareEncoding((bin,args)=>{
    assert.equal(bin,'ffmpeg');
    assert.equal(args[args.indexOf('-allow_sw')+1],'0');
    return {status:0};
  });
  assert.equal(supported.available,true);
  assert.equal(probeHardwareEncoding(()=>({status:187,stderr:'Cannot create compression session: -12903'})).available,false);
});

test('probe errors and invalid encoder settings must fail rather than skip coverage',()=>{
  for(const result of [
    {error:Error('ENOENT')},
    {status:null,signal:'SIGTERM'},
    {status:1,stderr:'Unknown encoder h264_videotoolbox'},
    {status:1,stderr:'Cannot create compression session: -12902'},
  ])assert.throws(()=>probeHardwareEncoding(()=>result));
});
