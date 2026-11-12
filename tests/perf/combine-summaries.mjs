import fs from 'node:fs';
import path from 'node:path';

// Put both comparison tables before the large raw JSON so the PR comment truncation
// keeps the short-clip and sustained-throughput results. Full JSON stays in artifacts.
const out=path.resolve(process.argv[2]||'tests/reports/bench');
const files=[['30-frame clips','summary.md'],['300-frame clips','long/summary.md']];
const sections=files.filter(([,file])=>fs.existsSync(path.join(out,file))).map(([title,file])=>{
  const text=fs.readFileSync(path.join(out,file),'utf8').split('<details>')[0];
  return text.replace('<!-- motionswift-bench -->\n','').replace(/^## .*$/m,`## ${title}`);
});
if(!sections.length)throw Error('No benchmark summaries were produced');
fs.writeFileSync(path.join(out,'summary.md'),`<!-- motionswift-bench -->\n${sections.join('\n')}\nFull raw results: bench-results artifact (results.json and long/results.json).\n`);
