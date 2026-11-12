import {test} from 'node:test';
import assert from 'node:assert/strict';
import {median,geometricMean,sameMachine,parityMetadata} from '../perf/metrics.mjs';
test('medians use both middle values and geometric mean weights ratios',()=>{
  assert.equal(median([3,1,9,5]),4); assert.equal(median([9,1,3]),3);
  assert.equal(geometricMean([0.5,2]),1);assert.equal(geometricMean([]),null);
  assert.throws(()=>median([NaN]));
});
test('baseline requires the same physical runner and hardware',()=>{
  const machine={platform:'darwin',cpu:'M2',cores:8,memoryGB:16,runner:'mac-1'};
  assert.equal(sameMachine(machine,{...machine}),true);
  assert.equal(sameMachine(machine,{...machine,runner:'mac-2'}),false);
});
test('SSIM cannot excuse missing frames or different dimensions',()=>{
  const metadata={codec_name:'h264',width:320,height:180,r_frame_rate:'30/1',nb_read_packets:'30'};
  assert.equal(parityMetadata(metadata,{...metadata}),true);
  assert.equal(parityMetadata(metadata,{...metadata,nb_read_packets:'29'}),false);
  assert.equal(parityMetadata(metadata,{...metadata,width:640}),false);
});
