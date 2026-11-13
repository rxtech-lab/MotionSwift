import fs from 'node:fs';
import path from 'node:path';

// Put the real project first so comment truncation retains its timings.
// Full JSON stays in artifacts.
const out=path.resolve(process.argv[2]||'tests/reports/bench');
const files=[['Actual Test Film project','test-film/summary.md'],['30-frame clips','summary.md'],['300-frame clips','long/summary.md']];
const comments=[];
const sections=files.filter(([,file])=>fs.existsSync(path.join(out,file))).map(([title,file])=>{
  const text=fs.readFileSync(path.join(out,file),'utf8').split('<details>')[0];
  // Keep only render timings and failures in the PR; methodology and memory
  // measurements remain in the job summary and downloadable report.
  const lines=text.split('\n');
  const start=lines.findIndex(line=>line.startsWith('| Fixture | Size |'));
  const table=[];
  if(start>=0) {
    for(const line of lines.slice(start)) {
      if(!line.startsWith('|'))break;
      const cells=line.split('|').slice(1,-1).map(cell=>cell.trim());
      table.push(`| ${[0,2,3,4,5,6,10,11].map(index=>cells[index]).join(' | ')} |`);
    }
  }
  const failures=lines.filter(line=>/^(?:❌|Error:)/.test(line));
  const unavailable=lines.some(line=>line.startsWith('**Hardware encoding unavailable'));
  const compact=[...table,...failures,unavailable?'Hardware encoding unavailable.':''].filter(Boolean).join('\n');
  comments.push(title==='Actual Test Film project'
    ?`### Test Film\n\n${compact}`
    :`<details><summary>${title}</summary>\n\n${compact}\n\n</details>`);
  return text.replace('<!-- motionswift-bench -->\n','').replace(/^## .*$/m,`## ${title}`);
});
if(!sections.length)throw Error('No benchmark summaries were produced');
fs.writeFileSync(path.join(out,'summary.md'),`<!-- motionswift-bench -->\n${sections.join('\n')}\nFull raw results: bench-results artifact (test-film/results.json, results.json, and long/results.json).\n`);
fs.writeFileSync(path.join(out,'comment.md'),`<!-- motionswift-bench -->\n## Benchmark\n\n${comments.join('\n\n')}\n\nTimes include startup and encoding. SSIM: CPU / GPU / HW / Shared; — = unavailable. Full report: **bench-results** artifact.\n`);
