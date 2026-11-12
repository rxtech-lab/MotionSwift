import {readJSON,testRoot} from './common.mjs';
import path from 'node:path';
const result=readJSON(path.join(testRoot,'reports/visual/results.json'));
console.log(`## Pixel comparisons: ${result.pass?'PASS':'FAIL'}\n\nExact RGBA; at most 0.3% changed pixels.\n`);
console.log('| Fixture | Frame | Changed pixels | Deterministic | Result |\n|---|---:|---:|---|---|');
for(const row of result.results)console.log(row.error?`\nError: ${row.error}`:
  `| ${row.id} | ${row.frame} | ${(row.diffRatio*100).toFixed(4)}% | ${row.deterministic} | ${row.pass&&row.deterministic?'PASS':'FAIL'} |`);
console.log('\nSide-by-side PNGs, diffs, and HTML: **visual-results** artifact.');
