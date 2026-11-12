import {readJSON,testRoot} from './common.mjs';
import fs from 'node:fs';
import path from 'node:path';
const base=path.join(testRoot,'reports/visual');
for(const backend of ['cpu','gpu']) {
  const file=path.join(base,backend,'results.json');
  if(!fs.existsSync(file))continue;
  const result=readJSON(file);
  console.log(`## Pixel comparisons (${backend}): ${result.pass?'PASS':'FAIL'}\n\nExact RGBA against Remotion goldens; at most 0.3% changed pixels.\n`);
  console.log('| Fixture | Frame | Changed pixels | Deterministic | Result |\n|---|---:|---:|---|---|');
  for(const row of result.results)console.log(row.error?`\nError: ${row.error}`:
    `| ${row.id} | ${row.frame} | ${(row.diffRatio*100).toFixed(4)}% | ${row.deterministic} | ${row.pass&&row.deterministic?'PASS':'FAIL'} |`);
  console.log('');
}
console.log('Side-by-side PNGs, diffs, and HTML: **visual-results** artifact.');
