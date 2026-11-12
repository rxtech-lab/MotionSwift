import {test} from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import {root} from './common.mjs';

test('PR benchmark summary puts actual-project timings before synthetic results and retains failures',()=>{
  const out=fs.mkdtempSync(path.join(os.tmpdir(),'test-film-comment-'));
  try {
    fs.mkdirSync(path.join(out,'test-film'));
    fs.mkdirSync(path.join(out,'long'));
    fs.writeFileSync(path.join(out,'summary.md'),'<!-- motionswift-bench -->\n## Short\nSynthetic short table\n<details>large raw data</details>');
    fs.writeFileSync(path.join(out,'long/summary.md'),'<!-- motionswift-bench -->\n## Long\nSynthetic long table\n');
    fs.writeFileSync(path.join(out,'test-film/summary.md'),'<!-- motionswift-bench -->\n## Real\nReal project timing table\n❌ parity failed\n<details>large real raw data</details>');
    const result=spawnSync(process.execPath,[path.join(root,'tests/perf/combine-summaries.mjs'),out],{encoding:'utf8'});
    assert.equal(result.status,0,result.stderr);
    const summary=fs.readFileSync(path.join(out,'summary.md'),'utf8');
    assert.ok(summary.startsWith('<!-- motionswift-bench -->\n## Actual Test Film project'));
    assert.ok(summary.indexOf('Real project timing table') < summary.indexOf('Synthetic short table'));
    assert.ok(summary.includes('Synthetic long table'));
    assert.ok(summary.includes('❌ parity failed'));
    assert.ok(summary.includes('test-film/results.json'));
    assert.ok(!summary.includes('<details>'));
  } finally {fs.rmSync(out,{recursive:true,force:true});}
});
