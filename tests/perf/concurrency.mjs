import os from 'node:os';

// Use the same available-core limit as Remotion, including constrained runners.
export function concurrencyFor(engines,config,override,availableCores=os.availableParallelism?.()??os.cpus().length) {
  const raw=override!==undefined?Number(override):config.concurrency??1;
  const requested=Object.fromEntries(engines.map(engine=>[engine,typeof raw==='object'?(raw[engine]??raw.gpu):raw]));
  if(Object.values(requested).some(value=>!Number.isInteger(value)||value<1))throw Error('Invalid concurrency');
  return {requested,availableCores,effective:Object.fromEntries(Object.entries(requested).map(([engine,value])=>[engine,Math.min(value,availableCores)]))};
}
