import fs from 'node:fs';
import path from 'node:path';

// Put the real project first so comment truncation retains its timings.
// Full JSON stays in artifacts.
const out=path.resolve(process.argv[2]||'tests/reports/bench');
const files=[['Actual Test Film project','test-film/summary.md'],['30-frame clips','summary.md'],['300-frame clips','long/summary.md']];
const sections=files.filter(([,file])=>fs.existsSync(path.join(out,file))).map(([title,file])=>{
  const text=fs.readFileSync(path.join(out,file),'utf8').split('<details>')[0];
  return text.replace('<!-- motionswift-bench -->\n','').replace(/^## .*$/m,`## ${title}`);
});
if(!sections.length)throw Error('No benchmark summaries were produced');
fs.writeFileSync(path.join(out,'summary.md'),`<!-- motionswift-bench -->\n${sections.join('\n')}\nFull raw results: bench-results artifact (test-film/results.json, results.json, and long/results.json).\n`);
