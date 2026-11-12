import {spawn,spawnSync} from 'node:child_process';

export const memoryMethod={metric:'sampled-process-tree-rss',unit:'bytes',intervalMs:100};

// Sum one snapshot, rather than adding independent per-process high-water marks.
export function treeRss(snapshot,rootPid) {
  const rows=snapshot.trim().split('\n').map(line=>line.trim().split(/\s+/).map(Number))
    .filter(row=>row.length===3&&row.every(Number.isFinite));
  const included=new Set([rootPid]);
  let changed=true;
  while(changed) {
    changed=false;
    for(const [pid,ppid] of rows)if(included.has(ppid)&&!included.has(pid)) {
      included.add(pid);changed=true;
    }
  }
  const members=rows.filter(([pid])=>included.has(pid));
  return {rssBytes:members.reduce((sum,[,,rss])=>sum+rss*1024,0),processes:members.length};
}

export function measureProcess(bin,args,options) {
  return new Promise(resolve=>{
    const child=spawn(bin,args,{...options,stdio:['ignore','pipe','pipe']});
    let stdout='',stderr='',error=null,peak=0,samples=0,peakProcesses=0,samplingError=null;
    child.stdout.on('data',data=>{stdout+=data;});
    child.stderr.on('data',data=>{stderr+=data;});
    const sample=()=>{
      if(!child.pid||samplingError)return;
      const result=spawnSync('/bin/ps',['-axo','pid=,ppid=,rss='],{encoding:'utf8',maxBuffer:16*1024*1024,timeout:5000});
      if(result.error||result.status!==0) {
        samplingError=String(result.error||result.stderr||`ps exit ${result.status}`);return;
      }
      const current=treeRss(result.stdout,child.pid);
      if(current.processes) {
        samples++;peak=Math.max(peak,current.rssBytes);peakProcesses=Math.max(peakProcesses,current.processes);
      }
    };
    sample();
    const timer=setInterval(sample,memoryMethod.intervalMs);
    child.on('error',value=>{error=value;});
    child.on('close',(status,signal)=>{
      clearInterval(timer);
      resolve({stdout,stderr,error,status,signal,memory:{
        status:samplingError||!samples?'unavailable':'ok',
        peakRssBytes:samplingError||!samples?null:peak,samples,peakProcesses,
        ...(samplingError?{error:samplingError}:{})
      }});
    });
  });
}
