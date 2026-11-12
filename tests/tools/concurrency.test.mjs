import {test} from 'node:test';
import assert from 'node:assert/strict';
import {concurrencyFor} from '../perf/concurrency.mjs';

test('benchmark caps every engine to constrained runner cores and preserves requested counts',()=>{
  const engines=['remotion','cpu','gpu','gpu-hw','gpu-shared'];
  const result=concurrencyFor(engines,{concurrency:8},undefined,5);
  assert.deepEqual(Object.values(result.effective),[5,5,5,5,5]);
  assert.deepEqual(Object.values(result.requested),[8,8,8,8,8]);
  assert.equal(result.availableCores,5);
});
test('benchmark preserves lower per-engine counts and validates overrides before capping',()=>{
  assert.deepEqual(concurrencyFor(['remotion','cpu','gpu'],{concurrency:{remotion:2,cpu:8,gpu:4}},undefined,5).effective,{remotion:2,cpu:5,gpu:4});
  assert.equal(concurrencyFor(['gpu'],{concurrency:8},'3',5).effective.gpu,3);
  for(const value of ['0','-1','1.5','oops'])assert.throws(()=>concurrencyFor(['gpu'],{},value,5),/Invalid concurrency/);
});
