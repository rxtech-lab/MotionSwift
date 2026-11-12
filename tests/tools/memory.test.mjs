import {test} from 'node:test';
import assert from 'node:assert/strict';
import {measureProcess,treeRss} from '../perf/memory.mjs';

test('RSS snapshot includes descendants in any order and excludes unrelated processes',()=>{
  assert.deepEqual(treeRss('30 20 300\n99 1 900\n20 10 200\n10 1 100',10),
    {rssBytes:600*1024,processes:3});
  assert.deepEqual(treeRss('',10),{rssBytes:0,processes:0});
});

test('memory sampler observes a real child allocation and preserves output and exit status',async()=>{
  const script=`
    const {spawn}=require('node:child_process');
    const child=spawn(process.execPath,['-e',
      'const data=Buffer.alloc(64*1024*1024,1);setTimeout(()=>console.log(data.length),700)'],{stdio:'inherit'});
    child.on('exit',()=>process.exit(7));
  `;
  const result=await measureProcess(process.execPath,['-e',script],{});
  assert.equal(result.status,7);
  assert.match(result.stdout,/67108864/);
  assert.equal(result.memory.status,'ok',result.memory.error);
  assert.ok(result.memory.peakProcesses>=2);
  assert.ok(result.memory.peakRssBytes>64*1024*1024);
  assert.ok(result.memory.samples>=2);
});

test('failed spawn resolves with the original error',async()=>{
  const result=await measureProcess('/nonexistent-motionswift-memory-test',[],{});
  assert.equal(result.error.code,'ENOENT');
  assert.equal(result.memory.status,'unavailable');
});
