import path from 'node:path';
import fs from 'node:fs';
import {fileURLToPath} from 'node:url';
import {spawnSync} from 'node:child_process';

export const testRoot = fileURLToPath(new URL('..', import.meta.url));
export const root = path.dirname(testRoot);
export const manifest = JSON.parse(fs.readFileSync(path.join(testRoot, 'fixtures.json')));
export const project = path.resolve(testRoot, manifest.project);
if(!Array.isArray(manifest.fixtures)||!manifest.fixtures.length)throw Error('No visual fixtures');
const ids=new Set();
for(const fixture of manifest.fixtures) {
  if(typeof fixture.id!=='string'||! /^[\w/-]+$/.test(fixture.id)||fixture.id.includes('..')||ids.has(fixture.id))throw Error('Invalid/duplicate fixture ID');
  if(typeof fixture.composition!=='string'||!fixture.composition)throw Error('Missing composition ID');
  if(!Array.isArray(fixture.frames)||!fixture.frames.length||fixture.frames.some(frame=>!Number.isInteger(frame)||frame<0)
      ||new Set(fixture.frames).size!==fixture.frames.length)throw Error('Invalid/duplicate fixture frames');
  ids.add(fixture.id);
}

export function nativeBin() {
  const candidates = [process.env.MOTIONSWIFT_BIN, path.join(root,'.build/release/motionswift'), path.join(root,'.build/debug/motionswift')].filter(Boolean);
  const file=candidates.find(file=>fs.existsSync(file));
  if(!file)throw Error('Build motionswift first: make build');
  return file;
}
export function run(command,args,options={}) {
  const result=spawnSync(command,args,{cwd:root,encoding:'utf8',maxBuffer:64*1024*1024,...options});
  if(result.error || result.status!==0)throw Error(`${command} ${args.join(' ')}\n${result.error||result.stderr||result.stdout||'process failed'}`);
  return result.stdout;
}
export function nativeArgs(command,fixture,output,extra=[]) {
  return [command,'--project',project,'--entry',manifest.entryPoint,fixture.composition,output,...extra];
}
export function outputPath(base, fixture, frame) {
  return path.join(base,fixture.id,`${frame}.png`);
}
export function readJSON(file) { return JSON.parse(fs.readFileSync(file,'utf8')); }
export function writeJSON(file, data) {
  fs.mkdirSync(path.dirname(file),{recursive:true}); fs.writeFileSync(file,JSON.stringify(data,null,2)+'\n');
}
export function parseOptions(argv, allowed) {
  const options={};
  for(let i=0;i<argv.length;i++) {
    const [key,inline]=argv[i].replace(/^--/,'').split('=',2);
    if(!argv[i].startsWith('--') || !allowed.includes(key) || options[key]!==undefined)throw Error(`Unknown/repeated argument: ${argv[i]}`);
    const value=inline ?? argv[++i];
    if(!value || value.startsWith('--'))throw Error(`Missing value for --${key}`);
    options[key]=value;
  }
  return options;
}
