import fs from 'node:fs';
import path from 'node:path';
import {pipeline} from 'node:stream/promises';
import {Transform,Readable} from 'node:stream';
import {fileURLToPath} from 'node:url';
import {spawnSync} from 'node:child_process';

const testRoot=fileURLToPath(new URL('..',import.meta.url));
export const browserLock=JSON.parse(fs.readFileSync(path.join(testRoot,'browser.lock.json')));
export async function browserOptions() {
  if(process.platform!=='darwin'||process.arch!=='arm64')throw Error('References currently require macOS ARM64');
  const cache=path.join(testRoot,'../.cache/chrome-for-testing',browserLock.version);
  const executable=path.join(cache,'chrome-mac-arm64/Google Chrome for Testing.app/Contents/MacOS/Google Chrome for Testing');
  if(!fs.existsSync(executable)) {
    const parent=path.dirname(cache);fs.mkdirSync(parent,{recursive:true});
    const temporary=fs.mkdtempSync(path.join(parent,'download-'));
    try {
      const url=`https://storage.googleapis.com/chrome-for-testing-public/${browserLock.version}/${browserLock.platform}/chrome-${browserLock.platform}.zip`;
      console.log(`Downloading pinned Chrome for Testing ${browserLock.version}`);
      const response=await fetch(url);
      if(!response.ok||!response.body)throw Error(`Chrome download: HTTP ${response.status}`);
      const total=Number(response.headers.get('content-length'));let transferred=0,last=-1;
      const progress=new Transform({transform(chunk,encoding,callback){
        transferred+=chunk.length;const step=Math.floor(transferred/total*10);
        if(step>last){last=step;console.log(`Chrome: ${(transferred/total*100).toFixed(0)}% (${transferred}/${total} bytes)`);}
        callback(null,chunk);
      }});
      const archive=path.join(temporary,'chrome.zip');
      await pipeline(Readable.fromWeb(response.body),progress,fs.createWriteStream(archive));
      const extract=spawnSync('/usr/bin/unzip',['-q',archive,'-d',temporary],{encoding:'utf8'});
      if(extract.status!==0)throw Error(`Unzip Chrome: ${extract.stderr}`);
      fs.unlinkSync(archive);
      // Each job downloads into a private directory; a completed concurrent cache is safe to reuse.
      if(!fs.existsSync(cache))fs.renameSync(temporary,cache);
    } finally {fs.rmSync(temporary,{recursive:true,force:true});}
  }
  const result=spawnSync(executable,['--version'],{encoding:'utf8'});
  if(result.status!==0||!result.stdout.includes(browserLock.version))throw Error('Pinned Chrome version verification failed');
  return {chromeMode:'chrome-for-testing',browserExecutable:executable};
}
