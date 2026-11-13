// Runtime-only microbenchmark: compiler work, layout, raster and encoding are excluded.
import {spawnSync} from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const output = path.resolve(root, 'bench-results/runtime');
fs.mkdirSync(output, {recursive: true});
const run = spawnSync('swift', ['test', ...process.argv.slice(2), '--filter', 'retainedRuntimeBenchmark'], {
  cwd: root, env: {...process.env, MOTIONSWIFT_RUNTIME_BENCHMARK: '1'}, encoding: 'utf8', maxBuffer: 16 * 1024 * 1024,
});
fs.writeFileSync(path.join(output, 'run.log'), (run.stdout || '') + (run.stderr || ''));
if (run.status !== 0) { process.stderr.write(run.stderr || run.stdout || String(run.error)); process.exit(run.status || 1); }
const match = run.stdout.match(/RUNTIME_BENCHMARK frames=(\d+) retained_ms=([\d.]+) fresh_ms=([\d.]+) speedup=([\d.]+) mutations=(\d+)/);
if (!match) throw Error('Swift test produced no runtime benchmark record; see bench-results/runtime/run.log');
const [,frames,retained,fresh,speedup,mutations] = match.map(Number);
const report = {frames, retainedMs: retained, freshWorkerMs: fresh, speedup, mutations,
  platform: process.platform, arch: process.arch, measuredAt: new Date().toISOString(),
  scope: 'Same current runtime: one retained worker versus a new worker per sample; not a historical end-to-end baseline.'};
fs.writeFileSync(path.join(output, 'results.json'), JSON.stringify(report, null, 2) + '\n');
const summary = `Runtime evaluation (${frames} frames): retained ${retained.toFixed(2)} ms; fresh workers ${fresh.toFixed(2)} ms; ${speedup.toFixed(2)}×; ${mutations} mutations.\n`;
fs.writeFileSync(path.join(output, 'summary.md'), summary + '\n' + report.scope + '\n');
console.log(summary);
